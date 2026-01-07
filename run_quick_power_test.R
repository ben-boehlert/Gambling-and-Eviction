#!/usr/bin/env Rscript
################################################################################
# run_quick_power_test.R
# Quick test run with just 10 simulations to verify everything works
################################################################################

# Define cfg for panel loading
cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
  outcome_preference = c("filings_per_1k_renters", "filings_count_per_1k_renters"),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date"
)

# Define config BEFORE sourcing
# This will override the default config in simple_power_simulation.R
config <- list(
  period = "precovid",
  n_sims = 10,
  effect_sizes = c(0, 1.5, 3.0),
  alpha = 0.05,
  target_power = 0.80,
  n_bootstrap = 20,
  control_group = "nevertreated",
  output_file = "quick_power_test.csv"
)

cat("=== Quick Power Simulation Test ===\n")
cat("This will run 10 simulations at 3 effect sizes\n")
cat("Expected runtime: ~5 minutes\n\n")

# Source the main script
source("simple_power_simulation.R")

cat("\n=== Test Complete ===\n")
cat("If you see results above, the simulation works!\n")
cat("Now you can run the full version:\n")
cat("  1. Edit simple_power_simulation.R to set n_sims = 500\n")
cat("  2. Run: Rscript simple_power_simulation.R\n")
cat("  3. Wait ~2-3 hours for final results\n")
