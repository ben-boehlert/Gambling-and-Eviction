# Handle Maturity Audit for Launch-Date LP-DiD

**Prepared:** 2026-08-20  
**Scope:** Descriptive audit only; no estimator or treatment date was changed  
**Analysis cutoff:** December 2024  
**Primary source:** `data/processed/activity_treatment_dates.csv`  
**Supporting audit:** `quality_reports/postcovid_ramp_candidate_data_profile.md`

## Bottom line

The concern is well founded for the **pre-COVID launch cohorts**, subject to the
peak-calibration convention. Under the project-default calibration, only Rhode
Island among the five pre-COVID online-launch states in the audited analysis
frame had reached 50% of its frozen peak before March 2020, and none had reached
75%. Indiana, New Hampshire, Pennsylvania, and West Virginia first reached 50%
during the COVID interruption under that calibration; all five reached 75%
during or after the interruption.

That first claim is not completely invariant to the peak-exclusion window. If
the peak calibration excludes the broader March 2020--March 2022 interval,
West Virginia's 50% crossing moves from August 2020 to January 2020. The other
early-state 50%/75% dates are unchanged, and no early state reaches 75% before
March 2020 under either calibration.

Consequently, a non-straddling pre-COVID LP-DiD cannot estimate a mature-market
effect for these early adopters. It estimates the effect of legal access during
the initial ramp. A smaller launch-date estimate can be interpreted as
attenuation relative to a mature-market effect only under additional conditions:
the eviction effect must be weakly monotone in contemporaneous or cumulative
Handle, early legal access must have no offsetting effect independent of Handle,
and the early- and mature-horizon effects must pertain to a comparable target
population. Without those conditions, market maturation implies a different
dynamic estimand, not a predictable direction of bias. In all cases, the
launch-date LP-DiD remains an intent-to-treat effect of legal access rather than
a biased estimate of that launch-date parameter.

## Audited 50% and 75% crossing dates

Thresholds are the first month at or above 50% or 75% of each state's frozen
maximum nominal monthly Handle through December 2024, with March 2020--July
2021 excluded when selecting that maximum. The search for the first threshold
crossing uses the full monthly sequence, so a reported crossing itself can fall
inside the excluded COVID months. Lags are calendar months from verified online
launch. The table covers all Handle-observed online-treated states in the
audited analysis frame and reports the project-default calibration.

| State | Online launch | 50% date | Lag | 75% date | Lag |
|---|---:|---:|---:|---:|---:|
| West Virginia | 2018-08 | 2020-08 | 24 | 2020-09 | 25 |
| Pennsylvania | 2019-05 | 2020-10 | 17 | 2021-10 | 29 |
| Rhode Island | 2019-09 | 2019-11 | 2 | 2020-11 | 14 |
| Indiana | 2019-10 | 2020-12 | 14 | 2021-10 | 24 |
| New Hampshire | 2019-12 | 2021-01 | 13 | 2021-10 | 22 |
| Colorado | 2020-05 | 2021-09 | 16 | 2022-01 | 20 |
| Tennessee | 2020-11 | 2021-10 | 11 | 2023-11 | 36 |
| Virginia | 2021-01 | 2021-10 | 9 | 2023-10 | 33 |
| Arizona | 2021-09 | 2021-10 | 1 | 2022-03 | 6 |
| Connecticut | 2021-10 | 2021-11 | 1 | 2023-10 | 24 |
| Louisiana | 2022-01 | 2022-02 | 1 | 2023-11 | 22 |
| New York | 2022-01 | 2022-01 | 0 | 2023-01 | 12 |
| Arkansas | 2022-03 | 2023-03 | 12 | 2023-11 | 20 |
| Kansas | 2022-09 | 2022-09 | 0 | 2023-09 | 12 |
| Maryland | 2022-11 | 2022-12 | 1 | 2022-12 | 1 |
| Ohio | 2023-01 | 2023-01 | 0 | 2023-01 | 0 |
| Massachusetts | 2023-03 | 2023-03 | 0 | 2023-11 | 8 |
| Kentucky | 2023-09 | 2023-10 | 1 | 2023-10 | 1 |
| Maine | 2023-11 | 2023-11 | 0 | 2023-12 | 1 |
| Delaware | 2024-01 | 2024-01 | 0 | 2024-09 | 8 |
| Vermont | 2024-01 | 2024-01 | 0 | 2024-01 | 0 |
| North Carolina | 2024-03 | 2024-03 | 0 | 2024-03 | 0 |

Florida legalized online in December 2023 but has no Handle series in the
audited file, so no threshold can be assigned. Missouri legalized after the
study cutoff. Online states outside the estimator-ready eviction frame are not
part of this table.

## What the regime split can and cannot identify

Splitting LP-DiD into pre- and post-COVID regimes protects against contrasts
whose baseline and outcome endpoints cross the omitted COVID interval. It does
not recover mature exposure for early adopters:

- Pre-COVID horizons end before four of five early cohorts reach even 50% and
  before every early cohort reaches 75%.
- In a clean-control post-COVID LP-DiD, those early cohorts are already treated
  at regime entry and therefore cannot re-enter as switchers.
- Pooling their mature post-COVID outcomes with pre-COVID baselines would
  reinstate the cross-COVID counterfactual problem the regime split was meant
  to avoid.

The honest conclusion is that this panel does not nonparametrically identify a
mature-market effect for the early-launch cohorts while also avoiding COVID.

## Recommended interpretation and sensitivity work

1. Keep verified online launch as the primary treatment date and call the
   resulting LP-DiD a dynamic **legal-access intent-to-treat** effect. Early
   horizons deliberately average immature exposure.
2. Report Handle maturation alongside the LP-DiD contributor table at every
   horizon. State explicitly that short-run null estimates do not rule out
   effects that emerge only after market scale develops.
3. Treat 50%/75% crossing-date analyses only as exploratory sensitivities with
   a different estimand. A state's realized Handle crossing is a post-launch,
   endogenous outcome. In a realized-threshold LP-DiD, every observation after
   legal launch but before the crossing is already legally treated. Coding
   those observations as untreated makes them contaminated controls unless
   sub-threshold betting and legal access have exactly zero effect. Thus the
   design requires both a no-effect-below-threshold restriction and a defense
   of the endogenous crossing time; it cannot be interpreted as the original
   legal-access ITT.
4. The existing post-COVID audit supports only Arkansas as a genuine delayed-
   ramp sensitivity: launch March 2022, 50% in March 2023, sustained 50% in
   September 2023, and 75% in November 2023. Connecticut, Louisiana, New York,
   Tennessee, and Virginia cross 75% later but were already near or above 50%
   by April 2022; treating them as untreated until 75% would be misleading.
5. If a maturity-timing sensitivity is retained, prefer an externally fixed or
   leave-one-state-out predicted lag over the state's own realized Handle date,
   and label it secondary rather than a fix for COVID identification.

## Right-censoring and measurement flags

The peak is frozen at December 2024 after excluding March 2020--July 2021 from
the maximization window; it is not a known lifetime or steady-state peak.
Crossings are nevertheless searched over all months, including the excluded
interval. Threshold dates are therefore provisional for late launches,
especially Delaware, Maine, North Carolina, and Vermont, which have only about
10--14 post-launch months by the cutoff; Kentucky and Massachusetts also have
limited post-launch histories. Their apparent immediate 50%/75% crossings can
arise because the denominator is a short, right-censored maximum.

Handle is nominal, seasonal, and not per capita. These dates diagnose market
ramp-up but do not by themselves identify the causal response of evictions to
gambling intensity.

## Paper-to-code naming map

| Paper concept | Code field | Meaning |
|---|---|---|
| Monthly Handle, \(H_{it}\) | underlying `Handle` series | Nominal monthly betting volume |
| Online launch, \(G_i\) | `legal_online_start` | Verified legal online start |
| 50% crossing, \(T_i(0.50)\) | `treat_50pct_peak` | First full-sequence month Handle reaches 50% of the COVID-excluded frozen peak |
| 75% crossing, \(T_i(0.75)\) | `treat_75pct_peak` | First full-sequence month Handle reaches 75% of the COVID-excluded frozen peak |
| Launch-to-50% lag | `lag_to_50pct` | Calendar months from launch to 50% |

## Result-status note

No treatment-effect estimate, standard error, p-value, or significance claim
was produced in this descriptive audit. Existing LP-DiD joint-pretrend p-values
remain outside this audit and should not be cited without covariance-aware
joint inference.
