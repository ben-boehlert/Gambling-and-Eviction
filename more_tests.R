#!/usr/bin/env Rscript
# power_simulation_tests.R
#
# A small test suite for your simulation/estimator plumbing.
# Run:
#   Rscript power_simulation_tests.R
#
# Optional env vars:
#   POWER_SIM_SCRIPT=/path/to/power_simulation_cs.R   (default: ./power_simulation_cs.R)
#   RUN_INTEGRATION=1                                (default: 0)  # tries to load your real data files

suppressPackageStartupMessages({
  library(testthat)
  library(tidyverse)
  library(future)
  library(furrr)
})

SIM_PATH <- Sys.getenv("POWER_SIM_SCRIPT", "power_simulation_cs.R")
RUN_INTEGRATION <- identical(Sys.getenv("RUN_INTEGRATION", "0"), "1")

if (!file.exists(SIM_PATH)) {
  stop("Cannot find power_simulation_cs.R at: ", SIM_PATH)
}

source(SIM_PATH)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

make_cfg_test <- function(...) {
  # Keep bootstrap off in tests for determinism + speed.
  base <- list(
    weights_var = NULL,
    did_bstrap = FALSE,
    did_biters = 10,
    did_cband  = FALSE,
    estimand   = "overall_att",
    target_h   = 12,
    alpha      = 0.05
  )
  modifyList(base, list(...))
}

make_synthetic_df_sim <- function(
    n_units = 40,
    n_months = 24,
    treated_share = 0.5,
    treat_month = 13,
    effect = 0,
    time_id_base = 2018 * 12L
) {
  stopifnot(treat_month >= 2, treat_month <= n_months)
  
  units <- tibble(
    unit_id = 1:n_units,
    state_abb = rep(state.abb[1:10], length.out = n_units)
  ) %>%
    mutate(
      ever_treated = runif(n_units) < treated_share,
      g_placebo_month = if_else(ever_treated, treat_month, NA_integer_)
    )
  
  df <- tidyr::expand_grid(
    unit_id = units$unit_id,
    t = 1:n_months
  ) %>%
    left_join(units, by = "unit_id") %>%
    mutate(
      time_id = time_id_base + t,                         # "large" time_id like your real data
      g_placebo = if_else(is.na(g_placebo_month), 0L, time_id_base + g_placebo_month),
      post = (t >= treat_month) & (g_placebo > 0L),
      
      # outcome with FE + trend + optional treatment effect
      u_fe = rnorm(n_units)[unit_id],
      t_fe = 0.02 * t + rnorm(n_months, sd = 0.05)[t],
      outcome_sim = u_fe + t_fe + (effect * as.numeric(post)) + rnorm(n(), sd = 1)
    ) %>%
    select(unit_id, time_id, outcome_sim, g_placebo, state_abb)
  
  df
}

run_many_estimates_fresh <- function(effect, cfg, cluster_var, n_sims = 300, seed = 1) {
  set.seed(seed)
  
  purrr::map_dfr(seq_len(n_sims), function(s) {
    df_s <- make_synthetic_df_sim(effect = effect)
    
    res <- run_estimator_and_extract_p(df_s, cfg = cfg, cluster_var = cluster_var)
    
    tstat <- if (is.finite(res$est) && is.finite(res$se) && res$se > 0) res$est / res$se else NA_real_
    
    tibble(
      sim = s,
      p   = as.numeric(res$p),
      est = as.numeric(res$est),
      se  = as.numeric(res$se),
      t   = tstat
    )
  })
}



power_strict <- function(p, alpha) mean(!is.na(p) & p <= alpha)
power_na_rm  <- function(p, alpha) mean(p <= alpha, na.rm = TRUE)

# ------------------------------------------------------------------------------
# TESTS
# ------------------------------------------------------------------------------

test_that("Estimator does not emit 'Inf assigned to integer' / out-of-range warnings (gname type check)", {
  cfg <- make_cfg_test()
  df0 <- make_synthetic_df_sim(effect = 0)
  
  # Run once and capture warnings (if any)
  warn_msgs <- character(0)
  out <- withCallingHandlers(
    run_estimator_and_extract_p(df0, cfg = cfg, cluster_var = "state_abb"),
    warning = function(w) {
      warn_msgs <<- c(warn_msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  
  # If gname is still integer inside your estimator input, did may warn about Inf/out-of-range.
  # After you fix gname to be numeric/double, this should be clean.
  expect_true(is.list(out))
  expect_true(is.na(out$p) || (is.finite(out$p) && out$p >= 0 && out$p <= 1))
  
  bad <- str_detect(tolower(warn_msgs), "inf") |
    str_detect(tolower(warn_msgs), "out-of-range") |
    str_detect(tolower(warn_msgs), "out of range")
  
  expect_false(any(bad),
               info = paste("Saw warnings consistent with the gname integer/Inf bug:\n",
                            paste0(" - ", warn_msgs, collapse = "\n"))
  )
})

test_that("Null size is roughly alpha using STRICT denominator (failures count as non-rejection)", {
  cfg <- make_cfg_test(alpha = 0.05)
  df0 <- make_synthetic_df_sim(effect = 0)
  
  draws <- run_many_estimates_fresh(effect = 0, cfg = cfg, cluster_var = "state_abb", n_sims = 300, seed = 1)
  size_hat <- power_strict(draws$p, cfg$alpha)
  
  # Binomial SE band around alpha
  se <- sqrt(cfg$alpha * (1 - cfg$alpha) / nrow(draws))
  tol <- 3 * se  # loose enough for quick runs; tighten if you raise n_sims
  
  msg <- paste0(
    "size_hat=", round(size_hat, 3),
    " alpha=", cfg$alpha,
    " tol=", round(tol, 3),
    " NA_rate=", round(mean(is.na(draws$p)), 3)
  )
  
  testthat::expect_true(abs(size_hat - cfg$alpha) < tol, info = msg)
  
})

test_that("Power increases with effect size (STRICT power)", {
  cfg <- make_cfg_test(alpha = 0.05)
  df_small <- make_synthetic_df_sim(effect = 0.5)
  df_big   <- make_synthetic_df_sim(effect = 2.0)
  
  d1 <- run_many_estimates_fresh(df_small, cfg, "state_abb", n_sims = 250, seed = 2)
  d2 <- run_many_estimates_fresh(df_big,   cfg, "state_abb", n_sims = 250, seed = 3)
  
  p1 <- power_strict(d1$p, cfg$alpha)
  p2 <- power_strict(d2$p, cfg$alpha)
  
  expect_gt(p2, p1,
            info = paste0("power_small=", round(p1, 3),
                          " power_big=", round(p2, 3),
                          " NA_small=", round(mean(is.na(d1$p)), 3),
                          " NA_big=", round(mean(is.na(d2$p)), 3)))
})

test_that("NA handling: na.rm power is never smaller than strict power", {
  cfg <- make_cfg_test(alpha = 0.05)
  df0 <- make_synthetic_df_sim(effect = 0)
  
  draws <- run_many_estimates_fresh(effect = 0, cfg = cfg, cluster_var = "state_abb", n_sims = 300, seed = 1)
  
  p_strict <- power_strict(draws$p, cfg$alpha)
  p_narm   <- power_na_rm(draws$p, cfg$alpha)
  
  expect_gte(p_narm, p_strict)
})

test_that("Sequential vs parallel reproducibility (bootstrap OFF)", {
  cfg <- make_cfg_test(alpha = 0.05, did_bstrap = FALSE, did_biters = 10)
  
  df0 <- make_synthetic_df_sim(effect = 1.0)
  
  # sequential
  set.seed(999)
  p_seq <- purrr::map_dbl(1:50, ~ run_estimator_and_extract_p(
    df0 %>% mutate(outcome_sim = outcome_sim + rnorm(n(), sd = 1e-6)),
    cfg = cfg, cluster_var = "state_abb"
  )$p)
  
  # parallel (furrr) with deterministic seeding
  plan(multisession, workers = 2)
  set.seed(999)
  p_par <- furrr::future_map_dbl(
    1:50,
    ~ run_estimator_and_extract_p(
      df0 %>% mutate(outcome_sim = outcome_sim + rnorm(n(), sd = 1e-6)),
      cfg = cfg, cluster_var = "state_abb"
    )$p,
    .options = furrr::furrr_options(seed = TRUE)
  )
  plan(sequential)
  
  # Allow exact equality; if this fails, you have RNG nondeterminism somewhere.
  expect_identical(p_seq, p_par)
})

# ------------------------------------------------------------------------------
# Optional integration smoke tests (uses your real data pipeline)
# ------------------------------------------------------------------------------

if (RUN_INTEGRATION) {
  test_that("Integration smoke: can load panel + treatment schedule", {
    cfg <- cfg
    cfg$use_parallel <- FALSE
    cfg$did_bstrap <- FALSE
    cfg$did_biters <- 10
    cfg$run_state_switcher_grid <- FALSE
    cfg$n_sims <- 5
    cfg$effect_grid <- c(0, 1)
    
    panel_df <- load_panel(cfg)
    expect_true(nrow(panel_df) > 0)
    expect_true("unit_id" %in% names(panel_df))
    expect_true("time_id" %in% names(panel_df))
    
    ts <- make_treat_schedule(panel_df, cfg)
    tss <- standardize_treat_schedule(ts, panel_df)
    expect_true(nrow(tss) > 0)
  })
}

# ------------------------------------------------------------------------------
# Run tests and exit with status
# ------------------------------------------------------------------------------

res <- testthat::test_dir(
  path = tempdir(), # dummy; we run inline below
  reporter = "summary"
)

# Running inline tests: testthat executes them as the file is sourced.
# If any expectation fails, Rscript exits non-zero by default in most setups.
cat("\nDone.\n")
