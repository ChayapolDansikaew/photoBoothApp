classdef testFlashSkinSmooth < matlab.unittest.TestCase
    methods (Test)
        function identicalPairReturnsInput(tc)
            % Same photo twice: detail = Y ./ base, so base .* detail is Y.
            img = im2uint8(synthFace(120, 0.03));
            out = imgproc.flashSkinSmooth(img, img);
            tc.verifyEqual(out, im2double(img), 'AbsTol', 1e-6);
        end
        function removesAmbientNoiseKeepsTexture(tc)
            % Result should be the ambient photo as if it had no noise:
            % ambient brightness, fine texture taken from the clean flash.
            [ambient, flash, cleanY] = flashPair();
            out = imgproc.flashSkinSmooth(ambient, flash);
            in = 11:150;   % skip borders (filter padding)
            err = lumaOf(out) - cleanY;
            noise = lumaOf(ambient) - cleanY;
            tc.verifyLessThan(rmsOf(err(in, in)), 0.5 * rmsOf(noise(in, in)));
        end
        function keepsAmbientColor(tc)
            % Flash light is cooler; the result keeps the ambient colors.
            [ambient, flash] = flashPair();
            out = imgproc.flashSkinSmooth(ambient, flash);
            tc.verifyEqual(chromaOf(out), chromaOf(ambient), 'AbsTol', 1e-6);
        end
        function resizesFlashToAmbient(tc)
            [ambient, flash] = flashPair();
            out = imgproc.flashSkinSmooth(ambient, imresize(flash, 1.5));
            tc.verifySize(out, size(ambient));
        end
    end
end

function [ambient, flash, cleanY] = flashPair()
%FLASHPAIR 160x160 skin patch with fine vertical texture (period 8 px).
% ambient: dim, warm and noisy (no flash). flash: brighter, cooler, clean.
% cleanY: luma of the ambient photo without its noise.
n = 160;
L = repmat(1 + 0.1 * sin(2*pi*(1:n)/8), n, 1);
skin = reshape([224 172 138] / 255, 1, 1, 3);
ambientClean = 0.7 * reshape([1.0 0.9 0.75], 1, 1, 3) .* skin .* L;
flash = reshape([0.95 1.0 1.1], 1, 1, 3) .* skin .* L;
rs = RandStream('mt19937ar', 'Seed', 7);
ambient = ambientClean + 0.03 * randn(rs, size(ambientClean));
cleanY = lumaOf(ambientClean);
end

function c = chromaOf(img)
yiq = rgb2ntsc(im2double(img));
c = yiq(:,:,2:3);
end

function r = rmsOf(x)
r = sqrt(mean(x(:).^2));
end
