#!/bin/bash
################################################################################
# run_pretrends_mortgage.sh
#
# Pre-trends diagnostics for mortgage delinquency (90+ days late):
# CS-DiD + TWFE/SunAb event studies
#
# Treatment: online sports gambling legalization (staggered)
# Outcome:   % of mortgages 90+ days delinquent (state-month panel)
#
# Usage:
#   bash scripts/run_pretrends_mortgage.sh                     # defaults
#   NO_COVID=FALSE bash scripts/run_pretrends_mortgage.sh      # include COVID
#   TREAT_DATE_COL=retail_start_date bash scripts/run_pretrends_mortgage.sh
################################################################################

set -euo pipefail

# Ensure working directory is project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---- Data files ----
export MORTGAGE_FILE="${MORTGAGE_FILE:-data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv}"
export TREAT_FILE="${TREAT_FILE:-data/raw/sports_gambling_legalization_dates.csv}"
export TREAT_DATE_COL="${TREAT_DATE_COL:-online_start_date}"

# ---- Panel filters ----
export EXCLUDE_STATES="${EXCLUDE_STATES:-}"
export MIN_DATE="${MIN_DATE:-2016-01-01}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"
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
export OUTCOME="${OUTCOME:-delinq_pct}"

# ---- CS settings ----
export CONTROL_GROUP="${CONTROL_GROUP:-notyettreated}"
export EST_METHOD="${EST_METHOD:-reg}"
export ALLOW_UNBALANCED_PANEL="${ALLOW_UNBALANCED_PANEL:-TRUE}"
export PRE_WINDOW="${PRE_WINDOW:--12:-1}"
export CS_ANALYTIC="${CS_ANALYTIC:-TRUE}"
export CS_BOOTSTRAP="${CS_BOOTSTRAP:-TRUE}"
export CS_BITERS="${CS_BITERS:-199}"
export CS_FASTER_MODE="${CS_FASTER_MODE:-TRUE}"

# ---- General ----
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-123}"

# ---- Output ----
export OUT_DIR="${OUT_DIR:-output/pretrends_mortgage_delinquency}"

echo "========================================="
echo "PRE-TRENDS: Mortgage Delinquency"
echo "========================================="
echo "Start time: $(date)"
echo ""
echo "Configuration:"
echo "  MORTGAGE_FILE:    $MORTGAGE_FILE"
echo "  TREAT_FILE:       $TREAT_FILE"
echo "  TREAT_DATE_COL:   $TREAT_DATE_COL"
echo "  EXCLUDE_STATES:   ${EXCLUDE_STATES:-<none>}"
echo "  MIN_DATE:         $MIN_DATE"
echo "  MAX_DATE:         $MAX_DATE"
echo "  DROP_START/END:   ${DROP_START:-<none>} / ${DROP_END:-<none>}"
echo "  NO_COVID:         $NO_COVID"
echo "  OUTCOME:          $OUTCOME"
echo "  CS_ANALYTIC:      $CS_ANALYTIC"
echo "  CS_BOOTSTRAP:     $CS_BOOTSTRAP (biters=$CS_BITERS)"
echo "  OUT_DIR:          $OUT_DIR"
echo ""

# Verify data files exist
if [[ ! -f "$MORTGAGE_FILE" ]]; then
  echo "ERROR: MORTGAGE_FILE not found: $MORTGAGE_FILE"
  exit 1
fi
if [[ ! -f "$TREAT_FILE" ]]; then
  echo "ERROR: TREAT_FILE not found: $TREAT_FILE"
  exit 1
fi

# Run
Rscript --vanilla analysis/pretrends/pretrends_mortgage_delinquency.R

echo ""
echo "========================================="
echo "COMPLETED: $(date)"
echo "Output: $OUT_DIR"
echo "========================================="
