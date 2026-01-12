#!/bin/bash
################################################################################
# run_twfe_power_no_maine_2024.sh
#
# Run TWFE power simulation excluding Maine and extending to end of 2024
# Uses traditional TWFE with proper cluster-robust SEs (no bootstrap needed)
################################################################################

export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.03,0.04,0.05,0.06}"
export OUT_DIR="twfe_power_out_no_maine_2024"
export N_WORKERS="${N_WORKERS:-20}"
export BATCH_SIZE="${BATCH_SIZE:-50}"

# Optional: exclude COVID period from residual pool
export EXCLUDE_START="${EXCLUDE_START:-2020-03-01}"
export EXCLUDE_END="${EXCLUDE_END:-2021-06-01}"

echo "Running TWFE power simulation:"
echo "  - Excluding state(s): $EXCLUDE_STATES"
echo "  - Max date: $MAX_DATE"
echo "  - Output directory: $OUT_DIR"
echo "  - N_SIMS: $N_SIMS"
echo "  - COVID exclusion (residual pool): $EXCLUDE_START to $EXCLUDE_END"
echo ""

Rscript power_simulation_twfe_statepanel_staggered_parallel_fixed.R
