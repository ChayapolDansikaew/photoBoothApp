function out = skinSmooth(img, sigmaR, sigmaS)
%SKINSMOOTH  ทำผิวหน้าเนียนแบบรักษาขอบภาพไว้ (Bilateral Filter)
%
%   out = skinSmooth(img)
%   out = skinSmooth(img, sigmaR, sigmaS)
%
%   img    : ภาพ RGB หรือ Grayscale (uint8 / double ก็ได้)
%   sigmaR : DegreeOfSmoothing - ระดับความเนียน / การรักษาขอบ
%            (ค่าน้อย = ขอบคมมาก, ค่ามาก = เนียนมากแต่ขอบเริ่มเบลอ)
%            ช่วงที่ใช้ใน Group4_Final: 0.01 - 2   (ค่าเริ่มต้น 0.01)
%   sigmaS : SpatialSigma - ขอบเขตการเบลอ (ช่วง 1 - 20, ค่าเริ่มต้น 3)
%
%   out    : ภาพผลลัพธ์ชนิด double ช่วง [0,1]
%
%   กรองเฉพาะช่องความสว่าง (Y ของ YIQ) เพื่อไม่ให้สีผิวเพี้ยน
%   ต้องใช้ Image Processing Toolbox (imbilatfilt)

    if nargin < 2 || isempty(sigmaR), sigmaR = 0.01; end
    if nargin < 3 || isempty(sigmaS), sigmaS = 3;    end

    img = im2double(img);

    if size(img, 3) == 1
        % ภาพขาวดำ: กรองตรงๆ
        out = imbilatfilt(img, sigmaR, sigmaS);
    else
        % ภาพสี: แยกความสว่าง (Y) ออกจากสี (I, Q) แล้วกรองเฉพาะ Y
        yiq = rgb2ntsc(img);
        yiq(:,:,1) = imbilatfilt(yiq(:,:,1), sigmaR, sigmaS);
        out = ntsc2rgb(yiq);
    end

    out = min(max(out, 0), 1);
end
