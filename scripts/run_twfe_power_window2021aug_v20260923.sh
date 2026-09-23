#!/usr/bin/env bash
# Application-era AR(1) TWFE sim with the COVID window ending August 2021,
# [2020-03-01, 2021-09-01), to compare with the paragraph's [2020-03-01,
# 2022-06-01) (scripts/run_twfe_power_window2022_v20260923.sh) and the
# [2020-03-01, 2021-06-01) window of the 5.5-6% run. Otherwise identical.
#   w21aug_pool       window excluded from the residual pool only
#   w21aug_nocovid    ... and dropped from the estimation panel
#   w21aug_both       ... plus ERR_SCALE=state_month
# Run from the project root:  bash scripts/run_twfe_power_window2021aug_v20260923.sh
set -euo pipefail
R=output/twfe_power_noise_fixes_v20260923
export DATA_FILE=output/twfe_power_rerun_v20260921/inputs/data_state_rows.csv
export TREAT_FILE=output/twfe_power_rerun_v20260921/inputs/treat_state_month.csv
export N_SIMS=2000 N_WORKERS=6 BATCH_SIZE=50 ERR_MODE=ar1 EXCLUDE_STATES=WA,MN
export EFFECT_PCTS=0,0.03,0.04,0.05,0.06,0.07,0.08,0.10,0.12,0.15,0.20
export EXCLUDE_START=2020-03-01 EXCLUDE_END=2021-09-01
run() { local tag=$1; shift; echo "=== $(date '+%T') $tag"; env "$@" OUT_DIR="$R/$tag" \
  Rscript --vanilla analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R > "$R.$tag.stdout.log" 2>&1; }
mkdir -p "$R"
run w21aug_pool
run w21aug_nocovid DROP_START=2020-03-01 DROP_END=2021-09-01
run w21aug_both    DROP_START=2020-03-01 DROP_END=2021-09-01 ERR_SCALE=state_month
echo "=== $(date '+%T') done"
