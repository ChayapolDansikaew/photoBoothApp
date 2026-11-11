function makeGif(photos, filePath, delaySeconds, longSide)
%MAKEGIF Write photos (cell of RGB images) as an endlessly looping GIF,
% each frame shown delaySeconds, downscaled so the long side <= longSide.
for k = 1:numel(photos)
    I = im2double(photos{k});
    scale = longSide / max(size(I, 1), size(I, 2));
    if scale < 1
        I = min(max(imresize(I, scale), 0), 1);
    end
    [ind, map] = rgb2ind(I, 256);
    if k == 1
        imwrite(ind, map, filePath, 'gif', 'LoopCount', Inf, 'DelayTime', delaySeconds);
    else
        imwrite(ind, map, filePath, 'gif', 'WriteMode', 'append', 'DelayTime', delaySeconds);
    end
end
end
