classdef SessionStore
    %SESSIONSTORE Save photobooth sessions to <Root>/yyyyMMdd_HHmmss[_n]/
    % and list them newest first (used by gallery and idle slideshow).
    % Session files: strip.png, animation.gif, raw_1..4.jpg,
    % photo_1..4.png, meta.json
    properties (SetAccess = immutable)
        Root (1,:) char
    end
    methods
        function obj = SessionStore(root)
            obj.Root = char(root);
            if ~isfolder(obj.Root)
                mkdir(obj.Root);
            end
        end

        function d = saveSession(obj, s)
            %SAVESESSION s fields: strip (image), photos (1x4 cell of
            % images), raws (1x4 cell; each a JPEG file path to copy or an
            % image to encode), meta (struct), gifDelay (s), gifLongSide (px)
            d = obj.newSessionFolder();
            imwrite(clamp01(s.strip), fullfile(d, 'strip.png'));
            for k = 1:numel(s.photos)
                imwrite(clamp01(s.photos{k}), fullfile(d, sprintf('photo_%d.png', k)));
                dst = fullfile(d, sprintf('raw_%d.jpg', k));
                raw = s.raws{k};
                if ischar(raw) || isstring(raw)
                    copyfile(raw, dst);
                else
                    imwrite(clamp01(raw), dst, 'Quality', 95);
                end
            end
            booth.makeGif(s.photos, fullfile(d, 'animation.gif'), s.gifDelay, s.gifLongSide);
            fid = fopen(fullfile(d, 'meta.json'), 'w', 'n', 'UTF-8');
            fprintf(fid, '%s', jsonencode(s.meta, 'PrettyPrint', true));
            fclose(fid);
        end

        function list = listSessions(obj)
            %LISTSESSIONS struct array (name, folder, stripPath), newest first.
            list = struct('name', {}, 'folder', {}, 'stripPath', {});
            ds = dir(obj.Root);
            ds = ds([ds.isdir] & ~startsWith({ds.name}, '.'));
            names = sort({ds.name});
            for k = numel(names):-1:1
                p = fullfile(obj.Root, names{k}, 'strip.png');
                if isfile(p)
                    list(end+1) = struct('name', names{k}, ...
                        'folder', fullfile(obj.Root, names{k}), 'stripPath', p); %#ok<AGROW>
                end
            end
        end
    end
    methods (Access = private)
        function d = newSessionFolder(obj)
            base = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            d = fullfile(obj.Root, base);
            n = 2;
            while isfolder(d)
                d = fullfile(obj.Root, sprintf('%s_%d', base, n));
                n = n + 1;
            end
            mkdir(d);
        end
    end
end

function x = clamp01(x)
if isfloat(x)
    x = min(max(x, 0), 1);
end
end
