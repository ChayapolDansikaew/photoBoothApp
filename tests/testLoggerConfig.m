classdef testLoggerConfig < matlab.unittest.TestCase
    properties
        Dir
    end
    methods (TestMethodSetup)
        function makeDir(tc)
            tc.Dir = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
        end
    end
    methods (Test)
        function loggerAppendsLines(tc)
            p = fullfile(tc.Dir, 'logs', 'x.log');
            lg = booth.Logger(p);
            lg.info('hello %d', 1);
            lg.warn('careful');
            lg.err('boom');
            txt = fileread(p);
            tc.verifySubstring(txt, '[INFO] hello 1');
            tc.verifySubstring(txt, '[WARN] careful');
            tc.verifySubstring(txt, '[ERROR] boom');
        end
        function configDefaultsWhenMissing(tc)
            cfg = booth.loadConfig(fullfile(tc.Dir, 'none.json'));
            tc.verifyEqual(cfg.countdownSeconds, 3);
            tc.verifyEqual(cfg.camera, 'webcam');
            tc.verifyEqual(cfg.webcamIndex, 0);
            tc.verifyEqual(cfg.defaultSmoothness, 40);
        end
        function configOverridesAndWarnsUnknown(tc)
            p = fullfile(tc.Dir, 'c.json');
            fid = fopen(p, 'w');
            fprintf(fid, '{"camera":"mock","countdownSeconds":5,"bogus":1}');
            fclose(fid);
            cfg = tc.verifyWarning(@() booth.loadConfig(p), 'booth:unknownConfigKey');
            tc.verifyEqual(cfg.camera, 'mock');
            tc.verifyEqual(cfg.countdownSeconds, 5);
            tc.verifyEqual(cfg.gapSeconds, 3);
        end
        function repoConfigIsValid(tc)
            root = fileparts(which('runAllTests'));
            cfg = tc.verifyWarningFree(@() booth.loadConfig(fullfile(root, 'config.json')));
            tc.verifyEqual(cfg.bridgePort, 5555);
        end
    end
end
