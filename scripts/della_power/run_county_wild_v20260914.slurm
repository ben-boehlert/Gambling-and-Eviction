#!/bin/bash
#SBATCH --job-name=county_wild_v20260914
#SBATCH --array=1-2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=11:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-county-wild-v20260914-%A_%a.out

# COUNTY LP-DiD wild size gate, clean 12-24 design, 2,000 reps x 2 scenarios.
#
# WHY. The analytic county arm has a 24% tighter sampling distribution than the
# state arm and half the null bias, but fails size at 0.157 (SE/SD 0.85). Only
# a size-valid wild arm can cash that. The 300-rep smoke landed at 0.060 —
# inside the [0.055, 0.09] escalation band — so this goes straight to 2,000.
#
# LAYOUT: 1 config x 2 scenarios = 2 array tasks, one scenario per task.
#   task 1 -> spliced      (covid: drop)
#   task 2 -> postcovid    (covid: post)
#
# SIZING. Measured locally 2026-09-14: the county panel costs ~11 core-seconds
# per rep and the wild arm adds only ~0.3-0.8s on top (boottest is a score
# bootstrap, B=999). 2,000 reps at 16 cpus is well under an hour per task; the
# 12h ceiling and 64G are headroom, not an estimate. This is NOT the county+CS
# arm that OOM'd at 42h/32G in 2026-08.
#
# RESUME-SAFE at 25-rep granularity: run_scenario_grid appends each batch to the
# partial and records it in a sidecar, so a timeout or preemption loses at most
# the trailing batch. Re-submit the same array to continue.
#
# PAIRING. Compare ONLY against lpdid_clean_gate_ewatt_pmd6_v20260914 (same
# panel vintage), never against the 2026-08-28 pre-rebuild state gate. Submit
# run_clean_v20260914.slurm too if that comparator has not been produced yet.
#
# Array tasks write per-scenario PARTIALS ONLY. Run the aggregation pass after:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm

set -e
module purge
module load R/4.4.2
cd "$SLURM_SUBMIT_DIR"

CFG="config/power_lpdid_clean_gate_county_ewatt_pmd6_wild_v20260914.yml"
RUN="lpdid_clean_gate_county_ewatt_pmd6_wild_v20260914"

export N_WORKERS="${SLURM_CPUS_PER_TASK}"
export CFG RUN
export SCENARIO_IDX="${SLURM_ARRAY_TASK_ID}"

echo "task ${SLURM_ARRAY_TASK_ID}: config=${CFG} run_name=${RUN} scenario=${SCENARIO_IDX}"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/impose_effects.R");     source("R/power/run_estimators.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  run_scenario_grid(Sys.getenv("CFG"),
                    resume    = TRUE,
                    workers   = as.integer(Sys.getenv("N_WORKERS")),
                    run_name  = Sys.getenv("RUN"),
                    scenarios = as.integer(Sys.getenv("SCENARIO_IDX")))
'
