function [Year,Month,dt] = common_read_dates(txt_col,excel_datafile,sheetname,preferred_format)
%COMMON_READ_DATES Read the date column of a data sheet in a locale-robust way.
%
% WHY THIS FUNCTION EXISTS
% The dates in column A of the 'Monthly' and 'Quarterly' sheets are stored as
% genuine Excel dates carrying the BUILT-IN short-date format. Excel renders
% that format according to the machine's locale, and what xlsread hands back
% therefore depends on the machine:
%   - Windows MATLAB with Excel installed (COM mode): the TEXT output holds the
%     date as displayed, i.e. '31.03.2026' on a Finnish machine, '3/31/2026' on
%     a US one, '31/03/2026' on a UK one, and so on.
%   - MATLAB without Excel (macOS, Linux, or Windows in basic mode): the text
%     output is empty for those cells and the date is only in the sheet itself.
% The original toolbox hard-codes 'dd.MM.yyyy', so it runs on the author's
% machine and fails everywhere else. Since these replication files have to run
% on a stranger's computer, the parsing is made robust here.
%
% WHAT IT DOES
% 1. Tries the preferred format first (default 'dd.MM.yyyy'), so that on the
%    original machine the result is bit-identical to the original code.
% 2. Falls back on the other common short-date formats. This is unambiguous
%    here because every date in the file is an end-of-month date, so the day
%    is always >= 13 somewhere in the column and a wrong day/month reading
%    cannot parse the whole column.
% 3. Falls back on re-reading column A straight from the workbook with
%    readtable, which returns a datetime whatever the locale.
% 4. Errors with an actionable message if all of the above fail.
%
% INPUTS
% - txt_col [cell column] = date column from the text output of xlsread
% - excel_datafile [char] = name of the workbook (without or with .xlsx)
% - sheetname [char] = name of the sheet the dates were taken from
% - preferred_format [char] = format tried first (optional, 'dd.MM.yyyy')
%
% OUTPUTS
% - Year [numeric column], Month [numeric column] = as returned by datevec
% - dt [datetime column] = the parsed dates
%
% NB: rows that cannot be read (e.g. trailing blank rows) come back as NaT and
%     hence as NaN in Year / Month, exactly as in the original code.

if nargin < 4 || isempty(preferred_format)
    preferred_format = 'dd.MM.yyyy';
end

txt_col = txt_col(:);
n = numel(txt_col);
dt = NaT(n,1);

% ---------------------------------------------------------------------
% 1-2. Parse the text that xlsread returned
% ---------------------------------------------------------------------

fmts = [{preferred_format}, ...
        {'dd.MM.yyyy','dd/MM/yyyy','dd-MM-yyyy','yyyy-MM-dd','yyyy/MM/dd', ...
         'MM/dd/yyyy','MM-dd-yyyy','dd.MM.yy','dd/MM/yy','MM/dd/yy','MM-dd-yy'}];

for ff = 1:numel(fmts)
    try
        trial = datetime(txt_col,'InputFormat',fmts{ff});
    catch
        continue    % this format does not fit the column, try the next one
    end
    if ~all(isnat(trial))
        dt = trial;
        break
    end
end

% ---------------------------------------------------------------------
% 3. Fall back on reading the column straight from the workbook
% ---------------------------------------------------------------------

if all(isnat(dt))
    try
        T = readtable(excel_datafile,'Sheet',sheetname,'Range','A5', ...
                      'ReadVariableNames',false);
        v = T{:,1};
        if isdatetime(v)
            dtall = v;
        elseif isnumeric(v)
            dtall = datetime(v,'ConvertFrom','excel');
        else
            dtall = datetime(string(v));
        end
        dtall = dtall(:);
        if numel(dtall) >= n
            dt = dtall(1:n);
        else
            dt = [dtall; NaT(n-numel(dtall),1)];
        end
    catch
        % handled by the error below
    end
end

% ---------------------------------------------------------------------
% 4. Give up with a message the user can act on
% ---------------------------------------------------------------------

if all(isnat(dt))
    first_cell = '<empty>';
    if n > 0
        try
            first_cell = char(string(txt_col{1}));
        catch
            first_cell = '<unreadable>';
        end
    end
    error(['common_read_dates: the dates in column A of sheet ''',sheetname,''' of ''', ...
           char(string(excel_datafile)),''' could not be read. The first cell reads "',first_cell,'". ', ...
           'Re-format column A of that sheet as plain text in the form 31.03.2026 (dd.MM.yyyy) ', ...
           'and run again.'])
end

[Year,Month] = datevec(dt);
Year = Year(:);
Month = Month(:);

end
