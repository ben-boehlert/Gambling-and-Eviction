# Cohort-specific long-difference results

## Main findings

- Placebo pre-period: -21.7% (95% CI -47.2% to +16.1%; jackknife SE 0.189; p=0.209; 8 treated states).
- Months 0-11 after online launch: +11.0% (95% CI -17.9% to +50.0%; jackknife SE 0.144; p=0.478; 8 treated states).
- Months 12-23 after online launch: +14.9% (95% CI -11.7% to +49.6%; jackknife SE 0.126; p=0.283; 8 treated states).
- Months 24-35 after online launch: +19.0% (95% CI -6.7% to +51.8%; jackknife SE 0.117; p=0.152; 8 treated states).

The point estimates are log contrasts transformed as 100*(exp(ATT)-1). 
This percentage transformation is descriptive unless the design's 
identifying assumptions hold. 
The design does not produce evidence that is robustly distinguishable from 
zero if the state-jackknife interval includes zero. The placebo is an 
important diagnostic: a nonzero placebo indicates differential movement 
before treatment rather than a causal post-treatment effect.

## Design and estimand

For each exact online-legalization month g, the primary design compares a 
24-month untreated county premean (g-30 through g-7, leaving a six-month 
anticipation gap) with fixed exposure windows g through g+11, g+12 through 
g+23, and g+24 through g+35. States without an online launch are transformed using 
the same cohort-calendar window boundaries. Primary county means require 
coverage in both windows but may use only 12/24 pre and 6/12 post months; 
they therefore need not average identical observed month sets. County 
changes are averaged to one 
state-cohort cell, and cohort contrasts are aggregated with equal treated-
state weights. This is a cohort-specific long-difference design, not a claim 
to implement the formal published Lee-Wooldridge estimator.
Treatment timing is `online_start_date` from 
`data/raw/sports_gambling_legalization_dates.csv`; first retail or other 
launch dates do not define treatment in this analysis.
The primary estimand mixes online-first/simultaneous states with states 
that already had retail betting before online launch. Its controls are 
states without an online launch, including some with retail betting. A 
causal interpretation therefore requires prior retail exposure and retail-
only control histories not to invalidate parallel cumulative changes or 
alter the response to online access.

The placebo compares g-30:g-19 with g-18:g-7. Per-cell estimates are 
descriptive because most cohorts contain one treated state. Aggregate 
inference uses a delete-one-state jackknife and never substitutes county-
clustered standard errors.

## Composition-stable primary estimates

Treated states supported at all three post horizons: WV, PA, IN, TN, VA, CT, NY, AR.
- Months 0-11: +11.0% (95% CI -17.9% to +50.0%; jackknife SE 0.144; p=0.478; 8 treated states).
- Months 12-23: +14.9% (95% CI -11.7% to +49.6%; jackknife SE 0.126; p=0.283; 8 treated states).
- Months 24-35: +19.0% (95% CI -6.7% to +51.8%; jackknife SE 0.117; p=0.152; 8 treated states).

## Retail-history regime split and clean sensitivity

Retail-first online-treated states: PA, IN, NY, AR. Online-first or simultaneous states: WV, CO, TN, VA, CT.
The online-first clean sensitivity has complete three-horizon support for WV, TN, VA, CT. CO is in the online-first/simultaneous regime but lacks clean-pre support. The resulting four treated states make inference especially fragile.
- Clean placebo: -29.4% (95% CI -64.5% to +40.6%; jackknife SE 0.329; p=0.303; 4 treated states).
- Clean months 0-11: +8.7% (95% CI -35.7% to +84.0%; jackknife SE 0.249; p=0.741; 4 treated states).
- Clean months 12-23: +19.0% (95% CI -22.8% to +83.3%; jackknife SE 0.203; p=0.405; 4 treated states).
- Clean months 24-35: +29.0% (95% CI -19.0% to +105.4%; jackknife SE 0.216; p=0.259; 4 treated states).

For each cohort endpoint, clean controls have no first sports-betting 
launch of any type by that endpoint. The contrast therefore targets first 
sports-betting access delivered online (possibly bundled with same-month 
retail), not the incremental effect of adding online access after retail.

## Sample and support

The joined panel contains 23 states (9 online-treated and 14 without an online launch), 1340 counties, and 112678 county-month rows from 2016-01-01 through 2025-09-01.
Primary coverage requires at least 12 of 24 pre months and 6 of 12 post months for the same county. There are 4 unsupported primary cohort-horizon cells.
Online-treated states excluded from every post horizon: CO (insufficient clean-pre calendar coverage). Partially supported online-treated states: none. See `treated_state_support.csv`.
States appearing in the legalization schedule but lacking an online launch date are classified as never treated for this online-access estimand: MT, NC, ND, WI. Notably, MT, NC, and ND remain controls; their retail launch dates are not used.
Unsupported primary cells: 2020-05-01 [CO]/placebo (treated cohort lacks county coverage); 2020-05-01 [CO]/months_0_11 (treated cohort lacks county coverage); 2020-05-01 [CO]/months_12_23 (treated cohort lacks county coverage); 2020-05-01 [CO]/months_24_35 (treated cohort lacks county coverage).

## Robustness specifications

The output reports six planned sensitivities: controls that are never or 
not yet treated through the window endpoint; the log filing rate; within-
state renter weighting; and stricter county coverage (18/24 pre months and 
9/12 post months). The complete-coverage specification requires every 
calendar month (24/24 pre and 12/12 post) for the same county. The online-
first clean specification restricts treated states by regime and requires 
controls to have no betting launch of any type through the endpoint.

| Specification | Horizon | Contrast (%) | 95% CI (%) | SE | p-value |
|---|---:|---:|---:|---:|---:|
| Complete coverage | placebo | -4.1 | [-43.4, +62.6] | 0.253 | 0.872 |
| Complete coverage | months_0_11 | +10.7 | [-22.8, +58.7] | 0.173 | 0.562 |
| Complete coverage | months_12_23 | +20.3 | [-13.3, +66.7] | 0.157 | 0.253 |
| Complete coverage | months_24_35 | +25.0 | [-6.4, +67.0] | 0.139 | 0.124 |
| Not-yet controls | placebo | -20.7 | [-44.2, +12.7] | 0.169 | 0.184 |
| Not-yet controls | months_0_11 | +12.6 | [-18.4, +55.4] | 0.155 | 0.451 |
| Not-yet controls | months_12_23 | +16.7 | [-13.6, +57.7] | 0.144 | 0.295 |
| Not-yet controls | months_24_35 | +19.3 | [-7.9, +54.6] | 0.124 | 0.170 |
| Online-first clean | placebo | -29.4 | [-64.5, +40.6] | 0.329 | 0.303 |
| Online-first clean | months_0_11 | +8.7 | [-35.7, +84.0] | 0.249 | 0.741 |
| Online-first clean | months_12_23 | +19.0 | [-22.8, +83.3] | 0.203 | 0.405 |
| Online-first clean | months_24_35 | +29.0 | [-19.0, +105.4] | 0.216 | 0.259 |
| Rate outcome | placebo | -10.3 | [-25.1, +7.3] | 0.086 | 0.219 |
| Rate outcome | months_0_11 | +1.7 | [-16.4, +23.7] | 0.094 | 0.861 |
| Rate outcome | months_12_23 | +3.9 | [-10.2, +20.2] | 0.070 | 0.588 |
| Rate outcome | months_24_35 | +6.9 | [-5.8, +21.3] | 0.061 | 0.286 |
| Renter weighted | placebo | -14.4 | [-42.9, +28.3] | 0.194 | 0.431 |
| Renter weighted | months_0_11 | +3.3 | [-27.3, +46.9] | 0.169 | 0.848 |
| Renter weighted | months_12_23 | +13.2 | [-16.0, +52.5] | 0.143 | 0.396 |
| Renter weighted | months_24_35 | +18.7 | [-7.9, +53.0] | 0.122 | 0.174 |
| Strict coverage | placebo | -20.1 | [-45.6, +17.3] | 0.184 | 0.237 |
| Strict coverage | months_0_11 | +12.0 | [-16.3, +49.8] | 0.140 | 0.428 |
| Strict coverage | months_12_23 | +16.0 | [-9.8, +49.3] | 0.121 | 0.233 |
| Strict coverage | months_24_35 | +19.3 | [-5.6, +50.7] | 0.112 | 0.131 |

## COVID and inference caveats

COVID overlap is flagged whenever either comparison interval intersects 
March 2020 through March 2022. Calendar matching does not remove differential 
pandemic shocks or recovery paths. Many early-cohort post windows and later-
cohort pre windows overlap this interval, so these contrasts still require a 
parallel cumulative-shocks assumption.
The aggregate `covid_any` flag is TRUE whenever any included cohort cell 
overlaps the COVID interval, including for a placebo aggregate when one or 
more of its cohort-calendar windows overlaps that interval.

Treatment is assigned at the state level and the effective sample is small. 
Delete-one-state jackknife intervals are approximate; `leave_one_state_out.csv` 
reports every replicate, invalid replicates, and the most influential state. 
A singleton treated cohort cannot support credible cell-specific inference.

Largest absolute leave-one-state-out changes in the primary estimates:

- placebo: CT, maximum absolute leave-one-out change 0.144 log points.
- months_0_11: NY, maximum absolute leave-one-out change 0.084 log points.
- months_12_23: CT, maximum absolute leave-one-out change 0.073 log points.
- months_24_35: CT, maximum absolute leave-one-out change 0.073 log points.

## Outcome summary statistics

Across county-month observations, y has mean 2.742, median 2.398, and SD 1.642; y_rate has mean 1.439, median 1.403, and SD 0.656.

## Paper-to-code naming map

| Paper notation | Code name | Meaning |
|---|---|---|
| Y_it | y, y_rate | Log filings and log filing rate |
| G_i | treat_start | First online-treatment month |
| DeltaY_i(g,h) | state_change | State long difference |
| ATT(g,h) | att_gh | Cohort-by-horizon contrast |
| ATT(h) | att_h | Equal-treated-state aggregate contrast |
