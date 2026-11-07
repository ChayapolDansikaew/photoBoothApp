function out = applyTone(img, name, mode)
%APPLYTONE Apply a named color tone (see imgproc.toneNames).
% mode 'preview' = fast curves/matrices only (for live view);
% mode 'final'   = also adds grain / vignette / glow.
% Unknown names fall back to 'bw' with warning imgproc:unknownTone.
% Returns the same class as img.
arguments
    img
    name {mustBeTextScalar}
    mode {mustBeMember(mode, {'preview', 'final'})} = 'preview'
end
I = im2double(img);
if size(I, 3) == 1, I = repmat(I, 1, 1, 3); end
name = char(name);
if ~ismember(name, imgproc.toneNames())
    warning('imgproc:unknownTone', 'Unknown tone "%s"; using bw.', name);
    name = 'bw';
end
isFinal = strcmp(mode, 'final');
s = max(size(I, 1), size(I, 2)) / 1000;   % resolution scale for blur sizes

switch name
    case 'bw'
        g = sCurve(luma(I), 0.6);
        if isFinal, g = g + grain(size(g), 0.02); end
        out = repmat(g, 1, 1, 3);
    case 'warmFilm'
        out = 0.06 + 0.94 * I;                 % lift blacks (faded film)
        out(:,:,1) = out(:,:,1) * 1.06;
        out(:,:,3) = out(:,:,3) * 0.90;
        out = sCurve(out, 0.3);
        if isFinal, out = vignette(out + grain([size(out,1) size(out,2)], 0.015), 0.25); end
    case 'pastel'
        out = I .^ 0.85;                       % brighten
        g = luma(out);
        out = g + 0.75 * (out - g);            % desaturate
        out = 0.5 + 0.85 * (out - 0.5);        % lower contrast
        out(:,:,1) = out(:,:,1) + 0.03;        % pink tint
        out(:,:,3) = out(:,:,3) + 0.015;
        if isFinal                             % soft glow (screen blend, 25%)
            blur = imgaussfilt(min(max(out, 0), 1), max(1, 8*s));
            out = 1 - (1 - out) .* (1 - 0.25 * blur);
        end
    case 'vivid'
        g = luma(I);
        out = sCurve(g + 1.35 * (I - g), 0.4);
    case 'cinematic'                           % teal shadows, orange highlights
        L = luma(I);
        teal   = reshape([-0.05 0.02 0.06], 1, 1, 3);
        orange = reshape([ 0.08 0.03 -0.06], 1, 1, 3);
        out = I + (1 - L).^2 .* teal + L.^2 .* orange;
        if isFinal, out = vignette(out, 0.2); end
    case 'sepia'
        M = [0.393 0.769 0.189; 0.349 0.686 0.168; 0.272 0.534 0.131];
        out = reshape(reshape(I, [], 3) * M.', size(I));
        if isFinal, out = vignette(out + grain([size(out,1) size(out,2)], 0.015), 0.3); end
end
out = imgproc.restoreClass(out, class(img));
end

function L = luma(I)
L = 0.299*I(:,:,1) + 0.587*I(:,:,2) + 0.114*I(:,:,3);
end

function y = sCurve(x, k)
% Blend of identity and a cosine S-curve; monotonic for k in [0,1].
x = min(max(x, 0), 1);
y = (1 - k) * x + k * (0.5 - 0.5 * cos(pi * x));
end

function n = grain(sz, sigma)
n = sigma * randn(sz);
end

function out = vignette(out, strength)
[h, w, ~] = size(out);
[X, Y] = meshgrid(linspace(-1, 1, w), linspace(-1, 1, h));
out = out .* (1 - strength * (X.^2 + Y.^2) / 2);
end
