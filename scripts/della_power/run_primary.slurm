#!/bin/bash
#SBATCH --job-name=power_primary
#SBATCH --array=1-11
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=23:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-primary-%A_%a.out

# Primary scenario grid of the blinded power simulation
# (config/power_primary.yml), ONE SCENARIO PER ARRAY TASK.
#
# Why an array rather than one big job: the monolithic 32-core version needed
# ~72h of medium-QOS wall clock and a single timeout lost the whole tail. Each
# scenario here is independent and fits comfortably in the 24h short QOS, the
# tasks queue separately (better turnaround), and a failure costs one scenario
# instead of the run.
#
#   --array=1-11  MUST match the expanded scenario count. Check it with
#                 `bash list_scenarios.sh config/power_primary.yml` — an
#                 out-of-range task id fails loudly rather than silently
#                 skipping work.
#
# Resume-safe: re-submitting skips scenarios whose partial is already
# complete, so `sbatch run_primary.slurm` after a partial failure only re-runs
# what is missing. Scenario ids are content hashes, so editing one block in
# the config does NOT invalidate the others' partials.
#
# AFTER the array finishes, run the aggregation pass — the array tasks write
# per-scenario partials only, never the shared run-level summaries:
#
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm
#   # or, once the array is done:  bash run_aggregate.sh config/power_primary.yml primary

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
  run_scenario_grid("config/power_primary.yml",
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = "primary",
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
