function [names,offsets,labels] = common_horizons(n_fore)
% This function defines the set of prediction horizons used throughout the
% toolbox.
%
% The toolbox originally supported two predictions only (a back-cast and a
% nowcast, or a nowcast and a one-quarter-ahead forecast). This helper
% generalises that to an arbitrary number of quarters ahead, while keeping
% the names of the first three horizons ('Bac', 'Now', 'For') identical to
% the original toolbox so that existing output files, Excel sheets and
% saved workspaces remain readable.
%
% INPUTS
% - n_fore [scalar] = maximum forecast horizon, in quarters ahead of the
%                     nowcast quarter. n_fore = 1 reproduces the original
%                     toolbox (back-cast, nowcast, one quarter ahead).
%
% OUTPUTS
% - names [cell vector] = field / sheet names of the horizons
%                         = {'Bac','Now','For','For2',...,'For<n_fore>'}
% - offsets [vector] = offset of each horizon, in months, relative to the
%                      last month of the nowcast quarter
%                      = [-3, 0, 3, 6, ..., 3*n_fore]
% - labels [cell vector] = human-readable labels of the horizons
%                          = {'back-cast (t-1)','nowcast (t)','forecast (t+1)',...}
%
% NB: the first element is always the back-cast. Element k (k >= 2)
%     corresponds to horizon h = k-2 quarters ahead of the nowcast quarter.
%

% Check input
if ~isscalar(n_fore) || n_fore < 1 || n_fore ~= round(n_fore)
    error('n_fore should be a positive integer (1 = original toolbox behaviour, i.e. nowcast and one quarter ahead).')
end

% Names of the horizons
names = cell(1,n_fore+2);
names{1} = 'Bac';
names{2} = 'Now';
names{3} = 'For';
for hh = 2:n_fore
    names{hh+2} = strcat('For',num2str(hh));
end

% Offsets in months relative to the last month of the nowcast quarter
offsets = 3*((1:(n_fore+2)) - 2);

% Human-readable labels
labels = cell(1,n_fore+2);
labels{1} = 'back-cast (t-1)';
labels{2} = 'nowcast (t)';
for hh = 1:n_fore
    labels{hh+2} = strcat('forecast (t+',num2str(hh),')');
end

end
