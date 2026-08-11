#!/bin/bash
#SBATCH --job-name=power_cheap
#SBATCH --array=1-8
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=1-23:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-cheap-%A_%a.out

# CHEAP pilot of the primary grid (config/power_cheap.yml): TWFE + did2s
# only, no CS, ONE SCENARIO PER ARRAY TASK. Purpose: prove the full
# pipeline end-to-end and bank the cheap-estimator operating
# characteristics before the expensive att_gt runs.
#
# Pacing (from the 12114571 primary logs): a county scenario without CS is
# ~25 batches-hours (~1.5h per 25-rep batch x 20 batches ~ 28-30h), hence
# the 48h limit; state scenarios finish in a few hours.
#
#   --array=1-8  MUST match the expanded scenario count. Check it with
#                `bash list_scenarios.sh config/power_cheap.yml`.
#
# Resume-safe: re-submitting skips scenarios whose partial is already
# complete. Scenario ids are content hashes, so this run's partials live
# independently of the primary run's (different estimator set => different
# ids, and a different run_name => different output directory).
#
# AFTER the array finishes:
#
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm cheap
#   # or, once every task has finished:  bash run_aggregate.sh cheap

set -e
module purge
module load R/4.4.2

# No hardcoded scratch path: run from wherever this folder was uploaded.
cd "$SLURM_SUBMIT_DIR"

export N_WORKERS="${SLURM_CPUS_PER_TASK}"
export SCENARIO_IDX="${SLURM_ARRAY_TASK_ID}"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  run_scenario_grid("config/power_cheap.yml",
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = "cheap",
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
