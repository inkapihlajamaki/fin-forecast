function R = diagnose_forecast_alignment(evalfile,opts)
% Work out why a model's RMSE falls as the horizon grows.
%
% A forecast RMSE that improves with the horizon is not possible if the model
% and the sample are sound, so one of three things is true:
%   (a) the horizons are scored on different target quarters (composition),
%   (b) the forecasts are misaligned in time against the actuals (an off-by-one
%       in the horizon mapping would do it), or
%   (c) the short-horizon forecasts are genuinely bad - worse than predicting
%       the sample mean - so that reverting to the mean at long horizons is an
%       improvement rather than a degradation.
%
% This script tests all three on the combined forecast table written by
% evaluate_forecasts.m, and says which one it is.
%
% USAGE
%   diagnose_forecast_alignment('./eval/UK/forecast_evaluation.xlsx')
%   diagnose_forecast_alignment('selftest')
%
% OPTIONS
%   opts.h_max        [4]      horizons to examine
%   opts.exclude2020  [true]   drop target year 2020
%
% OUTPUT
%   R [table] = per model and horizon: n, RMSE, the RMSE of two naive
%   benchmarks on the SAME quarters, the correlation between forecast and
%   actual, the mean error, and the time shift that minimises the RMSE.

if nargin >= 1 && strcmp(evalfile,'selftest')
    run_selftest();
    if nargout > 0, R = []; end
    return
end
if nargin < 2, opts = struct(); end
if ~isfield(opts,'h_max') || isempty(opts.h_max), opts.h_max = 4; end
if ~isfield(opts,'exclude2020') || isempty(opts.exclude2020), opts.exclude2020 = true; end

T = readtable(evalfile,'Sheet','forecasts');
if opts.exclude2020
    T = T(T.target_year ~= 2020,:);
end
q  = 4*T.target_year + T.target_quarter;      % running quarter index of the target
models = unique(T.model,'stable');

% A lookup from target quarter to the realised value, built once from all rows
[qA,ia] = unique(q);
A = T.actual(ia);

fprintf('\n========= FORECAST ALIGNMENT DIAGNOSTIC =========\n');
fprintf('File: %s\n',evalfile);
if opts.exclude2020, fprintf('Target year 2020 excluded.\n'); end

% ---------------------------------------------------------------------
%% 1. Are the horizons scored on the same quarters?
% ---------------------------------------------------------------------

fprintf('\n--- (a) Composition: target quarters per horizon ---\n');
fprintf('%-16s %-4s %-6s %-22s %s\n','model','h','n','span','shared with h=1');
for mm = 1:numel(models)
    base = [];
    for hh = 1:opts.h_max
        s = strcmp(T.model,models{mm}) & T.h==hh;
        if ~any(s), continue, end
        qs = q(s);
        if hh == 1, base = qs; end
        shared = numel(intersect(qs,base));
        [y1,q1] = qi2yq(min(qs)); [y2,q2] = qi2yq(max(qs));
        fprintf('%-16s %-4d %-6d %d Q%d to %d Q%d      %d of %d\n', ...
                models{mm},hh,sum(s),y1,q1,y2,q2,shared,numel(qs));
    end
end
fprintf(['If the spans barely move, composition is NOT the explanation and the\n' ...
         'divergence between models has to come from the models themselves.\n']);

% ---------------------------------------------------------------------
%% 2. Benchmarks, correlation, bias and the alignment scan
% ---------------------------------------------------------------------

shifts = -2:2;
rows = {};
% ---------------------------------------------------------------------
%% 1b. Audit the target series itself
% ---------------------------------------------------------------------
% If two independent pipelines disagree about what the realised value was, no
% comparison of their forecasts means anything. The DFM's actuals come from the
% toolbox (xest), the AR's from ar_benchmark reading the same sheet - they must
% agree on every quarter both cover.

fprintf('\n--- Target series audit ---\n');
maps = cell(1,numel(models));
for mm = 1:numel(models)
    s = strcmp(T.model,models{mm});
    [qm,im] = unique(q(s));
    am = T.actual(s);
    maps{mm} = [qm(:), am(im)];
end
disagree = false;
for mm = 2:numel(models)
    [shared,i1,i2] = intersect(maps{1}(:,1),maps{mm}(:,1));
    if isempty(shared), continue, end
    d = abs(maps{1}(i1,2) - maps{mm}(i2,2));
    d = d(isfinite(d));
    fprintf('%s vs %s: %d shared quarters, largest disagreement %.4f\n', ...
            models{1},models{mm},numel(shared),max([d;0]));
    if any(d > 1e-6)
        disagree = true;
        bad = find(abs(maps{1}(i1,2)-maps{mm}(i2,2)) > 1e-6);
        fprintf('   [!] the two pipelines disagree about the realised value.\n');
        for b = 1:min(5,numel(bad))
            [yy,qq] = qi2yq(shared(bad(b)));
            fprintf('       %dQ%d: %s = %.4f, %s = %.4f\n',yy,qq, ...
                    models{1},maps{1}(i1(bad(b)),2),models{mm},maps{mm}(i2(bad(b)),2));
        end
    end
end
if ~disagree
    fprintf('The pipelines agree on the realised values where they overlap.\n');
end

fprintf('\nRealised target, as scored (mean %.3f, sd %.3f, n %d):\n', ...
        mean(A,'omitnan'),std(A,'omitnan'),sum(isfinite(A)));
[~,ord] = sort(qA);
shown = 0;
for k = numel(ord):-1:1
    if ~isfinite(A(ord(k))), continue, end
    [yy,qq] = qi2yq(qA(ord(k)));
    fprintf('   %dQ%d %7.3f',yy,qq,A(ord(k)));
    shown = shown + 1;
    if mod(shown,6)==0, fprintf('\n'); end
    if shown >= 24, break, end
end
fprintf('\nCheck these against the published series. If they are not quarter-on-quarter\n');
fprintf('growth in percent, the transformation or the target column is wrong.\n');

fprintf('\n--- (b) and (c): scoring against naive benchmarks, and alignment ---\n');
fprintf('%-16s %-4s %-6s %-8s %-8s %-8s %-7s %-8s %s\n', ...
        'model','h','n','RMSE','RMSE mean','RMSE RW','corr','bias','best shift');
for mm = 1:numel(models)
    for hh = 1:opts.h_max
        s = strcmp(T.model,models{mm}) & T.h==hh;
        if ~any(s), continue, end
        f = T.forecast(s); a = T.actual(s); qs = q(s);
        ok = isfinite(f) & isfinite(a);
        f = f(ok); a = a(ok); qs = qs(ok);
        if numel(f) < 4, continue, end

        rmse = sqrt(mean((a-f).^2));

        % Benchmark 1: the sample mean of the target over the same quarters
        rmse_mean = sqrt(mean((a-mean(a)).^2));

        % Benchmark 2: a random walk from the last observed quarter, i.e. the
        % realised value h quarters before the target
        rw = lookup(qA,A,qs-hh);
        okrw = isfinite(rw);
        if any(okrw)
            rmse_rw = sqrt(mean((a(okrw)-rw(okrw)).^2));
        else
            rmse_rw = NaN;
        end

        % Correlation and bias
        cc = corr_safe(f,a);
        bias = mean(a-f);

        % Alignment scan: pair each forecast with the actual s quarters away.
        % NB: the baseline at shift 0 must come from the SAME lookup as the
        %     shifted values, otherwise a disagreement between the two sources
        %     of "actual" shows up as a spurious improvement at a non-zero shift.
        a0 = lookup(qA,A,qs);
        k0 = isfinite(a0);
        best_r = sqrt(mean((a0(k0)-f(k0)).^2));
        best_s = 0;
        for ss = shifts
            if ss == 0, continue, end
            a_s = lookup(qA,A,qs+ss);
            k = isfinite(a_s);
            if sum(k) < 4, continue, end
            r_s = sqrt(mean((a_s(k)-f(k)).^2));
            if r_s < best_r, best_r = r_s; best_s = ss; end
        end

        fprintf('%-16s %-4d %-6d %-8.3f %-8.3f %-8.3f %-7.2f %-8.3f %+d', ...
                models{mm},hh,numel(f),rmse,rmse_mean,rmse_rw,cc,bias,best_s);
        if best_s ~= 0
            fprintf('  (RMSE %.3f)',best_r);
        end
        fprintf('\n');

        rows(end+1,:) = {models{mm},hh,numel(f),rmse,rmse_mean,rmse_rw,cc,bias,best_s,best_r}; %#ok<AGROW>
    end
end

R = cell2table(rows,'VariableNames',{'model','h','n','RMSE','RMSE_mean','RMSE_RW', ...
                                     'corr','bias','best_shift','RMSE_at_best_shift'});

% ---------------------------------------------------------------------
%% 3. Verdict
% ---------------------------------------------------------------------

fprintf('\n--- Reading of the results ---\n');
for mm = 1:numel(models)
    sub = R(strcmp(R.model,models{mm}),:);
    if isempty(sub), continue, end
    fprintf('\n%s:\n',models{mm});

    worse_than_mean = sub.RMSE > sub.RMSE_mean;
    if any(worse_than_mean)
        hs = sprintf('%d ',sub.h(worse_than_mean));
        fprintf('  [!] worse than simply predicting the sample mean at h = %s\n',hs);
        fprintf('      A model that cannot beat a constant is not being helped by its data.\n');
        fprintf('      At short horizons this points to the real-time inputs, not the horizon:\n');
        fprintf('      check Eval.data_update_lastyear/lastmonth against where the data really\n');
        fprintf('      ends, and Eval.gdp_rel against the true publication lag.\n');
    end

    % Alignment: judge each horizon on its own. Scanning five shifts on a short
    % sample always produces some winner, so a shift only counts as evidence if
    % the shifted fit is materially better AND informative in absolute terms.
    idx = find(sub.best_shift ~= 0);
    meaningful = idx(sub.RMSE_at_best_shift(idx) < sub.RMSE_mean(idx) & ...
                     sub.RMSE_at_best_shift(idx) < 0.9*sub.RMSE(idx));
    if isempty(idx)
        fprintf('  no time shift improves the fit, so the forecasts are aligned correctly\n');
    elseif isempty(meaningful)
        fprintf('  a shift lowers the RMSE at h = %s, but never below what the sample mean\n', ...
                sprintf('%d ',sub.h(idx)));
        fprintf('      achieves, so this is shift-scan noise rather than an off-by-one.\n');
    else
        fprintf('  [!] shifting the forecasts in time gives a materially better AND informative\n');
        fprintf('      fit at h = %s (shift %+d -> RMSE %.3f instead of %.3f, against %.3f for\n', ...
                sprintf('%d ',sub.h(meaningful)),sub.best_shift(meaningful(1)), ...
                sub.RMSE_at_best_shift(meaningful(1)),sub.RMSE(meaningful(1)), ...
                sub.RMSE_mean(meaningful(1)));
        fprintf('      the sample mean). That is the signature of an off-by-one in the mapping.\n');
    end

    if any(sub.corr < 0.2)
        hs = sprintf('%d ',sub.h(sub.corr < 0.2));
        fprintf('  [!] forecast and actual are essentially uncorrelated at h = %s\n',hs);
    end

    if numel(sub.RMSE) > 1 && all(diff(sub.RMSE) < 0)
        fprintf('  RMSE falls monotonically with the horizon.\n');
        if all(~worse_than_mean)
            fprintf('      But it beats the mean everywhere, so this is a sample effect:\n');
            fprintf('      compare the spans in section (a).\n');
        end
    end
end
fprintf('\n================================================\n\n');

end % end of main function


% ---------------------------------------------------------------------
%% Local functions
% ---------------------------------------------------------------------

function v = lookup(keys,vals,want)
% Value of vals at each element of want, NaN where the key is absent.
v = nan(size(want));
[tf,loc] = ismember(want,keys);
v(tf) = vals(loc(tf));
end

function c = corr_safe(x,y)
% Pearson correlation without the Statistics Toolbox.
x = x(:); y = y(:);
k = isfinite(x) & isfinite(y);
x = x(k) - mean(x(k)); y = y(k) - mean(y(k));
d = sqrt(sum(x.^2)*sum(y.^2));
if d == 0, c = NaN; else, c = sum(x.*y)/d; end
end

function [y,q] = qi2yq(qi)
q = mod(qi-1,4) + 1;
y = (qi - q)/4;
end


function run_selftest()
fprintf('\n--- diagnose_forecast_alignment selftest ---\n');
n_fail = 0;

% --- lookup
keys = [8100;8101;8102]; vals = [1;2;3];
v_lk = lookup(keys,vals,[8101;8103]);   % NB: isequal would fail here, NaN ~= NaN
n_fail = n_fail + report(v_lk(1)==2 && isnan(v_lk(2)),'lookup returns NaN for absent keys');
n_fail = n_fail + report(isequal(lookup(keys,vals,[8102;8100]),[3;1]),'lookup preserves order');

% --- correlation against known values
x = (1:20)';
n_fail = n_fail + report(abs(corr_safe(x,2*x+1)-1) < 1e-12,'perfect positive correlation is 1');
n_fail = n_fail + report(abs(corr_safe(x,-x)+1) < 1e-12,'perfect negative correlation is -1');
n_fail = n_fail + report(isnan(corr_safe(x,ones(20,1))),'zero-variance input gives NaN');
n_fail = n_fail + report(abs(corr_safe([1;2;NaN;4],[2;4;9;8])-1) < 1e-12,'NaN pairs are dropped');

% --- the alignment scan must find a deliberately introduced off-by-one
qs = (8100:8130)';
randn('seed',11);
a_true = randn(numel(qs),1);
% forecasts equal the actual one quarter LATER, so pairing is wrong by +1
f = a_true;
qA = qs; A = a_true;
rmse0 = sqrt(mean((lookup(qA,A,qs) - f).^2));
rmse1 = sqrt(mean((lookup(qA,A,qs+1) - f(1:end)).^2,'omitnan'));
n_fail = n_fail + report(rmse0 < rmse1,'a correctly aligned series scores best at shift 0');

f_shift = lookup(qA,A,qs+1);          % forecast is really about quarter q+1
k = isfinite(f_shift);
r_at0 = sqrt(mean((lookup(qA,A,qs(k)) - f_shift(k)).^2));
r_at1 = sqrt(mean((lookup(qA,A,qs(k)+1) - f_shift(k)).^2));
n_fail = n_fail + report(r_at1 < r_at0,'a misaligned series scores best at a non-zero shift');

% --- quarter index round-trip
ok = true;
for yy = 2005:2026
    for qq = 1:4
        [y2,q2] = qi2yq(4*yy+qq); ok = ok && y2==yy && q2==qq;
    end
end
n_fail = n_fail + report(ok,'quarter index round-trips');

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
