#!/bin/bash
#SBATCH --job-name=power_primary
#SBATCH --array=1-9
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=71:59:00
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
#   --array=1-9   MUST match the expanded scenario count (9 after the
#                 2026-08-13 S3 drop). Check it with
#                 `bash list_scenarios.sh config/power_primary.yml` — an
#                 out-of-range task id fails loudly rather than silently
#                 skipping work.
#
# 2026-08-13: --time raised 24h -> 72h and --mem 16G -> 32G for the CS arm
# (county+CS needs ~50-63h; the 2026-08-08 attempt was OOM-killed at 16G with
# all work lost pre-checkpointing). Per-batch checkpointing (commit 45e3cc1,
# run_scenario_grid) now makes a timeout/OOM lose at most one batch.
#
# STALE PARTIALS: delete output_blinded_power/primary/ partials produced
# before the 2026-08-10 schedule repair (job 12114571) BEFORE submitting —
# scenario hashes do not encode the input data, so resume would skip them:
#   rm -rf output_blinded_power/primary/
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
#   # or, once every task has finished:  bash run_aggregate.sh

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
