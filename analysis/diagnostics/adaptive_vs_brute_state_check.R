#!/usr/bin/env Rscript
################################################################################
# adaptive_vs_brute_state_check.R — gate 6 of the adaptive-MDE validation
#
# Runs run_adaptive_mde() and run_scenario_grid() (brute force) on the SAME
# config (config/power_state_cs_adaptive_check.yml: state / S2 / D1 / count_nb
# / step / cs, n_reps = 40) and verifies:
#   1. every (rep, delta) cell the adaptive run visited is BIT-IDENTICAL in
#      the brute-force partial (att, se, p, ci_lo, ci_hi, truth);
#   2. per arm, the MDE verdicts agree (both cross with |mde diff| <= 0.005,
#      or both return the same non-crossing reason).
#
# The adaptive run's size gate is disabled (gate_interval = c(0, 1)): state
# CS arms are known miscalibrated, and this check validates the SEARCH, not
# the size. Production county runs keep the [2.5%, 10%] gate.
#
# Run from the repository root:
#   N_WORKERS=6 Rscript analysis/diagnostics/adaptive_vs_brute_state_check.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

stopifnot(file.exists("power_simulation_cs.R"))

source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/make_pseudo_schedules.R")
source("R/power/impose_effects.R")
source("R/power/run_estimators.R")
source("R/power/summarize_operating_characteristics.R")
source("R/power/run_scenario_grid.R")
source("R/power/adaptive_mde.R")

workers <- {
  v <- Sys.getenv("N_WORKERS")
  if (nzchar(v)) as.integer(v) else max(1L, parallel::detectCores() - 2L)
}
cfgp <- "config/power_state_cs_adaptive_check.yml"
rn_a <- "_amde_state_check_adaptive"
rn_b <- "_amde_state_check_brute"

cat(sprintf("[%s] gate 6: adaptive run (workers=%d)\n",
            format(Sys.time(), "%H:%M:%S"), workers))
ra <- run_adaptive_mde(cfgp, run_name = rn_a, workers = workers,
                       gate_interval = c(0, 1), resume = TRUE)

cat(sprintf("[%s] gate 6: brute-force run\n", format(Sys.time(), "%H:%M:%S")))
rb <- run_scenario_grid(cfgp, resume = TRUE, workers = workers,
                        run_name = rn_b)

sid <- ra$grid$scenario_id[1]
rows_a <- read_csv(file.path(.power_out_dir(rn_a), "partials",
                             paste0(sid, ".csv")),
                   col_types = .PARTIAL_COL_TYPES, show_col_types = FALSE)
rows_b <- read_csv(file.path(.power_out_dir(rn_b), "partials",
                             paste0(sid, ".csv")),
                   col_types = .PARTIAL_COL_TYPES, show_col_types = FALSE)

key <- c("rep", "delta", "estimator", "inference", "estimand", "event_time")
val <- c("att", "se", "p", "ci_lo", "ci_hi", "truth")
a <- rows_a %>% select(all_of(c(key, val))) %>% arrange(across(all_of(key)))
b <- rows_b %>%
  semi_join(distinct(rows_a, .data$rep, .data$delta), by = c("rep", "delta")) %>%
  select(all_of(c(key, val))) %>% arrange(across(all_of(key)))

cat(sprintf("cells visited by adaptive: %d (rep x delta); rows: %d vs %d\n",
            nrow(distinct(rows_a, rep, delta)), nrow(a), nrow(b)))
stopifnot("row sets differ between adaptive and brute partials" =
            nrow(a) == nrow(b))
same <- vapply(val, function(v) {
  isTRUE(all.equal(a[[v]], b[[v]], tolerance = 0)) ||
    identical(is.na(a[[v]]), is.na(b[[v]])) &&
      all(a[[v]] == b[[v]], na.rm = TRUE)
}, logical(1))
cat("bit-identity by column:\n")
print(same)
stopifnot("adaptive cells are NOT bit-identical to brute force" = all(same))

cat("\n---- adaptive MDE table ----\n")
print(as.data.frame(ra$mde))
cat("\n---- brute-force MDE table (cs rows) ----\n")
mb <- rb$mde %>% filter(.data$estimator == "cs")
print(as.data.frame(mb))

cmp <- ra$mde %>%
  transmute(arm, verdict_adaptive = verdict, mde_adaptive = mde) %>%
  left_join(mb %>% transmute(arm = inference, mde_brute = mde,
                             verdict_brute = mde_reason),
            by = "arm") %>%
  mutate(agree = (verdict_adaptive == verdict_brute &
                    (is.na(mde_adaptive) & is.na(mde_brute) |
                       abs(mde_adaptive - mde_brute) <= 0.005)) |
           (verdict_adaptive == "size_gate_failed"))
cat("\n---- agreement ----\n")
print(as.data.frame(cmp))

out <- file.path(.power_out_dir(rn_a), "gate6_agreement.csv")
write_csv(cmp, out)
cat(sprintf("\n[%s] gate 6 %s -> %s\n", format(Sys.time(), "%H:%M:%S"),
            if (all(cmp$agree, na.rm = TRUE)) "PASS" else "FAIL", out))
if (!all(cmp$agree, na.rm = TRUE)) quit(status = 1L, save = "no")
