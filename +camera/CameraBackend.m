classdef (Abstract) CameraBackend < handle
    %CAMERABACKEND Common interface for GPhotoCamera and MockCamera.
    methods (Abstract)
        start(obj)
        stop(obj)
        tf = isReady(obj)
        frame = getPreviewFrame(obj)
        outPath = capture(obj, outPath)
    end
end
