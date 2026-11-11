function frame = defaultFrame()
%DEFAULTFRAME Built-in plain white 2x6" strip (600x1800, 4x1 slots),
% used when frames/ has no usable frame.
h = 1800; w = 600;
slots = [41 41 520 390; 41 471 520 390; 41 901 520 390; 41 1331 520 390];
alpha = ones(h, w);
for k = 1:4
    s = slots(k,:);
    alpha(s(2):s(2)+s(4)-1, s(1):s(1)+s(3)-1) = 0;
end
frame = struct('name', 'Plain White', 'tone', 'bw', 'path', '', ...
    'rgb', ones(h, w, 3), 'alpha', alpha, 'slots', slots);
end
