function compare_horizons(evalfile,mth_of_q)
% Compare RMSE across forecast horizons on a COMMON set of target quarters.
%
% WHY THIS IS NEEDED
% At a given real-time month the back-cast targets the previous quarter, the
% nowcast the current one, and the horizon t+h the quarter h ahead. Over a fixed
% window of real-time months, each horizon therefore evaluates a DIFFERENT set of
% target quarters, shifted forward by h. Comparing the RMSE columns of the
% evaluation file directly compares six different samples, and over a short
% window those samples barely overlap - the back-cast and t+4 columns can have no
% quarter in common at all. Any pattern across horizons then reflects the
% calendar, not forecast difficulty.
%
% This script restricts every horizon to the quarters that ALL horizons cover,
% and holds the month of the quarter at which the forecast is made fixed, so the
% horizons become comparable. It also reports the standard deviation of the
% realised target over the same quarters: a long-horizon forecast that has
% reverted to the unconditional mean should have an RMSE close to it.
%
% INPUTS
% - evalfile [string] = path to an evaluation workbook written by
%   common_eval_models, e.g. './eval/FIN/FIN_DFM_evaluation_b1_1.xlsx'
%   Pass 'selftest' to run the built-in check on synthetic data.
% - mth_of_q [scalar 1/2/3] = month of the quarter at which the forecast is made
%   (optional, default 3 = the last month, i.e. the largest information set)
%
% OUTPUT
% Printed table. Nothing is written to disk.

if nargin < 2 || isempty(mth_of_q), mth_of_q = 3; end
if nargin < 1 || isempty(evalfile), error('Give the path to an evaluation workbook, or ''selftest''.'); end

if strcmp(evalfile,'selftest')
    run_selftest();
    return
end

hor_names = {'Bac','Now','For','For2','For3','For4'};

% ---------------------------------------------------------------------
%% Read the raw predictions of each horizon
% ---------------------------------------------------------------------

P = struct();
present = false(1,numel(hor_names));
for hh = 1:numel(hor_names)
    try
        raw = readmatrix(evalfile,'Sheet',hor_names{hh});
    catch
        continue % this horizon was not produced (n_fore smaller than 4)
    end
    % Keep only the block of raw predictions: the accuracy metrics written
    % underneath have text in the first column and therefore NaN here
    keep = all(isfinite(raw(:,1:4)),2);
    P.(hor_names{hh}) = raw(keep,1:7);
    present(hh) = true;
end
hor_names = hor_names(present);
if numel(hor_names) < 2
    error('Fewer than two horizons found in %s.',evalfile);
end

% ---------------------------------------------------------------------
%% Report the coverage of each horizon
% ---------------------------------------------------------------------

fprintf('\n================ HORIZON COMPARISON ================\n');
fprintf('File: %s\n',evalfile);
fprintf('Forecasts made in month %d of the quarter.\n\n',mth_of_q);

fprintf('--- Coverage of each horizon, as produced ---\n');
fprintf('%-6s %-8s %-22s %s\n','hor','rounds','target quarters','distinct');
qsets = cell(1,numel(hor_names));
for hh = 1:numel(hor_names)
    D = P.(hor_names{hh});
    qi = 4*D(:,3) + ceil(D(:,4)/3);            % running quarter index of the target
    qsets{hh} = unique(qi);
    fprintf('%-6s %-8d %d Q%d to %d Q%d      %d\n',hor_names{hh},size(D,1), ...
            D(1,3),ceil(D(1,4)/3),D(end,3),ceil(D(end,4)/3),numel(qsets{hh}));
end

% Overlap between the shortest and the longest horizon
common = qsets{1};
for hh = 2:numel(hor_names)
    common = intersect(common,qsets{hh});
end
fprintf('\nQuarters covered by EVERY horizon: %d\n',numel(common));

if numel(common) < 4
    fprintf('\n[!] That is too few to compare horizons on.\n');
    fprintf('    Each horizon shifts its target window forward by one quarter, so a\n');
    fprintf('    window of R real-time months leaves only about R/3 - n_fore - 1\n');
    fprintf('    quarters in common. To get N comparable quarters at n_fore = 4 you\n');
    fprintf('    need roughly 3*(N + 5) evaluation months.\n');
    fprintf('    Widen Eval.eval_startyear / eval_endyear and run again.\n');
    if isempty(common)
        fprintf('\n=====================================================\n\n');
        return
    end
end

% ---------------------------------------------------------------------
%% Recompute the metrics on the common quarters
% ---------------------------------------------------------------------

fprintf('\n--- Like-for-like: same target quarters, same month of quarter ---\n');
fprintf('%-6s %-8s %-10s %-10s %-10s %s\n','hor','n','RMSE mod','RMSE AR','sd(actual)','RMSE/sd');
for hh = 1:numel(hor_names)
    [n,rmse_mod,rmse_ar,sd_act] = metrics_on(P.(hor_names{hh}),common,mth_of_q);
    if n == 0
        fprintf('%-6s %-8d %s\n',hor_names{hh},0,'no rounds in this month of the quarter');
    else
        fprintf('%-6s %-8d %-10.3f %-10.3f %-10.3f %.2f\n', ...
                hor_names{hh},n,rmse_mod,rmse_ar,sd_act,rmse_mod/sd_act);
    end
end

fprintf('\nRMSE/sd near 1 means the forecast carries no information beyond the\n');
fprintf('sample mean, which is the expected destination as the horizon grows.\n');
fprintf('=====================================================\n\n');

end % end of main function


% ---------------------------------------------------------------------
%% Local functions
% ---------------------------------------------------------------------

function [n,rmse_mod,rmse_ar,sd_act] = metrics_on(D,common_q,mth_of_q)
% Restrict a prediction matrix to given target quarters and to forecasts made in
% a given month of the quarter, then compute the metrics.
% D columns: 1 year RT, 2 month RT, 3 year target, 4 month target, 5 AR, 6 model, 7 actual
qi = 4*D(:,3) + ceil(D(:,4)/3);                 % running quarter index of the target
moq = mod(D(:,2)-1,3) + 1;                      % month of the quarter of the forecast round
keep = ismember(qi,common_q) & (moq == mth_of_q) & all(isfinite(D(:,5:7)),2);
D = D(keep,:);
% If a target quarter still appears more than once, keep the first occurrence
[~,ia] = unique(qi(keep),'first');
D = D(sort(ia),:);
n = size(D,1);
if n == 0
    rmse_mod = NaN; rmse_ar = NaN; sd_act = NaN; return
end
rmse_mod = sqrt(mean((D(:,6)-D(:,7)).^2));
rmse_ar  = sqrt(mean((D(:,5)-D(:,7)).^2));
sd_act   = std(D(:,7));
end


function run_selftest()
% Checks the restriction logic on synthetic data where the answer is known.
fprintf('\n--- compare_horizons selftest ---\n');
n_fail = 0;

% Build a prediction matrix: 12 rounds, targets in quarters 8100..8103,
% actual = 1 in every quarter, model prediction off by exactly 0.5
D = [];
for k = 0:11
    y = 2020 + floor(k/12); mth = mod(k,12)+1;
    tq = 8100 + floor(k/3);
    ty = floor(tq/4); tm = 3*(mod(tq,4)); if tm == 0, tm = 12; ty = ty - 1; end
    D(end+1,:) = [y mth ty tm 1.5 1.5 1.0]; %#ok<AGROW>
end
% qi rebuilt from (ty,tm) must recover four distinct quarters
qi = 4*D(:,3) + ceil(D(:,4)/3);
n_fail = n_fail + report(numel(unique(qi))==4,'target quarters recovered from year/month');

% Restricting to month 3 of the quarter must leave one round per quarter
[n,rmse_mod,rmse_ar,~] = metrics_on(D,unique(qi),3);
n_fail = n_fail + report(n==4,'one round per target quarter after restriction');
n_fail = n_fail + report(abs(rmse_mod-0.5)<1e-12,'RMSE computed correctly');
n_fail = n_fail + report(abs(rmse_ar-0.5)<1e-12,'AR RMSE computed correctly');

% Restricting to a subset of quarters must shrink the sample
[n2,~,~,~] = metrics_on(D,unique(qi(1:6)),3);
n_fail = n_fail + report(n2 < n,'restricting the quarter set shrinks the sample');

% Rows with a missing actual must be dropped
D2 = D; D2(3:3:end,7) = NaN;
[n3,~,~,~] = metrics_on(D2,unique(qi),3);
n_fail = n_fail + report(n3==0,'rounds without a realised target are dropped');

if n_fail == 0
    fprintf('All selftest checks passed.\n\n');
else
    fprintf('%d selftest check(s) FAILED.\n\n',n_fail);
end
end


function bad = report(cond,name)
if cond
    fprintf('  PASS  %s\n',name); bad = 0;
else
    fprintf('  FAIL  %s\n',name); bad = 1;
end
end
