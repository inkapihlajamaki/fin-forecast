function run_all(varargin)
%RUN_ALL  Master file for "Forecasting Finland's GDP with a Dynamic Factor Model".
%
% Reproduces every forecast result reported in the paper, in order, from the
% raw input workbook. Run it from anywhere: it works out where it lives and
% sets all paths relative to itself, so no path has to be edited.
%
% -------------------------------------------------------------------------
% USAGE
% -------------------------------------------------------------------------
%   run_all                                  % everything (see the timings below)
%   run_all('Stages',{'ar','eval'})          % only some steps
%   run_all('Stages','all','SelfTests',false)
%   run_all('Reuse',true)                    % skip a step if its output exists
%
% OPTIONS (name-value, all optional)
%   'Stages'     ['all']  which steps to run, as a cell array of any of
%                         'selftest' - built-in checks of the two scripts
%                         'dfm'      - Nowcast_Main_vF.m, the DFM evaluation
%                         'ar'       - ar_benchmark.m, the AR(p) benchmark
%                         'eval'     - evaluate_forecasts.m, the comparison
%                         'compare'  - compare_horizons.m, common-sample check
%                         'all' is shorthand for all five, in that order.
%   'SelfTests'  [true]   run the built-in checks before the estimation
%   'Reuse'      [false]  if true, a step whose output file already exists is
%                         skipped. Useful to redo only the evaluation without
%                         re-running the eight-hour DFM loop.
%   'Diary'      [true]   write a full log to logs/run_all_<timestamp>.log
%
% -------------------------------------------------------------------------
% WHAT EACH STEP PRODUCES  (all paths relative to finowcast-main/nowcastFIN/)
% -------------------------------------------------------------------------
%   dfm     -> eval/FIN/FIN_DFM_evaluation.xlsx
%              Recursive out-of-sample DFM forecasts, one sheet per horizon
%              ('Bac','Now','For','For2','For3','For4'), for every real-time
%              month from 2005M12 to 2024M12.
%   ar      -> eval/FIN/FIN_AR_benchmark.xlsx
%              Direct and iterative AR(p) forecasts, h = 1..4, target quarters
%              2006Q1-2025Q4, lag order re-selected by BIC at every origin.
%   eval    -> eval/FIN/forecast_evaluation.xlsx  (sheets 'forecasts','metrics')
%              figures/forecast_errors_by_horizon.png
%              figures/accuracy_by_horizon.png
%   compare -> eval/FIN/comparehorizons.txt
%              RMSE across horizons restricted to a common set of target
%              quarters (printed by compare_horizons, captured to file here).
%
% -------------------------------------------------------------------------
% APPROXIMATE RUNNING TIMES
% -------------------------------------------------------------------------
%   selftest   a few seconds
%   dfm        several hours. The DFM is re-estimated by EM at every one of the
%              229 real-time months of the evaluation sample. This is by far
%              the longest step; the other three take about a minute together.
%   ar         under a minute
%   eval       a few seconds
%   compare    a few seconds
%
% -------------------------------------------------------------------------
% REQUIREMENTS
% -------------------------------------------------------------------------
%   MATLAB R2022a or later. No additional toolboxes are required: the code
%   uses only base MATLAB (the percentile and AR routines are hand-coded for
%   that reason). See README.txt for the one platform caveat, on how Excel
%   dates are read.
%
% The variable pre-selection (Variable_selection_vF.R) is deliberately NOT run
% here. It is a one-off step written in R whose output, the set of variables in
% var_keep, is already hard-coded in Nowcast_Main_vF.m. See README.txt.

% -------------------------------------------------------------------------
%% 0. Options
% -------------------------------------------------------------------------

opts = local_parse_options(varargin);

all_stages = {'selftest','dfm','ar','eval','compare'};
if ischar(opts.Stages) || isstring(opts.Stages)
    if strcmpi(opts.Stages,'all')
        stages = all_stages;
    else
        stages = {char(opts.Stages)};
    end
else
    stages = cellfun(@char,opts.Stages,'UniformOutput',false);
    if any(strcmpi(stages,'all')), stages = all_stages; end
end
stages = lower(stages);
bad = setdiff(stages,all_stages);
if ~isempty(bad)
    error('run_all: unknown stage ''%s''. Valid stages: %s.',bad{1},strjoin(all_stages,', '));
end
% keep the canonical order whatever order the user passed
stages = all_stages(ismember(all_stages,stages));
if ~opts.SelfTests
    stages = stages(~strcmp(stages,'selftest'));
end

% -------------------------------------------------------------------------
%% 1. Locate the code and move there
% -------------------------------------------------------------------------
% Everything below uses paths relative to the code folder, so that the package
% can be unzipped anywhere. The original working directory and the MATLAB
% search path are restored on exit, including if the run is interrupted.

here     = fileparts(mfilename('fullpath'));      % the folder holding this file
codedir  = fullfile(here,'finowcast-main','nowcastFIN');
if ~isfolder(codedir)
    error(['run_all: expected to find the code in ''finowcast-main/nowcastFIN'' next to this file, ' ...
           'but ''%s'' does not exist. Keep run_all.m in the root folder of the package.'],codedir);
end

old_dir  = pwd;
old_path = path;
cleanup  = onCleanup(@() local_restore(old_dir,old_path));   %#ok<NASGU>
cd(codedir);
addpath(fullfile(codedir,'tools'));
addpath(fullfile(codedir,'dataset'));

% Folders written to. Created here so that a fresh clone (where git does not
% carry empty folders) does not fail on the first write.
for f = {'./eval','./eval/FIN','./figures','./output','./output/FIN','./logs'}
    if ~isfolder(f{1}), mkdir(f{1}); end
end

if opts.Diary
    logfile = fullfile('./logs',['run_all_',datestr(now,'yyyy-mm-dd_HHMMSS'),'.log']); %#ok<TNOW1,DATST>
    diary(logfile);
    diary on
    cleanup_diary = onCleanup(@() diary('off'));   %#ok<NASGU>
else
    logfile = '';
end

t_start = tic;
fprintf('\n');
fprintf('==========================================================================\n');
fprintf('  FORECASTING FINLAND''S GDP - MASTER FILE\n');
fprintf('==========================================================================\n');
fprintf('  Started      : %s\n',datestr(now,'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
fprintf('  MATLAB       : %s\n',version);
fprintf('  Code folder  : %s\n',codedir);
fprintf('  Stages       : %s\n',strjoin(stages,' -> '));
fprintf('  Reuse output : %d\n',opts.Reuse);
if ~isempty(logfile)
    fprintf('  Log file     : %s\n',fullfile(codedir,logfile));
end
fprintf('==========================================================================\n\n');

% -------------------------------------------------------------------------
%% 2. Check that every input the run needs is present
% -------------------------------------------------------------------------

local_check_inputs();

% File names produced by the steps below. These are fixed by the code being
% called (see the header) and are only repeated here to check for their
% existence and to chain the steps together.
dfm_file = './eval/FIN/FIN_DFM_evaluation.xlsx';
ar_file  = './eval/FIN/FIN_AR_benchmark.xlsx';
ev_file  = './eval/FIN/forecast_evaluation.xlsx';
cmp_file = './eval/FIN/comparehorizons.txt';

% -------------------------------------------------------------------------
%% 3. Run the steps
% -------------------------------------------------------------------------

for ss = 1:numel(stages)

    stage = stages{ss};
    local_banner(ss,numel(stages),stage);
    t_stage = tic;

    switch stage

        case 'selftest'
            % Built-in checks of the two files written for this paper. They run
            % on simulated data with a known answer and touch no real data, so
            % a failure here means the code itself is broken, not the dataset.
            ar_benchmark('selftest');
            evaluate_forecasts('selftest');

        case 'dfm'
            % Nowcast_Main_vF.m is a SCRIPT that begins with 'clear'. It is
            % called from inside a function below so that the clear affects
            % only that function's workspace and not this one.
            if opts.Reuse && isfile(dfm_file)
                fprintf('Reuse is on and %s already exists - skipped.\n',dfm_file);
            else
                fprintf(['This step re-estimates the DFM at every real-time month of the\n' ...
                         'evaluation sample and takes several hours. Progress is printed below.\n\n']);
                local_run_dfm();
                if ~isfile(dfm_file)
                    error(['run_all: the DFM step finished but %s was not written. Check the settings ' ...
                           'at the top of Nowcast_Main_vF.m (do_eval must be 1 and do_loop 0).'],dfm_file);
                end
            end

        case 'ar'
            if opts.Reuse && isfile(ar_file)
                fprintf('Reuse is on and %s already exists - skipped.\n',ar_file);
            else
                ar_opts = struct();
                ar_opts.country      = 'FIN';   % writes to eval/FIN/FIN_AR_benchmark.xlsx
                ar_opts.target_start = [2006 1];
                ar_opts.target_end   = [2025 4];
                ar_opts.h_max        = 4;
                ar_opts.pmax         = 8;
                ar_opts.ic           = 'BIC';
                ar_opts.window       = 'expanding';  % matches the DFM's expanding sample
                ar_benchmark('data_FIN',ar_opts);
            end

        case 'eval'
            if ~isfile(dfm_file)
                error(['run_all: %s is missing, so the evaluation cannot run. Run the ''dfm'' stage ' ...
                       'first (run_all(''Stages'',''dfm'')).'],dfm_file);
            end
            if ~isfile(ar_file)
                error(['run_all: %s is missing, so the evaluation cannot run. Run the ''ar'' stage ' ...
                       'first (run_all(''Stages'',''ar'')).'],ar_file);
            end
            ev_opts = struct();
            ev_opts.country   = 'FIN';
            ev_opts.gdp_rel   = 2;   % must match Eval.gdp_rel in Nowcast_Main_vF.m
            ev_opts.mth_of_q  = 3;   % forecasts made in the last month of the quarter
            ev_opts.h_max     = 4;
            ev_opts.target_start = [2006 1];
            ev_opts.target_end   = [2025 4];
            ev_opts.make_plots   = true;
            evaluate_forecasts(dfm_file,ar_file,ev_opts);

        case 'compare'
            % compare_horizons prints to the screen and writes nothing, so the
            % output is captured here and saved next to the other results.
            if ~isfile(dfm_file)
                error('run_all: %s is missing, so compare_horizons cannot run.',dfm_file);
            end
            txt = evalc('compare_horizons(dfm_file,3)');
            fid = fopen(cmp_file,'w');
            if fid == -1
                warning('run_all: could not open %s for writing; the output is only shown below.',cmp_file);
            else
                fprintf(fid,'%% Output of compare_horizons(''%s'',3)\n',dfm_file);
                fprintf(fid,'%% Produced by run_all.m on %s\n\n',datestr(now,'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
                fprintf(fid,'%s',txt);
                fclose(fid);
            end
            fprintf('%s',txt);
            fprintf('Saved to %s\n',cmp_file);

    end

    fprintf('\n--- stage ''%s'' done in %s ---\n',stage,local_hms(toc(t_stage)));

end

% -------------------------------------------------------------------------
%% 4. Summary
% -------------------------------------------------------------------------

fprintf('\n==========================================================================\n');
fprintf('  ALL REQUESTED STAGES COMPLETED in %s\n',local_hms(toc(t_start)));
fprintf('==========================================================================\n');
fprintf('  Output files (relative to finowcast-main/nowcastFIN/):\n');
outs = {dfm_file,ar_file,ev_file,cmp_file, ...
        './figures/forecast_errors_by_horizon.png','./figures/accuracy_by_horizon.png'};
for oo = 1:numel(outs)
    if isfile(outs{oo})
        d = dir(outs{oo});
        fprintf('    [x] %-52s %s\n',outs{oo},datestr(d.datenum,'yyyy-mm-dd HH:MM')); %#ok<DATST>
    else
        fprintf('    [ ] %-52s (not produced in this run)\n',outs{oo});
    end
end
fprintf('==========================================================================\n\n');

end % end of run_all


% =========================================================================
%% Local functions
% =========================================================================

function local_run_dfm()
%LOCAL_RUN_DFM Run the toolbox main file in an isolated workspace.
% Nowcast_Main_vF.m starts with 'clear'. Because it is called from inside this
% function, the clear empties this function's workspace only, which is why
% nothing is passed in or out. All of the settings (do_eval = 1, do_loop = 0,
% n_fore = 4, country FIN, DFM) live in that file and are deliberately not
% overridden here, so that the file in the repository is the single source of
% truth for the specification reported in the paper.
run(fullfile(pwd,'Nowcast_Main_vF.m'));
end


function local_check_inputs()
%LOCAL_CHECK_INPUTS Fail early and clearly if something is missing.

fprintf('--- Checking inputs ---\n');

% MATLAB version
if verLessThan('matlab','9.12')
    error('run_all: MATLAB R2022a (9.12) or later is required; this is %s.',version);
end

needed = { ...
    './Nowcast_Main_vF.m',        'toolbox main file (DFM forecasts)'; ...
    './ar_benchmark.m',           'AR(p) benchmark'; ...
    './evaluate_forecasts.m',     'forecast evaluation'; ...
    './compare_horizons.m',       'common-sample comparison across horizons'; ...
    './dataset/data_FIN.xlsx',    'input dataset'; ...
    './tools/common_load_data.m', 'toolbox function library'; ...
    './tools/common_eval_models.m','out-of-sample evaluation engine'; ...
    './tools/common_horizons.m',  'horizon helper (multi-horizon extension)'; ...
    './tools/common_read_dates.m','date parsing helper'; ...
    './tools/AR_estimate_forecast.m','AR estimation and forecasting'};

missing = {};
for ii = 1:size(needed,1)
    if ~isfile(needed{ii,1})
        missing{end+1} = sprintf('    %-34s (%s)',needed{ii,1},needed{ii,2}); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error('run_all: the following required files are missing:\n%s\n',strjoin(missing,newline));
end

% The dataset must contain the sheets the loader asks for
try
    sheets = sheetnames('./dataset/data_FIN.xlsx');
catch
    sheets = string([]);
end
if ~isempty(sheets)
    want = ["Monthly","Quarterly","blocks","Groups"];
    absent = want(~ismember(want,sheets));
    if ~isempty(absent)
        error('run_all: sheet(s) %s are missing from dataset/data_FIN.xlsx.',strjoin(absent,', '));
    end
end

fprintf('All required files and sheets are present.\n\n');
end


function opts = local_parse_options(args)
%LOCAL_PARSE_OPTIONS Minimal name-value parser (no toolbox dependency).
opts = struct('Stages','all','SelfTests',true,'Reuse',false,'Diary',true);
if mod(numel(args),2) ~= 0
    error('run_all: options must be given as name-value pairs, e.g. run_all(''Reuse'',true).');
end
valid = fieldnames(opts);
for ii = 1:2:numel(args)
    name = args{ii};
    if ~(ischar(name) || isstring(name))
        error('run_all: option names must be text.');
    end
    hit = valid(strcmpi(valid,char(name)));
    if isempty(hit)
        error('run_all: unknown option ''%s''. Valid options: %s.',char(name),strjoin(valid',', '));
    end
    opts.(hit{1}) = args{ii+1};
end
opts.SelfTests = logical(opts.SelfTests);
opts.Reuse     = logical(opts.Reuse);
opts.Diary     = logical(opts.Diary);
end


function local_banner(ii,n,stage)
labels = struct('selftest','Built-in checks of ar_benchmark and evaluate_forecasts', ...
                'dfm','DFM forecasts - Nowcast_Main_vF.m', ...
                'ar','AR(p) benchmark - ar_benchmark.m', ...
                'eval','Forecast evaluation - evaluate_forecasts.m', ...
                'compare','Horizons on a common sample - compare_horizons.m');
fprintf('\n--------------------------------------------------------------------------\n');
fprintf('  STEP %d of %d: %s\n',ii,n,labels.(stage));
fprintf('  started %s\n',datestr(now,'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
fprintf('--------------------------------------------------------------------------\n');
end


function s = local_hms(secs)
h = floor(secs/3600); m = floor((secs-3600*h)/60); s2 = secs - 3600*h - 60*m;
if h > 0
    s = sprintf('%dh %02dm %02.0fs',h,m,s2);
elseif m > 0
    s = sprintf('%dm %02.0fs',m,s2);
else
    s = sprintf('%.1fs',s2);
end
end


function local_restore(old_dir,old_path)
%LOCAL_RESTORE Put the user's session back the way it was found.
try
    diary('off');
catch
end
try
    path(old_path);
catch
end
try
    cd(old_dir);
catch
end
end
