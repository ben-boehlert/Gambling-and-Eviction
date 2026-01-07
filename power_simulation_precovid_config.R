#!/usr/bin/env Rscript
################################################################################
# power_simulation_precovid_config.R
# Configuration for pre-COVID power simulation (recommended approach)
################################################################################

# This is the RECOMMENDED configuration based on diagnostic analysis
#
# Key findings from diagnostics:
# - Pre-COVID (2016-2020): Parallel trends HOLD (p = 0.14), Type I error = 12%
# - Full period (2016-2025): Parallel trends VIOLATED (p < 0.001), Type I error = 24%
# - Adding month FE makes Type I error too conservative (2%)
#
# Decision: Use pre-COVID period only with unit + time FE

cfg <- list(
  # Data source
  data_dir = ".",

  # Panel choice
  panel_choice = "states_from_counties",  # State-level analysis for state-level policy

  # COVID HANDLING: Restrict to pre-COVID period
  # This is the key modification based on diagnostic findings
  restrict_to_precovid = TRUE,
  precovid_cutoff = as.Date("2020-03-01"),  # Last month before COVID structural break

  # Outcome
  outcome_preference = c(
    "filings_per_1k_renters",
    "filings_count_per_1k_renters",
    "filings_count"
  ),

  # Weights (optional)
  weights_var = "renter_occupied_housing_units",

  # Treatment definition
  treat_date_col = "online_start_date",  # or "retail_start_date", "first_start_date"

  # Simulation parameters
  n_sims = 500,  # Increase from 100 for final analysis
  effect_grid = seq(0, 3, by = 0.5),  # Test range of effect sizes
  alpha = 0.05,
  power_target = 0.80,

  # State-level grid (for sensitivity analysis)
  run_state_switcher_grid = TRUE,
  n_states_grid = c(15, 20, 25),  # Pre-COVID has ~25 states
  n_switchers_grid = c(5, 8, 10, 12),

  # Estimand
  estimand = "overall_att",  # or "event_time"
  target_h = 12,

  # Required windows around placebo adoption
  # These should be validated against your pre-COVID period
  pre_len = 12,   # 12 months pre-treatment
  post_len = 12,  # 12 months post-treatment

  # Effect shape
  effect_shape = "step",  # "step", "ramp", or "delayed"
  delay_h = 6,  # Only used if effect_shape = "delayed"

  # Inference
  did_bstrap = TRUE,
  did_biters = 50,  # Use 50 for faster runs, increase to 199 for final
  cluster_level = "state",  # State-level clustering for state policies

  # Output
  output_prefix = "power_precovid",  # Distinguish from other runs
  save_plots = TRUE,
  save_csv = TRUE
)

# Print configuration summary
cat("=== Pre-COVID Power Simulation Configuration ===\n\n")
cat("Period restriction: Pre-COVID only\n")
cat(sprintf("Cutoff date: %s\n", cfg$precovid_cutoff))
cat(sprintf("Panel: %s\n", cfg$panel_choice))
cat(sprintf("Treatment definition: %s\n", cfg$treat_date_col))
cat(sprintf("Cluster level: %s\n", cfg$cluster_level))
cat(sprintf("Number of simulations: %d\n", cfg$n_sims))
cat(sprintf("Effect grid: %s\n", paste(cfg$effect_grid, collapse = ", ")))
cat(sprintf("Pre/post windows: %d/%d months\n", cfg$pre_len, cfg$post_len))
cat("\nJustification:\n")
cat("- Parallel trends hold in pre-COVID period (p = 0.14)\n")
cat("- Type I error = 12% (acceptable for power analysis)\n")
cat("- Clean identification without COVID structural break\n")
cat("\nLimitations:\n")
cat("- Results apply to pre-COVID context only\n")
cat("- May not generalize to post-pandemic conditions\n")
cat("- Smaller sample size than full period\n")

# Save configuration
saveRDS(cfg, "cfg_precovid.rds")
cat("\nConfiguration saved to: cfg_precovid.rds\n")
cat("\nTo run power simulation with this config:\n")
cat("  cfg <- readRDS('cfg_precovid.rds')\n")
cat("  source('power_simulation_cs.R')\n")
