#!/usr/bin/env python3
"""TCP bridge between MATLAB and a camera: the built-in laptop webcam via
OpenCV (Windows/macOS, run natively), libgphoto2 (DSLR inside WSL), or
FakeCamera for testing.

Protocol (ASCII line requests, newline-terminated):
  PING                -> OK pong
  STATUS              -> OK <ready|disconnected> <model>
  PREVIEW             -> OK <w> <h> <nbytes>\n + raw RGB uint8 (HWC)
  CAPTURE <path>      -> OK <path>
  QUIT                -> OK bye
"""
import argparse
import io
import os
import socketserver
import struct
import sys
import threading
import time
import zlib


def _make_png_bytes(width, height, rgb_bytes):
    """Build a valid 24-bit RGB PNG in pure stdlib so imread() always recognizes it."""
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw.extend(rgb_bytes[y * stride : (y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw)))
        + chunk(b"IEND", b"")
    )


class FakeCamera:
    """In-memory camera adapter for unit/integration tests without hardware."""

    def __init__(self, width=64, height=48, sample_path=None):
        self.width = width
        self.height = height
        self.sample_path = sample_path
        self.model = "FakeNikonZ6II"
        self.connected = True
        self.reconnects = 0
        self.frame_index = 0

    def connect(self):
        self.connected = True

    def close(self):
        self.connected = False

    def reconnect(self):
        self.reconnects += 1
        self.close()
        self.connect()

    def preview(self):
        self.frame_index = (self.frame_index + 1) % 256
        w, h = self.width, self.height
        buf = bytearray(w * h * 3)
        idx = 0
        for y in range(h):
            for x in range(w):
                buf[idx] = (200 + self.frame_index) % 256
                buf[idx + 1] = (150 + x) % 256
                buf[idx + 2] = (120 + y) % 256
                idx += 3
        return w, h, bytes(buf)

    def capture(self, dest_path):
        folder = os.path.dirname(dest_path)
        if folder:
            os.makedirs(folder, exist_ok=True)
        if self.sample_path and os.path.isfile(self.sample_path):
            with open(self.sample_path, "rb") as src, open(dest_path, "wb") as dst:
                dst.write(src.read())
            return dest_path
        w, h, rgb = self.preview()
        try:
            from PIL import Image
            img = Image.frombytes("RGB", (w, h), rgb)
            img.save(dest_path, format="JPEG", quality=92)
        except Exception:
            with open(dest_path, "wb") as f:
                f.write(_make_png_bytes(w, h, rgb))
        return dest_path


class GPhotoCameraAdapter:
    """Real libgphoto2 adapter for Nikon Z6II in WSL."""

    def __init__(self, preview_width=960):
        self.preview_width = preview_width
        self.camera = None
        self.model = "NikonZ6II"
        self.connected = False
        self.connect()

    def connect(self):
        import gphoto2 as gp
        self.gp = gp
        self.camera = gp.Camera()
        self.camera.init()
        try:
            summary = str(self.camera.get_summary())
            for line in summary.splitlines():
                if line.lower().startswith("model:"):
                    self.model = line.split(":", 1)[1].strip().replace(" ", "_")
                    break
        except Exception:
            pass
        self.connected = True

    def close(self):
        self.connected = False
        if self.camera is not None:
            try:
                self.camera.exit()
            except Exception:
                pass
            self.camera = None

    def reconnect(self):
        self.close()
        self.connect()

    def preview(self):
        from PIL import Image
        if not self.connected or self.camera is None:
            self.connect()
        cam_file = self.camera.capture_preview()
        file_data = cam_file.get_data_and_size()
        img = Image.open(io.BytesIO(memoryview(file_data))).convert("RGB")
        if img.width > self.preview_width:
            new_h = max(1, round(img.height * (self.preview_width / img.width)))
            img = img.resize((self.preview_width, new_h), Image.BILINEAR)
        return img.width, img.height, img.tobytes()

    def capture(self, dest_path):
        if not self.connected or self.camera is None:
            self.connect()
        folder = os.path.dirname(dest_path)
        if folder:
            os.makedirs(folder, exist_ok=True)
        file_path = self.camera.capture(self.gp.GP_CAPTURE_IMAGE)
        cam_file = self.camera.file_get(
            file_path.folder, file_path.name, self.gp.GP_FILE_TYPE_NORMAL
        )
        cam_file.save(dest_path)
        return dest_path


class WebcamAdapter:
    """Built-in laptop (or USB) webcam through OpenCV.

    Windows uses DirectShow (then Media Foundation), macOS AVFoundation. A
    background thread keeps reading so PREVIEW/CAPTURE always get the newest
    frame instead of a stale one sitting in the driver's buffer.
    """

    STALE_SECONDS = 2.0

    def __init__(self, device=0, width=1280, height=720, preview_width=960,
                 capture_factory=None, open_timeout=8.0):
        self.device = device
        self.req_width = width
        self.req_height = height
        self.preview_width = preview_width
        self.open_timeout = open_timeout
        self._factory = capture_factory or self._open_cv
        self.model = f"Webcam{device}"
        self.connected = False
        self._cap = None
        self._fresh = threading.Condition()
        self._frame = None
        self._seq = 0
        self._last_ok = 0.0
        self._stop = threading.Event()
        self._thread = None
        self.connect()

    def _open_cv(self):
        import cv2
        if sys.platform.startswith("win"):
            backends = [cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY]
        elif sys.platform == "darwin":
            backends = [cv2.CAP_AVFOUNDATION, cv2.CAP_ANY]
        else:
            backends = [cv2.CAP_V4L2, cv2.CAP_ANY]
        modes = []
        for mode in [(self.req_width, self.req_height), (1280, 720), (640, 480)]:
            if mode not in modes:
                modes.append(mode)
        for backend in backends:
            # Some drivers accept any size but then stall at ~1 fps outside their
            # native modes, so keep the first size that actually streams. The
            # device is reopened per size: resizing a stalled capture stays stalled.
            for w, h in modes:
                cap = cv2.VideoCapture(self.device, backend)
                if not cap.isOpened():
                    cap.release()
                    break
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
                if self._streams(cap):
                    return cap
                cap.release()
        if sys.platform == "darwin":
            hint = " (allow camera access for MATLAB in System Settings > Privacy & Security > Camera)"
        else:
            hint = " (not found, or in use by another app)"
        raise RuntimeError(f"cannot open webcam {self.device}{hint}")

    @staticmethod
    def _streams(cap, max_interval=0.3):
        """True when, after a warm-up read, two reads each arrive quickly."""
        ok, _ = cap.read()
        if not ok:
            return False
        for _ in range(2):
            t0 = time.monotonic()
            ok, _ = cap.read()
            if not ok or time.monotonic() - t0 > max_interval:
                return False
        return True

    def connect(self):
        self.close()
        cap = self._factory()
        t0 = time.monotonic()
        frame = None
        while time.monotonic() - t0 < self.open_timeout:
            ok, frame = cap.read()
            if ok and frame is not None:
                break
            frame = None
            time.sleep(0.05)
        if frame is None:
            cap.release()
            raise RuntimeError(f"webcam {self.device} opened but delivered no frames")
        self._cap = cap
        with self._fresh:
            self._frame = frame
            self._seq += 1
            self._last_ok = time.monotonic()
        self._stop.clear()
        self._thread = threading.Thread(target=self._reader, args=(cap,), daemon=True)
        self._thread.start()
        self.connected = True

    def _reader(self, cap):
        while not self._stop.is_set():
            try:
                ok, frame = cap.read()
            except Exception:
                ok, frame = False, None
            if ok and frame is not None:
                with self._fresh:
                    self._frame = frame
                    self._seq += 1
                    self._last_ok = time.monotonic()
                    self._fresh.notify_all()
            else:
                time.sleep(0.02)

    def close(self):
        self.connected = False
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None
        if self._cap is not None:
            try:
                self._cap.release()
            except Exception:
                pass
            self._cap = None

    def reconnect(self):
        self.connect()

    def _latest(self, fresh=False):
        """Newest BGR frame; with fresh=True, one read after this call."""
        if not self.connected:
            self.connect()
        with self._fresh:
            if fresh:
                target = self._seq + 1
                self._fresh.wait_for(lambda: self._seq >= target, timeout=1.0)
            if time.monotonic() - self._last_ok > self.STALE_SECONDS:
                raise RuntimeError("webcam stopped delivering frames")
            return self._frame

    def preview(self):
        import cv2
        frame = self._latest()
        h, w = frame.shape[:2]
        if w > self.preview_width:
            new_h = max(1, round(h * self.preview_width / w))
            frame = cv2.resize(frame, (self.preview_width, new_h), interpolation=cv2.INTER_AREA)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        return rgb.shape[1], rgb.shape[0], rgb.tobytes()

    def capture(self, dest_path):
        import cv2
        frame = self._latest(fresh=True)
        folder = os.path.dirname(dest_path)
        if folder:
            os.makedirs(folder, exist_ok=True)
        ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
        if not ok:
            raise RuntimeError("JPEG encoding failed")
        # Written by Python, not cv2.imwrite, so non-ASCII paths work on Windows.
        with open(dest_path, "wb") as f:
            f.write(buf.tobytes())
        return dest_path


class BridgeHandler(socketserver.StreamRequestHandler):
    def _run_with_retry(self, fn):
        last_err = None
        for _ in range(3):
            try:
                return fn()
            except Exception as exc:
                last_err = exc
                try:
                    self.server.camera.reconnect()
                except Exception:
                    pass
        raise RuntimeError(str(last_err))

    def handle(self):
        cam = self.server.camera
        while True:
            try:
                raw_line = self.rfile.readline()
            except (ConnectionResetError, BrokenPipeError, OSError):
                break
            if not raw_line:
                break
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            parts = line.split(" ", 1)
            cmd = parts[0].upper()
            arg = parts[1].strip() if len(parts) > 1 else ""
            try:
                if cmd == "PING":
                    self.wfile.write(b"OK pong\n")
                elif cmd == "STATUS":
                    state = "ready" if getattr(cam, "connected", False) else "disconnected"
                    self.wfile.write(f"OK {state} {cam.model}\n".encode("ascii"))
                elif cmd == "PREVIEW":
                    w, h, payload = self._run_with_retry(cam.preview)
                    header = f"OK {w} {h} {len(payload)}\n".encode("ascii")
                    self.wfile.write(header)
                    self.wfile.write(payload)
                elif cmd == "CAPTURE":
                    if not arg:
                        self.wfile.write(b"ERR missing capture path\n")
                    else:
                        out = self._run_with_retry(lambda: cam.capture(arg))
                        self.wfile.write(f"OK {out}\n".encode("utf-8"))
                elif cmd == "QUIT":
                    self.wfile.write(b"OK bye\n")
                    self.wfile.flush()
                    self.server._BaseServer__shutdown_request = True
                    break
                else:
                    self.wfile.write(f"ERR unknown command {cmd}\n".encode("ascii"))
            except Exception as exc:
                msg = str(exc).replace("\n", " ")
                self.wfile.write(f"ERR {msg}\n".encode("utf-8"))
            try:
                self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError, OSError):
                break


class BridgeServer(socketserver.TCPServer):
    allow_reuse_address = True

    def __init__(self, server_address, camera):
        self.camera = camera
        super().__init__(server_address, BridgeHandler)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Photobooth camera TCP bridge")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5555)
    parser.add_argument("--fake", action="store_true", help="Use FakeCamera instead of gphoto2")
    parser.add_argument("--sample-jpg", default=None, help="Optional JPEG file for FakeCamera.capture")
    parser.add_argument("--webcam", action="store_true", help="Use the built-in webcam via OpenCV")
    parser.add_argument("--device", type=int, default=0, help="Webcam index (0 = built-in)")
    parser.add_argument("--width", type=int, default=1280, help="Requested webcam width")
    parser.add_argument("--height", type=int, default=720, help="Requested webcam height")
    args = parser.parse_args(argv)

    try:
        if args.fake:
            cam = FakeCamera(sample_path=args.sample_jpg)
        elif args.webcam:
            cam = WebcamAdapter(device=args.device, width=args.width, height=args.height)
        else:
            cam = GPhotoCameraAdapter()
    except Exception as exc:
        print(f"BRIDGE_CAMERA_ERROR {exc}", flush=True)
        return 2
    try:
        with BridgeServer((args.host, args.port), cam) as srv:
            print(f"BRIDGE_LISTENING {args.host}:{srv.server_address[1]} {cam.model}", flush=True)
            srv.serve_forever()
    finally:
        cam.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
