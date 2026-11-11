function out = cropToAspect(img, aspect)
%CROPTOASPECT Center-crop img so that width/height == aspect.
[h, w, ~] = size(img);
if w / h > aspect
    newW = max(1, round(h * aspect));
    x0 = floor((w - newW) / 2);
    out = img(:, x0+1:x0+newW, :);
else
    newH = max(1, round(w / aspect));
    y0 = floor((h - newH) / 2);
    out = img(y0+1:y0+newH, :, :);
end
end
