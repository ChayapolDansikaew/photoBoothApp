classdef Logger < handle
    %LOGGER Append timestamped lines to a UTF-8 log file. Never throws
    % (logging must not crash the booth). Usage:
    %   lg = booth.Logger('logs/photobooth.log'); lg.warn('x=%d', 3);
    properties (SetAccess = immutable)
        FilePath (1,:) char
    end
    methods
        function obj = Logger(filePath)
            obj.FilePath = char(filePath);
            folder = fileparts(obj.FilePath);
            if ~isempty(folder) && ~isfolder(folder)
                mkdir(folder);
            end
        end
        function info(obj, fmt, varargin)
            obj.write('INFO', fmt, varargin{:});
        end
        function warn(obj, fmt, varargin)
            obj.write('WARN', fmt, varargin{:});
        end
        function err(obj, fmt, varargin)
            obj.write('ERROR', fmt, varargin{:});
        end
    end
    methods (Access = private)
        function write(obj, level, fmt, varargin)
            fid = fopen(obj.FilePath, 'a', 'n', 'UTF-8');
            if fid < 0, return; end
            closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
            stamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            fprintf(fid, '%s [%s] %s\n', stamp, level, sprintf(fmt, varargin{:}));
        end
    end
end
