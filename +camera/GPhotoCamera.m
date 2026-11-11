classdef GPhotoCamera < camera.CameraBackend
    %GPHOTOCAMERA Talks to camera_bridge/bridge.py over TCP.
    % By default it launches the gphoto2 bridge inside WSL; LaunchCommand
    % replaces that (WebcamCamera uses it to run the bridge natively).
    % Bridge output goes to logs/bridge.log.
    properties (SetAccess = private)
        Host (1,:) char = '127.0.0.1'
        Port (1,1) double = 5555
        AutoLaunch (1,1) logical = true
        UseWslPaths (1,1) logical = true
        ConnectTimeout (1,1) double = 10
        LaunchCommand cell = {}
        Client = []
        Ready (1,1) logical = false
        Process = []       % java.lang.Process of a bridge this object launched
    end
    methods
        function obj = GPhotoCamera(opts)
            arguments
                opts.Host (1,:) char = '127.0.0.1'
                opts.Port (1,1) double = 5555
                opts.AutoLaunch (1,1) logical = true
                opts.UseWslPaths (1,1) logical = true
                opts.ConnectTimeout (1,1) double = 10
                opts.LaunchCommand cell = {}
            end
            obj.Host = opts.Host;
            obj.Port = opts.Port;
            obj.AutoLaunch = opts.AutoLaunch;
            obj.UseWslPaths = opts.UseWslPaths;
            obj.ConnectTimeout = opts.ConnectTimeout;
            obj.LaunchCommand = opts.LaunchCommand;
        end

        function start(obj)
            if obj.tryConnect()
                return;
            end
            logFile = ''; logOffset = 0;
            if obj.AutoLaunch
                [logFile, logOffset] = obj.launchBridge();
            end
            t0 = tic;
            while toc(t0) < obj.ConnectTimeout
                pause(0.25);
                if obj.tryConnect()
                    return;
                end
                if ~isempty(obj.Process) && ~obj.Process.isAlive()
                    obj.Process = [];
                    error('camera:bridgeExited', 'Camera bridge exited: %s', ...
                        camera.GPhotoCamera.lastLogLine(logFile, logOffset));
                end
            end
            obj.killBridge();
            error('camera:connectFailed', ...
                'Could not connect to camera bridge on %s:%d.', obj.Host, obj.Port);
        end

        function stop(obj)
            if ~isempty(obj.Client)
                try
                    writeline(obj.Client, 'QUIT');
                catch
                end
            end
            obj.Client = [];
            obj.Ready = false;
            obj.killBridge();
        end

        function tf = isReady(obj)
            tf = obj.Ready && ~isempty(obj.Client);
        end

        function frame = getPreviewFrame(obj)
            if ~obj.isReady()
                error('camera:notReady', 'GPhotoCamera is not connected.');
            end
            writeline(obj.Client, 'PREVIEW');
            hdr = char(readline(obj.Client));
            if ~startsWith(hdr, 'OK ')
                error('camera:previewFailed', 'Bridge preview failed: %s', hdr);
            end
            vals = sscanf(hdr(4:end), '%d %d %d');
            w = vals(1); h = vals(2); nbytes = vals(3);
            raw = read(obj.Client, nbytes, 'uint8');
            frame = permute(reshape(uint8(raw), [3, w, h]), [3, 2, 1]);
        end

        function outPath = capture(obj, outPath)
            if ~obj.isReady()
                error('camera:notReady', 'GPhotoCamera is not connected.');
            end
            outPath = char(outPath);
            folder = fileparts(outPath);
            if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
            remotePath = outPath;
            if obj.UseWslPaths
                remotePath = camera.GPhotoCamera.toWslPath(outPath);
            end
            writeline(obj.Client, ['CAPTURE ' remotePath]);
            resp = char(readline(obj.Client));
            if ~startsWith(resp, 'OK ')
                error('camera:captureFailed', 'Bridge capture failed: %s', resp);
            end
        end
    end
    methods (Access = private)
        function [logFile, logOffset] = launchBridge(obj)
            root = fileparts(fileparts(mfilename('fullpath')));
            cmd = obj.LaunchCommand;
            if isempty(cmd)
                wslScript = camera.GPhotoCamera.toWslPath(fullfile(root, 'camera_bridge', 'bridge.py'));
                cmd = {'wsl', 'python3', wslScript, '--port', num2str(obj.Port)};
            end
            logDir = fullfile(root, 'logs');
            if ~isfolder(logDir), mkdir(logDir); end
            logFile = fullfile(logDir, 'bridge.log');
            logOffset = 0;
            if isfile(logFile), logOffset = dir(logFile).bytes; end
            pb = java.lang.ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            pb.redirectOutput(javaMethod('appendTo', 'java.lang.ProcessBuilder$Redirect', ...
                java.io.File(logFile)));
            obj.Process = pb.start();
        end

        function killBridge(obj)
            %KILLBRIDGE Give a bridge we launched a moment to exit after QUIT
            % (so it releases the camera cleanly), then make sure it is gone.
            if isempty(obj.Process), return; end
            try
                if ~obj.Process.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)
                    obj.Process.destroy();
                end
            catch
            end
            obj.Process = [];
        end

        function ok = tryConnect(obj)
            ok = false;
            try
                c = tcpclient(obj.Host, obj.Port, 'Timeout', 5);
                configureTerminator(c, 'LF');
                writeline(c, 'PING');
                resp = strtrim(char(readline(c)));
                if strcmp(resp, 'OK pong')
                    obj.Client = c;
                    obj.Ready = true;
                    ok = true;
                end
            catch
                obj.Client = [];
                obj.Ready = false;
            end
        end
    end
    methods (Static)
        function line = lastLogLine(logFile, offset)
            %LASTLOGLINE Last BRIDGE_ line (else last non-empty line) written to
            % the log after byte OFFSET, i.e. by the bridge just launched.
            line = 'see logs/bridge.log';
            if isempty(logFile) || ~isfile(logFile), return; end
            fid = fopen(logFile, 'r', 'n', 'UTF-8');
            if fid < 0, return; end
            fseek(fid, offset, 'bof');
            txt = fread(fid, [1 Inf], '*char');
            fclose(fid);
            lines = strtrim(splitlines(string(txt)));
            lines = lines(lines ~= "");
            if isempty(lines), return; end
            tagged = lines(startsWith(lines, "BRIDGE_"));
            if ~isempty(tagged)
                line = char(tagged(end));
            else
                line = char(lines(end));
            end
        end

        function wsl = toWslPath(winPath)
            p = strrep(char(winPath), '\', '/');
            if numel(p) >= 2 && p(2) == ':'
                drive = lower(p(1));
                wsl = ['/mnt/' drive p(3:end)];
            else
                wsl = p;
            end
        end
    end
end
