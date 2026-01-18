#!/bin/bash
################################################################################
# run_pretrends_twfe.sh
#
# Bash runner for TWFE pre-trends testing
# Compatible with SLURM (Della) and local execution
#
# Usage:
#   sbatch scripts/run_pretrends_twfe.sh           # On Della
#   bash scripts/run_pretrends_twfe.sh             # Locally
################################################################################

#SBATCH --job-name=pretrends_twfe
#SBATCH --output=pretrends_twfe_%j.out
#SBATCH --error=pretrends_twfe_%j.err
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=$USER@princeton.edu

set -euo pipefail

echo "========================================="
echo "TWFE PRE-TRENDS DIAGNOSTICS"
echo "========================================="
echo "Start time: $(date)"
echo "Host: $(hostname)"
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

# Support diagnostic threshold
export MIN_STATES_PER_MONTH="${MIN_STATES_PER_MONTH:-5}"

# General settings
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-123}"

# Event window
export MIN_E="${MIN_E:--24}"
export MAX_E="${MAX_E:-24}"
export BALANCE_E="${BALANCE_E:-}"

# TWFE settings
export BINNED_ENDPOINTS="${BINNED_ENDPOINTS:-FALSE}"

# Output directory
export OUT_DIR="${OUT_DIR:-pretrends_twfe_out}"

echo "Configuration:"
echo "  OUTCOME:               $OUTCOME"
echo "  RATE_EPS:              $RATE_EPS"
echo "  EXCLUDE_STATES:        $EXCLUDE_STATES"
echo "  MAX_DATE:              $MAX_DATE"
echo "  MIN_STATES_PER_MONTH:  $MIN_STATES_PER_MONTH"
echo "  Event window:          [$MIN_E, $MAX_E]"
echo "  BINNED_ENDPOINTS:      $BINNED_ENDPOINTS"
echo "  OUT_DIR:               $OUT_DIR"
echo ""

# ----------------------------- run diagnostics --------------------------------

echo "========================================="
echo "Running TWFE pre-trends diagnostics"
echo "========================================="
echo ""

Rscript analysis/pretrends_twfe.R

RUN_STATUS=$?
if [[ $RUN_STATUS -ne 0 ]]; then
  echo "ERROR: TWFE pre-trends diagnostics failed with exit code $RUN_STATUS"
  exit $RUN_STATUS
fi

echo ""
echo "========================================="
echo "DIAGNOSTICS COMPLETED SUCCESSFULLY"
echo "========================================="
echo "End time: $(date)"
echo ""
echo "Output directory: $OUT_DIR"
echo ""
echo "Key outputs:"
echo "  - panel_summary.csv"
echo "  - cohort_sizes.csv"
echo "  - untreated_support_by_month.csv"
echo "  - support_by_event_time.csv"
echo "  - twfe_event_study.csv + .png"
echo "  - twfe_pretrends_joint_test.csv"
echo "  - diagnostic_summary.csv"
echo "  - run_pretrends_twfe.log"
echo ""
