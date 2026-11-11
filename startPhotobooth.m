function app = startPhotobooth(configPath)
%STARTPHOTOBOOTH Launch the MATLAB Photobooth kiosk application.
root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'tools'));

if isempty(dir(fullfile(root, 'frames', '*.png')))
    makeSampleFrames(fullfile(root, 'frames'));
end
if isempty(dir(fullfile(root, 'assets', 'mock', '*.jpg')))
    makeMockPhotos(fullfile(root, 'assets', 'mock'));
end
if nargin < 1 || isempty(configPath)
    configPath = fullfile(root, 'config.json');
end
cfg = booth.loadConfig(configPath);
app = PhotoboothApp(cfg);
end
