#!/bin/bash
################################################################################
# run_mortgage_pretrends_full.sh
#
# Complete pipeline for mortgage delinquency pre-trends analysis
#
# Usage: bash scripts/run_mortgage_pretrends_full.sh
################################################################################

set -e  # Exit on error

echo "========================================================================"
echo "MORTGAGE DELINQUENCY PRE-TRENDS ANALYSIS - FULL PIPELINE"
echo "========================================================================"
echo ""

# Check required input file
if [ ! -f "StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv" ]; then
    echo "ERROR: Input file not found: StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv"
    exit 1
fi

if [ ! -f "data/raw/sports_gambling_legalization_dates.csv" ]; then
    echo "ERROR: Gambling dates file not found: data/raw/sports_gambling_legalization_dates.csv"
    exit 1
fi

echo "✓ Input files verified"
echo ""

# Step 1: Create mortgage delinquency panel
echo "========================================================================"
echo "STEP 1: Creating mortgage delinquency panel (wide to long)"
echo "========================================================================"
Rscript analysis/create_mortgage_delinquency_panel.R

if [ ! -f "data/processed/mortgage_delinquency_panel.csv" ]; then
    echo "ERROR: Failed to create mortgage_delinquency_panel.csv"
    exit 1
fi

echo "✓ Mortgage panel created"
echo ""

# Step 2: Merge treatment dates
echo "========================================================================"
echo "STEP 2: Merging treatment dates"
echo "========================================================================"
Rscript analysis/create_mortgage_treatment_panel.R

if [ ! -f "data/processed/mortgage_treatment_panel.csv" ]; then
    echo "ERROR: Failed to create mortgage_treatment_panel.csv"
    exit 1
fi

echo "✓ Treatment panel created"
echo ""

# Step 3: Run pre-trends analysis
echo "========================================================================"
echo "STEP 3: Running pre-trends analysis"
echo "========================================================================"
Rscript analysis/mortgage_delinquency_pretrends_simple.R

if [ ! -f "mortgage_delinquency_out/comparison/pretrends_summary.csv" ]; then
    echo "ERROR: Pre-trends analysis did not complete successfully"
    exit 1
fi

echo "✓ Pre-trends analysis complete"
echo ""

# Step 4: Run diagnostics
echo "========================================================================"
echo "STEP 4: Running data diagnostics"
echo "========================================================================"
Rscript analysis/diagnostic_mortgage_data.R

if [ ! -f "mortgage_delinquency_out/diagnostics_trends.png" ]; then
    echo "ERROR: Diagnostics did not complete successfully"
    exit 1
fi

echo "✓ Diagnostics complete"
echo ""

# Summary
echo "========================================================================"
echo "PIPELINE COMPLETE"
echo "========================================================================"
echo ""
echo "Output files:"
echo "  - Data: data/processed/mortgage_treatment_panel.csv"
echo "  - Results: mortgage_delinquency_out/"
echo "  - Summary: MORTGAGE_PRETRENDS_ANALYSIS_SUMMARY.md"
echo ""

# Display key results
echo "Key Results:"
echo "------------"
if command -v column &> /dev/null; then
    tail -n +2 mortgage_delinquency_out/comparison/pretrends_summary.csv | \
        awk -F',' '{printf "%-40s | F=%-8.2f | p=%s | %s\n", $1, $2, $3, $5}'
else
    cat mortgage_delinquency_out/comparison/pretrends_summary.csv
fi

echo ""
echo "See MORTGAGE_PRETRENDS_ANALYSIS_SUMMARY.md for detailed interpretation"
echo ""
