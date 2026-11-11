classdef testSkinMask < matlab.unittest.TestCase
    methods (Test)
        function findsFaceNotBackground(tc)
            [img, inside, bg] = synthFace(400, 0.03);
            M = imgproc.skinMask(img);
            tc.verifyGreaterThan(mean(M(inside)), 0.8);
            tc.verifyLessThan(mean(M(bg)), 0.05);
        end
        function maskIsSoftAndBounded(tc)
            M = imgproc.skinMask(synthFace(200));
            tc.verifySize(M, [200 200]);
            tc.verifyGreaterThanOrEqual(min(M(:)), 0);
            tc.verifyLessThanOrEqual(max(M(:)), 1);
        end
        function excludesStrongEdges(tc)
            [img, c] = synthSkinStep(400);
            [M, st] = imgproc.skinMask(img);
            tc.verifyTrue(all(st.edges(200, c:c+1)));
            tc.verifyLessThan(M(200, c), 0.5);
            tc.verifyGreaterThan(M(200, 50), 0.9);
        end
        function returnsStages(tc)
            [~, st] = imgproc.skinMask(synthFace(100));
            tc.verifyTrue(all(isfield(st, {'raw', 'cleaned', 'edges', 'hard'})));
        end
    end
end
