#!/bin/bash
################################################################################
# run_cs_power_threshold_sweep_no_maine_2024_min5.sh
#
# Callaway-Sant'Anna (did::att_gt + aggte) power sweep across state coverage
# thresholds, excluding Maine and extending to end of 2024.
#
# This matches the TWFE "min5" setup by excluding COVID months from the
# residual pool (NOT from the analysis panel).
################################################################################

set -euo pipefail

export DATA_FILE="${DATA_FILE:-backup_cleanup_20260112_094739/combined_monthly_panel.csv}"
export TREAT_FILE="${TREAT_FILE:-backup_cleanup_20260112_094739/state_month_panel_with_treatment.csv}"

export EXCLUDE_STATES="${EXCLUDE_STATES:-ME}"
export MAX_DATE="${MAX_DATE:-2024-12-31}"

export OUTCOME="${OUTCOME:-log1p_filings_count}"
export RATE_EPS="${RATE_EPS:-0.01}"

export N_SIMS="${N_SIMS:-50}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.05,0.1,0.15,0.2}"
export COVERAGE_THRESHOLDS="${COVERAGE_THRESHOLDS:-0,40,60,80,100,108}"
export ALPHA="${ALPHA:-0.05}"
export SEED="${SEED:-123}"

export MIN_STATES_PER_MONTH="${MIN_STATES_PER_MONTH:-5}"

export DID_FASTER_MODE="${DID_FASTER_MODE:-FALSE}"
export DID_BSTRAP="${DID_BSTRAP:-FALSE}"
export DID_BITERS="${DID_BITERS:-199}"
export DID_ALLOW_UNBALANCED_PANEL="${DID_ALLOW_UNBALANCED_PANEL:-FALSE}"

export N_CORES="${N_CORES:-1}"

# Exclude COVID period from residual pool (same defaults as TWFE min5 script)
export EXCLUDE_START="${EXCLUDE_START:-2020-03-01}"
export EXCLUDE_END="${EXCLUDE_END:-2021-06-01}"

export OUT_DIR="${OUT_DIR:-output/cs_threshold_sweep_no_maine_2024_min5}"

echo "Running CS coverage-threshold sweep (COVID excluded from residual pool):"
echo "  - Data: $DATA_FILE"
echo "  - Treat: $TREAT_FILE"
echo "  - Excluding state(s): $EXCLUDE_STATES"
echo "  - Max date: $MAX_DATE"
echo "  - Out: $OUT_DIR"
echo "  - N_SIMS: $N_SIMS"
echo "  - Effects: $EFFECT_PCTS"
echo "  - Coverage thresholds: $COVERAGE_THRESHOLDS"
echo "  - Outcome: $OUTCOME (RATE_EPS=$RATE_EPS)"
echo "  - min states/month (resid pool): $MIN_STATES_PER_MONTH"
echo "  - Residual-pool COVID exclusion: $EXCLUDE_START to $EXCLUDE_END"
echo "  - DID_FASTER_MODE: $DID_FASTER_MODE  DID_BSTRAP: $DID_BSTRAP (biters=$DID_BITERS)"
echo "  - DID_ALLOW_UNBALANCED_PANEL: $DID_ALLOW_UNBALANCED_PANEL"
echo "  - N_CORES: $N_CORES"
echo ""

Rscript analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R
