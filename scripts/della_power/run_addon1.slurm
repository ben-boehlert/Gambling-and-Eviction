#!/bin/bash
#SBATCH --job-name=power_addon1
#SBATCH --array=1-3
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=1-23:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-addon1-%A_%a.out

# First add-on scenario set (config/power_addon1.yml): handle-calibrated
# intensity_ramp + cohort_het (honest MDE), county + state. Run AFTER the
# cheap grid — see the config header. One scenario per array task; county
# tasks ~28-30h, state task a few hours. Batch-checkpointed: crashes lose at
# most one 25-rep batch, resubmitting resumes.
#
# AFTER the array finishes:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm addon1
#   # or:  bash run_aggregate.sh addon1

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
  run_scenario_grid("config/power_addon1.yml",
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = "addon1",
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
