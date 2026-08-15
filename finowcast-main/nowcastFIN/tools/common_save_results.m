% This scripts saves the entire workspace and copies the results in the
% excel file specified in "excel_outputfile". 
% The subfolder output stores the results of each run by
% date in matlab (.mat) format.
%
% Adapted from an initial version by S. Delle Chiaie and F. Kurcz
%

%% Extract predictions and percentage of available data

% The model predicts n_pred = n_fore + 1 quarters, starting with the quarter
% that follows the last released target. Prediction jj relates to the quarter
% ending 3*jj months after the last released target.
n_pred = n_fore + 1;

% Nowcast_position finds the third month of a quarter
indxGDP = find(~isnan(xest_out(:,end)),1,'last');

% Check that the data has been extended far enough (see m in the Mainfile)
if indxGDP + 3*n_pred > size(GDP_track,1)
    error(['The dataset is not extended far enough to predict ',num2str(n_fore),' quarters ahead. ' ...
           'Set m = 3*(n_fore+1) in the Mainfile.'])
end


%% Prepare the MAE

% If real-time nowcast quarter exceeds model nowcast quarter, then we are backcasting
yr_q_mdl = [datet(indxGDP + 3,1), quarter(datetime(datet(indxGDP + 3,1),datet(indxGDP + 3,2),1))]; % model year and quarter of nowcast
yr_q_real = [year(datetime("today")),quarter(datetime("today"))]; % real-time year and quarter of nowcast
date_comp = sum(yr_q_real > yr_q_mdl);

% Map each prediction onto a horizon of the MAE structure
% If the first prediction is a back-cast, prediction jj is horizon hor_names{jj}
% (Bac, Now, For, For2, ...). Otherwise it is horizon hor_names{jj+1}.
if date_comp >= 1 % first prediction is a backcast
    hor_shift = 0;
else % first prediction is a nowcast
    hor_shift = 1;
end

% Collect the predictions, the data coverage and the errors for each horizon
% NB: the MAE are adjusted for outliers (as in ECB, 2009)
pred_value = nan(1,n_pred);
pred_share = nan(1,n_pred);
pred_mae = nan(1,n_pred);
pred_fda = nan(1,n_pred);
pred_hor = cell(1,n_pred);
for jj = 1:n_pred
    idx = indxGDP + 3*jj;                            % last month of the predicted quarter
    pred_value(jj) = GDP_track(idx,3);
    input_jj = xest_out((idx-2):idx,1:(end-1));      % inputs for the predicted quarter
    pred_share(jj) = 100 - 100*sum(isnan(input_jj),'all')/numel(input_jj);
    pred_hor{jj} = hor_names{jj + hor_shift};
    pred_mae(jj) = MAE.(pred_hor{jj}).mae;
    pred_fda(jj) = MAE.(pred_hor{jj}).fda;
end

% Keep the original variable names for the first two predictions
lastnow = pred_value(1);   share_now = pred_share(1);
mae_now = pred_mae(1);     fda_now = pred_fda(1);
forecast = pred_value(2);  share_fore = pred_share(2);
mae_for = pred_mae(2);     fda_for = pred_fda(2);


%% Prepare table for output

% One row of output per predicted quarter.
% Columns 1-11 hold the prediction and its reliability metrics, columns 12+ the
% news decomposition (by group, then by individual series).
% NB: the news decomposition is only computed for the first two predictions (see
%     DFM_News_Mainfile, which loops over forecast_news = 0:1). For the more
%     distant horizons the news columns are left empty - extend the loop in the
%     News_Mainfile of the model if a decomposition is needed there too.
pred_chartdata = cell(1,n_pred);
for jj = 1:n_pred

    % News for this horizon (available for the first two predictions only)
    if jj == 1
        news_jj = news_results;
    elseif jj == 2
        news_jj = news_results_fcst;
    else
        news_jj = [];
    end

    if prev_news == false || isempty(news_jj)

        % No news to report for this horizon: write the prediction and its
        % metrics, and leave the news columns empty
        if prev_news == false
            date_jj = strrep(namesave,'sav_', '');
        else % news exist for the earlier horizons, so the date of the run is known
            date_jj = datestr(news_results.dates(2));
        end

        pred_chartdata{jj} = {date_jj, pred_value(jj), strcat(num2str(round(pred_share(jj))),'%'), strcat(num2str(round(100*pred_fda(jj))),'%'), ... % prediction
                              pred_mae(jj), pred_value(jj) - pred_mae(jj), pred_value(jj) + pred_mae(jj), ... % MAE
                              [], ...
                              [], [], ... % old prediction (not available)
                              [], ...
                              nan(1,length(groups_name)),[], ... % last [] is for revisions to data and model
                              nan(1,1), ... % blank space between group and individual news
                              nan(1,length(nameseries))};

    else

        pred_chartdata{jj} = {datestr(news_jj.dates(2)), pred_value(jj), strcat(num2str(round(pred_share(jj))),'%'), strcat(num2str(round(100*pred_fda(jj))),'%'), ... % prediction
                              pred_mae(jj), pred_value(jj) - pred_mae(jj), pred_value(jj) + pred_mae(jj), ... % MAE
                              [], ...
                              datestr(news_jj.dates(1)), news_jj.now_old, ... % old prediction
                              [], ...
                              news_jj.group_sums, news_jj.impact_revision + news_jj.impact_reestimation, ... % news decomposition
                              nan(1,1), ... % blank space between group and individual news
                              news_jj.indiv_news}; % news decomposition for individual variables

    end

end

% Keep the original variable names for the first two predictions
chartdata = pred_chartdata{1};
quarterahead_chartdata = pred_chartdata{2};



%% Prepare table for (approximate) contributions

% Sort the individual contributions
% NB: we always sort only for the nowcast (first missing quarter)
[ctb_indiv_sorted,idx_sort] = sort(news_results.ctb_indiv(1:end-1)); % not sorting the last because this is the mean
ctb_indiv_fcst_sorted = news_results_fcst.ctb_indiv(idx_sort);

% Create the matrix for contributions
contrib = [sum(news_results.ctb_groups),sum(news_results_fcst.ctb_groups); ...
           NaN,NaN; ...
           common_ensureColumnVector(news_results.ctb_groups),common_ensureColumnVector(news_results_fcst.ctb_groups); ...
           NaN,NaN; ...
           NaN,NaN; ...
           common_ensureColumnVector(ctb_indiv_sorted),common_ensureColumnVector(ctb_indiv_fcst_sorted); ... % sort without the mean
           news_results.ctb_indiv(end),news_results_fcst.ctb_indiv(end)]; % adding the mean on the bottom

% Create the names of the contributions
nameseries_sorted = nameseries(idx_sort);
names_contrib = ['Nowcast'; ...
                 NaN; ...
                 common_ensureColumnVector(string(groups_name)); ...
                 'Mean'; ...
                 NaN; ...
                 NaN; ...
                 common_ensureColumnVector(string(nameseries_sorted)); ... % no mean in the names of series
                 'Mean'];

% Sort the full names and groups of the individual series
fullnames_sorted = fullnames(idx_sort);
groups_sorted = groups(idx_sort);
gnames_sorted = cell(size(groups_sorted));
for i = 1:length(groups_sorted)
    gnames_sorted(i) = groups_name(groups_sorted(i));
end

% Create information on individual contributions
info_indiv_contrib = cell(size(contrib,1)-1,1); % -1 because we have no information for the mean (last row of contrib / names_contrib)
num_cell = length(contrib) - length(fullnames); % +1 because of NaN in contrib / names_contrib
info_indiv_contrib(num_cell:end,1) = common_ensureColumnVector(fullnames_sorted);
info_indiv_contrib(num_cell:end,2) = num2cell(common_ensureColumnVector(groups_sorted));
info_indiv_contrib(num_cell:end,3) = common_ensureColumnVector(gnames_sorted);
info_indiv_contrib(num_cell-1,:) = {'Full names','Group ID','Group name'};

% Create a matrix with individual contributions by groups
% NB: this is for use in the Excel charts
matrix_indiv_contrib = cell(size(contrib,1)-1,max(groups_sorted));
for vv = 1:length(ctb_indiv_sorted)
    gg = groups_sorted(vv);
    matrix_indiv_contrib(num_cell+vv-1,gg) = num2cell(ctb_indiv_sorted(vv));
end

% Adding the headers
% NB: also include a warning that individual contributions are for the first prediction (backcast or nowcast)
matrix_indiv_contrib(num_cell-1,:) = groups_name;
matrix_indiv_contrib(num_cell-2,1) = {'Contributions below relate to first prediction (back-cast or nowcast)'};


%% Save the entire workspace in excel and store in the output folder
common_save_excel(pred_chartdata,Par,excel_outputfile,newsfile,prev_news,groups_name,contrib,names_contrib,info_indiv_contrib,matrix_indiv_contrib,nameseries,fullnames,heatmap,datet,country,Res,groups,do_range,range,indxGDP);


%% Save the entire workspace in matlab
% ...results in the summary file 'country.name'_GDP_tracking.xlsx

% Rename variables to save them
Qend = Par.qend;
%namesave = namesave_orig;

% Clean workspace
clear Qend_* namesave_* flag* store* Nowcast_position pos Yearq check_spelling

% Autorename the workspace if the name already exists
[namesave] = common_autorename(namesave,outputfolder,rootfolder);
save(strcat(outputfolder,namesave)); 

if strcmp('cur_nowcast.mat',newsfile)
    % Save old nowcast as old_nowcast
    if exist(strcat(outputfolder,'cur_nowcast.mat'),'file') == 2
        movefile(strcat(outputfolder,'cur_nowcast.mat'),strcat(outputfolder,'old_nowcast.mat'));
    end
    
    % Save current output as cur_nowcast
    save(strcat(outputfolder,'cur_nowcast')); 
end

% Create a vintage the output Excel for the nowcast date
vintage_excel = [strrep(namesave,'.mat',''),'_',country.name,'_tracking.xlsx'];
filename_vintage = fullfile(outputfolder, vintage_excel);
copyfile(excel_outputfile,filename_vintage);
