# Post-COVID Handle-Ramp Candidate Data Profile

**Prepared:** 2026-08-14  
**Analysis window:** April 2022–December 2024  
**Peak calibration cutoff:** December 2024  
**Purpose:** Determine whether states legalizing before April 2022 can credibly
enter a post-COVID CS-DiD or Sun–Abraham design because Handle had not yet
matured.

## Bottom line

Arkansas is the only usable state for which the claim is supported at the 25%,
50%, and sustained-50% thresholds. It legalized online in March 2022, was at
only 13.0% of its frozen peak in April 2022, and crossed 25% in September 2022,
50% in March 2023, and 50% for three consecutive months in September 2023.

Five additional states in the balanced estimator sample cross 75% after April
2022: Connecticut, Louisiana, New York, Tennessee, and Virginia. They are not
credible delayed-ramp additions. By April 2022 they were already at 47.8%–60.0%
of peak, and each had crossed and sustained 50% before the post-COVID sample.
Their later 75% dates largely capture continued growth or seasonality, not the
onset of meaningful exposure.

Adding Arkansas is potentially useful as an exploratory appendix sensitivity,
but not as a solution to thin CS/SA cohorts and not as a substitute for the
online-legalization estimand. It is also not a net treated-state addition
relative to the full legal ITT: requiring Handle data removes Florida.

## Usable candidates in the balanced CS/SA sample

All six states below have complete eviction outcomes for all 33 post-COVID
months.

| Rank | State | Online legal | April 2022 share of peak | 25% date | 50% date | Sustained 50% date | 75% date | Post-COVID pre-threshold outcome months | Feasibility |
|---:|---|---|---:|---|---|---|---|---|---|
| 1 | Arkansas | 2022-03 | 13.0% | 2022-09 | 2023-03 | 2023-09 | 2023-11 | 5 / 11 / 17 / 19 | **B: useful sensitivity** |
| 2 | Connecticut | 2021-10 | 47.8% | 2021-11 | 2021-11 | 2021-11 | 2023-10 | 0 / 0 / 0 / 18 | **D: 75%-only artifact** |
| 3 | Tennessee | 2020-11 | 49.3% | 2020-12 | 2021-10 | 2021-10 | 2023-11 | 0 / 0 / 0 / 19 | **D: already mature** |
| 4 | Virginia | 2021-01 | 52.5% | 2021-02 | 2021-10 | 2021-10 | 2023-10 | 0 / 0 / 0 / 18 | **D: already mature** |
| 5 | Louisiana | 2022-01 | 50.4% | 2022-02 | 2022-02 | 2022-02 | 2023-11 | 0 / 0 / 0 / 19 | **D: immediate ramp** |
| 6 | New York | 2022-01 | 60.0% | 2022-01 | 2022-01 | 2022-01 | 2023-01 | 0 / 0 / 0 / 9 | **D: immediate ramp** |

The four numbers in “pre-threshold outcome months” correspond to the 25%, 50%,
sustained-50%, and 75% definitions. A zero means the threshold was reached
before the post-COVID sample began.

Arkansas's legal-to-threshold lags are 6 months (25%), 12 months (50%), 18
months (sustained 50%), and 20 months (75%). The one-month 50% crossing is not
just a single seasonal spike: the three-month persistence date is six months
later, in September 2023. This provides a meaningful robustness range, but it
also shows that the exact activity date is definition-sensitive.

## Candidates unavailable in the eviction panel

- **District of Columbia:** Legally online May 2020; 26.9% of peak in April
  2022; first 50% in May 2024; sustained 50% in August 2024. This is a plausible
  delayed-ramp pattern, but DC has no observations in the state eviction panel.
- **Oregon:** Legally online October 2019; 47.6% of peak in April 2022; first and
  sustained 50% in October 2022. Oregon has no observations in the state
  eviction panel and is not a COVID-era legalization under either definition.
- **Wyoming:** Legally online September 2021; 39.6% of peak in April 2022;
  sustained 50% in September 2022. Wyoming has no observations in the state
  eviction panel.
- **Illinois:** Its 75% date is October 2023, but it was already at 54.8% of
  peak in April 2022 and has no observations in the state eviction panel.

These states cannot be added to the current estimators without acquiring a new
eviction outcome source and rebuilding the analysis panel.

## North Carolina coverage

North Carolina legalized online in March 2024 and immediately crossed the 25%,
50%, and 75% thresholds. It does not identify a treatment effect in the current
panel: its eviction series contains 15 post-COVID observations, April 2022–June
2023, and **zero observations after its March 2024 treatment**. It is therefore
correctly absent from the balanced estimator sample.

## Cohort and event-time consequences

On the 28-state common Handle-measurement sample, strict online legalization
contains 7 treated states in 6 exact-month cohorts. The full legal-date ITT
sample can retain balanced Florida and contains 8 treated states in 7 cohorts.
Applying a coherent activity threshold to every Handle-measured state gives:

| Treatment definition | Treated states | Cohorts | Singleton cohorts | Largest cohort |
|---|---:|---:|---:|---:|
| 25% of peak | 8 | 6 | 4 | 2 |
| 50% of peak | 8 | 7 | 6 | 2 |
| Sustained 50% | 8 | 8 | 8 | 1 |
| 75% of peak | 13 | 8 | 5 | 3 |

Thus, Arkansas at 25% joins Kansas's September 2022 cohort and modestly reduces
the singleton problem within the common Handle sample. It does not increase
treated-state N relative to the full legal ITT; it effectively replaces
Florida, which lacks Handle data. Arkansas at 50% creates a new March 2023 cohort. The
sustained-50% definition produces eight singleton cohorts—worse for cohort
support despite adding one treated state.

At event month +24, the numbers of supporting treated states are 3 (25%), 2
(50%), 2 (sustained 50%), and 1 (75%). The 75% rule expands near-treatment
support but worsens the long-horizon tail because most treatment dates move
late into 2023 or 2024. None of the definitions resolves the weak long-horizon
support that is most problematic for CS and SA inference.

## COVID-window sensitivity

Thresholds were recomputed twice:

1. Project-default peak exclusion: March 2020–July 2021.
2. Broad peak exclusion: March 2020–March 2022.

The candidate states and every candidate threshold date are identical across
the two definitions. West Virginia is the only profiled online state whose peak
or threshold date changes; it crossed all relevant thresholds before April
2022 and is not a candidate. The Arkansas conclusion is therefore not driven by
the choice between the narrow and broad COVID windows.

## Identification cautions

Handle is a post-legalization outcome, not an externally assigned policy date.
Redating treatment to a Handle crossing changes the estimand from the effect of
legal access to the effect of reaching a chosen market scale. It also requires
the strong assumption that sub-threshold betting has no effect. Arkansas had
positive legal Handle beginning in March 2022, so its April–August 2022 months
are not literally untreated.

First-crossing treatment is made absorbing for CS/SA even if monthly Handle
later falls. The sustained rule reduces sensitivity to one-month spikes, but it
does not eliminate endogenous timing or restore the legal-policy interpretation.
For that reason:

- Use Arkansas under 25%, 50%, and sustained-50% dates only as a labeled,
  exploratory market-maturation sensitivity analysis with a different estimand.
- Do not add the five 75%-only states as untreated until 2023.
- Do not use this exercise to claim that the small-cohort problem is solved.
- Retain online legalization as the primary intent-to-treat date.

## Source-backed artifacts

- `output/postcovid_ramp_candidates/candidate_state_profile.csv` and `.rds`
- `output/postcovid_ramp_candidates/all_preperiod_online_state_profile.csv` and
  `.rds`
- `output/postcovid_ramp_candidates/pure_activity_design_summary.csv` and `.rds`
- `output/postcovid_ramp_candidates/pure_activity_event_time_support.csv` and
  `.rds`
- `output/postcovid_ramp_candidates/pure_activity_design_treatment_dates.csv`
  and `.rds`

The source files are the updated LSR Handle series, updated legalization
schedule, estimator-ready Handle classification/panel, and raw state-month
eviction panel. No production panel or estimator script was modified.
