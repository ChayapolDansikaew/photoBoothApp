function makeSampleFrames(outDir)
%MAKESAMPLEFRAMES Write two example frames (PNG + JSON) that demonstrate
% the frame format. Real frames are designed by hand in any image editor:
% an RGBA PNG with exactly 4 fully transparent windows.
if nargin < 1
    outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'frames');
end
if ~isfolder(outDir), mkdir(outDir); end

% 1) Classic 2x6" strip (600x1800), 4x1, cream with a dark footer line.
rgb = repmat(reshape([0.97 0.95 0.90], 1, 1, 3), 1800, 600);
rgb(1740:1765, 60:540, :) = 0.15;
rects = [41 41 520 390; 41 471 520 390; 41 901 520 390; 41 1331 520 390];
writeFrame(outDir, 'classic_strip', rgb, rects, 'Classic B&W', 'bw');

% 2) 4x6" grid (1200x1800), 2x2, pastel pink with a footer band.
rgb = repmat(reshape([1.00 0.86 0.90], 1, 1, 3), 1800, 1200);
rgb(1600:1700, 100:1100, :) = repmat(reshape([0.98 0.62 0.70], 1, 1, 3), 101, 1001);
rects = [40 40 540 720; 620 40 540 720; 40 800 540 720; 620 800 540 720];
writeFrame(outDir, 'pastel_grid', rgb, rects, 'Pastel Dream', 'pastel');
end

function writeFrame(outDir, base, rgb, rects, name, tone)
[h, w, ~] = size(rgb);
alpha = ones(h, w);
for k = 1:size(rects, 1)
    r = rects(k,:);
    alpha(r(2):r(2)+r(4)-1, r(1):r(1)+r(3)-1) = 0;
end
imwrite(rgb, fullfile(outDir, [base '.png']), 'Alpha', alpha);
fid = fopen(fullfile(outDir, [base '.json']), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(struct('name', name, 'tone', tone)));
fclose(fid);
end
