# Updated handle timing and staggered-DiD cohort support

**Audit date:** 2026-08-14  
**Scope:** Descriptive support audit only; no models were estimated.

## Bottom line

Using the first month in which a state reaches 50% of its fixed, pre-2025 peak
Handle modestly consolidates the full-sample monthly cohorts, but it does **not**
solve the small-cohort problem for Callaway-Sant'Anna (CS) or Sun-Abraham (SA).
In the balanced 26-state no-COVID sample, online legalization gives 17 treated
states in 16 cohorts; the 50%-Handle rule gives 16 treated states in 13 cohorts.
The improvement comes almost entirely from one three-state cohort
(AZ/TN/VA, October 2021) and one two-state cohort (DE/VT, January 2024).
Thirteen of the 16 Handle-treated states (81%) remain in cohorts of at most two
states.

In the intended post-COVID analysis (April 2022--December 2024), the result is
even clearer: online dates and 50%-Handle dates each produce eight treated
states in seven cohorts, consisting of six singleton cohorts and one doubleton.
Handle timing changes *which* singleton state/date appears, not the fundamental
treated-cluster support.

## Data and grain

- LSR Handle file: 2,270 state-month rows, 35 states, June 2018--May 2026.
- Legalization schedule: 38 states; 31 have an online date, 32 a retail date,
  and all 38 a first-start date.
- Raw eviction panel: 4,120 state-month rows, 39 states, January 2012--November
  2025, unbalanced.
- Default balanced no-COVID estimator sample: **26 states x 91 observed months**
  (January 2016--December 2024 excluding March 2020--July 2021), 2,366 rows.
  Results for this sample must not be described as applying to all 39 panel
  states.
- Intended post-COVID sample: 30 states x 33 months, 990 rows.
- The current activity-date file contains 29 states globally, 22 of the 39 raw
  panel states, and 16 of the 26 balanced no-COVID states.

The 50%-Handle date is calculated from **total reported Handle**, not a
retail/online channel split, but only observations at or after the state's
online start enter the calculation. Peaks are capped at December 2024 and
exclude March 2020--July 2021; the threshold search itself can retain crossings
during that excluded COVID interval.

## Exact monthly cohort sizes

The table treats a cohort as states sharing the exact first-treatment month.
“Small states” is the number of treated states in cohorts of size one or two.

| Sample / timing definition | Treated states in window | Cohorts | Singleton cohorts | Doubleton cohorts | Cohorts of 3+ | Small states |
|---|---:|---:|---:|---:|---:|---:|
| All 39 panel states, online | 23 | 21 | 19 | 2 | 0 | 23 |
| All 39 panel states, retail | 24 | 19 | 14 | 5 | 0 | 24 |
| All 39 panel states, first | 28 | 23 | 18 | 5 | 0 | 28 |
| All 39 panel states, 50%-Handle | 22 | 18 | 15 | 2 | 1 | 19 |
| Balanced 26, online | 17 | 16 | 15 | 1 | 0 | 17 |
| Balanced 26, retail | 15 | 14 | 13 | 1 | 0 | 15 |
| Balanced 26, first | 19 | 18 | 17 | 1 | 0 | 19 |
| Balanced 26, 50%-Handle | 16 | 13 | 11 | 1 | 1 | 13 |
| Post-COVID 30, online | 8 | 7 | 6 | 1 | 0 | 8 |
| Post-COVID 30, 50%-Handle | 8 | 7 | 6 | 1 | 0 | 8 |

For the balanced 26-state sample, the online-date doubleton is DE/VT in
January 2024. Under 50%-Handle timing, DE/VT remain a January 2024 doubleton and
AZ/TN/VA form the only cohort larger than two, in October 2021. Every other
Handle cohort is a singleton.

Relative to the preserved pre-update activity file, the revised construction
improves post-COVID support only slightly: the old post-COVID roster had seven
treated states in seven singleton cohorts; moving Delaware from an invalid
retail-era September 2018 threshold to January 2024 creates the DE/VT
doubleton, yielding eight states in seven cohorts. The fix is substantively
correct, but not large enough to change the small-cohort diagnosis.

## Post-COVID event-time support

Counts below include only cohorts treated within April 2022--December 2024 and
whose calendar month at the stated event time is observed.

| Event time | Online: states / cohorts | 50%-Handle: states / cohorts |
|---:|---:|---:|
| -12 | 5 / 4 | 4 / 3 |
| -6 | 7 / 6 | 7 / 6 |
| -1 | 8 / 7 | 8 / 7 |
| 0 | 8 / 7 | 8 / 7 |
| +6 | 8 / 7 | 8 / 7 |
| +12 | 6 / 6 | 6 / 6 |
| +18 | 3 / 3 | 4 / 4 |
| +24 | 2 / 2 | 2 / 2 |

Thus Handle timing adds one state/cohort at +18 but loses one at -12. It does
not prevent the long-horizon SA aggregation from collapsing to two treated
states/cohorts by +24. For CS, not-yet-treated plus never-treated comparison
counts remain much larger (12--19 under the Handle schedule), but the treated
side of each ATT(g,t) is usually one state. More controls cannot substitute for
additional independently treated state clusters.

The deleted COVID interval adds another complication in the full no-COVID
sample. Two online treatment months (TN November 2020; VA January 2021) are not
observed, versus three 50%-Handle treatment months (WV August 2020, PA October
2020, IN December 2020). The Handle rule therefore consolidates later states
but places more adoption dates inside the panel's common time gap, weakening
near-treatment event-time support for a single full-period analysis.

## Integrity and definition findings

### High: the post-COVID runner currently ignores the Handle treatment dates

`scripts/run_pretrends_pre_post_covid.sh` supplies the rebuilt Handle panel but
does not set `TREAT_SOURCE=panel`. `scripts/run_pretrends_statepanel.sh`
defaults to `TREAT_SOURCE=file` and `TREAT_DATE_COL=online_start_date`, and the
template deliberately gives that file schedule priority over embedded panel
dates. Consequently, under defaults the purported post-COVID Handle run still
estimates cohorts defined by online legalization. This means the Handle update
currently does nothing to the CS/SA run unless treatment source is explicitly
changed. Confidence: high, from direct code-path inspection.

### High: absence of Handle is not equivalent to never treated

Florida is legally online from December 2023 in the schedule but has no rows in
the LSR Handle file. A pure Handle-threshold left join therefore assigns Florida
`treat_start = NA`, making it a “never-treated” control after legal treatment.
In the 30-state post-COVID sample, Florida is the only 2022--2024 online adopter
with this failure. Nevada is also coded `NA` despite the builder documenting it
as a pre-PASPA market; it should not silently become a never-treated state in a
post-period online-access design. Confidence: high.

### Medium: source coverage mismatches require explicit classification

Across the source files, Nebraska and Nevada appear in Handle but not in the
legalization schedule; Florida, New Mexico, North Dakota, Washington, and
Wisconsin appear in the schedule but not in Handle. Nebraska is not in the
eviction panel, so its mismatch has no current estimator effect. Missouri has
a December 2025 online date and post-cutoff Handle observations, so it is
correctly absent from the pre-2025 activity-date file but is “not yet treated
in the study window,” not never treated in general.

### Medium: the fixed cutoff is necessary but defines the estimand

The December 2024 calibration cap prevents later LSR releases from moving old
treatment dates, which is appropriate for reproducibility. It also means the
50% threshold is 50% of each state's *peak observed by the study cutoff*, not
its eventual mature-market peak. This should be stated wherever the treatment
definition is used.

## Implication for CS and SA

- **CS:** Handle timing reduces 16 online cohorts to 13 in the balanced sample,
  but 11 of those 13 Handle cohorts remain singletons. ATT(g,t) estimates are
  still driven by one treated state in almost every group, so inference remains
  vulnerable to state-specific shocks and small-cluster calibration.
- **SA:** The underlying cohort-by-event-time interactions remain mostly
  state-specific. At longer horizons the contributing treated states fall from
  eight to two, so aggregation cannot create information absent from the
  cohort interactions.
- **Net:** The updated Handle data yields a small, real support improvement, not
  a remedy. Exact-month 50%-Handle timing should not be presented as solving the
  heterogeneity-robust estimator problem.

As a sensitivity description, calendar-year pooling would mechanically turn
the post-COVID exact-month cohorts into three groups of sizes 2, 4, and 2 under
either online or Handle timing. That improves cell counts but changes treatment
timing by up to months and therefore defines a different specification; it is
not a data correction.

## Minimum data/pipeline fixes before re-estimation

1. Make the post-COVID runner explicitly use the embedded Handle schedule (or
   fail if the requested and resolved schedules differ).
2. Do not translate “no Handle measurement” into “never treated.” Add an
   explicit missing-threshold status and either supply a documented fallback or
   exclude such states from that specification.
3. Exclude or explicitly classify pre-sample treated states such as Nevada so
   they cannot enter the never-treated control pool.
4. Save a cohort-support table with every CS/SA run: treatment definition,
   states per cohort, contributing states/cohorts by event time, and control
   counts at each adoption month.

## Source files inspected

- `data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv`
- `data/raw/sports_gambling_legalization_dates.csv`
- `data/raw/state_month_panel_with_treatment.csv`
- `data/processed/activity_treatment_dates.csv`
- `data/processed/state_month_panel_handle50_treatment.csv`
- `data/processed/deprecated/activity_treatment_dates_2026-08-14_prefix.csv`
- `data_prep/build_panel_handle50_treatment.R`
- `analysis/data_prep/create_activity_treatment_dates.R`
- `scripts/run_pretrends_pre_post_covid.sh`
- `scripts/run_pretrends_statepanel.sh`
- `analysis/pretrends/pretrends_statepanel_template.R`
