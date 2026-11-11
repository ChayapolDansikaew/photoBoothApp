classdef MockCamera < camera.CameraBackend
    %MOCKCAMERA Cycles through images in assets/mock/ (or synthetic faces
    % if none exist), adding slight per-frame noise in getPreviewFrame().
    properties (SetAccess = private)
        Folder (1,:) char
        Images (1,:) cell = {}
        Index (1,1) double = 1
        Ready (1,1) logical = false
    end
    methods
        function obj = MockCamera(folder)
            if nargin < 1 || isempty(folder)
                root = fileparts(fileparts(mfilename('fullpath')));
                folder = fullfile(root, 'assets', 'mock');
            end
            obj.Folder = char(folder);
        end

        function start(obj)
            files = [dir(fullfile(obj.Folder, '*.jpg')); dir(fullfile(obj.Folder, '*.png'))];
            obj.Images = cell(1, numel(files));
            for k = 1:numel(files)
                obj.Images{k} = im2uint8(imread(fullfile(files(k).folder, files(k).name)));
            end
            if isempty(obj.Images)
                [X, Y] = meshgrid(1:600, 1:450);
                face = ((X - 300)/115).^2 + ((Y - 225)/155).^2 <= 1;
                skin = [224 172 138] / 255;
                bg = [0.2 0.4 0.8];
                img = cat(3, face*skin(1) + ~face*bg(1), ...
                             face*skin(2) + ~face*bg(2), ...
                             face*skin(3) + ~face*bg(3));
                obj.Images = {im2uint8(img)};
            end
            obj.Index = 1;
            obj.Ready = true;
        end

        function stop(obj)
            obj.Ready = false;
        end

        function tf = isReady(obj)
            tf = obj.Ready;
        end

        function frame = getPreviewFrame(obj)
            if ~obj.Ready, obj.start(); end
            base = im2double(obj.Images{obj.Index});
            noisy = min(max(base + 0.008 * randn(size(base)), 0), 1);
            frame = im2uint8(noisy);
        end

        function outPath = capture(obj, outPath)
            if ~obj.Ready, obj.start(); end
            img = obj.Images{obj.Index};
            obj.Index = mod(obj.Index, numel(obj.Images)) + 1;
            if nargin >= 2 && ~isempty(outPath)
                folder = fileparts(char(outPath));
                if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
                imwrite(img, char(outPath), 'Quality', 95);
            else
                outPath = img;
            end
        end
    end
end
