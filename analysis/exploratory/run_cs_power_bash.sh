#!/bin/bash

# CS DiD Power Simulation - Bash Version (no SLURM)
# Run directly with: bash run_cs_power_bash.sh

# Load R module (check with: module avail R)
module load R 2>/dev/null || echo "Warning: module load failed, continuing anyway..."

# Environment variables
export DATA_FILE=combined_monthly_panel.csv
export TREAT_FILE=state_month_panel_with_treatment.csv
export OUT_DIR=cs_reg_power_out
export N_SIMS=2000
export EFFECT_PCTS="0,0.05,0.10,0.15,0.20"
export N_WORKERS=20
export BATCH_SIZE=100
export ALPHA=0.05
export SEED=123

# Date windows
export EXCLUDE_START=2020-03-01
export EXCLUDE_END=2021-07-01

# Progress tracking
export PROGRESS_BATCHES=cs_reg_power_out/progress_batches.csv

# DID options (defaults match main analysis)
export DID_CONTROL_GROUP=notyettreated
export DID_BSTRAP=TRUE
export DID_BITERS=199

# Error mode
export ERR_MODE=iid_month

# Run simulation
echo "Starting CS DiD power simulation..."
echo "Output directory: $OUT_DIR"
echo "N_SIMS: $N_SIMS, N_WORKERS: $N_WORKERS"

Rscript power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R

echo ""
echo "Simulation complete. Check $OUT_DIR/ for results."
echo "Main results:"
echo "  - power_by_effect.csv (power curve)"
echo "  - diagnostics_sanity.csv (null diagnostics)"
echo "  - run.log (execution log)"
