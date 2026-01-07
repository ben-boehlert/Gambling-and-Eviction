#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_bestof_SAFE.R
#
# Safe smoke-tests that WILL NOT kill your RStudio session.
# - Never calls quit() when interactive()
# - Runs the main script in a subprocess (Rscript --vanilla), so a segfault in did
#   does NOT take down your interactive R session.
#
# What it does:
#   1) DRY_RUN=TRUE on main script (no did call) -> should always succeed
#   2) Optional probe script (did_realdata_probe.R if present) in subprocess
#   3) TEST_MODE run of main script with tiny sims in subprocess
#
# Requirements (files in the SAME folder as this test script):
#   - power_simulation_cs_ets_merged_bestof.R
#   - merged_ets_combined.csv
# Optional:
#   - did_realdata_probe.R   (preferred; uses your real data)
#
# Run (recommended):
#   Rscript test_power_simulation_cs_ets_merged_bestof_SAFE.R
#
# Run from RStudio:
#   source("test_power_simulation_cs_ets_merged_bestof_SAFE.R")
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
})

# ----------------------------- helpers ----------------------------------------

is_interactive <- interactive()

.fail <- function(msg) {
  cat(glue("\n[FAIL] {msg}\n"))
  if (is_interactive) stop(msg, call. = FALSE) else quit(status = 1)
}
.ok <- function(msg) cat(glue("[ OK ] {msg}\n"))
.assert <- function(cond, msg) if (!isTRUE(cond)) .fail(msg) else .ok(msg)

this_file_dir <- function() {
  # Works for Rscript and for source() in RStudio
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd, value = TRUE)
  if (length(file_arg) == 1) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg))))
  }
  # When sourced, sys.frames can contain the path
  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(dirname(normalizePath(sys.frames()[[1]]$ofile)))
  }
  # Fallback: current working dir
  normalizePath(getwd())
}

root <- this_file_dir()
setwd(root)
.ok(glue("Working directory set to: {root}"))

main_script <- "power_simulation_cs_ets_merged_bestof.R"
data_file   <- "merged_ets_combined.csv"
probe_script <- if (file.exists("did_realdata_probe.R")) "did_realdata_probe.R" else NA_character_

.assert(file.exists(main_script), glue("Found main script: {main_script}"))
.assert(file.exists(data_file),   glue("Found data file: {data_file}"))

rscript_bin <- Sys.which("Rscript")
.assert(nzchar(rscript_bin), "Rscript is available on PATH")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_root <- file.path(tempdir(), paste0("power_smoketest_", stamp))
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
.assert(dir.exists(out_root), glue("Created temp output dir: {out_root}"))

run_subprocess <- function(label, script, env, out_dir) {
  log_file <- file.path(out_dir, paste0(label, ".log"))
  status <- system2(
    rscript_bin,
    args = c("--vanilla", script),
    env = env,
    stdout = log_file,
    stderr = log_file
  )
  if (!identical(status, 0L)) {
    cat(glue("\n--- {label} LOG ({log_file}) ---\n"))
    if (file.exists(log_file)) cat(paste(readLines(log_file, warn = FALSE), collapse = "\n"), "\n")
    .fail(glue("{label} failed (exit status {status}). See log above."))
  }
  .ok(glue("{label} exited with status 0 (log: {log_file})"))
  invisible(log_file)
}

# ----------------------------- 1) DRY RUN -------------------------------------

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
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "SKIP_PLOT=TRUE"
)

cat("\n=== 1) DRY_RUN main script (no did call) ===\n")
run_subprocess("dry_run", main_script, env_dry, dry_dir)

dbg <- file.path(dry_dir, "debug_one_draw.csv")
.assert(file.exists(dbg), "DRY_RUN wrote debug_one_draw.csv")

# ----------------------------- 2) Optional probe ------------------------------

if (is.na(probe_script)) {
  cat("\nSkipping probe: did_realdata_probe.R not found in this folder.\n")
  cat("If you want this check, put did_realdata_probe.R next to this test script.\n")
} else {
  probe_dir <- file.path(out_root, "probe")
  dir.create(probe_dir, recursive = TRUE, showWarnings = FALSE)

  env_probe <- c(
    glue("DATA_FILE={normalizePath(data_file)}"),
    glue("OUT_DIR={normalizePath(probe_dir)}"),
    "OUTCOME=log1p_filings_count",
    "PRE_LEN=12",
    "POST_LEN=12",
    "CONTROL_GROUP=notyettreated",
    "DID_EST_METHOD=ipw"
  )

  cat("\n=== 2) did_realdata_probe (single att_gt on YOUR data) ===\n")
  run_subprocess("probe", probe_script, env_probe, probe_dir)
}

# ----------------------------- 3) TEST MODE run -------------------------------

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
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "SKIP_PLOT=TRUE"
)

cat("\n=== 3) TEST_MODE main script (tiny sims) ===\n")
run_subprocess("test_mode", main_script, env_test, test_dir)

out_csv <- file.path(test_dir, "power_by_effect.csv")
.assert(file.exists(out_csv), "Wrote power_by_effect.csv in TEST_MODE")

df <- readr::read_csv(out_csv, show_col_types = FALSE)
required_cols <- c("effect_pct","effect_log","power","alpha","fail_rate","n_sims","control_group_requested","control_group_used")
missing <- setdiff(required_cols, names(df))
.assert(length(missing) == 0, glue("power_by_effect has required columns (missing: {paste(missing, collapse=', ')})"))
.assert(all(is.finite(df$power) & df$power >= 0 & df$power <= 1), "power finite in [0,1]")
.assert(all(is.finite(df$fail_rate) & df$fail_rate >= 0 & df$fail_rate <= 1), "fail_rate finite in [0,1]")

cat("\nAll SAFE smoke tests passed.\n")
cat(glue("Outputs/logs are in: {out_root}\n\n"))
