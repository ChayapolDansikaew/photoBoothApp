classdef testRestoreClass < matlab.unittest.TestCase
    methods (Test)
        function clampsAndCastsToUint8(tc)
            out = imgproc.restoreClass([-0.5 0.5 1.5], 'uint8');
            tc.verifyClass(out, 'uint8');
            tc.verifyEqual(out, uint8([0 128 255]));
        end
        function keepsDouble(tc)
            out = imgproc.restoreClass([-1 0.25 2], 'double');
            tc.verifyClass(out, 'double');
            tc.verifyEqual(out, [0 0.25 1]);
        end
        function castsSingle(tc)
            tc.verifyClass(imgproc.restoreClass(0.5, 'single'), 'single');
        end
    end
end
