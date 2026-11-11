function fig = debugSkinPipeline(img, amount, visible)
%DEBUGSKINPIPELINE Show every stage of the skin smoothing pipeline in a
% 2x3 figure (for the report / presentation):
%   original -> YCbCr skin -> morphology -> edge map -> final mask -> result
% Example: imgproc.debugSkinPipeline(imread('output/.../raw_1.jpg'), 70)
arguments
    img
    amount (1,1) double = 70
    visible (1,1) logical = true
end
[~, st] = imgproc.skinMask(img);
prep = imgproc.prepareSmoothing(img);
out = imgproc.blendSmoothing(prep, amount);

fig = figure('Name', 'Skin smoothing pipeline', ...
    'Visible', matlab.lang.OnOffSwitchState(visible));
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact');
panels = {img, st.raw, st.cleaned, st.edges, prep.M, out};
titles = {'1. Original', '2. YCbCr skin', '3. Morphology', ...
          '4. Edge map', '5. Final mask', sprintf('6. Result (%d)', round(amount))};
for k = 1:6
    ax = nexttile(tl);
    imshow(panels{k}, 'Parent', ax);
    title(ax, titles{k});
end
end
