#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_bestof.R
#
# Crash-focused preflight tests for power_simulation_cs_ets_merged_bestof.R
#
# Why this exists:
# - If R is segfaulting, tryCatch won't help. The only safe test is a subprocess.
# - This runs the main script in TEST_MODE with very small settings, so it should
#   either succeed quickly or crash immediately.
#
# What it checks:
#   1) Main script runs end-to-end (exit status 0)
#   2) Output files exist
#   3) power_by_effect.csv has required columns and bounded power/fail_rate
#
# Run:
#   Rscript test_power_simulation_cs_ets_merged_bestof.R
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
})

.fail <- function(msg) { cat(glue("\n[FAIL] {msg}\n")); quit(status = 1) }
.ok   <- function(msg) { cat(glue("[ OK ] {msg}\n")) }
.assert <- function(cond, msg) if (!isTRUE(cond)) .fail(msg) else .ok(msg)

main_script <- "power_simulation_cs_ets_merged_bestof.R"
data_file   <- "merged_ets_combined.csv"

.assert(file.exists(main_script), glue("Found main script: {main_script}"))
.assert(file.exists(data_file),   glue("Found data file: {data_file}"))

rscript_bin <- Sys.which("Rscript")
.assert(nzchar(rscript_bin), "Rscript is available on PATH")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_root <- file.path(tempdir(), paste0("power_smoketest_", stamp))
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
.assert(dir.exists(out_root), glue("Created temp output dir: {out_root}"))

case_dir <- file.path(out_root, "case_test_mode")
dir.create(case_dir, recursive = TRUE, showWarnings = FALSE)

env <- c(
  glue("DATA_FILE={normalizePath(data_file)}"),
  glue("OUT_DIR={normalizePath(case_dir)}"),
  "TEST_MODE=TRUE",
  "SEED=123",
  "N_SIMS=5",
  "PRE_LEN=12",
  "POST_LEN=12",
  "EFFECT_PCTS=0,0.05",
  "CONTROL_GROUP=notyettreated",
  # keep bootstrap off in tests (common segfault culprit on some stacks)
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0"
)

cat("\n=== Running TEST_MODE preflight ===\n")
status <- system2(rscript_bin, args = c(main_script), env = env)
.assert(identical(status, 0L), "Main script exited with status 0 in TEST_MODE")

out_csv <- file.path(case_dir, "power_by_effect.csv")
out_mde <- file.path(case_dir, "mde_summary.csv")
out_png <- file.path(case_dir, "power_curve.png")
out_txt <- file.path(case_dir, "README_results.txt")

.assert(file.exists(out_csv), "Wrote power_by_effect.csv")
.assert(file.exists(out_mde), "Wrote mde_summary.csv")
.assert(file.exists(out_png), "Wrote power_curve.png")
.assert(file.exists(out_txt), "Wrote README_results.txt")

df <- readr::read_csv(out_csv, show_col_types = FALSE)

required_cols <- c(
  "effect_pct", "effect_log", "power", "alpha",
  "fail_rate", "mean_att", "median_se", "n_sims",
  "control_group_requested", "control_group_used"
)
missing <- setdiff(required_cols, names(df))
.assert(length(missing) == 0, glue("power_by_effect.csv has required columns (missing: {paste(missing, collapse=', ')})"))

.assert(all(is.finite(df$alpha) & df$alpha == 0.05), "alpha column present and equals 0.05")
.assert(all(is.finite(df$power) & df$power >= 0 & df$power <= 1), "power is finite and in [0,1]")
.assert(all(is.finite(df$fail_rate) & df$fail_rate >= 0 & df$fail_rate <= 1), "fail_rate is finite and in [0,1]")

cat("\nPreflight passed.\n")
cat(glue("Outputs are in: {out_root}\n\n"))
