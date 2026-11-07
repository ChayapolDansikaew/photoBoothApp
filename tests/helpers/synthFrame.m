function frame = synthFrame(h, w, rects)
%SYNTHFRAME Purple frame struct with holes at rects (already in slot order).
rgb = repmat(reshape([0.5 0.2 0.8], 1, 1, 3), h, w);
frame = struct('name', 'Test', 'tone', 'bw', 'path', '', 'rgb', rgb, ...
    'alpha', makeAlpha(h, w, rects), 'slots', rects);
end
