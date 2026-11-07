classdef testApplyTone < matlab.unittest.TestCase
    properties (TestParameter)
        tone = {'bw', 'warmFilm', 'pastel', 'vivid', 'cinematic', 'sepia'}
        mode = {'preview', 'final'}
    end
    methods (Test)
        function preservesSizeAndClass(tc, tone, mode)
            img = im2uint8(synthFace(64, 0.02));
            out = imgproc.applyTone(img, tone, mode);
            tc.verifyClass(out, 'uint8');
            tc.verifySize(out, size(img));
        end
        function bwIsGray(tc, mode)
            out = imgproc.applyTone(synthFace(64, 0.02), 'bw', mode);
            tc.verifyEqual(out(:,:,1), out(:,:,2));
            tc.verifyEqual(out(:,:,2), out(:,:,3));
        end
        function vividIncreasesSaturation(tc)
            img = synthFace(64);
            hsvIn = rgb2hsv(img);
            hsvOut = rgb2hsv(imgproc.applyTone(img, 'vivid', 'preview'));
            tc.verifyGreaterThan(mean(hsvOut(:,:,2), 'all'), mean(hsvIn(:,:,2), 'all'));
        end
        function warmFilmIsWarmer(tc)
            out = imgproc.applyTone(0.5 * ones(32, 32, 3), 'warmFilm', 'preview');
            tc.verifyGreaterThan(mean(out(:,:,1), 'all'), mean(out(:,:,3), 'all'));
        end
        function sepiaOrdersChannels(tc)
            out = imgproc.applyTone(0.5 * ones(8, 8, 3), 'sepia', 'preview');
            px = squeeze(out(4, 4, :));
            tc.verifyGreaterThan(px(1), px(2));
            tc.verifyGreaterThan(px(2), px(3));
        end
        function unknownToneFallsBackToBw(tc)
            img = synthFace(32);
            out = tc.verifyWarning(@() imgproc.applyTone(img, 'nope', 'preview'), 'imgproc:unknownTone');
            tc.verifyEqual(out, imgproc.applyTone(img, 'bw', 'preview'));
        end
        function toneNamesHasLabels(tc)
            [ids, labels] = imgproc.toneNames();
            tc.verifyEqual(ids, {'bw', 'warmFilm', 'pastel', 'vivid', 'cinematic', 'sepia'});
            tc.verifyNumElements(labels, numel(ids));
        end
    end
end
