#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_v5style.R
#
# Smoke tests (fast), subprocess-based.
# On failure prints:
#   - captured stdout+stderr from subprocess
#   - OUT_DIR listing
#   - power_FATAL_ERROR.txt (if present)
#   - run.log tail (if present)
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
})

here <- normalizePath(getwd())
main <- file.path(here, "power_simulation_cs_ets_merged_v5style.R")
data <- file.path(here, "merged_ets_combined.csv")

if (!file.exists(main)) stop(glue("Missing main script: {main}"), call. = FALSE)
if (!file.exists(data)) stop(glue("Missing data file: {data}"), call. = FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript not found on PATH.", call. = FALSE)

cat("=== Preflight ===\n")
cat(glue("WD: {here}\nMAIN: {main}\nDATA: {data}\n"))
cat("Main script md5:\n")
print(tools::md5sum(main))
cat("=== End preflight ===\n\n")

cat_file <- function(path, title, n = 200) {
  if (file.exists(path)) {
    cat(glue("\n---- {title} ----\n"))
    lines <- readLines(path, warn = FALSE)
    cat(paste(utils::tail(lines, n), collapse = "\n"), "\n")
  }
}

print_dir <- function(dir) {
  cat("\nOUT_DIR contents:\n")
  if (dir.exists(dir)) print(list.files(dir, all.files = TRUE)) else cat("(OUT_DIR does not exist)\n")
}

run_sub <- function(label, env, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  cat(glue("\nRunning: {rscript} --vanilla {main}\n"))
  cat(glue("OUT_DIR: {out_dir}\n"))
  cat("Env overrides:\n")
  cat(paste0("  ", env, collapse = "\n"), "\n")

  out <- system2(
    rscript,
    args = c("--vanilla", main),
    env = env,
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L

  cap <- file.path(out_dir, paste0(label, ".captured.log"))
  writeLines(out, cap)

  cat(glue("\n=== {label} (exit {status}) ===\n"))
  if (length(out) > 0) {
    cat("---- BEGIN SUBPROCESS OUTPUT ----\n")
    cat(paste(out, collapse = "\n"), "\n")
    cat("---- END SUBPROCESS OUTPUT ----\n")
  } else {
    cat("(no subprocess output captured)\n")
  }

  if (!identical(as.integer(status), 0L)) {
    print_dir(out_dir)
    cat_file(file.path(out_dir, "power_FATAL_ERROR.txt"), "power_FATAL_ERROR.txt", n = 200)
    cat_file(file.path(out_dir, "run.log"), "run.log (tail)", n = 200)
    stop(glue("{label} failed (exit {status})"), call. = FALSE)
  }

  invisible(TRUE)
}

tmp <- file.path(tempdir(), paste0("cs_power_smoke_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

# 1) DRY_RUN (no did)
out1 <- file.path(tmp, "dry_run")
env1 <- c(
  glue("DATA_FILE={data}"),
  glue("OUT_DIR={out1}"),
  "DRY_RUN=TRUE",
  "TEST_MODE=TRUE",
  "N_SIMS=1",
  "EFFECT_PCTS=0,0.05",
  "MAKE_HEATMAP=FALSE",
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
  "N_SIMS=20",
  "EFFECT_PCTS=0,0.05",
  "MAKE_HEATMAP=FALSE",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "DID_EST_METHOD=ipw"
)
run_sub("test_mode", env2, out2)

out_csv <- file.path(out2, "power_by_effect.csv")
if (!file.exists(out_csv)) stop("TEST_MODE did not write power_by_effect.csv", call. = FALSE)

df <- readr::read_csv(out_csv, show_col_types = FALSE)
need <- c("n_states","effect_pct","effect_log","power","alpha","fail_rate","n_sims")
miss <- setdiff(need, names(df))
if (length(miss) > 0) stop(glue("Missing columns in power_by_effect.csv: {paste(miss, collapse=', ')}"), call. = FALSE)
if (any(!is.finite(df$power))) stop("Non-finite power values found.", call. = FALSE)
if (any(df$power < 0 | df$power > 1)) stop("Power outside [0,1].", call. = FALSE)

cat(glue("\nAll smoke tests passed. Outputs are in: {tmp}\n"))
