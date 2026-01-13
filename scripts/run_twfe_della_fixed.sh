#!/bin/bash
#SBATCH --job-name=twfe_power_fixed
#SBATCH --output=twfe_power_fixed_%j.out
#SBATCH --error=twfe_power_fixed_%j.err
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem=32G
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=your_email@princeton.edu

################################################################################
# run_twfe_della_fixed.sh
#
# Slurm batch script for Della to run the FIXED TWFE power simulation
# - Excludes Maine
# - Extends to end of 2024
# - Uses MIN_STATES_PER_MONTH=5 (not MIN_POOL=10)
# - Excludes March 2020 - May 2021 from residual pool ONLY (not analysis panel)
# - Effect grid: 0, 3%, 4%, 5%, 6%
#
# NOTE: Excluding COVID from residual pool INCREASES power by reducing noise.
# Analysis panel includes all data (N=3349), but residuals drawn from non-COVID periods.
################################################################################

echo "================================================================"
echo "TWFE Power Simulation - FIXED VERSION"
echo "Job ID: $SLURM_JOB_ID"
echo "Start time: $(date)"
echo "Running on node: $(hostname)"
echo "Working directory: $(pwd)"
echo "================================================================"

# Load R module (adjust version if needed)
module purge
module load R/4.4.2

# Verify R is loaded
which R
R --version

# Set working directory to your project root
cd /scratch/gpfs/DESMOND/ben/eviction_gambling || exit 1
echo "Changed to: $(pwd)"

# Verify required files exist
if [ ! -f "power_simulation_twfe_statepanel_staggered_parallel_fixed.R" ]; then
    echo "ERROR: power_simulation_twfe_statepanel_staggered_parallel_fixed.R not found!"
    exit 1
fi

if [ ! -f "combined_monthly_panel.csv" ]; then
    echo "ERROR: combined_monthly_panel.csv not found!"
    exit 1
fi

if [ ! -f "state_month_panel_with_treatment.csv" ]; then
    echo "ERROR: state_month_panel_with_treatment.csv not found!"
    exit 1
fi

echo "All required files found."
echo ""

# Export simulation parameters
export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.03,0.04,0.05,0.06}"
export OUT_DIR="twfe_power_out_no_maine_2024_FIXED"
export N_WORKERS="20"
export BATCH_SIZE="50"
export SEED="123"
export ALPHA="0.05"

# CRITICAL FIX: Use MIN_STATES_PER_MONTH=5 (not MIN_POOL=10)
export MIN_STATES_PER_MONTH="5"

# Exclude March 2020 through May 2021 (end exclusive) from residual pool
# This INCREASES power by removing high-variance COVID period from error distribution
export EXCLUDE_START="2020-03-01"
export EXCLUDE_END="2021-06-01"

# DO NOT drop from analysis panel - keep full N=3349 for maximum power
# export DROP_START=""
# export DROP_END=""

# Error mode
export ERR_MODE="iid_month"

# Data files (default paths, in current directory)
export DATA_FILE="combined_monthly_panel.csv"
export TREAT_FILE="state_month_panel_with_treatment.csv"
export OUTCOME="log1p_filings_count"

echo "================================================================"
echo "SIMULATION PARAMETERS:"
echo "  EXCLUDE_STATES: $EXCLUDE_STATES"
echo "  MAX_DATE: $MAX_DATE"
echo "  N_SIMS: $N_SIMS"
echo "  EFFECT_PCTS: $EFFECT_PCTS"
echo "  MIN_STATES_PER_MONTH: $MIN_STATES_PER_MONTH"
echo "  EXCLUDE_START: $EXCLUDE_START (excluded from residual pool only)"
echo "  EXCLUDE_END: $EXCLUDE_END (excluded from residual pool only)"
echo "  OUT_DIR: $OUT_DIR"
echo "  N_WORKERS: $N_WORKERS"
echo "  ERR_MODE: $ERR_MODE"
echo "  NOTE: Analysis panel includes all months (N=3349) for maximum power"
echo "================================================================"
echo ""

# Run the simulation
echo "Starting TWFE power simulation..."
Rscript power_simulation_twfe_statepanel_staggered_parallel_fixed.R

EXIT_CODE=$?

echo ""
echo "================================================================"
echo "Simulation completed with exit code: $EXIT_CODE"
echo "End time: $(date)"
echo "================================================================"

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "SUCCESS! Output files written to: $OUT_DIR"
    echo ""
    echo "Key output files:"
    ls -lh "$OUT_DIR"/*.{log,csv,png} 2>/dev/null || echo "  (checking output directory...)"
    echo ""
    echo "Checking log for key diagnostics:"
    if [ -f "$OUT_DIR/run.log" ]; then
        echo ""
        echo "--- EXCLUDE window (should NOT be 'none') ---"
        grep "EXCLUDE (resid pool only)" "$OUT_DIR/run.log" | tail -1
        echo ""
        echo "--- MIN_STATES_PER_MONTH (should be 5) ---"
        grep "MIN_STATES_PER_MONTH" "$OUT_DIR/run.log" | tail -1
        echo ""
        echo "--- Final analysis N (should be ~3349) ---"
        grep "Final analysis panel N" "$OUT_DIR/run.log"
        echo ""
        echo "--- Effect grid (should be 0, 0.03, 0.04, 0.05, 0.06) ---"
        grep "EFFECT_PCTS:" "$OUT_DIR/run.log" | tail -1
        echo ""
        echo "--- Residual pool stats ---"
        grep "Residual pool construction:" -A 6 "$OUT_DIR/run.log" | tail -7
        echo ""
    fi
else
    echo ""
    echo "ERROR! Simulation failed. Check the log files:"
    echo "  Standard output: twfe_power_fixed_${SLURM_JOB_ID}.out"
    echo "  Standard error: twfe_power_fixed_${SLURM_JOB_ID}.err"
    echo "  Run log (if created): $OUT_DIR/run.log"
fi

exit $EXIT_CODE
