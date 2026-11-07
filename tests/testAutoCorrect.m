classdef testAutoCorrect < matlab.unittest.TestCase
    methods (Test)
        function removesColorCast(tc)
            g = repmat(linspace(0.2, 0.8, 64), 64, 1);
            img = cat(3, g * 0.8, g * 0.9, g * 1.15);   % blue cast on grays
            before = channelSpread(img);
            out = imgproc.autoCorrect(img);
            tc.verifyLessThan(channelSpread(out), 0.5 * before);
        end
        function preservesSizeAndClass(tc)
            img = im2uint8(synthFace(48, 0.02));
            out = imgproc.autoCorrect(img);
            tc.verifyClass(out, 'uint8');
            tc.verifySize(out, size(img));
        end
        function blackImageDoesNotError(tc)
            tc.verifySize(imgproc.autoCorrect(zeros(16, 16, 3)), [16 16 3]);
        end
    end
end

function s = channelSpread(img)
m = squeeze(mean(img, [1 2]));
s = max(m) - min(m);
end
