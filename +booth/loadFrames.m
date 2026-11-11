function [frames, problems] = loadFrames(folder)
%LOADFRAMES Load every <name>.png (+ optional <name>.json) in folder.
% JSON: {"name": "Classic B&W", "tone": "bw"}; both keys optional
% (defaults: file name, 'bw'). Invalid frames are skipped with warning
% booth:frameSkipped and described in the cellstr problems. If nothing
% loads, warns booth:noFrames and returns booth.defaultFrame().
frames = struct('name', {}, 'tone', {}, 'path', {}, 'rgb', {}, 'alpha', {}, 'slots', {});
problems = {};
files = dir(fullfile(folder, '*.png'));
for k = 1:numel(files)
    p = fullfile(files(k).folder, files(k).name);
    try
        frames(end+1) = readFrame(p); %#ok<AGROW>
    catch err
        msg = sprintf('Skipping frame %s: %s', files(k).name, err.message);
        warning('booth:frameSkipped', '%s', msg);
        problems{end+1} = msg; %#ok<AGROW>
    end
end
if isempty(frames)
    warning('booth:noFrames', 'No usable frames in %s; using built-in frame.', folder);
    problems{end+1} = 'No usable frames; using built-in frame.';
    frames = booth.defaultFrame();
end
end

function f = readFrame(p)
[rgb, map, alpha] = imread(p);
if isempty(alpha)
    error('booth:noAlpha', 'PNG has no transparency (alpha channel).');
end
if ~isempty(map), rgb = ind2rgb(rgb, map); end
rgb = im2double(rgb);
if size(rgb, 3) == 1, rgb = repmat(rgb, 1, 1, 3); end
alpha = im2double(alpha);
slots = booth.detectSlots(alpha);
[folder, base] = fileparts(p);
[name, tone] = readMeta(fullfile(folder, [base '.json']), base);
f = struct('name', name, 'tone', tone, 'path', p, 'rgb', rgb, 'alpha', alpha, 'slots', slots);
end

function [name, tone] = readMeta(jsonPath, base)
name = base;
tone = 'bw';
if ~isfile(jsonPath), return; end
meta = jsondecode(fileread(jsonPath, 'Encoding', 'UTF-8'));
if isfield(meta, 'name'), name = char(meta.name); end
if isfield(meta, 'tone')
    if ismember(meta.tone, imgproc.toneNames())
        tone = char(meta.tone);
    else
        warning('booth:unknownTone', 'Frame %s: unknown tone "%s"; using bw.', base, meta.tone);
    end
end
end
