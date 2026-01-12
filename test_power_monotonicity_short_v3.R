#!/usr/bin/env Rscript
################################################################################
# test_power_monotonicity_short_v3.R
#
# Short, "peace-of-mind" properties test for the CS power sim.
#
# What it checks (with small-ish compute):
#   1) The script runs end-to-end and writes the expected CSVs.
#   2) Type I error at effect=0 is non-degenerate (not ~0 and not ~1).
#   3) Power increases at large effects (not all zeros).
#   4) MDE is weakly decreasing in n_states (when defined).
#
# Usage (example):
#   TEST_N_WORKERS=20 TEST_N_SIMS=60 Rscript --vanilla test_power_monotonicity_short_v3.R
#
# Notes:
#   - Works from a Della RStudio allocation too (hostname "della-h*").
#   - Writes outputs to a temp folder (prints the path).
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
  library(dplyr)
})

here <- normalizePath(getwd())
main <- file.path(here, "power_simulation_cs_ets_merged_v5final_parallel.R")
data <- file.path(here, "merged_ets_combined.csv")

if (!file.exists(main)) stop(glue("Missing main script: {main}"), call. = FALSE)
if (!file.exists(data)) stop(glue("Missing data file: {data}"), call. = FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript not found on PATH.", call. = FALSE)

host <- Sys.info()[["nodename"]]

# --- user knobs ---
TEST_N_SIMS    <- as.integer(Sys.getenv("TEST_N_SIMS", "60"))
TEST_N_WORKERS <- as.integer(Sys.getenv("TEST_N_WORKERS", "2"))

# allow >2 workers if we're on a compute node (della-h*) OR if SLURM vars exist
slurm_job <- Sys.getenv("SLURM_JOB_ID")
on_compute <- grepl("^della-h", host)
if (is.na(TEST_N_WORKERS) || TEST_N_WORKERS < 1L) TEST_N_WORKERS <- 1L
if (TEST_N_WORKERS > 2L && !on_compute && !nzchar(slurm_job)) {
  stop(glue(
    "Refusing to run with TEST_N_WORKERS={TEST_N_WORKERS} without a compute allocation.\n",
    "Host: {host}\n",
    "Run from a Della compute node (hostname della-h*) or with SLURM_JOB_ID set, or set TEST_N_WORKERS<=2."
  ), call. = FALSE)
}

run_sub <- function(env, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  logf <- file.path(out_dir, "monotonicity_short.log")

  cat(glue("Running: {rscript} --vanilla {main}\n"))
  cat(glue("OUT_DIR: {out_dir}\n"))
  cat(glue("Host: {host}\n"))
  cat(glue("Workers requested: {TEST_N_WORKERS}\n"))
  cat(glue("Sims per cell: {TEST_N_SIMS}\n\n"))

  status <- system2(
    rscript,
    args = c("--vanilla", main),
    env  = env,
    stdout = logf,
    stderr = logf
  )
  cat(glue("Exit: {status}\n"))
  cat(glue("Log : {logf}\n"))

  if (!identical(status, 0L)) {
    cat("\n---- LOG (tail) ----\n")
    lines <- readLines(logf, warn = FALSE)
    cat(paste(utils::tail(lines, 200), collapse = "\n"), "\n")
    fatal <- file.path(out_dir, "power_FATAL_ERROR.txt")
    if (file.exists(fatal)) {
      cat("\n---- power_FATAL_ERROR.txt ----\n")
      cat(paste(readLines(fatal, warn = FALSE), collapse = "\n"), "\n")
    }
    stop(glue("Subprocess failed (exit {status})."), call. = FALSE)
  }

  invisible(TRUE)
}

tmp_root <- file.path(tempdir(), paste0("cs_monotonicity_short_", format(Sys.time(), "%Y%m%d_%H%M%S")))
out <- file.path(tmp_root, "out")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# moderate grid, but with large effects so we can detect power > 0
grid_n <- "8,10,12"
effects <- "0,0.20,0.40"  # large enough to avoid all-zero power if things are working

env <- c(
  glue("DATA_FILE={data}"),
  glue("OUT_DIR={out}"),
  "DRY_RUN=FALSE",
  "TEST_MODE=TRUE",
  glue("N_SIMS={TEST_N_SIMS}"),
  glue("N_WORKERS={TEST_N_WORKERS}"),
  glue("GRID_N_STATES={grid_n}"),
  glue("EFFECT_PCTS={effects}"),
  "MAKE_HEATMAP=FALSE",
  "SAVE_DRAWS=TRUE",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "DID_EST_METHOD=ipw"
)

run_sub(env, out)

cat(glue("\nOutputs directory: {out}\n"))
cat("Files:\n")
print(sort(list.files(out)))

# --- required outputs ---
req <- c("power_by_effect.csv")
miss <- req[!file.exists(file.path(out, req))]
if (length(miss) > 0) stop(glue("Missing expected output(s): {paste(miss, collapse = ', ')}"), call. = FALSE)

pwr <- readr::read_csv(file.path(out, "power_by_effect.csv"), show_col_types = FALSE)

need_cols <- c("n_states","effect_pct","power","fail_rate","n_sims")
miss_cols <- setdiff(need_cols, names(pwr))
if (length(miss_cols) > 0) stop(glue("power_by_effect.csv missing columns: {paste(miss_cols, collapse=', ')}"), call. = FALSE)

# --- Check 1: Type I error isn't degenerate ---
alpha_guess <- unique(pwr$alpha)
alpha_guess <- alpha_guess[is.finite(alpha_guess)]
alpha <- if (length(alpha_guess) >= 1) alpha_guess[1] else 0.05

p0 <- pwr %>%
  filter(effect_pct == 0) %>%
  group_by(n_states) %>%
  summarise(power0 = mean(power, na.rm = TRUE), .groups = "drop")

print(p0)

if (any(p0$power0 < 0.005, na.rm = TRUE)) {
  stop("Type I error looks too low (power at effect=0 < 0.005). Common cause: all cohorts treated=0 (g not matching time_id) or failures mapped to p=1.", call. = FALSE)
}
if (any(p0$power0 > 0.25, na.rm = TRUE)) {
  stop("Type I error looks too high (power at effect=0 > 0.25). Common cause: p-values stuck at 0 or miscomputed.", call. = FALSE)
}
cat(glue("PASS: Type I error is non-degenerate (alpha≈{alpha}).\n"))

# --- Check 2: Power increases at large effects (not all zeros) ---
pmax <- pwr %>%
  group_by(n_states) %>%
  summarise(
    p0   = power[which.min(effect_pct)],
    pmax = power[which.max(effect_pct)],
    .groups = "drop"
  )
print(pmax)

if (mean(pmax$pmax - pmax$p0, na.rm = TRUE) < 0.02) {
  stop("Power is not higher at large effects (avg(pmax-p0) < 0.02). If p0 is reasonable, this suggests effect injection isn't working.", call. = FALSE)
}
cat("PASS: Power is higher at large effects (basic sanity).\n")

# --- Check 3: MDE weakly decreasing in n_states (when defined) ---
target <- 0.20
mde <- pwr %>%
  group_by(n_states) %>%
  summarise(
    mde_pct = {
      ok <- effect_pct[which(power >= target)]
      if (length(ok) == 0) NA_real_ else min(ok)
    },
    .groups = "drop"
  ) %>%
  arrange(n_states)

print(mde)

mde2 <- mde %>% filter(is.finite(mde_pct))
if (nrow(mde2) >= 2) {
  d <- diff(mde2$mde_pct)
  if (any(d > 1e-8)) {
    stop("MDE is not weakly decreasing in n_states (for defined MDEs).", call. = FALSE)
  }
  cat(glue("PASS: MDE weakly decreases with n_states (target power={target}).\n"))
} else {
  cat("SKIP: Not enough defined MDEs to test monotonicity (increase effects or lower target).\n")
}

# --- Optional: draw-level diagnostics (if produced) ---
draws_path <- file.path(out, "draws_example.csv")
if (file.exists(draws_path)) {
  dr <- readr::read_csv(draws_path, show_col_types = FALSE)
  if ("p_value" %in% names(dr) && "effect_pct" %in% names(dr)) {
    max_eff <- max(dr$effect_pct, na.rm = TRUE)
    dr2 <- dr %>% filter(effect_pct == max_eff)
    frac1 <- mean(abs(dr2$p_value - 1) < 1e-12, na.rm = TRUE)
    frac_na <- mean(is.na(dr2$p_value))
    cat(glue("\n[DIAG] max effect={max_eff}: frac(p==1)={round(frac1,3)} frac(p NA)={round(frac_na,3)}\n"))
    if (is.finite(frac1) && frac1 > 0.98) {
      stop("At max effect, >98% of p-values are exactly 1. This usually means failures are being mapped to p=1.", call. = FALSE)
    }
  }
}

cat(glue("\nAll short monotonicity tests passed.\nOutputs kept at: {out}\n"))
