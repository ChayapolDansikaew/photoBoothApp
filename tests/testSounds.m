classdef testSounds < matlab.unittest.TestCase
    methods (Test)
        function wavesAreValidAudio(tc)
            waves = {booth.Sounds.beepWave(), booth.Sounds.beepWave(1320), booth.Sounds.shutterWave()};
            for k = 1:numel(waves)
                w = waves{k};
                tc.verifyTrue(iscolumn(w));
                tc.verifyNotEmpty(w);
                tc.verifyLessThanOrEqual(max(abs(w)), 1);
            end
        end
        function playDoesNotThrowWithoutAudioDevice(tc)
            booth.Sounds.beep();
            booth.Sounds.shutter();
            tc.verifyTrue(true);
        end
    end
end
