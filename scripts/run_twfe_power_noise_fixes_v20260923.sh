#!/usr/bin/env bash
# Application-era AR(1) TWFE sim with the 2026-09-23 noise fixes, one at a time.
# Same inputs/settings as twfe_power_rerun_noMNWA_v20260922 (ar1), finer grid.
#   (a) base          application setup (reproduction check)
#   (b) statesd       ERR_SCALE=state_month  -- each state's own residual sd
#   (c) nocovid       COVID window dropped from the estimation panel too
#   (d) both          (b) + (c)
#   (e) both_renters  (d) + UNIT_WEIGHTS=renters
# Run from the project root:  bash scripts/run_twfe_power_noise_fixes_v20260923.sh
set -euo pipefail
R=output/twfe_power_noise_fixes_v20260923
export DATA_FILE=output/twfe_power_rerun_v20260921/inputs/data_state_rows.csv
export TREAT_FILE=output/twfe_power_rerun_v20260921/inputs/treat_state_month.csv
export N_SIMS=2000 N_WORKERS=6 BATCH_SIZE=50 ERR_MODE=ar1 EXCLUDE_STATES=WA,MN
export EFFECT_PCTS=0,0.03,0.04,0.05,0.06,0.07,0.08,0.10,0.12,0.15,0.20
export EXCLUDE_START=2020-03-01 EXCLUDE_END=2021-06-01
run() { local tag=$1; shift; echo "=== $(date '+%T') $tag"; env "$@" OUT_DIR="$R/$tag" \
  Rscript --vanilla analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R > "$R.$tag.stdout.log" 2>&1; }
mkdir -p "$R"
run base
run statesd      ERR_SCALE=state_month
run nocovid      DROP_START=2020-03-01 DROP_END=2021-06-01
run both         ERR_SCALE=state_month DROP_START=2020-03-01 DROP_END=2021-06-01
run both_renters ERR_SCALE=state_month DROP_START=2020-03-01 DROP_END=2021-06-01 UNIT_WEIGHTS=renters
echo "=== $(date '+%T') done"
