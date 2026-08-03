#!/usr/bin/env bash
# =============================================================================
# scripts/run_power_sensitivity.sh
#
# Runs the SENSITIVITY scenario grid of the blinded power simulation
# (config/power_sensitivity.yml; POWER_SIMULATION_DESIGN.md §§5-12, §15
# fragility screen).
#
# Env vars:
#   N_WORKERS  parallel workers (default: availableCores() - 2)
#   RUN_NAME   output subdir under output_blinded_power/ (default:
#              "sensitivity"; keep it stable to allow checkpoint/resume)
#   RESUME     TRUE (default) to skip scenarios with complete partials
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

  w  <- Sys.getenv("N_WORKERS", ""); w  <- if (nzchar(w)) as.integer(w) else NULL
  rn <- Sys.getenv("RUN_NAME", "");  rn <- if (nzchar(rn)) rn else NULL
  rs <- toupper(Sys.getenv("RESUME", "TRUE")) != "FALSE"

  run_scenario_grid("config/power_sensitivity.yml",
                    resume = rs, workers = w, run_name = rn)
'
