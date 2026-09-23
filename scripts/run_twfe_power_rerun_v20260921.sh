#!/bin/bash
################################################################################
# run_twfe_power_rerun_v20260921.sh
#
# Re-run of the application-era naive TWFE staggered power sim on the CURRENT
# vintage: rebuilt 42-state panel (boundary 11), repaired schedule (online
# launch dates), NV excluded as always-treated. Closes the FINDINGS.md §6 item.
#
# Two error modes, otherwise identical:
#   iid_month  the original DGP (shocks redrawn independently every month)
#   ar1        within-state AR(1) shocks, rho estimated from untreated residuals
#
# Blind by construction: the sim fits FE and draws residuals from untreated
# observations only, and never estimates anything on real post-treatment data.
#
# Run from the project root:
#   bash scripts/run_twfe_power_rerun_v20260921.sh
################################################################################

set -euo pipefail

RUN_ROOT="output/twfe_power_rerun_v20260921"
Rscript --vanilla analysis/main/prep_twfe_power_rerun_inputs.R "$RUN_ROOT/inputs"

export DATA_FILE="$RUN_ROOT/inputs/data_state_rows.csv"
export TREAT_FILE="$RUN_ROOT/inputs/treat_state_month.csv"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.03,0.05,0.08,0.10,0.12,0.15,0.20}"
export N_WORKERS="${N_WORKERS:-6}"
export BATCH_SIZE="${BATCH_SIZE:-50}"
export EXCLUDE_START="${EXCLUDE_START:-2020-03-01}"
export EXCLUDE_END="${EXCLUDE_END:-2021-06-01}"

for mode in iid_month ar1; do
  export ERR_MODE="$mode"
  export OUT_DIR="$RUN_ROOT/$mode"
  echo "=== ERR_MODE=$mode -> $OUT_DIR ==="
  Rscript --vanilla analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R
done
