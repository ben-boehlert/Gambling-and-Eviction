# Repository Cleanup Plan

## KEEP - Final Analysis Scripts

### Main Analysis
- `power_simulation_twfe_statepanel_staggered_parallel_fixed.R` - **FINAL power simulation (TWFE)**
- `power_simulation_cs_statepanel_staggered_parallel_merged.R` - Alternative CS-DiD version (has SE issues, documented)

### Analysis Scripts (Different purposes, keep all)
- `analyze_gambling_dose_response.R` - Dose-response analysis
- `analyze_gambling_dose_no_ny.R` - Sensitivity without NY
- `analyze_parallel_trends.R` - Parallel trends validation

### Plotting/Visualization
- `plot_deseasonalized_trends.R`
- `plot_event_study_deseasonalized.R`
- `plot_precovid_traditional.R`
- `plot_seasonality_results.R`

### Data Preparation
- `merge_ets_combined.R` - Merges ETS data
- `merge_ets_data.R` - Alternative merge
- `diff_county_court_issued_2025_update.R` - Recent data update

### Utilities
- `check_panel_size.R` - Diagnostic for panel structure
- `verify_merge.R` - Validates data merge
- `summarize_all_approaches.R` - Compare different methods

### Shell Scripts (Keep all - these are the replication interface)
- `run_twfe_power_no_maine_2024.sh` - Main power sim (no COVID in residual pool)
- `run_twfe_power_no_maine_2024_with_covid.sh` - Robustness with COVID
- `run_twfe_power_no_maine_2024_min5.sh` - Min 5 states variant
- `run_power_no_maine_2024.sh` - CS-DiD version (for comparison)
- `verify_script_version.sh` - Version checking utility

## DELETE - Old/Debug/Superseded Files

### Old Power Simulation Versions (superseded by TWFE version)
- `power_simulation_cs.R` - Old CS version
- `power_simulation_cs_v2.R` - Old iteration
- `power_simulation_cs_v4_1.R` - Old iteration
- `power_simulation_cs_v4_2.R` - Old iteration
- `power_simulation_cs_v4_3.R` - Old iteration
- `power_simulation_cs_v4_5.R` - Old iteration
- `power_simulation_cs_v4_6_logcounts_heatmap80.R` - Old iteration
- `power_simulation_cs_ets_merged_bestof.R` - Old ETS version
- `power_simulation_cs_ets_merged_unified.R` - Old ETS version
- `power_simulation_cs_ets_merged_v46like.R` - Old ETS version
- `power_simulation_cs_ets_merged_v5final_parallel.R` - Old ETS version
- `power_simulation_cs_ets_merged_v5style.R` - Old ETS version
- `power_simulation_cs_statepanel_staggered_parallel_boot_ar1.R` - Old AR1 version
- `power_simulation_cs_statepanel_staggered_parallel_boot_ar1_fixed.R` - Old AR1 version
- `power_simulation_cs_statepanel_staggered_parallel_fixed2 (5).R` - Superseded by merged version
- `power_simulation_main.R` - Old main file
- `eviction_gambling_power_analysis.R` - Old version
- `eviction_power_analysis_SAFE.R` - Old safe version
- `power_analysis_NO_TIDYVERSE.R` - Old version
- `power_sensitivity_and_plots.R` - Old version
- `did_power_analysis.R` - Old version
- `simple_power_simulation.R` - Old simple version
- `formula_based_power.R` - Old formula version
- `power_simulation_precovid_config.R` - Old config

### Test Files (delete unless needed for CI/CD)
- `test_*.R` (all 26 test files) - Debug/development tests
- `quick_test.R`
- `quick_test_grid.R`
- `run_quick_power_test.R`

### Debug Files
- `DEBUG_SIMULATION.R`
- `debug_*.R` (all debug files)
- `diagnose_*.R` (all diagnose files)
- `check_inffunc.R`
- `check_missing_data.R`
- `check_warnings.R`
- `check_variance.R`
- `check_simulation.R`
- `debug_effect.R`
- `trace_warning.R`

### Old Analysis Files (superseded)
- `Combined_Panel_Analysis.R`
- `Drop-in.R`
- `FIX_AND_RUN.R`
- `FIX_AND_RUN_V2.R`
- `Fixed_SA_DiD.R`
- `Normal SA.R`
- `Weird SA.R`
- `More gambling eviction.R`
- `Third File.R`
- `gambling_eviction_analysis (1).R`
- `RUN_ALL_ANALYSES.R`
- `RUN_MINIMAL.R`
- `RUN_SAFE.R`
- `WORKING_SIMULATION.R`

### Utilities/Setup (keep or delete based on need)
- `INSTALL_PACKAGES.R` - Could keep for replication
- `build_panels_WORKING.R` - Delete if data already built
- `fix_state_mapping.R` - Delete if fixed
- `shinyApp.R` - Delete unless using Shiny
- `more_tests.R` - Delete

### Test Utilities (likely delete)
- `test_month_fe_full_period.R`
- `test_postcovid_parallel_trends.R`
- `test_seasonality.R`

## Recommended File Structure After Cleanup

```
/
├── analysis/
│   ├── power_simulation_twfe_statepanel_staggered_parallel_fixed.R (MAIN)
│   ├── power_simulation_cs_statepanel_staggered_parallel_merged.R (ALTERNATIVE)
│   ├── analyze_gambling_dose_response.R
│   ├── analyze_gambling_dose_no_ny.R
│   └── analyze_parallel_trends.R
├── data_prep/
│   ├── merge_ets_combined.R
│   ├── merge_ets_data.R
│   └── diff_county_court_issued_2025_update.R
├── plots/
│   ├── plot_deseasonalized_trends.R
│   ├── plot_event_study_deseasonalized.R
│   ├── plot_precovid_traditional.R
│   └── plot_seasonality_results.R
├── utils/
│   ├── check_panel_size.R
│   ├── verify_merge.R
│   └── summarize_all_approaches.R
├── scripts/ (shell scripts for replication)
│   ├── run_twfe_power_no_maine_2024.sh
│   ├── run_twfe_power_no_maine_2024_with_covid.sh
│   ├── run_twfe_power_no_maine_2024_min5.sh
│   ├── run_power_no_maine_2024.sh
│   └── verify_script_version.sh
├── data/
│   └── (your CSV files)
├── README.md
└── INSTALL_PACKAGES.R (optional)
```

## Estimated Cleanup: DELETE ~70 files, KEEP ~20 files
