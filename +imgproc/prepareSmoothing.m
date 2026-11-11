function prep = prepareSmoothing(img)
%PREPARESMOOTHING Precompute everything the beauty slider needs, so that
% moving the slider is only a cheap blend (imgproc.blendSmoothing).
%   prep.I      original image (double)
%   prep.M      soft skin mask (imgproc.skinMask)
%   prep.smooth original color (I, Q of YIQ) with smoothed brightness:
%               imgproc.skinSmooth on Y + 30% fine texture
%   prep.cls    class of the input (restored on output)
% Only Y is filtered, so skin tone never shifts. The bilateral filter runs
% on a copy at most 800 px on its long side (the smoothed layer is
% low-frequency, so upsampling it loses nothing), and fine texture from
% the full-resolution Y is added back so skin does not look plastic.
sigmaR = 0.01;    % imgproc.skinSmooth DegreeOfSmoothing
sigmaS800 = 3;    % imgproc.skinSmooth SpatialSigma, in px at 800 px long side

I = im2double(img);
[h, w, ~] = size(I);
longSide = max(h, w);
M = imgproc.skinMask(I);

yiq = rgb2ntsc(I);
Y = yiq(:,:,1);
scale = min(1, 800 / longSide);
sigmaS = max(0.5, sigmaS800 * longSide * scale / 800);
Ys = imgproc.skinSmooth(imresize(Y, scale), sigmaR, sigmaS);
if scale < 1
    Ys = imresize(Ys, [h w]);
end
yiq(:,:,1) = Ys + 0.3 * (Y - imgaussfilt(Y, 1));
sm = ntsc2rgb(yiq);

prep = struct('I', I, 'M', M, 'smooth', sm, 'cls', class(img));
end
