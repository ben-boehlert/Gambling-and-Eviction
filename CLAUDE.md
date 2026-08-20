# CLAUDE.md - Project Guide for Claude Code

## Project Overview

Research replication package analyzing the causal effect of sports gambling legalization on eviction rates using staggered difference-in-differences (DiD) methods. This is an economics/econometrics project written primarily in R.

## Terminology Note (Data Search)

When searching for or evaluating eviction data sources (state AOC/court dashboards, LSC filings, county court systems), **"landlord/tenant filings" and other near-synonyms (e.g., "landlord-tenant cases," "L&T," "forcible entry and detainer," "unlawful detainer," "summary process") are acceptable stand-ins for "eviction."** Many state court systems file evictions under these case-type labels rather than the word "eviction" itself. Do not discard a source or dashboard as irrelevant just because it doesn't use the literal word "eviction" — check whether the case type is a landlord/tenant or possession action first.

## Key Entry Points

- `README.md` — repo overview and structure
- `START_HERE.md` — navigation guide for the CS-DiD debugging work
- `QUICK_START.md` — one-page reference for outputs and plots
- `INSTALL_PACKAGES.R` — run first to install all R dependencies

## Repository Structure

```
analysis/           Main analysis scripts
  main/             Primary TWFE and CS-DiD power simulations
  pretrends/        Pre-trends diagnostics (Roth 2022, Rambachan & Roth 2023)
  diagnostics/      Debugging and diagnostic tools
  exploratory/      Exploratory analyses (dose-response, parallel trends)
  visualization/    Plotting scripts
data/
  raw/              Source CSVs (eviction data, gambling legalization dates)
  processed/        Cleaned panels
data_prep/          Data merging and preparation scripts
scripts/            Shell scripts for running analyses
patches/            Fixes for bugs in the `did` R package (CS-DiD)
plots/              Visualization utility scripts
utils/              Diagnostic and utility tools
docs/               Documentation and methodology write-ups
figures/            Generated plots (PNG, PDF)
output/             Analysis output (CSVs, plots, logs)
did/                Patched copy of the `did` R package (Callaway & Sant'Anna)
DRDID-master/       Patched copy of DRDID package (doubly-robust DiD)
fastglm-master/     Fast GLM package dependency
```

## Critical Files

- `power_simulation_cs.R` — core simulation engine; defines `cfg`, `load_panel()`, `make_treat_schedule()`, `build_untreated_sample()`, and other key functions. Sourced by many analysis and plot scripts.
- `analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R` — recommended TWFE-based power simulation (correct Type I error)
- `analysis/pretrends/pretrends_statepanel_template.R` — pre-trends diagnostics pipeline: CS-DiD (analytic + bootstrap) + Sun-Abraham event studies, optional gambling intensity heterogeneity, optional self-test calibration to detect inflated CS SEs. Configured via env vars; run via `scripts/run_pretrends_statepanel.sh`.
- `analysis/diagnostics/validate_csdid_dynamic_sim.R` — CS-DiD validation harness: simulates outcomes on the real design skeleton with known DGP, checks Type I error and SE calibration. Template for self-test pattern.
- `analysis/diagnostics/cs_calibration_multi_estimator.R` — **Multi-estimator calibration test** (2026-04-09). Tests TWFE, Sun-Abraham, CS, didimputation, and did2s on the balanced 24-state panel under the null. This is the definitive test showing all het.-robust estimators are 4-5x noisier than TWFE. Output: `data/output/cs_calibration_multi/`.
- `analysis/diagnostics/cs_calibration_test.R` — Earlier single-estimator calibration test (v3). Output: `data/output/cs_calibration_test/`. Superseded by multi-estimator version.
- `utils/eviction_treatment_schedule.R` — Shared utility for loading treatment schedule from `sports_gambling_legalization_dates.csv`. Handles state name → abbreviation mapping. Used by pretrends pipeline and calibration tests.
- `patches/att_gt_safe.R` — safe wrapper around CS-DiD that avoids segfaults on unbalanced panels
- `data/raw/monthly_county_data_download.csv` — primary county-level eviction data (2016-2025)
- `data/raw/sports_gambling_legalization_dates.csv` — treatment schedule (state legalization dates)
- `data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv` — monthly sports betting handle/revenue by state (June 2018–Sept 2025, starting when each state legalizes). Columns: `State` (full name), `month_date`, `Handle` (dollars wagered), `Revenue`, `Hold`, `Taxes`. NOT per-capita. 34 states; earliest: DE/NV/NJ in June 2018.
- `data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv` — state-month mortgage delinquency rates (% 90+ days late), wide format (2008-01 to 2025-03). All 50 states + DC. Source: mortgage performance data.

## Working Directory

All scripts assume the working directory is the **project root**. Paths like `source("power_simulation_cs.R")` and `read_csv("data/raw/...")` are relative to root.

## Data

- Panel data: county-month eviction filings (2016-2025) from the Eviction Tracking System
- State-month panel: `data/raw/state_month_panel_with_treatment.csv` — columns: `state_abb`, `month_date`, `filings_count`, `renter_occupied_housing_units`, `filings_per_1k_renters`, `treat_start`, `treated`
- Treatment: staggered sports gambling online legalization dates by state (`data/raw/sports_gambling_legalization_dates.csv`)
- Gambling amounts: `data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv` — monthly Handle/Revenue by state (June 2018+, starts per-state at legalization). Uses full state names (needs crosswalk to `state_abb` via `state_name_to_abb()`)
- Mortgage delinquency: `data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv` — wide format (states × months), % of mortgages 90+ days late
- `cfg$data_dir = "data/raw"` in `power_simulation_cs.R` controls where data files are loaded from
- `cfg$panel_choice = "counties"` is the default and recommended panel for power simulations

## Running the Analysis

```r
# Install dependencies
source("INSTALL_PACKAGES.R")

# Run TWFE power simulation (recommended)
source("analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R")

# Run CS-DiD power simulation (slower, uses bootstrap)
source("power_simulation_cs.R")

# Generate CS-DiD support diagnostics and plots
Rscript scripts/generate_support_plots.R

# Run pre-trends evaluation (legacy, CS section disabled)
source("analysis/pretrends/pretrends_modern.R")
```

```bash
# Run pre-trends diagnostics pipeline (CS-DiD + SunAb, recommended)
bash scripts/run_pretrends_statepanel.sh

# Run mortgage delinquency pretrends (alternative outcome)
bash scripts/run_pretrends_mortgage.sh

# With gambling intensity heterogeneity (see known issue below)
GAMBLING_FILE=data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv \
  bash scripts/run_pretrends_statepanel.sh

# With self-test calibration (detects inflated CS SEs; slow, ~30 min with 4 cores)
SELF_TEST=TRUE N_CORES=4 bash scripts/run_pretrends_statepanel.sh

# Validate CS-DiD SE calibration directly
Rscript analysis/diagnostics/validate_csdid_dynamic_sim.R
```

## Blinded Power-Simulation Framework (Pre-Analysis Plan)

Blinded (untreated-data-only) calibration + power simulation supporting the Arnold Ventures
pre-analysis plan. Code: `R/power/` (9 modules). Configs: `config/power_*.yml`. Methodology:
`docs/methodology/POWER_SIMULATION_{DESIGN,BLINDNESS_PROTOCOL,CODE_AUDIT}.md`. Cluster package:
`della_power_upload/`, rebuilt by `scripts/make_della_power_upload.sh`; runs on Princeton Della at
`/scratch/gpfs/DESMOND/ben/eviction_gambling/della_power_upload/` (see `scripts/della_power/README.txt`
for upload/run/monitor commands).

**Purpose in the PAP** (decided 2026-08-07/08-10): estimator and aggregation-level selection is
pre-registered as a *decision rule*, not a named estimator — (1) size gate: any estimator × level
cell whose δ=0 rejection is materially off nominal is disqualified; (2) MDE among survivors picks
the headline spec. This converts the post-hoc-looking did2s choice (CS/SunAb are miscalibrated on
this design; see calibration tables above) into a blinded, pre-committed selection. AV guidance
(`AV_Pre-Analysis_Plan_Guidance_202507.pdf`): QED checklist, ≤6 pages, MDEs in real-world terms.

**Run ladder** (validate cheap before spending on CS — `att_gt` is the cost driver, ~2,750 fits
per county scenario):

| Run | Config | Scenarios | Estimators | Cost | Status |
|-----|--------|-----------|-----------|------|--------|
| smoke | `power_smoke.yml` | 2 (county+state headline) | twfe, did2s; 50 reps × 4 δ | ~1h county, <1 min state | run 12220717, 2026-08-10 |
| cheap | `power_cheap.yml` | 8 (4 county, 4 state) | twfe, did2s; 500 reps × 11 δ | ~28–30h county tasks | ready |
| primary | `power_primary.yml` | 11 (S3 blocks infeasible → effectively 9) | + cs (250 reps) | 50–63h per county task | partial (see below) |
| sensitivity | `power_sensitivity.yml` | 26 (one axis at a time) | varies | state-level baseline | not started |

Key mechanics:
- `seed_rep = base_seed + 10007*rep + 101*scenario` with `base_seed = 20260723` shared across all
  configs → a later CS-only run sees the identical simulated panels rep-for-rep (paired comparisons
  across runs).
- Scenario ids are content hashes of the scenario's own settings → resubmitting skips completed
  partials; editing one config block never invalidates another's partial. Config edits that change
  the scenario COUNT require updating `--array` in the matching `run_*.slurm`.
- `est_anticipation` is a CS-only knob (`att_gt` argument; `R/power/run_estimators.R`) — pointless
  in CS-free runs.

**S3 × D1 infeasibility (diagnosed 2026-08-10).** D1 (cohort-preserving reassignment) places the
*full* real online template — 18 cohorts, ~24 treated states, 55-month span — but S3 (never-treated
sample) has only 12 (county) / 14 (state) states. Structurally infeasible; no `min_pre`/`min_post`
relaxation helps. The two S3 primary tasks fail in ~10 s at startup. Resolution: S3 dropped from D1
blocks (done in `power_cheap.yml`; pending in `power_primary.yml`); the never-treated comparison
belongs to design D4, which scales cohort counts proportionally (sensitivity `alt_designs`; consider
promoting a D4 block to primary). The PAP should report this infeasibility explicitly.

**First primary run (Della job 12114571, submitted 2026-08-08).** 4 state scenarios completed
(6–13h each); 2 S3 tasks failed instantly (above); 5 county tasks were **OOM-killed at ~42h**
(exit 0:125, `sacct` state OUT_OF_MEMORY — NOT walltime): the runner accumulates every batch in
RAM and writes the partial CSV only after all 20 batches, so CS's 13–19k-row batches climbed into
the 16G ceiling and **all work was lost** (no batch-level checkpointing; the per-batch log lines
are progress display only). Pacing facts: county twfe+did2s ≈ 1.5h per 25-rep batch (11 δ);
CS batches ≈ 4–5h; county+CS needs ~50–63h total. Before resubmitting the CS arm: add per-batch
checkpoint/resume (fixes both the OOM and the loss-on-death), raise `--time` to ~72h, and raise
`--mem`.

**2026-08-10 evening findings (smoke-ladder debugging — read before touching the framework):**
- **`fwildclusterboot` is ARCHIVED from CRAN.** Della's setup silently skipped it → every wild
  row of the first smoke run failed. Fixed: `setup.sh` now installs from the s3alfisc r-universe
  repo and hard-fails if absent.
- **boottest memory bomb, fixed.** `boottest()` without `fe = "id"` dummy-expands ~1,200 county
  FEs → ~1.8 GB peak per worker → 8×16G OOM in 2 min (job 12223288). `run_estimators.R` now
  passes `fe = "id"`: ~0.6 GB, 5× faster, identical p-value.
- **D1 on county/S2 is deterministically infeasible under the current code+data** (verified
  50/50 rep failures with the runner's exact seed path, reproduced identically on laptop and
  Della). The national 24-state template into the ~29-state county-S2 pool with per-state
  coverage windows does not place.
- **REPRODUCIBILITY "ANOMALY" — RESOLVED (2026-08-10 ~23:45).** The mid-day feasibility flip
  was caused by commit `2be0bd0` (16:16, a CONCURRENT session's deliberate data repair):
  `sports_gambling_legalization_dates.csv` had frozen ~early 2023 and was repaired to add
  online dates for DE, NC, KY, ME, FL, VT, MO (verified vs regulators/LSR). The online
  template grew ~24 → ~31 states, tipping national-D1 placement into infeasibility. Runs
  before the repair reached Della (old CSV) succeeded; runs after the 19:15 rsync failed; all
  local checks compared against a HEAD that had already moved. No nondeterminism ever existed.
  **Lesson: when deterministic code changes behavior, check `git log` (including concurrent
  sessions' commits) before anything else.** Pre-repair smoke partial (old schedule + harsher
  national template — the source of the spurious "did2s 31% Type I" reading) preserved at
  `output_blinded_power/smoke_prewildfix/` on Della; old CSV in `data/raw/deprecated/`.
- **Schedule repair ripple (IMPORTANT, beyond the sims):** ME, VT, KY, FL are **no longer
  never-treated controls** (online Nov 2023 / Jan 2024 / Sep 2023 / Dec 2023; MO Dec 2025 is
  post-panel). The pretrends headline results above ("26 states, 12 treated, 14 never-treated,
  ME included as control") predate the repair and are STALE — re-run the pretrends pipeline
  with the repaired schedule. FL's voided 2021 online launch (West Flagler) needs a PAP flag.
- **Panel-restricted template — IMPLEMENTED (2026-08-10 ~22:30), first results good.**
  `template: panel` config axis (D1 places treated-states-in-panel; 17 county cohort states
  under the repaired schedule); per-rep schedule infeasibility now yields failure rows instead
  of aborting the scenario. National-template ids unchanged (conditionally hashed). Smoke on
  the corrected design: **county did2s 4.1% Type I / SE-SD 0.96; county TWFE-wild 4.0%; state
  did2s 23-29% Type I (disqualified); TWFE analytic ~10% county (wild fixes it)**. Local Mac
  reproduces Della's analytic numbers bit-for-bit (wild differs 1-2 reps: bootstrap RNG layer;
  did2s convergence 48 vs 49/50: BLAS). Full 500-rep state cheap results (local): did2s
  disqualified; TWFE-wild calibrated but MDE > 20% under the count_nb DGP — far above the
  application's old "5% state MDE" claim; county (Della job 12248328, ~Tue) is the headline.
  Mac is ~6x faster per rep than a Della node — use local runs for smoke-scale work.

- Pre-COVID period (2016-2020) has better parallel trends than the full sample
- Idaho is excluded from annual analyses due to data quality issues
- Maine: was excluded for a late-2023 zero-fill data artifact; **repaired 2026-07-23** from the Maine Judicial Branch court source (`data_prep/monthly_panel_expansion/07_repair_me_from_court_source.R`, `08_repair_me_in_county_files.R`) and now included as a never-treated control
- **UPDATED 2026-05-21**: Main finding has been substantially revised after a session-long methodological diagnostic. See `output/border_diagnostic/HANDOFF.md` for the full reframing. Headline points:
  - The state-panel "MDE = 5%" claim is wrong as a precision constraint. Going from state aggregates to county-level data with state clustering shrinks the simulated cluster-robust SE by ~5× (Sim D in the 4-way decomposition).
  - Under a homogeneous-effect DGP, the all-county TWFE MDE is ~2%. Under realistic cohort heterogeneity, the actual real-data SE is ~10× larger; the realistic MDE is ~8–10%.
  - The pooled null was masking substantial cohort heterogeneity. Per-state did2s ATTs range from −57% (NH, a data artifact) to +34% (AR). 8 of 13 states show statistically significant positive ATTs in the +6% to +12% range.
  - **New recommended headline: did2s on pre-COVID-treated cohorts excluding NH = +9.1%, CI [−0.10%, +17.5%]** (borderline significant, consistent with Hollenbeck et al. 2025).
  - The previous "5% MDE TWFE state-panel" spec stays as a robustness check, not the headline.
- See `output/border_diagnostic/HANDOFF.md` for the complete narrative of the diagnostic and recommended next steps.

### Heterogeneity-Robust Estimator Calibration (2026-04-09, SUPERSEDED 2026-05-21)

**Original state-panel calibration** (kept for chronology). Tested via `analysis/diagnostics/cs_calibration_multi_estimator.R` on the balanced 24-state panel (100 null simulations, effect=0, alpha=0.05):

| Estimator | Type | Rejection (target 5%) | SE/SD (target 1.0) | Noise vs TWFE |
|-----------|------|----------------------|---------------------|---------------|
| **TWFE** (fixest) | Pooled | 1% | 1.14 | 1x |
| **Sun-Abraham** (fixest) | Het.-robust | **21%** | **0.58** | **4x** |
| **CS Analytic** (did) | Het.-robust | **14%** | **0.67** | **5.1x** |
| didimputation (BJS) | Het.-robust | failed | — | — |
| did2s (Gardner) | Het.-robust | failed | — | — |

### Heterogeneity-Robust Estimator Calibration at COUNTY LEVEL (2026-05-21, NEW HEADLINE)

Ported the same calibration test to the all-county panel via `analysis/diagnostics/cs_calibration_multi_estimator_county.R`. 50 null simulations.

| Estimator | State-panel rej / SE-SD / noise | County-panel rej / SE-SD / noise | Status |
|-----------|---------------------------------|----------------------------------|--------|
| TWFE | 1% / 1.14 / 1× | **8% / 0.95 / 1×** | OK; wild bootstrap recommended for inference |
| Sun-Abraham | 21% / 0.58 / 4× | 30% / 0.51 / 4.5× | Still broken — skip |
| CS Analytic | 14% / 0.67 / 5.1× | 0% / 2.46 / 3.4× | Over-corrects — skip |
| didimputation (BJS) | failed | **14% / 0.73 / 1.1×** | Rescued; usable as robustness |
| **did2s (Gardner)** | **failed** | **4% / 0.97 / 1.1×** | **Rescued — NEW HEADLINE ESTIMATOR** |

**Key conclusions (updated):**
1. **County-level data rescues the modern imputation estimators.** did2s and didimputation, which failed entirely on the state panel, now run cleanly. did2s is well-calibrated and as efficient as TWFE.
2. **CS-DiD and Sun-Abraham remain broken even on county data.** The cohort heterogeneity problem isn't fixed by within-cohort disaggregation.
3. **TWFE at county level has Type I ≈ 7-8%** — mildly anti-conservative, within MC noise of nominal 5% but consistent enough to require wild cluster bootstrap for valid inference.
4. **Real-data SE is ~10× larger than null-DGP simulated SE.** The 2% MDE from the bootstrap simulation assumes homogeneous treatment effects. Real-data cohort heterogeneity widens the pooled SE substantially, putting the realistic MDE in the 8–10% range.

**Panel used for calibration** (matches pretrends pipeline exactly):
- Source: `state_month_panel_with_treatment.csv` + `sports_gambling_legalization_dates.csv`
- COVID drop: 2020-03-01 to 2022-03-31
- Exclude: ME
- Coverage threshold: auto (83 months) + BALANCE_COMMON_MONTHS=TRUE
- Result: 24 states (11 treated, 13 never-treated), 83 months, 1992 obs, perfectly balanced

**Cohort structure** (why het.-robust estimators struggle):
- 11 treated states, each with a unique online legalization date → 11 singleton cohorts
- No cohort has more than 1 state
- Compare to Hollenbeck et al. (2025): same treatment timing but 51 state clusters (24 treated), ~2x our design

### Previous CS threshold-sweep behavior (legacy, superseded by calibration test)

- Script: `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` (invoked by `scripts/run_cs_power_threshold_sweep_no_maine_2024_min5.sh`)
- For each threshold, the code estimates CS once per simulation at `effect=0` (`one_cs0`), storing `att0` and `se0`.
- For nonzero effects, it does **not** re-estimate `att_gt()`; it shifts the estimate as `att = att0 + log1p(effect_pct)` and keeps `se = se0`.
- P-values are then recomputed from the shifted t-statistic using `2 * pt(-abs(att/se), df = n_states - 1)`.
- Implication: within a threshold, `sd_att`, `mean_se`, and `se_over_sdatt` are expected to be nearly identical across effect sizes; only `mean_att` and rejection rates (power) should change.

## Empirical Results Summary

### Eviction Filings (Primary Outcome)

**UPDATED 2026-07-23 (post NH + ME court-source repairs).** NH (commit 84678a6) and ME (this session) were repaired from their state judicial-branch sources after both were found to carry a late-2023 zero-fill artifact; ME is now included as a never-treated control. Numbers below are the current repaired-panel pretrends run (`output/pretrends_statepanel_me_included`).

- **Panel**: 26 states (12 treated, 14 never-treated), 12 cohorts, 91 months (2016–2024, excl. COVID), 2,366 obs
- **CS-DiD pretrends**: Parallel trends NOT rejected (Holm min p = 1.0, both analytic and bootstrap)
- **Sun-Abraham pretrends**: NO LONGER rejects after the repairs (joint Holm min p = 0.357) — the prior rejection was partly driven by the NH/ME data artifacts
- **Overall ATT (CS-DiD)**: +0.011 log points (SE = 0.163 analytic, 0.162 bootstrap) — **not statistically significant** (was −0.225 pre-repair; the shift is mostly the NH −57% artifact removal)
- **Interpretation**: No detectable effect of online gambling legalization on eviction filings
- **TWFE power**: 80% power to detect 5% effect (MDE = 5 log points) — **unchanged by ME inclusion** (power 0.828 with ME vs 0.835 without at 5%; 38-state raw panel). Adding one never-treated control does not move the MDE.
- **Prior spec (pre-repair, for reference)**: 24 states (14 treated, 10 never-treated), overall ATT −0.225, SunAb rejected pre-trends

### Mortgage Delinquency (Alternative Outcome)

- **Panel**: 51 states (24 treated, 27 never-treated), 18 cohorts, 91 months (2016–2024, excl. COVID), 4,641 obs
- **CS-DiD pretrends**: Parallel trends NOT rejected (Holm min p = 1.0)
- **Sun-Abraham pretrends**: Rejects (same long-horizon trend issue — secular post-financial-crisis decline)
- **Overall ATT (CS-DiD)**: +0.030 percentage points (SE = 0.043) — **not statistically significant**
- **Interpretation**: No detectable effect on mortgage delinquency rates
- **Script**: `analysis/pretrends/pretrends_mortgage_delinquency.R`, run via `scripts/run_pretrends_mortgage.sh`

### Related Literature: Hollenbeck, Larsen & Proserpio (2025)

- Uses individual-level UC Consumer Credit Panel (~7M people), Callaway & Sant'Anna estimator
- Same treatment variation as our project (state-level online gambling legalization dates)
- Finds significant effects of **online** gambling access on: credit scores (−2.75 points), bankruptcy (+10%), collections (+7.5%), auto loan delinquency (+20%)
- **No effect** on credit card delinquency
- Effects appear ~2 years post-legalization, concentrated among subprime borrowers
- Key differences from our project:
  - **Data**: individual-level credit records for all 50 states + DC vs. aggregate state-level eviction data for 24 states
  - **Clusters**: 51 state clusters (24 treated) vs. our 24 (11 treated) — roughly 2x our design
  - **CS works for them** because they have more clusters, not because of individual vs. aggregate data (treatment is at state level for both; clustering is at state level for both)
  - **Implication**: their 7.5-10% individual credit effects may not aggregate into detectable state-level eviction effects — eviction is a more extreme margin with additional attenuation steps

### Gambling Market Maturation (Handle Quintile Timing)

Analysis of how quickly state gambling markets reach their peak monthly Handle (33 states, June 2018–Oct 2025). Measures months from a state's first Handle data to first reaching each quintile of that state's peak month.

| Quintile | Mean (mo) | Median (mo) | SD   | Min | Max |
| -------- | --------- | ----------- | ---- | --- | --- |
| 20%      | 4.8       | 1.9         | 8.5  | 0   | 38  |
| 40%      | 10.3      | 8.0         | 12.1 | 0   | 48  |
| 60%      | 16.9      | 14.0        | 14.9 | 0   | 52  |
| 80%      | 29.3      | 30.0        | 17.5 | 0   | 65  |
| 100%     | 46.3      | 46.0        | 19.6 | 0   | 78  |

- Most states reach 20% of peak within 2 months (median), though retail-first states like Arkansas take ~38 months
- 80% of peak takes ~2.5 years on average (median 30 months)
- Peak reached at ~3.8 years on average, ranging 0–78 months
- States launching with online immediately (Ohio, North Carolina, Kansas) hit high quintiles in month 1; retail-first states (Arkansas, Oregon) take years
- Relevant for gambling intensity heterogeneity: post-treatment handle maturation varies widely, so first-year handle may not capture steady-state intensity
- Script: `analysis/exploratory/quintile_timing_analysis.R`

## Known Issues and Limitations

### STATE PANEL DOUBLE COUNT — REBUILT 2026-08-20 (read before using any pre-rebuild state-level result)

`data/raw/state_month_panel_with_treatment.csv` was, until 2026-08-20, an exact double count
for 12 states: `filings_count = (county download sum) + (merged_ets_combined.csv ETS series)`,
verified to the unit on 891 of 916 overlap state-months (100% for all 12 affected states;
the other 25 are WI, already repaired by 08c and therefore not an exact addition)
(`analysis/diagnostics/statepanel_double_count_audit.R`; outputs in
`output/statepanel_double_count/`). The two sources cover the SAME filings. Because each ETS
series has its own span, the double count switched on/off mid-panel — a 1.2x-2.4x level break
with no eviction content: cities series START 2020-01 (AZ OH SC TN TX -> jump up), state_level
series END 2023-02 (CT DE IN MN PA VA -> drop), FL state series end 2020-01 (drop). No repo
script ever built this file; only the NH/ME/MD/WI patch scripts touched it.

**Rebuild** (`data_prep/rebuild_state_month_panel.R`): one consistent source per state —
county-download sums for all states in the download except NH/WI (court-source repairs kept),
MD carried as Judiciary monthly Landlord/Tenant COMPLAINT filings (NOT the superseded Socrata
post-judgment warrant extract),
NY trimmed to 2019+ (pre-2019 was a different-basket ETS series; NY now fails the 91-month
balance and DROPS from the balanced pretrends panel), MD/LA/MA/MO/NM/NV/RI single-source rows
carried over. `treat_start` recomputed from the repaired schedule. Old panel preserved at
`data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv`.
Provenance per state: `data/processed/state_panel_rebuild_source_table.csv`.

**Bias mechanism**: constant multiplicative inflation cancels in log outcomes with state FE;
only windows STRADDLING a break (2020-01 or 2023-02) are biased — which includes the standard
2016-2024-excl-COVID window for all 12 states, and the post-COVID window for the 2023-02 six.
This is what made TX (+0.785) and MN (-0.715) long differences fake (county file: -0.493/-0.024)
and inflated the real-calendar sigma 0.592 -> 0.327.

**Contaminated (state-panel-based; re-run before citing):** pretrends headline (re-run 2026-08-20,
see below), state calibration table (CS 14%/SunAb 21% — residual-pool DGP contained the breaks),
blinded-power STATE cells (did2s 23-29% Type I, TWFE-wild MDE>20%, time_agg/splice memo,
LP-DiD spliced-state MDE 8.1% synthesis, longdiff_power, cheap_sims grid), TWFE staggered
power sim (MDE=5% claim), handle50/post-COVID handle50 outputs (panel regenerated 2026-08-20;
downstream outputs stale), era-variance state-panel sigmas (county fixed-basket numbers stand).
**Immune:** everything county-download-based (county calibration incl. did2s 4%/0.97, county CS
adaptive MDE verdict, border diagnostic, +9.1% did2s headline), mortgage delinquency, 2x2
pseudo-power on the annual court panel, handle maturation stats.

**REBUILT PANEL IS NOT YET ANALYSIS-READY — composition churn is unfixed (Codex review,
2026-08-20).** The rebuild removes the double count but a county-sum state total is still a
COMPOSITION-VARYING basket, and a state-month presence check does not catch it. Verified cases:
FL drops Miami-Dade and Lee at 2024-01 — one month after FL's own 2023-12 treatment date;
TN falls 36 -> 12 -> 3 reporting counties over 2024-03/04; TX loses Harris at 2024-05, cutting
its renter denominator 48%. Measured effect on the 2016-19 -> 2022-24 change in log filings:
artifacts of +1.02 (ID), -0.28 (FL), -0.16 (TX) log points; cross-state SD 0.249 as-reported vs
0.207 on a fixed basket. Every row now carries `n_counties` and `basket_share`, and
`data/processed/state_panel_coverage_qa.csv` grades each state — censor the tail or fix the
basket before any state-level estimate is cited. Also fixed in the same pass: zero renter
denominators were producing FABRICATED rates up to 6,934,000 per 1k renters (404 rows across
LA MA MO NM NV RI); rates are now NA where no denominator exists. The rebuild is idempotent and
the pre-fix panel is preserved once and never overwritten.

**Post-rebuild pretrends headline — PROVISIONAL, do not cite (2026-08-20, `output/pretrends_rebuild_B_newpanel/`):**
25 states (16 treated, 9 never-treated — schedule repair moved ME/VT/KY/FL to treated; NY out),
15 cohorts, 91 months. CS overall ATT **+0.080 log points (SE 0.088 analytic, 0.088 bootstrap)**
— not significant, CI ~[-0.09, +0.25]. Pre-trends NOT rejected (CS Holm p = 1.0; SunAb p = 1.0).
Vs the old panel run at the same schedule (`output/pretrends_rebuild_A_oldpanel/`: ATT +0.074,
SE 0.130): the fix leaves the point estimate nearly unchanged and cuts the CS SE by ~1/3;
mean |pre-ATT| halves (0.047 -> 0.029). The pre-rebuild published numbers (ATT +0.011, SE 0.163,
26 states 12 treated) are dead — they mixed the double count with the stale schedule.


### CS in the Blinded Power Framework: Two Execution Flags (2026-08-17)

The CS arm of `R/power/` could not run at all until this date. Two run-level config keys
now govern it; both default to historical behavior and both are hashed into the scenario
id **only when non-default AND only for CS-bearing scenarios**, so enabling either never
moves a twfe/did2s id or orphans a completed partial. Full write-up:
`docs/methodology/POWER_SIMULATION_DESIGN.md` §16a. Tests:
`tests/testthat/test-cs-safe-patches.R`.

- **`cs_safe_patches`** (default `FALSE`). `att_gt` → `DRDID:::reg_did_rc` → `fastglm`
  **aborts the R process** (C-level, uncatchable) on zero-row design matrices from
  non-identifiable (g,t) cells — ~1 rep in 4 on the D1 state design. Under furrr the
  worker dies and the scenario is lost. `TRUE` installs `patches/reg_did_rc_safe.R`.
  **Must patch two bindings**: `did` does `importFrom(DRDID, reg_did_rc)` and copies it by
  value, and under `faster_mode=TRUE` calls it unqualified — patching DRDID alone leaves
  the hot path unguarded while appearing to succeed.
- **`cs_faster_mode`** (default `TRUE` = historical). With `TRUE`, CS failed on **100%**
  of probed rep × delta cells: "singular matrix due to not enough control units. Try
  changing faster_mode=FALSE." TWFE/did2s converged on 100% of the same reps.
  `analysis/diagnostics/cs_cv3_calibration_state.R:64-66` found this on 2026-08-11 and
  fixed it only in that script. `FALSE` is also *faster* here (24–40 s vs 57–101 s/fit).
  **Implication: every prior CS run in this framework used a non-estimating code path.**

**Unresolved:** the two `faster_mode` settings return materially different ATTs on
identical data (−0.033 vs +0.557 on one rep, with different SEs). `faster_mode` is meant
to be a pure computational shortcut, so this should not happen. Treat CS point estimates
from this framework as provisional and always record which mode produced them.

### County CS Verdict via the Adaptive MDE Search (2026-08-19 — RESOLVED question)

Shift mode was barred for the headline CS MDE by an Opus review
(`quality_reports/sufficient_statistics_shift_mode_code_review.md`); the replacement is
`R/power/adaptive_mde.R` (`run_adaptive_mde()`, design doc §16c) — an adaptive grid where
every cell is a genuine full estimate, bit-identical per (rep, δ) to brute force
(verified on real state CS). Production run `output_blinded_power/county_cs_adaptive/`
(county/S2/D1-panel/count_nb/step, 250 reps, faster_mode=FALSE, safe patches on):

- **Size gate:** analytic 61.2% FAIL (SE/SD 0.23, coverage 39%); **boot 4.4% and
  boot_t 3.2% size-valid** (0 failures) — the multiplier bootstrap that over-rejected at
  state (24.5%) is size-valid at county — **but NOT calibrated**: SE/SD ≈ 1.74, CI width
  ≈ 2 log points ([−60%, +150%] in filings).
- **Power curve is FLAT for both size-valid arms** — power ≈ size everywhere, 7.2%/4.8%
  at δ=0.20 with full 250 reps → `never_crosses_target`. **No defensible finite county CS
  MDE exists on the pre-registered grid** (do not write "MDE > 20%" as if it sits nearby).
- **CS point estimate is biased +0.10 upward under the null** on this cell (t ≈ 4.7),
  which inflates power and so strengthens the never-crosses verdict a fortiori; the cell
  must not be reused for point-estimate claims.
- PAP consequence: CS is eliminated on power among size-valid arms (did2s remains the
  calibrated county workhorse). One-cell scope; §14 fragility criterion unmet by design.
- Full report: `quality_reports/adaptive_cs_mde_report_2026-08-19.md`; overnight
  narrative: `quality_reports/adaptive_sim_overnight_log.md`. The old shift-mode partial
  `output_blinded_power/county_cs/` is preserved untouched.

### Time Aggregation Does NOT Fix CS; the COVID Splice Is What Breaks It (2026-08-19)

Tested directly: `config/power_time_agg_covid_gates.yml` (state/S2/D1-panel/count_nb,
delta=0, 300 reps, 13 cells) using the new `time_agg` axis (month/quarter/year) in
`load_blinded_panel()`. Memo: `quality_reports/time_agg_covid_calibration_memo_2026-08-19.md`.

- **Cohorts DO collapse as hypothesised** — 21 cohorts (max 2 states) monthly -> 17 (max 3)
  quarterly -> **7 cohorts (max 6 states) annually** — **but CS size does not follow**:
  spliced-window CS analytic 18.3% (month) -> 16.7% (quarter) -> **24.7% (year)**. The
  singleton-cohort story is NOT the binding constraint.
- **The COVID splice is the dominant factor.** On the clean post-COVID monthly window CS
  PASSES the size gate for the first time in this project: 5.0% analytic / 6.0% boot /
  3.3% boot_t, SE/SD 1.06-1.14. Every spliced cell fails for CS *and* did2s (26-42%),
  generalising the 2026-08-17 did2s splice-artifact finding to CS.
- **CS null bias is large and negative on post-COVID cells** (-0.20 monthly to -0.58
  annual) even where size passes — size-valid is not unbiased; report both.
- **Annual aggregation has a partial-period artifact:** the loader filters COVID months
  BEFORE aggregating, so annual 2020 = 2 months of filings and 2021 = 5. Use
  `complete_periods_only: true` to drop incomplete unit-periods — but note that on the
  SPLICED window this makes coarse aggregation **D1-infeasible** (quarter 1/5 placements,
  year 0/5, vs 5/5 with it off).
- **LP-DiD is incompatible with coarse aggregation: 0/300 convergence** at quarterly and
  annual (its lags run on calendar months by design); 300/300 monthly. Fix before any
  quarterly LP-DiD spec.
- **Speed:** CS costs 27.7 s/cell monthly, 3.4 s quarterly, 0.2 s annually (8-140x) — a
  reusable speedup even though calibration is unchanged.

### Binary 2x2 Long Difference: Pseudo-Treatment Power Verdict (2026-08-19)

The binary long difference — `tau = (Ybar^T_end - Ybar^C_end) - (Ybar^T_pre -
Ybar^C_pre)`, one common calendar, "online by 2022" as a binary group — is
powered as a **pseudo-treatment experiment in the pre-treatment era** (Black,
Hollingsworth, Nunes & Simon 2022), NOT by truncating each state at its own
legalization date. Truncating leaves 6 usable states at the real calendar;
shifting the whole experiment before 2018-06 (first-ever legalization) keeps
every state, because nothing is treated there. Full memo:
`quality_reports/longdiff_pseudo_treatment_memo_2026-08-19.md`.

- **Substrate switch is forced.** The ETS monthly untreated era is only
  2016-01..2018-05 = **29 months**, so a 24-month baseline + 12-month endpoint
  cannot fit disjointly, let alone at the real ~70-month distance. The
  **annual county court panel** (`data/raw/county_court-issued_2000_2023_ben_update_5_12.csv`)
  does: **CY2008+2009 -> CY2016 = 37 states, 1,549 counties, 72-month distance,
  22 online-ever / 15 never** — widths, distance, and counts all preserved.
  Watch the DC case mismatch ("District Of Columbia"); a case-sensitive join
  silently drops DC and changes the split.
- **MDE-80 = 0.241 log points (+27% in filings)** under randomization
  inference, 500 reps (`output/longdiff_2x2_pseudo/`). **This is a FLOOR** —
  measured in the calm pre-2018 era.
- **RI is exactly nominal (5.0%); CRVE FAILS the size gate** (7.8% main,
  **12.4%** on the 12-month-baseline variant, SE/SD 0.88). At 37 unbalanced
  clusters do not quote CRVE. WCB is fine (5.2%). Null bias -0.0008.
- **Real-era MDE is +20% to +80%** — a RANGE, not a point: the era-inflated
  pseudo route gives +77%, the corrected direct anchor +20-24%, and the two
  disagree because the ETS inputs are coverage-unstable (see below). **The 2x2 cannot detect the 7.5-10% effects the credit literature
  reports**, and is far weaker than LP-DiD spliced-state (MDE 8.1%). Keep it as
  a transparent descriptive contrast; do not make it the powered spec.
- **Type M is severe**: a significant estimate at delta = 0.05-0.10 overstates
  the truth by **2-4x**; at delta = 0.02 under CRVE, 28% of significant
  estimates have the WRONG SIGN.
- **Selection check passes**: eventual online legalizers show no pre-treatment
  divergence from never-legalizers (tau = -1.4%, RI p = 0.90;
  `analysis/diagnostics/longdiff_2x2_selection_placebo.R`).

### Era Variance: Pre-2018 Understates Post-COVID Noise by 2-4x (2026-08-19)

`analysis/diagnostics/longdiff_era_variance.R` -> `output/longdiff_era_variance/`.
sigma = SD across states of the state-level long difference (exactly what the
clustered SE is built from), windows slid over every feasible placement at
**matched geometry and matched distance**, on states untreated in BOTH eras.

- **Median post/pre sigma ratio 2.67** (range 1.8-5.2); 3.86 on the strict
  never-any-legalization set. Any pre-era MDE must be inflated accordingly.
- **IDAHO TRAP:** with ID included the raw comparison *inverts* (pre looks
  noisier). ID is the single most extreme state in **100%** of pre-era
  placements. CLAUDE.md already excludes ID from annual analyses; exclude it
  here too. Trimmed and MAD statistics were right all along.
- **Never-treated states are ~1.5-1.6x noisier than the full state set** in the
  pre era. The real control pool IS those states, so an all-states rehearsal
  understates noise on that count as well.
- **Real-calendar anchor — CONTAMINATED, revised down.** State panel gave
  sigma = 0.472 (MDE +56%), but **two states (TX, MN) carry nearly all of it
  and BOTH disagree with the county file** (TX: state panel +0.785 vs
  county-aggregated -0.493; MN: -0.715 vs -0.024; the other five agree
  exactly). A second artifact compounds it: reporting-county composition
  changes between windows (TX 12.8 -> 8.5 counties), and fixing the basket
  flips TX to +0.36. Corrected sigma **0.19-0.23 -> MDE-80 ~ +20% to +24%**.
  Era factor survives but shrinks: **2.36x** on a fixed basket vs 3.89 from the
  state panel at the same cell. **ACTION: reconcile the TX and MN state-panel
  series against `monthly_county_data_download.csv` before reporting any long
  difference.** Script: `analysis/diagnostics/longdiff_real_calendar_decomp.R`.
- **Averaging is nearly inert (Burlig-Preonas-Woerman confirmed).** Measured
  with the endpoint window's CENTRE fixed so averaging is separated from
  distance: in the post-COVID era a 12-month endpoint average cuts sigma by
  only **5-12%** vs the 71% independence would give. The 24-month baseline
  likewise buys ~nothing over 12 months (MDE 0.241 vs 0.246). Do not spend
  design freedom on window length.

### Gambling Intensity Heterogeneity Analysis Does Not Work

The `pretrends_statepanel_template.R` gambling intensity feature bins states by **pre-treatment average handle**. This always produces 0 states because gambling handle only exists AFTER legalization — there is no handle before a state legalizes (it's 0 by definition). The code at `filter(g > 0L, t < g, !is.na(gambling_amount))` correctly returns empty results.

**To fix**: Refactor intensity binning to use post-treatment handle (e.g., first-year average, or cumulative handle per capita) instead of pre-treatment handle. Alternatively, use regulatory features (number of operators, tax rate, advertising rules) as the intensity measure, which avoids the endogeneity concern that post-treatment handle is itself an outcome.

### State-Level Power Constraint

Treatment varies at the state level, so the effective sample size for inference is ~51 clusters (or ~24 treated in our balanced panel). Using county-level data does NOT meaningfully improve power because cluster-robust SEs are driven by the number of clusters, not observations within clusters. The null results on evictions and mortgage delinquency may reflect genuine null effects or insufficient power at the state level to detect small effects.

### Data Coverage Constraint

The ETS (Eviction Tracking System) monthly panel covers only 38 states, and after balancing to common months (excluding COVID), ~26 states survive (25 without ME; ME repaired and re-included 2026-07-23). This is the binding constraint on power — not the estimator choice.

**7 online gambling states have annual court data but are NOT in the ETS panel:**

| State | Online Start | Court Data Source | Coverage |
|-------|-------------|-------------------|----------|
| NJ | 2018-08 | `Court Data/` compiled CSV | 2013-2025, 21 counties |
| IA | 2019-08 | Compiled CSV (no source files) | 2000-2025, 99 counties |
| OR | 2019-10 | `Oregon pasted.xlsx` | 2000-2025, 36 counties |
| IL | 2020-06 | `Summary Illinois.xlsx` | 2000-2025, 102 counties |
| MI | 2021-01 | Compiled CSV (no source files) | 2010-2025, 83 counties |
| WY | 2021-09 | Compiled CSV | 2014-2025, 23 counties |
| MD | 2022-11 | `Maryland 20XX.xlsx` files | 2000-2025, 24 counties |

- All court data is **annual** (county-year), not monthly
- Only North Carolina has monthly breakdowns in source files (and NC is already in the ETS panel)
- Court data compiled file: `/Users/bb1806/Documents/Court Data/county_court-issued_2000_2025_ben_update_3_19.csv`
- Adding these 7 states via an annual panel would: (a) increase treated clusters from 11 to 18, (b) create multi-state annual cohorts (e.g., 2019: PA+IA+IN+OR = 4 states), (c) partially resolve the singleton-cohort problem
- Tradeoff: annual data means fewer time periods, coarser treatment timing

### Interpretation: Null Result vs. Underpowered

The result is a **bound**, not a precise null:
- **Can say**: "No evidence of effects above 5% on evictions" (TWFE-based, well-calibrated)
- **Cannot say**: "Gambling doesn't increase evictions" (true effect could be 1-2%, well below MDE)
- **Framing for policy**: gambling legalization doesn't cause an eviction *crisis*, but may cause smaller effects we can't detect
- **Framing for Arnould Ventures**: we've established the analytical framework and ruled out large effects; funding would support expanding the eviction panel to tighten the MDE
- **The 5% MDE is informative relative to Hollenbeck et al.** (7.5-10% credit effects), but eviction is a more extreme downstream margin with additional attenuation

## TO DO

- [ ] Build annual panel merging ETS (aggregated to annual) + Court Data states for 30+ state robustness check
- [ ] Run CS calibration on the annual panel to test whether multi-state cohorts fix the het.-robust estimator problem
- [ ] Consider sourcing monthly court data directly from state court systems (NJ Courts, Michigan SCAO, Iowa Judicial Branch) for states with online gambling
- [ ] Run Goodman-Bacon (2021) decomposition on TWFE to quantify negative-weight concern
- [ ] Add per-batch checkpoint/resume to `R/power/run_scenario_grid.R` and raise `--time` before resubmitting the CS arm of the power sims (county+CS needs ~50–63h vs the 48h limit; a timeout currently loses the whole scenario)
- [ ] Drop S3 from `power_primary.yml` D1 blocks (structurally infeasible — see Blinded Power-Simulation Framework section) and decide whether to promote a D4 never-treated block into primary
- [ ] Draft the Arnold pre-analysis plan: port design sections from `Arnold Housing Loss Gambling - Application.docx`; rewrite estimator-selection rule (calibration-gate decision rule, not "CS if different"), power section (blinded framework + MDE in filings-per-year terms + heterogeneous-DGP MDE), and key modeling decisions (COVID window, log(1+y), treatment date defs, balance rules, state exclusions)

## Bundled R Packages (`did/`, `DRDID-master/`, `fastglm-master/`)

This repo includes local patched copies of three R packages to fix critical bugs:

### `did` v2.3.0 (Callaway & Sant'Anna)

- **Purpose**: Group-time average treatment effects for staggered DiD designs via `att_gt()`
- **Authors**: Brantly Callaway and Pedro H. C. Sant'Anna
- **Known bugs fixed by this project**:
  1. **P-value computation** — incorrect two-sided t-test statistic caused 0% rejection rate under the null (`FIX_cs_pvalue_computation.patch`)
  2. **Unbalanced panel handling** — IPW estimator failed when panels had missing observations (`FIX_unbalanced_panel.patch`, `FIX_allow_unbalanced.patch`)
  3. **Estimation method selection** — bootstrap and regression estimator incompatible combinations caused errors (`FIX_cs_simulation_est_method.patch`)
  4. **Empty matrix segfaults** — `fastglm()` called on 0-row design matrices triggered C++ segfaults in `colMax_dense()`

### `DRDID` v1.2.3 (Sant'Anna & Zhao 2020)

- **Purpose**: Doubly-robust DiD estimators (IPW + outcome regression)
- **Paper**: Sant'Anna & Zhao (2020) <doi:10.1016/j.jeconom.2020.06.003>
- **Key function**: `reg_did_rc()` — used internally by `did::att_gt()`
- **Patch**: `patches/reg_did_rc_safe.R` adds guards before `fastglm()` calls; returns NA for non-identifiable cells instead of crashing

### `fastglm` v0.0.4

- **Purpose**: Fast GLM fitting via RcppEigen (iteratively reweighted least squares)
- **Used by**: DRDID for outcome regression
- **Root cause of segfaults**: crashes on 0-row design matrices passed from non-identifiable (g,t) cells

## Safety Wrappers & Patches (`patches/`)

| File | Description |
| ---- | ----------- |
| `att_gt_safe.R` | Safe wrapper around `did::att_gt()` with preflight support check; returns NA for unsupported cells |
| `preflight_support_check.R` | Computes (g,t) cell support BEFORE estimation; flags non-identifiable cells with reasons |
| `reg_did_rc_safe.R` | Patched DRDID function with guards before every `fastglm()` call |
| `plot_csdid_pretrends.R` | Plotting: event study, pre-trends tests, group dynamics, support heatmap |
| `FIX_cs_pvalue_computation.patch` | Corrects two-sided t-test in `did` package |
| `FIX_cs_simulation_est_method.patch` | Fixes estimation method selection logic |
| `FIX_unbalanced_panel.patch` | Handles missing observations in IPW estimator |
| `FIX_allow_unbalanced.patch` | Adds `allow_unbalanced_panel` parameter |

## R Econometrics Methodology

### Estimators

1. **TWFE (Two-Way Fixed Effects)** — Primary estimator for power analysis
   - Implementation: `fixest::feols()` with unit + time fixed effects
   - Inference: cluster-robust SEs at state level (fixest default)
   - **Calibration**: SE/SD = 1.14, rejection under null = 1% (well-calibrated, slightly conservative)
   - Limitation: does not properly capture dynamic treatment effects in staggered designs (Goodman-Bacon 2021). Less concerning for a null result.
   - Script: `analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`

2. **CS-DiD (Callaway & Sant'Anna 2021)** — Heterogeneity-robust, miscalibrated on this design
   - Implementation: `did::att_gt()` with analytic or bootstrap inference (`biters=199`)
   - Strength: group-time heterogeneity, avoids negative weighting, handles staggered treatment properly
   - **Calibration**: SE/SD = 0.67, rejection under null = 14% (over-rejects, SEs too small). NOT a `did` package bug — structural issue with singleton cohorts.
   - Noise: 5.1x noisier than TWFE (SD of ATT across null sims)
   - Effective MDE: ~25% (vs TWFE's 5%) — too large to be useful
   - Script: `power_simulation_cs.R`, calibration: `analysis/diagnostics/cs_calibration_multi_estimator.R`

3. **Sun-Abraham (2021)** — Heterogeneity-robust, also miscalibrated
   - Implementation: `fixest::sunab()` with fixest cluster-robust SEs
   - **Calibration**: SE/SD = 0.58, rejection under null = 21% (worst of all estimators tested)
   - Noise: 4x noisier than TWFE
   - Same structural issue as CS — uses fixest SEs (not `did` package), confirming the problem is the design not the software

4. **didimputation (Borusyak, Jaravel & Spiess 2024)** — Installed, fails on this panel
   - Implementation: `didimputation::did_imputation()`
   - Status: runs on real data but fails in simulation (all 100 sims errored)

5. **did2s (Gardner 2022)** — Installed, SE extraction issues
   - Implementation: `did2s::did2s()`
   - Status: SE extraction failed due to API differences; needs debugging

### Inference Methods

- **Cluster-robust SEs**: state-level clustering (`cluster_level = "state"`) — primary method
- **Wild bootstrap**: `fwildclusterboot` package — optional, for small number of clusters
- **Bootstrap (CS-DiD)**: multiplier bootstrap with 50-199 iterations

### Pre-trends Testing (Modern Methods)

- **Roth (2022)**: Power analysis for pre-trend tests — reports minimal detectable violations (MDVs) alongside p-values. Key insight: don't condition analysis on pre-test results.
- **Rambachan & Roth (2023)**: `HonestDiD` sensitivity analysis — bounded violations framework with M ∈ {0, 0.5, 1, 1.5, 2}. Tests robustness under plausible parallel trends violations.
- **Equivalence testing** (Hartman & Hidalgo 2018): provides positive evidence FOR parallel trends (not just failing to reject). Reports smallest δ* that can be ruled out.
- Legacy script: `analysis/pretrends/pretrends_modern.R` (1200+ lines, 10+ specifications, CS section disabled)
- **Recommended pipeline**: `analysis/pretrends/pretrends_statepanel_template.R` — runs CS-DiD (analytic + bootstrap) and Sun-Abraham event studies on the same sample, with Holm-adjusted joint pre-trend test (CS) and Wald F-test (SunAb). Optional self-test calibration guards against inflated CS SEs by running null simulations on the real design skeleton. Optional gambling intensity heterogeneity analysis via Handle terciles.

### Support Structure

- Raw ETS panel: 38 states (Maine repaired 2026-07-23 and re-included; formerly excluded for data quality)
- Balanced panel: pretrends ~26 states (ME included); the CS calibration script still hardcodes `EXCLUDE_STATES=c("ME")` and reports 24 states until re-run
- 11 treated states, each in its own cohort (singleton cohorts)
- 13 never-treated states
- 15–18 treatment groups in unbalanced panel (depending on treatment definition: online, retail, first)
- 875 total (g,t) cells; only 338 identifiable (38.6%) in unbalanced panel

### Power Analysis Results

- **TWFE without COVID**: 80% power to detect 5% effect (MDE = 5 log points). Well-calibrated: SE/SD = 1.14, Type I error = 1-5%.
- **TWFE with COVID**: 80% power to detect 8% effect (MDE = 8 log points)
- **Heterogeneity-robust estimators (CS, SunAb)**: MDE ≈ 20-25% (4-5x noisier). Not useful for detecting plausible effect sizes.
- **No formal power simulation exists for mortgage delinquency** (the mortgage panel has 51 states so power is likely better than evictions)

## Common Tasks

- **Fix broken paths**: All scripts use paths relative to project root. If something can't find a file, check that `setwd()` points to the repo root.
- **Add a new analysis**: Source `power_simulation_cs.R` to get access to `load_panel(cfg)`, `make_treat_schedule()`, etc.
- **Modify treatment definition**: Edit `cfg$treat_date_col` in `power_simulation_cs.R` (options: `online_start_date`, `retail_start_date`, `first_start_date`)

## Requirements

- R >= 4.0
- Core packages: tidyverse, fixest, lubridate, did, glue, patchwork
- Calibration packages: did2s, didimputation (installed 2026-04-09)
- Optional: fwildclusterboot (for wild bootstrap inference)
