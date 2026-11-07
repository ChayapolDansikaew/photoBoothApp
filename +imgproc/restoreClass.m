function out = restoreClass(out, cls)
%RESTORECLASS Clamp a double image to [0,1] and cast it to class cls
% ('uint8' | 'uint16' | 'single' | 'double').
out = min(max(out, 0), 1);
switch cls
    case 'uint8',  out = im2uint8(out);
    case 'uint16', out = im2uint16(out);
    case 'single', out = single(out);
    otherwise,     out = double(out);
end
end
