function out = autoCorrect(img)
%AUTOCORRECT Gray-world white balance (illumgray + chromadapt in linear
% RGB), then gentle CLAHE on the Lab lightness channel only, so that
% contrast improves without shifting colors. Returns the input class.
I = im2double(img);
lin = rgb2lin(I);
if any(lin(:) > 0)
    illum = illumgray(lin, 2);           % ignore 2% darkest/brightest
    if all(isfinite(illum)) && all(illum > eps)
        lin = chromadapt(lin, illum, 'ColorSpace', 'linear-rgb');
    end
end
I = lin2rgb(min(max(lin, 0), 1));
lab = rgb2lab(I);
L = min(max(lab(:,:,1) / 100, 0), 1);
lab(:,:,1) = 100 * adapthisteq(L, 'ClipLimit', 0.005);
out = imgproc.restoreClass(lab2rgb(lab), class(img));
end
