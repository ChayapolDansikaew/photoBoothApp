function [img, c] = synthSkinStep(n)
%SYNTHSKINSTEP n-by-n image: left half light skin, right half darker skin.
% c = last column of the left half (the step is between c and c+1).
c = n / 2;
img = zeros(n, n, 3);
left = [224 172 138] / 255;
right = [150 100 75] / 255;
for k = 1:3
    img(:, 1:c, k) = left(k);
    img(:, c+1:end, k) = right(k);
end
end
