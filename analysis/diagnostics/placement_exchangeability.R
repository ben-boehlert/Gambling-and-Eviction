################################################################################
# analysis/diagnostics/placement_exchangeability.R
#
# Prototype + paired test of EXCHANGEABLE pseudo-treatment placement.
#
# Motivation: quality_reports/nullbias_decomposition_2026-08-25.md showed the
# delta = 0 null bias in the state D1 design comes from .assign_cohorts()'s
# deterministic scarcest-cohort-first fill, which routes coverage-constrained
# states to particular cohort dates. The real adoption process shows no such
# skew (corr(adoption month, own pre-trend) = -0.08 ETS / +0.22 annual, both
# n.s.), so the simulation's reference distribution is mis-specified.
#
# This script (a) REGRESSION-CHECKS that placement = "scarcest" reproduces the
# pre-2026-08-26 implementation bit-for-bit, then (b) compares the three
# placement rules on the exchangeability statistic that diagnosed the problem:
# corr(pseudo-adoption date, that state's own outcome trend slope).
#
# Estimation-free and fast: schedule draws only. Writes ONLY to
# output/placement_exchangeability/.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(lubridate)
})

for (mod in c("config.R", "blindness_checks.R", "load_blinded_panel.R",
              "make_pseudo_schedules.R", "run_scenario_grid.R")) {
  source(file.path("R", "power", mod))
}

OUT <- "output/placement_exchangeability"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

N_DRAWS   <- as.integer(Sys.getenv("N_DRAWS", "400"))
BASE_SEED <- 20260723L        # same base as every gate run
CFG_PATH  <- "config/power_lpdid_shift12_gate_vwatt.yml"

cfg <- read_power_config(CFG_PATH)
grid <- expand_scenario_grid(cfg)
grid <- grid[grid$name == "mde_spliced", , drop = FALSE]
stopifnot(nrow(grid) == 1L)
sc <- as.list(grid[1, ])

panel <- load_blinded_panel(
  level = "state", treat_def = "shift12_start_date", anticipation = 6L,
  sample = "S2", covid = "drop", quarterly = FALSE, time_agg = "month",
  complete_periods_only = FALSE, config = cfg
)
panel <- panel[panel$state_abb != "NV", , drop = FALSE]
real_schedule <- guarded_read_csv(cfg$schedule)

.mi <- function(d) year(d) * 12L + (month(d) - 1L)

state_features <- panel %>%
  group_by(state_abb) %>%
  summarise(coverage_months = n(),
            trend_slope = coef(lm(y_log1p ~ t))[["t"]], .groups = "drop")
cat("States:", nrow(state_features), "| draws per rule:", N_DRAWS, "\n\n")

draw <- function(seed, placement) {
  tryCatch(
    make_pseudo_schedule(design = sc$design, panel = panel,
                         real_schedule = real_schedule, treat_def = sc$treat_def,
                         min_pre = sc$min_pre, min_post = sc$min_post,
                         seed = seed, template = sc$template,
                         placement = placement),
    error = function(e) NULL)
}

# ---------------------------------------------------------------------------
# (a) REGRESSION CHECK: default must reproduce the archived implementation.
# ---------------------------------------------------------------------------
old_env <- new.env()
sys.source("R/power/deprecated/make_pseudo_schedules_pre_placement_2026-08-26.R",
           envir = old_env)
cat("=== Regression check: placement='scarcest' vs pre-2026-08-26 code\n")
mismatch <- 0L
for (i in 1:25) {
  s <- BASE_SEED + 10007L * i
  a <- draw(s, "scarcest")
  b <- tryCatch(old_env$make_pseudo_schedule(
        design = sc$design, panel = panel, real_schedule = real_schedule,
        treat_def = sc$treat_def, min_pre = sc$min_pre, min_post = sc$min_post,
        seed = s, template = sc$template), error = function(e) NULL)
  ok <- identical(is.null(a), is.null(b)) &&
        (is.null(a) || isTRUE(all.equal(as.data.frame(a[order(a$state_abb), ]),
                                        as.data.frame(b[order(b$state_abb), ]),
                                        check.attributes = FALSE)))
  if (!ok) mismatch <- mismatch + 1L
}
cat(if (mismatch == 0L) "PASS — 25/25 identical\n\n" else
    sprintf("FAIL — %d/25 differ (STOP: default behaviour changed)\n\n", mismatch))
if (mismatch > 0L) quit(status = 1)

# ---------------------------------------------------------------------------
# (b) Exchangeability comparison across placement rules.
# ---------------------------------------------------------------------------
rows <- list()
for (pl in c("scarcest", "random_order", "uniform")) {
  t0 <- Sys.time(); nfail <- 0L
  for (i in seq_len(N_DRAWS)) {
    s <- BASE_SEED + 10007L * i + 101L
    sch <- draw(s, pl)
    if (is.null(sch)) { nfail <- nfail + 1L; next }
    sch <- sch %>% left_join(state_features, by = "state_abb") %>%
      mutate(gi = .mi(pseudo_g))
    rows[[length(rows) + 1L]] <- tibble(
      placement = pl, seed = s, n_treated = nrow(sch),
      cor_date_trend = suppressWarnings(cor(sch$gi, sch$trend_slope)),
      cor_date_cov   = suppressWarnings(cor(sch$gi, sch$coverage_months)))
  }
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("%-13s draws=%d infeasible=%d (%.1fs)\n", pl, N_DRAWS, nfail, el))
}
res <- bind_rows(rows)
write_csv(res, file.path(OUT, "placement_draws.csv"))

cat("\n=== corr(pseudo-adoption date, own trend slope) by placement rule\n")
summ <- res %>% group_by(placement) %>%
  summarise(n = n(), mean_cor = mean(cor_date_trend, na.rm = TRUE),
            sd_cor = sd(cor_date_trend, na.rm = TRUE),
            share_negative = mean(cor_date_trend < 0, na.rm = TRUE),
            mean_cor_date_coverage = mean(cor_date_cov, na.rm = TRUE),
            .groups = "drop")
print(as.data.frame(summ), digits = 3)
write_csv(summ, file.path(OUT, "placement_summary.csv"))
cat("\nExchangeable placement => mean_cor ~ 0 and share_negative ~ 0.5.\n")
cat("Real-data benchmark: -0.078 (ETS, n=16) / +0.215 (annual, n=23), both n.s.\n")
