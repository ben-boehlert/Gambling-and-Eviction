#!/bin/bash
################################################################################
# run_power_mortgage.sh
#
# Power simulation for mortgage delinquency outcome.
# Runs both TWFE and CS-DiD (CS optional via RUN_CS=FALSE).
#
# Usage:
#   bash scripts/run_power_mortgage.sh                        # defaults (COVID excluded)
#   N_SIMS=500 CS_N_SIMS=200 bash scripts/run_power_mortgage.sh  # quick test
#   RUN_CS=FALSE bash scripts/run_power_mortgage.sh           # TWFE only
#   NO_COVID=FALSE bash scripts/run_power_mortgage.sh         # include COVID period
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---- Data ----
export MORTGAGE_FILE="${MORTGAGE_FILE:-data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv}"
export TREAT_FILE="${TREAT_FILE:-data/raw/sports_gambling_legalization_dates.csv}"
export TREAT_DATE_COL="${TREAT_DATE_COL:-online_start_date}"

# ---- Panel filters ----
export MIN_DATE="${MIN_DATE:-2016-01-01}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"
export DROP_START="${DROP_START:-}"
export DROP_END="${DROP_END:-}"
export NO_COVID="${NO_COVID:-TRUE}"

NO_COVID_UPPER="$(printf '%s' "${NO_COVID}" | tr '[:lower:]' '[:upper:]')"
if [[ "${NO_COVID_UPPER}" == "TRUE" || "${NO_COVID_UPPER}" == "1" ]]; then
  if [[ -z "${DROP_START}" && -z "${DROP_END}" ]]; then
    export DROP_START="2020-03-01"
    export DROP_END="2021-07-31"
  fi
fi

# ---- Simulation settings ----
export OUTCOME="${OUTCOME:-delinq_pct}"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_SIZES="${EFFECT_SIZES:-0,0.05,0.10,0.15,0.20,0.30,0.50}"
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-20260409}"
export N_WORKERS="${N_WORKERS:-8}"
export BATCH_SIZE="${BATCH_SIZE:-50}"
export ERR_MODE="${ERR_MODE:-iid_month}"

# ---- CS settings ----
export RUN_CS="${RUN_CS:-TRUE}"
export CS_N_SIMS="${CS_N_SIMS:-500}"
export CS_BITERS="${CS_BITERS:-50}"
export CS_CONTROL_GROUP="${CS_CONTROL_GROUP:-notyettreated}"
export CS_EST_METHOD="${CS_EST_METHOD:-reg}"

# ---- Output ----
export OUT_DIR="${OUT_DIR:-output/power_mortgage_delinquency}"

echo "========================================="
echo "POWER SIMULATION: Mortgage Delinquency"
echo "========================================="
echo "Start: $(date)"
echo ""
echo "Configuration:"
echo "  OUTCOME:        $OUTCOME"
echo "  N_SIMS (TWFE):  $N_SIMS"
echo "  EFFECT_SIZES:   $EFFECT_SIZES"
echo "  DROP window:    ${DROP_START:-<none>} / ${DROP_END:-<none>}"
echo "  N_WORKERS:      $N_WORKERS"
echo "  RUN_CS:         $RUN_CS"
echo "  CS_N_SIMS:      $CS_N_SIMS"
echo "  OUT_DIR:        $OUT_DIR"
echo ""

# Verify data
if [[ ! -f "$MORTGAGE_FILE" ]]; then
  echo "ERROR: MORTGAGE_FILE not found: $MORTGAGE_FILE"
  exit 1
fi
if [[ ! -f "$TREAT_FILE" ]]; then
  echo "ERROR: TREAT_FILE not found: $TREAT_FILE"
  exit 1
fi

Rscript --vanilla analysis/main/power_simulation_mortgage_delinquency.R

echo ""
echo "========================================="
echo "COMPLETED: $(date)"
echo "Output: $OUT_DIR"
echo "========================================="
