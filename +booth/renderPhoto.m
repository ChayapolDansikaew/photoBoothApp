function out = renderPhoto(prep, amount, tone, mode)
%RENDERPHOTO Skin smoothing blend (amount 0-100) followed by the frame's
% tone. mode: 'preview' (review screen) or 'final' (export).
out = imgproc.applyTone(imgproc.blendSmoothing(prep, amount), tone, mode);
end
