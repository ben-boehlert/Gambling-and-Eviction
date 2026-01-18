#!/bin/bash
################################################################################
# test_pretrends_local.sh
#
# Quick smoke test for pre-trends diagnostics (local execution)
# Runs with minimal bootstrap iterations for fast verification
################################################################################

set -euo pipefail

echo "========================================="
echo "PRE-TRENDS DIAGNOSTICS: LOCAL SMOKE TEST"
echo "========================================="
echo "Start time: $(date)"
echo ""

# Navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || {
  echo "ERROR: Could not cd to repo root"
  exit 1
}

echo "Working directory: $(pwd)"
echo ""

# ----------------------------- verify files exist -----------------------------

export DATA_FILE="${DATA_FILE:-combined_monthly_panel.csv}"
export TREAT_FILE="${TREAT_FILE:-state_month_panel_with_treatment.csv}"

if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: DATA_FILE not found: $DATA_FILE"
  echo ""
  echo "This test expects data files in the repo root."
  echo "If your data files are elsewhere, set DATA_FILE and TREAT_FILE env vars."
  exit 1
fi

if [[ ! -f "$TREAT_FILE" ]]; then
  echo "ERROR: TREAT_FILE not found: $TREAT_FILE"
  echo ""
  echo "This test expects data files in the repo root."
  echo "If your data files are elsewhere, set DATA_FILE and TREAT_FILE env vars."
  exit 1
fi

echo "✓ Data files found"
echo "  DATA_FILE:  $DATA_FILE"
echo "  TREAT_FILE: $TREAT_FILE"
echo ""

# ----------------------------- verify R script exists -------------------------

R_SCRIPT="analysis/pretrends_eventstudy_diagnostics.R"

if [[ ! -f "$R_SCRIPT" ]]; then
  echo "ERROR: R script not found: $R_SCRIPT"
  exit 1
fi

echo "✓ R script found: $R_SCRIPT"
echo ""

# ----------------------------- run test ---------------------------------------

echo "Running quick test (minimal bootstrap)..."
echo ""

export OUT_DIR="pretrends_test_$(date +%Y%m%d_%H%M%S)"
export OUTCOME="log1p_filings_count"
export RATE_EPS="0.01"
export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"
export DROP_START=""
export DROP_END=""
export MIN_STATES_PER_MONTH="5"
export ALPHA="0.05"
export SEED="123"
export MIN_E="-24"
export MAX_E="24"
export BALANCE_E=""
export DID_EST_METHOD="reg"
export DID_CONTROL_GROUP="notyettreated"
export DID_ALLOW_UNBALANCED="TRUE"
export DID_BSTRAP="TRUE"
export DID_BITERS="19"  # Minimal bootstrap for speed
export RUN_TWFE_ES="TRUE"

echo "Configuration:"
echo "  OUT_DIR:      $OUT_DIR"
echo "  DID_BSTRAP:   $DID_BSTRAP (biters=$DID_BITERS)"
echo "  RUN_TWFE_ES:  $RUN_TWFE_ES"
echo ""

Rscript "$R_SCRIPT"

TEST_STATUS=$?

echo ""
echo "========================================="

if [[ $TEST_STATUS -ne 0 ]]; then
  echo "❌ TEST FAILED (exit code $TEST_STATUS)"
  echo "========================================="
  exit $TEST_STATUS
fi

echo "✅ TEST PASSED"
echo "========================================="
echo ""

# ----------------------------- verify outputs ---------------------------------

echo "Verifying outputs..."
echo ""

REQUIRED_FILES=(
  "run_pretrends.log"
  "panel_summary.csv"
  "untreated_support_by_month.csv"
  "support_by_event_time.csv"
  "cs_event_study.csv"
  "cs_event_study.png"
  "cs_pretrends_joint_test.csv"
)

# TWFE outputs (should exist since RUN_TWFE_ES=TRUE)
TWFE_FILES=(
  "twfe_event_study.csv"
  "twfe_event_study.png"
)

ALL_FOUND=true

for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$OUT_DIR/$file" ]]; then
    echo "  ✓ $file"
  else
    echo "  ❌ MISSING: $file"
    ALL_FOUND=false
  fi
done

for file in "${TWFE_FILES[@]}"; do
  if [[ -f "$OUT_DIR/$file" ]]; then
    echo "  ✓ $file"
  else
    echo "  ⚠ TWFE output not found (may have failed): $file"
  fi
done

echo ""

if [[ "$ALL_FOUND" == false ]]; then
  echo "❌ VERIFICATION FAILED: Some required files missing"
  exit 1
fi

echo "✅ ALL REQUIRED OUTPUTS VERIFIED"
echo ""

# ----------------------------- display summary --------------------------------

echo "Output directory: $OUT_DIR"
echo ""

if [[ -f "$OUT_DIR/run_pretrends.log" ]]; then
  echo "Log excerpt:"
  tail -20 "$OUT_DIR/run_pretrends.log" | sed 's/^/  /'
  echo ""
fi

if [[ -f "$OUT_DIR/panel_summary.csv" ]]; then
  echo "Panel summary:"
  cat "$OUT_DIR/panel_summary.csv" | sed 's/^/  /'
  echo ""
fi

if [[ -f "$OUT_DIR/cs_pretrends_joint_test.csv" ]]; then
  echo "CS-DiD pre-trends joint test:"
  cat "$OUT_DIR/cs_pretrends_joint_test.csv" | sed 's/^/  /'
  echo ""
fi

echo "========================================="
echo "SMOKE TEST COMPLETE"
echo "========================================="
echo "End time: $(date)"
echo ""
echo "Next steps:"
echo "  1. Review outputs in: $OUT_DIR"
echo "  2. Check event-study plots (.png files)"
echo "  3. Examine pre-trends test results"
echo "  4. Run full bootstrap (DID_BITERS=199 or 999) for publication"
echo ""
