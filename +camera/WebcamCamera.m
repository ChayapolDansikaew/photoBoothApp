classdef WebcamCamera < camera.GPhotoCamera
    %WEBCAMCAMERA The laptop's built-in webcam on Windows or macOS.
    % Runs camera_bridge/bridge.py --webcam natively (no WSL) with a Python
    % that has OpenCV (pip install -r camera_bridge/requirements-webcam.txt)
    % and speaks the same TCP protocol as the gphoto2 bridge.
    %
    % macOS: the first start asks for camera access for MATLAB; allow it in
    % System Settings > Privacy & Security > Camera, then reconnect.
    properties (SetAccess = private)
        Device (1,1) double = 0
        PythonExe (1,:) char = ''
    end
    methods
        function obj = WebcamCamera(opts)
            arguments
                opts.Port (1,1) double = 5555
                opts.Device (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                opts.Resolution (1,2) double {mustBePositive} = [1280 720]
                opts.PythonExe (1,:) char = ''
                opts.AutoLaunch (1,1) logical = true
                opts.ConnectTimeout (1,1) double = 20
                opts.Fake (1,1) logical = false   % bridge FakeCamera, for tests
            end
            py = opts.PythonExe;
            if isempty(py) && opts.AutoLaunch
                py = camera.WebcamCamera.findPython();
            end
            root = fileparts(fileparts(mfilename('fullpath')));
            script = fullfile(root, 'camera_bridge', 'bridge.py');
            if opts.Fake
                mode = {'--fake'};
            else
                mode = {'--webcam', '--device', num2str(opts.Device), ...
                    '--width', num2str(opts.Resolution(1)), '--height', num2str(opts.Resolution(2))};
            end
            cmd = [{py, '-u', script}, mode, {'--port', num2str(opts.Port)}];
            obj@camera.GPhotoCamera('Port', opts.Port, 'AutoLaunch', opts.AutoLaunch, ...
                'UseWslPaths', false, 'ConnectTimeout', opts.ConnectTimeout, ...
                'LaunchCommand', cmd);
            obj.Device = opts.Device;
            obj.PythonExe = py;
        end
    end
    methods (Static)
        function py = findPython(forceRescan)
            %FINDPYTHON First Python 3 on this machine that can import cv2.
            % Searches the usual install locations (MATLAB launched from the
            % Dock/Start menu often has a minimal PATH), then PATH itself.
            persistent cached
            if nargin < 1, forceRescan = false; end
            if ~isempty(cached) && ~forceRescan
                py = cached;
                return;
            end
            cands = camera.WebcamCamera.pythonCandidates();
            for k = 1:numel(cands)
                c = cands{k};
                if contains(c, filesep) && ~isfile(c), continue; end
                [status, ~] = system(sprintf('"%s" -c "import cv2"', c));
                if status == 0
                    cached = c;
                    py = c;
                    return;
                end
            end
            error('camera:noPython', ['No Python with OpenCV found. Install Python 3 and run: ' ...
                'pip install -r camera_bridge/requirements-webcam.txt ' ...
                '(or set "pythonExe" in config.json).']);
        end

        function cands = pythonCandidates()
            cands = {};
            if ispc
                base = fullfile(getenv('LOCALAPPDATA'), 'Programs', 'Python');
                d = dir(fullfile(base, 'Python3*'));
                names = sort({d.name});
                for k = numel(names):-1:1        % newest version first
                    cands{end+1} = fullfile(base, names{k}, 'python.exe'); %#ok<AGROW>
                end
                d = dir(fullfile(getenv('ProgramFiles'), 'Python3*'));
                names = sort({d.name});
                for k = numel(names):-1:1
                    cands{end+1} = fullfile(getenv('ProgramFiles'), names{k}, 'python.exe'); %#ok<AGROW>
                end
                cands = [cands, {'python', 'python3'}];
            else
                cands = {'/opt/homebrew/bin/python3', '/usr/local/bin/python3', ...
                    '/Library/Frameworks/Python.framework/Versions/Current/bin/python3', ...
                    fullfile(getenv('HOME'), 'miniconda3', 'bin', 'python3'), ...
                    fullfile(getenv('HOME'), 'anaconda3', 'bin', 'python3'), ...
                    '/usr/bin/python3', 'python3'};
            end
        end
    end
end
