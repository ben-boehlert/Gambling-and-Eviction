# WA and MI added to the state panel; five trailing partial months censored (2026-09-14)

**Panel: 40 → 42 states** (+113 WA rows, +68 MI rows, −4 trailing partials). A concurrent session
replaced Idaho's Twin Falls LSC basket with a statewide 44-county series the same afternoon
(`data_prep/add_id_to_state_panel.R`) and re-ran `rebuild_state_month_panel.R`, so absolute row
totals moved after this work landed — read them off the file, not off this memo. **That re-run also
restored CT 2016-01 / 2016-02, undoing `censor_series_start_ramps.R`; re-apply it before any run.**
Vintage boundary
`state_month_panel_with_treatment_pre_wa_mi_2026-09-14.csv`.

Scripts: `data_prep/add_wa_to_state_panel.R`, `data_prep/add_mi_to_state_panel.R`,
`data_prep/censor_trailing_partial_months.R`, then `data_prep/fetch_acs_renter_denominators.R`
(extended) and `data_prep/make_data_currency_doc.R`.

---

## 1. What was added, and what it is actually worth

Both states were already in the repo and unused — WA inside the Eviction Lab internal extract
`ets_county_month.csv`, which `rebuild_single_series_from_ets_internal.R` filters to six states;
MI inside `data/raw/michigan/mi_lt_statewide_month_year.csv`, parsed 2026-09-03 from the Judicial
Data Warehouse PDF. Neither appears in LSC CCDI, so **neither can enter the county arm** — both are
state-arm-only.

Roles under the clean-anchor rule (6-month pre-launch baseline, outcomes 12–24 months post,
COVID 2020-03..2021-07 dropped):

| State | Treat def | Baseline | Outcomes | Role |
|---|---|---|---|---|
| **WA** | online (headline) | — | — | **never-treated control, 113 clean contiguous months** |
| WA | first_start 2021-09 | 1 of 1 eligible | 13 of 13 | thin-baseline switcher |
| **MI** | shift12 2022-01 (headline) | 5 of 5 eligible | **2 of 13** | baseline only |
| MI | online 2021-01 | **0 of 0 eligible** — all six fall inside the COVID drop | 13 of 13 | outcomes without a baseline |
| **MI** | first_start 2020-03 (retail) | 6 of 6 | 8 of 8 | **full clean switcher** |

`docs/DATA_CURRENCY.md` reaches the same verdict independently: WA `control (no online date)`,
MI `not a switcher`.

**Read this honestly.** WA is an unambiguous gain — a clean 113-month never-treated control
cluster. **MI is not a clean-anchor switcher under either headline definition.** Its online launch
(2021-01) sits inside the COVID drop window, which erases its whole baseline; its shift12 date
(2022-01) has a clean baseline but its 12–24-month outcome window lands in MI's gap field. MI is a
full clean switcher only on the retail `first_start` date. The headline switcher count does not
change. MI was added because it is a real cluster with 68 real months, not because it strengthens
the headline cell.

Arm accounting, refreshed by `analysis/diagnostics/county_vs_state_arm_coverage.R`
(covid = drop): **state 35 states / county 26** — up from 32/26 before the 2026-09-14 additions
(OR, WA, MI). The county arm buys 1,180 units against the state arm's 35, but clusters bind, not
observations. Cite only the `states`/`units` columns of
`data/processed/county_vs_state_arm_summary.csv`: its `switchers` column is 0 in every row, an
artifact of the blinded loader truncating each state before treatment.

## 2. WA — scope, and what it does to the control pool

Single site `TACOMA` = **Pierce County (53053)**. 114 months 2017-01..2026-06 in the extract,
**113 after the trailing partial is dropped**, zero interior gaps. `n_counties = 1`,
`basket_share = 1` — the LA / MA / NV single-jurisdiction convention. **WA levels are not
statewide**; the denominator is Pierce County renters (124k), not Washington's.

`treat_start` is NA because WA has no `online_start_date` — retail-only, Sep 2021. The pre-flight
audit therefore flags WA under **§7 control-pool states with legal retail sports betting**, joining
MT, ND, NM and WI. That flag is not new and not a defect of this addition, but it is now five
states: if retail exposure contaminates the never-treated pool, WA enlarges the problem as well as
the pool. Any spec that purges retail-legal controls loses WA.

**Series-start ramp: not censored.** 2017-01 runs 0.69 of its own-month norm and 2017-02 runs 0.76
— far milder than the CT (0.15 / 0.19) and NH (0.20) months `censor_series_start_ramps.R` removed,
and comparable to WI's 0.56, which that script deliberately left in. The audit's §7b does not flag
it. Recorded here so the next ramp audit does not relitigate it.

## 3. MI — footprint, gaps, denominator

Statewide monthly LT new filings, **minus six jurisdictions the JDW report excludes**: Berrien
County, Grand Rapids, Dearborn Heights, Center Line & Warren, Northern Macomb County, Grandville
& Walker. The report publishes no county values, so the missing footprint cannot be reconstructed —
`n_counties` and `basket_share` are NA, the MD / NH / WI / OR convention.

**Footprint measured, not assumed.** 2019 is the only year both MI products are complete: JDW
monthly sums to **181,440** against the county dashboard's 81-county sum of **193,007** →
**0.940 coverage**. `add_mi_to_state_panel.R` asserts this ratio stays in [0.90, 0.98]. Consequence:
the statewide ACS denominator **understates MI's rate by about 6%**. State fixed effects absorb a
constant, so this does not bias within-MI variation — but **MI levels are not comparable** to other
states', and the 11.7 filings per 1k renters in `DATA_CURRENCY.md` is a floor.

**68 of 89 months.** The other 21 are `unlabelled_in_source` — Power BI omitted the bar label, so no
value exists. They are **omitted rows, never zero-filled and never interpolated**: the panel forbids
NA `filings_count`. The series is complete 2019-01 → 2023-01; every gap falls in 2023-02 or later,
longest run 8 months (2023-06..2024-01). **CS-DiD consecutive-indexes months and will not accept the
gapped span**; LP-DiD tolerates it with a gap tolerance. Three of the 68 values are
`derived_from_annual_total` (Jan 2020, Sep 2021, Jan 2026) — exact arithmetic from the published
annual total, not estimates.

## 4. Trailing partial months — a defect found in the LIVE panel, now fixed

The Eviction Lab extract cuts each site at its own collection date, so the final month of each
extract-sourced series is partial. The 2026-09-14 single-series rebuild carried those months
straight into the panel and nothing flagged them: `DATA_CURRENCY.md`'s "partial *n*/13" column is
about outcome-window coverage, not about partial months, and the pre-flight audit's level-break
check is the only thing that would have caught them.

Final month over the median of the preceding six:

| State | Month | Value | Prior-6 median | Ratio |
|---|---|---:|---:|---:|
| NM | 2026-06 | 154 | 967.5 | **0.16** |
| MO | 2026-06 | 363 | 1,376.0 | **0.26** |
| LA | 2026-03 | 119 | 389.5 | **0.31** |
| WA | 2026-06 | 125 | 328.0 | **0.38** |
| MA | 2026-06 | 346 | 651.0 | **0.53** |

All five dropped. NV (1.11) and RI (0.90) end a month earlier and are clean. WA's was dropped
upstream in `add_wa_to_state_panel.R`; the other four by `censor_trailing_partial_months.R`, which
asserts each censored month really is that state's last and really is below 0.75 of its prior-6
median before removing anything.

**Verified effect.** Non-COVID level breaks (|Δlog| > 0.75) lost exactly the three the partials
caused — LA 2026-03 (−1.361), MO 2026-06 (−1.389), NM 2026-06 (−1.816). MA's −0.63 sat under the
threshold and had been passing silently. Every level break the addition introduced (7: five MI, two
WA) falls inside the COVID drop window and is the 2020 moratorium collapse, which the loader drops.

**Re-check after every extract refresh** — this is a property of how the extract is cut, not a
one-time error.

## 5. Denominators

`data_prep/fetch_acs_renter_denominators.R` was extended additively to cover the two new tags. It
now fills 8 states, at the geography the numerator actually covers: WA → Pierce County alone; MI →
all 83 MI counties (statewide). The union of ACS years is unchanged (2015–2024 available; 2025/2026
404 and fall back to 2024), so **the six original states pull exactly the same vintages they did
before**. Verified: diffing the new panel against the preserved vintage shows the six changed in
nothing but their four dropped final months and float round-tripping at 2e-16 relative.

## 6. Run hygiene

Scenario ids hash settings, not data. This is a **new vintage boundary**: every power and pretrends
run after it needs a fresh `run_name` (token `p39` → `p42`), and no result from before it may be
paired with one after. Nothing was re-run in this pass — panel construction only, no estimates, no
outcomes inspected.
