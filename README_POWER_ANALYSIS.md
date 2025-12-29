# Simulated Power Analysis: Sports Gambling → Eviction Filings

## Overview

This analysis implements a simulated power calculation following:
- **Black, Hollingsworth, Nunes & Simon (2021)**: Simulated power analysis methodology
- **Burlig, Preonas & Woerman (2020)**: Serial-correlation-robust panel data design
- **Repository**: hollina/health_insurance_and_mortality (simple_power_example.do)

## Methodology

### Data Sources
1. **monthly_county_data_download.csv**: County-level eviction filings
2. **all_sites_monthly_2020_2021.csv**: Eviction Lab site-level data
3. **sports_gambling_legalization_dates.csv**: Treatment timing

### Key Steps
1. **Panel Construction**: Aggregated to state-month level, calculated filings per 1,000 renters
2. **Error Calibration**: Used ONLY untreated months (never-treated + pre-adoption)
3. **Assignment Schemes**:
   - **A**: Random treated states with common post-period
   - **B**: Staggered adoption (permuted actual dates)
4. **Bootstrap**: Moving-block to preserve within-state autocorrelation
5. **Estimation**: `Y ~ D | state + month` with cluster-robust SE
6. **Metrics**: Power, MDE, sign error rate, magnitude error rate (>2× truth)

### Sensitivity Analyses
- Panel length: +6, +12, +24 months
- Number of states (clusters)
- Bootstrap block length

## Key Results

Analysis in progress or incomplete. Run the full analysis to see results.


## Files

### Scripts (run in order)
1. `eviction_gambling_power_analysis.R` - Data prep & error calibration
2. `power_simulation_main.R` - Main simulations
3. `power_sensitivity_and_plots.R` - Sensitivity & visualization
4. `RUN_ALL_ANALYSES.R` - Master script (runs all)

### Output
**Data:**
- `eviction_gambling_power_workspace.RData`
- `power_simulation_results.RData`

**Results:**
- `power_results_scheme_a.csv`
- `power_results_scheme_b.csv`
- `sensitivity_*.csv`

**Tables:**
- `table_main_results.csv`
- `table_mde_summary.csv`

**Plots:**
- `plot_power_curves.png` - Main power curves
- `plot_error_rates.png` - Sign/magnitude errors
- `plot_panel_length_sensitivity.png`
- `plot_n_states_sensitivity.png`
- `plot_combined_sensitivity.png` - 4-panel summary

## References

1. Black, Hollingsworth, Nunes & Simon (2021). "Simulated power analyses for observational studies: An application to the Affordable Care Act Medicaid expansion."

2. Burlig, Preonas & Woerman (2020). "Panel data and experimental design." *Journal of Development Economics*, 144, 102458.

3. Repository: https://github.com/hollina/health_insurance_and_mortality
   - See `simple_power_example.do` (lines 1-665)

4. Gelman & Carlin (2014). "Beyond power calculations." *Perspectives on Psychological Science*.

## Generated

Date: %s
Directory: %s

Date: December 24, 2025
Directory: /Users/bb1806/Documents/eviction_gambling

