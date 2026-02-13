# CLAUDE.md - Project Guide for Claude Code

## Project Overview

Research replication package analyzing the causal effect of sports gambling legalization on eviction rates using staggered difference-in-differences (DiD) methods. This is an economics/econometrics project written primarily in R.

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
- `patches/att_gt_safe.R` — safe wrapper around CS-DiD that avoids segfaults on unbalanced panels
- `data/raw/monthly_county_data_download.csv` — primary county-level eviction data (2016-2025)
- `data/raw/sports_gambling_legalization_dates.csv` — treatment schedule (state legalization dates)

## Working Directory

All scripts assume the working directory is the **project root**. Paths like `source("power_simulation_cs.R")` and `read_csv("data/raw/...")` are relative to root.

## Data

- Panel data: county-month eviction filings (2016-2025) from the Eviction Tracking System
- Treatment: staggered sports gambling online legalization dates by state
- `cfg$data_dir = "data/raw"` in `power_simulation_cs.R` controls where data files are loaded from
- `cfg$panel_choice = "counties"` is the default and recommended panel

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

# Run pre-trends evaluation
source("analysis/pretrends/pretrends_modern.R")
```

## Key Methodological Notes

- The `did` package (CS-DiD) has known bugs with unbalanced panels — the `patches/` directory contains fixes
- Pre-COVID period (2016-2020) has better parallel trends than the full sample
- Idaho is excluded from annual analyses due to data quality issues
- Main finding: 80% power to detect a 5% effect (MDE = 5 log points) using TWFE without COVID in residual pool
- I need to add a working CS simulation because traditional TWFE does not properly capture dynamic treatment effects.
- The problem is that the CS simulation has SEs that are far too big. I almost never reject the null, even when alpha is 0.05, when the effect is 0. In this case, I should reject 5% of the time.

### Current CS threshold-sweep behavior (important)

- Script: `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` (invoked by `scripts/run_cs_power_threshold_sweep_no_maine_2024_min5.sh`)
- For each threshold, the code estimates CS once per simulation at `effect=0` (`one_cs0`), storing `att0` and `se0`.
- For nonzero effects, it does **not** re-estimate `att_gt()`; it shifts the estimate as `att = att0 + log1p(effect_pct)` and keeps `se = se0`.
- P-values are then recomputed from the shifted t-statistic using `2 * pt(-abs(att/se), df = n_states - 1)`.
- Implication: within a threshold, `sd_att`, `mean_se`, and `se_over_sdatt` are expected to be nearly identical across effect sizes; only `mean_att` and rejection rates (power) should change.

# TO DO

Create a working Callaway-Santa'Anna simulation with a 5% rejection rate when alpha=0.05 and the effect size is zero.

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

1. **CS-DiD (Callaway & Sant'Anna 2021)** — Target primary estimator
   - Implementation: `did::att_gt()` with bootstrap inference (`bstrap=TRUE`, `biters=50-199`)
   - Strength: group-time heterogeneity, avoids negative weighting, handles staggered treatment properly
   - Current issue: SEs too large, rejection rate under null far below nominal 5% — bugs being resolved (see patches)
   - Weakness: 537/875 (g,t) cells non-identifiable due to unbalanced panel; computationally expensive
   - Script: `power_simulation_cs.R`

2. **TWFE (Two-Way Fixed Effects)** — Working baseline while CS-DiD is being fixed
   - Implementation: `fixest::feols()` with unit + time fixed effects
   - Inference: cluster-robust SEs at state level (fixest default)
   - Limitation: does not properly capture dynamic treatment effects in staggered designs
   - Script: `analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`

3. **Sun-Abraham (2021)** — Available for robustness checks via `fixest::sunab()`

### Inference Methods

- **Cluster-robust SEs**: state-level clustering (`cluster_level = "state"`) — primary method
- **Wild bootstrap**: `fwildclusterboot` package — optional, for small number of clusters
- **Bootstrap (CS-DiD)**: multiplier bootstrap with 50-199 iterations

### Pre-trends Testing (Modern Methods)

- **Roth (2022)**: Power analysis for pre-trend tests — reports minimal detectable violations (MDVs) alongside p-values. Key insight: don't condition analysis on pre-test results.
- **Rambachan & Roth (2023)**: `HonestDiD` sensitivity analysis — bounded violations framework with M ∈ {0, 0.5, 1, 1.5, 2}. Tests robustness under plausible parallel trends violations.
- **Equivalence testing** (Hartman & Hidalgo 2018): provides positive evidence FOR parallel trends (not just failing to reject). Reports smallest δ* that can be ruled out.
- Script: `analysis/pretrends/pretrends_modern.R` (1200+ lines, 10+ specifications)

### Support Structure

- 37 states (Maine excluded for data quality)
- 15–18 treatment groups (depending on treatment definition: online, retail, first)
- 875 total (g,t) cells; only 338 identifiable (38.6%) due to unbalanced panel

### Power Analysis Results

- **Without COVID**: 80% power to detect 5% effect (MDE = 5 log points)
- **With COVID**: 80% power to detect 8% effect (MDE = 8 log points)
- Type I error: well-calibrated at ~5% for TWFE

## Common Tasks

- **Fix broken paths**: All scripts use paths relative to project root. If something can't find a file, check that `setwd()` points to the repo root.
- **Add a new analysis**: Source `power_simulation_cs.R` to get access to `load_panel(cfg)`, `make_treat_schedule()`, etc.
- **Modify treatment definition**: Edit `cfg$treat_date_col` in `power_simulation_cs.R` (options: `online_start_date`, `retail_start_date`, `first_start_date`)

## Requirements

- R >= 4.0
- Core packages: tidyverse, fixest, lubridate, did, glue, patchwork
- Optional: fwildclusterboot (for wild bootstrap inference)
