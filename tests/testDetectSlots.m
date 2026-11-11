classdef testDetectSlots < matlab.unittest.TestCase
    methods (Test)
        function stripOrderTopToBottom(tc)
            rects = [41 41 520 390; 41 471 520 390; 41 901 520 390; 41 1331 520 390];
            tc.verifyEqual(booth.detectSlots(makeAlpha(1800, 600, rects)), rects);
        end
        function gridOrderRowMajor(tc)
            rects = [40 40 540 720; 620 40 540 720; 40 800 540 720; 620 800 540 720];
            tc.verifyEqual(booth.detectSlots(makeAlpha(1800, 1200, rects)), rects);
        end
        function slightlyOffsetRowStillLeftToRight(tc)
            rects = [20 65 200 300; 260 50 200 300; 20 450 200 300; 260 450 200 300];
            tc.verifyEqual(booth.detectSlots(makeAlpha(800, 500, rects)), rects);
        end
        function ignoresTinySpecks(tc)
            rects = [41 41 520 390; 41 471 520 390; 41 901 520 390; 41 1331 520 390];
            alpha = makeAlpha(1800, 600, [rects; 5 5 3 3]);
            tc.verifyEqual(booth.detectSlots(alpha), rects);
        end
        function wrongCountErrors(tc)
            alpha = makeAlpha(800, 500, [20 50 200 300; 260 50 200 300; 20 450 200 300]);
            tc.verifyError(@() booth.detectSlots(alpha), 'booth:badSlotCount');
        end
    end
end
