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
- TWFE with cluster-robust SEs is the primary approach; CS-DiD is secondary/comparison
- Pre-COVID period (2016-2020) has better parallel trends than the full sample
- Idaho is excluded from annual analyses due to data quality issues
- Main finding: 80% power to detect a 5% effect (MDE = 5 log points) using TWFE without COVID in residual pool

## Common Tasks

- **Fix broken paths**: All scripts use paths relative to project root. If something can't find a file, check that `setwd()` points to the repo root.
- **Add a new analysis**: Source `power_simulation_cs.R` to get access to `load_panel(cfg)`, `make_treat_schedule()`, etc.
- **Modify treatment definition**: Edit `cfg$treat_date_col` in `power_simulation_cs.R` (options: `online_start_date`, `retail_start_date`, `first_start_date`)

## Requirements

- R >= 4.0
- Core packages: tidyverse, fixest, lubridate, did, glue, patchwork
- Optional: fwildclusterboot (for wild bootstrap inference)
