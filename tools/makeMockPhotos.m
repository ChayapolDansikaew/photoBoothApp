function makeMockPhotos(outDir)
%MAKEMOCKPHOTOS Write 4 synthetic 450x600 portrait JPEGs to assets/mock/
% so MockCamera has distinct poses/backgrounds out of the box.
if nargin < 1
    outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'assets', 'mock');
end
if ~isfolder(outDir), mkdir(outDir); end

bgs = [0.20 0.40 0.78; 0.25 0.62 0.52; 0.72 0.36 0.52; 0.48 0.38 0.72];
shifts = [-35 -15; 25 -10; -20 20; 30 15];
h = 450; w = 600;
[X, Y] = meshgrid(1:w, 1:h);
skin = [224 172 138] / 255;

for idx = 1:4
    cx = w/2 + shifts(idx, 1);
    cy = h/2 + shifts(idx, 2);
    r = ((X - cx) / 115).^2 + ((Y - cy) / 155).^2;
    face = r <= 1;
    eyes = (((X - (cx - 40)).^2 + (Y - (cy - 25)).^2) <= 14^2) | ...
           (((X - (cx + 40)).^2 + (Y - (cy - 25)).^2) <= 14^2);
    smile = (abs(X - cx) <= 42) & (abs((Y - (cy + 45)) - 0.008*(X - cx).^2) <= 5);
    features = eyes | smile;

    img = zeros(h, w, 3);
    for c = 1:3
        ch = face * skin(c) + ~face * bgs(idx, c);
        ch(features) = 0.15;
        img(:,:,c) = ch;
    end
    imwrite(im2uint8(img), fullfile(outDir, sprintf('mock_%d.jpg', idx)), 'Quality', 95);
end
end
