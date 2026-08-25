#!/bin/bash
################################################################################
# test_pretrends_treatment_routing.sh
#
# Lightweight regression tests for the panel-treatment routing contract.
# CS estimation and bootstrap arms are disabled; Sun-Abraham is a smoke test.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

QA_OUT_DIR="$(mktemp -d /tmp/pretrends-treatment-routing.XXXXXX)"
export QA_OUT_DIR
trap 'rm -rf "$QA_OUT_DIR"' EXIT

# Static contract: the post-COVID Handle run must make panel routing explicit.
rg -q '^TREAT_SOURCE=panel \\' scripts/run_pretrends_pre_post_covid.sh
rg -q '^EXPECTED_TREAT_SOURCE=panel \\' \
  scripts/run_pretrends_pre_post_covid.sh
rg -q '^REQUIRE_PANEL_TREATMENT=TRUE \\' \
  scripts/run_pretrends_pre_post_covid.sh

# Shell entry point must reject a source mismatch before launching R.
if TREAT_SOURCE=file \
  EXPECTED_TREAT_SOURCE=panel \
  REQUIRE_PANEL_TREATMENT=TRUE \
  CS_ANALYTIC=FALSE \
  CS_BOOTSTRAP=FALSE \
  OUT_DIR="$QA_OUT_DIR/negative_shell" \
  bash scripts/run_pretrends_statepanel.sh >/dev/null 2>&1; then
  echo "ERROR: shell treatment-source mismatch was not rejected."
  exit 1
fi

# Direct R entry point must enforce the same contract independently.
if TREAT_SOURCE=file \
  EXPECTED_TREAT_SOURCE=panel \
  REQUIRE_PANEL_TREATMENT=TRUE \
  OUT_DIR="$QA_OUT_DIR/negative_r" \
  Rscript --vanilla \
    analysis/pretrends/pretrends_statepanel_template.R >/dev/null 2>&1; then
  echo "ERROR: R treatment-source mismatch was not rejected."
  exit 1
fi

# Positive smoke test: use the embedded Handle-50 schedule and skip both CS arms.
PANEL_FILE=data/processed/state_month_panel_handle50_treatment.csv \
TREAT_SOURCE=panel \
EXPECTED_TREAT_SOURCE=panel \
REQUIRE_PANEL_TREATMENT=TRUE \
MIN_DATE=2022-04-01 \
MAX_DATE=2024-12-31 \
NO_COVID=FALSE \
CS_ANALYTIC=FALSE \
CS_BOOTSTRAP=FALSE \
SELF_TEST=FALSE \
OUT_DIR="$QA_OUT_DIR/positive" \
  bash scripts/run_pretrends_statepanel.sh >/dev/null

Rscript --vanilla -e '
  out_dir <- file.path(Sys.getenv("QA_OUT_DIR"), "positive")
  summary <- read.csv(file.path(out_dir, "panel_summary.csv"))
  schedule <- read.csv(file.path(out_dir, "treatment_schedule_resolved.csv"))
  stopifnot(nrow(summary) == 1L)
  stopifnot(identical(summary$treat_source, "panel"))
  stopifnot(identical(summary$expected_treat_source, "panel"))
  stopifnot(isTRUE(summary$require_panel_treatment))
  stopifnot(identical(summary$resolved_treat_date_col, "treat_start"))
  stopifnot(nrow(schedule) == summary$n_states)
  stopifnot(all(schedule$treatment_source == "panel"))
  stopifnot(all(schedule$resolved_matches_panel))
  stopifnot(!any(schedule$state_abb %in% c("FL", "NV")))
  stopifnot(!any(
    is.na(schedule$resolved_treat_start) &
      !is.na(schedule$control_eligible) &
      !schedule$control_eligible
  ))
  stopifnot(file.exists(file.path(out_dir, "treatment_schedule_resolved.rds")))
'

echo "PASS: treatment routing contract and resolved schedule audit."
