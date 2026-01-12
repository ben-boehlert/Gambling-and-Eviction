#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_v46like.R
#
# Minimal smoke tests that DON'T require testthat.
# Runs the main script twice in a subprocess:
#   1) DRY_RUN (no did call) -> must create debug_one_draw.csv
#   2) TEST_MODE (tiny sims) -> must create power_by_effect.csv with finite power
#
# Put this file in the SAME folder as:
#   - power_simulation_cs_ets_merged_v46like.R
#   - merged_ets_combined.csv
#
# Run:
#   Rscript test_power_simulation_cs_ets_merged_v46like.R
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
})

here <- normalizePath(getwd())
main <- file.path(here, "power_simulation_cs_ets_merged_v46like.R")
data <- file.path(here, "merged_ets_combined.csv")

if (!file.exists(main)) stop(glue("Missing main script: {main}"), call. = FALSE)
if (!file.exists(data)) stop(glue("Missing data file: {data}"), call. = FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript not found on PATH.", call. = FALSE)

run_sub <- function(label, env, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  logf <- file.path(out_dir, paste0(label, ".log"))

  cat(glue("Running: {rscript} --vanilla {main}\n"))
  cat(glue("Log: {logf}\n"))
  cat("Env overrides:\n")
  cat(paste0("  ", env, collapse="\n"), "\n")

  status <- system2(
    rscript,
    args = c("--vanilla", main),
    env = env,
    stdout = logf,
    stderr = logf
  )

  cat(glue("\n=== {label} (exit {status}) ===\n"))
  if (file.exists(logf)) {
    lines <- readLines(logf, warn = FALSE)
    if (length(lines) > 0) {
      cat("---- BEGIN LOG ----\n")
      cat(paste(lines, collapse = "\n"), "\n")
      cat("---- END LOG ----\n")
    } else {
      cat("(log is empty)\n")
    }
  } else {
    cat("(log file not created)\n")
  }

  if (!identical(status, 0L)) stop(glue("{label} failed (exit {status})"), call. = FALSE)
}

tmp <- file.path(tempdir(), paste0("cs_power_smoke_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

# 1) dry run
out1 <- file.path(tmp, "dry_run")
env1 <- c(
  glue("DATA_FILE={data}"),
  glue("OUT_DIR={out1}"),
  "DRY_RUN=TRUE",
  "TEST_MODE=TRUE",
  "N_SIMS=1",
  "EFFECT_PCTS=0,0.05",
  "OPTION=A1",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0"
)
run_sub("dry_run", env1, out1)

dbg <- file.path(out1, "debug_one_draw.csv")
if (!file.exists(dbg)) stop("DRY_RUN did not write debug_one_draw.csv", call. = FALSE)

# 2) tiny estimation run
out2 <- file.path(tmp, "test_mode")
env2 <- c(
  glue("DATA_FILE={data}"),
  glue("OUT_DIR={out2}"),
  "DRY_RUN=FALSE",
  "TEST_MODE=TRUE",
  "N_SIMS=5",
  "EFFECT_PCTS=0,0.05",
  "OPTION=A1",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "DID_EST_METHOD=ipw"
)
run_sub("test_mode", env2, out2)

out_csv <- file.path(out2, "power_by_effect.csv")
if (!file.exists(out_csv)) stop("TEST_MODE did not write power_by_effect.csv", call. = FALSE)

df <- readr::read_csv(out_csv, show_col_types = FALSE)

need <- c("effect_pct","effect_log","power","alpha","fail_rate","n_sims")
miss <- setdiff(need, names(df))
if (length(miss) > 0) stop(glue("Missing columns in power_by_effect.csv: {paste(miss, collapse=', ')}"), call. = FALSE)

if (any(!is.finite(df$power))) stop("Non-finite power values found.", call. = FALSE)
if (any(df$power < 0 | df$power > 1)) stop("Power outside [0,1].", call. = FALSE)

cat(glue("\nAll smoke tests passed. Outputs are in: {tmp}\n"))
