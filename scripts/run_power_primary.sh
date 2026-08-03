#!/usr/bin/env bash
# =============================================================================
# scripts/run_power_primary.sh
#
# Runs the PRIMARY scenario grid of the blinded power simulation
# (config/power_primary.yml; POWER_SIMULATION_DESIGN.md §§5-12).
#
# Env vars:
#   N_WORKERS  parallel workers (default: availableCores() - 2)
#   RUN_NAME   output subdir under output_blinded_power/ (default: "primary";
#              keep it stable to allow checkpoint/resume)
#   RESUME     TRUE (default) to skip scenarios with complete partials
#   SCENARIOS  optional comma-separated subset: scenario indices (1-based),
#              block names, or scenario ids. Empty (default) = whole grid.
#              A subset run writes per-scenario partials ONLY and skips the
#              run-level summaries, so several may run concurrently without
#              racing; re-run with SCENARIOS unset to aggregate. Example:
#                SCENARIOS=7,8,9,10,11 bash scripts/run_power_primary.sh
#                SCENARIOS=state_nb_step bash scripts/run_power_primary.sh
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

  sc <- Sys.getenv("SCENARIOS", "")
  sc <- if (!nzchar(sc)) NULL else {
    parts <- trimws(strsplit(sc, ",", fixed = TRUE)[[1]])
    parts <- parts[nzchar(parts)]
    # All-numeric -> positional indices; otherwise names / ids.
    if (all(grepl("^[0-9]+$", parts))) as.integer(parts) else parts
  }

  run_scenario_grid("config/power_primary.yml",
                    resume = rs, workers = w, run_name = rn, scenarios = sc)
'
