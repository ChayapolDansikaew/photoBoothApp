function results = runAllTests(target)
%RUNALLTESTS Run unit tests in tests/. Optional target = test file name
% without extension (e.g. 'testApplyTone'). Errors if any test fails.
% (Named runAllTests, not runTests, so it cannot shadow the built-in
% runtests on case-insensitive Windows file systems.)
root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'tests', 'helpers'));
if nargin < 1 || isempty(target)
    suite = fullfile(root, 'tests');
else
    suite = fullfile(root, 'tests', [char(target) '.m']);
end
results = runtests(suite);
disp(table(results));
assertSuccess(results);
end
