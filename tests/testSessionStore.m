classdef testSessionStore < matlab.unittest.TestCase
    properties
        Dir
    end
    methods (TestMethodSetup)
        function makeDir(tc)
            tc.Dir = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
        end
    end
    methods (Test)
        function savesAllFiles(tc)
            store = booth.SessionStore(fullfile(tc.Dir, 'out'));
            d = store.saveSession(sampleSession(tc.Dir));
            expected = [{'strip.png', 'animation.gif', 'meta.json'}, ...
                arrayfun(@(k) sprintf('raw_%d.jpg', k), 1:4, 'UniformOutput', false), ...
                arrayfun(@(k) sprintf('photo_%d.png', k), 1:4, 'UniformOutput', false)];
            for k = 1:numel(expected)
                tc.verifyTrue(isfile(fullfile(d, expected{k})), expected{k});
            end
            meta = jsondecode(fileread(fullfile(d, 'meta.json')));
            tc.verifyEqual(meta.frame, 'Test');
        end
        function listsNewestFirstWithoutCollisions(tc)
            store = booth.SessionStore(fullfile(tc.Dir, 'out'));
            d1 = store.saveSession(sampleSession(tc.Dir));
            d2 = store.saveSession(sampleSession(tc.Dir));
            tc.verifyNotEqual(d1, d2);
            list = store.listSessions();
            tc.verifyNumElements(list, 2);
            tc.verifyEqual(list(1).folder, d2);
            tc.verifyTrue(isfile(list(1).stripPath));
        end
        function emptyStoreListsNothing(tc)
            store = booth.SessionStore(fullfile(tc.Dir, 'empty'));
            tc.verifyEmpty(store.listSessions());
        end
    end
end

function s = sampleSession(tmp)
photos = arrayfun(@(k) ones(60, 80, 3) * k / 5, 1:4, 'UniformOutput', false);
rawPath = fullfile(tmp, 'raw_src.jpg');
imwrite(ones(60, 80, 3) * 0.5, rawPath);
s = struct('strip', ones(200, 100, 3) * 0.7, 'photos', {photos}, ...
    'raws', {{rawPath, ones(60, 80, 3), rawPath, ones(60, 80, 3)}}, ...
    'meta', struct('frame', 'Test', 'tone', 'bw', 'smoothness', 40, 'autoLight', true), ...
    'gifDelay', 0.6, 'gifLongSide', 80);
end
