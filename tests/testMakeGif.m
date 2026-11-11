classdef testMakeGif < matlab.unittest.TestCase
    methods (Test)
        function writesLoopingGif(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            p = fullfile(d, 'a.gif');
            photos = arrayfun(@(k) ones(120, 160, 3) * k / 5, 1:4, 'UniformOutput', false);
            booth.makeGif(photos, p, 0.6, 80);
            info = imfinfo(p);
            tc.verifyNumElements(info, 4);
            tc.verifyEqual(double(info(1).Width), 80);
        end
    end
end
