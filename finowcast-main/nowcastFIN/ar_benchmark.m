function T_out = ar_benchmark(excel_datafile,opts)
% Model (M1) of the seminar guidelines: direct AND iterative h-steps-ahead
% forecasts from an AR(p) benchmark, produced recursively in quasi real time.
%
% This is deliberately independent of the nowcasting toolbox. It reads the
% target from the same Excel dataset, so the AR and the DFM are evaluated on
% the same series, but it does not touch any of the toolbox's own code paths.
%
% USAGE
%   T = ar_benchmark('data_UK');                  % all defaults
%   T = ar_benchmark('data_UK',opts);             % see the options below
%   ar_benchmark('selftest')                      % check the estimator
%
% OPTIONS (all optional, defaults in brackets)
%   opts.target_start  [2006 1]   first target quarter, as [year quarter]
%   opts.target_end    [2025 4]   last target quarter
%   opts.h_max         [4]        longest horizon, in quarters
%   opts.pmax          [8]        largest lag order considered
%   opts.ic            ['BIC']    'AIC' or 'BIC'
%   opts.date_format   ['dd.MM.yyyy'] format of the dates in column A of the
%                                 Quarterly sheet. Must match whatever
%                                 common_load_data uses on the same file.
%   opts.window        ['expanding']  'expanding' or 'rolling'
%   opts.win_len       [80]       length of the rolling window, in quarters
%   opts.est_startyear []         trim the estimation sample to start here.
%                                 Leave empty to use all available history.
%   opts.country       ['']       used for the output path and file name
%   opts.outfile       ['']       overrides the output path entirely
%
% OUTPUT
%   A table with one row per (origin, horizon, method), written to
%   ./eval/<country>/<country>_AR_benchmark.xlsx and returned.
%
% NB ON THE INFORMATION SET
%   Origins here are indexed directly by the last OBSERVED quarter: at origin
%   q_obs the target is observed through q_obs and horizon h targets q_obs + h,
%   which is the seminar's definition of h.
%   No release convention (gdp_rel) is needed, because the AR uses nothing but
%   the target itself, so its information set is fully described by the last
%   observed quarter. gdp_rel matters only for the DFM, whose monthly indicators
%   arrive during the quarter; evaluate_forecasts.m uses it there to work out
%   which quarter was last observed at each of the toolbox's monthly rounds.
%
% NB ON THE WINDOW
%   The guidelines describe re-estimation as "from t to 2005Q4, t+1 to 2006Q1,
%   ..." which can be read as an expanding or a rolling window. Both are
%   implemented; the default is expanding, which matches the DFM in the toolbox.

if nargin < 1 || isempty(excel_datafile)
    error('Give the name of the data file (without .xlsx), or ''selftest''.')
end
if strcmp(excel_datafile,'selftest')
    run_selftest();
    if nargout > 0, T_out = []; end
    return
end
if nargin < 2, opts = struct(); end

% Defaults
opts = setdef(opts,'target_start',[2006 1]);
opts = setdef(opts,'target_end',[2025 4]);
opts = setdef(opts,'h_max',4);
opts = setdef(opts,'pmax',8);
opts = setdef(opts,'ic','BIC');
opts = setdef(opts,'date_format','dd.MM.yyyy');
opts = setdef(opts,'window','expanding');
opts = setdef(opts,'win_len',80);
opts = setdef(opts,'est_startyear',[]);
opts = setdef(opts,'country','');
opts = setdef(opts,'outfile','');

addpath('./tools');
addpath('./dataset');

% ---------------------------------------------------------------------
%% 1. Load and transform the target, exactly as common_load_data does
% ---------------------------------------------------------------------

[C,D] = xlsread(excel_datafile,'Quarterly');
transf_q = C(1,:);
seriesq  = C(5:end,:);
% NB: the date format must match the one common_load_data uses on the same
%     file. Change opts.date_format if you re-format the dataset.
try
    dt_q = datetime(D(5:end,1),'InputFormat',opts.date_format);
catch
    dt_q = NaT(numel(D(5:end,1)),1);
end
if all(isnat(dt_q))
    error(['None of the dates in column A of the "Quarterly" sheet could be read with the format ''', ...
           opts.date_format,'''. The first cell contains "',char(string(D{5,1})),'". ' ...
           'Set opts.date_format to match (for example ''dd/MM/yyyy'' or ''yyyy-MM-dd''), ' ...
           'using the same format as in common_load_data.'])
end
[Year_q,Month_q] = datevec(dt_q);
t_q = [Year_q, Month_q];

data_q = common_transform_data(seriesq,transf_q,1);
t_q = t_q(2:end,:);                       % the transformation consumes one row

y   = data_q(:,end);                      % the target is the last column
qi  = 4*t_q(:,1) + ceil(t_q(:,2)/3);      % running quarter index

% Optional trim of the estimation history
if ~isempty(opts.est_startyear)
    keep = t_q(:,1) >= opts.est_startyear;
    y = y(keep); qi = qi(keep); t_q = t_q(keep,:);
end

fprintf('\n=========== AR(p) BENCHMARK (model M1) ===========\n');
fprintf('Target loaded: %d Q%d to %d Q%d (%d quarters)\n', ...
        t_q(1,1),ceil(t_q(1,2)/3),t_q(end,1),ceil(t_q(end,2)/3),numel(y));
fprintf('Lag order by %s, pmax = %d, %s window', upper(opts.ic),opts.pmax,opts.window);
if strcmpi(opts.window,'rolling'), fprintf(' of %d quarters',opts.win_len); end
fprintf('\n');

% ---------------------------------------------------------------------
%% 2. Recursive loop over forecast origins
% ---------------------------------------------------------------------
% Horizon h targets quarter (last observed) + h, so to cover target quarters
% from target_start onwards the last observed quarter runs from target_start-1.

qi_first_obs = 4*opts.target_start(1) + opts.target_start(2) - 1;
qi_last_obs  = 4*opts.target_end(1)   + opts.target_end(2)   - 1;

rows = {};
n_short = 0;
for q_obs = qi_first_obs:qi_last_obs

    % Real-time information set: the target observed up to and including q_obs
    i_obs = find(qi == q_obs,1);
    if isempty(i_obs), continue, end

    if strcmpi(opts.window,'rolling')
        i_start = max(1,i_obs - opts.win_len + 1);
    else
        i_start = 1;
    end
    y_in = y(i_start:i_obs);

    if sum(~isnan(y_in)) < 40
        n_short = n_short + 1;
    end

    [fc_dir,fc_it,p_sel] = AR_estimate_forecast(y_in,opts.h_max,opts.pmax,opts.ic);

    for hh = 1:opts.h_max
        q_tgt = q_obs + hh;
        i_tgt = find(qi == q_tgt,1);
        if isempty(i_tgt)
            actual = NaN;
            [ty,tq] = qi2yq(q_tgt);
        else
            actual = y(i_tgt);
            ty = t_q(i_tgt,1); tq = ceil(t_q(i_tgt,2)/3);
        end
        [oy,oq] = qi2yq(q_obs);
        rows(end+1,:) = {oy,oq,hh,ty,tq,'AR direct',   p_sel,fc_dir(hh),actual,actual-fc_dir(hh)}; %#ok<AGROW>
        rows(end+1,:) = {oy,oq,hh,ty,tq,'AR iterative',p_sel,fc_it(hh), actual,actual-fc_it(hh)};  %#ok<AGROW>
    end
end

if n_short > 0
    warning('%d origin(s) had fewer than 40 usable observations, as flagged in the guidelines.',n_short);
end

T_out = cell2table(rows,'VariableNames', ...
    {'origin_year','origin_quarter','h','target_year','target_quarter', ...
     'model','p','forecast','actual','error'});

% ---------------------------------------------------------------------
%% 3. Report and write
% ---------------------------------------------------------------------

fprintf('\nOrigins: %d Q%d to %d Q%d      Forecasts produced: %d\n', ...
        T_out.origin_year(1),T_out.origin_quarter(1), ...
        T_out.origin_year(end),T_out.origin_quarter(end),height(T_out));

fprintf('\nLag order selected (%s):\n',upper(opts.ic));
ps = T_out.p(strcmp(T_out.model,'AR direct') & T_out.h==1);
for pp = 1:opts.pmax
    n = sum(ps==pp);
    if n > 0
        fprintf('   p = %d in %d of %d origins (%.0f%%)\n',pp,n,numel(ps),100*n/numel(ps));
    end
end

fprintf('\nRMSE / MAE over all origins with a realised target:\n');
fprintf('%-14s %-4s %-8s %-10s %s\n','model','h','n','RMSE','MAE');
for m = {'AR direct','AR iterative'}
    for hh = 1:opts.h_max
        s = strcmp(T_out.model,m{1}) & T_out.h==hh & isfinite(T_out.error);
        e = T_out.error(s);
        fprintf('%-14s %-4d %-8d %-10.3f %.3f\n',m{1},hh,numel(e),sqrt(mean(e.^2)),mean(abs(e)));
    end
end

if isempty(opts.outfile)
    if isempty(opts.country)
        outfile = './AR_benchmark.xlsx';
    else
        outfile = ['./eval/',opts.country,'/',opts.country,'_AR_benchmark.xlsx'];
    end
else
    outfile = opts.outfile;
end
folder = fileparts(outfile);
if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
if isfile(outfile), delete(outfile); end
writetable(T_out,outfile,'Sheet','forecasts');
fprintf('\nWritten to %s\n',outfile);
fprintf('==================================================\n\n');

end % end of main function


% ---------------------------------------------------------------------
%% Local functions
% ---------------------------------------------------------------------

function s = setdef(s,field,val)
if ~isfield(s,field) || isempty(s.(field))
    s.(field) = val;
end
end

function [y,q] = qi2yq(qi)
% Invert qi = 4*year + quarter
q = mod(qi-1,4) + 1;
y = (qi - q)/4;
end


function run_selftest()
% Checks the AR estimator on simulated data where the answer is known.
addpath('./tools');
fprintf('\n--- ar_benchmark selftest ---\n');
n_fail = 0;

% --- quarter index arithmetic round-trips
ok = true;
for yy = 2004:2027
    for qq = 1:4
        [y2,q2] = qi2yq(4*yy+qq);
        ok = ok && (y2==yy) && (q2==qq);
    end
end
n_fail = n_fail + report(ok,'quarter index round-trips');

% --- simulate a known AR(2)
randn('seed',42);
n = 600; c0 = 0.3; a1 = 0.5; a2 = -0.25;
y = zeros(n,1);
for t = 3:n
    y(t) = c0 + a1*y(t-1) + a2*y(t-2) + 0.4*randn;
end
y = y(101:end); % burn-in

[fc_dir,fc_it,p_sel] = AR_estimate_forecast(y,4,8,'BIC');
n_fail = n_fail + report(p_sel==2,sprintf('BIC recovers the true lag order (selected p = %d)',p_sel));

% --- direct and iterative must coincide at h = 1
n_fail = n_fail + report(abs(fc_dir(1)-fc_it(1)) < 1e-10, ...
    sprintf('direct and iterative agree at h=1 (diff %.2e)',abs(fc_dir(1)-fc_it(1))));

% --- the iterative path must equal the AR recursion applied to itself
idx = (p_sel+1:numel(y))';
X = ones(numel(idx),1);
for j = 1:p_sel, X = [X, y(idx-j)]; end %#ok<AGROW>
b = X\y(idx);
manual = nan(1,4);
z = y(end:-1:end-p_sel+1);
for hh = 1:4
    manual(hh) = b(1) + b(2:end)'*z;
    z = [manual(hh); z(1:end-1)];
end
n_fail = n_fail + report(max(abs(manual-fc_it)) < 1e-10,'iterative path matches the AR recursion');

% --- forecasts must converge towards the unconditional mean
mu = c0/(1-a1-a2);
[fc_d8,fc_i8] = AR_estimate_forecast(y,12,8,'BIC');
n_fail = n_fail + report(abs(fc_i8(12)-mu) < abs(fc_i8(1)-mu) + 1e-12, ...
    sprintf('iterative forecast tends to the unconditional mean (%.3f vs %.3f)',fc_i8(12),mu));
n_fail = n_fail + report(all(isfinite(fc_d8)),'direct forecasts are finite at every horizon');

% --- a pure white-noise series should select p = 1 and forecast near the mean
randn('seed',7);
w = 2 + 0.5*randn(400,1);
[~,fc_w,p_w] = AR_estimate_forecast(w,4,8,'BIC');
n_fail = n_fail + report(p_w<=2,sprintf('white noise selects a short lag order (p = %d)',p_w));
n_fail = n_fail + report(abs(fc_w(4)-2) < 0.2,'white-noise forecast sits near the mean');

% --- too little data must return NaN rather than error
[fd,fi,pp] = AR_estimate_forecast(randn(5,1),4,8,'BIC');
n_fail = n_fail + report(all(isnan(fd)) && all(isnan(fi)) && isnan(pp), ...
    'insufficient data returns NaN without erroring');

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
