classdef PhotoboothApp < handle
    %PHOTOBOOTHAPP Fullscreen kiosk UI + state machine for MATLAB Photobooth.
    % Screens: 'idle' | 'gallery' | 'chooseFrame' | 'shooting' | 'review' | 'result'
    %
    % Layout is authored on a 1280x760 design canvas and scaled uniformly to
    % the window (see applyScale); runtime repositioning goes through place().
    %
    % Operator shortcuts (not shown to visitors):
    %   Ctrl+Shift+R  reconnect the real camera (webcam or DSLR, per config.camera)
    %   Ctrl+Shift+M  switch to demo mode (MockCamera, sample images) — idle/gallery only
    %   Ctrl+Shift+Q  quit the kiosk
    properties (SetAccess = private)
        Config struct
        RootDir (1,:) char
        Logger booth.Logger
        Store booth.SessionStore
        Frames struct
        SelectedFrameIdx (1,1) double = 1
        Camera = []
        Screen (1,:) char = 'idle'
        RawFiles (1,4) cell = {'', '', '', ''}
        ReviewPreps (1,4) cell = {[], [], [], []}
        SelectedPhotoIdx (1,1) double = 1
        Smoothness (1,1) double = 40
        AutoLight (1,1) logical = true
        Comparing (1,1) logical = false
        AdvancedOpen (1,1) logical = false
        RetakeTarget (1,1) double = 0
        CurrentShotIdx (1,1) double = 1
        LastStrip = []
        LastPhotos (1,4) cell = {[], [], [], []}
        CameraBannerVisible (1,1) logical = false
        SaveErrorVisible (1,1) logical = false
        AutoTimers (1,1) logical = true
        IsBusy (1,1) logical = false
        IsShooting (1,1) logical = false
        Scale (1,1) double = 1
    end
    properties (Dependent)
        IsDemo   % true when photos come from MockCamera instead of the real camera
    end
    properties (Access = private)
        Fig
        Root
        Panels (1,1) struct = struct()
        Widgets (1,1) struct = struct()
        PreviewTimer = []
        IdleTimer = []
        SlideTimer = []
        WarnTimer = []
        WarnRemaining (1,1) double = 0
        WarnLoss (1,:) char = ''
        SlideIdx (1,1) double = 1
        ConnectTimeout (1,1) double = 20   % cap; a crashed bridge fails sooner
        ShootToken (1,1) double = 0        % bumps on every shoot start/cancel
        PreviewFailures (1,1) double = 0
        MainAspect (1,1) double = 4/3
        LiveAspect (1,1) double = 3/2
        DemoCache = []
        Palette (1,1) struct = PhotoboothApp.studioPalette()
    end
    properties (Constant)
        SmoothPresets = [0 40 80]
        SmoothPresetLabels = {'ธรรมชาติ', 'เนียน', 'เนียนสุด'}
    end
    properties (Constant, Access = private)
        StageSize = [1280 760]      % design canvas
        WarnSeconds = 15            % grace period before unsaved work is abandoned
        MaxFrameButtons = 4         % frame tiles: 2 columns x 2 rows
        MaxPreviewFailures = 10     % ~0.8 s of failed live frames => camera lost
        MainImageBox = [540 250 700 370]
        LiveImageBox = [40 40 880 540]
        StripBox = [40 40 560 590]  % result strip area; print slot sits on its top edge
    end

    methods (Static)
        function p = studioPalette()
            %STUDIOPALETTE Seoul Self-Studio Minimal tokens (see DESIGN.md).
            p = struct( ...
                'terracotta',     [0.78 0.35 0.23], ... % #c85a3b  one primary CTA per screen, countdown
                'terracottaDeep', [0.66 0.27 0.16], ... % #a8462a  selection outline
                'sage',           [0.31 0.43 0.34], ... % #4f6d57  success text (5.1:1 on ivory)
                'ivory',          [0.97 0.95 0.93], ... % #f7f3ec  layer 0 studio wall
                'linen',          [0.93 0.90 0.86], ... % #ede6db  layer 1 secondary controls
                'sand',           [0.86 0.82 0.76], ... % #dcd2c3  layer 2 photo canvas
                'espresso',       [0.14 0.12 0.11], ... % #231f1d  primary ink, selected state
                'taupe',          [0.43 0.40 0.37], ... % #6e655f  secondary ink
                'paper',          [1.00 1.00 1.00], ... % #ffffff  ink on terracotta/rust/espresso
                'rust',           [0.62 0.20 0.16], ... % #9e3328  hardware alerts
                'font',           'Segoe UI');
        end

        function img = placeholderImage(h, w)
            %PLACEHOLDERIMAGE Sand Border fill for empty photo slots.
            sand = uint8([220 210 195]);
            img = repmat(reshape(sand, 1, 1, 3), h, w, 1);
        end

        function label = toneLabel(toneId)
            %TONELABEL Visitor-facing Thai name for a tone id.
            [ids, labels] = imgproc.toneNames();
            hit = strcmp(ids, toneId);
            if any(hit), label = labels{hit}; else, label = toneId; end
        end
    end

    methods
        function obj = PhotoboothApp(cfg, opts)
            arguments
                cfg struct = booth.loadConfig()
                opts.Visible (1,1) logical = true
                opts.AutoTimers (1,1) logical = true
                opts.ConnectTimeout (1,1) double = 20
                opts.Fullscreen = []
            end
            obj.RootDir = fileparts(mfilename('fullpath'));
            obj.Config = cfg;
            obj.Smoothness = cfg.defaultSmoothness;
            obj.AutoTimers = opts.AutoTimers;
            obj.ConnectTimeout = opts.ConnectTimeout;
            obj.DemoCache = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            fullscreen = opts.Fullscreen;
            if isempty(fullscreen), fullscreen = opts.Visible && opts.AutoTimers; end

            logPath = fullfile(obj.RootDir, 'logs', 'photobooth.log');
            obj.Logger = booth.Logger(logPath);
            outDir = cfg.outputDir;
            if ~ startsWith(outDir, {'/', '\'}) && (numel(outDir) < 2 || outDir(2) ~= ':')
                outDir = fullfile(obj.RootDir, outDir);
            end
            obj.Store = booth.SessionStore(outDir);
            [obj.Frames, problems] = booth.loadFrames(fullfile(obj.RootDir, 'frames'));
            for k = 1:numel(problems)
                obj.Logger.warn('%s', problems{k});
            end
            if numel(obj.Frames) > obj.MaxFrameButtons
                obj.Logger.warn('%d frames found; only the first %d are offered.', ...
                    numel(obj.Frames), obj.MaxFrameButtons);
            end

            obj.buildUI(opts.Visible, logical(fullscreen));
            obj.initCamera();
            obj.goToIdle();
        end

        function delete(obj)
            obj.stopAllTimers();
            if ~isempty(obj.Camera)
                try obj.Camera.stop(); catch, end
            end
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                delete(obj.Fig);
            end
        end

        function tf = get.IsDemo(obj)
            tf = ~isempty(obj.Camera) && isa(obj.Camera, 'camera.MockCamera');
        end

        function goToIdle(obj)
            obj.stopAllTimers();
            obj.resetSession();
            obj.hideOverlay('WarnOverlay');
            obj.showScreen('idle');
            obj.refreshIdleSlide();
            if obj.AutoTimers
                obj.SlideTimer = timer('ExecutionMode', 'fixedRate', 'Period', 4.0, ...
                    'TimerFcn', @(~,~) obj.refreshIdleSlide());
                start(obj.SlideTimer);
            end
        end

        function goToGallery(obj)
            obj.stopAllTimers();
            obj.showScreen('gallery');
            obj.refreshGallery();
            obj.restartIdleTimer();
        end

        function goToChooseFrame(obj)
            if obj.IsBusy || obj.IsShooting, return; end
            if ~obj.cameraIsReady()
                obj.setCameraBanner(true, '');
                obj.pulseBanner();
                return;
            end
            obj.stopAllTimers();
            obj.showScreen('chooseFrame');
            obj.refreshFrameTiles();
            obj.selectFrame(obj.SelectedFrameIdx);
            obj.startPreviewLoop();
            obj.restartIdleTimer();
        end

        function startNewRound(obj)
            %STARTNEWROUND "ถ่ายอีกครั้ง" from Result: same frame, fresh settings.
            if obj.IsBusy || obj.IsShooting, return; end
            obj.resetSession();
            obj.goToChooseFrame();
        end

        function selectFrame(obj, idx)
            obj.SelectedFrameIdx = max(1, min(idx, numel(obj.Frames)));
            n = numel(obj.Widgets.FrameTiles);
            for k = 1:n
                if k == obj.SelectedFrameIdx
                    obj.Widgets.FrameTileLabels(k).FontWeight = 'bold';
                else
                    obj.Widgets.FrameTileLabels(k).FontWeight = 'normal';
                end
            end
            if obj.SelectedFrameIdx <= n
                p = obj.designPos(obj.Widgets.FrameTiles(obj.SelectedFrameIdx));
                obj.place(obj.Widgets.FrameSelection, p + [-5 -5 10 10]);
                obj.Widgets.FrameSelection.Visible = 'on';
            end
            obj.updateLivePreview();
            obj.restartIdleTimer();
        end

        function startShooting(obj)
            if obj.IsBusy || obj.IsShooting, return; end
            if ~obj.cameraIsReady()
                obj.goToIdle();
                obj.setCameraBanner(true, '');
                return;
            end
            obj.stopAllTimers();
            obj.RetakeTarget = 0;
            obj.RawFiles = {'', '', '', ''};
            for k = 1:4
                obj.Widgets.ShootThumbs(k).ImageSource = PhotoboothApp.placeholderImage(90, 120);
            end
            obj.showScreen('shooting');
            obj.setShootStatus(1, 4, 1);
            if obj.AutoTimers
                obj.runShootSequence(1:4);
            end
        end

        function captureAllNow(obj)
            %CAPTUREALLNOW Synchronous 4-shot capture (used by tests and instant mode).
            if obj.IsBusy || obj.IsShooting, return; end
            obj.stopAllTimers();
            obj.RetakeTarget = 0;
            obj.showScreen('shooting');
            for k = 1:4
                obj.captureOneSlot(k);
            end
            obj.enterReview(true);
        end

        function startRetake(obj, slotIdx)
            if obj.IsBusy || obj.IsShooting, return; end
            if ~obj.cameraIsReady()
                obj.setCameraBanner(true, '');   % stay on Review; photos are kept
                obj.pulseBanner();
                return;
            end
            obj.stopAllTimers();
            obj.RetakeTarget = slotIdx;
            obj.showScreen('shooting');
            obj.setShootStatus(slotIdx, 1, 1);
            if obj.AutoTimers
                obj.runShootSequence(slotIdx);
            end
        end

        function retakeSlotNow(obj, slotIdx)
            if obj.IsBusy || obj.IsShooting, return; end
            obj.stopAllTimers();
            obj.RetakeTarget = slotIdx;
            obj.showScreen('shooting');
            obj.captureOneSlot(slotIdx);
            obj.prepareRetakenSlot(slotIdx);
            obj.enterReview(false);
        end

        function cancelShooting(obj)
            %CANCELSHOOTING Visitor exit from a running countdown. A retake goes
            % back to Review; a full shoot goes back to frame choice (frame kept).
            obj.ShootToken = obj.ShootToken + 1;   % any running sequence stops at its next check
            obj.IsShooting = false;
            obj.stopTimer('PreviewTimer');
            obj.hideShootOverlays();
            if obj.RetakeTarget > 0 && all(~cellfun(@isempty, obj.ReviewPreps))
                obj.RetakeTarget = 0;
                obj.showScreen('review');
                obj.refreshReviewDisplay();
                obj.restartIdleTimer();
            else
                obj.RetakeTarget = 0;
                obj.goToChooseFrame();
            end
        end

        function selectReviewPhoto(obj, idx)
            obj.SelectedPhotoIdx = max(1, min(4, idx));
            obj.refreshMainImage();
            obj.restartIdleTimer();
        end

        function setSmoothness(obj, val)
            % Adjusting smoothness always shows the result, so it leaves compare.
            obj.Smoothness = max(0, min(100, round(val)));
            obj.Comparing = false;
            obj.Widgets.SmoothSlider.Value = obj.Smoothness;
            obj.refreshReviewDisplay();
            obj.restartIdleTimer();
        end

        function setAutoLight(obj, tf)
            if obj.IsBusy, return; end
            obj.AutoLight = logical(tf);
            obj.updateAutoLightButton();
            if strcmp(obj.Screen, 'review')
                obj.stopTimer('IdleTimer');
                release = obj.beginBusy('กำลังปรับแสงใหม่', '');
                n = 0;
                for k = 1:4
                    if ~isempty(obj.RawFiles{k})
                        obj.setBusyProgress(sprintf('รูปที่ %d จาก 4', k), n / 4);
                        obj.ReviewPreps{k} = booth.preparePhoto( ...
                            obj.RawFiles{k}, obj.Config.reviewLongSide, obj.Config.mirror, obj.AutoLight);
                        n = n + 1;
                    end
                end
                clear release
                obj.refreshReviewDisplay();
            end
            obj.restartIdleTimer();
        end

        function setComparing(obj, tf)
            %SETCOMPARING Before (smoothness 0) vs after on the main image only.
            obj.Comparing = logical(tf);
            obj.refreshMainImage();
            obj.restartIdleTimer();
        end

        function toggleAdvanced(obj)
            obj.AdvancedOpen = ~obj.AdvancedOpen;
            obj.updateAdvanced();
            obj.restartIdleTimer();
        end

        function finishReview(obj)
            if obj.IsBusy || obj.IsShooting, return; end
            obj.stopAllTimers();
            obj.hideOverlay('WarnOverlay');
            obj.Comparing = false;
            f = obj.Frames(obj.SelectedFrameIdx);
            release = obj.beginBusy('กำลังแต่งรูปของคุณ', '');
            photos = cell(1, 4);
            for k = 1:4
                obj.setBusyProgress(sprintf('ปรับผิวและโทนสี รูปที่ %d จาก 4', k), (k - 1) / 5);
                prep = booth.preparePhoto( ...
                    obj.RawFiles{k}, obj.Config.workingLongSide, obj.Config.mirror, obj.AutoLight);
                photos{k} = booth.renderPhoto(prep, obj.Smoothness, f.tone, 'final');
            end
            obj.setBusyProgress('รวมรูปลงกรอบและบันทึก', 4 / 5);
            obj.LastPhotos = photos;
            obj.LastStrip = booth.composeStrip(f, photos);
            obj.trySaveCurrentSession();
            obj.setBusyProgress('เสร็จแล้ว', 1);
            clear release

            obj.showScreen('result');
            obj.Widgets.ResultStripImg.ImageSource = im2uint8(obj.LastStrip);
            obj.revealStrip();
            obj.restartIdleTimer();
        end

        function retrySave(obj)
            if obj.IsBusy, return; end
            release = obj.beginBusy('กำลังบันทึกอีกครั้ง', '');
            obj.trySaveCurrentSession();
            clear release
            obj.restartIdleTimer();
        end

        function retryCamera(obj)
            if obj.IsBusy || obj.IsShooting, return; end
            release = obj.beginBusy('กำลังเชื่อมต่อกล้อง', 'อาจใช้เวลาสักครู่');
            obj.initCamera();
            clear release
        end

        function useMockCamera(obj)
            %USEMOCKCAMERA Operator-only switch to demo mode (sample images).
            if ~isempty(obj.Camera)
                try obj.Camera.stop(); catch, end
            end
            obj.Camera = camera.MockCamera(fullfile(obj.RootDir, 'assets', 'mock'));
            obj.Camera.start();
            obj.PreviewFailures = 0;
            obj.setCameraBanner(false, '');
            obj.Logger.info('Operator switched to MockCamera (demo mode).');
        end

        function onIdleTimeout(obj)
            hasUnsaved = strcmp(obj.Screen, 'review') || ...
                (strcmp(obj.Screen, 'result') && obj.SaveErrorVisible);
            if hasUnsaved && obj.AutoTimers
                obj.showIdleWarning();
            elseif ismember(obj.Screen, {'chooseFrame', 'review', 'result', 'gallery'})
                obj.Logger.info('Idle timeout on %s -> returning to idle.', obj.Screen);
                obj.goToIdle();
            end
        end

        function stillHere(obj)
            %STILLHERE Visitor dismissed the idle warning.
            obj.stopTimer('WarnTimer');
            obj.hideOverlay('WarnOverlay');
            obj.restartIdleTimer();
        end
    end

    methods (Access = private)
        %% Camera
        function initCamera(obj)
            if ~isempty(obj.Camera)
                try obj.Camera.stop(); catch, end
            end
            obj.PreviewFailures = 0;
            try
                switch lower(obj.Config.camera)
                    case 'mock'
                        obj.Camera = camera.MockCamera(fullfile(obj.RootDir, 'assets', 'mock'));
                    case 'webcam'
                        obj.Camera = camera.WebcamCamera('Port', obj.Config.bridgePort, ...
                            'Device', obj.Config.webcamIndex, ...
                            'Resolution', obj.Config.webcamResolution(:)', ...
                            'PythonExe', obj.Config.pythonExe, ...
                            'AutoLaunch', obj.AutoTimers, 'ConnectTimeout', obj.ConnectTimeout);
                    otherwise
                        obj.Camera = camera.GPhotoCamera('Port', obj.Config.bridgePort, ...
                            'AutoLaunch', obj.AutoTimers, 'ConnectTimeout', obj.ConnectTimeout);
                end
                obj.Camera.start();
                obj.setCameraBanner(false, '');
                obj.Logger.info('Camera started (%s).', obj.Config.camera);
            catch err
                obj.Camera = [];
                obj.Logger.err('Camera start failed: %s', err.message);
                obj.setCameraBanner(true, '');
            end
        end

        function tf = cameraIsReady(obj)
            tf = ~isempty(obj.Camera) && obj.Camera.isReady();
        end

        function onCameraLost(obj)
            %ONCAMERALOST Live frames stopped arriving mid-visit: fail fast and say so.
            obj.PreviewFailures = 0;
            obj.Logger.err('Camera lost on %s (live preview failing).', obj.Screen);
            obj.stopTimer('PreviewTimer');
            if ismember(obj.Screen, {'chooseFrame', 'shooting'})
                obj.goToIdle();
            end
            obj.setCameraBanner(true, 'กล้องหลุดการเชื่อมต่อ — กรุณาแจ้งเจ้าหน้าที่ประจำบูธ');
        end

        function setCameraBanner(obj, vis, msg)
            obj.CameraBannerVisible = vis;
            obj.Widgets.CameraBanner.Visible = matlab.lang.OnOffSwitchState(vis);
            if isempty(msg)
                msg = 'กล้องยังไม่พร้อมถ่าย — กรุณาแจ้งเจ้าหน้าที่ประจำบูธ';
            end
            obj.Widgets.CameraBannerLabel.Text = msg;
            % START stays enabled so its label keeps full contrast; goToChooseFrame
            % refuses to enter the flow while the camera is not ready.
            btn = obj.Widgets.StartButton;
            if vis
                btn.Text = 'กล้องยังไม่พร้อม';
                btn.BackgroundColor = obj.Palette.sand;
                btn.FontColor = obj.Palette.espresso;
            else
                btn.Text = 'แตะเพื่อเริ่มถ่าย';
                btn.BackgroundColor = obj.Palette.terracotta;
                btn.FontColor = obj.Palette.paper;
            end
            obj.updateDemoTag();
        end

        function pulseBanner(obj)
            %PULSEBANNER Visible answer to a tap that can't proceed without a camera.
            if ~obj.AutoTimers || ~obj.CameraBannerVisible, return; end
            cb = obj.Widgets.CameraBanner;
            for k = 1:2
                cb.BackgroundColor = obj.Palette.terracottaDeep; drawnow; pause(0.12);
                cb.BackgroundColor = obj.Palette.rust;           drawnow; pause(0.12);
            end
        end

        function updateDemoTag(obj)
            % Never shown together with the camera banner (they share the top strip).
            show = obj.IsDemo && ~obj.CameraBannerVisible;
            obj.Widgets.DemoTag.Visible = matlab.lang.OnOffSwitchState(show);
        end

        function onKey(obj, evt)
            mods = evt.Modifier;
            if ~all(ismember({'control', 'shift'}, mods)), return; end
            switch lower(evt.Key)
                case 'r'
                    obj.retryCamera();
                case 'm'
                    % Only between visitors, so a session never mixes real and sample photos.
                    if ismember(obj.Screen, {'idle', 'gallery'}) && ~obj.IsBusy
                        obj.useMockCamera();
                    end
                case 'q'
                    delete(obj);
            end
        end

        function onPointerDown(obj)
            % Press-and-hold compare: holding the compare button or the photo
            % itself shows "before" until the pointer is released.
            if ~strcmp(obj.Screen, 'review') || obj.IsBusy, return; end
            hit = obj.Fig.CurrentObject;
            if isempty(hit), return; end
            if isequal(hit, obj.Widgets.CompareButton) || isequal(hit, obj.Widgets.ReviewMainImg)
                obj.setComparing(true);
            end
        end

        function onPointerUp(obj)
            if obj.Comparing && strcmp(obj.Screen, 'review')
                obj.setComparing(false);
            end
        end

        %% Shooting
        function runShootSequence(obj, slots)
            obj.ShootToken = obj.ShootToken + 1;
            token = obj.ShootToken;
            obj.IsShooting = true;
            guard = onCleanup(@() obj.endShooting(token)); %#ok<NASGU>
            obj.startPreviewTimer();   % live mirror runs through countdowns and gaps
            obj.updateLivePreview();   % measure the live aspect before the first count
            for idx = 1:numel(slots)
                k = slots(idx);
                ok = false;
                attempts = 0;
                while ~ok
                    if obj.shootAborted(token), return; end
                    attempts = attempts + 1;
                    obj.setShootStatus(k, numel(slots), idx);
                    for c = obj.Config.countdownSeconds:-1:1
                        if obj.shootAborted(token), return; end
                        obj.showCountdown(sprintf('%d', c));
                        if c > 1, booth.Sounds.beep(); else, booth.Sounds.finalBeep(); end
                        drawnow;
                        pause(1.0);
                    end
                    if obj.shootAborted(token), return; end
                    % Hold until the camera has actually taken the picture; the
                    % flash and shutter sound confirm the exposure, not precede it.
                    obj.showHold();
                    drawnow;
                    obj.stopTimer('PreviewTimer');
                    try
                        obj.captureOneSlot(k);
                        ok = true;
                    catch err
                        obj.Logger.err('Capture failed on slot %d (attempt %d): %s', k, attempts, err.message);
                        if attempts >= 3
                            obj.Logger.err('Camera unresponsive after 3 attempts; shoot aborted.');
                            obj.goToIdle();
                            obj.setCameraBanner(true, ...
                                'กล้องไม่ตอบสนอง ขออภัยด้วย — กรุณาแจ้งเจ้าหน้าที่ประจำบูธ');
                            return;
                        end
                        obj.startPreviewTimer();
                        obj.showShootMessage('ถ่ายไม่ติด ลองอีกครั้งนะ');
                        drawnow;
                        pause(1.5);
                        continue;
                    end
                    obj.hideShootOverlays();
                    booth.Sounds.shutter();
                    obj.flash();
                    obj.startPreviewTimer();
                end
                if idx < numel(slots)
                    if obj.shootAborted(token), return; end
                    obj.Widgets.ShootStatusLabel.Text = sprintf('2. ได้รูปที่ %d แล้ว', idx);
                    obj.showShootMessage('โพสท่าต่อไป!');
                    drawnow;
                    pause(obj.Config.gapSeconds);
                end
            end
            if obj.shootAborted(token), return; end
            obj.stopTimer('PreviewTimer');
            obj.hideShootOverlays();
            if obj.RetakeTarget > 0
                obj.prepareRetakenSlot(obj.RetakeTarget);
                obj.enterReview(false);
            else
                obj.enterReview(true);
            end
        end

        function tf = shootAborted(obj, token)
            tf = ~isvalid(obj) || isempty(obj.Fig) || ~isvalid(obj.Fig) ...
                || obj.ShootToken ~= token || ~strcmp(obj.Screen, 'shooting');
        end

        function endShooting(obj, token)
            if ~isvalid(obj) || obj.ShootToken ~= token, return; end
            obj.IsShooting = false;
            if strcmp(obj.Screen, 'shooting')
                obj.stopTimer('PreviewTimer');
            end
        end

        function setShootStatus(obj, slot, total, idx)
            if total == 1
                obj.Widgets.ShootStatusLabel.Text = sprintf('2. ถ่ายรูปที่ %d ใหม่ — เตรียมโพส!', slot);
            else
                obj.Widgets.ShootStatusLabel.Text = sprintf('2. รูปที่ %d จาก 4 — เตรียมโพส!', idx);
            end
            p = obj.designPos(obj.Widgets.ShootThumbs(slot));
            obj.place(obj.Widgets.ShootSelection, p + [-5 -5 10 10]);
            obj.Widgets.ShootSelection.Visible = 'on';
        end

        function [x, y, w, h] = liveRect(obj)
            % The mirror as actually drawn (letterboxed inside LiveImageBox).
            b = obj.LiveImageBox;
            w = min(b(3), b(4) * obj.LiveAspect);
            h = min(b(4), b(3) / obj.LiveAspect);
            x = b(1) + (b(3) - w) / 2;
            y = b(2) + (b(4) - h) / 2;
        end

        function showCountdown(obj, txt)
            % Top-centre of the mirror, nearest the lens (camera assumed above
            % the screen; see DESIGN.md).
            [x, y, w, h] = obj.liveRect();
            obj.Widgets.ShootMessageBand.Visible = 'off';
            obj.Widgets.HoldLabel.Visible = 'off';
            obj.Widgets.CountdownLabel.Text = txt;
            obj.Widgets.CountdownLabel.Visible = 'on';
            obj.place(obj.Widgets.CountdownPlate, [x + w/2 - 100, y + h - 12 - 170, 200, 170]);
            obj.Widgets.CountdownPlate.Visible = 'on';
        end

        function showHold(obj)
            obj.Widgets.CountdownLabel.Visible = 'off';
            obj.Widgets.HoldLabel.Visible = 'on';
            obj.Widgets.CountdownPlate.Visible = 'on';
        end

        function showShootMessage(obj, txt)
            [x, y, w] = obj.liveRect();
            obj.Widgets.CountdownPlate.Visible = 'off';
            obj.Widgets.ShootMessageLabel.Text = txt;
            obj.place(obj.Widgets.ShootMessageBand, [x, y, w, 100]);
            obj.place(obj.Widgets.ShootMessageLabel, [0 0 w 100]);
            obj.Widgets.ShootMessageBand.Visible = 'on';
        end

        function hideShootOverlays(obj)
            obj.Widgets.CountdownPlate.Visible = 'off';
            obj.Widgets.ShootMessageBand.Visible = 'off';
        end

        function flash(obj)
            %FLASH Brief paper-white flash over the mirror confirming the exposure.
            if ~obj.AutoTimers, return; end
            obj.Widgets.ShootFlash.Visible = 'on';
            drawnow;
            pause(0.12);
            obj.Widgets.ShootFlash.Visible = 'off';
            drawnow;
        end

        function captureOneSlot(obj, k)
            obj.CurrentShotIdx = k;
            if ~obj.cameraIsReady()
                error('Photobooth:cameraNotReady', 'Camera is not ready.');
            end
            tmpDir = fullfile(tempdir, 'mineaorz_session');
            if ~isfolder(tmpDir), mkdir(tmpDir); end
            outFile = fullfile(tmpDir, sprintf('shot_%d.jpg', k));
            obj.Camera.capture(outFile);
            obj.RawFiles{k} = outFile;
            f = obj.Frames(obj.SelectedFrameIdx);
            rawImg = imread(outFile);
            if obj.Config.mirror, rawImg = fliplr(rawImg); end
            thumb = imgproc.applyTone(imresize(rawImg, [180 240]), f.tone, 'preview');
            obj.Widgets.ShootThumbs(k).ImageSource = im2uint8(thumb);
        end

        %% Choose frame
        function refreshFrameTiles(obj)
            %REFRESHFRAMETILES Each tile shows the frame filled with the visitor's
            % current live image in that frame's tone (computed once per visit).
            img = PhotoboothApp.placeholderImage(180, 240);
            if obj.cameraIsReady()
                try
                    frame = obj.Camera.getPreviewFrame();
                    if obj.Config.mirror, frame = fliplr(frame); end
                    img = imresize(booth.cropToAspect(frame, 4/3), [180 240]);
                catch err
                    obj.Logger.warn('Frame tile preview failed: %s', err.message);
                end
            end
            for k = 1:numel(obj.Widgets.FrameTiles)
                f = obj.Frames(k);
                try
                    toned = imgproc.applyTone(img, f.tone, 'preview');
                    tile = booth.composeStrip(f, repmat({im2double(toned)}, 1, 4));
                    obj.Widgets.FrameTiles(k).ImageSource = im2uint8(tile);
                catch err
                    obj.Logger.warn('Frame tile %d failed: %s', k, err.message);
                end
            end
        end

        %% Review
        function prepareRetakenSlot(obj, s)
            release = obj.beginBusy('กำลังเตรียมรูปใหม่', '');
            obj.ReviewPreps{s} = booth.preparePhoto( ...
                obj.RawFiles{s}, obj.Config.reviewLongSide, obj.Config.mirror, obj.AutoLight);
            clear release
            obj.SelectedPhotoIdx = s;
        end

        function enterReview(obj, prepareAll)
            obj.stopAllTimers();
            if prepareAll
                release = obj.beginBusy('เยี่ยมมาก! กำลังเตรียมรูปให้ปรับผิว', '');
                for k = 1:4
                    obj.setBusyProgress(sprintf('รูปที่ %d จาก 4', k), (k - 1) / 4);
                    obj.ReviewPreps{k} = booth.preparePhoto( ...
                        obj.RawFiles{k}, obj.Config.reviewLongSide, obj.Config.mirror, obj.AutoLight);
                end
                obj.setBusyProgress('พร้อมแล้ว', 1);
                clear release
                obj.SelectedPhotoIdx = 1;
            end
            obj.RetakeTarget = 0;
            obj.showScreen('review');
            obj.refreshReviewDisplay();
            obj.restartIdleTimer();
        end

        function refreshReviewDisplay(obj)
            %REFRESHREVIEWDISPLAY Thumbnails + main image (after a committed change).
            if ~strcmp(obj.Screen, 'review'), return; end
            f = obj.Frames(obj.SelectedFrameIdx);
            for k = 1:4
                if ~isempty(obj.ReviewPreps{k}) && k ~= obj.SelectedPhotoIdx
                    rendered = booth.renderPhoto(obj.ReviewPreps{k}, obj.Smoothness, f.tone, 'preview');
                    obj.Widgets.ReviewThumbs(k).ImageSource = im2uint8(rendered);
                end
            end
            obj.refreshMainImage(true);
        end

        function refreshMainImage(obj, alsoThumb)
            %REFRESHMAINIMAGE Re-render only the selected photo (one render per tap).
            if nargin < 2, alsoThumb = false; end
            if ~strcmp(obj.Screen, 'review'), obj.updateReviewState(); return; end
            prep = obj.ReviewPreps{obj.SelectedPhotoIdx};
            if ~isempty(prep)
                f = obj.Frames(obj.SelectedFrameIdx);
                amt = obj.Smoothness;
                if obj.Comparing, amt = 0; end
                rendered = booth.renderPhoto(prep, amt, f.tone, 'preview');
                obj.showMainImage(rendered);
                if alsoThumb && ~obj.Comparing
                    obj.Widgets.ReviewThumbs(obj.SelectedPhotoIdx).ImageSource = im2uint8(rendered);
                end
            end
            obj.updateReviewState();
        end

        function showMainImage(obj, img)
            obj.Widgets.ReviewMainImg.ImageSource = im2uint8(img);
            obj.MainAspect = size(img, 2) / size(img, 1);
        end

        function previewSmoothness(obj, val)
            %PREVIEWSMOOTHNESS Live re-render of the main image while dragging.
            amt = max(0, min(100, round(val)));
            obj.Comparing = false;
            if isempty(obj.ReviewPreps{obj.SelectedPhotoIdx}), return; end
            f = obj.Frames(obj.SelectedFrameIdx);
            rendered = booth.renderPhoto(obj.ReviewPreps{obj.SelectedPhotoIdx}, amt, f.tone, 'preview');
            obj.showMainImage(rendered);
            obj.updateBadge(sprintf('หลังปรับ · เนียน %d', amt), obj.Palette.espresso);
        end

        function updateReviewState(obj)
            P = obj.Palette;
            p = obj.designPos(obj.Widgets.ReviewThumbs(obj.SelectedPhotoIdx));
            obj.place(obj.Widgets.ReviewSelection, p + [-5 -5 10 10]);
            obj.Widgets.ReviewHint.Text = sprintf('แตะรูปเพื่อดูภาพใหญ่ · กำลังดูรูปที่ %d', obj.SelectedPhotoIdx);
            obj.Widgets.RetakeButton.Text = sprintf('ถ่ายรูปที่ %d ใหม่', obj.SelectedPhotoIdx);
            for k = 1:numel(obj.Widgets.PresetButtons)
                obj.styleChoice(obj.Widgets.PresetButtons(k), obj.Smoothness == obj.SmoothPresets(k));
            end
            obj.updateAutoLightButton();
            if obj.Comparing
                obj.updateBadge('ก่อนปรับผิว', P.taupe);
            else
                obj.updateBadge(sprintf('หลังปรับ · เนียน %d', obj.Smoothness), P.espresso);
            end
        end

        function updateBadge(obj, txt, bg)
            % Badge hangs above the top-right corner of the photo as actually drawn
            % (the main image is letterboxed inside MainImageBox).
            b = obj.MainImageBox;
            w = min(b(3), b(4) * obj.MainAspect);
            right = b(1) + (b(3) + w) / 2;
            obj.Widgets.CompareBadge.Text = txt;
            obj.Widgets.CompareBadge.BackgroundColor = bg;
            obj.place(obj.Widgets.CompareBadge, [right - 250, b(2) + b(4) + 8, 250, 40]);
        end

        function updateAutoLightButton(obj)
            btn = obj.Widgets.AutoLightButton;
            obj.styleChoice(btn, obj.AutoLight);
            if obj.AutoLight
                btn.Text = 'ปรับแสงอัตโนมัติ: เปิด';
            else
                btn.Text = 'ปรับแสงอัตโนมัติ: ปิด';
            end
        end

        function updateAdvanced(obj)
            vis = matlab.lang.OnOffSwitchState(obj.AdvancedOpen);
            obj.Widgets.AutoLightButton.Visible = vis;
            obj.Widgets.FineLabel.Visible = vis;
            obj.Widgets.SmoothSlider.Visible = vis;
            if obj.AdvancedOpen
                obj.Widgets.MoreButton.Text = 'ซ่อนการปรับเพิ่มเติม';
            else
                obj.Widgets.MoreButton.Text = 'ปรับเพิ่มเติม';
            end
        end

        function styleChoice(obj, btn, selected)
            % Segmented choice / toggle: espresso when on, linen otherwise.
            P = obj.Palette;
            if selected
                btn.BackgroundColor = P.espresso;
                btn.FontColor = P.paper;
                btn.FontWeight = 'bold';
            else
                btn.BackgroundColor = P.linen;
                btn.FontColor = P.espresso;
                btn.FontWeight = 'normal';
            end
        end

        function resetSession(obj)
            %RESETSESSION Clear per-visitor state so the next visitor starts fresh.
            obj.Smoothness = obj.Config.defaultSmoothness;
            obj.Comparing = false;
            obj.AutoLight = true;
            obj.AdvancedOpen = false;
            obj.SelectedPhotoIdx = 1;
            obj.RetakeTarget = 0;
            obj.ReviewPreps = {[], [], [], []};
            if isfield(obj.Widgets, 'SmoothSlider')
                obj.Widgets.SmoothSlider.Value = obj.Smoothness;
                obj.updateAutoLightButton();
                obj.updateAdvanced();
            end
            obj.hideShootOverlays();
        end

        function showIdleWarning(obj)
            obj.Logger.info('Idle on %s with unsaved work -> warning visitor.', obj.Screen);
            if strcmp(obj.Screen, 'review')
                obj.WarnLoss = 'รูปที่ยังไม่ได้กดบันทึกจะหายไป';
            else
                obj.WarnLoss = 'รูปที่ยังบันทึกไม่สำเร็จจะหายไป';
            end
            obj.WarnRemaining = obj.WarnSeconds;
            obj.updateWarnText();
            obj.Widgets.WarnOverlay.Visible = 'on';
            obj.stopTimer('WarnTimer');
            obj.WarnTimer = timer('ExecutionMode', 'fixedRate', 'Period', 1, ...
                'StartDelay', 1, 'TimerFcn', @(~,~) obj.warnTick());
            start(obj.WarnTimer);
        end

        function warnTick(obj)
            if ~isvalid(obj) || obj.IsBusy, return; end
            obj.WarnRemaining = obj.WarnRemaining - 1;
            if obj.WarnRemaining <= 0
                obj.goToIdle();
            else
                obj.updateWarnText();
            end
        end

        function updateWarnText(obj)
            obj.Widgets.WarnDetail.Text = { ...
                sprintf('ถ้าไม่แตะปุ่มด้านล่าง จะกลับหน้าแรกใน %d วินาที', obj.WarnRemaining), ...
                obj.WarnLoss};
        end

        %% Result
        function trySaveCurrentSession(obj)
            f = obj.Frames(obj.SelectedFrameIdx);
            try
                s = struct('strip', obj.LastStrip, ...
                    'photos', {obj.LastPhotos}, ...
                    'raws', {obj.RawFiles}, ...
                    'meta', struct('frame', f.name, 'tone', f.tone, ...
                        'smoothness', obj.Smoothness, 'autoLight', obj.AutoLight, ...
                        'demo', obj.IsDemo), ...
                    'gifDelay', obj.Config.gifDelaySeconds, ...
                    'gifLongSide', obj.Config.reviewLongSide);
                savedDir = obj.Store.saveSession(s);
                obj.DemoCache(savedDir) = obj.IsDemo;
                try
                    obj.Widgets.ResultGifImg.ImageSource = fullfile(savedDir, 'animation.gif');
                catch
                    obj.Widgets.ResultGifImg.ImageSource = im2uint8(obj.LastPhotos{1});
                end
                obj.SaveErrorVisible = false;
                obj.Widgets.SaveErrorPanel.Visible = 'off';
                obj.Widgets.ResultHeadline.Text = 'สวยมาก! รูปของคุณเสร็จแล้ว';
                obj.Widgets.SavedLabel.Text = 'บันทึกลงแกลเลอรีของบูธแล้ว';
                obj.Widgets.SavedLabel.Visible = 'on';
                obj.Logger.info('Saved session to %s', savedDir);
            catch err
                obj.SaveErrorVisible = true;
                obj.Widgets.ResultGifImg.ImageSource = im2uint8(obj.LastPhotos{1});
                obj.Widgets.SaveErrorPanel.Visible = 'on';
                obj.Widgets.ResultHeadline.Text = 'รูปเสร็จแล้ว แต่ยังบันทึกไม่สำเร็จ';
                obj.Widgets.SavedLabel.Visible = 'off';
                obj.Logger.err('Save session failed: %s', err.message);
            end
        end

        function revealStrip(obj)
            %REVEALSTRIP The strip drops out of the "print slot" like a booth print.
            % Slot and tray are sized to the strip's own aspect; a 2px sand hairline
            % keeps the strip's cream edge from dissolving into the ivory wall.
            box = obj.StripBox;
            slotTop = box(2) + box(4);
            [h0, w0, ~] = size(obj.LastStrip);
            scale = min((box(3) - 4) / w0, (box(4) - 4) / h0);
            w = round(w0 * scale);
            h = round(h0 * scale);
            x = box(1) + round((box(3) - w - 4) / 2);
            obj.place(obj.Widgets.StripTray, [x, slotTop - h - 4, w + 4, h + 4]);
            obj.place(obj.Widgets.StripSlot, [x - 16, slotTop, w + 36, 8]);
            img = obj.Widgets.ResultStripImg;
            final = [2 2 w h];
            if ~obj.AutoTimers || ~strcmp(char(obj.Fig.Visible), 'on')
                obj.place(img, final);
                return;
            end
            steps = 16;
            for t = 1:steps
                p = 1 - (1 - t / steps)^3;           % ease-out cubic
                obj.place(img, [2, 2 + round((h + 2) * (1 - p)), w, h]);
                drawnow limitrate;
                pause(0.03);
            end
            obj.place(img, final);
        end

        %% Idle / gallery
        function list = visibleSessions(obj)
            %VISIBLESESSIONS Sessions for public display; demo sessions only in demo mode.
            list = obj.Store.listSessions();
            if obj.IsDemo || isempty(list), return; end
            keep = true(1, numel(list));
            for k = 1:numel(list)
                keep(k) = ~obj.isDemoSession(list(k).folder);
            end
            list = list(keep);
        end

        function tf = isDemoSession(obj, folder)
            if isKey(obj.DemoCache, folder)
                tf = obj.DemoCache(folder);
                return;
            end
            tf = false;
            try
                meta = jsondecode(fileread(fullfile(folder, 'meta.json')));
                tf = isfield(meta, 'demo') && meta.demo;
            catch
            end
            obj.DemoCache(folder) = tf;
        end

        function refreshIdleSlide(obj)
            %REFRESHIDLESLIDE Alternate each recent strip with its before/after
            % pair, so the algorithm sells itself from across the room.
            list = obj.visibleSessions();
            obj.Widgets.IdleCaption.Visible = 'off';
            if isempty(list)
                f = obj.Frames(1);
                placeholder = booth.composeStrip(f, ...
                    repmat({im2double(PhotoboothApp.placeholderImage(180, 240))}, 1, 4));
                obj.Widgets.IdleSlideImg.ImageSource = im2uint8(placeholder);
                return;
            end
            n = numel(list);
            i = mod(obj.SlideIdx - 1, 2 * n) + 1;
            s = list(ceil(i / 2));
            obj.SlideIdx = obj.SlideIdx + 1;
            if mod(i, 2) == 0
                try
                    obj.Widgets.IdleSlideImg.ImageSource = obj.beforeAfter(s.folder);
                    obj.Widgets.IdleCaption.Visible = 'on';
                    return;
                catch
                end
            end
            obj.Widgets.IdleSlideImg.ImageSource = s.stripPath;
        end

        function img = beforeAfter(obj, folder)
            % Top: straight from the camera. Bottom: after smoothing + tone.
            raw = imread(fullfile(folder, 'raw_1.jpg'));
            if obj.Config.mirror, raw = fliplr(raw); end
            fin = imread(fullfile(folder, 'photo_1.png'));
            raw = im2uint8(imresize(booth.cropToAspect(raw, 4/3), [300 400]));
            fin = im2uint8(imresize(booth.cropToAspect(fin, 4/3), [300 400]));
            if size(fin, 3) == 1, fin = repmat(fin, 1, 1, 3); end
            gap = repmat(reshape(uint8([247 243 236]), 1, 1, 3), 10, 400, 1);
            img = [raw; gap; fin];
        end

        function refreshGallery(obj)
            list = obj.visibleSessions();
            obj.Widgets.GalleryEmpty.Visible = matlab.lang.OnOffSwitchState(isempty(list));
            for k = 1:4
                thumb = obj.Widgets.GalleryThumbs(k);
                hasSession = k <= numel(list);
                thumb.Visible = matlab.lang.OnOffSwitchState(hasSession);
                if hasSession
                    thumb.ImageSource = list(k).stripPath;
                end
            end
        end

        %% Live preview & timers
        function startPreviewLoop(obj)
            obj.updateLivePreview();
            obj.startPreviewTimer();
        end

        function startPreviewTimer(obj)
            obj.stopTimer('PreviewTimer');
            if obj.AutoTimers
                obj.PreviewTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.08, ...
                    'BusyMode', 'drop', 'TimerFcn', @(~,~) obj.updateLivePreview());
                start(obj.PreviewTimer);
            end
        end

        function updateLivePreview(obj)
            if ~isvalid(obj), return; end
            live = ismember(obj.Screen, {'chooseFrame', 'shooting'});
            if ~obj.cameraIsReady()
                if live && obj.AutoTimers, obj.onCameraLost(); end
                return;
            end
            try
                frame = obj.Camera.getPreviewFrame();
                obj.PreviewFailures = 0;
                if obj.Config.mirror, frame = fliplr(frame); end
                f = obj.Frames(obj.SelectedFrameIdx);
                toned = imgproc.applyTone(frame, f.tone, 'preview');
                if strcmp(obj.Screen, 'chooseFrame')
                    obj.Widgets.ChooseLiveImg.ImageSource = im2uint8(toned);
                elseif strcmp(obj.Screen, 'shooting')
                    obj.Widgets.ShootLiveImg.ImageSource = im2uint8(toned);
                    obj.LiveAspect = size(toned, 2) / size(toned, 1);
                end
            catch err
                obj.PreviewFailures = obj.PreviewFailures + 1;
                if obj.PreviewFailures == 1
                    obj.Logger.warn('Live preview error: %s', err.message);
                end
                if live && obj.PreviewFailures >= obj.MaxPreviewFailures
                    obj.onCameraLost();
                end
            end
        end

        function restartIdleTimer(obj)
            obj.stopTimer('IdleTimer');
            if obj.AutoTimers && obj.Config.idleTimeoutSeconds > 0
                obj.IdleTimer = timer('StartDelay', obj.Config.idleTimeoutSeconds, ...
                    'TimerFcn', @(~,~) obj.onIdleTimeout());
                start(obj.IdleTimer);
            end
        end

        function stopTimer(obj, name)
            t = obj.(name);
            if ~isempty(t) && isvalid(t)
                stop(t);
                delete(t);
            end
            obj.(name) = [];
        end

        function stopAllTimers(obj)
            names = {'PreviewTimer', 'IdleTimer', 'SlideTimer', 'WarnTimer'};
            for k = 1:numel(names)
                obj.stopTimer(names{k});
            end
        end

        %% Busy overlay
        function release = beginBusy(obj, title, detail)
            obj.IsBusy = true;
            obj.Widgets.BusyTitle.Text = title;
            obj.setBusyProgress(detail, 0);
            obj.Widgets.BusyOverlay.Visible = 'on';
            drawnow;
            release = onCleanup(@() obj.endBusy());
        end

        function setBusyProgress(obj, detail, frac)
            obj.Widgets.BusyDetail.Text = detail;
            track = obj.designPos(obj.Widgets.BusyTrack);
            w = max(1, round(track(3) * max(0, min(1, frac))));
            obj.place(obj.Widgets.BusyFill, [0 0 w track(4)]);
            drawnow;
        end

        function endBusy(obj)
            if ~isvalid(obj), return; end
            obj.IsBusy = false;
            obj.hideOverlay('BusyOverlay');
        end

        function hideOverlay(obj, name)
            if isfield(obj.Widgets, name) && isvalid(obj.Widgets.(name))
                obj.Widgets.(name).Visible = 'off';
            end
        end

        function showScreen(obj, name)
            obj.Screen = name;
            names = fieldnames(obj.Panels);
            for k = 1:numel(names)
                on = strcmp(names{k}, name);
                obj.Panels.(names{k}).Visible = matlab.lang.OnOffSwitchState(on);
            end
        end

        %% Stage scaling
        function centerStage(obj)
            %CENTERSTAGE Fit the 1280x760 design canvas to the window, centred.
            if isempty(obj.Fig) || ~isvalid(obj.Fig) || isempty(obj.Root), return; end
            fp = obj.Fig.Position;
            sz = obj.StageSize;
            s = min(fp(3) / sz(1), fp(4) / sz(2));
            w = round(sz(1) * s);
            h = round(sz(2) * s);
            % Root first, then children: every child position is re-applied from
            % its design value on each resize, so intermediate window sizes
            % reported during a resize can never leave stale geometry behind.
            obj.Root.Position = [max(0, floor((fp(3) - w) / 2)), max(0, floor((fp(4) - h) / 2)), w, h];
            obj.applyScale(s);
        end

        function applyScale(obj, s)
            %APPLYSCALE Scale every component's Position and FontSize from its
            % design value (recorded in UserData on first use). Two-meter text
            % carries a MinFont floor so a smaller display never shrinks it.
            obj.Scale = s;
            hs = findall(obj.Root);
            for k = 1:numel(hs)
                h = hs(k);
                if h == obj.Root || ~isprop(h, 'Position'), continue; end
                ud = h.UserData;
                if ~isstruct(ud), ud = struct(); end
                if ~isfield(ud, 'DesignPos'), ud.DesignPos = h.Position; end
                hasFont = isprop(h, 'FontSize');
                if hasFont && ~isfield(ud, 'DesignFont'), ud.DesignFont = h.FontSize; end
                h.UserData = ud;
                % Font first: a visible uislider re-flows its track when its
                % tick-label font changes, so Position must be applied last.
                if hasFont
                    minFont = 8;
                    if isfield(ud, 'MinFont'), minFont = ud.MinFont; end
                    h.FontSize = max(minFont, round(ud.DesignFont * s));
                end
                pos = round(ud.DesignPos * s);
                if isa(h, 'matlab.ui.control.Slider')
                    pos(4) = h.Position(4);   % slider height is fixed by MATLAB
                end
                h.Position = pos;
            end
        end

        function place(obj, h, p)
            %PLACE Set a component's position in design coordinates.
            ud = h.UserData;
            if ~isstruct(ud), ud = struct(); end
            ud.DesignPos = p;
            h.UserData = ud;
            h.Position = round(p * obj.Scale);
        end

        function p = designPos(~, h)
            ud = h.UserData;
            if isstruct(ud) && isfield(ud, 'DesignPos')
                p = ud.DesignPos;
            else
                p = h.Position;
            end
        end

        function setMinFont(~, h, minFont)
            %SETMINFONT Two-meter text: never rendered smaller than minFont px.
            ud = h.UserData;
            if ~isstruct(ud), ud = struct(); end
            ud.MinFont = minFont;
            h.UserData = ud;
        end

        %% Build
        function buildUI(obj, visible, fullscreen)
            % Seoul Self-Studio Minimal — tonal layering on a warm-paper ground.
            % Layer 0 ivory wall → layer 1 linen controls → layer 2 sand canvas
            % → layer 3 a single terracotta CTA per screen (DESIGN.md).
            P = obj.Palette;
            fn = P.font;
            ivory = P.ivory;

            obj.Fig = uifigure('Name', 'MATLAB Photobooth Studio', ...
                'Position', [80 60 obj.StageSize], 'Color', ivory, ...
                'AutoResizeChildren', 'off', ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'CloseRequestFcn', @(~,~) delete(obj), ...
                'WindowKeyPressFcn', @(~,e) obj.onKey(e), ...
                'WindowButtonDownFcn', @(~,~) obj.onPointerDown(), ...
                'WindowButtonUpFcn', @(~,~) obj.onPointerUp());
            obj.Root = uipanel(obj.Fig, 'Position', [0 0 obj.StageSize], ...
                'BackgroundColor', ivory, 'BorderType', 'none', 'AutoResizeChildren', 'off');
            R = obj.Root;

            % Shared component recipes
            primaryBtn = @(parent, pos, txt, sz, cb) uibutton(parent, 'Position', pos, ...
                'Text', txt, 'FontName', fn, 'FontSize', sz, 'FontWeight', 'bold', ...
                'BackgroundColor', P.terracotta, 'FontColor', P.paper, 'ButtonPushedFcn', cb);
            secondaryBtn = @(parent, pos, txt, sz, cb) uibutton(parent, 'Position', pos, ...
                'Text', txt, 'FontName', fn, 'FontSize', sz, ...
                'BackgroundColor', P.linen, 'FontColor', P.espresso, 'ButtonPushedFcn', cb);
            headline = @(parent, pos, txt) uilabel(parent, 'Position', pos, 'Text', txt, ...
                'FontName', fn, 'FontSize', 28, 'FontWeight', 'bold', 'FontColor', P.espresso);
            screenPanel = @() uipanel(R, 'Position', [0 0 1280 700], ...
                'BackgroundColor', ivory, 'BorderType', 'none', 'AutoResizeChildren', 'off');

            % Top strip: camera alert (visitor-facing) and demo-mode tag
            cb = uipanel(R, 'Position', [0 700 1280 60], ...
                'BackgroundColor', P.rust, 'BorderType', 'none', 'Visible', 'off');
            obj.Widgets = struct('CameraBanner', cb);
            obj.Widgets.CameraBannerLabel = uilabel(cb, 'Position', [40 14 900 32], ...
                'Text', '', 'FontName', fn, 'FontSize', 18, ...
                'FontWeight', 'bold', 'FontColor', P.paper);
            uibutton(cb, 'Position', [1000 8 240 44], 'Text', 'เชื่อมต่อกล้องใหม่', ...
                'FontName', fn, 'FontSize', 16, 'FontWeight', 'bold', ...
                'BackgroundColor', P.paper, 'FontColor', P.rust, ...
                'ButtonPushedFcn', @(~,~) obj.retryCamera());
            obj.Widgets.DemoTag = uilabel(R, 'Position', [760 714 480 34], ...
                'Text', 'โหมดสาธิต: ใช้ภาพตัวอย่างแทนกล้องจริง', ...
                'HorizontalAlignment', 'right', 'FontName', fn, 'FontSize', 18, ...
                'FontWeight', 'bold', 'FontColor', P.taupe, 'Visible', 'off');

            % 0. IDLE SCREEN — copy + CTA on the left, the wall of recent strips
            % (alternating with before/after pairs) on the right
            pIdle = screenPanel();
            uilabel(pIdle, 'Position', [80 540 600 60], 'Text', 'PHOTOBOOTH STUDIO', ...
                'FontName', fn, 'FontSize', 42, 'FontWeight', 'bold', 'FontColor', P.espresso);
            uilabel(pIdle, 'Position', [80 485 620 40], ...
                'Text', 'เลือกกรอบพร้อมโทนสี • ถ่าย 4 ช็อต • ปรับผิวเนียนสวยธรรมชาติ', ...
                'FontName', fn, 'FontSize', 18, 'FontColor', P.taupe);
            obj.Widgets.StartButton = primaryBtn(pIdle, [80 320 360 90], 'แตะเพื่อเริ่มถ่าย', 28, ...
                @(~,~) obj.goToChooseFrame());
            secondaryBtn(pIdle, [80 210 240 55], 'ดูแกลเลอรี', 18, ...
                @(~,~) obj.goToGallery());
            obj.Widgets.IdleSlideImg = uiimage(pIdle, 'Position', [740 70 440 570]);
            obj.Widgets.IdleCaption = uilabel(pIdle, 'Position', [740 24 440 34], ...
                'Text', 'บน: ภาพจากกล้อง · ล่าง: หลังปรับผิวและโทนสี', ...
                'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 17, ...
                'FontWeight', 'bold', 'FontColor', P.taupe, 'Visible', 'off');

            % GALLERY SCREEN — no forward step, so no terracotta CTA
            pGal = screenPanel();
            headline(pGal, [40 630 700 45], 'แกลเลอรีรูปถ่ายล่าสุด');
            secondaryBtn(pGal, [1040 630 200 50], 'กลับหน้าแรก', 16, @(~,~) obj.goToIdle());
            obj.Widgets.GalleryThumbs = gobjects(1, 4);
            for k = 1:4
                obj.Widgets.GalleryThumbs(k) = uiimage(pGal, ...
                    'Position', [40 + (k-1)*305, 50, 280, 540], ...
                    'ImageSource', PhotoboothApp.placeholderImage(180, 90));
            end
            obj.Widgets.GalleryEmpty = uilabel(pGal, 'Position', [40 300 1200 80], ...
                'Text', {'ยังไม่มีรูปในแกลเลอรี', 'กลับหน้าแรกแล้วแตะ "เริ่มถ่าย" เพื่อเป็นคนแรกได้เลย'}, ...
                'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 20, ...
                'FontColor', P.taupe, 'Visible', 'off');

            % 1. CHOOSE FRAME SCREEN — frames are chosen by picture: each tile shows
            % the frame filled with the visitor's own live image in its tone.
            pChoose = screenPanel();
            headline(pChoose, [40 635 700 45], '1. เลือกกรอบและโทนสี');
            uilabel(pChoose, 'Position', [40 596 340 30], 'Text', 'แตะกรอบที่ชอบ', ...
                'FontName', fn, 'FontSize', 16, 'FontColor', P.taupe);
            nTiles = min(obj.MaxFrameButtons, numel(obj.Frames));
            obj.Widgets.FrameSelection = uipanel(pChoose, 'Position', [35 390 170 200], ...
                'BackgroundColor', P.terracottaDeep, 'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.FrameTiles = gobjects(1, nTiles);
            obj.Widgets.FrameTileLabels = gobjects(1, nTiles);
            for k = 1:nTiles
                idx = k;
                col = mod(k - 1, 2);
                row = floor((k - 1) / 2);
                x = 40 + col * 180;
                y = 395 - row * 250;
                obj.Widgets.FrameTiles(k) = uiimage(pChoose, 'Position', [x y 160 190], ...
                    'BackgroundColor', P.linen, 'ScaleMethod', 'fit', ...
                    'ImageSource', PhotoboothApp.placeholderImage(190, 160), ...
                    'ImageClickedFcn', @(~,~) obj.selectFrame(idx));
                obj.Widgets.FrameTileLabels(k) = uilabel(pChoose, 'Position', [x y-46 160 42], ...
                    'Text', {obj.Frames(k).name, PhotoboothApp.toneLabel(obj.Frames(k).tone)}, ...
                    'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 15, ...
                    'FontColor', P.espresso);
            end
            obj.Widgets.ChooseLiveImg = uiimage(pChoose, 'Position', [420 110 820 470], ...
                'ImageSource', PhotoboothApp.placeholderImage(49, 82));
            secondaryBtn(pChoose, [40 20 180 54], 'ย้อนกลับ', 17, @(~,~) obj.goToIdle());
            primaryBtn(pChoose, [960 25 280 65], 'เริ่มถ่ายเลย!', 24, ...
                @(~,~) obj.startShooting());

            % 2. SHOOTING SCREEN — the live mirror is the stage; the countdown hangs
            % from its top edge, nearest the lens.
            pShoot = screenPanel();
            obj.Widgets.ShootStatusLabel = uilabel(pShoot, 'Position', [40 638 960 44], ...
                'Text', '2. รูปที่ 1 จาก 4 — เตรียมโพส!', 'FontName', fn, 'FontSize', 32, ...
                'FontWeight', 'bold', 'FontColor', P.espresso);
            obj.setMinFont(obj.Widgets.ShootStatusLabel, 26);
            secondaryBtn(pShoot, [1060 636 180 50], 'ยกเลิก', 17, @(~,~) obj.cancelShooting());
            cue = uilabel(pShoot, 'Position', [40 588 880 40], 'Text', 'มองที่เลนส์กล้อง แล้วยิ้มได้เลย', ...
                'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 28, ...
                'FontWeight', 'bold', 'FontColor', P.taupe);
            obj.setMinFont(cue, 26);
            obj.Widgets.ShootLiveImg = uiimage(pShoot, 'Position', obj.LiveImageBox, ...
                'ImageSource', PhotoboothApp.placeholderImage(54, 88));
            obj.Widgets.ShootFlash = uipanel(pShoot, 'Position', obj.LiveImageBox, ...
                'BackgroundColor', P.paper, 'BorderType', 'none', 'Visible', 'off');
            % 200x170: the smallest plate that holds a 160px numeral, so it hides
            % as little of the mirror's top edge as possible.
            plate = uipanel(pShoot, 'Position', [380 398 200 170], ...
                'BackgroundColor', ivory, 'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.CountdownPlate = plate;
            % The 160px line box is ~220px tall and the numeral sits low in it, so
            % the label overhangs the plate (clipped) to centre the visible digit.
            obj.Widgets.CountdownLabel = uilabel(plate, 'Position', [0 -5 200 220], ...
                'Text', '3', 'FontName', fn, 'FontSize', 160, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
                'FontColor', P.terracotta);
            obj.setMinFont(obj.Widgets.CountdownLabel, 160);
            obj.Widgets.HoldLabel = uilabel(plate, 'Position', [0 -20 200 200], ...
                'Text', 'นิ่ง!', 'FontName', fn, 'FontSize', 80, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
                'FontColor', P.terracotta, 'Visible', 'off');
            obj.setMinFont(obj.Widgets.HoldLabel, 72);
            band = uipanel(pShoot, 'Position', [40 40 880 100], ...
                'BackgroundColor', ivory, 'BorderType', 'none', 'Visible', 'off', ...
                'AutoResizeChildren', 'off');
            obj.Widgets.ShootMessageBand = band;
            obj.Widgets.ShootMessageLabel = uilabel(band, 'Position', [0 0 880 100], ...
                'Text', '', 'FontName', fn, 'FontSize', 56, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
                'FontColor', P.espresso);
            obj.setMinFont(obj.Widgets.ShootMessageLabel, 40);
            obj.Widgets.ShootSelection = uipanel(pShoot, 'Position', [995 450 190 145], ...
                'BackgroundColor', P.terracottaDeep, 'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.ShootThumbs = gobjects(1, 4);
            for k = 1:4
                y = 600 - k*145;
                num = uilabel(pShoot, 'Position', [952 y 32 135], 'Text', sprintf('%d', k), ...
                    'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 26, ...
                    'FontWeight', 'bold', 'FontColor', P.taupe);
                obj.setMinFont(num, 26);
                obj.Widgets.ShootThumbs(k) = uiimage(pShoot, ...
                    'Position', [1000, y, 180, 135], 'ScaleMethod', 'fill', ...
                    'ImageSource', PhotoboothApp.placeholderImage(90, 120));
            end

            % 3. REVIEW & BEAUTY SCREEN — main image sits on plain ivory (skin-check rule)
            pRev = screenPanel();
            headline(pRev, [40 636 700 44], '3. ตรวจรูปและปรับผิวเนียน');
            obj.Widgets.CompareBadge = uilabel(pRev, 'Position', [990 628 250 40], ...
                'Text', '', 'HorizontalAlignment', 'center', 'FontName', fn, 'FontSize', 17, ...
                'FontWeight', 'bold', 'FontColor', P.paper, 'BackgroundColor', P.espresso);
            obj.Widgets.ReviewSelection = uipanel(pRev, 'Position', [35 415 230 175], ...
                'BackgroundColor', P.terracottaDeep, 'BorderType', 'none');
            coords = [40 420; 280 420; 40 235; 280 235];
            obj.Widgets.ReviewThumbs = gobjects(1, 4);
            for k = 1:4
                idx = k;
                obj.Widgets.ReviewThumbs(k) = uiimage(pRev, ...
                    'Position', [coords(k,:) 220 165], 'ScaleMethod', 'fill', ...
                    'BackgroundColor', P.sand, ...
                    'ImageClickedFcn', @(~,~) obj.selectReviewPhoto(idx));
                uilabel(pRev, 'Position', [coords(k,1) + 8, coords(k,2) + 129, 30, 28], ...
                    'Text', sprintf('%d', k), 'HorizontalAlignment', 'center', ...
                    'FontName', fn, 'FontSize', 17, 'FontWeight', 'bold', ...
                    'FontColor', P.paper, 'BackgroundColor', P.espresso);
            end
            obj.Widgets.ReviewHint = uilabel(pRev, 'Position', [40 186 460 30], ...
                'Text', '', 'FontName', fn, 'FontSize', 16, 'FontColor', P.taupe);
            obj.Widgets.RetakeButton = secondaryBtn(pRev, [40 30 300 60], 'ถ่ายรูปที่ 1 ใหม่', 17, ...
                @(~,~) obj.startRetake(obj.SelectedPhotoIdx));
            obj.Widgets.ReviewMainImg = uiimage(pRev, 'Position', obj.MainImageBox);
            obj.Widgets.PresetButtons = gobjects(1, numel(obj.SmoothPresets));
            for k = 1:numel(obj.SmoothPresets)
                val = obj.SmoothPresets(k);
                obj.Widgets.PresetButtons(k) = secondaryBtn(pRev, [540 + (k-1)*140, 180, 130, 54], ...
                    obj.SmoothPresetLabels{k}, 18, @(~,~) obj.setSmoothness(val));
            end
            obj.Widgets.MoreButton = secondaryBtn(pRev, [970 180 270 54], 'ปรับเพิ่มเติม', 17, ...
                @(~,~) obj.toggleAdvanced());
            % Advanced row (hidden until "ปรับเพิ่มเติม")
            obj.Widgets.AutoLightButton = secondaryBtn(pRev, [540 108 270 50], ...
                'ปรับแสงอัตโนมัติ: เปิด', 16, @(~,~) obj.setAutoLight(~obj.AutoLight));
            obj.Widgets.FineLabel = uilabel(pRev, 'Position', [830 118 100 30], 'Text', 'ปรับละเอียด', ...
                'FontName', fn, 'FontSize', 16, 'FontColor', P.taupe);
            obj.Widgets.SmoothSlider = uislider(pRev, 'Position', [940 134 290 3], ...
                'Limits', [0 100], 'Value', obj.Smoothness, ...
                'MajorTicks', [0 50 100], 'MajorTickLabels', {'0', '50', '100'}, 'MinorTicks', [], ...
                'FontName', fn, 'FontSize', 14, 'FontColor', P.taupe, ...
                'ValueChangingFcn', @(~,e) obj.previewSmoothness(e.Value), ...
                'ValueChangedFcn', @(s,~) obj.setSmoothness(s.Value));
            % Press-and-hold compare (handled by WindowButtonDown/Up)
            obj.Widgets.CompareButton = uibutton(pRev, 'Position', [540 30 300 60], ...
                'Text', 'กดค้างเพื่อดูภาพก่อนปรับ', 'FontName', fn, 'FontSize', 17, ...
                'BackgroundColor', P.linen, 'FontColor', P.espresso);
            primaryBtn(pRev, [1010 30 230 60], 'บันทึกรูป', 24, ...
                @(~,~) obj.finishReview());

            % 4. RESULT SCREEN — a celebration; the strip is the hero and drops
            % from a print slot. Photos stay in the booth gallery (no take-home).
            pRes = screenPanel();
            obj.Widgets.StripSlot = uipanel(pRes, 'Position', [40 630 560 8], ...
                'BackgroundColor', P.espresso, 'BorderType', 'none');
            stripTray = uipanel(pRes, 'Position', obj.StripBox, ...
                'BackgroundColor', P.sand, 'BorderType', 'none', 'AutoResizeChildren', 'off');
            obj.Widgets.StripTray = stripTray;
            obj.Widgets.ResultStripImg = uiimage(stripTray, 'Position', [2 2 556 586]);
            obj.Widgets.ResultHeadline = headline(pRes, [640 630 600 44], 'สวยมาก! รูปของคุณเสร็จแล้ว');
            obj.Widgets.SavedLabel = uilabel(pRes, 'Position', [640 590 600 32], ...
                'Text', '', 'FontName', fn, 'FontSize', 18, 'FontWeight', 'bold', ...
                'FontColor', P.sage);
            obj.Widgets.ResultGifImg = uiimage(pRes, 'Position', [640 250 360 270]);
            uilabel(pRes, 'Position', [640 216 600 28], 'Text', 'ภาพเคลื่อนไหวจากทั้ง 4 ช็อต', ...
                'FontName', fn, 'FontSize', 16, 'FontColor', P.taupe);
            errP = uipanel(pRes, 'Position', [640 120 600 64], 'BackgroundColor', P.rust, ...
                'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.SaveErrorPanel = errP;
            uilabel(errP, 'Position', [20 4 380 56], ...
                'Text', {'บันทึกไม่สำเร็จ แต่รูปยังอยู่ในเครื่อง', 'ลองบันทึกซ้ำ หรือแจ้งเจ้าหน้าที่'}, ...
                'FontName', fn, 'FontSize', 16, 'FontWeight', 'bold', 'FontColor', P.paper);
            uibutton(errP, 'Position', [410 10 170 44], 'Text', 'ลองบันทึกซ้ำ', ...
                'FontName', fn, 'FontSize', 16, 'FontWeight', 'bold', ...
                'BackgroundColor', P.paper, 'FontColor', P.rust, ...
                'ButtonPushedFcn', @(~,~) obj.retrySave());
            secondaryBtn(pRes, [640 30 280 60], 'ถ่ายอีกครั้ง', 18, ...
                @(~,~) obj.startNewRound());
            primaryBtn(pRes, [960 30 280 60], 'เสร็จสิ้น', 24, ...
                @(~,~) obj.goToIdle());

            obj.Panels = struct('idle', pIdle, 'gallery', pGal, ...
                'chooseFrame', pChoose, 'shooting', pShoot, ...
                'review', pRev, 'result', pRes);

            % Overlays (created last so they sit above every screen)
            busy = uipanel(R, 'Position', [0 0 1280 700], 'BackgroundColor', ivory, ...
                'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.BusyOverlay = busy;
            obj.Widgets.BusyTitle = uilabel(busy, 'Position', [140 370 1000 56], ...
                'Text', '', 'HorizontalAlignment', 'center', 'FontName', fn, ...
                'FontSize', 34, 'FontWeight', 'bold', 'FontColor', P.espresso);
            obj.Widgets.BusyDetail = uilabel(busy, 'Position', [140 322 1000 36], ...
                'Text', '', 'HorizontalAlignment', 'center', 'FontName', fn, ...
                'FontSize', 20, 'FontColor', P.taupe);
            trackFrame = uipanel(busy, 'Position', [439 279 402 14], ...
                'BackgroundColor', P.taupe, 'BorderType', 'none');
            track = uipanel(trackFrame, 'Position', [1 1 400 12], ...
                'BackgroundColor', P.linen, 'BorderType', 'none');
            obj.Widgets.BusyTrack = track;
            obj.Widgets.BusyFill = uipanel(track, 'Position', [0 0 1 12], ...
                'BackgroundColor', P.terracotta, 'BorderType', 'none');

            warn = uipanel(R, 'Position', [0 0 1280 700], 'BackgroundColor', ivory, ...
                'BorderType', 'none', 'Visible', 'off');
            obj.Widgets.WarnOverlay = warn;
            uilabel(warn, 'Position', [140 400 1000 56], 'Text', 'ยังอยู่ไหม?', ...
                'HorizontalAlignment', 'center', 'FontName', fn, ...
                'FontSize', 40, 'FontWeight', 'bold', 'FontColor', P.espresso);
            obj.Widgets.WarnDetail = uilabel(warn, 'Position', [140 310 1000 80], ...
                'Text', '', 'HorizontalAlignment', 'center', 'FontName', fn, ...
                'FontSize', 22, 'FontColor', P.taupe);
            primaryBtn(warn, [490 200 300 70], 'ยังอยู่ ทำต่อ', 26, ...
                @(~,~) obj.stillHere());

            % applyScale owns every position; MATLAB's proportional auto-resize
            % of panel children would otherwise shift them a second time.
            set(findall(R, '-property', 'AutoResizeChildren'), 'AutoResizeChildren', 'off');
            obj.updateAdvanced();
            obj.Fig.SizeChangedFcn = @(~,~) obj.centerStage();
            if fullscreen
                try
                    obj.Fig.WindowState = 'fullscreen';
                catch err
                    obj.Logger.warn('Fullscreen unavailable: %s', err.message);
                end
            end
            obj.centerStage();
        end
    end
end
