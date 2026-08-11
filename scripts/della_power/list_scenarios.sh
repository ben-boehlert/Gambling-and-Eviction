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

# R is not on PATH by default on module-based clusters, and a `module load`
# run inside another script (e.g. run_validation.sh) does NOT persist to your
# interactive shell — so this script has to load R itself. On a laptop with R
# already on PATH the whole block is a no-op.
if ! command -v Rscript >/dev/null 2>&1; then
  # `module` is a shell function, not a binary, so it may not exist in a
  # non-interactive shell until the modules init is sourced.
  if [ -n "${MODULESHOME:-}" ] && [ -f "$MODULESHOME/init/bash" ]; then
    # shellcheck disable=SC1091
    . "$MODULESHOME/init/bash"
  fi
  if command -v module >/dev/null 2>&1; then
    module load R/4.4.2 || true
  fi
fi
if ! command -v Rscript >/dev/null 2>&1; then
  echo "list_scenarios.sh: Rscript not found." >&2
  echo "  On Della:  module load R/4.4.2" >&2
  exit 1
fi

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
            "mechanism", "shape", "outcome", "est_anticipation", "template")
  print(as.data.frame(grid[, cols]), row.names = FALSE)
  cat("\nscenario ids (partial filenames):\n")
  cat(paste0("  ", grid$scenario_index, "  ", grid$scenario_id, collapse = "\n"),
      "\n")
  cat(sprintf("\n%d scenarios  ->  set  #SBATCH --array=1-%d\n",
              nrow(grid), nrow(grid)))
'
