#!/bin/bash
################################################################################
# run_twfe_della_interactive.sh
#
# Interactive shell script for Della to run the FIXED TWFE power simulation
# Run this directly on a login node or in an interactive session
# - Excludes Maine
# - Extends to end of 2024
# - Uses MIN_STATES_PER_MONTH=5 (not MIN_POOL=10)
# - Excludes March 2020 - May 2021 from residual pool (end exclusive)
# - Effect grid: 0, 3%, 4%, 5%, 6%
################################################################################

echo "================================================================"
echo "TWFE Power Simulation - FIXED VERSION (Interactive)"
echo "Start time: $(date)"
echo "Running on node: $(hostname)"
echo "Working directory: $(pwd)"
echo "================================================================"

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
export EXCLUDE_START="2020-03-01"
export EXCLUDE_END="2021-06-01"

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
echo "  EXCLUDE_START: $EXCLUDE_START"
echo "  EXCLUDE_END: $EXCLUDE_END"
echo "  OUT_DIR: $OUT_DIR"
echo "  N_WORKERS: $N_WORKERS"
echo "  ERR_MODE: $ERR_MODE"
echo "================================================================"
echo ""

# Run the simulation
echo "Starting TWFE power simulation..."
echo "(This will take ~30-60 minutes for N_SIMS=2000)"
echo ""

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
    ls -lh "$OUT_DIR"/*.{log,csv,png} 2>/dev/null
    echo ""
    echo "================================================================"
    echo "KEY DIAGNOSTICS FROM LOG:"
    echo "================================================================"
    if [ -f "$OUT_DIR/run.log" ]; then
        echo ""
        echo "--- EXCLUDE window (should NOT be 'none') ---"
        grep "EXCLUDE (resid pool only)" "$OUT_DIR/run.log" | tail -1
        echo ""
        echo "--- MIN_STATES_PER_MONTH (should be 5) ---"
        grep "MIN_STATES_PER_MONTH" "$OUT_DIR/run.log" | head -1
        echo ""
        echo "--- Final analysis N (should be ~2867) ---"
        grep "Final analysis panel N" "$OUT_DIR/run.log"
        echo ""
        echo "--- Effect grid (should be 0, 0.03, 0.04, 0.05, 0.06) ---"
        grep "EFFECT_PCTS:" "$OUT_DIR/run.log" | tail -1
        echo ""
        echo "--- Residual pool stats ---"
        grep "Residual pool construction:" -A 6 "$OUT_DIR/run.log" | tail -7
        echo ""
        echo "================================================================"
        echo ""
        echo "Full log available at: $OUT_DIR/run.log"
    fi
else
    echo ""
    echo "ERROR! Simulation failed."
    echo "Check the run log (if created): $OUT_DIR/run.log"
fi

exit $EXIT_CODE
