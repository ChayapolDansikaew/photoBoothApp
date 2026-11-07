function s = edgeStep(img)
%EDGESTEP Mean (over middle rows) of the largest horizontal luma jump
% between adjacent pixels. A sharp step keeps its full height; blur lowers it.
L = lumaOf(img);
n = size(L, 1);
rows = round(0.125*n):round(0.875*n);
d = abs(diff(L(rows,:), 1, 2));
s = mean(max(d, [], 2));
end
