function out = blendSmoothing(prep, amount)
%BLENDSMOOTHING out = I.*(1 - a*M) + smooth.*(a*M), with a = amount/100.
% amount = 0 returns the original image exactly.
arguments
    prep (1,1) struct
    amount (1,1) double {mustBeInRange(amount, 0, 100)}
end
W = (amount / 100) * prep.M;
out = prep.I .* (1 - W) + prep.smooth .* W;
out = imgproc.restoreClass(out, prep.cls);
end
