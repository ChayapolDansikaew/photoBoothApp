function [img, inside, background] = synthFace(n, noiseSigma)
%SYNTHFACE n-by-n RGB double image: skin-colored ellipse on a blue
% background, with optional Gaussian noise (fixed seed). inside = ellipse
% interior well away from its boundary; background = far from the face.
if nargin < 2, noiseSigma = 0; end
[X, Y] = meshgrid(1:n, 1:n);
c = (n + 1) / 2;
r = ((X - c) / (0.3*n)).^2 + ((Y - c) / (0.4*n)).^2;
face = r <= 1;
inside = r <= 0.5;
background = r >= 2;
skin = [224 172 138] / 255;   % YCbCr ~ (174, 105, 153): inside skin range
bg = [0.2 0.4 0.8];           % Cb ~ 180: outside skin range
img = zeros(n, n, 3);
for k = 1:3
    img(:,:,k) = face * skin(k) + ~face * bg(k);
end
rs = RandStream('mt19937ar', 'Seed', 42);
img = min(max(img + noiseSigma * randn(rs, size(img)), 0), 1);
end
