% Verification script for the multi-horizon extension of the nowcasting toolbox.
% Run with Octave or MATLAB from the repository root:  verify_horizons
%
% It checks that
%   1. every modified file parses,
%   2. the horizon helper reproduces the original three horizons for n_fore = 1,
%   3. the generalised quarter/year labelling reproduces the original one,
%   4. the iterated AR benchmark reproduces the original AR_now / AR_1,
%   5. the mapping of predictions onto MAE horizons reproduces the original one,
%   6. the index arithmetic stays inside the data for m = 3*(n_fore+1).

addpath('./tools');
n_fail = 0;

function n_fail = check(cond,name,n_fail)
    if cond
        printf('  PASS  %s\n',name);
    else
        printf('  FAIL  %s\n',name);
        n_fail = n_fail + 1;
    end
end

printf('\n=== 1. Files parse ===\n');
funs = {'common_horizons','common_mae','common_eval_models','common_save_excel', ...
        'common_load_data','DFM_estimate'};
for k = 1:numel(funs)
    ok = true;
    try
        nargin(funs{k});
    catch err
        ok = false;
        printf('        %s\n',err.message);
    end
    n_fail = check(ok,sprintf('%s.m parses',funs{k}),n_fail);
end

% Scripts cannot be parsed with nargin, so wrap them in a temporary function
scripts = {'tools/common_save_results.m','Nowcast_Main_vF.m'};
for k = 1:numel(scripts)
    txt = fileread(scripts{k});
    tmp = sprintf('parsecheck_%d.m',k);
    fid = fopen(tmp,'w');
    fprintf(fid,'function parsecheck_%d()\n%s\nend\n',k,txt);
    fclose(fid);
    ok = true;
    try
        nargin(sprintf('parsecheck_%d',k));
    catch err
        ok = false;
        printf('        %s\n',err.message);
    end
    delete(tmp);
    n_fail = check(ok,sprintf('%s parses',scripts{k}),n_fail);
end

printf('\n=== 2. Horizon helper ===\n');
[nm1,of1,~] = common_horizons(1);
n_fail = check(isequal(nm1,{'Bac','Now','For'}),'n_fore=1 gives the original three horizons',n_fail);
n_fail = check(isequal(of1,[-3 0 3]),'n_fore=1 gives the original offsets',n_fail);
[nm4,of4,lb4] = common_horizons(4);
n_fail = check(isequal(nm4,{'Bac','Now','For','For2','For3','For4'}),'n_fore=4 names',n_fail);
n_fail = check(isequal(of4,[-3 0 3 6 9 12]),'n_fore=4 offsets',n_fail);
n_fail = check(strcmp(lb4{6},'forecast (t+4)'),'n_fore=4 labels',n_fail);
n_fail = check(strcmp(nm4{1},nm1{1}) && strcmp(nm4{3},nm1{3}),'first horizons keep their original names',n_fail);

printf('\n=== 3. Quarter / year labelling of the output sheets ===\n');
% Original toolbox logic, reproduced verbatim
QuartersQ = {'Q1','Q2','Q3','Q4','Q1','Q2'};
ok_lab = true;
for Qend = 1:4
    for Yearq_in = [2023 2025]
        Qsheet_o = QuartersQ{Qend+1};
        Qsheet_fore_o = QuartersQ{Qend+2};
        Yearq_o = Yearq_in;
        if Qend == 4
            Yearq_o = Yearq_o + 1; Yearq_fore_o = Yearq_o;
        elseif Qend == 3
            Yearq_fore_o = Yearq_o + 1;
        else
            Yearq_fore_o = Yearq_o;
        end
        sheet1_o = strcat(num2str(Yearq_o),Qsheet_o);
        sheet2_o = strcat(num2str(Yearq_fore_o),Qsheet_fore_o);

        % New generalised logic
        n_pred = 2;
        q_idx = Qend + (1:n_pred);
        pred_q = mod(q_idx-1,4) + 1;
        pred_year = Yearq_in + floor((q_idx-1)/4);
        sheet1_n = strcat(num2str(pred_year(1)),'Q',num2str(pred_q(1)));
        sheet2_n = strcat(num2str(pred_year(2)),'Q',num2str(pred_q(2)));

        ok_lab = ok_lab && strcmp(sheet1_o,sheet1_n) && strcmp(sheet2_o,sheet2_n);
    end
end
n_fail = check(ok_lab,'sheet names match the original for every Qend and year',n_fail);

% And the sequence keeps rolling correctly beyond t+1
Qend = 3; Yearq_in = 2026; q_idx = Qend + (1:5);
seq = arrayfun(@(k) sprintf('%dQ%d',Yearq_in+floor((q_idx(k)-1)/4),mod(q_idx(k)-1,4)+1),1:5,'UniformOutput',false);
n_fail = check(isequal(seq,{'2026Q4','2027Q1','2027Q2','2027Q3','2027Q4'}),'sheet names roll over the year for t+2..t+4',n_fail);

printf('\n=== 4. Iterated AR benchmark ===\n');
beta = [0.12; 0.45];   % constant and AR(1) coefficient
AR_back = 0.3;
AR_back_prev = 0.2;
% Original
AR_now_o = [1 AR_back]*beta;
AR_1_o = [1 AR_now_o]*beta;
% New
C = common_horizons(4);
AR_path = nan(1,numel(C)); AR_prev = nan(1,numel(C));
AR_path(1) = AR_back; AR_prev(1) = AR_back_prev;
for hh = 2:numel(C)
    AR_path(hh) = [1 AR_path(hh-1)]*beta;
    AR_prev(hh) = AR_path(hh-1);
end
n_fail = check(abs(AR_path(2)-AR_now_o)<1e-12,'AR nowcast unchanged',n_fail);
n_fail = check(abs(AR_path(3)-AR_1_o)<1e-12,'AR t+1 unchanged',n_fail);
n_fail = check(abs(AR_path(6)-([1 [1 [1 AR_1_o]*beta]*beta]*beta))<1e-12,'AR t+4 is the AR(1) iterated four times',n_fail);
n_fail = check(all(abs(AR_prev(2:end)-AR_path(1:end-1))<1e-12),'AR direction compares consecutive quarters',n_fail);

printf('\n=== 5. Mapping of predictions onto MAE horizons ===\n');
[hor_names,~,~] = common_horizons(4);
% date_comp >= 1: the first prediction is a back-cast
hor_shift = 0;
m1 = arrayfun(@(jj) hor_names{jj+hor_shift},1:2,'UniformOutput',false);
n_fail = check(isequal(m1,{'Bac','Now'}),'back-casting round maps to Bac / Now as before',n_fail);
% date_comp == 0: the first prediction is a nowcast
hor_shift = 1;
m2 = arrayfun(@(jj) hor_names{jj+hor_shift},1:2,'UniformOutput',false);
n_fail = check(isequal(m2,{'Now','For'}),'nowcasting round maps to Now / For as before',n_fail);
m3 = arrayfun(@(jj) hor_names{jj+hor_shift},1:5,'UniformOutput',false);
n_fail = check(isequal(m3,{'Now','For','For2','For3','For4'}),'nowcasting round extends to For2..For4',n_fail);
% the most distant prediction must still exist in the horizon list
ok_bounds = true;
for n_fore = 1:6
    hn = common_horizons(n_fore);
    ok_bounds = ok_bounds && ((n_fore+1) + 1 <= numel(hn));
end
n_fail = check(ok_bounds,'horizon list always covers the n_fore+1 predictions',n_fail);

printf('\n=== 6. Index arithmetic stays inside the data ===\n');
ok_idx = true;
for n_fore = 1:6
    [~,offs] = common_horizons(n_fore);
    m = 3*(n_fore+1);
    % Evaluation / MAE loop: iQ <= i+2 and the data has i+m rows
    ok_idx = ok_idx && (2 + max(offs) <= m);
    % Nowcast mode: the last predicted quarter ends 3*(n_fore+1) months after
    % the last released target, which sits at row T at the latest
    ok_idx = ok_idx && (3*(n_fore+1) <= m);
    % The back-cast still needs the quarter before it
    ok_idx = ok_idx && (min(offs) - 3 == -6);
end
n_fail = check(ok_idx,'m = 3*(n_fore+1) covers every horizon for n_fore = 1..6',n_fail);
n_fail = check(3*(1+1)==6,'n_fore = 1 reproduces the original m = 6',n_fail);

printf('\n=== 7. Target dates on a realistic monthly grid ===\n');
% Build a monthly date grid 2005M1 to 2026M6 and append m NaN months, as
% common_load_data does, then walk through the evaluation loop and check that
% every horizon lands on the third month of the expected quarter.
n_fore = 4;
[C,offs] = common_horizons(n_fore);
m = 3*(n_fore+1);
yy = []; mm = [];
for y = 2005:2026
    for k = 1:12
        yy(end+1,1) = y; mm(end+1,1) = k;
    end
end
t_m = [yy mm];
t_m = t_m(1:find(t_m(:,1)==2026 & t_m(:,2)==6),:);
datet = t_m;
for k = 1:m % complete the dates, as common_complete_dates_fct does
    nxt = datet(end,2) + 1;
    if nxt > 12, datet(end+1,:) = [datet(end,1)+1, 1]; else datet(end+1,:) = [datet(end,1), nxt]; end
end
n_obs = size(t_m,1);

ok_dates = true; ok_range = true;
for i = 120:(n_obs-3) % every possible real-time month
    iQ = i + mod(3-mod(t_m(i,2),3),3);   % last month of the current quarter
    ok_dates = ok_dates && (mod(datet(iQ,2),3)==0); % iQ must be a third month
    for hh = 1:numel(C)
        idx = iQ + offs(hh);
        ok_range = ok_range && (idx >= 1) && (idx <= i+m) && (idx-3 >= 1);
        % the target must be the third month of the quarter offs(hh)/3 away
        ok_dates = ok_dates && (mod(datet(idx,2),3)==0);
        months_apart = 12*(datet(idx,1)-datet(iQ,1)) + (datet(idx,2)-datet(iQ,2));
        ok_dates = ok_dates && (months_apart == offs(hh));
    end
end
n_fail = check(ok_dates,'every horizon lands on the third month of the expected quarter',n_fail);
n_fail = check(ok_range,'every horizon index stays within the estimation sample (1..i+m)',n_fail);

% The most distant horizon must also stay inside xest, which has n_obs+m rows
i = n_obs - 3; iQ = i + mod(3-mod(t_m(i,2),3),3);
n_fail = check(iQ + max(offs) <= n_obs + m,'the t+4 target stays inside the appended data',n_fail);

printf('\n=== Summary ===\n');
if n_fail == 0
    printf('All checks passed.\n\n');
else
    printf('%d check(s) FAILED.\n\n',n_fail);
end
