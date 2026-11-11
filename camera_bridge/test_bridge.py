import os
import socket
import tempfile
import threading
import time
import unittest
from camera_bridge import bridge


class FlakyCamera(bridge.FakeCamera):
    def __init__(self, fail_times=0):
        super().__init__()
        self.fail_times = fail_times
        self.calls = 0

    def preview(self):
        self.calls += 1
        if self.calls <= self.fail_times:
            raise RuntimeError("USB PTP timeout")
        return super().preview()


class BridgeProtocolTests(unittest.TestCase):
    def start_server(self, cam):
        srv = bridge.BridgeServer(("127.0.0.1", 0), cam)
        port = srv.server_address[1]
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        self.addCleanup(srv.server_close)  # cleanups run LIFO: shutdown first
        self.addCleanup(srv.shutdown)
        return port

    def send_cmd(self, sock, line):
        sock.sendall((line + "\n").encode("ascii"))
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = sock.recv(1)
            if not chunk:
                break
            buf += chunk
        return buf.decode("ascii").strip()

    def test_ping_status_preview_capture(self):
        port = self.start_server(bridge.FakeCamera(width=32, height=24))
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            self.assertEqual(self.send_cmd(s, "PING"), "OK pong")
            self.assertEqual(self.send_cmd(s, "STATUS"), "OK ready FakeNikonZ6II")

            hdr = self.send_cmd(s, "PREVIEW")
            parts = hdr.split()
            self.assertEqual(parts[:3], ["OK", "32", "24"])
            nbytes = int(parts[3])
            self.assertEqual(nbytes, 32 * 24 * 3)
            data = b""
            while len(data) < nbytes:
                data += s.recv(nbytes - len(data))
            self.assertEqual(len(data), nbytes)

            with tempfile.TemporaryDirectory() as d:
                out_path = os.path.join(d, "shot.jpg")
                resp = self.send_cmd(s, f"CAPTURE {out_path}")
                self.assertEqual(resp, f"OK {out_path}")
                self.assertTrue(os.path.isfile(out_path))
                self.assertGreater(os.path.getsize(out_path), 50)

    def test_reconnects_up_to_three_times(self):
        cam = FlakyCamera(fail_times=2)
        port = self.start_server(cam)
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            hdr = self.send_cmd(s, "PREVIEW")
            self.assertTrue(hdr.startswith("OK "))
            self.assertGreaterEqual(cam.reconnects, 2)

    def test_returns_err_after_three_failures(self):
        cam = FlakyCamera(fail_times=5)
        port = self.start_server(cam)
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            hdr = self.send_cmd(s, "PREVIEW")
            self.assertTrue(hdr.startswith("ERR "))


try:
    import cv2  # noqa: F401
    import numpy as np
    HAVE_CV2 = True
except ImportError:
    HAVE_CV2 = False


class FakeVideoCapture:
    """Stands in for cv2.VideoCapture: numbered BGR frames, optional dropouts."""

    def __init__(self, width=1280, height=720, dead_after=None):
        self.width, self.height = width, height
        self.dead_after = dead_after
        self.reads = 0
        self.released = False

    def read(self):
        self.reads += 1
        if self.released or (self.dead_after is not None and self.reads > self.dead_after):
            return False, None
        frame = np.zeros((self.height, self.width, 3), dtype=np.uint8)
        frame[:, :, 0] = 10           # B
        frame[:, :, 2] = 200          # R
        frame[0, 0, 1] = self.reads % 256
        time.sleep(0.005)
        return True, frame

    def release(self):
        self.released = True


@unittest.skipUnless(HAVE_CV2, "OpenCV not installed")
class WebcamAdapterTests(unittest.TestCase):
    def make(self, **kw):
        caps = []

        def factory():
            caps.append(FakeVideoCapture(**kw))
            return caps[-1]

        cam = bridge.WebcamAdapter(capture_factory=factory, preview_width=640)
        self.addCleanup(cam.close)
        return cam, caps

    def test_preview_is_downscaled_rgb(self):
        cam, _ = self.make()
        w, h, payload = cam.preview()
        self.assertEqual((w, h), (640, 360))
        self.assertEqual(len(payload), 640 * 360 * 3)
        rgb = np.frombuffer(payload, dtype=np.uint8).reshape(h, w, 3)
        self.assertEqual(int(rgb[100, 100, 0]), 200)  # red channel first
        self.assertEqual(int(rgb[100, 100, 2]), 10)

    def test_capture_writes_full_res_jpeg_to_non_ascii_path(self):
        cam, _ = self.make()
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "ภาพ", "shot.jpg")
            self.assertEqual(cam.capture(out), out)
            with open(out, "rb") as f:
                data = np.frombuffer(f.read(), dtype=np.uint8)
            img = cv2.imdecode(data, cv2.IMREAD_COLOR)
            self.assertEqual(img.shape, (720, 1280, 3))

    def test_close_releases_device(self):
        cam, caps = self.make()
        cam.close()
        self.assertTrue(caps[-1].released)
        self.assertFalse(cam.connected)

    def test_stale_feed_raises_then_reconnect_recovers(self):
        cam, caps = self.make(dead_after=3)
        cam.STALE_SECONDS = 0.2
        time.sleep(0.4)
        with self.assertRaises(RuntimeError):
            cam.preview()
        caps[-1].dead_after = None  # not used again; reconnect opens a new device
        cam.reconnect()
        self.assertEqual(len(caps), 2)
        self.assertTrue(caps[0].released)

    def test_bridge_serves_webcam(self):
        cam, _ = self.make()
        srv = bridge.BridgeServer(("127.0.0.1", 0), cam)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            s.sendall(b"STATUS\n")
            self.assertEqual(s.makefile("rb").readline().strip(), b"OK ready Webcam0")


if __name__ == "__main__":
    unittest.main()
