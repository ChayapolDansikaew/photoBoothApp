classdef testCoreFlow < matlab.unittest.TestCase
    methods (Test)
        function rawToSavedStrip(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            frame = booth.defaultFrame();
            raws = arrayfun(@(k) im2uint8(imresize(synthFace(450, 0.03), [450 600])), ...
                1:4, 'UniformOutput', false);
            photos = cell(1, 4);
            for k = 1:4
                prep = booth.preparePhoto(raws{k}, 400, true, true);
                tc.verifyEqual(max(size(prep.I, [1 2])), 400);
                photos{k} = booth.renderPhoto(prep, 40, 'warmFilm', 'final');
            end
            strip = booth.composeStrip(frame, photos);
            store = booth.SessionStore(fullfile(d, 'out'));
            store.saveSession(struct('strip', strip, 'photos', {photos}, 'raws', {raws}, ...
                'meta', struct('frame', frame.name, 'tone', 'warmFilm', 'smoothness', 40, 'autoLight', true), ...
                'gifDelay', 0.6, 'gifLongSide', 200));
            list = store.listSessions();
            tc.verifyNumElements(list, 1);
            tc.verifySize(imread(list(1).stripPath), [1800 600 3]);
        end
        function preparePhotoAcceptsFilePath(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            p = fullfile(d, 'r.jpg');
            imwrite(synthFace(300), p);
            prep = booth.preparePhoto(p, 150, false, false);
            tc.verifySize(prep.I, [150 150 3]);
        end
        function mirrorFlipsHorizontally(tc)
            img = zeros(10, 20, 3);
            img(:, 1:5, :) = 1;
            prep = booth.preparePhoto(img, 100, true, false);
            tc.verifyEqual(prep.I(5, end, 1), 1, 'AbsTol', 1e-9);
            tc.verifyEqual(prep.I(5, 1, 1), 0, 'AbsTol', 1e-9);
        end
    end
end
