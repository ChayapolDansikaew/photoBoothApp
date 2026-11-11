# MATLAB Photobooth + Beauty — Design Spec

- **วันที่:** 2026-11-07
- **สถานะ:** ผ่านการพูดคุยแล้ว รอผู้ใช้รีวิว
- **เดดไลน์:** 2–4 สัปดาห์
- **สภาพแวดล้อม:** Windows, MATLAB R2024b + Image Processing Toolbox (ไม่มี Computer Vision Toolbox), กล้อง Nikon Z6II, WSL2

## 1. เป้าหมาย

แอป MATLAB แบบตู้โฟโต้บูธ:
- ผู้ใช้เลือกกรอบ โดยแต่ละกรอบมีโทนสีของตัวเอง
- กดถ่ายในแอป กล้องนับ 3-2-1 แล้วถ่ายรวม 4 รูป
- ปรับความเนียนผิวและถ่ายใหม่รายรูปได้
- ได้รูปรวม 4 รูปในแผ่นเดียว + GIF เซฟลงเครื่อง

กล้องเชื่อมด้วย **gphoto2** ผ่าน WSL และมีโหมด Mock ไว้พัฒนาและเป็นตัวสำรอง

**ไม่ทำ (Non-goals):**
- ปริ้น
- QR code
- สติ๊กเกอร์
- ปรับความเนียนแยกรายรูป
- ตาโต / แก้รูปหน้า
- ตรวจจับใบหน้าด้วย deep learning
- รองรับกล้องหลายตัว

## 2. UX Flow

```
0 Idle ──แตะ──▶ 1 เลือกกรอบ ──Start──▶ 2 ถ่าย (x4) ──▶ 3 Review & Beauty ──Done──▶ 4 ผลลัพธ์ ──▶ 0
   │                                        ▲                │ Retake รูป N
   └──▶ Gallery                             └────────────────┘ (ถ่ายเดี่ยว 1 รูป แล้วกลับหน้า 3)
```

| หน้า | องค์ประกอบ | พฤติกรรม |
|---|---|---|
| 0 Idle | สไลด์โชว์ `strip.png` ล่าสุด (เปลี่ยนทุก 4 วิ), ปุ่ม "แตะเพื่อเริ่ม", ปุ่ม Gallery | ถ้ายังไม่เคยถ่ายเลย แสดงข้อความต้อนรับแทน |
| Gallery | ตารางรูปย่อของทุกเซสชัน เรียงใหม่ไปเก่า แตะเพื่อดูรูปใหญ่ | ปุ่มกลับไปหน้า Idle |
| 1 เลือกกรอบ | การ์ดกรอบ (รูปย่อ + ป้ายโทน), live preview ที่ใส่โทนของกรอบที่เลือก, ปุ่ม Start | เลือกกรอบแรกไว้ให้ก่อน |
| 2 ถ่าย | live preview จอใหญ่ (กลับซ้ายขวาแบบกระจก + ใส่โทน), แถบรูปย่อ 4 ช่องด้านขวา, ข้อความ "รูป n / 4" | นับ 3-2-1 (เลขใหญ่ + บี๊บ) → ถ่าย (จอขาวแวบ + เสียงชัตเตอร์) → รูปย่อเข้าช่อง → พัก 3 วิ ("โพสต่อ!") → รูปถัดไป |
| 3 Review & Beauty | ตาราง 2×2 + ปุ่ม Retake ใต้แต่ละรูป, รูปที่เลือกแสดงใหญ่, สไลด์ Smoothness 0–100 (เริ่มที่ 40), สวิตช์ Auto light (เริ่มที่เปิด), ปุ่มกดค้างเพื่อดูก่อน/หลัง, ปุ่ม Done | ขยับสไลด์แล้วรูปใหญ่อัปเดตทันที (คำนวณที่ประมาณ 800px) |
| 4 ผลลัพธ์ | รูปรวมสุดท้าย + GIF ที่เล่นวน, ปุ่ม "ถ่ายใหม่" / "เสร็จ" | เซฟอัตโนมัติตอนเข้าหน้านี้ |

**ทั่วไป:**
- เปิดเต็มจอ ปุ่มใหญ่
- ไม่มีใครแตะ 60 วิ ในหน้า 1, 3, 4 หรือ Gallery จะกลับหน้า Idle (หน้า 2 ไม่นับเวลา)
- Mockup: `ui_mockups.md` ใน artifacts พื้นเทาเข้ม #1a1a1f ตัวหนังสือครีม สีเน้นคอรัล #ff6b6b

## 3. สถาปัตยกรรม

```
Nikon Z6II ──USB(usbipd)──▶ WSL: camera_bridge/bridge.py ◀──TCP localhost:5555──▶ MATLAB
```

### 3.1 โครงสร้างไฟล์

```
Mineaorz/
├── PhotoboothApp.m           # UI + state machine (คลาสที่ใช้ uifigure)
├── startPhotobooth.m         # จุดเริ่ม: addpath, อ่าน config, เปิดแอป
├── config.json
├── +camera/
│   ├── CameraBackend.m       # คลาสแม่แบบ abstract: start / getPreviewFrame / capture / stop / isReady
│   ├── GPhotoCamera.m        # tcpclient ต่อไปที่ bridge
│   └── MockCamera.m          # วนรูปจาก assets/mock/ (เติมสัญญาณรบกวนนิดหน่อยให้ดูเหมือนภาพสด)
├── +imgproc/
│   ├── autoCorrect.m
│   ├── skinMask.m            # คืนมาสก์ผิวแบบขอบนุ่ม [0,1]
│   ├── prepareSmoothing.m    # มาสก์ + เลเยอร์ผิวเนียน (skinSmooth บนช่อง Y, ทำครั้งเดียวต่อรูป)
│   ├── blendSmoothing.m      # ผสมตามค่าสไลด์ (เร็ว)
│   ├── skinSmooth.m          # bilateral เฉพาะช่อง Y ของ YIQ (จาก Group4_Final)
│   ├── flashSkinSmooth.m     # ผิวเนียนจากภาพไม่แฟลช + รายละเอียดจากภาพแฟลช (ยังไม่ใช้ในตู้)
│   ├── applyTone.m           # applyTone(img, name, 'preview'|'final')
│   ├── toneNames.m
│   ├── restoreClass.m
│   └── debugSkinPipeline.m   # รูปแสดงแต่ละขั้น ไว้ใส่รายงาน
├── +booth/
│   ├── loadFrames.m          # อ่าน frames/*.png + .json (เดิมใน spec เรียก FrameLibrary)
│   ├── detectSlots.m         # หาช่องใส 4 ช่องแล้วเรียงลำดับ
│   ├── defaultFrame.m
│   ├── preparePhoto.m        # รูปดิบ → ย่อ/mirror/autoCorrect/prepareSmoothing
│   ├── renderPhoto.m         # blend + tone
│   ├── loadConfig.m
│   ├── cropToAspect.m
│   ├── composeStrip.m
│   ├── makeGif.m
│   ├── SessionStore.m
│   ├── Sounds.m              # บี๊บ/ชัตเตอร์สร้างด้วย sound() ไม่ใช้ไฟล์เสียง
│   └── Logger.m
├── camera_bridge/
│   ├── bridge.py
│   ├── test_bridge.py        # ใช้ fake camera
│   └── requirements.txt      # gphoto2, pillow, numpy
├── setup_camera.ps1          # usbipd bind/attach กล้อง Nikon (VID 04b0) เข้า WSL ต้องรันแบบ admin
├── frames/                   # <ชื่อ>.png + <ชื่อ>.json (ผู้ใช้ออกแบบเอง) มีกรอบตัวอย่างมาให้ 2 อัน
├── assets/mock/              # รูปสำหรับ MockCamera
├── output/                   # เซสชันที่ถ่ายไว้
├── logs/
├── tests/
└── docs/hardware-checklist.md
```

### 3.2 Bridge protocol (TCP, ASCII header + binary)

- Request เป็นบรรทัด ASCII ปิดด้วย `\n`
- Response บรรทัดแรกขึ้นต้นด้วย `OK` หรือ `ERR <ข้อความ>`

| Request | Response |
|---|---|
| `PING` | `OK pong` |
| `STATUS` | `OK <ready\|disconnected> <ชื่อรุ่นกล้อง>` |
| `PREVIEW` | `OK <w> <h> <nbytes>\n` ตามด้วย RGB uint8 ดิบ เรียงแบบ HWC ย่อให้กว้าง 960 px |
| `CAPTURE <wsl_path>` | `OK <wsl_path>` บันทึก JPEG เต็มความละเอียดลง path ที่ระบุ |

- **ฝั่ง MATLAB:** แปลงไบต์เป็นรูปด้วย `permute(reshape(bytes,[3 w h]),[3 2 1])` และแปลง path จาก `C:\...` เป็น `/mnt/c/...`
- **ฝั่ง bridge:**
  - รับทีละ client ทำงาน thread เดียว เปิดเซสชันกล้องค้างไว้
  - ถ้าเกิด error ฝั่ง gphoto ให้ปิดแล้วเปิดกล้องใหม่ (สูงสุด 3 ครั้ง) ก่อนจะตอบ `ERR`
- **ตอนเปิดแอป:** ถ้า `GPhotoCamera.start` ต่อไม่ได้ จะสั่ง `system('start "" /b wsl python3 <path>/bridge.py')` แล้วลองต่อใหม่ทุก 1 วิ นานสุด 10 วิ
- **ความเร็วเป้าหมาย:** live preview 10–15 fps โดยใช้ MATLAB `timer` เรียกทุก 66 ms ระหว่างรอ `CAPTURE` ให้หยุด preview ไว้ก่อน

### 3.3 config.json

`camera` เป็น `"gphoto"` หรือ `"mock"` ส่วน `mirror` ใช้กับทั้ง preview และรูปที่เซฟ (ไฟล์จริงห้ามมีคอมเมนต์ เพราะ `jsondecode` จะอ่านไม่ได้)

```json
{
  "camera": "gphoto",
  "bridgePort": 5555,
  "countdownSeconds": 3,
  "gapSeconds": 3,
  "mirror": true,
  "idleTimeoutSeconds": 60,
  "workingLongSide": 2400,
  "reviewLongSide": 800,
  "gifDelaySeconds": 0.6,
  "defaultSmoothness": 40,
  "outputDir": "output"
}
```

## 4. ไปป์ไลน์ภาพ

ลำดับในแต่ละรูป:
1. ย่อเหลือ `workingLongSide`
2. mirror
3. `autoCorrect` (ถ้าเปิดสวิตช์ไว้)
4. ผิวเนียน (`prepareSmoothing` + `blendSmoothing`)
5. `applyTone(...,'final')`
6. ส่งต่อให้ `composeStrip`

ต้องทำหน้าเนียนก่อนใส่โทน เพราะการหาผิวต้องใช้สี

### 4.1 `autoCorrect(img)`
- ประเมินสีของแสงด้วย `illumgray(img, 10)` แล้วแก้ด้วย `chromadapt(img, illum)`
- แปลง `rgb2lab` → ใช้ `adapthisteq` กับช่อง L/100 (`ClipLimit` 0.005) → แปลงกลับ `lab2rgb`

### 4.2 `skinMask(img)` → M ∈ [0,1]
1. แปลง `rgb2ycbcr` แล้วเลือกพิกเซลที่ Cb อยู่ช่วง [77,127] และ Cr อยู่ช่วง [133,173]
2. `imopen(disk 3)` → `imclose(disk 7)` → `imfill holes` → `bwareaopen` (ตัดชิ้นที่เล็กกว่า 0.2% ของพื้นที่รูป)
3. ตัดขอบออก: ใช้ `imgradient` กับช่อง Y ที่ normalize แล้ว พิกเซลที่ gradient มากกว่าค่า percentile ที่ 85 ถือเป็นขอบ ขยายด้วย `imdilate(disk 1)` แล้วเอาออกจากมาสก์
4. เบลอมาสก์ด้วย `imgaussfilt`, σ = 0.004 × ด้านยาวของรูป

### 4.3 ผิวเนียน: `prepareSmoothing` + `blendSmoothing(prep, amount)` (amount 0–100)
- a = amount/100 ถ้า a = 0 คืนรูปเดิมทันที
- แยกเป็น 2 ขั้นเพื่อให้ลากสไลด์แล้วเห็นผลทันที:
  - **`prepareSmoothing`** ทำครั้งเดียวต่อรูป: หามาสก์ M แล้วแปลงรูปเป็น YIQ ทำช่อง Y ให้เนียนด้วย `skinSmooth(Y, 0.01, sigmaS)` บนรูปย่อที่ด้านยาวไม่เกิน 800px (sigmaS = 3 px ที่ 800 px) ถ้าย่อมาก็ขยายกลับ แล้วประกอบกับช่อง I/Q เดิมของรูป สีผิวจึงไม่เปลี่ยน
  - **`blendSmoothing`** ทำทุกครั้งที่ขยับสไลด์: แค่ผสมรูปตามสูตรด้านล่าง
- ความแรงของ bilateral คงที่ สไลด์คุมแค่น้ำหนัก a
- คืนรายละเอียดผิว (เฉพาะช่อง Y): `detail = Y − imgaussfilt(Y, 1)` แล้วใช้ `Ysmooth = Ysmooth + 0.3·detail`
- ผสมรูป: `out = img·(1 − a·M) + smooth·(a·M)`
- `skinSmooth(img, sigmaR, sigmaS)` (จาก Group4_Final): `imbilatfilt` เฉพาะช่อง Y ของ YIQ ค่าเริ่มต้น sigmaR 0.01, sigmaS 3 คืนค่า double [0,1]
- `flashSkinSmooth(noFlashImg, flashImg, sigmaR, sigmaS)`: base = bilateral ของ Y จากภาพไม่แฟลช, detail = Y_flash ./ bilateral(Y_flash), ผลลัพธ์ = base·detail โดยใช้สี (I/Q) ของภาพไม่แฟลช ถ้าภาพแฟลชขนาดไม่เท่ากันจะ resize ให้ ยังไม่ได้ใช้ในตู้ เพราะตู้ถ่ายช่องละ 1 รูปและไม่มีแฟลช
- `debugSkinPipeline` แสดง 6 ช่อง: ต้นฉบับ → มาสก์ YCbCr → หลังทำ morphology → edge map → มาสก์สุดท้าย → ผลลัพธ์

### 4.4 `applyTone(img, name, mode)`
- แต่ละโทนประกอบด้วย LUT ต่อช่องสี (256 ค่า) + color matrix 3×3 ซึ่งเร็วพอสำหรับ preview
- โหมด `'final'` ใส่ grain, vignette, glow เพิ่ม

| name | ส่วนที่ใช้ใน preview | สิ่งที่ `final` ใส่เพิ่ม |
|---|---|---|
| `bw` | luminance (0.299/0.587/0.114) + S-curve | grain σ 0.02 |
| `warmFilm` | ยกส่วนมืดขึ้น 0.06, R ×1.06, B ×0.90, S-curve อ่อนๆ | grain + vignette 0.25 |
| `pastel` | gamma 0.85, saturation ×0.75, contrast ×0.85, ทินต์ชมพู (+0.03 R, +0.015 B) | soft glow (screen blend กับรูปที่เบลอ σ 8, 25%) |
| `vivid` | saturation ×1.35, S-curve | — |
| `cinematic` | split toning: ส่วนมืด +teal (−R, +G, +B), ส่วนสว่าง +orange, สลับตามค่าความสว่าง | vignette 0.2 |
| `sepia` | sepia matrix มาตรฐาน | vignette 0.3 + grain |

- ชื่อโทนที่ไม่รู้จัก: ใช้ `bw` แทนและเขียนเตือนลง log

### 4.5 `composeStrip(frame, photos)` / `makeGif`
- ขนาดรูปรวม = ขนาด PNG กรอบ
- แต่ละรูป: center crop ให้ได้สัดส่วนเท่า bounding box ของช่อง → `imresize` → วางลง canvas สีขาว
- เอากรอบทับด้านบน: `out = canvas·(1−α) + frameRGB·α`
- `makeGif`: ใช้ `rgb2ind(img, 256)` + `imwrite(..., 'gif', 'LoopCount', Inf, 'DelayTime', 0.6)` สำหรับรูปเดี่ยวทั้ง 4 ที่ย่อด้านยาวเหลือ 800

## 5. สเปกไฟล์กรอบ (สำหรับคนออกแบบ)

- PNG แบบ RGBA เจาะช่องใส (alpha < 10) ให้ได้ **4 ช่องพอดี** ช่องเป็นรูปทรงอะไรก็ได้ แอปใช้ bounding box ของช่องในการวางรูป ส่วนขอบที่ไม่ใสของกรอบจะทับรูปอยู่ด้านบน
- จุดใสที่เล็กกว่า 1% ของพื้นที่กรอบจะถูกมองข้าม
- ขนาดที่แนะนำ (300 dpi):
  - **2×6 นิ้ว** (แถบยาว) → 600×1800
  - **4×6 นิ้ว** (2×2) → 1200×1800
- ลำดับช่อง: เรียงจากบนลงล่าง ถ้าจุดกึ่งกลางสูงต่างกันไม่เกิน 10% ของความสูงช่อง ถือว่าอยู่แถวเดียวกัน แล้วเรียงซ้ายไปขวา
- `<ชื่อ>.json`: `{"name": "Classic B&W", "tone": "bw"}` ถ้าไม่มีไฟล์นี้ ชื่อกรอบ = ชื่อไฟล์ และโทน = `bw`

## 6. การเซฟ

`output/YYYYMMDD_HHMMSS/` ประกอบด้วย:
- `strip.png`
- `animation.gif`
- `raw_1..4.jpg` (รูปต้นฉบับจากกล้อง)
- `photo_1..4.png` (รูปหลังประมวลผล)
- `meta.json` (กรอบ, โทน, ค่า smoothness, สถานะ auto light)

แกลเลอรี่และหน้า Idle อ่านจากโฟลเดอร์นี้

## 7. การรับมือ error

| เหตุการณ์ | แอปทำอะไร |
|---|---|
| ต่อ bridge ไม่ได้ตอนเปิดแอป | สั่งรัน bridge ให้เองแล้วลองต่อนาน 10 วิ ถ้าไม่ได้ ขึ้นแบนเนอร์ "กล้องไม่พร้อม" พร้อมปุ่ม [ลองใหม่] [ใช้โหมดสำรอง] |
| สายหลุดหรือกล้องค้างกลางเซสชัน | bridge เปิดกล้องใหม่ (สูงสุด 3 ครั้ง) รูปที่ถ่ายแล้วยังอยู่ ถ่ายต่อจากรูปที่ค้างได้ |
| `CAPTURE` เกิน 10 วิ หรือได้ `ERR` | ขึ้นข้อความ "ถ่ายไม่สำเร็จ ลองอีกครั้ง" แล้วนับ 3-2-1 รูปเดิมใหม่ |
| กรอบเสีย / ช่องไม่ครบ 4 / JSON ผิด | ข้ามกรอบนั้นและเขียนเตือนลง log ถ้าไม่มีกรอบใช้ได้เลยสักอัน ใช้กรอบในตัวแบบขาวล้วน 4×1 |
| เซฟไม่สำเร็จ | แจ้งเตือนบนจอ รูปยังอยู่ในหน่วยความจำ กดเซฟซ้ำได้ |

ทุก error จะเขียนลง `logs/photobooth.log`

## 8. การเทสต์

ใช้ `matlab.unittest` รันด้วย `runtests('tests')`

- **`imgproc`:**
  - `blendSmoothing(prepareSmoothing(img), 0)` ต้องได้รูปเดิมเป๊ะ
  - ผิวเนียนต้องไม่เปลี่ยนสี: ช่อง I/Q ของ YIQ เท่าเดิม ทั้งรูปเล็กและรูปที่ใหญ่กว่า 800px
  - `flashSkinSmooth`: ใส่ภาพเดียวกันสองช่องต้องได้ภาพเดิม, ได้ความสว่างและสีจากภาพไม่แฟลชโดย noise ลดลง และได้ texture จากภาพแฟลช
  - บริเวณผิวสังเคราะห์ที่มี noise ค่า variance ต้องลดลงอย่างน้อย 50% ที่ amount 100
  - ความชันของขอบ step edge ต้องเหลืออย่างน้อย 90%
  - ทุกโทนต้องคืนขนาดและ class เดิม และ `bw` ต้องได้ R=G=B
- **`FrameLibrary`:** ใช้ PNG ที่สร้างในโค้ด (4×1, 2×2, ช่องขนาดไม่เท่ากัน, มีจุดใสเล็กๆ, มีแค่ 3 ช่อง ซึ่งต้องถูกข้าม) เช็คว่าตำแหน่งและลำดับช่องถูก
- **`composeStrip`:** ขนาดผลลัพธ์เท่ากรอบ พิกเซลกลางช่องมาจากรูปที่ถ่าย ส่วนกรอบทึบไม่ถูกเปลี่ยน
- **Flow:** ใช้ `MockCamera` ทำครบรอบ (เลือกกรอบ → ถ่าย 4 รูป → retake รูปที่ 2 → Done) โดยสั่งผ่าน method ของแอปตรงๆ ไม่ต้องคลิก UI แล้วเช็คว่าไฟล์ในเซสชันครบ
- **`bridge.py`:** ใช้ `pytest` กับ fake camera ทดสอบ protocol และการเปิดกล้องใหม่ตอน error
- **กล้องจริง:** `docs/hardware-checklist.md`
  - ตั้งกล้องเป็น JPEG Fine L
  - ปิด auto power off
  - ตั้งโฟกัส AF-S ที่จับใบหน้า
  - รัน usbipd attach
  - เทสต์ preview fps และความหน่วงตอนถ่าย
