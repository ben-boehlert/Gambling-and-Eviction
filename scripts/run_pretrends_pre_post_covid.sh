#!/bin/bash
################################################################################
# run_pretrends_pre_post_covid.sh
#
# Runs pre-trends diagnostics separately for:
#   1) Pre-COVID (Jan 2016 – Feb 2020), standard legal treatment dates
#   2) Post-COVID (Apr 2022 – Dec 2024), 50% Handle treatment dates
#
# Usage:
#   bash scripts/run_pretrends_pre_post_covid.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "================================================================"
echo "PRE/POST COVID SPLIT ANALYSIS"
echo "================================================================"
echo "Start time: $(date)"

# ==== PART 1: Pre-COVID (Jan 2016 – Feb 2020), standard legal dates ====
echo ""
echo "---- PART 1: Pre-COVID (2016-01 to 2020-02) ----"

MIN_DATE=2016-01-01 \
MAX_DATE=2020-02-29 \
NO_COVID=FALSE \
OUT_DIR=output/pretrends_eviction_precovid \
  bash scripts/run_pretrends_statepanel.sh

# ==== PART 2: Build 50% Handle treatment panel ====
echo ""
echo "---- PART 2: Building 50% Handle treatment panel ----"

Rscript --vanilla data_prep/build_panel_handle50_treatment.R

# ==== PART 3: Post-COVID (Apr 2022 – Dec 2024), 50% Handle treatment ====
echo ""
echo "---- PART 3: Post-COVID (2022-04 to 2024-12), 50% Handle treatment ----"

PANEL_FILE=data/processed/state_month_panel_handle50_treatment.csv \
MIN_DATE=2022-04-01 \
MAX_DATE=2024-12-31 \
NO_COVID=FALSE \
CS_FASTER_MODE=FALSE \
OUT_DIR=output/pretrends_eviction_postcovid_handle50 \
  bash scripts/run_pretrends_statepanel.sh

echo ""
echo "================================================================"
echo "COMPLETED: $(date)"
echo "  Pre-COVID output:  output/pretrends_eviction_precovid"
echo "  Post-COVID output: output/pretrends_eviction_postcovid_handle50"
echo "================================================================"
