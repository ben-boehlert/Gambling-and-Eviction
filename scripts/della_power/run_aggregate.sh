#!/bin/bash
# Login-node aggregation pass for an array-based power run.
#
# The array tasks write ONLY per-scenario partials (they would otherwise race
# on the shared run-level files). This stacks them and writes
# results_raw.csv.gz, oc_summary.csv, mde_table.csv, pretrend_summary.csv,
# failures.csv, scenario_truths.csv and run_metadata.json.
#
# SAFETY: run_scenario_grid() re-runs any scenario whose partial is missing or
# incomplete. On a login node that would mean computing a ~51 core-hour
# scenario on a shared machine. So this script REFUSES to proceed unless every
# partial is already complete, and tells you to use the SLURM version instead:
#
#   sbatch run_aggregate.slurm [primary|sensitivity]
#
# Usage:
#   bash run_aggregate.sh              # primary (default)
#   bash run_aggregate.sh sensitivity
set -e
cd "$(dirname "$0")"

module purge
module load R/4.4.2

RUN="${1:-primary}"
case "$RUN" in
  primary)     CONFIG="config/power_primary.yml" ;;
  sensitivity) CONFIG="config/power_sensitivity.yml" ;;
  cheap)       CONFIG="config/power_cheap.yml" ;;
  smoke)       CONFIG="config/power_smoke.yml" ;;
  addon1)      CONFIG="config/power_addon1.yml" ;;
  *) echo "run_aggregate.sh: unknown run '$RUN' (want primary|sensitivity|cheap|smoke|addon1)" >&2
     exit 1 ;;
esac

export AGG_CONFIG="$CONFIG"
export AGG_RUN="$RUN"

echo "=== 1/2: checking every scenario partial is complete ==="
Rscript --vanilla -e '
  suppressMessages({
    source("R/power/config.R");  source("R/power/blindness_checks.R")
    source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
    source("R/power/summarize_operating_characteristics.R")
    source("R/power/run_scenario_grid.R")
  })
  cfg  <- read_power_config(Sys.getenv("AGG_CONFIG"))
  grid <- expand_scenario_grid(cfg)
  pdir <- .power_out_dir(Sys.getenv("AGG_RUN"), "partials")

  incomplete <- character(0)
  for (i in seq_len(nrow(grid))) {
    sc  <- as.list(grid[i, ])
    est <- unlist(sc$estimators)
    eg  <- unlist(sc$effect_grid)
    er  <- .estimator_rep_counts(est, sc$n_reps, sc$estimator_reps[[1]])
    n_expected <- sum(er) * length(eg)
    f  <- file.path(pdir, paste0(sc$scenario_id, ".csv"))
    ok <- FALSE
    if (file.exists(f)) {
      d <- try(readr::read_csv(f, show_col_types = FALSE, progress = FALSE),
               silent = TRUE)
      ok <- !inherits(d, "try-error") && nrow(d) > 0L &&
        dplyr::n_distinct(paste(d$estimator, d$rep, d$delta)) >= n_expected
    }
    if (!ok) incomplete <- c(incomplete, sprintf("  [%d] %s", i, sc$scenario_id))
  }

  if (length(incomplete)) {
    cat("INCOMPLETE partials (", length(incomplete), " of ", nrow(grid), "):\n",
        paste(incomplete, collapse = "\n"), "\n\n", sep = "")
    cat("Aggregating here would recompute these on the login node.\n",
        "Submit the SLURM version instead:\n\n",
        "  sbatch run_aggregate.slurm ", Sys.getenv("AGG_RUN"), "\n\n",
        "(or re-submit the array to fill the gaps first).\n", sep = "")
    quit(status = 1L)
  }
  cat("All", nrow(grid), "partials complete.\n")
'

echo ""
echo "=== 2/2: summarizing ==="
Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  # No `scenarios` argument = full grid = writes the run-level summaries.
  # Every partial is complete (checked above), so this only stacks and
  # summarizes — 2 workers is plenty and keeps the login node quiet.
  run_scenario_grid(Sys.getenv("AGG_CONFIG"),
                    resume   = TRUE,
                    workers  = 2L,
                    run_name = Sys.getenv("AGG_RUN"))
'
