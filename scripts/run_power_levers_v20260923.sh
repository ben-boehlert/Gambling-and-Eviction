#!/usr/bin/env bash
# Power-lever probes for the June-2022 LP-DiD design (2026-09-23): four blinded
# size gates, one change each against lpdid_l618_pmd3_start202206_noMNWA_gate_v20260921_k7.
# Waits for the RI run (analysis/diagnostics/lpdid_ri_post2022.R) to release the
# cores, then runs the gates one after another. Run from the project root:
#   bash scripts/run_power_levers_v20260923.sh
set -euo pipefail
WORKERS="${WORKERS:-6}"
while pgrep -f "analysis/diagnostics/lpdid_ri_post2022" > /dev/null; do sleep 60; done
for tag in renters vwatt pmd6 pmd6min3; do
  cfg="config/power_lpdid_l618_start202206_gate_${tag}_v20260923_k7.yml"
  echo "=== $(date '+%F %T') START $tag"
  Rscript --vanilla -e 'for (f in c("R/power/config.R","R/power/blindness_checks.R","R/power/inclusion_rule.R","R/power/load_blinded_panel.R","R/power/make_pseudo_schedules.R","R/power/impose_effects.R","R/power/run_estimators.R","R/power/summarize_operating_characteristics.R","R/power/run_scenario_grid.R")) source(f); a <- commandArgs(TRUE); run_scenario_grid(a[1], resume = TRUE, workers = as.integer(a[2]))' "$cfg" "$WORKERS"
  echo "=== $(date '+%F %T') END $tag"
done
