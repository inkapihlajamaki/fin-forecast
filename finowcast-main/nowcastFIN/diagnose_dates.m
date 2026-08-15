% Diagnostic for the error
%   "Unable to perform assignment because the size of the left side is 0-by-N"
%   in common_load_data, line 159:  temp(inx,:) = data_q(i,:);
%
% That line fails when a row of the Quarterly sheet has a (year, month) that
% does not exist in the date column of the Monthly sheet, so that the lookup
% returns nothing. This script reproduces the loading steps of
% common_load_data and reports exactly which rows are involved and why.
%
% HOW TO USE
%   1. put this file in the root of the toolbox (next to Nowcast_Main_vF.m)
%   2. set excel_datafile below to the name of YOUR data file, without .xlsx
%   3. run it
%
% It only reads the file - nothing is written or modified.

clear
excel_datafile = 'data_Example1';   % <-- CHANGE THIS to your file (no .xlsx)
date_format = 'dd.MM.yyyy';         % <-- must match the format used in common_load_data
mon_freq = 'Monthly';
quar_freq = 'Quarterly';

addpath('./tools');
addpath('./dataset');

% ---------------------------------------------------------------------
%% Reproduce the loading steps of common_load_data
% ---------------------------------------------------------------------

[A,B] = xlsread(excel_datafile,mon_freq);
[C,D] = xlsread(excel_datafile,quar_freq);

fprintf('\n================ DATE DIAGNOSTIC ================\n');
fprintf('File: %s.xlsx\n',excel_datafile);
fprintf('Monthly sheet   : %d data rows, %d series\n',size(B,1)-4,size(A,2));
fprintf('Quarterly sheet : %d data rows, %d series\n',size(D,1)-4,size(C,2));

% Dates, exactly as common_load_data reads them
raw_m = B(5:end,1);
raw_q = D(5:end,1);
dt_m = datetime(raw_m,'InputFormat',date_format);
dt_q = datetime(raw_q,'InputFormat',date_format);

% Unparsed dates (NaT) are a common cause: a blank row, a footnote, or a
% date displayed in a format other than date_format
bad_m = find(isnat(dt_m));
bad_q = find(isnat(dt_q));
if ~isempty(bad_m)
    fprintf('\n[!] %d monthly date(s) could not be read. Excel rows: %s\n', ...
            numel(bad_m),mat2str((bad_m(:)'+4)));
    fprintf('    First offending cell content: "%s"\n',string(raw_m{bad_m(1)}));
end
if ~isempty(bad_q)
    fprintf('\n[!] %d quarterly date(s) could not be read. Excel rows: %s\n', ...
            numel(bad_q),mat2str((bad_q(:)'+4)));
    fprintf('    First offending cell content: "%s"\n',string(raw_q{bad_q(1)}));
    fprintf('    A blank or stray row at the bottom of the sheet is the usual cause.\n');
end

[Year_m,Month_m] = datevec(dt_m);
[Year_q,Month_q] = datevec(dt_q);
t_m = [Year_m, Month_m];
t_q = [Year_q, Month_q];

% The first row of each sheet is consumed by the growth-rate transformation
t_m = t_m(2:end,:);
t_q = t_q(2:end,:);

% ---------------------------------------------------------------------
%% Report
% ---------------------------------------------------------------------

fprintf('\n--- Coverage ---\n');
fprintf('Monthly   : %d/%d  to  %d/%d   (%d months)\n', ...
        t_m(1,2),t_m(1,1),t_m(end,2),t_m(end,1),size(t_m,1));
fprintf('Quarterly : %d/%d  to  %d/%d   (%d quarters)\n', ...
        t_q(1,2),t_q(1,1),t_q(end,2),t_q(end,1),size(t_q,1));

% Convert to a running month counter for easy comparison
mth_m = 12*t_m(:,1) + t_m(:,2);
mth_q = 12*t_q(:,1) + t_q(:,2);

fprintf('\n--- Check 1: does the monthly sheet start early enough? ---\n');
n_before = sum(mth_q < mth_m(1));
if n_before > 0
    fprintf('[PROBLEM] %d quarterly observation(s) start BEFORE the monthly sample.\n',n_before);
    fprintf('          First quarterly date : %d/%d\n',t_q(1,2),t_q(1,1));
    fprintf('          First monthly date   : %d/%d\n',t_m(1,2),t_m(1,1));
    fprintf('          The toolbox looks each quarterly date up in the monthly date\n');
    fprintf('          column, so the monthly sheet must span at least as far back.\n');
    fprintf('          FIX: either delete the quarterly rows before %d/%d, or extend\n',t_m(1,2),t_m(1,1));
    fprintf('          the monthly sheet backwards (empty cells are fine, the dates\n');
    fprintf('          in column A are what matters).\n');
else
    fprintf('OK - the monthly sample starts at or before the first quarterly date.\n');
end

fprintf('\n--- Check 2: gaps or duplicates in the monthly date column ---\n');
gaps = find(diff(mth_m) ~= 1);
if ~isempty(gaps)
    fprintf('[PROBLEM] the monthly dates are not consecutive. First break after %d/%d\n', ...
            t_m(gaps(1),2),t_m(gaps(1),1));
    fprintf('          (next date is %d/%d, Excel rows %d and %d)\n', ...
            t_m(gaps(1)+1,2),t_m(gaps(1)+1,1),gaps(1)+5,gaps(1)+6);
    fprintf('          FIX: every month must have its own row, even if all values are empty.\n');
else
    fprintf('OK - the monthly dates run consecutively with no gap or duplicate.\n');
end

fprintf('\n--- Check 3: are the quarterly dates on quarter-end months? ---\n');
odd_q = find(mod(t_q(:,2),3) ~= 0);
if ~isempty(odd_q)
    fprintf('[PROBLEM] %d quarterly date(s) are not in March, June, September or December.\n',numel(odd_q));
    fprintf('          First one: %d/%d (Excel row %d)\n',t_q(odd_q(1),2),t_q(odd_q(1),1),odd_q(1)+5);
    fprintf('          FIX: quarterly observations must be dated on the LAST month of\n');
    fprintf('          the quarter, otherwise the mixed-frequency alignment is wrong.\n');
else
    fprintf('OK - every quarterly date falls on the last month of a quarter.\n');
end

fprintf('\n--- Check 4: the lookup that actually fails ---\n');
missing = [];
for i = 1:size(t_q,1)
    if isempty(find(t_m(:,1)==t_q(i,1) & t_m(:,2)==t_q(i,2),1))
        missing(end+1,1) = i; %#ok<SAGROW>
    end
end
if isempty(missing)
    fprintf('OK - every quarterly date was found in the monthly date column.\n');
    fprintf('     The merge in common_load_data will not fail on this file.\n');
else
    fprintf('[PROBLEM] %d quarterly date(s) have no matching monthly row.\n',numel(missing));
    fprintf('     These are the rows on which line 159 errors.\n\n');
    fprintf('     %-12s %-10s %-12s %s\n','Excel row','Date','Position','Note');
    for k = 1:min(numel(missing),15)
        i = missing(k);
        if mth_q(i) < mth_m(1)
            pos = 'before'; note = 'earlier than the monthly sample';
        elseif mth_q(i) > mth_m(end)
            pos = 'after'; note = 'later than the monthly sample';
        else
            pos = 'inside'; note = 'inside the range - month missing from column A';
        end
        fprintf('     %-12d %02d/%-8d %-12s %s\n',i+5,t_q(i,2),t_q(i,1),pos,note);
    end
    if numel(missing) > 15
        fprintf('     ... and %d more\n',numel(missing)-15);
    end
end

fprintf('\n================================================\n\n');
