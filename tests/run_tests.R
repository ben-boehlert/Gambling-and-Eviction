#!/usr/bin/env Rscript
################################################################################
# tests/run_tests.R
#
# Runs the power-framework testthat suite WITHOUT the repo being an R package.
# Sources all R/power/*.R (plus the reused utils helper), then test_dir().
# Assumes the working directory is the repository root.
################################################################################

suppressPackageStartupMessages(library(testthat))

# Fail early if not at repo root.
if (!file.exists("power_simulation_cs.R")) {
  stop("Run tests from the repository root (power_simulation_cs.R not found).")
}

# Source framework modules in dependency order.
source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/make_pseudo_schedules.R")

res <- test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)

# Non-zero exit on any failure.
df <- as.data.frame(res)
n_fail  <- sum(df$failed)
n_error <- sum(df$error)
if (n_fail > 0L || n_error > 0L) {
  quit(status = 1L, save = "no")
}
