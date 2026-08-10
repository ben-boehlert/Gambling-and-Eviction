#!/bin/bash
################################################################################
# run_dose_response_iv.sh
#
# Dose-response IV analysis: continuous handle per capita on evictions,
# instrumented by binary legalization.
#
# Usage:
#   bash scripts/run_dose_response_iv.sh                # defaults
#   LOO=FALSE bash scripts/run_dose_response_iv.sh      # skip LOO sensitivity
#   NO_COVID=FALSE bash scripts/run_dose_response_iv.sh  # include COVID months
################################################################################

set -euo pipefail

# Ensure working directory is project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---- Core panel ----
export PANEL_FILE="${PANEL_FILE:-data/raw/state_month_panel_with_treatment.csv}"
export HANDLE_FILE="${HANDLE_FILE:-data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv}"
export TREAT_SOURCE="${TREAT_SOURCE:-file}"
export TREAT_FILE="${TREAT_FILE:-data/raw/sports_gambling_legalization_dates.csv}"
export TREAT_DATE_COL="${TREAT_DATE_COL:-online_start_date}"
export EXCLUDE_STATES="${EXCLUDE_STATES:-ME}"
export MIN_DATE="${MIN_DATE:-2016-01-01}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"

# Optional: drop a window (e.g., COVID months)
export DROP_START="${DROP_START:-}"
export DROP_END="${DROP_END:-}"
export NO_COVID="${NO_COVID:-TRUE}"

# Convenience switch: if NO_COVID=TRUE and no explicit DROP window, drop COVID
NO_COVID_UPPER="$(printf '%s' "${NO_COVID}" | tr '[:lower:]' '[:upper:]')"
if [[ "${NO_COVID_UPPER}" == "TRUE" || "${NO_COVID_UPPER}" == "1" ]]; then
  if [[ -z "${DROP_START}" && -z "${DROP_END}" ]]; then
    export DROP_START="2020-03-01"
    export DROP_END="2021-07-31"
  fi
fi

# ---- Outcome ----
export OUTCOME="${OUTCOME:-log1p_filings_count}"
export RATE_EPS="${RATE_EPS:-0.01}"

# ---- Analysis options ----
export ALPHA="${ALPHA:-0.05}"
export LOO="${LOO:-TRUE}"
export SUBPERIOD="${SUBPERIOD:-TRUE}"
export SUBPERIOD_START="${SUBPERIOD_START:-2022-04-01}"

# ---- Output ----
export OUT_DIR="${OUT_DIR:-output/dose_response_iv}"

echo "========================================="
echo "DOSE-RESPONSE IV ANALYSIS"
echo "========================================="
echo "Start time: $(date)"
echo ""
echo "Configuration:"
echo "  PANEL_FILE:       $PANEL_FILE"
echo "  HANDLE_FILE:      $HANDLE_FILE"
echo "  TREAT_SOURCE:     $TREAT_SOURCE"
echo "  TREAT_FILE:       $TREAT_FILE"
echo "  TREAT_DATE_COL:   $TREAT_DATE_COL"
echo "  EXCLUDE_STATES:   $EXCLUDE_STATES"
echo "  MIN_DATE:         $MIN_DATE"
echo "  MAX_DATE:         $MAX_DATE"
echo "  DROP_START/END:   ${DROP_START:-<none>} / ${DROP_END:-<none>}"
echo "  NO_COVID:         $NO_COVID"
echo "  OUTCOME:          $OUTCOME"
echo "  LOO:              $LOO"
echo "  SUBPERIOD:        $SUBPERIOD (start=$SUBPERIOD_START)"
echo "  OUT_DIR:          $OUT_DIR"
echo ""

# Verify inputs exist
if [[ ! -f "$PANEL_FILE" ]]; then
  echo "ERROR: PANEL_FILE not found: $PANEL_FILE"
  exit 1
fi
if [[ ! -f "$HANDLE_FILE" ]]; then
  echo "ERROR: HANDLE_FILE not found: $HANDLE_FILE"
  exit 1
fi

# Run
Rscript --vanilla analysis/main/dose_response_iv.R

echo ""
echo "========================================="
echo "COMPLETED: $(date)"
echo "Output: $OUT_DIR"
echo "========================================="
