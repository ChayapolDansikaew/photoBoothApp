classdef testSkinSmooth < matlab.unittest.TestCase
    methods (Test)
        function zeroAmountIsIdentity(tc)
            img = im2uint8(synthFace(120, 0.03));
            tc.verifyEqual(smoothAt(img, 0), img);
        end
        function reducesSkinNoise(tc)
            [img, inside] = synthFace(400, 0.03);
            out = smoothAt(img, 100);
            tc.verifyLessThan(varIn(out, inside), 0.5 * varIn(img, inside));
        end
        function keepsEdgesSharp(tc)
            img = synthSkinStep(400);
            before = edgeStep(img);
            tc.verifyGreaterThan(edgeStep(smoothAt(img, 100)), 0.8 * before);
            % sanity: the metric does detect blur
            tc.verifyLessThan(edgeStep(imgaussfilt(img, 4)), 0.5 * before);
        end
        function backgroundUntouched(tc)
            [img, ~, bg] = synthFace(400, 0.03);
            d = max(abs(smoothAt(img, 100) - img), [], 3);
            tc.verifyLessThan(mean(d(bg)), 0.01);
        end
        function keepsSkinColor(tc)
            % Only brightness (Y of YIQ) is smoothed; color (I, Q) must not
            % shift. 1000 px exercises the downscaled bilateral path used by
            % the final export. Values stay inside (0,1) so nothing clips.
            img = 0.25 + 0.5 * synthFace(1000, 0.03);
            out = smoothAt(img, 100);
            [yIn, cIn] = splitYIQ(img);
            [yOut, cOut] = splitYIQ(out);
            tc.assertGreaterThan(max(abs(yOut - yIn), [], 'all'), 0.01, ...
                'Skin should have been found and smoothed.');
            tc.verifyEqual(cOut, cIn, 'AbsTol', 1e-6);
        end
        function blendIsMonotonic(tc)
            [img, inside] = synthFace(300, 0.03);
            prep = imgproc.prepareSmoothing(img);
            v = arrayfun(@(a) varIn(imgproc.blendSmoothing(prep, a), inside), [0 50 100]);
            tc.verifyTrue(issorted(v, 'descend'));
        end
        function rejectsOutOfRange(tc)
            prep = imgproc.prepareSmoothing(synthFace(50));
            tc.verifyError(@() imgproc.blendSmoothing(prep, 150), ?MException);
        end
        function skinSmoothFiltersBrightnessOnly(tc)
            % imgproc.skinSmooth on its own: whole image, default settings.
            [face, inside] = synthFace(200, 0.03);
            img = im2uint8(0.25 + 0.5 * face);
            out = imgproc.skinSmooth(img);
            [~, cIn] = splitYIQ(img);
            [~, cOut] = splitYIQ(out);
            tc.verifyEqual(cOut, cIn, 'AbsTol', 1e-6);
            tc.verifyLessThan(varIn(out, inside), 0.5 * varIn(img, inside));
        end
    end
end

function out = smoothAt(img, amount)
out = imgproc.blendSmoothing(imgproc.prepareSmoothing(img), amount);
end

function v = varIn(img, mask)
L = lumaOf(img);
v = var(L(mask));
end

function [y, c] = splitYIQ(img)
yiq = rgb2ntsc(im2double(img));
y = yiq(:,:,1);
c = yiq(:,:,2:3);
end
