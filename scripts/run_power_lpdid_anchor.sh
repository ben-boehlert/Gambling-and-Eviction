#!/usr/bin/env bash
# =============================================================================
# scripts/run_power_lpdid_anchor.sh
#
# LP-DiD cell-anchor comparison (config/power_lpdid_ramp75_anchor.yml):
# 2 windows x 2 anchors at a fixed 12..24 horizon window.
#
# Env vars: N_WORKERS, RUN_NAME, RESUME, SCENARIOS, CONFIG
#   (same semantics as scripts/run_power_cs_probe.sh).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

Rscript --vanilla -e '
  source("R/power/config.R")
  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R")
  source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")

  w  <- Sys.getenv("N_WORKERS", ""); w  <- if (nzchar(w)) as.integer(w) else NULL
  rn <- Sys.getenv("RUN_NAME", "");  rn <- if (nzchar(rn)) rn else NULL
  rs <- toupper(Sys.getenv("RESUME", "TRUE")) != "FALSE"
  cf <- Sys.getenv("CONFIG", "config/power_lpdid_ramp75_anchor.yml")

  sc <- Sys.getenv("SCENARIOS", "")
  sc <- if (!nzchar(sc)) NULL else {
    parts <- trimws(strsplit(sc, ",", fixed = TRUE)[[1]])
    parts <- parts[nzchar(parts)]
    if (all(grepl("^[0-9]+$", parts))) as.integer(parts) else parts
  }

  run_scenario_grid(cf, resume = rs, workers = w, run_name = rn, scenarios = sc)
'
