function prep = preparePhoto(raw, longSide, mirror, autoLight)
%PREPAREPHOTO Turn a captured photo into a smoothing-ready struct:
% load (if raw is a file path) -> downscale so the long side <= longSide
% -> optional mirror -> optional imgproc.autoCorrect ->
% imgproc.prepareSmoothing. Use longSide = cfg.reviewLongSide for the
% interactive review and cfg.workingLongSide for the final export.
if ischar(raw) || isstring(raw)
    raw = imread(raw);
end
I = im2double(raw);
scale = longSide / max(size(I, 1), size(I, 2));
if scale < 1
    I = min(max(imresize(I, scale), 0), 1);
end
if mirror
    I = fliplr(I);
end
if autoLight
    I = imgproc.autoCorrect(I);
end
prep = imgproc.prepareSmoothing(I);
end
