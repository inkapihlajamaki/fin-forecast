function [fc_dir,fc_it,p_sel,ic_out] = AR_estimate_forecast(y,h_max,pmax,ic)
% Direct and iterative h-steps-ahead forecasts from an AR(p) process, with the
% lag order chosen by an information criterion.
%
% This is model (M1) of the seminar guidelines: the AR(p) benchmark, with both
% the direct forecast (a separate regression of y_{t+h} on y_t, ..., y_{t-p+1}
% for each h) and the iterative forecast (a one-step AR(p) applied h times).
%
% INPUTS
% - y [vector] = the target, observed up to and including the forecast origin.
%                Everything in y is treated as known; the caller is responsible
%                for having trimmed it to the real-time information set.
% - h_max [scalar] = longest horizon, in quarters
% - pmax [scalar] = largest lag order considered
% - ic [string] = 'AIC' or 'BIC', the criterion used to pick the lag order
%
% OUTPUTS
% - fc_dir [1 x h_max] = direct forecasts,    fc_dir(h) is y_{T+h|T}
% - fc_it  [1 x h_max] = iterative forecasts, fc_it(h)  is y_{T+h|T}
% - p_sel [scalar] = lag order selected
% - ic_out [struct] = .values (pmax x 1 criterion values), .name, .aic, .bic
%
% NB: the lag order is selected once per origin, on the one-step AR(p), and the
%     same order is used for the direct regressions at every horizon. This is
%     the usual convention and keeps the two methods comparable: selecting a
%     different p for every horizon would confound the direct/iterative
%     comparison with a changing specification.
% NB: at h = 1 the direct and the iterative forecast are identical by
%     construction - the two regressions are the same one, written differently.
%     The selftest in ar_benchmark.m checks this.

y = y(:);
y = y(~isnan(y));           % the caller passes a trimmed vintage; drop any gaps
T = numel(y);

fc_dir = nan(1,h_max);
fc_it  = nan(1,h_max);
p_sel  = NaN;
ic_out = struct('values',nan(pmax,1),'name',ic,'aic',nan(pmax,1),'bic',nan(pmax,1));

% Not enough observations to estimate anything sensible
if T < pmax + 10
    return
end

% ---------------------------------------------------------------------
%% 1. Select the lag order on the one-step AR(p)
% ---------------------------------------------------------------------
% All candidate orders are estimated on the SAME sample (starting at pmax+1),
% otherwise the criteria are not comparable across p.

aic = nan(pmax,1);
bic = nan(pmax,1);
for p = 1:pmax
    idx = (pmax+1:T)';
    X = ones(numel(idx),1);
    for j = 1:p
        X = [X, y(idx-j)]; %#ok<AGROW>
    end
    Y = y(idx);
    b = X\Y;
    e = Y - X*b;
    n = numel(Y);
    k = p + 1;                          % coefficients, including the constant
    sig2 = (e'*e)/n;
    if sig2 <= 0 || ~isfinite(sig2)
        continue
    end
    aic(p) = log(sig2) + 2*k/n;
    bic(p) = log(sig2) + k*log(n)/n;
end

if strcmpi(ic,'AIC')
    crit = aic;
else
    crit = bic;
end
if all(isnan(crit))
    return
end
[~,p_sel] = min(crit);
ic_out.values = crit;
ic_out.aic = aic;
ic_out.bic = bic;

p = p_sel;

% ---------------------------------------------------------------------
%% 2. Iterative forecast
% ---------------------------------------------------------------------
% Estimate the one-step AR(p) on the longest sample available for that p, then
% feed each forecast back in as the next observation.

idx = (p+1:T)';
X = ones(numel(idx),1);
for j = 1:p
    X = [X, y(idx-j)]; %#ok<AGROW>
end
b = X\y(idx);
c = b(1);
phi = b(2:end);                          % phi(j) multiplies y_{t-j}

z = y(T:-1:T-p+1);                       % [y_T; y_{T-1}; ...; y_{T-p+1}]
for hh = 1:h_max
    yhat = c + phi'*z;
    fc_it(hh) = yhat;
    z = [yhat; z(1:end-1)];              % roll the state forward
end

% ---------------------------------------------------------------------
%% 3. Direct forecasts
% ---------------------------------------------------------------------
% One regression per horizon: y_{t+h} on a constant and y_t, ..., y_{t-p+1}.

xf = [1, y(T:-1:T-p+1)'];                % regressors at the origin
for hh = 1:h_max
    idx = (p:(T-hh))';
    if numel(idx) < p + 5                % too short to estimate this horizon
        continue
    end
    X = ones(numel(idx),1);
    for j = 0:p-1
        X = [X, y(idx-j)]; %#ok<AGROW>
    end
    Y = y(idx+hh);
    b_h = X\Y;
    fc_dir(hh) = xf*b_h;
end

end
