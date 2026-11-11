# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **ผู้เข้าชมงานและนักศึกษาในงานนิทรรศการมหาวิทยาลัย (Booth Visitors):** แวะมาถ่ายรูปเดี่ยวหรือถ่ายเป็นกลุ่มหน้าบูธ ต้องการประสบการณ์ที่เข้าใจได้ทันทีในไม่กี่วินาที กดเริ่ม เลือกกรอบ โพสท่า 4 ช็อต ปรับผิวเนียน และได้ไฟล์รูป Strip 4 ช่องพร้อม GIF กลับไปโดยไม่ต้องมีคนคอยสอนทุกขั้นตอน
- **อาจารย์และผู้ตรวจโปรเจกต์วิชา Image Processing (Academic Evaluators):** ประเมินความถูกต้อง ความลื่นไหล และคุณภาพของอัลกอริทึมประมวลผลภาพที่เขียนขึ้นเองใน MATLAB (การตรวจจับพื้นที่ผิวด้วย YCbCr + Morphology + Edge Removal, การทำ Bilateral Skin Smoothing แบบแยก Prepare/Blend เพื่อความเร็วระดับ Interactive, การแก้แสงด้วย Gray World + CLAHE บนปริภูมิสี LAB และการย้อมโทนสีด้วย LUT/Color Matrix)

## Product Purpose

แอปพลิเคชันตู้ถ่ายรูปโฟโต้บูธแบบเต็มจอ (Fullscreen Kiosk) บน MATLAB ที่เปลี่ยนอัลกอริทึม Image Processing เชิงวิชาการให้กลายเป็นประสบการณ์ถ่ายรูปจริงระดับสตูดิโอ ผู้ใช้สามารถเลือกกรอบพร้อมโทนสีประจำกรอบ ถ่ายภาพต่อเนื่อง 4 ช็อตจากกล้องมิเรอร์เลส Nikon Z6II ปรับระดับความเนียนผิวแบบเห็นผลทันที และรับไฟล์ภาพ Strip 4 ช่องพร้อมภาพเคลื่อนไหว GIF บันทึกลงเครื่องอัตโนมัติ

ความสำเร็จของผลิตภัณฑ์วัดจาก:
1. ผู้มางานสามารถเดินเข้ามาใช้งานตั้งแต่หน้า Idle จนได้รูปจบครบเซสชันด้วยตัวเองอย่างลื่นไหล (Self-service Kiosk)
2. การปรับค่าความเนียนผิว (Smoothness 0–100) และสลับดูก่อน/หลังในหน้า Review ตอบสนองทันทีโดยไม่สะดุด และรักษาความคมชัดของดวงตา คิ้ว ปาก และเส้นผมไว้ได้อย่างเป็นธรรมชาติ

## Positioning

ตู้โฟโต้บูธที่ขับเคลื่อนด้วยไปป์ไลน์ Image Processing แบบ Classical ล้วนบน MATLAB Image Processing Toolbox (ไม่พึ่งพา Deep Learning หรือ Computer Vision Toolbox) ผสานกับกล้องจริง Nikon Z6II ผ่านสะพานเชื่อมต่อ WSL2 `gphoto2` TCP Bridge โดยออกแบบสถาปัตยกรรมแยกขั้นตอนคำนวณหนัก (`prepareSmoothing` ด้วย Bilateral Filter) ออกจากขั้นตอนผสมภาพ (`blendSmoothing`) ทำให้ลากสไลด์ปรับผิวเนียนและเปลี่ยนโทนสีได้แบบเรียลไทม์ในหน้าจอ Kiosk

## Operating Context

- **สถานที่และการจัดวาง:** ตั้งแสดงเป็นซุ้ม/บูธในงานนิทรรศการวิชาการของมหาวิทยาลัย เชื่อมต่อคอมพิวเตอร์ระบบ Windows เข้ากับกล้อง Nikon Z6II บนขาตั้งและไฟสตูดิโอ/สภาพแวดล้อมในร่มของงาน
- **รูปแบบการใช้งาน:** เปิดหน้าจอค้างไว้ตลอดงาน มีระบบ Idle Timeout (60 วินาที) วนกลับหน้าแรกพร้อมสไลด์โชว์ผลงานล่าสุดอัตโนมัติเมื่อไม่มีคนใช้งาน และมีระบบสลับเข้าโหมดกล้องสำรอง (`MockCamera`) อัตโนมัติหรือกดสลับได้ทันทีหากสาย USB หรือกล้องมีปัญหาระหว่างจัดแสดง
- **ลำดับการใช้งาน 6 หน้าจอ:**
  1. `idle`: สไลด์โชว์รูป `strip.png` ล่าสุดทุก 4 วินาที พร้อมปุ่มเริ่มถ่ายและปุ่มดูแกลเลอรี่
  2. `gallery`: แสดงผลงานรูปถ่ายล่าสุดจากเซสชันก่อนหน้า
  3. `chooseFrame`: เลือกกรอบรูป (`frames/*.png` + `.json`) ซึ่งผูกกับโทนสีอัตโนมัติ พร้อมเห็นภาพ Live Preview ย้อมโทนสีจริง
  4. `shooting`: นับถอยหลัง 3-2-1 พร้อมเสียงสัญญาณสังเคราะห์ (`+booth/Sounds.m`) ถ่ายต่อเนื่อง 4 ช็อต (เว้นระยะโพสท่า 3 วินาที) และแสดงภาพย่อด้านข้าง
  5. `review`: ตาราง 2×2 เลือกดูรูปขยาย กดถ่ายซ้ำรายรูป (Single-shot Retake) ปรับสไลด์ความเนียนผิว (0–100, ค่าเริ่มต้น 40) เปิด/ปิด Auto Light และกดสลับดูภาพก่อน/หลัง
  6. `result`: แสดงภาพ Strip 4 ช่องฉบับสมบูรณ์คู่กับ `animation.gif` ที่เล่นวน พร้อมบันทึกไฟล์ลงโฟลเดอร์เซสชันอัตโนมัติ

## Capabilities and Constraints

- **ข้อจำกัดด้านแพลตฟอร์มและ UI Stack:** พัฒนาและปรับโฉมบน **MATLAB R2024b `uifigure`** ([`PhotoboothApp.m`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/PhotoboothApp.m)) โดยตรง ภายใต้ความสามารถของคอมโพเนนต์มาตรฐาน (`uipanel`, `uilabel`, `uibutton`, `uiimage`, `uislider`, `uicheckbox`) ร่วมกับการออกแบบกราฟิกกรอบรูป (`frames/`) และ Assets ประกอบ
- **ข้อจำกัดทางเทคนิค:**
  - ใช้เฉพาะ MATLAB + Image Processing Toolbox เท่านั้น (ห้ามใช้ฟังก์ชันจาก Computer Vision Toolbox หรือ Deep Learning)
  - ลำดับไปป์ไลน์ภาพต้องทำ `skinSmooth` ก่อน `applyTone` เสมอ เนื่องจากอัลกอริทึมคัดแยกสีผิวต้องอ้างอิงค่าสี YCbCr ก่อนถูกย้อมโทน
  - โทนสีที่รองรับในระบบ: `bw`, `warmFilm`, `pastel`, `vivid`, `cinematic`, `sepia` (แยกโหมด `'preview'` เน้นความเร็ว 10–15 fps และ `'final'` ที่เติม grain, vignette หรือ soft glow)
  - กรอบรูปเป็นไฟล์ PNG แบบ RGBA ที่เจาะช่องโปร่งใส (`alpha < 10`) จำนวน 4 ช่องพอดี พร้อมไฟล์ JSON กำหนดชื่อและโทนสี
- **ขอบเขตที่ไม่ทำ (Non-goals):** ไม่มีการสั่งพิมพ์กระดาษจริง, ไม่สร้าง QR Code, ไม่มีสติ๊กเกอร์ตกแต่ง, ไม่ปรับความเนียนแยกรายรูป, และไม่ทำฟีเจอร์บีบหน้า/ตาโต

## Brand Commitments

- **ทิศทางภาพลักษณ์หลัก (Visual Direction):** **Seoul Self-Studio Minimal (Warm Ivory & Espresso)** — โทนสว่างอบอุ่นสไตล์สตูดิโอถ่ายรูปตัวเองเกาหลียุคใหม่ ใช้พื้นหลังสีครีมอ่อน/งาช้าง (`Warm Ivory`) การ์ดสีเบจละมุน (`Soft Sand / Warm Linen`) ตัวอักษรสีน้ำตาลเอสเปรสโซเข้ม (`Deep Espresso`) และสีเน้นโทนอบอุ่น (`Burnt Terracotta` & `Muted Sage`)
- **ลำดับความสำคัญทางสายตา:** ภาพตัวอย่างจากกล้องและผลลัพธ์การปรับผิวเนียน (Before/After) ต้องเป็นจุดเด่นที่สุดบนจอ โดยสีของ UI ต้องเป็นกลางและอบอุ่นพอที่จะไม่ทำให้สายตาเพี้ยนเวลาประเมินสีผิวจริงหรือโทนสีของกรอบรูป

## Evidence on Hand

- โค้ดแอปพลิเคชันหลักและ UI State Machine: [`PhotoboothApp.m`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/PhotoboothApp.m), [`startPhotobooth.m`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/startPhotobooth.m), [`config.json`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/config.json)
- โมดูลประมวลผลภาพ: `+imgproc/` (`autoCorrect.m`, `skinMask.m`, `prepareSmoothing.m`, `blendSmoothing.m`, `skinSmooth.m`, `applyTone.m`, `debugSkinPipeline.m`)
- โมดูลจัดการบูธและกล้อง: `+booth/`, `+camera/`, `camera_bridge/bridge.py`
- กรอบรูปตัวอย่าง 2 แบบ: `frames/classic_strip.png` (โทน `bw`) และ `frames/pastel_grid.png` (โทน `pastel`)
- ภาพตัวอย่างสำหรับโหมดจำลอง: `assets/mock/mock_1.jpg` ถึง `mock_4.jpg`
- เอกสารสเปกและเช็กลิสต์ฮาร์ดแวร์: [`docs/superpowers/specs/2026-11-07-matlab-photobooth-design.md`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/docs/superpowers/specs/2026-11-07-matlab-photobooth-design.md), [`docs/hardware-checklist.md`](file:///c:/Users/ArthurZ/Desktop/Mineaorz/docs/hardware-checklist.md)

## Product Principles

1. **Self-Explanatory Booth Flow (เดินเข้ามาใช้ได้เองทันที):** ทุกหน้าจอต้องมีจุดโฟกัสเดียวที่ชัดเจน ปุ่มกดขนาดใหญ่ อ่านง่ายจากระยะยืนโพสท่าหน้ากล้อง และนำทางผู้ใช้ตั้งแต่ต้นจนจบโดยไม่ต้องพึ่งคู่มือหรือคนคุมตู้
2. **Real-Time Algorithmic Craft (โชว์งานประมวลผลภาพที่ตอบสนองทันใจ):** หน้าจอเลือกโทนสีและหน้าจอปรับความเนียนผิวคือหัวใจของโปรเจกต์ การจัดวาง UI ต้องส่งให้ภาพตัวอย่างขนาดใหญ่โดดเด่นที่สุด เพื่อให้ทั้งผู้มาถ่ายและอาจารย์เห็นความแตกต่างของผิวและแสงก่อน/หลังประมวลผลอย่างชัดเจน
3. **Graceful Hardware Resilience (พร้อมรับมือหน้างานจริงเสมอ):** เมื่อกล้องจริงหลุดการเชื่อมต่อหรือบันทึกไฟล์ติดขัด UI ต้องแจ้งเตือนอย่างชัดเจนแต่ไม่ทำให้แอปค้าง และมีทางออกฉุกเฉิน (Retry / สลับโหมด Mock / บันทึกซ้ำ) ที่กดได้ทันทีบนหน้าจอ
4. **MATLAB-Native Polish (รีดศักยภาพ `uifigure` ให้ดูเป็นผลิตภัณฑ์จริง):** ออกแบบ Layout, สัดส่วนช่องว่าง, การใช้สีตัดกัน และลำดับชั้นของตัวอักษรให้ก้าวข้ามความรู้สึกของหน้าต่างโปรแกรมคำนวณทั่วไป กลายเป็นหน้าจอตู้ Kiosk สตูดิโอที่มีเอกลักษณ์
