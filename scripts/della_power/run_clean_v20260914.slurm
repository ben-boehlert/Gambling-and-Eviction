#!/bin/bash
#SBATCH --job-name=clean_v20260914
#SBATCH --array=1-8
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
# MA +31). The real switcher set moved 13 -> 15 and MA became full-window, so
# every pre-rebuild gate/MDE is on a superseded vintage and cannot be paired
# with anything new. These four configs are byte-identical to their pmd6
# predecessors except for run_name.
#
# LAYOUT: 4 configs x 2 scenarios = 8 array tasks, one scenario per task.
#   task 1,2 -> gate ewatt   (spliced, postcovid)
#   task 3,4 -> mde  ewatt
#   task 5,6 -> gate vwatt
#   task 7,8 -> mde  vwatt
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
)
RUNS=(
  "lpdid_clean_gate_ewatt_pmd6_v20260914"
  "lpdid_clean_mde_ewatt_pmd6_v20260914"
  "lpdid_clean_gate_vwatt_pmd6_v20260914"
  "lpdid_clean_mde_vwatt_pmd6_v20260914"
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
