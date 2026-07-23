#!/bin/bash
################################################################################
# run_twfe_power_2024_with_me.sh
#
# TWFE power simulation INCLUDING Maine (repaired 2026-07-23 from the Maine
# Judicial Branch court source). Companion to run_twfe_power_no_maine_2024.sh;
# same settings, but ME is no longer excluded and outputs go to a separate dir so
# the old no-Maine run is preserved for comparison. Runs locally (explicit
# data/raw paths, worker count sized for a workstation).
################################################################################

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

export DATA_FILE="${DATA_FILE:-data/raw/combined_monthly_panel.csv}"
export TREAT_FILE="${TREAT_FILE:-data/raw/state_month_panel_with_treatment.csv}"
export EXCLUDE_STATES="${EXCLUDE_STATES:-}"          # ME now included
export MAX_DATE="${MAX_DATE:-2024-12-31}"
export N_SIMS="${N_SIMS:-2000}"
export EFFECT_PCTS="${EFFECT_PCTS:-0,0.03,0.04,0.05,0.06}"
export OUT_DIR="${OUT_DIR:-data/output/twfe_power_out_2024_with_me}"
export N_WORKERS="${N_WORKERS:-6}"
export BATCH_SIZE="${BATCH_SIZE:-50}"
export SEED="${SEED:-123}"

# COVID excluded from the residual pool only (matches the headline no-Maine spec)
export EXCLUDE_START="${EXCLUDE_START:-2020-03-01}"
export EXCLUDE_END="${EXCLUDE_END:-2021-06-01}"

echo "TWFE power simulation (Maine INCLUDED):"
echo "  DATA_FILE:  $DATA_FILE"
echo "  TREAT_FILE: $TREAT_FILE"
echo "  EXCLUDE_STATES: ${EXCLUDE_STATES:-<none>}"
echo "  MAX_DATE:   $MAX_DATE   N_SIMS: $N_SIMS   N_WORKERS: $N_WORKERS"
echo "  OUT_DIR:    $OUT_DIR"
echo ""

Rscript analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R
