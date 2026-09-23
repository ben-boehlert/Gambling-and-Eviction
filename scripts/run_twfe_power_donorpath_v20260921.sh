#!/usr/bin/env bash
# Launcher for the TWFE donor-path power simulation.
# See quality_reports/plans/2026-09-21_twfe_donorpath_power_sim.md
#
# Runs, in order:
#   1. C2 reconciliation: legacy iid_month sim (500 sims) on the 'full' inputs,
#      needed by power_simulation_twfe_donorpath.R's C2 check.
#   2. Primary donor-path scenarios: full, start202206 (2000 sims each,
#      1000 sims for the wild bootstrap arm).
#   3. AR(1) parametric cross-check on start202206 (1000 sims, no wild arm --
#      the cross-check's purpose is the analytic MDE next to the donor-path one).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_BASE="output/twfe_power_donorpath_v20260921"
mkdir -p "$OUT_BASE"

N_WORKERS="${N_WORKERS:-6}"

echo "=== [1/4] C2 reconciliation: legacy iid_month sim (500 sims, full inputs) ==="
LEGACY_INPUTS="output/twfe_power_rerun_v20260921/inputs"
if [ ! -f "$LEGACY_INPUTS/data_state_rows.csv" ]; then
  Rscript analysis/main/prep_twfe_power_rerun_inputs.R "$LEGACY_INPUTS"
fi
DATA_FILE="$LEGACY_INPUTS/data_state_rows.csv" \
TREAT_FILE="$LEGACY_INPUTS/treat_state_month.csv" \
OUT_DIR="$OUT_BASE/full/_c2_iid_month_check" \
OUTCOME=log1p_filings_count \
N_SIMS=500 \
EFFECT_PCTS=0 \
SEED=123 \
N_WORKERS="$N_WORKERS" \
ERR_MODE=iid_month \
EXCLUDE_START=2020-03-01 EXCLUDE_END=2021-06-01 \
Rscript analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R

echo "=== [2/4] Primary scenario: full (donor-path, 2000 sims) ==="
SCENARIO=full ERR_MODE=donorpath N_SIMS=2000 N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" OUT_DIR="$OUT_BASE" SEED=20260921 \
  Rscript analysis/main/power_simulation_twfe_donorpath.R

echo "=== [3/4] Primary scenario: start202206 (donor-path, 2000 sims) ==="
SCENARIO=start202206 ERR_MODE=donorpath N_SIMS=2000 N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" OUT_DIR="$OUT_BASE" SEED=20260921 \
  Rscript analysis/main/power_simulation_twfe_donorpath.R

echo "=== [4/4] AR(1) parametric cross-check on start202206 (1000 sims, no wild arm) ==="
SCENARIO=start202206 ERR_MODE=ar1 N_SIMS=1000 RUN_WILD=FALSE \
  N_WORKERS="$N_WORKERS" OUT_DIR="$OUT_BASE" SEED=20260921 \
  Rscript analysis/main/power_simulation_twfe_donorpath.R

echo "=== DONE. Outputs in $OUT_BASE ==="
