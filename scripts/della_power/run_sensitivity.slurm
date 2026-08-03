#!/bin/bash
#SBATCH --job-name=power_sens
#SBATCH --array=1-26
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=23:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-sens-%A_%a.out

# Sensitivity grid of the blinded power simulation
# (config/power_sensitivity.yml), ONE SCENARIO PER ARRAY TASK.
# See run_primary.slurm for the rationale and the resume/aggregate contract.
#
#   --array=1-26  MUST match the expanded scenario count. Check it with
#                 `bash list_scenarios.sh config/power_sensitivity.yml`.
#
# Every sensitivity scenario is state-level, so these tasks are much cheaper
# than the county scenarios in the primary grid.
#
# AFTER the array finishes:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm sensitivity

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
  run_scenario_grid("config/power_sensitivity.yml",
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = "sensitivity",
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
