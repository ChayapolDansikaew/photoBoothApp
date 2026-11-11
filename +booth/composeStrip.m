function out = composeStrip(frame, photos)
%COMPOSESTRIP Fill each slot of frame with photos{k} (center-cropped to
% the slot's aspect ratio, resized to fit), then overlay the frame using
% its alpha: out = canvas.*(1-alpha) + frame.rgb.*alpha.
% Output: double RGB, same size as frame.rgb.
[h, w, ~] = size(frame.rgb);
canvas = ones(h, w, 3);
for k = 1:size(frame.slots, 1)
    s = frame.slots(k,:);
    tile = booth.cropToAspect(im2double(photos{k}), s(3) / s(4));
    tile = min(max(imresize(tile, [s(4) s(3)]), 0), 1);
    canvas(s(2):s(2)+s(4)-1, s(1):s(1)+s(3)-1, :) = tile;
end
out = canvas .* (1 - frame.alpha) + frame.rgb .* frame.alpha;
end
