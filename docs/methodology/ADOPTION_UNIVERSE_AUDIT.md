# Adoption Universe Audit — the absent-row trap and the Nevada exception

**Date:** 2026-08-21
**Trigger:** a selection diagnostic joined state features to
`sports_gambling_legalization_dates.csv` with `inner_join` and silently lost 13
never-adopters.
**Canonical fix:** `utils/eviction_treatment_schedule.R` (bottom block) —
`EVICTION_STATE_UNIVERSE`, `PRE_PASPA_SPORTS_BETTING`,
`eviction_adoption_outcomes()`, `eviction_control_states()`,
`assert_no_pre_paspa_controls()`. The della copy is kept byte-identical.

Every claim below was checked by tracing the actual data path and, where it
mattered, by reconstructing the sample and printing the state list — not by
pattern-matching file names. That is the standing lesson from the 2026-08-10
"reproducibility anomaly" and the 2026-08-20 TWFE mislabelling.

---

## Defect 1 — the absent-row trap

`sports_gambling_legalization_dates.csv` has a row **only** for states that
legalized something. States that never legalized are **absent**, not present
with an NA date. The 13 with no row at all:

> AL AK CA GA HI ID MN NE NV OK SC TX UT

Wrong (deletes never-adopters, no warning):

```r
features %>% inner_join(schedule, by = "state_abb")
schedule  %>% pull(state_abb)          # this is NOT the state universe
```

Right (universe comes from the panel):

```r
never <- setdiff(panel_states, ever_online)
D     <- as.integer(state_abb %in% ever_online)
load_eviction_treatment_schedule(..., states = panel$state_abb)   # left join
```

### Scan result

81 first-party scripts reference the schedule. **The trap is essentially not
present in the committed pipeline.** The prevailing idiom is
`setdiff(panel_states, ever_*)` or `%in% ever_*`, both of which are correct,
and `R/power/load_blinded_panel.R:262-264` documents the hazard explicitly and
derives never-treated from the panel.

| Script | Verdict |
|---|---|
| `analysis/diagnostics/adoption_selection_levels_slopes.R` | **WAS AFFECTED — fixed 2026-08-21.** Substrate A 29 → 41 states |
| `analysis/cheap_sims/11_exposure_time_vs_intensity.R` | Not affected. `inner_join` is intentional — a handle-intensity analysis defined on legalizing states only |
| `analysis/cheap_sims/00_common.R` | Not affected — safe idiom present |
| all other schedule-referencing scripts | Not affected |

---

## Defect 2 — Nevada is not a never-adopter

Nevada has had legal sports betting continuously since 1949. It is absent from
the schedule *because there was no post-PASPA legalization event to record* —
not because it never adopted. Treating "absent from the schedule" as "never
treated" therefore places an **always-treated** state in the control pool.

Delaware, Oregon and Montana all carry explicit post-2018 dates in the
schedule, so they are handled by the ordinary path and are **not** part of this
exception. Nevada is the only member of `PRE_PASPA_SPORTS_BETTING`.

### Where Nevada actually lands

Nevada is absent from the ETS county download entirely, present in the state
panel (46 months outside COVID), and present in the annual court panel.

| Analysis family | NV in the sample? | Evidence |
|---|---|---|
| Balanced-panel pretrends, CS/SunAb calibration | **NO — immune** | NV has 46 non-COVID months vs the 91-month balance threshold; it drops before estimation |
| All county-download work (county calibration, border diagnostic, +9.1% did2s headline, county blinded-power cells) | **NO — immune** | NV is not in `monthly_county_data_download.csv` at all |
| `longdiff_era_variance.R` | **YES — affected** | NV is in the `never_any` set and is the flagged `outlier_state` in post-era placements (`output/longdiff_era_variance/placements.csv`) |
| `longdiff_2x2_pseudo_power.R`, `longdiff_2x2_selection_placebo.R` | **YES — affected** | Reconstructed 2x2 window: 37 states, 17 never, and NV is one of them |
| State-level blinded-power cells | **YES — affected** | `attr(panel, "never_treated")` at `level="state"` contains NV; county does not |
| `longdiff_real_calendar_decomp.R` | **NO — immune** | Runs on the ETS county file; never-online set is AK GA MN MT OK TX UT |
| `analysis/cheap_sims/11_exposure_time_vs_intensity.R` | Already excluded NV — but **ad hoc**, via an inline `state_abb != "NV"`. Should be migrated to the shared constant |

---

## Superseded until re-run

Treat these as **provisional, do not cite**, pending a re-run against the
corrected universe:

1. **2x2 long-difference pseudo-power** — `MDE-80 = 0.241 log points (+27%)`,
   the RI/CRVE/WCB size table, and the Type-M numbers
   (`output/longdiff_2x2_pseudo/`). NV is in the 17-state control pool.
2. **2x2 selection placebo** — `tau = -1.4%, RI p = 0.90`. Same control pool.
   Note this test asks whether eventual legalizers differ from never-legalizers,
   so an always-treated state in the "never" arm goes to the heart of it.
3. **Era-variance ratios** — median post/pre `sigma` ratio 2.67 and especially
   the strict-never-set 3.86 (`output/longdiff_era_variance/`). NV is both a
   member and the flagged outlier of the small strict set, so the strict-set
   number is the most exposed figure in the file.
4. **State-level blinded-power cells** — already flagged as double-count
   contaminated; this is a second, independent reason. County cells are immune.
5. **Anything previously derived from `adoption_selection_levels_slopes.R`
   before 2026-08-21** — superseded by the re-run already in
   `output/adoption_selection/`.

**Explicitly NOT superseded by this defect:** the pretrends headline, the
CS/SunAb/did2s calibration tables, the county CS adaptive-MDE verdict, the
border diagnostic, the +9.1% did2s headline, the TWFE staggered power sim, and
mortgage delinquency. Each was checked above and is immune for a stated reason.

---

## How to write this correctly from now on

```r
source("utils/eviction_treatment_schedule.R")

# full 51-state outcome table; never silently drops a never-adopter
out <- eviction_adoption_outcomes("data/raw/sports_gambling_legalization_dates.csv",
                                  treat_date_col = "online_start_date")

# controls for a panel, with pre-PASPA states removed and a warning emitted
ctl <- eviction_control_states(panel$state_abb,
                               "data/raw/sports_gambling_legalization_dates.csv")

# belt and braces before estimating
assert_no_pre_paspa_controls(ctl, context = "my analysis control pool")
```

`eviction_adoption_outcomes()` returns one row per state in
`EVICTION_STATE_UNIVERSE` and carries `pre_paspa_legal` and `control_eligible`
so the Nevada decision is explicit in the data rather than re-litigated in each
script.

---

# ADDENDUM 2026-08-21 — full NV footprint sweep

Scan of 102 output CSVs carrying a state-like column, plus every data substrate.
This extends the original table; two estimation samples were **missed** first time.

## The mechanism I got wrong initially

`monthly_county_data_download.csv` has no NV (state FIPS 32 absent) — that part
was right, and it is why all county work is immune. But `combined_monthly_panel.csv`
carries a **state-level** Nevada series of 71 months as
`geo_level=state, geo_id=nevada, geo_name=nevada` — **lowercase, and with no
fips**. A fips-based or case-sensitive check misses it. `build_state_panel()`
falls back to `geo_level == "state"` rows for states absent from the county file,
and NV is absent from the county file, so NV enters by exactly that fallback.
(Beware also `fips 05099` = **Nevada County, Arkansas**, a false positive.)

## NV-FREE — verified, with the reason

| Work | Why immune |
|---|---|
| All county-download work: county calibration (did2s 4%/0.97), border diagnostic, +9.1% did2s headline, county blinded-power cells, county CS adaptive MDE, `longdiff_real_calendar_decomp` | NV absent from `monthly_county_data_download.csv` entirely |
| Balanced state pretrends headline; state CS/SunAb calibration | NV has 46 non-COVID months against a 91-month balance threshold — drops before estimation |

## NV IN THE ESTIMATION SAMPLE

| Work | NV's role | Status |
|---|---|---|
| **TWFE staggered power sim** (`data/output/twfe_power_out_*`) — the MDE = 5% claim | one of the **16 never-treated** in the 38-state panel (`g=0, ever_treated=FALSE`) | **NEWLY FOUND — not in the original audit** |
| **Mortgage delinquency pretrends** (51 states) | one of the 27 never-treated; full coverage so no balance rule removes it | **NEWLY FOUND** |
| `output/state_influence_loo_postcovid` | untreated unit in a 27-state sample | affected; influence measured — see below |
| `output/pretrends_annual_statepanel_experiment` | 10 rows of a 48-state annual panel | affected |
| 2x2 pseudo-power, 2x2 selection placebo, era variance, state blinded-power | control pool | re-run 2026-08-21 |

## NV present and CORRECT — do not "fix"

`output/market_maturation`, `output/handle_cohort_support`,
`output/postcovid_handle_ramp_support`. NV is a genuine sports-betting market and
belongs in descriptive gambling-market statistics. One judgement call to flag
rather than a bug: NV is a market mature since 1949, so including it in
"months to reach a quintile of peak handle" mixes a mature market into a
new-market maturation statistic.

## How much does it actually matter? Measured, not assumed

| Analysis | Effect of removing NV |
|---|---|
| Era variance | **large** — median ratio 2.67 -> 2.04; strict set 3.86 -> 2.73 (NV was the flagged outlier) |
| State blinded-power D1 | **fatal** — design becomes infeasible, 3,600/3,600 rep failures |
| `state_influence_loo_postcovid` (direct LOO read) | **small** — TWFE ATT 0.51%, Sun-Abraham 3.81% |
| 2x2 pseudo-power MDE-80 | **negligible** — 0.241 -> 0.2401 |
| 2x2 selection placebo | small, in the reassuring direction — tau -1.4% -> -0.30% |

Rule of thumb the numbers support: NV matters where the control pool is thin or
where NV is an outlier on the outcome, and is nearly inert where it is one control
among many.
