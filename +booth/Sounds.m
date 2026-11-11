classdef Sounds
    %SOUNDS Synthesized booth sounds (no audio files needed).
    %   booth.Sounds.beep()       countdown tick (880 Hz)
    %   booth.Sounds.finalBeep()  last tick (1320 Hz)
    %   booth.Sounds.shutter()    camera shutter
    properties (Constant)
        Fs = 44100
    end
    methods (Static)
        function y = beepWave(freq)
            if nargin < 1, freq = 880; end
            fs = booth.Sounds.Fs;
            dur = 0.15;
            t = (0:round(dur * fs) - 1)' / fs;
            env = min(min(1, t / 0.005), (dur - t) / 0.03);   % 5 ms attack, 30 ms release
            y = 0.3 * sin(2 * pi * freq * t) .* max(env, 0);
        end
        function y = shutterWave()
            fs = booth.Sounds.Fs;
            rs = RandStream('mt19937ar', 'Seed', 7);
            n1 = round(0.012 * fs);
            n2 = round(0.06 * fs);
            click = randn(rs, n1, 1) .* exp(-(0:n1-1)' / (0.002 * fs));
            body = randn(rs, n2, 1) .* exp(-(0:n2-1)' / (0.015 * fs));
            y = [click; zeros(round(0.03 * fs), 1); body];
            y = 0.5 * y / max(abs(y));
        end
        function play(y)
            try
                sound(y, booth.Sounds.Fs);
            catch
                % no audio device: stay silent rather than crash the booth
            end
        end
        function beep()
            booth.Sounds.play(booth.Sounds.beepWave());
        end
        function finalBeep()
            booth.Sounds.play(booth.Sounds.beepWave(1320));
        end
        function shutter()
            booth.Sounds.play(booth.Sounds.shutterWave());
        end
    end
end
