#!/usr/bin/env Rscript
################################################################################
# test_auto_balance_fix.R
#
# Test if allow_unbalanced_panel=FALSE (auto-balancing) fixes SE inflation
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(did)
})

cat("TESTING: Does Auto-Balancing (allow_unbalanced_panel=FALSE) Fix SE Inflation?\n")
cat("=============================================================================\n\n")

################################################################################
# Load actual panel if available, otherwise create test panel
################################################################################

if (file.exists("/tmp/cs_test_out/panel_for_diagnosis.rds")) {
  cat("Loading saved panel data...\n")
  panel_data <- readRDS("/tmp/cs_test_out/panel_for_diagnosis.rds")
  panel_full <- panel_data$panel
  resid_pool_by_t <- panel_data$resid_pool_by_t
  global_pool <- panel_data$global_pool
  MIN_STATES_PER_MONTH <- panel_data$MIN_STATES_PER_MONTH

  cat("Panel loaded successfully\n")
  cat("  n_states:", length(unique(panel_full$id)), "\n")
  cat("  n_obs:", nrow(panel_full), "\n\n")

} else {
  cat("Panel data not found - creating synthetic test panel...\n")

  set.seed(999)
  n_states <- 38
  months_per_state <- round(runif(n_states, min = 33, max = 165))

  panel_full <- do.call(rbind, lapply(1:n_states, function(i) {
    n_t <- months_per_state[i]
    data.frame(id = i, t = 1:n_t)
  }))

  g_assignment <- c(rep(0, 10), rep(40, 9), rep(60, 9), rep(80, 10))
  panel_full$g <- g_assignment[panel_full$id]

  state_fe <- rnorm(n_states, mean = 5, sd = 1)
  time_fe_extended <- rnorm(165, mean = 0, sd = 0.5)
  panel_full$state_fe <- state_fe[panel_full$id]
  panel_full$time_fe <- time_fe_extended[panel_full$t]
  panel_full$yhat <- panel_full$state_fe + panel_full$time_fe

  # Create residual pools
  MIN_STATES_PER_MONTH <- 5
  resid_pool_by_t <- list()
  global_pool <- rnorm(1000, 0, 1)

  cat("Synthetic panel created\n")
  cat("  n_states:", n_states, "\n")
  cat("  n_obs:", nrow(panel_full), "\n\n")
}

################################################################################
# Error generation function
################################################################################

draw_errors_iid_month <- function(t_vec, pool_by_t, fallback_pool, min_states) {
  e <- numeric(length(t_vec))
  for (t_val in unique(t_vec)) {
    idx <- which(t_vec == t_val)
    pool <- pool_by_t[[as.character(t_val)]]
    if (is.null(pool) || length(pool) < min_states) pool <- fallback_pool
    e[idx] <- sample(pool, size = length(idx), replace = TRUE)
  }
  e
}

################################################################################
# Run simulation with allow_unbalanced_panel=FALSE (auto-balancing)
################################################################################

run_sim_autobalance <- function(seed) {
  set.seed(seed)

  # Generate errors
  if (exists("resid_pool_by_t") && !is.null(resid_pool_by_t)) {
    e <- draw_errors_iid_month(panel_full$t, resid_pool_by_t, global_pool, MIN_STATES_PER_MONTH)
  } else {
    e <- rnorm(nrow(panel_full), 0, 1)
  }

  y_sim <- panel_full$yhat + e  # effect=0

  dat <- data.frame(
    id = panel_full$id,
    t = panel_full$t,
    g = panel_full$g,
    y = y_sim
  )

  tryCatch({
    est <- did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", xformla = ~ 1,
      data = dat, panel = TRUE, control_group = "notyettreated",
      allow_unbalanced_panel = FALSE,  # <-- AUTO-BALANCE
      est_method = "reg",
      bstrap = TRUE, biters = 199,
      cband = FALSE, clustervars = "id"
    )

    agg <- did::aggte(est, type = "simple", na.rm = TRUE)

    list(
      ok = TRUE,
      att = as.numeric(agg$overall.att),
      se = as.numeric(agg$overall.se)
    )
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, msg = e$message)
  })
}

################################################################################
# Run many simulations
################################################################################

n_sims <- 50
cat("Running", n_sims, "simulations with allow_unbalanced_panel=FALSE...\n")
set.seed(12345)
results <- lapply(sample.int(1e8, n_sims), function(s) {
  if (s %% 10 == 0) cat(".")
  run_sim_autobalance(s)
})
cat("\n\n")

ok_vec <- sapply(results, function(r) r$ok)
cat("Success rate:", sum(ok_vec), "/", n_sims, "\n\n")

if (sum(ok_vec) > 0) {
  att_vec <- sapply(results, function(r) r$att)[ok_vec]
  se_vec <- sapply(results, function(r) r$se)[ok_vec]

  cat("Results with Auto-Balancing:\n")
  cat("  Mean ATT:", round(mean(att_vec), 4), "\n")
  cat("  SD(ATT):", round(sd(att_vec), 4), "\n")
  cat("  Mean SE:", round(mean(se_vec), 4), "\n")
  cat("  SE inflation:", round(mean(se_vec) / sd(att_vec), 4), "\n")

  p_vals <- 2 * pnorm(-abs(att_vec / se_vec))
  cat("  Rejection rate:", round(mean(p_vals < 0.05), 4), "\n\n")

  if (abs(mean(se_vec) / sd(att_vec) - 1.0) < 0.15 && abs(mean(p_vals < 0.05) - 0.05) < 0.05) {
    cat("*** SUCCESS! Auto-balancing fixes the problem! ***\n")
    cat("\nFIX: Set allow_unbalanced_panel=FALSE\n")
    cat("     The did package will automatically drop states to create a balanced panel.\n")
  } else {
    cat("Auto-balancing helps but SE inflation persists.\n")
    cat("SE inflation:", round(mean(se_vec) / sd(att_vec), 4), "\n")
    cat("Rejection rate:", round(mean(p_vals < 0.05), 4), "\n")
  }
} else {
  cat("All simulations failed.\n")
  errors <- sapply(results, function(r) if (!r$ok && !is.null(r$msg)) r$msg else NA)
  cat("\nUnique errors:\n")
  print(unique(errors[!is.na(errors)]))
}
