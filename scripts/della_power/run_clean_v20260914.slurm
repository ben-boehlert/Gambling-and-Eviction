#!/bin/bash
#SBATCH --job-name=clean_v20260914
#SBATCH --array=1-16
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=23:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-clean-v20260914-%A_%a.out

# Clean-anchor gate + MDE re-run on the 2026-09-14 PANEL VINTAGE.
#
# WHY THIS EXISTS. The 6 Eviction Lab single-series states were rebuilt from
# the internal county extract on 2026-09-14 (RI +77 months, MO/NM +41,
# MA +31), and OREGON was added as a new state (OJD PDFs + dashboard, seam
# 0.9905 on 12 overlapping months, unadjusted and disclosed). The panel is now
# 40 states / 4,174 rows; the real switcher set moved 13 -> 16, full-window
# 6 -> 7, MA became full-window and RI and OR joined. Every pre-rebuild
# gate/MDE is on a superseded vintage and cannot be paired with anything new.
# These configs are byte-identical to their pmd6 predecessors except run_name
# and the reverted eligibility window.
#
# LAYOUT: 8 configs x 2 scenarios = 16 array tasks, one scenario per task.
#   task  1,2  -> gate ewatt          (spliced, postcovid)
#   task  3,4  -> mde  ewatt
#   task  5,6  -> gate vwatt
#   task  7,8  -> mde  vwatt
#   task  9,10 -> gate ewatt  noMO
#   task 11,12 -> mde  ewatt  noMO
#   task 13,14 -> gate vwatt  noMO
#   task 15,16 -> mde  vwatt  noMO
#
# ELIGIBILITY WINDOW (2026-09-14) -- session memo open decision 1, RESOLVED.
# These configs were patched to min_pre 18 / min_post 12, which places 0 of 25
# seeds under D1. The blocker was the 12, not the 18: the estimator needs at
# least ONE outcome horizon, not all thirteen (outcomes run launch+12..launch+24
# and a state contributes at whatever horizons it has -- memo correction #4).
# Settled at (18, 0): min_pre 18 reaches launch-6, the first month the strict
# PMD=6 baseline needs; min_post 0 requires the series to reach launch+12, the
# first outcome. Verified on the current 40-state panel -- (18,0) and (18,1)
# place 25/25; (15,6), (18,3), (18,6), (12,9) and (18,12) all place 0/25.
# (18,0) admits the same 23 treated states as (12,6) but raises the states that
# actually CONTRIBUTE from ~11.0 to ~15.3 of 23 (48% -> 66%), because (12,6)
# simultaneously admitted states with no baseline and demanded six post-months
# nothing uses. Residual caveat: min_pre is still an ENDPOINT test, so it
# guarantees the series STARTS early enough, not that the six baseline months
# are present -- the COVID hole is invisible to it. Probes:
# analysis/diagnostics/{eligibility_window_feasibility,d1_placement_autopsy}.R
#
# Resume-safe: re-submitting skips scenarios whose partial is already complete.
# Array tasks write per-scenario PARTIALS ONLY. You must run the aggregation
# pass afterwards or there will be no oc_summary.csv / mde_table*.csv:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm
#
# --time is 24h (short QOS) not 72h: these are state-level LP-DiD arms, which
# ran in minutes-to-hours pre-rebuild. The 72h/32G ceiling in run_primary.slurm
# exists for the county+CS arm, which this does not touch.

set -e
module purge
module load R/4.4.2
cd "$SLURM_SUBMIT_DIR"

CONFIGS=(
  "config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml"
  "config/power_lpdid_clean_mde_ewatt_pmd6_v20260914.yml"
  "config/power_lpdid_clean_gate_vwatt_pmd6_v20260914.yml"
  "config/power_lpdid_clean_mde_vwatt_pmd6_v20260914.yml"
  "config/power_lpdid_clean_gate_ewatt_pmd6_v20260914_noMO.yml"
  "config/power_lpdid_clean_mde_ewatt_pmd6_v20260914_noMO.yml"
  "config/power_lpdid_clean_gate_vwatt_pmd6_v20260914_noMO.yml"
  "config/power_lpdid_clean_mde_vwatt_pmd6_v20260914_noMO.yml"
)
RUNS=(
  "lpdid_clean_gate_ewatt_pmd6_v20260914"
  "lpdid_clean_mde_ewatt_pmd6_v20260914"
  "lpdid_clean_gate_vwatt_pmd6_v20260914"
  "lpdid_clean_mde_vwatt_pmd6_v20260914"
  "lpdid_clean_gate_ewatt_pmd6_v20260914_noMO"
  "lpdid_clean_mde_ewatt_pmd6_v20260914_noMO"
  "lpdid_clean_gate_vwatt_pmd6_v20260914_noMO"
  "lpdid_clean_mde_vwatt_pmd6_v20260914_noMO"
)

I=$(( (SLURM_ARRAY_TASK_ID - 1) / 2 ))   # 0..3 -> which config
S=$(( (SLURM_ARRAY_TASK_ID - 1) % 2 + 1 ))  # 1..2 -> which scenario

export N_WORKERS="${SLURM_CPUS_PER_TASK}"
export CFG="${CONFIGS[$I]}"
export RUN="${RUNS[$I]}"
export SCENARIO_IDX="${S}"

echo "task ${SLURM_ARRAY_TASK_ID}: config=${CFG} run_name=${RUN} scenario=${S}"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  run_scenario_grid(Sys.getenv("CFG"),
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = Sys.getenv("RUN"),
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
