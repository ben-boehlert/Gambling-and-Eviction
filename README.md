# Sports Gambling and Eviction Rates: Replication Package

This repository contains code and data for analyzing the effect of sports gambling legalization on eviction rates using staggered difference-in-differences methods.

## Quick Start

```bash
cd scripts
./run_twfe_power_no_maine_2024.sh
```

## Documentation

- **[Documentation Index](docs/README.md)** - Complete documentation navigation
- **[Complete Replication Guide](docs/README_REPLICATION.md)** - Full instructions for reproducing all analyses
- **[Quick Start Guide](docs/QUICK_START_GUIDE.md)** - Get started quickly
- **[Power Analysis Summary](docs/POWER_ANALYSIS_SUMMARY.md)** - Overview of power simulation results
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Blinded Power-Simulation Framework (Pre-Analysis Plan)

A separate, blinded power-simulation framework (`R/power/`) supports the project's pre-analysis
plan by evaluating candidate research designs on **untreated data only**, with known effects
imposed of sizes drawn from external literature — never from this project's own estimates. Start
here:

- **[Blindness Protocol](docs/methodology/POWER_SIMULATION_BLINDNESS_PROTOCOL.md)** - What may and
  may not be used, cutoffs, automated enforcement
- **[Simulation Design](docs/methodology/POWER_SIMULATION_DESIGN.md)** - Estimand, calibration
  samples, pseudo-treatment designs, effect grid (with sources), decision rule
- **[Code Audit](docs/methodology/POWER_SIMULATION_CODE_AUDIT.md)** - What existed before this
  framework and what it reuses/deprecates
- **[Pre-Analysis Plan Language](docs/methodology/PRE_ANALYSIS_PLAN_POWER_LANGUAGE.md)** - Draft
  PAP text, to be filled in only from blinded simulation output

Run it:
```bash
Rscript tests/run_tests.R                     # unit tests (must pass first)
bash scripts/run_power_validation.sh          # small BHNS-style validation
bash scripts/run_power_primary.sh             # primary candidate specifications
bash scripts/run_power_sensitivity.sh         # full sensitivity grid
```
All outputs are written to `output_blinded_power/` (gitignored, regenerable) and never mixed
with `output/` or `figures/`.

## Repository Structure

```
analysis/       Main power simulation and analysis scripts (see analysis/README.md)
  ├─ main/          Primary analyses (TWFE and CS-DiD power simulations)
  ├─ pretrends/     Pre-trends diagnostics and evaluation
  ├─ data_prep/     Data preparation scripts
  ├─ visualization/ Plotting scripts
  ├─ diagnostics/   Debugging and diagnostic tools
  └─ exploratory/   Exploratory analyses
data_prep/      Original data merging and preparation scripts
plots/          Visualization utility scripts
utils/          Diagnostic and utility tools
scripts/        Shell scripts for replication (START HERE); also run_power_*.sh (blinded framework)
data/           Data files (raw inputs and outputs)
docs/           Documentation (see docs/README.md)
  └─ methodology/ Detailed methodology documentation, incl. POWER_SIMULATION_* (blinded framework)
figures/        Generated visualizations
patches/        CS-DiD package bug fixes (see patches/README.md)
R/power/        Blinded power-simulation framework (config, loader, schedules, effects,
                 estimators, OC summarizer, validation, scenario-grid runner)
config/         Power-simulation scenario configs (power_validation/primary/sensitivity.yml)
tests/          testthat suite for the power-simulation framework (tests/run_tests.R)
output_blinded_power/  Power-simulation outputs only (gitignored; never output/ or figures/)
```

## Recent Updates

- **CS-DiD Issues Documented**: Critical bugs discovered in the `did` package during development. See [patches/](patches/) for fixes and [docs/methodology/CS_DID_PVALUE_FIX.md](docs/methodology/CS_DID_PVALUE_FIX.md) for detailed analysis
- **Modern Pre-trends Methods**: Implemented Roth (2022) and Rambachan & Roth (2023) diagnostics for robust pre-trends evaluation
- **Activity-Based Treatment**: Alternative treatment timing using gambling handle data shows 66% improvement in pre-trends F-statistic (see [docs/methodology/ACTIVITY_BASED_TREATMENT.md](docs/methodology/ACTIVITY_BASED_TREATMENT.md))

## Main Results

Using TWFE with proper cluster-robust standard errors (2016-2024, excluding Maine):

- **Without COVID in residual pool**: 80% power to detect 5% effect (MDE = 5 log points)
- **With COVID in residual pool**: 80% power to detect 8% effect (MDE = 8 log points)

## Requirements

- R (≥ 4.0)
- Required packages: `dplyr`, `readr`, `glue`, `fixest`, `tibble`, `parallel`
- Optional: `did` (for Callaway-Sant'Anna comparison)

Install dependencies:
```R
source("INSTALL_PACKAGES.R")
```

## Research Archive

The [archive/](archive/) directory (excluded from GitHub via .gitignore) contains diagnostic notes and research process documentation showing how methodological issues were identified and resolved. This material demonstrates the rigorous investigation conducted during development but is not required for replication.

## Contributing

This is a research replication package. For questions about methodology or data, please open an issue.

## Citation

[Add citation here]

## License

[Add license here]
