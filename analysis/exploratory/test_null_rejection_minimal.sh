#!/bin/bash
################################################################################
# Minimal reproducible test for CS-DiD p-value fix
# Tests that rejection rate under null (effect_pct=0) is ~5% at alpha=0.05
#
# Run from anywhere - script will find the correct paths
################################################################################

# Get the directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "==================================================================="
echo "CS-DiD P-Value Fix - Minimal Test (N_SIMS=200, effect_pct=0)"
echo "==================================================================="
echo ""
echo "Repository root: ${REPO_ROOT}"
echo ""
echo "Expected outcome:"
echo "  - Rejection rate: ~5% (between 2% and 8% is reasonable with N=200)"
echo "  - P-value quantiles: 5th~0.05, 50th~0.50, 95th~0.95"
echo ""
echo "Starting test..."
echo ""

# Set environment for minimal test
export DATA_FILE="${REPO_ROOT}/combined_monthly_panel.csv"
export TREAT_FILE="${REPO_ROOT}/state_month_panel_with_treatment.csv"
export N_SIMS=200
export N_WORKERS=1
export EFFECT_PCTS="0"
export ALPHA=0.05
export DID_CONTROL_GROUP=notyettreated
export DID_BSTRAP=TRUE
export DID_BITERS=199
export OUT_DIR="${REPO_ROOT}/cs_reg_power_out_TEST_NULL"

# Remove old test output
rm -rf "${OUT_DIR}"

# Run simulation
Rscript "${SCRIPT_DIR}/power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R"

# Check results
echo ""
echo "==================================================================="
echo "TEST RESULTS"
echo "==================================================================="

if [ -f "${OUT_DIR}/diagnostics_sanity.csv" ]; then
  echo ""
  echo "Null diagnostics (all N_SIMS):"
  cat "${OUT_DIR}/diagnostics_sanity.csv"
  echo ""
fi

if [ -f "${OUT_DIR}/null_pvalues_first200.csv" ]; then
  echo ""
  echo "First 200 p-values saved to: ${OUT_DIR}/null_pvalues_first200.csv"
  echo "Number of p-values collected:"
  tail -n +2 "${OUT_DIR}/null_pvalues_first200.csv" | wc -l
  echo ""
fi

if [ -f "${OUT_DIR}/run.log" ]; then
  echo ""
  echo "Null p-value diagnostic (from run.log):"
  grep -A 6 "NULL P-VALUE DIAGNOSTIC" "${OUT_DIR}/run.log"
  echo ""
fi

echo ""
echo "==================================================================="
echo "INTERPRETATION GUIDE"
echo "==================================================================="
echo ""
echo "If the fix works correctly, you should see:"
echo "  ✓ Rejection rate between 2-8% (expected: 5%)"
echo "  ✓ P-value 5th percentile near 0.05 (range: 0.02-0.08)"
echo "  ✓ P-value 50th percentile near 0.50 (range: 0.40-0.60)"
echo "  ✓ P-value 95th percentile near 0.95 (range: 0.90-0.98)"
echo ""
echo "If the bug is still present, you would see:"
echo "  ✗ Rejection rate 0% or near 0%"
echo "  ✗ P-value quantiles heavily skewed toward 1.0"
echo ""
echo "Full results in: ${OUT_DIR}/"
echo "==================================================================="
