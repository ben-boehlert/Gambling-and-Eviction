#!/bin/bash
################################################################################
# run_pretrends_della.sh
#
# Bash runner for pre-trends event-study diagnostics
# Compatible with SLURM (Della) and local execution
#
# Usage:
#   sbatch scripts/run_pretrends_della.sh           # On Della
#   bash scripts/run_pretrends_della.sh             # Locally
################################################################################

#SBATCH --job-name=pretrends
#SBATCH --output=pretrends_della_%j.out
#SBATCH --error=pretrends_della_%j.err
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=$USER@princeton.edu

set -euo pipefail

echo "========================================="
echo "PRE-TRENDS EVENT-STUDY DIAGNOSTICS"
echo "========================================="
echo "Start time: $(date)"
echo "Host: $(hostname)"
echo "Working directory: $(pwd)"
echo ""

# ----------------------------- environment setup ------------------------------

# Detect if running on Della or locally
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  echo "Running on SLURM cluster (Job ID: $SLURM_JOB_ID)"
  ON_DELLA=true

  # Load R module on Della
  module purge
  module load R/4.3.1

  # Set working directory to scratch on Della
  cd /scratch/gpfs/DESMOND/ben/eviction_gambling || {
    echo "ERROR: Could not cd to Della scratch directory"
    exit 1
  }
else
  echo "Running locally"
  ON_DELLA=false

  # Ensure we're in the repo root
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR/.." || {
    echo "ERROR: Could not cd to repo root"
    exit 1
  }
fi

echo "Working directory: $(pwd)"
echo ""

# ----------------------------- data file paths --------------------------------

# Set data file paths (adjust if needed)
export DATA_FILE="${DATA_FILE:-combined_monthly_panel.csv}"
export TREAT_FILE="${TREAT_FILE:-state_month_panel_with_treatment.csv}"

# Verify files exist
if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: DATA_FILE not found: $DATA_FILE"
  exit 1
fi

if [[ ! -f "$TREAT_FILE" ]]; then
  echo "ERROR: TREAT_FILE not found: $TREAT_FILE"
  exit 1
fi

echo "Data files verified:"
echo "  DATA_FILE:  $DATA_FILE"
echo "  TREAT_FILE: $TREAT_FILE"
echo ""

# ----------------------------- common settings --------------------------------

# Outcome specification
export OUTCOME="${OUTCOME:-log1p_filings_count}"
export RATE_EPS="${RATE_EPS:-0.01}"

# Filtering
export EXCLUDE_STATES="${EXCLUDE_STATES:-ME}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"

# DROP_START/DROP_END: remove from analysis panel
export DROP_START="${DROP_START:-}"
export DROP_END="${DROP_END:-}"

# EXCLUDE_START/EXCLUDE_END: documented but unused (only affects TWFE resid pool)
export EXCLUDE_START="${EXCLUDE_START:-}"
export EXCLUDE_END="${EXCLUDE_END:-}"

# Support diagnostic threshold
export MIN_STATES_PER_MONTH="${MIN_STATES_PER_MONTH:-5}"

# General settings
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-123}"

# Event window
export MIN_E="${MIN_E:--24}"
export MAX_E="${MAX_E:-24}"
export BALANCE_E="${BALANCE_E:-}"

# CS-DiD settings
export DID_EST_METHOD="${DID_EST_METHOD:-reg}"
export DID_CONTROL_GROUP="${DID_CONTROL_GROUP:-notyettreated}"
export DID_ALLOW_UNBALANCED="${DID_ALLOW_UNBALANCED:-TRUE}"

echo "Configuration:"
echo "  OUTCOME:               $OUTCOME"
echo "  RATE_EPS:              $RATE_EPS"
echo "  EXCLUDE_STATES:        $EXCLUDE_STATES"
echo "  MAX_DATE:              $MAX_DATE"
echo "  MIN_STATES_PER_MONTH:  $MIN_STATES_PER_MONTH"
echo "  Event window:          [$MIN_E, $MAX_E]"
echo "  DID_EST_METHOD:        $DID_EST_METHOD"
echo "  DID_CONTROL_GROUP:     $DID_CONTROL_GROUP"
echo ""

# ----------------------------- run 1: fast diagnostic (no bootstrap) ----------

echo "========================================="
echo "RUN 1: Fast diagnostic (no bootstrap)"
echo "========================================="

export OUT_DIR="pretrends_out_noboot"
export DID_BSTRAP="FALSE"
export DID_BITERS="0"
export RUN_TWFE_ES="FALSE"

echo "Output directory: $OUT_DIR"
echo "Bootstrap: $DID_BSTRAP"
echo "TWFE event study: $RUN_TWFE_ES"
echo ""

if [[ "$ON_DELLA" == true ]]; then
  Rscript analysis/pretrends_eventstudy_diagnostics.R
else
  Rscript analysis/pretrends_eventstudy_diagnostics.R
fi

RUN1_STATUS=$?
if [[ $RUN1_STATUS -ne 0 ]]; then
  echo "ERROR: Run 1 failed with exit code $RUN1_STATUS"
  exit $RUN1_STATUS
fi

echo "Run 1 completed successfully."
echo ""

# ----------------------------- run 2: full inference (with bootstrap) ---------

echo "========================================="
echo "RUN 2: Full inference (with bootstrap)"
echo "========================================="

export OUT_DIR="pretrends_out_boot199"
export DID_BSTRAP="TRUE"
export DID_BITERS="199"
export RUN_TWFE_ES="TRUE"

echo "Output directory: $OUT_DIR"
echo "Bootstrap: $DID_BSTRAP (biters=$DID_BITERS)"
echo "TWFE event study: $RUN_TWFE_ES"
echo ""

if [[ "$ON_DELLA" == true ]]; then
  Rscript analysis/pretrends_eventstudy_diagnostics.R
else
  Rscript analysis/pretrends_eventstudy_diagnostics.R
fi

RUN2_STATUS=$?
if [[ $RUN2_STATUS -ne 0 ]]; then
  echo "ERROR: Run 2 failed with exit code $RUN2_STATUS"
  exit $RUN2_STATUS
fi

echo "Run 2 completed successfully."
echo ""

# ----------------------------- summary ----------------------------------------

echo "========================================="
echo "BOTH RUNS COMPLETED SUCCESSFULLY"
echo "========================================="
echo "End time: $(date)"
echo ""
echo "Output directories:"
echo "  pretrends_out_noboot/"
echo "  pretrends_out_boot199/"
echo ""
echo "Key outputs:"
echo "  - panel_summary.csv"
echo "  - untreated_support_by_month.csv"
echo "  - support_by_event_time.csv"
echo "  - cs_event_study.csv + .png"
echo "  - cs_pretrends_joint_test.csv"
echo "  - twfe_event_study.csv + .png (in boot199 run)"
echo "  - twfe_pretrends_joint_test.csv (in boot199 run)"
echo "  - run_pretrends.log"
echo ""
