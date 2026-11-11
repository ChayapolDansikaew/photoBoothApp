classdef testCameraBackends < matlab.unittest.TestCase
    methods (Test)
        function mockCameraPreviewAndCaptureCycle(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            mockDir = fullfile(d, 'mock');
            makeMockPhotos(mockDir);
            cam = camera.MockCamera(mockDir);
            cam.start();
            tc.addTeardown(@() cam.stop());
            tc.verifyTrue(cam.isReady());

            f1 = cam.getPreviewFrame();
            f2 = cam.getPreviewFrame();
            tc.verifyClass(f1, 'uint8');
            tc.verifySize(f1, [450 600 3]);
            tc.verifyNotEqual(f1, f2);   % subtle live noise differs each frame

            out1 = fullfile(d, 'shot1.jpg');
            res1 = cam.capture(out1);
            tc.verifyEqual(res1, out1);
            tc.verifyTrue(isfile(out1));
            img1 = imread(out1);
            tc.verifySize(img1, [450 600 3]);
        end

        function wslPathConversion(tc)
            p = camera.GPhotoCamera.toWslPath('C:\Users\ArthurZ\Desktop\shot.jpg');
            tc.verifyEqual(p, '/mnt/c/Users/ArthurZ/Desktop/shot.jpg');
        end

        function webcamCommandLine(tc)
            cam = camera.WebcamCamera('PythonExe', 'mypython', 'AutoLaunch', false, ...
                'Device', 1, 'Resolution', [1920 1080], 'Port', 5601);
            cmd = cam.LaunchCommand;
            tc.verifyEqual(cmd{1}, 'mypython');
            tc.verifySubstring(cmd{3}, fullfile('camera_bridge', 'bridge.py'));
            tc.verifyEqual(cmd(4:end), {'--webcam', '--device', '1', '--width', '1920', ...
                '--height', '1080', '--port', '5601'});
            tc.verifyFalse(cam.UseWslPaths);
        end

        function webcamCameraLaunchesNativeBridge(tc)
            % Full path through the native launcher, with the bridge's fake
            % camera standing in for the webcam hardware.
            py = webcamPythonOrSkip(tc);
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            port = 5760 + randi(200);
            cam = camera.WebcamCamera('Fake', true, 'Port', port, 'PythonExe', py, ...
                'ConnectTimeout', 15);
            tc.addTeardown(@() cam.stop());
            cam.start();
            tc.verifyTrue(cam.isReady());
            tc.verifySize(cam.getPreviewFrame(), [48 64 3]);
            out = fullfile(d, 'cap.jpg');
            cam.capture(out);
            tc.verifyTrue(isfile(out));

            cam.stop();
            tc.verifyEmpty(cam.Process, 'stop() must end the bridge so the camera is released');
            stillListening = true;
            try
                tcpclient('127.0.0.1', port, 'Timeout', 1, 'ConnectTimeout', 1);
            catch
                stillListening = false;
            end
            tc.verifyFalse(stillListening, 'Bridge still listening after stop().');
        end

        function webcamBridgeFailureFailsFast(tc)
            py = webcamPythonOrSkip(tc);
            cam = camera.WebcamCamera('Device', 37, 'Port', 5960 + randi(30), ...
                'PythonExe', py, 'ConnectTimeout', 30);
            tc.addTeardown(@() cam.stop());
            t0 = tic;
            err = [];
            try
                cam.start();
            catch err
            end
            tc.assertNotEmpty(err, 'start() must fail when the webcam cannot be opened.');
            tc.verifyEqual(err.identifier, 'camera:bridgeExited');
            tc.verifyLessThan(toc(t0), 25, 'A bridge that exits must not wait out the timeout.');
            tc.verifySubstring(err.message, 'webcam 37');
            tc.verifyFalse(cam.isReady());
        end

        function gphotoCameraTalksToPythonBridge(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            sampleJpg = fullfile(d, 'sample.jpg');
            imwrite(im2uint8(synthFace(120, 0.02)), sampleJpg);

            root = fileparts(which('runAllTests'));
            bridgePy = fullfile(root, 'camera_bridge', 'bridge.py');
            port = 5560 + randi(200);
            pyExe = 'python';
            localPy = fullfile(getenv('LOCALAPPDATA'), 'Programs', 'Python', 'Python313', 'python.exe');
            if isfile(localPy), pyExe = localPy; end
            pb = java.lang.ProcessBuilder({pyExe, bridgePy, '--fake', '--port', num2str(port), '--sample-jpg', sampleJpg});
            pb.redirectErrorStream(true);
            proc = pb.start();
            tc.addTeardown(@() proc.destroy());

            cam = camera.GPhotoCamera('Host', '127.0.0.1', 'Port', port, ...
                'AutoLaunch', false, 'UseWslPaths', false, 'ConnectTimeout', 5);
            tc.addTeardown(@() cam.stop());
            cam.start();
            tc.verifyTrue(cam.isReady());

            frame = cam.getPreviewFrame();
            tc.verifyClass(frame, 'uint8');
            tc.verifySize(frame, [48 64 3]);

            outJpg = fullfile(d, 'cap.jpg');
            got = cam.capture(outJpg);
            tc.verifyEqual(got, outJpg);
            tc.verifyTrue(isfile(outJpg));
            tc.verifySize(imread(outJpg), [120 120 3]);
        end
    end
end

function py = webcamPythonOrSkip(tc)
try
    py = camera.WebcamCamera.findPython();
catch
    py = '';
end
tc.assumeNotEmpty(py, 'No Python with OpenCV on this machine.');
end
