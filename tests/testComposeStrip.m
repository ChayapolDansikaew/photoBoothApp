classdef testComposeStrip < matlab.unittest.TestCase
    methods (Test)
        function placesPhotosInSlotsUnderFrame(tc)
            rects = [10 10 180 85; 10 105 180 85; 10 200 180 85; 10 295 180 85];
            frame = synthFrame(400, 200, rects);
            colors = [1 0 0; 0 1 0; 0 0 1; 1 1 0];
            photos = arrayfun(@(k) repmat(reshape(colors(k,:), 1, 1, 3), 300, 450), ...
                1:4, 'UniformOutput', false);
            out = booth.composeStrip(frame, photos);
            tc.verifySize(out, [400 200 3]);
            for k = 1:4
                r = rects(k,:);
                px = squeeze(out(r(2) + round(r(4)/2), r(1) + round(r(3)/2), :))';
                tc.verifyEqual(px, colors(k,:), 'AbsTol', 1e-3);
            end
            tc.verifyEqual(squeeze(out(2, 2, :))', [0.5 0.2 0.8], 'AbsTol', 1e-9);
        end
        function cropToAspectCentersWideImage(tc)
            img = zeros(100, 200, 3);
            img(:, 51:150, :) = 1;
            out = booth.cropToAspect(img, 1);
            tc.verifySize(out, [100 100 3]);
            tc.verifyEqual(min(out(:)), 1);
        end
        function cropToAspectTallTarget(tc)
            tc.verifySize(booth.cropToAspect(zeros(100, 200, 3), 0.5), [100 50 3]);
            tc.verifySize(booth.cropToAspect(zeros(200, 100, 3), 2), [50 100 3]);
        end
    end
end
