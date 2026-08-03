#!/bin/bash
#SBATCH --job-name=power_agg
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=03:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-agg-%j.out

# Aggregation pass for an array-based power run.
#
# The array tasks in run_primary.slurm / run_sensitivity.slurm write ONLY
# per-scenario partials — if they each wrote the run-level summaries they
# would race on the same files. This job stacks the partials and writes
# results_raw.csv.gz, oc_summary.csv, mde_table.csv, pretrend_summary.csv,
# failures.csv, scenario_truths.csv and run_metadata.json.
#
# It re-runs any scenario whose partial is missing or incomplete, so it also
# doubles as a "did the array actually finish?" check: if every task
# succeeded it just summarizes (a few minutes); if one failed, it computes
# that scenario here.
#
# Usage:
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm            # primary
#   sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm sensitivity
#
# Arg 1 (optional): "primary" (default) or "sensitivity".

set -e
module purge
module load R/4.4.2

cd "$SLURM_SUBMIT_DIR"

RUN="${1:-primary}"
case "$RUN" in
  primary)     CONFIG="config/power_primary.yml" ;;
  sensitivity) CONFIG="config/power_sensitivity.yml" ;;
  *) echo "run_aggregate.slurm: unknown run '$RUN' (want primary|sensitivity)" >&2
     exit 1 ;;
esac

export N_WORKERS="${SLURM_CPUS_PER_TASK}"
export AGG_CONFIG="$CONFIG"
export AGG_RUN="$RUN"

echo "Aggregating run '$RUN' from $CONFIG"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  # No `scenarios` argument = full grid = writes the run-level summaries.
  run_scenario_grid(Sys.getenv("AGG_CONFIG"),
                    resume   = TRUE,
                    workers  = as.integer(Sys.getenv("N_WORKERS")),
                    run_name = Sys.getenv("AGG_RUN"))
'
