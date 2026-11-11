classdef testDebugSkinPipeline < matlab.unittest.TestCase
    methods (Test)
        function drawsSixPanels(tc)
            fig = imgproc.debugSkinPipeline(synthFace(200, 0.02), 70, false);
            tc.addTeardown(@() close(fig));
            tc.verifyNumElements(findobj(fig, 'Type', 'axes'), 6);
        end
    end
end
