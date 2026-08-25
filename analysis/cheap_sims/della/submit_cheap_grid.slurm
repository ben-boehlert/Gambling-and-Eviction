#!/bin/bash
#SBATCH --job-name=cheap_power_sim
#SBATCH --output=cheap_power_sim_%A_%a.out
#SBATCH --array=0-9
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=06:00:00

# Cheap-sim grid on Della, split by replication block (one output shard per
# array task; merge with della/merge_results.R). Only needed if the local run
# is impractical -- as measured 2026-08-12 the full 250-rep grid runs in ~1-2 h
# on a laptop, so this exists for 1,000+ rep escalation only.
#
# Setup mirrors della_power_upload/ (see scripts/della_power/README.txt):
# rsync the repo to /scratch/gpfs/DESMOND/ben/eviction_gambling/ and run
# setup.sh there first (installs did/fixest/tidyverse into the project lib).
# Inspect available R modules with `module avail R` -- do not assume names.

module purge
module load R/4.5   # adjust to an available module (module avail R)

cd "$SLURM_SUBMIT_DIR/../../.."   # repo root

REPS_PER_TASK=${REPS_PER_TASK:-100}
START=$(( SLURM_ARRAY_TASK_ID * REPS_PER_TASK + 1 ))

# Each task writes its own shard dir: no simultaneous writes to a shared CSV.
N_REPS=$(( START + REPS_PER_TASK - 1 )) \
CHEAP_REP_START=$START \
CHEAP_OUT_DIR="output/cheap_power_sim/della_shard_${SLURM_ARRAY_TASK_ID}" \
N_CORES=$SLURM_CPUS_PER_TASK \
Rscript analysis/cheap_sims/02_run_cheap_grid.R
