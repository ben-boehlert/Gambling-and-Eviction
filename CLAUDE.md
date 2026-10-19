# CLAUDE.md - Project Guide for Claude Code

## Project Overview

Research replication package analyzing the causal effect of sports gambling legalization on eviction rates using staggered difference-in-differences (DiD) methods. This is an economics/econometrics project written primarily in R.

## Where Truth Lives (read this first)

This file describes the repo's **structure, data, and conventions**. It does not carry results.

- **[FINDINGS.md](FINDINGS.md)** — current truth only: headline answers, the PAP decision table, calibration verdicts, standing design traps, open questions. Every number there is artifact-verified.
- **[RUN_LEDGER.md](RUN_LEDGER.md)** — the run registry: every sim/pretrends/calibration/diagnostic run with status `LIVE / SUPERSEDED / CONTAMINATED / DEAD / EXPLORATORY / UNKNOWN`, config, vintage, and output path. Answers "has X been run, and can I cite it?"
- **[ESTIMATOR_MATRIX.md](ESTIMATOR_MATRIX.md)** — the cross-cut view: estimator × spec → runs, results, and coverage gaps. Update together with the ledger.
- **[docs/findings-archive/](docs/findings-archive/INDEX.md)** — the chronological findings/corrections history that used to live in this file, split by topic, preserved verbatim.
- **[MOVES.md](MOVES.md)** — where the 2026-08-25 cleanup relocated every deprecated artifact (old → new paths).
- **[docs/DATA_CURRENCY.md](docs/DATA_CURRENCY.md)** — generated, never hand-edited: per-state span, staleness, interior gaps, basket share, denominator presence, clean-anchor role, and the exact refresh command for each source. Regenerate with `Rscript data_prep/make_data_currency_doc.R` after any panel rebuild. Check it before claiming a series is current.
- **[docs/DATA_PROVENANCE.md](docs/DATA_PROVENANCE.md)** — who collected every input file, from what, and whether that is verified. Read it before describing any data source. Two standing corrections: `monthly_county_data_download.csv` is **LSC CCDI, not ETS** (§1 there; §5 lists the places, including PAP text, that still say otherwise), and it is a **HYBRID, not a pristine LSC download** — see the box below.
- **[docs/STATE_SOURCES.md](docs/STATE_SOURCES.md)** — one row per state: provider, and whether the series is the whole state, a county basket, or a single city. LA = New Orleans, MA = Boston, NV = Las Vegas; ID/KS/MS are one county each.

**Maintenance rules (mandatory for every session):**
1. Every completed run appends one row to the matching RUN_LEDGER.md table before the session ends. A superseded row is never deleted — its status changes and points to its replacement.
2. When a LIVE result changes, update FINDINGS.md in the same session.
3. Corrections and post-mortems get a dated file in `docs/findings-archive/` — do **not** accumulate findings narrative in this file.
4. Deprecation is by move to the nearest `deprecated/` folder, recorded in MOVES.md. Nothing is deleted.
5. Before comparing any two runs, check RUN_LEDGER.md vintages: NH/ME court-source repairs 2026-07-23, schedule repair 2026-08-10, panel rebuild 2026-08-20, NV exclusion 2026-08-21, LP-DiD weights fix 2026-08-24, per-state basket rebuild 2026-08-28 (adds CO/HI/MS/NY/SC; prior state-months unchanged), MD series extension 2026-09-03 (adds MD 2025-12..2026-06; prior rows unchanged bit-for-bit), **single-series rebuild 2026-09-14** (LA/MA/MO/NM/NV/RI rebuilt from the Eviction Lab internal county extract — RI +77 months, MO/NM +41, MA +31; RI/MO/NM change geographic scope, so prior rows are NOT unchanged for those three; switchers 13 → 15), **Oregon + WA + MI added and trailing partials censored 2026-09-14** (same boundary: OR splices OJD PDFs with the Evicted in Oregon dashboard; WA = Tacoma/Pierce Co. from the same extract, never-treated control; MI = JDW statewide, 68 of 89 months with 21 interior gaps, **not** a clean-anchor switcher on either headline treat_def; LA/MA/MO/NM lose a partial final month — 42 states, 4,351 rows), **Idaho swapped to the statewide Idaho Judicial Branch A12 series 2026-09-14** (same boundary: Twin Falls LSC basket, 113 months, → all 44 counties, 66 months 2021-01..2026-06, no pre-2021 data; `data_prep/add_id_to_state_panel.R`. A post-swap re-run of `rebuild_state_month_panel.R` silently restored CT's two ramp months; re-censored 2026-09-16 and the rebuild now re-applies the censor itself — **42 states, 4,304 rows**), **value censor + breadth-aware plausibility band + hybrid relabel 2026-09-17** (UT 2023-11/12 and CO 2023-11 removed by name; a plausibility rule then removed 7 more state-months — the band is K state-sigmas of each state's OWN dispersion of deviation-from-expected, interior K=7.0 / terminal K=4.2, calibrated to reproduce the 50–150% / 70–130% bands at median dispersion; NC/ME court-source rows relabelled — **42 states, 4,288 rows**; every other row unchanged bit-for-bit), **LSC-site extension 2026-09-17 evening** (LSC's bulk download ends 2025-09 for every state but its per-county pages run to 2026-06; `data_prep/pull_lsc_site_county_month.R` + `append_lsc_site_months.R` append only new keys after 2025-09 — county file 123,845 → 130,927 rows, state panel **4,429 rows, 42 states, all 4,288 prior rows unchanged**; 18 states extend, the late-2025/2026 never-treated pool goes 4 → 11; LSC's revisions to shared history are audited in `data/processed/lsc_site_revisions_2026-09-17.csv` and NOT applied), **Maine court extension 2026-10-19** (ME re-parsed from the Maine Judicial Branch FED report copy with ref date 2026-09-18 by `data_prep/monthly_panel_expansion/07c_parse_me_fed_monthly15yr.R`, reading each page's own year header — the 2026-09-17 Jun–Dec relabel is retired; ME now runs to 2026-08, +15 months; one prior ME month (2023-07) moves by 1 filing; **4,444 rows**, every non-ME row unchanged). Never pair across a boundary; after any panel/schedule edit use a fresh `run_name` (scenario ids hash settings, not data).

## Terminology Note (Data Search)

When searching for or evaluating eviction data sources (state AOC/court dashboards, LSC filings, county court systems), **"landlord/tenant filings" and other near-synonyms (e.g., "landlord-tenant cases," "L&T," "forcible entry and detainer," "unlawful detainer," "summary process") are acceptable stand-ins for "eviction."** Many state court systems file evictions under these case-type labels rather than the word "eviction" itself. Do not discard a source or dashboard as irrelevant just because it doesn't use the literal word "eviction" — check whether the case type is a landlord/tenant or possession action first.

## Key Entry Points

- `FINDINGS.md` / `RUN_LEDGER.md` — results and run registry (see above)
- `README.md` — repo overview
- `INSTALL_PACKAGES.R` — run first to install all R dependencies
- `quality_reports/cleanup_2026-08-25/` — the inventories behind the ledger's classifications

## Repository Structure

```
analysis/           Main analysis scripts
  main/             Primary TWFE / LP-DiD / CS-DiD analyses
  pretrends/        Pre-trends diagnostics (Roth 2022, Rambachan & Roth 2023)
  diagnostics/      Debugging and diagnostic tools
  exploratory/      Exploratory analyses (dose-response, maturation, adoption)
  visualization/    Plotting scripts
R/power/            Blinded power-simulation framework (9 modules)
config/             power_*.yml configs for the blinded framework
data/
  raw/              Source CSVs (eviction data, gambling legalization dates)
  processed/        Cleaned panels, schedules, QA tables
data_prep/          Data merging and preparation scripts
scripts/            Shell scripts for running analyses
patches/            Fixes for bugs in the `did` R package (CS-DiD)
utils/              Shared utilities (treatment schedule, universe helpers)
docs/               Methodology write-ups; findings-archive/ holds history
output/             Analysis outputs (LIVE runs at top level; deprecated/ below)
output_blinded_power/  Blinded power-sim outputs (gitignored; deprecated/ below)
figures/            Generated plots
quality_reports/    Memos, reviews, plans, session logs, cleanup inventories
deprecated/         Root-level relics and pre-slim CLAUDE.md
Literature/         Reference papers (PDFs)
did/                Patched copy of the `did` package (Callaway & Sant'Anna)
DRDID-master/       Patched copy of DRDID (doubly-robust DiD)
fastglm-master/     Fast GLM dependency
della_power_upload/ Cluster package for Princeton Della
```

## Critical Files

- `power_simulation_cs.R` — core simulation engine; defines `cfg`, `load_panel()`, `make_treat_schedule()`, `build_untreated_sample()`. Sourced by many analysis and plot scripts.
- `R/power/` — blinded power framework: `load_blinded_panel.R`, `run_scenario_grid.R`, `run_estimators.R`, `adaptive_mde.R`, `make_pseudo_schedules.R` etc. Configs in `config/power_*.yml`.
- `analysis/pretrends/pretrends_statepanel_template.R` — pre-trends pipeline: CS-DiD (analytic + bootstrap) + Sun-Abraham on the same sample, Holm-adjusted joint tests, optional covariate conditioning (`COVARIATES` env var), optional self-test calibration. Run via `scripts/run_pretrends_statepanel.sh`.
- `analysis/main/lpdid_statepanel.R` — real-data LP-DiD event studies (post-2026-08-24 corrected weights).
- `utils/eviction_treatment_schedule.R` — treatment schedule loader + **canonical adoption-universe helpers**: `EVICTION_STATE_UNIVERSE`, `PRE_PASPA_SPORTS_BETTING`, `eviction_adoption_outcomes()`, `eviction_control_states()`, `assert_no_pre_paspa_controls()`. Use them; never re-derive the universe or the NV rule in a script (`sports_gambling_legalization_dates.csv` has ABSENT rows, not NA, for never-legalizers — a naive join silently drops 13 states).
- `patches/att_gt_safe.R`, `patches/reg_did_rc_safe.R` — safe wrappers around CS-DiD / DRDID that avoid segfaults on non-identifiable cells.
- `data_prep/rebuild_state_month_panel.R` — the state-panel rebuild (single consistent source per state; idempotent).
- `data_prep/build_shift12_schedule.R` — the shift12 (launch + 12 months) treatment schedule; uses no outcome data.

## Data

- Panel data: county-month eviction filings (2016–2026) from **LSC CCDI plus merged court sources** (NOT the Eviction Tracking System); primary file `data/raw/monthly_county_data_download.csv` (**no NV rows — county-level work is NV-immune**).

> **`monthly_county_data_download.csv` IS A HYBRID FILE. Read this before touching it or reasoning about a fresh LSC pull.**
> It began as an LSC CCDI download, but court-source series were merged into it, and since 2026-09-17 it also carries **LSC-site months the bulk download does not have**. As of 2026-09-17 evening the local file holds **130,927 rows** to the bulk download's 120,357: **NC 2023-07→2026-06 (3,600 rows, NC AOC Summary Ejectment)**, and **7,082 rows for 2025-10→2026-06 scraped from LSC's own per-county pages** (`data_prep/pull_lsc_site_county_month.R`; the bulk CSV LSC serves ends 2025-09 for every state, the site runs to 2026-06). ME's court rows were removed from this file on 2026-09-17 (Maine is spliced at the state-panel level by `add_me_to_state_panel.R`); since 2026-10-19 the court input is the per-page-header parse of the ref-2026-09-18 report, through 2026-08). LSC's own NC series ends 2023-06.
> - **Re-downloading it is destructive, not a refresh.** It deletes NC 2023-07→2026-06 and every 2025-10+ month. To refresh LSC, run `pull_lsc_site_county_month.R` then `append_lsc_site_months.R` (append-only; revisions to existing keys are audited, never applied silently). Both states are switchers under the inclusion rule, and NC's entire outcome window (2025-03→2026-03) lives in the locally-added range.
> - **A fresh LSC pull missing those rows is NOT a retraction.** LSC never published them. This has been misread as a retraction more than once (most recently 2026-09-17).
> - The state panel's `panel_source` now says `nc_aoc_summary_ejectment` / `me_judicial_branch_fed` on those rows. Before 2026-09-17 they inherited `county_download_fixed_basket`, i.e. the data asserted the wrong provenance — that mislabel was the proximate cause of the misreadings.
> - Full record: [docs/DATA_PROVENANCE.md](docs/DATA_PROVENANCE.md) §1 correction (2026-09-14); per-state provider table: [docs/STATE_SOURCES.md](docs/STATE_SOURCES.md).
- State-month panel: `data/raw/state_month_panel_with_treatment.csv` — **rebuilt 2026-08-20** (one consistent source per state; pre-rebuild file was a 12-state double count, preserved in `data/raw/deprecated/`); **extended 2026-08-28** with per-state basket starts (adds CO/HI/MS/NY/SC — 39 states; prior state-months unchanged; global-basket vintage preserved in `data/raw/deprecated/`); **rebuilt/extended again 2026-09-14** to **42 states / 4,304 rows** (single-series rebuild of LA/MA/MO/NM/NV/RI, ramp censor, + OR + WA + MI, trailing-partial censor, ID swapped from the Twin Falls LSC basket to the statewide Idaho Judicial Branch series 2021-01..2026-06 — ID has no pre-2021 months). Columns include `n_counties`, `basket_share`; composition QA in `data/processed/state_panel_coverage_qa.csv` — check it before citing any state-level estimate.
- Treatment schedule: `data/raw/sports_gambling_legalization_dates.csv` — **repaired 2026-08-10** (added online dates for DE/NC/KY/ME/FL/VT/MO; ME/VT/KY/FL are no longer never-treated). Never-legalizers have NO row (absent, not NA). NV is absent because it is **always-treated** (legal since 1949) — exclude it from every state-level control pool via the universe helpers.
- shift12 schedule: `data/processed/shift12_schedule.csv` (launch + 12 months, blind to outcomes).
- Gambling amounts: `data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv` — monthly Handle/Revenue by state (June 2018+, starts per-state at legalization; full state names, NOT per-capita).
- Mortgage delinquency: `data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv` — state-month % 90+ days late, wide format.
- Annual court panel: `/Users/bb1806/Documents/Court Data/county_court-issued_2000_2025_ben_update_3_19.csv` (county-year; used by the 2×2 long-difference work).
- `cfg$data_dir = "data/raw"` in `power_simulation_cs.R`; `cfg$panel_choice = "counties"` is the default.
- COVID drop window in most specs: 2020-03 to 2021-07 (or 2022-03 in older specs — check the run's config). The COVID splice is a first-order design fact; see FINDINGS.md §5.

## Running the Analysis

```r
# Install dependencies
source("INSTALL_PACKAGES.R")
```

```bash
# Pre-trends pipeline (CS-DiD + SunAb, recommended)
bash scripts/run_pretrends_statepanel.sh

# Mortgage delinquency pretrends (alternative outcome; NV re-run still pending — see FINDINGS.md §6)
bash scripts/run_pretrends_mortgage.sh

# Blinded power framework (local): Rscript with a config
Rscript -e 'source("R/power/run_scenario_grid.R"); run_from_config("config/power_lpdid_shift12_gate_vwatt.yml")'
# Cluster runs: della_power_upload/ + scripts/della_power/ (see its README.txt)
```

Working directory for all scripts is the **project root**.

## Blinded Power-Simulation Framework (Pre-Analysis Plan)

Blinded (untreated-data-only) calibration + power simulation supporting the Arnold Ventures PAP. Code: `R/power/`. Configs: `config/power_*.yml`. Methodology: `docs/methodology/POWER_SIMULATION_{DESIGN,BLINDNESS_PROTOCOL,CODE_AUDIT}.md`. Cluster package: `della_power_upload/` (rebuilt by `scripts/make_della_power_upload.sh`).

**PAP decision rule** (pre-registered): (1) size gate — any estimator × level cell whose δ=0 rejection is materially off nominal is disqualified; (2) MDE among survivors picks the headline spec. Current gate results and MDEs: **FINDINGS.md §2**.

Key mechanics (stable — do not re-derive):
- `seed_rep = base_seed + 10007*rep + 101*scenario`, `base_seed = 20260723`, shared across configs → later runs see identical simulated panels rep-for-rep (paired comparisons), **but only within the same panel/schedule vintage** (ids hash settings, not data — fresh `run_name` after any data edit).
- Scenario ids are content hashes of the scenario's own settings → resubmitting skips completed partials; non-default values of conditionally-hashed knobs change ids. **Exception:** `lpdid_weights` inverts the rule — the new default `ewatt` is hashed, legacy `cellsize` is not (the default changed behavior).
- Config knobs to know: `lpdid_weights` (`ewatt` default | `vwatt` | `cellsize` retired), `lpdid_pmd` (base-period width, default 3), `exclude_states` (e.g. `[NV]`), `template` (`panel` vs national), `time_agg` (month/quarter/year; LP-DiD is monthly-only), `cs_safe_patches: TRUE` + `cs_faster_mode: FALSE` (both **required** for CS to actually estimate — see FINDINGS.md §5).
- `est_anticipation` is CS-only. S3 × D1 is structurally infeasible (never-treated sample too small for the full template); state D1 without NV is infeasible at the post-COVID boundary — the honest PAP statement is that that cell is not estimable.
- Run logs live inside their run's output dir; per-run provenance is `run_metadata.json`.

Full framework history (Della jobs, OOM lessons, template evolution): `docs/findings-archive/blinded-power-framework-notes_2026-08.md`.

## Known Constraints (stable)

- **State-level power constraint.** Treatment varies at the state level; inference is driven by the number of state clusters (~30 usable), not observations. County data improves calibration, not clusters.
- **Data coverage constraint.** Cluster count, not observations, is the binding power constraint. The state arm now holds **35 usable clusters** on the 42-state panel and the county arm **26** (`data/processed/county_vs_state_arm_summary.csv`, covid=drop); the county arm is LSC-only, so every non-LSC state (MD NH WI MI OR + the 7 Eviction Lab states) is state-arm-only. **County and state are run as two co-equal main specs, never pooled** — see FINDINGS §2. Of the online-gambling states once listed as monthly-less, **MD, OR and MI are now in the panel**; **NJ, IA, IL and WY are not** — NJ and IA are annual/request-only, IL's county-quarter series starts 2022 (no pre-period). Adding the rest via an annual panel would raise treated clusters and break up singleton cohorts at the cost of coarser timing (details: `docs/findings-archive/empirical-results-summary_pre-cleanup.md`).
- **Gambling intensity heterogeneity in the pretrends template does not work** — it bins on pre-treatment handle, which is zero by definition. Fix requires post-treatment handle or regulatory features as intensity.
- **Idaho** is excluded from annual analyses (data quality; it is the single most extreme state in 100% of pre-era variance placements).
- **Interpretation discipline.** Results are bounds, not precise nulls: "no evidence of effects above the MDE," never "gambling doesn't increase evictions." Current MDEs: FINDINGS.md §2.

## TO DO

Open analysis items are tracked in **FINDINGS.md §6** (mortgage power-sim reconciliation, mortgage pretrends NV re-run, LDAM MDE, boundary_B finalization, TWFE staggered power re-run on the repaired schedule). Standing infrastructure items:

- [ ] Add per-batch checkpoint/resume to `R/power/run_scenario_grid.R` and raise `--time`/`--mem` before resubmitting any county+CS Della run (the 2026-08-08 primary run lost ~42h of work to an OOM with no checkpointing).
- [ ] Drop S3 from `power_primary.yml` D1 blocks (structurally infeasible) and decide whether to promote a D4 never-treated block into primary.
- [ ] Draft the Arnold PAP: port design sections from `Arnold Housing Loss Gambling - Application.docx`; estimator selection as the calibration-gate decision rule; power section from the blinded framework with MDEs in filings-per-year terms; key modeling decisions (COVID window, log(1+y), treatment date defs, balance rules, state exclusions). Drafts: `preanalysis plan v1.1.docx`.
- [ ] Migrate `analysis/cheap_sims/11_exposure_time_vs_intensity.R` from its inline `state_abb != "NV"` to the shared `PRE_PASPA_SPORTS_BETTING` constant.
- [ ] Build an annual panel merging ETS (aggregated to annual) + Court Data states for a 30+ state robustness check (the 7-state table: `docs/findings-archive/empirical-results-summary_pre-cleanup.md`).
- [ ] Run CS calibration on that annual panel to test whether multi-state cohorts fix the het.-robust estimator problem.
- [ ] Consider sourcing monthly court data directly from state court systems (NJ Courts, Michigan SCAO, Iowa Judicial Branch) for online-gambling states without monthly ETS coverage.
- [ ] Run a Goodman-Bacon (2021) decomposition on TWFE to quantify the negative-weight concern (TWFE's known staggered-design caveat; less concerning for a null result).

## Bundled R Packages (`did/`, `DRDID-master/`, `fastglm-master/`)

Local patched copies fixing critical bugs:

- **`did` v2.3.0** (Callaway & Sant'Anna) — `att_gt()` group-time ATTs. Patched: p-value computation (`FIX_cs_pvalue_computation.patch`), unbalanced-panel handling (`FIX_unbalanced_panel.patch`, `FIX_allow_unbalanced.patch`), estimation-method selection (`FIX_cs_simulation_est_method.patch`), empty-matrix segfaults.
- **`DRDID` v1.2.3** (Sant'Anna & Zhao 2020) — doubly-robust DiD; `patches/reg_did_rc_safe.R` guards `fastglm()` calls, returns NA for non-identifiable cells instead of crashing. Note: `did` imports `reg_did_rc` by value AND calls it unqualified under `faster_mode=TRUE` — a patch must rebind in **both** namespaces.
- **`fastglm` v0.0.4** — RcppEigen GLM; crashes on 0-row design matrices (root cause of the segfaults).

## Safety Wrappers & Patches (`patches/`)

| File | Description |
| ---- | ----------- |
| `att_gt_safe.R` | Safe wrapper around `did::att_gt()` with preflight support check |
| `preflight_support_check.R` | Computes (g,t) cell support BEFORE estimation; flags non-identifiable cells |
| `reg_did_rc_safe.R` | Patched DRDID function with guards before every `fastglm()` call |
| `plot_csdid_pretrends.R` | Plotting: event study, pre-trends tests, group dynamics, support heatmap |
| `FIX_*.patch` | The four `did`-package patches listed above |

## R Econometrics Methodology

### Estimators (descriptions; current calibration verdicts live in FINDINGS.md §4)

1. **TWFE** — `fixest::feols()`, unit + time FE, state-clustered SEs; wild cluster bootstrap for inference where analytic size is off.
2. **LP-DiD** (Dube, Girardi, Jordà & Taylor) — `.re_lpdid` in `R/power/run_estimators.R`; `lpdid_weights`: `ewatt` (equally-weighted ATT = CS's estimand; first-lag reweighted LP-DiD ≡ CS on contiguous panels), `vwatt` (Cengiz-style stack), `cellsize` (retired — accidental hybrid, dead estimand). Cross-checked exactly against Girardi's reference implementation (`tests/testthat/test-estimators.R`).
3. **CS-DiD** (Callaway & Sant'Anna 2021) — `did::att_gt()`; requires `cs_safe_patches=TRUE`, `cs_faster_mode=FALSE`. Breaks on interior time gaps (the COVID splice) — it consecutive-indexes months.
4. **Sun-Abraham** — `fixest::sunab()`.
5. **did2s** (Gardner 2022) — county-level workhorse.
6. **didimputation** (BJS 2024) — county robustness only.
7. **LDAM** (autoregressive panel) — jackknife inference only; analytic is catastrophically miscalibrated.

### Inference Methods

- Cluster-robust SEs at state level (primary); **wild cluster bootstrap** (`fwildclusterboot` — CRAN-archived, install from the s3alfisc r-universe; pass `fe = "id"` to `boottest()` on county panels or it dummy-expands ~1,200 FEs); CS multiplier bootstrap; LDAM jackknife.

### Pre-trends Testing

- **Roth (2022)** power analysis; **Rambachan & Roth (2023)** `HonestDiD` sensitivity; equivalence testing (Hartman & Hidalgo 2018). Pipeline: `analysis/pretrends/pretrends_statepanel_template.R`. Watch the SunAb coefficient mask — it must be `^[^:]+::-?[0-9]+$` so covariate interactions `i(t, X)` aren't swept into the event study.

## Common Tasks

- **Fix broken paths**: scripts use paths relative to project root; a moved deprecated artifact's new location is in MOVES.md.
- **Add a new analysis**: source `power_simulation_cs.R` for `load_panel(cfg)` etc., or `R/power/load_blinded_panel.R` for the blinded framework. Then add its ledger row.
- **Modify treatment definition**: `treat_def` in the blinded framework accepts `online` / `maturation50` / `ramp75` / `shift12`; `cfg$treat_date_col` in `power_simulation_cs.R` for the legacy engine.

## Requirements

- R >= 4.0
- Core: tidyverse, fixest, lubridate, did, glue, patchwork
- Estimators: did2s, didimputation; wild bootstrap: fwildclusterboot (r-universe)
