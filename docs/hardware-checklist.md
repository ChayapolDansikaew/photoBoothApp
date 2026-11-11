# Camera Setup & Demo Checklist

The camera is chosen by `"camera"` in `config.json`:

| Value      | Camera                                           | Platforms        |
|------------|--------------------------------------------------|------------------|
| `"webcam"` | The laptop's built-in webcam (default)           | Windows, macOS   |
| `"gphoto"` | Nikon Z6II over USB through gphoto2 in WSL2      | Windows only     |
| `"mock"`   | Sample images in `assets/mock/` (no hardware)    | any              |

# Built-in Webcam (default)

MATLAB runs `camera_bridge/bridge.py --webcam` natively with Python + OpenCV
(DirectShow on Windows, AVFoundation on macOS). No MATLAB add-on is needed.

## One-Time Setup
1. Install Python 3 (python.org, or `brew install python` on macOS).
2. Install the webcam dependencies from the repo root:
   ```bash
   python -m pip install -r camera_bridge/requirements-webcam.txt
   ```
   (on macOS use `python3 -m pip ...`).
3. **macOS only:** the first start asks whether MATLAB may use the camera. Allow it,
   or turn MATLAB on later in System Settings → Privacy & Security → Camera, then
   press **Ctrl+Shift+R** in the app to reconnect.
4. **Windows only:** Settings → Privacy & security → Camera → turn on
   "Let desktop apps access your camera".

The app finds a Python that can `import cv2` on its own. If it picks the wrong
one, set `"pythonExe"` in `config.json` to its full path.

## Options (`config.json`)
- `"webcamIndex"`: `0` is the built-in camera; use `1`, `2`, … for an external USB webcam.
- `"webcamResolution"`: requested size, default `[1280, 720]`. A 1080p webcam can use
  `[1920, 1080]`. If the camera can't stream at that size, the bridge falls back to
  1280×720, then 640×480.

## Before Every Session
1. Open the laptop's privacy shutter / turn the camera key on. A closed shutter gives
   **all-black** photos with no error.
2. Close other apps using the camera (Teams, Zoom, Camera app).
3. In MATLAB run `startPhotobooth` and check that the live preview shows your face.
4. If the camera banner appears, check `logs/bridge.log` (the last `BRIDGE_` line
   says why), fix it, then press **Ctrl+Shift+R**.

# Nikon Z6II (DSLR, `"camera": "gphoto"`)

## 1. One-Time Setup (Windows + WSL2)
1. Install `usbipd-win` on Windows (Admin PowerShell):
   ```powershell
   winget install --exact dorssel.usbipd-win
   ```
2. Inside WSL (Ubuntu), install `gphoto2` and Python dependencies:
   ```bash
   sudo apt update
   sudo apt install -y gphoto2 libgphoto2-dev python3-pip python3-pil python3-numpy
   pip3 install --break-system-packages gphoto2
   ```

## 2. Camera Settings (Nikon Z6II)
- **Image Quality:** JPEG Fine, Size L (or M for faster transfer).
- **Focus Mode:** `AF-S` with Auto-area AF (Face/Eye detection ON).
- **Power Saving:** Setup Menu → Power off timers → Standby timer = **No limit** (or 30 min).
- **USB Data Connection:** MTP/PTP.
- **Memory Card:** Insert a formatted SD/CFexpress card.

## 3. Before Every Demo Session
1. Turn on the Nikon Z6II and plug in the USB-C cable.
2. Close Nikon NX Tether / Webcam Utility if running on Windows.
3. Run PowerShell as Administrator in the repo root:
   ```powershell
   .\setup_camera.ps1
   ```
   Confirm `Nikon Z6_2` appears under `gphoto2 --auto-detect`.
4. In MATLAB, run:
   ```matlab
   startPhotobooth
   ```
5. Verify live preview runs at ~10–15 fps and test one 4-shot session.
6. If the camera cable is unplugged mid-event, re-run `.\setup_camera.ps1` and click **ลองใหม่ (Retry)** in the app, or click **ใช้โหมดสำรอง (Mock)** to continue without hardware.
