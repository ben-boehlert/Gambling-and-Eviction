#!/bin/bash
################################################################################
# run_twfe_power_no_maine_2024_with_covid.sh
#
# Run TWFE power simulation excluding Maine and extending to end of 2024
# Includes COVID period (no exclusion from residual pool)
# Uses traditional TWFE with proper cluster-robust SEs (no bootstrap needed)
################################################################################

export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.06,0.07,0.08,0.09,0.1}"
export OUT_DIR="twfe_power_out_no_maine_2024_with_covid"
export N_WORKERS="${N_WORKERS:-20}"
export BATCH_SIZE="${BATCH_SIZE:-50}"

# Minimum states per month for residual pool
export MIN_STATES_PER_MONTH="5"

# No COVID exclusion - keep all periods in residual pool
unset EXCLUDE_START
unset EXCLUDE_END

echo "Running TWFE power simulation:"
echo "  - Excluding state(s): $EXCLUDE_STATES"
echo "  - Max date: $MAX_DATE"
echo "  - Output directory: $OUT_DIR"
echo "  - N_SIMS: $N_SIMS"
echo "  - Min states per month: $MIN_STATES_PER_MONTH"
echo "  - COVID period: INCLUDED in residual pool"
echo ""

Rscript power_simulation_twfe_statepanel_staggered_parallel_fixed.R
