classdef testLoadFrames < matlab.unittest.TestCase
    properties
        Dir
    end
    methods (TestMethodSetup)
        function makeDir(tc)
            tc.Dir = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
        end
    end
    methods (Test)
        function loadsFrameWithMeta(tc)
            writeFrame(tc.Dir, 'cute', 4, '{"name":"Cute","tone":"pastel"}');
            frames = booth.loadFrames(tc.Dir);
            tc.verifyNumElements(frames, 1);
            tc.verifyEqual(frames.name, 'Cute');
            tc.verifyEqual(frames.tone, 'pastel');
            tc.verifySize(frames.slots, [4 4]);
            tc.verifySize(frames.rgb, [400 200 3]);
        end
        function defaultsWithoutJson(tc)
            writeFrame(tc.Dir, 'plain', 4, '');
            frames = booth.loadFrames(tc.Dir);
            tc.verifyEqual(frames.name, 'plain');
            tc.verifyEqual(frames.tone, 'bw');
        end
        function skipsBadFrameKeepsGood(tc)
            writeFrame(tc.Dir, 'good', 4, '');
            writeFrame(tc.Dir, 'bad', 3, '');
            [frames, problems] = tc.verifyWarning(@() booth.loadFrames(tc.Dir), 'booth:frameSkipped');
            tc.verifyEqual({frames.name}, {'good'});
            tc.verifyNumElements(problems, 1);
        end
        function unknownToneFallsBack(tc)
            writeFrame(tc.Dir, 'odd', 4, '{"tone":"neon"}');
            frames = tc.verifyWarning(@() booth.loadFrames(tc.Dir), 'booth:unknownTone');
            tc.verifyEqual(frames.tone, 'bw');
        end
        function emptyFolderUsesDefault(tc)
            frames = tc.verifyWarning(@() booth.loadFrames(tc.Dir), 'booth:noFrames');
            tc.verifyEqual(frames.name, 'Plain White');
            tc.verifySize(frames.slots, [4 4]);
            tc.verifySize(frames.rgb, [1800 600 3]);
        end
    end
end

function writeFrame(folder, base, nSlots, json)
h = 400; w = 200;
rects = [10 10 180 85; 10 105 180 85; 10 200 180 85; 10 295 180 85];
rgb = repmat(reshape([0.9 0.3 0.4], 1, 1, 3), h, w);
imwrite(rgb, fullfile(folder, [base '.png']), 'Alpha', makeAlpha(h, w, rects(1:nSlots,:)));
if ~isempty(json)
    fid = fopen(fullfile(folder, [base '.json']), 'w');
    fprintf(fid, '%s', json);
    fclose(fid);
end
end
