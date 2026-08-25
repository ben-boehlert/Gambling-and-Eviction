# Updated legalization and Handle cohort-support diagnostic

## Pre-Code Report

**Strategy memo:** `docs/literature_review_2026-07_estimation_strategy.md` (estimation-strategy reassessment; no separate approved strategist memo/critic score found)
**Domain profile:** loaded from `.claude/references/domain-profile.md`
**Language:** R (from `AGENTS.md`)
**Paper type:** reduced-form

**Identification strategy:** Staggered state-level DiD of sports-gambling access on eviction outcomes; this script diagnoses support for CS group-time ATTs and Sun-Abraham relative-time coefficients without fitting outcome models.

**Key variables:**
- Outcome: $Y_{st}$ eviction filings per 1,000 renters -> `filings_per_1k_renters` (panel skeleton only)
- Treatment: $G_s$ -> `cohort_month`, under updated online, first, retail, and Handle-50 definitions
- Event time: $e=t-G_s$ -> `event_time`
- Controls: eligible never-treated and not-yet-treated states; Handle support excludes states with missing exposure or pre-sample treatment
- Fixed effects: none estimated; target estimators use state and calendar-period effects
- Clustering: state

**Data source:** the state eviction panel, updated legalization schedule, updated LSR Handle-50 treatment panel, and explicit Handle state classification.
**Estimator:** Callaway-Sant'Anna and Sun-Abraham support only; no point estimates, standard errors, p-values, or significance levels are produced.
**Robustness checks:** all 39 observed states for legal-date definitions; classification-eligible Handle subsets; current balanced and legacy samples; monthly versus annual cohorts; never-treated versus not-yet-treated controls; relative-time support.
**Naming map confirms:** yes.

Proceeding to implementation.

The project references were loaded from `.claude/references/`; the `.Codex/references/` paths named in the generic coder instructions were not present.

## Bottom line

The updated dates do **not solve the small-cohort problem**. They make the current monthly design more fragmented: the current exact sample has 17 online-treated states spread over 16 monthly cohorts; 15 cohorts are singletons and 100.0% of treated states belong to cohorts smaller than five.
Across all 39 states appearing in the 2016-2024 panel, the updated online definition yields 23 treated states in 21 monthly cohorts. After excluding Florida (online-treated but missing Handle) and Nevada (pre-sample treated), the 37-state Handle-eligible sample yields 22 treated states in 18 cohorts and 15 eligible controls. CS/SA support uses each state's actually observed months because this panel is unbalanced.
Moving treatment from legal access to 50% of the frozen non-COVID peak Handle only modestly pools states. In the Handle-eligible subset of the current balanced base sample (25 states), it produces 16 treated states in 13 monthly cohorts, with 11 singleton cohorts and 100.0% of treated states in groups smaller than five.
Annualizing treatment timing helps mechanically, although these comparison rows use 26 states for online dates and 25 Handle-eligible states. Online dates collapse to 7 annual cohorts (largest cohort 4), while Handle-50 dates collapse to 5 annual cohorts (largest cohort 4). But 100.0% of online-treated states and 100.0% of Handle-50-treated states still lie in annual cohorts smaller than five.

## What changed relative to the prior design

On the legacy 24-state sample, the embedded schedule had 15 treated states, 9 never-treated controls, and 14 monthly cohorts. The updated online schedule has 16 treated states, 8 never-treated controls, and 15 cohorts. Newly treated states are: FL, KY, VT; states removed from treatment because they are retail-only are: MT, ND.
The current default exact sample adds repaired Maine and Idaho, yielding 26 states: 17 treated and 9 never treated. This adds clusters, but not a large repeated cohort: the largest monthly online cohort has only 2 states.
The current 50%-Handle build changes 3 dates/statuses relative to the immediately prior build: DE (2018-09 -> 2024-01); MT (2020-12 -> never); WV (2020-01 -> 2020-08).
Among the 16 current-sample states with both dates, 50% of peak is reached a median 1.0 months after online launch (range 0 to 24). The reshuffling reduces the number of monthly cohorts somewhat, but not enough to create any cohort of five states.
The estimator-ready Handle panel now excludes rather than recodes problematic states: FL (`legally_online_missing_handle`); NV (`pre_sample_treated`). Missouri remains an eligible control because its online start is after the 2024-12 study cutoff.

## Consequences for Callaway-Sant'Anna

With not-yet-treated controls, all mechanically defined post-treatment group-time cells retain at least one control in the balanced sample: 521/521 for updated online dates and 376/376 for Handle-50. Formal existence is therefore not the main problem.
The problem is weak cluster support inside the treated side of each ATT(g,t): 100.0% of online-date cells and 100.0% of Handle-50 cells inherit a treatment cohort smaller than five states. The same small state group is reused at every post-treatment t, so extra months do not create extra independent treated clusters.
The updated online design ends with only 9 not-yet/never-treated controls; Handle-50 ends with 9. Updated dates thus modestly shrink the late-period control reservoir while adding mostly singleton treated cohorts.

## Consequences for Sun-Abraham

Sun-Abraham aggregates cohort-by-relative-time interactions, but far leads and lags are supported by progressively fewer states. For online treatment, the first nonnegative monthly event time supported by fewer than five treated states is e=48; the last post-treatment e with at least five states is 47.
For Handle-50, the first post-treatment monthly e with fewer than five states is e=39; the last e with at least five states is 38. See `sa_focus_horizons.csv` for exact counts at commonly plotted horizons.
The interaction-weighted aggregation prevents forbidden comparisons, but it cannot manufacture independent clusters. Long-horizon coefficients remain high-leverage combinations of a few states, which is the project’s existing calibration concern for SA.

## Treatment-definition comparison (current exact base sample, monthly)

| Definition | Treated | Never | Cohorts | Singleton cohorts | Largest cohort | Treated states in cohorts <5 |
|---|---:|---:|---:|---:|---:|---:|
| Updated online | 17 | 9 | 16 | 15 | 2 | 100.0% |
| Updated first | 19 | 7 | 18 | 17 | 2 | 100.0% |
| Updated retail | 15 | 11 | 14 | 13 | 2 | 100.0% |
| Prior Handle-50 build | 17 | 9 | 14 | 12 | 3 | 100.0% |
| Updated Handle-50 | 16 | 9 | 13 | 11 | 3 | 100.0% |

## Interpretation and recommendation

- Keep CS and SA as heterogeneity-robust diagnostics/robustness estimators, but do not treat conventional clustered inference as automatically reliable in singleton and very small cohorts.
- Pre-specify a supported event window using `sa_event_time_support.csv`; bin or omit tails where fewer than five treated states contribute, and show the state count under every plotted coefficient.
- Annualizing reduces the number of cohorts, but it is a precision-versus-timing tradeoff and does not fully cure small groups. Do not annualize solely to obtain larger cohort labels without acknowledging loss of monthly treatment timing.
- The Handle-50 date is an intensity/maturation estimand, not a cleaner version of legalization. Its heterogeneous lag shifts composition across event time and is post-treatment by construction, so it is best framed as a complementary exposure definition rather than the primary legal-access treatment.
- Continue the project’s calibrated did2s headline and use state-level wild bootstrap/randomization inference where applicable. The support tables here explain why adding updated treatment dates does not overturn that estimator ordering.

## Reproducibility and artifacts

- Exact current sample: 26 states x 91 observed months = 2,366 observations.
- Estimator-ready Handle panel: 37 states, 3,884 observations; excluded states are exported in `handle_analysis_exclusions.csv`.
- Dates: 2016-01-01 through 2024-12-31; excluded 2020-03-01 through 2021-07-31.
- Every CSV has a same-named RDS, plus saved analysis panels, schedules, and a combined `all_support_diagnostics.rds`.
- No outcome model was fitted, so point estimates, standard errors, and significance levels are not applicable.

## Paper-to-Code Naming Map

| Paper notation | Code name | Description |
|---|---|---|
| $Y_{st}$ | `filings_per_1k_renters` | Eviction filings per 1,000 renters |
| $G_s$ | `cohort_value` / `cohort_label` | First-treated month or year |
| $e=t-G_s$ | `event_time` | Relative month or year |
| $ATT(g,t)$ | `cs_group_time_support` | CS group-time comparison cell |
| $\theta_e$ | `sa_event_time_support` | Sun-Abraham relative-time coefficient support |
