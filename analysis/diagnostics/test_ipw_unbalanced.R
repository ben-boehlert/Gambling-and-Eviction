#!/usr/bin/env Rscript
################################################################################
# test_ipw_unbalanced.R
#
# Test if est_method="ipw" works with unbalanced panel
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(did)
})

cat("TESTING: Does IPW Estimator Work with Unbalanced Panel?\n")
cat("========================================================\n\n")

################################################################################
# Create unbalanced panel (matching test structure)
################################################################################

set.seed(999)
n_states <- 38
months_per_state <- round(runif(n_states, min = 33, max = 165))

panel_unbal <- do.call(rbind, lapply(1:n_states, function(i) {
  n_t <- months_per_state[i]
  data.frame(
    id = i,
    t = 1:n_t
  )
}))

# Staggered treatment
g_assignment <- c(
  rep(0, 10),   # never treated
  rep(40, 9),   # early adopters
  rep(60, 9),   # mid adopters
  rep(80, 10)   # late adopters
)
panel_unbal$g <- g_assignment[panel_unbal$id]

# Fixed effects
state_fe <- rnorm(n_states, mean = 5, sd = 1)
time_fe_extended <- rnorm(165, mean = 0, sd = 0.5)
panel_unbal$state_fe <- state_fe[panel_unbal$id]
panel_unbal$time_fe <- time_fe_extended[panel_unbal$t]

cat("Panel structure:\n")
cat("  n_states:", n_states, "\n")
cat("  months per state: min=", min(months_per_state), ", max=", max(months_per_state), "\n")
cat("  total observations:", nrow(panel_unbal), "\n\n")

################################################################################
# Run with IPW estimator
################################################################################

run_sim_ipw <- function(seed) {
  set.seed(seed)
  e <- rnorm(nrow(panel_unbal), 0, 1)
  y <- panel_unbal$state_fe + panel_unbal$time_fe + e

  dat <- data.frame(
    id = panel_unbal$id,
    t = panel_unbal$t,
    g = panel_unbal$g,
    y = y
  )

  tryCatch({
    est <- did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", xformla = ~ 1,
      data = dat, panel = TRUE, control_group = "notyettreated",
      allow_unbalanced_panel = TRUE,
      est_method = "ipw",  # <-- IPW INSTEAD OF REG
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

cat("Running 20 simulations with est_method='ipw'...\n")
set.seed(12345)
results_ipw <- lapply(sample.int(1e8, 20), function(s) {
  cat(".")
  run_sim_ipw(s)
})
cat("\n\n")

ok_ipw <- sapply(results_ipw, function(r) r$ok)
cat("SUCCESS RATE:", sum(ok_ipw), "/", length(results_ipw), "\n\n")

if (sum(ok_ipw) > 0) {
  att_ipw <- sapply(results_ipw, function(r) r$att)[ok_ipw]
  se_ipw <- sapply(results_ipw, function(r) r$se)[ok_ipw]

  cat("IPW Results:\n")
  cat("  Mean ATT:", round(mean(att_ipw), 4), "\n")
  cat("  SD(ATT):", round(sd(att_ipw), 4), "\n")
  cat("  Mean SE:", round(mean(se_ipw), 4), "\n")
  cat("  SE inflation:", round(mean(se_ipw) / sd(att_ipw), 4), "\n")

  p_vals <- 2 * pnorm(-abs(att_ipw / se_ipw))
  cat("  Rejection rate:", round(mean(p_vals < 0.05), 4), "\n\n")

  if (abs(mean(se_ipw) / sd(att_ipw) - 1.0) < 0.15) {
    cat("*** SUCCESS! IPW works with unbalanced panel! ***\n")
    cat("\nFIX: Change est_method from 'reg' to 'ipw'\n")
  } else {
    cat("IPW completes but still has SE inflation issue.\n")
  }
} else {
  cat("IPW also fails with unbalanced panel.\n")
  errors <- sapply(results_ipw, function(r) if (!r$ok) r$msg else NA)
  cat("\nError messages:\n")
  print(unique(errors[!is.na(errors)]))
}
