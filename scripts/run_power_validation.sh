#!/usr/bin/env bash
# =============================================================================
# scripts/run_power_validation.sh
#
# BHNS-style validation of the blinded power-simulation engine
# (POWER_SIMULATION_DESIGN.md §13). Thin wrapper around
# R/power/validate_simulation.R.
#
# Env vars: N_WORKERS (unused here — validation is serial), RUN_NAME (unused;
# validation always writes to output_blinded_power/validation/), N_REPS
# (default 25).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

Rscript --vanilla -e '
  source("R/power/config.R")
  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R")
  source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  source("R/power/validate_simulation.R")

  n_reps <- Sys.getenv("N_REPS", "25")
  out <- validate_simulation(n_reps = as.integer(n_reps))
  print(out$checks, n = Inf)
  if (!out$pass) quit(status = 1L, save = "no")
'
