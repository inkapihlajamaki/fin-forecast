 FORECASTING FINLAND'S QUARTERLY GDP GROWTH WITH A DYNAMIC FACTOR MODEL
 Replication files
 
 Author   : Inka Pihlajamäki
 
 The empirical work builds on the ECB nowcasting toolbox of Linzenich, J., and
 Meunier, B. (2024), "Nowcasting Made Easier: a Toolbox for Real-Time
 Predictions", ECB Working Paper Series No 3004. The toolbox is written for
 nowcasting, i.e. for the current quarter and at most one quarter ahead. It has
 been extended here to produce forecasts up to four quarters ahead, and an AR(p)
 benchmark and an evaluation layer have been added. Section 5 below lists
 what was changed relative to the published toolbox.
 
 1. QUICK START
 
 1. Open MATLAB (R2022a or later).
 2. Change the current folder to the ROOT folder of this package, i.e. the
    folder that contains this README.txt and run_all.m.
 3. Type:
 
        run_all
 
    run_all.m locates every other file relative to its own position,
    so nothing has to be edited and no path has to be set.
 
 The full run takes several hours, almost all of it in the DFM step, which
 re-estimates the factor model at every month of the evaluation sample. To
 reproduce only part of the results, or to re-run the evaluation on forecasts
 that have already been produced:
 
        run_all('Stages',{'ar','eval'})   run only the AR benchmark and the
                                          evaluation
        run_all('Reuse',true)             skip any step whose output file is
                                          already on disk
        run_all('Stages','selftest')      run the built-in checks only (seconds)
        run_all('SelfTests',false)        skip the built-in checks
        run_all('Diary',false)            do not write a log file
 
 Every run writes a full transcript to
 finowcast-main/nowcastFIN/logs/run_all_<timestamp>.log.
 
================================================================================
 2. WHAT run_all.m DOES, STEP BY STEP
================================================================================
 
 STEP 1  'selftest'
         Runs the built-in checks of ar_benchmark.m and evaluate_forecasts.m.
         They work on simulated data with a known answer: the AR estimator is
         checked against a simulated AR(2), and the horizon mapping, the
         percentile routine and the figure code are checked against hand-worked
         cases. Nothing is read from the dataset and nothing is overwritten. If
         these fail, the code is broken rather than the data.
         Runs in a few seconds.
 
 STEP 2  'dfm'   -> Nowcast_Main_vF.m
         The dynamic factor model. Runs the toolbox in evaluation mode
         (do_eval = 1, do_loop = 0, n_fore = 4), which walks through the
         evaluation sample month by month, re-estimates the DFM on the
         information available at that month, and stores the back-cast, the
         nowcast and the forecasts up to four quarters ahead.
         Specification: 2 factors, 1 lag, AR(1) idiosyncratic components,
         estimation from 1995M12, 15 monthly and quarterly indicators selected
         by the pre-selection step (var_keep in the file), no Covid correction.
         Evaluation sample: real-time months 2005M12 to 2024M12.
         Produces  eval/FIN/FIN_DFM_evaluation.xlsx, with one sheet per horizon
         ('Bac','Now','For','For2','For3','For4') and, on each sheet, the
         real-time month, the target quarter, the toolbox AR(1) prediction, the
         model prediction and the realised value.
         Runs in several hours.
 
 STEP 3  'ar'    -> ar_benchmark.m
         The AR(p) benchmark, estimated on the same target series 
         as the DFM but otherwise fully independent of the toolbox. 
         At every forecast origin the lag order is re-selected by
         BIC over p = 1..8 on an expanding window, and both direct and
         iterative h-step-ahead forecasts are formed for h = 1..4.
         Target quarters 2006Q1 to 2025Q4.
         Produces  eval/FIN/FIN_AR_benchmark.xlsx (sheet 'forecasts').
         Runs in under a minute.
 
 STEP 4  'eval'  -> evaluate_forecasts.m
         Puts the DFM and the AR forecasts on the same footing and scores them.
         The toolbox labels horizons relative to the nowcast quarter, while the
         guidelines define h relative to the last OBSERVED quarter; this step
         converts the former into the latter using the GDP release convention
         (gdp_rel = 2, i.e. the previous quarter's GDP is published in the
         second month of the quarter), fixes the forecast origin at the third
         month of the quarter, and reports MAE and RMSE by horizon, overall and
         for the pre-Covid, 2020, post-Covid and excluding-2020 subsamples.
         Produces  eval/FIN/forecast_evaluation.xlsx (sheets 'forecasts' and
                   'metrics')
                   figures/forecast_errors_by_horizon.png
                   figures/accuracy_by_horizon.png
         Runs in a few seconds.
 
 STEP 5  'compare' -> compare_horizons.m
         A robustness check. Over a fixed window of real-time months each
         horizon scores a different set of target quarters, so the RMSE columns
         of the evaluation file are not directly comparable. This step restricts
         every horizon to the target quarters that all horizons cover and
         reports the RMSE against the standard deviation of the realised target
         over the same quarters.
         Produces  eval/FIN/comparehorizons.txt
         Runs in a few seconds.
 
 Steps 4 and 5 read the files written by steps 2 and 3, so the order matters.
 run_all.m enforces it and stops with a clear message if an input is missing.
 
 NOT RUN by run_all.m: the variable pre-selection (Variable_selection_vF.R).
 It is a one-off step, it is written in R rather than MATLAB, and its result is
 already hard-coded in Nowcast_Main_vF.m as the vector var_keep. Section 4
 explains how to re-run it if desired.
 
 
================================================================================
 3. FOLDER STRUCTURE AND FILES
================================================================================
 
 ROOT FOLDER (the folder containing this file)
 ---------------------------------------------
 run_all.m             MASTER FILE. Runs everything in order.
 finowcast-main/       The code and data (see below)
 
 finowcast-main/nowcastFIN/     -- the working directory of all the code --
 ------------------------------------------------------------------------------
 MAIN PROGRAMS
 Nowcast_Main_vF.m         Toolbox main file. All user settings for the DFM are
                           at the top of this file, in the sections "0. TOOLBOX
                           SETTINGS" and "1. MODEL INPUTS"; the code below the
                           marked line should not be modified. This is the source 
                           for the specification reported in the paper.
 ar_benchmark.m            AR(p) benchmark, model (M1) of the guidelines
                           Also runs its own checks via ar_benchmark('selftest')
 evaluate_forecasts.m      Combines the DFM and AR forecasts, computes MAE and
                           RMSE by horizon and subsample, and draws the figures
                           Also runs evaluate_forecasts('selftest')
 compare_horizons.m        Compares horizons on a common set of target quarters
 Variable_selection_vF.R   Variable pre-selection in R
 
 DIAGNOSTICS (not needed to reproduce the results; kept for transparency)
   verify_horizons.m       Checks that the multi-horizon extension reproduces
                           the original toolbox exactly when n_fore = 1. NB:
                           written in Octave syntax (printf, functions defined
                           inside a script); run it with Octave, not MATLAB.
   diagnose_dates.m        Prints the date alignment of the input data, used
                           while checking the real-time information sets.
   diagnose_forecast_alignment.m
                           Checks that forecasts and realisations are matched to
                           the right target quarter, and compares against naive
                           benchmarks.
 
 dataset/
   data_FIN.xlsx           THE INPUT DATASET
                           Sheets:
                             Readme     - notes on the sources
                             Monthly    - 21 monthly indicators, 1985M1 onward
                                          Row 1 = transformation code, row 2 =
                                          group, row 3 = short name, row 4 =
                                          full source description, row 5 on =
                                          data, column A = dates.
                             Quarterly  - 8 quarterly indicators plus the target
                                          (last column), same layout, 1985Q1 onward
                             Groups     - names of the variable groups
                             blocks     - block structure of the factor model (not used in this case)
                             
   data_Example1.xlsx      Example dataset shipped with the original toolbox.
                           Not used in the paper; kept so that the toolbox's own
                           example still runs.
 
 tools/                    Function library, 69 files. Not to be edited.
   common_*.m              Shared routines: data loading and transformation
                           (common_load_data, common_transform_data,
                           common_read_dates), the out-of-sample evaluation
                           engine (common_eval_models), the horizon helper
                           (common_horizons), Covid and outlier handling,
                           Excel writing, and the news and range utilities.
   DFM_*.m                 Dynamic factor model: EM estimation (DFM_estimate,
                           DFM_EMstep, DFM_InitCond), the Kalman filter and
                           smoother (DFM_runKF), and the news decomposition.
   AR_estimate_forecast.m  AR(p) estimation with BIC/AIC lag selection and both
                           direct and iterative h-step forecasts. Written for
                           this paper.
   BEQ_*.m, BVAR_*.m       Bridge-equation and Bayesian VAR models of the
                           original toolbox. Not used in the paper (the model is
                           set to 'DFM'), kept so that the toolbox is complete
                           and the alternative models remain available.
 
 eval/FIN/                 Results of the evaluation.
 FIN_DFM_evaluation.xlsx   Output of step 2 (DFM forecasts by horizon).
 FIN_AR_benchmark.xlsx     Output of step 3 (AR forecasts).
 forecast_evaluation.xlsx  Output of step 4 (all forecasts and the metrics).
 comparehorizons.txt       Output of step 5.
 old/                      Earlier runs kept for reference: the model-selection
                           loops (FIN_DFM_evaluation_b1_1 to b1_5, b2_1, b2_2,
                           FIN_DFM_loop_b1) over which the specification was
                           chosen. Not used by run_all.m
 
 figures/
   forecast_errors_by_horizon.png  Distribution of forecast errors by horizon.
   accuracy_by_horizon.png         RMSE and MAE against the horizon.
                           Both are overwritten by step 4 and are the versions
                           included in the paper.
 
 output/                   Written by the toolbox in nowcasting mode
                           (do_eval = 0), which the paper does not use.
                           output/Example1/ holds the original toolbox example.
 
 logs/                     Created on the first run; holds the transcript of
                           each run of run_all.m.
 
 OTHER FILES
   README.md               Original toolbox README (attribution and citations
                           requested by Linzenich and Meunier)
   Preselection-FIN.xlsx   Output of the R pre-selection step: the ranking of
                           candidate indicators from which var_keep was taken.
   data_FIN_backup.xlsx    Copy of an earlier vintage of the dataset. Not read
                           by any program; kept only as a backup. 
 
================================================================================
 4. RE-RUNNING THE VARIABLE PRE-SELECTION (optional)
================================================================================
 
 The pre-selection to narrow down the initial set of candidate regressors.  
 It is not part of run_all.m  because it is written in R
 and its result is fixed in the paper.
 
 To re-run it:
   1. Open R (or RStudio) and set the working directory to
      finowcast-main/nowcastFIN/.
   2. Run Variable_selection_vF.R. It installs and loads the packages it needs
   3. It reads dataset/data_FIN.xlsx and writes its ranking to
      eval/FIN/FIN_preselection_method<...>.csv.
   4. The contents of the resulting .csv file should be copy-pasted (manually) to Preselection-FIN.xlsx
   5. The selected variables are then entered as the vector var_keep in
      the section "Additional inputs for subsetting input data" of
      Nowcast_Main_vF.m. The vector currently in the file is the one used in the
      paper; changing it changes the model. 
 
 
================================================================================
 5. WHAT WAS CHANGED RELATIVE TO THE PUBLISHED TOOLBOX
================================================================================
 
 The original toolbox (Linzenich and Meunier, 2024) nowcasts: it produces a
 back-cast, a nowcast and one quarter ahead. 
 The changes are:
 
 - A horizon setting, n_fore, was added to Nowcast_Main_vF.m. With n_fore = 1
   the code reproduces the original toolbox exactly; with n_fore = 4 it also
   produces the horizons 'For2', 'For3' and 'For4'. The number of months of
   empty data appended for the Kalman extrapolation follows as m = 3*(n_fore+1).
 - common_horizons.m was added to generate the horizon names, offsets and
   labels for a given n_fore; common_eval_models.m, common_mae.m and
   common_save_excel.m were generalised to loop over them instead of over the
   three hard-coded horizons.
 - Eval.dirc_dropmissing was added. At horizons beyond the nowcast, the last
   rounds of the evaluation sample have no realised target yet. The original
   code dropped those rounds from the RMSE but still counted them in the
   directional accuracy, where a missing realisation was read as "no increase".
   The default here (1) drops them from both. Setting it to 0 restores the original behaviour.
 - AR_estimate_forecast.m, ar_benchmark.m, evaluate_forecasts.m and
   compare_horizons.m were written for this paper.
 - common_read_dates.m was added and common_load_data.m routed through it, so
   that the dates in the input workbook are read on any machine (see the caveat
   in section 6).
 
 verify_horizons.m checks the first three points: that with n_fore = 1 the
 extended code reproduces the original horizons, labels and error mapping.
 
 
================================================================================
 6. REQUIREMENTS AND KNOWN CAVEATS
================================================================================
 
 SOFTWARE
   MATLAB R2022a (9.12) or later. No additional MathWorks toolboxes are
   required: the routines that would normally come from the Statistics or
   Econometrics toolboxes (percentiles, AR estimation) are hand-coded.
   R is needed only for the optional pre-selection step, Octave only for the
   optional verify_horizons.m.
 
 READING THE DATES IN THE INPUT WORKBOOK
   Column A of the 'Monthly' and 'Quarterly' sheets holds real Excel dates
   carrying Excel's built-in short-date format, which is displayed according to
   the machine's locale. What MATLAB's xlsread hands back therefore differs from
   one computer to another. The original toolbox assumed the Finnish rendering
   ('31.03.2026') and stopped elsewhere. common_read_dates.m now tries that
   first, so results on the original machine are unchanged, then the other
   common formats, and finally reads the column directly from the workbook. If
   it still cannot read the dates it says so and tells you what to do.
 
 RANDOMNESS
   There is none in the results reported in the paper. The DFM is estimated by
   EM from a deterministic initialisation, the AR by least squares. Repeated
   runs should give identical numbers. (The random model loop, do_loop = 1, is not used
   for the reported results.)
 
 OVERWRITING
   Each step deletes and rewrites its own output file. The files currently in
   eval/FIN/ and figures/ are the ones behind the numbers and figures in the
   paper, so a full re-run should reproduce them exactly, so keep a copy first if
   you want to compare. 
 
================================================================================
 7. HOW THE PAPER'S TABLES AND FIGURES MAP ONTO THE OUTPUT
================================================================================
 
 Forecast accuracy by horizon (MAE, RMSE)
     eval/FIN/forecast_evaluation.xlsx, sheet 'metrics'. One row per model,
     horizon and subsample; the subsamples are 'all', 'pre-Covid (<2020)',
     'Covid (2020)', 'post-Covid (>2020)' and 'excl. Covid'.
 Every individual forecast behind those numbers
     eval/FIN/forecast_evaluation.xlsx, sheet 'forecasts'. One row per model,
     forecast origin and horizon, with the forecast, the realisation and the
     error.
 Distribution of forecast errors
     figures/forecast_errors_by_horizon.png
 Accuracy against the horizon
     figures/accuracy_by_horizon.png
 Common-sample check across horizons
     eval/FIN/comparehorizons.txt
 Raw model output, if the intermediate steps are of interest
     eval/FIN/FIN_DFM_evaluation.xlsx and eval/FIN/FIN_AR_benchmark.xlsx
 
================================================================================
 8. CITATION OF THE UNDERLYING TOOLBOX AND MODELS
================================================================================
 
 Linzenich, J., and Meunier, B. (2024). "Nowcasting Made Easier: a Toolbox for
   Real-Time Predictions", Working Paper Series, No 3004, European Central Bank.
 Banbura, M., and Modugno, M. (2014). "Maximum likelihood estimation of factor
   models on datasets with arbitrary pattern of missing data", Journal of
   Applied Econometrics, 29(11), 133-160.
 Delle Chiaie, S., Ferrara, L., and Giannone, D. (2022). "Common factors of
   commodity prices", Journal of Applied Econometrics, 37(3), 461-476.
 
 The toolbox code in tools/ remains the responsibility of its authors. 
 The extensions and the files written for this paper are mine.
 
================================================================================
 
