function slots = detectSlots(alpha)
%DETECTSLOTS Find the 4 transparent photo windows in a frame's alpha
% channel (double, 0..1). Returns 4x4 [x y w h] in 1-based pixel coords,
% ordered row by row (top -> bottom), left -> right within a row. Slots
% whose centers differ by <= 10% of slot height count as the same row.
% Transparent regions smaller than 1% of the frame are ignored.
holes = alpha < 10/255;
stats = regionprops(bwconncomp(holes, 4), 'BoundingBox', 'Area', 'Centroid');
stats = stats([stats.Area] >= 0.01 * numel(alpha));
if numel(stats) ~= 4
    error('booth:badSlotCount', 'Expected 4 transparent slots, found %d.', numel(stats));
end
bb = vertcat(stats.BoundingBox);           % [x-0.5 y-0.5 w h]
slots = [bb(:,1:2) + 0.5, bb(:,3:4)];
c = vertcat(stats.Centroid);

[~, order] = sort(c(:,2));
slots = slots(order,:);
c = c(order,:);
rowId = ones(4, 1);
ref = c(1,2);
for k = 2:4
    if abs(c(k,2) - ref) > 0.1 * slots(k,4)
        ref = c(k,2);
        rowId(k) = rowId(k-1) + 1;
    else
        rowId(k) = rowId(k-1);
    end
end
[~, order] = sortrows([rowId c(:,1)]);
slots = slots(order,:);
end
