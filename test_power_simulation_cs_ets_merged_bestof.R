#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_bestof.R
#
# Crash triage tests. Runs in subprocess because segfaults can't be caught.
#
# Steps:
#   1) DRY_RUN of main script (proves data + baseline + placebo schedule works)
#   2) did_preflight_probe.R (proves did works on synthetic data using est_method=ipw)
#   3) TEST_MODE run of main script with N_SIMS=5, DID_EST_METHOD=ipw, DID_BSTRAP=FALSE
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
})

.fail <- function(msg) { cat(glue("\n[FAIL] {msg}\n")); quit(status = 1) }
.ok   <- function(msg) { cat(glue("[ OK ] {msg}\n")) }
.assert <- function(cond, msg) if (!isTRUE(cond)) .fail(msg) else .ok(msg)

main_script <- "power_simulation_cs_ets_merged_bestof.R"
probe_script <- "did_preflight_probe.R"
data_file   <- "merged_ets_combined.csv"

.assert(file.exists(main_script), glue("Found main script: {main_script}"))
.assert(file.exists(probe_script), glue("Found probe script: {probe_script}"))
.assert(file.exists(data_file),   glue("Found data file: {data_file}"))

rscript_bin <- Sys.which("Rscript")
.assert(nzchar(rscript_bin), "Rscript is available on PATH")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_root <- file.path(tempdir(), paste0("power_smoketest_", stamp))
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
.assert(dir.exists(out_root), glue("Created temp output dir: {out_root}"))

run_subprocess <- function(args, env = character(), label = "subprocess") {
  status <- system2(rscript_bin, args = args, env = env)
  .assert(identical(status, 0L), glue("{label} exited with status 0"))
}

# 1) DRY RUN
dry_dir <- file.path(out_root, "dry_run")
dir.create(dry_dir, recursive = TRUE, showWarnings = FALSE)

env_dry <- c(
  glue("DATA_FILE={normalizePath(data_file)}"),
  glue("OUT_DIR={normalizePath(dry_dir)}"),
  "DRY_RUN=TRUE",
  "TEST_MODE=TRUE",
  "N_SIMS=1",
  "EFFECT_PCTS=0,0.05",
  "CONTROL_GROUP=notyettreated",
  "DID_EST_METHOD=ipw",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "SKIP_PLOT=TRUE"
)

cat("\n=== 1) DRY_RUN main script ===\n")
run_subprocess(args = c(main_script), env = env_dry, label = "DRY_RUN")
dbg <- file.path(dry_dir, "debug_one_draw.csv")
.assert(file.exists(dbg), "DRY_RUN wrote debug_one_draw.csv")

# 2) did probe (synthetic data)
cat("\n=== 2) did_preflight_probe.R ===\n")
run_subprocess(args = c(probe_script), env = character(), label = "did probe")

# 3) TEST MODE run (sequential, no bootstrap)
test_dir <- file.path(out_root, "test_mode")
dir.create(test_dir, recursive = TRUE, showWarnings = FALSE)

env_test <- c(
  glue("DATA_FILE={normalizePath(data_file)}"),
  glue("OUT_DIR={normalizePath(test_dir)}"),
  "TEST_MODE=TRUE",
  "N_SIMS=5",
  "PRE_LEN=12",
  "POST_LEN=12",
  "EFFECT_PCTS=0,0.05",
  "CONTROL_GROUP=notyettreated",
  "DID_EST_METHOD=ipw",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "SKIP_PLOT=TRUE"
)

cat("\n=== 3) TEST_MODE main script ===\n")
run_subprocess(args = c(main_script), env = env_test, label = "TEST_MODE")

out_csv <- file.path(test_dir, "power_by_effect.csv")
.assert(file.exists(out_csv), "Wrote power_by_effect.csv in TEST_MODE")

df <- readr::read_csv(out_csv, show_col_types = FALSE)
required_cols <- c("effect_pct","effect_log","power","alpha","fail_rate","n_sims","control_group_requested","control_group_used")
missing <- setdiff(required_cols, names(df))
.assert(length(missing) == 0, glue("power_by_effect has required columns (missing: {paste(missing, collapse=', ')})"))
.assert(all(is.finite(df$power) & df$power >= 0 & df$power <= 1), "power finite in [0,1]")
.assert(all(is.finite(df$fail_rate) & df$fail_rate >= 0 & df$fail_rate <= 1), "fail_rate finite in [0,1]")

cat("\nAll triage tests passed.\n")
cat(glue("Outputs are in: {out_root}\n\n"))
