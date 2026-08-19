#!/usr/bin/env bash
# ============================================================================
# run_power_county_cs_adaptive.sh — county CS adaptive MDE search
#
# Adaptive successor to run_power_county_cs.sh (shift mode barred for the
# headline CS MDE by the 2026-08-18 review). Null calibration (250 reps at
# delta = 0) runs first; the MDE search only starts for inference arms that
# pass the [2.5%, 10%] size gate. Fully resumable: re-running this script
# continues from the .done_cells checkpoint.
#
# Usage:  N_WORKERS=6 bash scripts/run_power_county_cs_adaptive.sh
# Output: output_blinded_power/county_cs_adaptive/
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

: "${N_WORKERS:=6}"

Rscript - <<EOF
source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/make_pseudo_schedules.R")
source("R/power/impose_effects.R")
source("R/power/run_estimators.R")
source("R/power/summarize_operating_characteristics.R")
source("R/power/run_scenario_grid.R")
source("R/power/adaptive_mde.R")
run_adaptive_mde("config/power_county_cs_adaptive.yml",
                 workers = ${N_WORKERS}, resume = TRUE)
EOF
