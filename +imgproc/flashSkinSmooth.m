function out = flashSkinSmooth(noFlashImg, flashImg, sigmaR, sigmaS)
%FLASHSKINSMOOTH  ผิวเนียนจากภาพไม่เปิดแฟลช + ความคมจากภาพเปิดแฟลช
%   (Bilateral Filter + Flash Detail Transfer, จาก Group4_Final.mlapp)
%
%   out = flashSkinSmooth(noFlashImg, flashImg)
%   out = flashSkinSmooth(noFlashImg, flashImg, sigmaR, sigmaS)
%
%   noFlashImg : ภาพ Ambient (ไม่เปิดแฟลช) RGB
%   flashImg   : ภาพ Flash (เปิดแฟลช) RGB - ถ้าขนาดไม่เท่ากันจะ resize ให้
%   sigmaR     : DegreeOfSmoothing (0.01 - 2, ค่าเริ่มต้น 0.01)
%   sigmaS     : SpatialSigma      (1 - 20,   ค่าเริ่มต้น 3)
%
%   out        : ภาพผลลัพธ์ชนิด double ช่วง [0,1]

    if nargin < 3 || isempty(sigmaR), sigmaR = 0.01; end
    if nargin < 4 || isempty(sigmaS), sigmaS = 3;    end

    A = im2double(noFlashImg);
    F = im2double(flashImg);
    if ~isequal(size(F, 1, 2), size(A, 1, 2))
        F = imresize(F, size(A, 1, 2));
    end

    % แปลงเป็น YIQ แล้วประมวลผลเฉพาะความสว่าง Y
    A_yiq = rgb2ntsc(A);
    F_yiq = rgb2ntsc(F);
    A_y = A_yiq(:,:,1);
    F_y = F_yiq(:,:,1);

    % ผิวเนียน (Base layer) จากภาพ Ambient
    A_base = imbilatfilt(A_y, sigmaR, sigmaS);

    % รายละเอียด (Detail layer) จากภาพ Flash
    F_base   = imbilatfilt(F_y, sigmaR, sigmaS);
    F_detail = (F_y + eps) ./ (F_base + eps);

    % รวม: ผิวเนียนจาก Ambient x ความคมจาก Flash
    res_y = min(max(A_base .* F_detail, 0), 1);

    A_yiq(:,:,1) = res_y;
    out = min(max(ntsc2rgb(A_yiq), 0), 1);
end
