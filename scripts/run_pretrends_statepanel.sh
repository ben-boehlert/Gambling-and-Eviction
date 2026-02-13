#!/bin/bash
################################################################################
# run_pretrends_statepanel.sh
#
# Pre-trends diagnostics for state-month panel:
# CS-DiD + TWFE/SunAb + optional gambling intensity + optional self-test
#
# Usage:
#   bash scripts/run_pretrends_statepanel.sh                # defaults
#   SELF_TEST=TRUE N_CORES=4 bash scripts/run_pretrends_statepanel.sh  # with calibration
#   GAMBLING_FILE=data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv \
#     bash scripts/run_pretrends_statepanel.sh              # with gambling
################################################################################

set -euo pipefail

# Ensure working directory is project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---- Core panel ----
export PANEL_FILE="${PANEL_FILE:-data/raw/state_month_panel_with_treatment.csv}"
export EXCLUDE_STATES="${EXCLUDE_STATES:-ME}"
export MIN_DATE="${MIN_DATE:-2016-01-01}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"
# Optional: drop a window from the analysis panel (e.g., COVID months)
# Example: DROP_START=2020-03-01 DROP_END=2021-07-31
export DROP_START="${DROP_START:-}"
export DROP_END="${DROP_END:-}"
export NO_COVID="${NO_COVID:-TRUE}"

# Convenience switch: if NO_COVID=TRUE and no explicit DROP window provided,
# drop the commonly-used COVID period.
NO_COVID_UPPER="$(printf '%s' "${NO_COVID}" | tr '[:lower:]' '[:upper:]')"
if [[ "${NO_COVID_UPPER}" == "TRUE" || "${NO_COVID_UPPER}" == "1" ]]; then
  if [[ -z "${DROP_START}" && -z "${DROP_END}" ]]; then
    export DROP_START="2020-03-01"
    export DROP_END="2021-07-31"
  fi
fi
export COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-}"
export BALANCE_COMMON_MONTHS="${BALANCE_COMMON_MONTHS:-TRUE}"

# ---- Outcome ----
export OUTCOME="${OUTCOME:-log1p_filings_count}"
export RATE_EPS="${RATE_EPS:-0.01}"

# ---- CS settings ----
export CONTROL_GROUP="${CONTROL_GROUP:-notyettreated}"
export EST_METHOD="${EST_METHOD:-reg}"
export ALLOW_UNBALANCED_PANEL="${ALLOW_UNBALANCED_PANEL:-TRUE}"
export PRE_WINDOW="${PRE_WINDOW:--12:-1}"
export CS_ANALYTIC="${CS_ANALYTIC:-TRUE}"
export CS_BOOTSTRAP="${CS_BOOTSTRAP:-TRUE}"
export CS_BITERS="${CS_BITERS:-199}"
export CS_FASTER_MODE="${CS_FASTER_MODE:-TRUE}"

# ---- Gambling (optional) ----
export GAMBLING_FILE="${GAMBLING_FILE:-}"
export GAMBLING_AMOUNT_COL="${GAMBLING_AMOUNT_COL:-Handle}"

# ---- General ----
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-123}"

# ---- Self-test (optional) ----
export SELF_TEST="${SELF_TEST:-FALSE}"
export SELF_TEST_N="${SELF_TEST_N:-200}"
export SELF_TEST_ERR_MODE="${SELF_TEST_ERR_MODE:-resid_pool_ar1_state}"

# ---- Parallelism ----
export N_CORES="${N_CORES:-1}"

# ---- Output ----
export OUT_DIR="${OUT_DIR:-output/pretrends_statepanel_template}"

echo "========================================="
echo "PRE-TRENDS DIAGNOSTICS (State Panel)"
echo "========================================="
echo "Start time: $(date)"
echo ""
echo "Configuration:"
echo "  PANEL_FILE:       $PANEL_FILE"
echo "  EXCLUDE_STATES:   $EXCLUDE_STATES"
echo "  MIN_DATE:         $MIN_DATE"
echo "  MAX_DATE:         $MAX_DATE"
echo "  DROP_START/END:   ${DROP_START:-<none>} / ${DROP_END:-<none>}"
echo "  NO_COVID:         $NO_COVID"
echo "  OUTCOME:          $OUTCOME"
echo "  CS_ANALYTIC:      $CS_ANALYTIC"
echo "  CS_BOOTSTRAP:     $CS_BOOTSTRAP (biters=$CS_BITERS)"
echo "  GAMBLING_FILE:    ${GAMBLING_FILE:-<none>}"
echo "  SELF_TEST:        $SELF_TEST (N=$SELF_TEST_N, ERR=$SELF_TEST_ERR_MODE)"
echo "  N_CORES:          $N_CORES"
echo "  OUT_DIR:          $OUT_DIR"
echo ""

# Verify panel exists
if [[ ! -f "$PANEL_FILE" ]]; then
  echo "ERROR: PANEL_FILE not found: $PANEL_FILE"
  exit 1
fi

# Run
Rscript --vanilla analysis/pretrends/pretrends_statepanel_template.R

echo ""
echo "========================================="
echo "COMPLETED: $(date)"
echo "Output: $OUT_DIR"
echo "========================================="
