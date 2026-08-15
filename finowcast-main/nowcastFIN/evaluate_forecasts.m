function [T_all,M] = evaluate_forecasts(dfm_evalfile,ar_file,opts)
% Combine the DFM and AR forecasts, score them with MAE and RMSE by horizon,
% and draw the forecast-error distributions the seminar guidelines ask for.
%
% The two sources index their horizons differently. The toolbox labels horizons
% relative to the NOWCAST quarter ('Bac', 'Now', 'For', 'For2', ...), while the
% guidelines define h relative to the last OBSERVED quarter. This script
% converts the former into the latter, using the release convention in
% opts.gdp_rel, so that everything is expressed as h = 1, ..., h_max.
%
% USAGE
%   evaluate_forecasts('./eval/UK/UK_DFM_evaluation.xlsx', ...
%                      './eval/UK/UK_AR_benchmark.xlsx')
%   evaluate_forecasts(...,...,opts)
%   evaluate_forecasts('selftest')
%
% OPTIONS (defaults in brackets)
%   opts.gdp_rel      [2]         month of quarter in which the previous
%                                 quarter's GDP is released (match the Mainfile)
%   opts.mth_of_q     [3]         month of the quarter used as forecast origin.
%                                 Must be >= gdp_rel, otherwise the previous
%                                 quarter's GDP is not yet out and h shifts.
%   opts.h_max        [4]         horizons reported
%   opts.target_start [2006 1]    first target quarter, as [year quarter]
%   opts.target_end   [2025 4]    last target quarter
%   opts.dfm_label    ['DFM']     name for the toolbox model in the output
%   opts.include_toolbox_ar [false]  also score the toolbox's built-in AR(1)
%   opts.country      ['']        used for output paths
%   opts.make_plots   [true]      draw and save the figures
%
% OUTPUTS
%   T_all [table] = every forecast, one row per (model, origin, horizon)
%   M     [table] = MAE and RMSE by model, horizon and subsample
%
% Figures are written to ./figures/ as PNG, ready for \includegraphics.

if nargin >= 1 && strcmp(dfm_evalfile,'selftest')
    run_selftest();
    if nargout > 0, T_all = []; M = []; end
    return
end
if nargin < 2, error('Give the DFM evaluation workbook and the AR benchmark file.'); end
if nargin < 3, opts = struct(); end

opts = setdef(opts,'gdp_rel',2);
opts = setdef(opts,'mth_of_q',3);
opts = setdef(opts,'h_max',4);
opts = setdef(opts,'target_start',[2006 1]);
opts = setdef(opts,'target_end',[2025 4]);
opts = setdef(opts,'dfm_label','DFM');
opts = setdef(opts,'include_toolbox_ar',false);
opts = setdef(opts,'country','');
opts = setdef(opts,'make_plots',true);

if opts.mth_of_q < opts.gdp_rel
    warning(['opts.mth_of_q (%d) is before the GDP release month (%d). At that point the ' ...
             'previous quarter is not yet published, so every horizon shifts by one quarter.'], ...
             opts.mth_of_q,opts.gdp_rel);
end

qi_lo = 4*opts.target_start(1) + opts.target_start(2);
qi_hi = 4*opts.target_end(1)   + opts.target_end(2);

% ---------------------------------------------------------------------
%% 1. Read the DFM forecasts and convert the horizon labels
% ---------------------------------------------------------------------

hor_names = {'Bac','Now','For','For2','For3','For4','For5','For6'};
rows = {};
for hh = 1:numel(hor_names)
    try
        raw = readmatrix(dfm_evalfile,'Sheet',hor_names{hh});
    catch
        continue
    end
    raw = raw(all(isfinite(raw(:,1:4)),2),1:7);
    for r = 1:size(raw,1)
        h = map_h(raw(r,1),raw(r,2),raw(r,3),raw(r,4),opts.gdp_rel);
        k = mod(raw(r,2)-1,3) + 1;                  % month of the quarter
        qi_t = 4*raw(r,3) + ceil(raw(r,4)/3);
        if k ~= opts.mth_of_q, continue, end
        if h < 1 || h > opts.h_max, continue, end
        if qi_t < qi_lo || qi_t > qi_hi, continue, end
        [oy,oq] = qi2yq(qi_t - h);                  % the last observed quarter
        rows(end+1,:) = {oy,oq,h,raw(r,3),ceil(raw(r,4)/3),opts.dfm_label, ...
                         raw(r,6),raw(r,7),raw(r,7)-raw(r,6)}; %#ok<AGROW>
        if opts.include_toolbox_ar
            rows(end+1,:) = {oy,oq,h,raw(r,3),ceil(raw(r,4)/3),'AR(1) toolbox', ...
                             raw(r,5),raw(r,7),raw(r,7)-raw(r,5)}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    error(['No DFM forecasts survived the filters. Check opts.mth_of_q (%d), the target ' ...
           'window, and that the evaluation actually covers it.'],opts.mth_of_q);
end
T_dfm = cell2table(rows,'VariableNames', ...
    {'origin_year','origin_quarter','h','target_year','target_quarter','model', ...
     'forecast','actual','error'});

% ---------------------------------------------------------------------
%% 2. Read the AR benchmark and align the target window
% ---------------------------------------------------------------------

T_ar = readtable(ar_file,'Sheet','forecasts');
T_ar = T_ar(:,{'origin_year','origin_quarter','h','target_year','target_quarter', ...
               'model','forecast','actual','error'});
qi_t_ar = 4*T_ar.target_year + T_ar.target_quarter;
T_ar = T_ar(qi_t_ar >= qi_lo & qi_t_ar <= qi_hi & T_ar.h <= opts.h_max,:);

T_all = [T_dfm; T_ar];
T_all = T_all(isfinite(T_all.error),:);   % drop targets not yet realised

% ---------------------------------------------------------------------
%% 3. Report coverage, then score
% ---------------------------------------------------------------------

models = unique(T_all.model,'stable');
fprintf('\n============ FORECAST EVALUATION ============\n');
fprintf('DFM file : %s\n',dfm_evalfile);
fprintf('AR file  : %s\n',ar_file);
fprintf('Origins fixed at month %d of the quarter; h defined against the last observed quarter.\n', ...
        opts.mth_of_q);
fprintf('Target window requested: %dQ%d to %dQ%d\n\n', ...
        opts.target_start(1),opts.target_start(2),opts.target_end(1),opts.target_end(2));

fprintf('--- Coverage ---\n');
fprintf('%-16s %-6s %-6s %s\n','model','h','n','target quarters');
for mm = 1:numel(models)
    for hh = 1:opts.h_max
        s = strcmp(T_all.model,models{mm}) & T_all.h==hh;
        if ~any(s), continue, end
        sub = T_all(s,:);
        fprintf('%-16s %-6d %-6d %dQ%d to %dQ%d\n',models{mm},hh,sum(s), ...
                sub.target_year(1),sub.target_quarter(1),sub.target_year(end),sub.target_quarter(end));
    end
end

% Warn if the models are not scored on the same quarters
fprintf('\n--- Common sample check ---\n');
common = [];
for mm = 1:numel(models)
    s = strcmp(T_all.model,models{mm}) & T_all.h==1;
    q = 4*T_all.target_year(s) + T_all.target_quarter(s);
    if isempty(common), common = q; else, common = intersect(common,q); end
end
fprintf('Target quarters at h=1 shared by all models: %d\n',numel(common));
if numel(common) < 0.9*max(sum(T_all.h==1 & strcmp(T_all.model,models{1})),1)
    fprintf('[!] The models do not cover the same quarters. Comparisons below are not like-for-like.\n');
end

% Metrics
subs = {'all','pre-Covid (<2020)','Covid (2020)','post-Covid (>2020)','excl. Covid'};
mrows = {};
for mm = 1:numel(models)
    for hh = 1:opts.h_max
        for ss = 1:numel(subs)
            s = strcmp(T_all.model,models{mm}) & T_all.h==hh & submask(T_all.target_year,subs{ss});
            e = T_all.error(s);
            if isempty(e)
                mrows(end+1,:) = {models{mm},hh,subs{ss},0,NaN,NaN,NaN,NaN}; %#ok<AGROW>
            else
                mrows(end+1,:) = {models{mm},hh,subs{ss},numel(e), ...
                                  mean(abs(e)),sqrt(mean(e.^2)),median(e),std(T_all.actual(s))}; %#ok<AGROW>
            end
        end
    end
end
M = cell2table(mrows,'VariableNames',{'model','h','sample','n','MAE','RMSE','median_error','sd_actual'});

fprintf('\n--- MAE and RMSE by horizon (all targets) ---\n');
fprintf('%-16s %-4s %-6s %-9s %-9s %s\n','model','h','n','MAE','RMSE','RMSE/sd');
for mm = 1:numel(models)
    for hh = 1:opts.h_max
        r = M(strcmp(M.model,models{mm}) & M.h==hh & strcmp(M.sample,'all'),:);
        if isempty(r) || r.n==0, continue, end
        fprintf('%-16s %-4d %-6d %-9.3f %-9.3f %.2f\n',models{mm},hh,r.n,r.MAE,r.RMSE,r.RMSE/r.sd_actual);
    end
end

fprintf('\n--- MAE and RMSE by horizon (excluding 2020) ---\n');
fprintf('%-16s %-4s %-6s %-9s %-9s\n','model','h','n','MAE','RMSE');
for mm = 1:numel(models)
    for hh = 1:opts.h_max
        r = M(strcmp(M.model,models{mm}) & M.h==hh & strcmp(M.sample,'excl. Covid'),:);
        if isempty(r) || r.n==0, continue, end
        fprintf('%-16s %-4d %-6d %-9.3f %-9.3f\n',models{mm},hh,r.n,r.MAE,r.RMSE);
    end
end

% Write the results
outdir = './eval';
if ~isempty(opts.country), outdir = ['./eval/',opts.country]; end
if ~isfolder(outdir), mkdir(outdir); end
outfile = fullfile(outdir,'forecast_evaluation.xlsx');
if isfile(outfile), delete(outfile); end
writetable(T_all,outfile,'Sheet','forecasts');
writetable(M,outfile,'Sheet','metrics');
fprintf('\nWritten to %s\n',outfile);

% ---------------------------------------------------------------------
%% 4. Figures
% ---------------------------------------------------------------------

if opts.make_plots
    if ~isfolder('./figures'), mkdir('./figures'); end

    % Flatten the table into plain arrays, so the plotting routines stay
    % independent of the table type (and can be tested on their own)
    mi = zeros(height(T_all),1);
    for mm = 1:numel(models)
        mi(strcmp(T_all.model,models{mm})) = mm;
    end
    plot_error_distributions(T_all.error,mi,T_all.h,models,opts.h_max);

    rmse_mat = nan(numel(models),opts.h_max);
    mae_mat  = nan(numel(models),opts.h_max);
    for mm = 1:numel(models)
        for hh = 1:opts.h_max
            r = M(strcmp(M.model,models{mm}) & M.h==hh & strcmp(M.sample,'excl. Covid'),:);
            if ~isempty(r) && r.n > 0
                rmse_mat(mm,hh) = r.RMSE;
                mae_mat(mm,hh)  = r.MAE;
            end
        end
    end
    plot_accuracy_by_horizon(rmse_mat,mae_mat,models,opts.h_max);
    fprintf('Figures written to ./figures/\n');
end
fprintf('=============================================\n\n');

end % end of main function


% ---------------------------------------------------------------------
%% Local functions
% ---------------------------------------------------------------------

function h = map_h(yr_rt,mth_rt,yr_t,mth_t,gdp_rel)
% Convert a toolbox round into the seminar's horizon.
% At an origin in quarter Q, the previous quarter's GDP is released from month
% gdp_rel onwards, so the last OBSERVED quarter is Q-1 from that month and Q-2
% before it. The horizon is the distance from there to the target quarter.
k = mod(mth_rt-1,3) + 1;                 % month of the quarter of the origin
qi_rt = 4*yr_rt + ceil(mth_rt/3);
if k >= gdp_rel
    qi_obs = qi_rt - 1;
else
    qi_obs = qi_rt - 2;
end
qi_t = 4*yr_t + ceil(mth_t/3);
h = qi_t - qi_obs;
end

function m = submask(target_year,name)
switch name
    case 'all',                 m = true(size(target_year));
    case 'pre-Covid (<2020)',   m = target_year < 2020;
    case 'Covid (2020)',        m = target_year == 2020;
    case 'post-Covid (>2020)',  m = target_year > 2020;
    case 'excl. Covid',         m = target_year ~= 2020;
    otherwise,                  m = true(size(target_year));
end
end

function q = pctl(x,p)
% Percentile without the Statistics Toolbox, matching prctile's convention.
x = sort(x(~isnan(x)));
n = numel(x);
if n == 0, q = NaN; return, end
if n == 1, q = x(1); return, end
pos = p/100*n + 0.5;
if pos <= 1, q = x(1); return, end
if pos >= n, q = x(n); return, end
lo = floor(pos);
q = x(lo) + (pos-lo)*(x(lo+1)-x(lo));
end

function [y,q] = qi2yq(qi)
q = mod(qi-1,4) + 1;
y = (qi - q)/4;
end

function s = setdef(s,field,val)
if ~isfield(s,field) || isempty(s.(field))
    s.(field) = val;
end
end

function plot_error_distributions(err,model_idx,h_idx,models,h_max)
% Median and percentile range of the forecast errors, by horizon and model.
% This is the visualisation asked for on slide 16 of the guidelines.
% Takes plain arrays so that it does not depend on the table type:
%   err [n x 1] forecast errors, model_idx [n x 1] index into models,
%   h_idx [n x 1] horizon of each error.
cols = [0.20 0.35 0.60; 0.85 0.45 0.15; 0.30 0.60 0.35; 0.55 0.35 0.65; 0.45 0.45 0.45];
nm = numel(models);
w = 0.8/nm;                                   % width allotted to each model

fig = figure('Color','w','Position',[100 100 780 420]);
hold on
plot([0.4 h_max+0.6],[0 0],'-','Color',[0.6 0.6 0.6],'LineWidth',0.8);
leg_h = []; leg_txt = {};
for mm = 1:nm
    c = cols(mod(mm-1,size(cols,1))+1,:);
    shown = false;
    for hh = 1:h_max
        e = err(model_idx==mm & h_idx==hh);
        e = e(~isnan(e));
        if isempty(e), continue, end
        x = hh - 0.4 + (mm-0.5)*w;
        p10 = pctl(e,10); p25 = pctl(e,25); p50 = pctl(e,50);
        p75 = pctl(e,75); p90 = pctl(e,90);
        % whisker
        plot([x x],[p10 p90],'-','Color',c,'LineWidth',1.0);
        plot([x-0.15*w x+0.15*w],[p10 p10],'-','Color',c,'LineWidth',1.0);
        plot([x-0.15*w x+0.15*w],[p90 p90],'-','Color',c,'LineWidth',1.0);
        % interquartile box
        hp = patch([x-0.35*w x+0.35*w x+0.35*w x-0.35*w],[p25 p25 p75 p75], ...
                   c,'FaceAlpha',0.35,'EdgeColor',c,'LineWidth',0.9);
        % median
        plot([x-0.35*w x+0.35*w],[p50 p50],'-','Color',c,'LineWidth',1.8);
        if ~shown
            leg_h(end+1) = hp; leg_txt{end+1} = models{mm}; %#ok<AGROW>
            shown = true;
        end
    end
end
hold off
xlim([0.4 h_max+0.6]); set(gca,'XTick',1:h_max);
xlabel('Forecast horizon h (quarters ahead of the last observed quarter)');
ylabel('Forecast error, percentage points');
title('Distribution of forecast errors by horizon');
if ~isempty(leg_h)
    legend(leg_h,leg_txt,'Location','best'); legend boxoff
end
box on
print(fig,'./figures/forecast_errors_by_horizon.png','-dpng','-r200');
close(fig);
end

function plot_accuracy_by_horizon(rmse_mat,mae_mat,models,h_max)
% RMSE and MAE against the horizon, one panel each.
% rmse_mat and mae_mat are [n_models x h_max].
cols = [0.20 0.35 0.60; 0.85 0.45 0.15; 0.30 0.60 0.35; 0.55 0.35 0.65; 0.45 0.45 0.45];
fig = figure('Color','w','Position',[100 100 860 360]);
for pp = 1:2
    if pp == 1, V = rmse_mat; fld = 'RMSE'; else, V = mae_mat; fld = 'MAE'; end
    subplot(1,2,pp); hold on
    for mm = 1:numel(models)
        c = cols(mod(mm-1,size(cols,1))+1,:);
        plot(1:h_max,V(mm,:),'-o','Color',c,'MarkerFaceColor',c,'LineWidth',1.4,'MarkerSize',5);
    end
    hold off; box on
    set(gca,'XTick',1:h_max); xlim([0.8 h_max+0.2]);
    xlabel('Horizon h'); ylabel([fld,', percentage points']);
    title([fld,' by horizon (excluding 2020)']);
    if pp == 1, legend(models,'Location','best'); legend boxoff; end
end
print(fig,'./figures/accuracy_by_horizon.png','-dpng','-r200');
close(fig);
end


function run_selftest()
fprintf('\n--- evaluate_forecasts selftest ---\n');
n_fail = 0;

% --- horizon mapping, origin in the third month of the quarter, gdp_rel = 2
% Origin 2024M6 (Q2, month 3). GDP for 2024Q1 is out, so the last observed
% quarter is 2024Q1 and the nowcast of 2024Q2 is h = 1.
n_fail = n_fail + report(map_h(2024,6,2024,6,2)==1,'Now maps to h=1 at month 3');
n_fail = n_fail + report(map_h(2024,6,2024,9,2)==2,'For maps to h=2 at month 3');
n_fail = n_fail + report(map_h(2024,6,2024,12,2)==3,'For2 maps to h=3 at month 3');
n_fail = n_fail + report(map_h(2024,6,2025,3,2)==4,'For3 maps to h=4 at month 3');
n_fail = n_fail + report(map_h(2024,6,2024,3,2)==0,'Bac maps to h=0 (already observed)');

% --- before the release month everything shifts by one quarter
n_fail = n_fail + report(map_h(2024,4,2024,6,2)==2,'Now maps to h=2 at month 1');
n_fail = n_fail + report(map_h(2024,5,2024,6,2)==1,'Now maps to h=1 at month 2 when gdp_rel=2');
n_fail = n_fail + report(map_h(2024,5,2024,6,3)==2,'the mapping follows gdp_rel');

% --- year boundaries
n_fail = n_fail + report(map_h(2024,12,2025,3,2)==2,'mapping crosses the year end');
n_fail = n_fail + report(map_h(2025,3,2025,3,2)==1,'mapping is correct in Q1');

% --- percentiles against a known sample
x = (1:100)';
n_fail = n_fail + report(abs(pctl(x,50)-50.5) < 1e-9,'median of 1..100 is 50.5');
n_fail = n_fail + report(abs(pctl(x,25)-25.0) < 0.6,'25th percentile is about 25');
n_fail = n_fail + report(pctl(x,0)==1 && pctl(x,100)==100,'extremes clamp to min and max');
n_fail = n_fail + report(isnan(pctl(nan(3,1),50)),'all-NaN input returns NaN');
n_fail = n_fail + report(pctl([nan;5;nan],50)==5,'NaN are ignored');

% --- subsample masks
yrs = [2018;2020;2022];
n_fail = n_fail + report(isequal(submask(yrs,'pre-Covid (<2020)'),[true;false;false]),'pre-Covid mask');
n_fail = n_fail + report(isequal(submask(yrs,'Covid (2020)'),[false;true;false]),'Covid mask');
n_fail = n_fail + report(isequal(submask(yrs,'excl. Covid'),[true;false;true]),'excl. Covid mask');

% --- quarter index round-trip
ok = true;
for yy = 2005:2026
    for qq = 1:4
        [y2,q2] = qi2yq(4*yy+qq); ok = ok && y2==yy && q2==qq;
    end
end
n_fail = n_fail + report(ok,'quarter index round-trips');

% --- the figures must render and be written
if ~isfolder('./figures'), mkdir('./figures'); end
f1 = './figures/forecast_errors_by_horizon.png';
f2 = './figures/accuracy_by_horizon.png';
if isfile(f1), delete(f1); end
if isfile(f2), delete(f2); end
randn('seed',3);
nm = 3; hm = 4; err = []; mi = []; hi = [];
for mm = 1:nm
    for hh = 1:hm
        e = (0.15 + 0.20*hh)*randn(40,1);
        err = [err; e]; mi = [mi; mm*ones(40,1)]; hi = [hi; hh*ones(40,1)]; %#ok<AGROW>
    end
end
mdl = {'DFM','AR direct','AR iterative'};
ok_fig = true;
try
    plot_error_distributions(err,mi,hi,mdl,hm);
    plot_accuracy_by_horizon(0.3+rand(nm,hm),0.2+rand(nm,hm),mdl,hm);
catch err_fig
    ok_fig = false;
    fprintf('        %s\n',err_fig.message);
end
n_fail = n_fail + report(ok_fig && isfile(f1) && isfile(f2),'figures render and are written to ./figures/');

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
