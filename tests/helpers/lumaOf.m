function L = lumaOf(img)
%LUMAOF Rec.601 luma of an RGB image (double).
I = im2double(img);
L = 0.299*I(:,:,1) + 0.587*I(:,:,2) + 0.114*I(:,:,3);
end
