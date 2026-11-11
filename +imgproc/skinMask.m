function [M, stages] = skinMask(img)
%SKINMASK Soft skin mask M in [0,1] (same height/width as img).
%  1. YCbCr color threshold (Chai & Ngan 1999): Cb 77-127, Cr 133-173
%  2. Morphological cleanup: open -> close -> fill holes -> remove specks
%  3. Remove strong edges (gradient of smoothed Y) so eyes, brows, lips
%     and hairlines stay sharp
%  4. Feather with a Gaussian so the blend has no visible seams
% stages (for debugSkinPipeline): raw, cleaned, edges, hard (logical).
I8 = im2uint8(img);
ycc = rgb2ycbcr(I8);
Cb = ycc(:,:,2);
Cr = ycc(:,:,3);
raw = Cb >= 77 & Cb <= 127 & Cr >= 133 & Cr <= 173;

[h, w] = size(raw);
s = max(h, w) / 1000;                     % scale sizes with resolution
cleaned = imopen(raw, strel('disk', max(1, round(3*s))));
cleaned = imclose(cleaned, strel('disk', max(1, round(7*s))));
cleaned = imfill(cleaned, 'holes');
cleaned = bwareaopen(cleaned, max(1, round(0.002 * h * w)));

Y = im2double(ycc(:,:,1));
G = imgradient(imgaussfilt(Y, max(0.5, 1.5*s)));
v = sort(G(:));
t = max(v(max(1, round(0.85 * numel(v)))), 0.25);   % 85th pct, floor 0.25
edges = imdilate(G > t, strel('disk', max(1, round(s))));

hard = cleaned & ~edges;
M = min(max(imgaussfilt(double(hard), max(0.5, 4*s)), 0), 1);
stages = struct('raw', raw, 'cleaned', cleaned, 'edges', edges, 'hard', hard);
end
