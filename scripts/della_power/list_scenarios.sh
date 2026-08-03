#!/usr/bin/env bash
# =============================================================================
# list_scenarios.sh — print the expanded scenario table for a power config.
#
# The `--array=1-N` range in run_primary.slurm / run_sensitivity.slurm must
# match the number of rows printed here. Run this after ANY config edit that
# adds or removes a scenario block, and update the array range to match.
#
# Also prints each scenario's content hash id, which is the partial filename
# under output_blinded_power/<run>/partials/ — useful for checking which
# scenarios are already done.
#
# Usage:
#   bash list_scenarios.sh [config/power_primary.yml]
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-config/power_primary.yml}"
export LS_CONFIG="$CONFIG"

Rscript --vanilla -e '
  suppressMessages({
    source("R/power/config.R");  source("R/power/blindness_checks.R")
    source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
    source("R/power/summarize_operating_characteristics.R")
    source("R/power/run_scenario_grid.R")
  })
  cfg  <- read_power_config(Sys.getenv("LS_CONFIG"))
  grid <- expand_scenario_grid(cfg)
  cols <- c("scenario_index", "name", "level", "sample", "covid", "design",
            "mechanism", "shape", "outcome", "est_anticipation")
  print(as.data.frame(grid[, cols]), row.names = FALSE)
  cat("\nscenario ids (partial filenames):\n")
  cat(paste0("  ", grid$scenario_index, "  ", grid$scenario_id, collapse = "\n"),
      "\n")
  cat(sprintf("\n%d scenarios  ->  set  #SBATCH --array=1-%d\n",
              nrow(grid), nrow(grid)))
'
