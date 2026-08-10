#!/bin/bash
#SBATCH --job-name=power_smoke
#SBATCH --array=1-2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=05:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-smoke-%A_%a.out

# 2-scenario SMOKE TEST (config/power_smoke.yml): county + state headline
# cells, 50 reps, 4 deltas, TWFE + did2s. Validates the full
# array -> partials -> aggregate pipeline in ~1h (county) / minutes (state)
# before the 28-30h county scenarios of run_cheap.slurm.
#
# AFTER both tasks finish:
#
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm smoke
#   # or:  bash run_aggregate.sh smoke
#
# Success criteria: 2 partials in output_blinded_power/smoke/partials/,
# aggregate writes oc_summary.csv / mde_table.csv, size at delta=0 is
# plausible (within MC noise of alpha), and power rises with delta.

set -e
module purge
module load R/4.4.2

cd "$SLURM_SUBMIT_DIR"

export N_WORKERS="${SLURM_CPUS_PER_TASK}"
export SCENARIO_IDX="${SLURM_ARRAY_TASK_ID}"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  run_scenario_grid("config/power_smoke.yml",
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = "smoke",
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
