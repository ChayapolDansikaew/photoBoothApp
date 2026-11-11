classdef testPhotoboothApp < matlab.unittest.TestCase
    properties
        Dir
    end
    methods (TestMethodSetup)
        function makeDir(tc)
            tc.Dir = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
        end
    end
    methods (Test)
        function fullBoothFlowWithRetakeAndGallery(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'mock';
            cfg.outputDir = fullfile(tc.Dir, 'out');
            cfg.workingLongSide = 400;
            cfg.reviewLongSide = 200;

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false);
            tc.addTeardown(@() delete(app));

            tc.verifyEqual(app.Screen, 'idle');
            app.goToChooseFrame();
            tc.verifyEqual(app.Screen, 'chooseFrame');
            app.selectFrame(min(2, numel(app.Frames)));

            app.captureAllNow();
            tc.verifyEqual(app.Screen, 'review');
            tc.verifyNumElements(app.RawFiles, 4);

            % Adjust beauty controls and retake slot 2
            app.setSmoothness(75);
            tc.verifyEqual(app.Smoothness, 75);
            app.setAutoLight(false);
            tc.verifyFalse(app.AutoLight);
            app.setAutoLight(true);
            app.setComparing(true);
            app.setComparing(false);

            app.retakeSlotNow(2);
            tc.verifyEqual(app.Screen, 'review');

            % Complete review -> saves session and transitions to result
            app.finishReview();
            tc.verifyEqual(app.Screen, 'result');
            list = app.Store.listSessions();
            tc.verifyNumElements(list, 1);
            tc.verifyTrue(isfile(fullfile(list(1).folder, 'strip.png')));
            tc.verifyTrue(isfile(fullfile(list(1).folder, 'animation.gif')));
            meta = jsondecode(fileread(fullfile(list(1).folder, 'meta.json')));
            tc.verifyEqual(meta.smoothness, 75);

            % Gallery and idle timeout
            app.goToGallery();
            tc.verifyEqual(app.Screen, 'gallery');
            app.onIdleTimeout();
            tc.verifyEqual(app.Screen, 'idle');
        end

        function cameraFailureShowsBannerAndFallbackWorks(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'gphoto';
            cfg.bridgePort = 5599;   % nothing listening
            cfg.outputDir = fullfile(tc.Dir, 'out');

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false, 'ConnectTimeout', 0.3);
            tc.addTeardown(@() delete(app));

            tc.verifyTrue(app.CameraBannerVisible);
            app.useMockCamera();
            tc.verifyFalse(app.CameraBannerVisible);
            tc.verifyTrue(app.Camera.isReady());
            tc.verifyTrue(app.IsDemo);
        end

        function noSilentMockFallbackWhenCameraMissing(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'gphoto';
            cfg.bridgePort = 5599;   % nothing listening
            cfg.outputDir = fullfile(tc.Dir, 'out');

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false, 'ConnectTimeout', 0.3);
            tc.addTeardown(@() delete(app));

            app.goToChooseFrame();
            tc.verifyEqual(app.Screen, 'idle', 'Visitors must not enter the flow without a camera.');
            tc.verifyError(@() app.captureAllNow(), 'Photobooth:cameraNotReady');
            tc.verifyFalse(app.IsDemo, 'Capture must not silently switch to MockCamera.');
            tc.verifyEmpty(app.Store.listSessions());
        end

        function idleResetsVisitorStateAndFlagsDemoSessions(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'mock';
            cfg.outputDir = fullfile(tc.Dir, 'out');
            cfg.workingLongSide = 300;
            cfg.reviewLongSide = 160;

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false);
            tc.addTeardown(@() delete(app));

            app.goToChooseFrame();
            app.captureAllNow();
            app.selectReviewPhoto(3);
            app.setSmoothness(85);
            app.setComparing(true);
            tc.verifyTrue(app.Comparing);
            app.setComparing(false);
            app.finishReview();
            tc.verifyFalse(app.IsBusy);

            list = app.Store.listSessions();
            meta = jsondecode(fileread(fullfile(list(1).folder, 'meta.json')));
            tc.verifyTrue(meta.demo);

            app.goToIdle();
            tc.verifyEqual(app.Smoothness, cfg.defaultSmoothness);
            tc.verifyFalse(app.Comparing);
            tc.verifyEqual(app.SelectedPhotoIdx, 1);
        end

        function cancelKeepsFrameAndLostCameraStopsShoot(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'mock';
            cfg.outputDir = fullfile(tc.Dir, 'out');

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false);
            tc.addTeardown(@() delete(app));

            app.goToChooseFrame();
            app.selectFrame(min(2, numel(app.Frames)));
            chosen = app.SelectedFrameIdx;
            app.startShooting();
            tc.verifyEqual(app.Screen, 'shooting');
            app.cancelShooting();
            tc.verifyEqual(app.Screen, 'chooseFrame', 'Cancel returns to frame choice, not idle.');
            tc.verifyEqual(app.SelectedFrameIdx, chosen);
            tc.verifyFalse(app.IsShooting);

            app.Camera.stop();            % camera drops out after the visitor got in
            app.startShooting();
            tc.verifyEqual(app.Screen, 'idle');
            tc.verifyTrue(app.CameraBannerVisible);
        end

        function adjustingSmoothnessLeavesCompareAndNewRoundResets(tc)
            cfg = booth.loadConfig();
            cfg.camera = 'mock';
            cfg.outputDir = fullfile(tc.Dir, 'out');
            cfg.workingLongSide = 300;
            cfg.reviewLongSide = 160;

            app = PhotoboothApp(cfg, 'Visible', false, 'AutoTimers', false);
            tc.addTeardown(@() delete(app));

            app.goToChooseFrame();
            app.captureAllNow();
            app.setComparing(true);
            app.setSmoothness(app.SmoothPresets(3));
            tc.verifyFalse(app.Comparing, 'Changing smoothness must show the adjusted photo.');
            tc.verifyEqual(app.Smoothness, app.SmoothPresets(3));

            app.setComparing(true);
            app.setAutoLight(false);
            app.finishReview();
            tc.verifyEqual(app.Screen, 'result');

            app.startNewRound();
            tc.verifyEqual(app.Screen, 'chooseFrame');
            tc.verifyEqual(app.Smoothness, cfg.defaultSmoothness);
            tc.verifyFalse(app.Comparing);
            tc.verifyTrue(app.AutoLight);
        end
    end
end
