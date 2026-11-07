function alpha = makeAlpha(h, w, rects)
%MAKEALPHA Opaque h-by-w alpha with transparent holes at rects [x y w h].
alpha = ones(h, w);
for k = 1:size(rects, 1)
    r = rects(k,:);
    alpha(r(2):r(2)+r(4)-1, r(1):r(1)+r(3)-1) = 0;
end
end
