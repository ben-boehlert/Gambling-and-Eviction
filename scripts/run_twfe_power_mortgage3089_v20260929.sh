#!/usr/bin/env bash
# 30-89 DAY twin (2026-09-29) of run_twfe_power_mortgage_v20260929.sh. Application-era AR(1) TWFE power sim on the MORTGAGE delinquency rate
# (log), run through the unchanged eviction script so the MDE is comparable to
# the eviction side's 5.5-6% (twfe_power_rerun_noMNWA_v20260922, ar1).
# Inputs: data_prep/build_mortgage_twfe_sim_inputs.R with MORT_FILE=...30-89DaysLate... (see its header). OUTCOME=log1p_rate with
# RATE_EPS=0 gives y = log(rate). Two runs, one change apart:
#   mirror      every setting of the 5.5-6% run (ar1, residual-pool exclusion
#               [2020-03-01, 2021-06-01), EXCLUDE_STATES=WA,MN, SEED 123, 2,000 sims)
#   all_states  same, WA and MN kept (their exclusion is an eviction-data decision)
# Run from the project root:  bash scripts/run_twfe_power_mortgage3089_v20260929.sh
set -euo pipefail
R=output/twfe_power_mortgage3089_v20260929
export DATA_FILE=$R/inputs/data_state_rows.csv
export TREAT_FILE=$R/inputs/treat_state_month.csv
export OUTCOME=log1p_rate RATE_EPS=0
export N_SIMS=2000 N_WORKERS=6 BATCH_SIZE=50 SEED=123 ERR_MODE=ar1
export EFFECT_PCTS=0,0.03,0.05,0.08,0.10,0.12,0.15,0.20,0.25,0.30
export EXCLUDE_START=2020-03-01 EXCLUDE_END=2021-06-01
run() { local tag=$1; shift; echo "=== $(date '+%T') $tag"; env "$@" OUT_DIR="$R/$tag" \
  Rscript --vanilla analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R > "$R/$tag.stdout.log" 2>&1; }
run mirror     EXCLUDE_STATES=WA,MN
run all_states EXCLUDE_STATES=
echo "=== $(date '+%T') done"
