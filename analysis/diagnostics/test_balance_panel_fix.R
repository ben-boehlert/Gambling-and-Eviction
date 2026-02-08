#!/usr/bin/env Rscript
################################################################################
# test_balance_panel_fix.R
#
# Test if converting unbalanced panel to balanced fixes the SE inflation
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(did)
})

cat("TESTING: Does Balancing Panel Fix SE Inflation?\n")
cat("================================================\n\n")

################################################################################
# Create unbalanced panel (like user's data)
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

cat("Original unbalanced panel:\n")
cat("  n_obs:", nrow(panel_unbal), "\n")
cat("  months per state: min=", min(months_per_state), ", max=", max(months_per_state), "\n\n")

################################################################################
# Create balanced version (keep only common time periods)
################################################################################

# Find common time range across all states
common_t_min <- 1
common_t_max <- min(months_per_state)

panel_bal <- panel_unbal %>%
  filter(t >= common_t_min, t <= common_t_max)

cat("Balanced panel (common time periods only):\n")
cat("  n_obs:", nrow(panel_bal), "\n")
cat("  time periods:", common_t_min, "to", common_t_max, "(", common_t_max - common_t_min + 1, "periods)\n\n")

################################################################################
# Run simulation on balanced panel
################################################################################

run_sim_balanced <- function(seed) {
  set.seed(seed)
  e <- rnorm(nrow(panel_bal), 0, 1)
  y <- panel_bal$state_fe + panel_bal$time_fe + e

  dat <- data.frame(
    id = panel_bal$id,
    t = panel_bal$t,
    g = panel_bal$g,
    y = y
  )

  tryCatch({
    est <- did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", xformla = ~ 1,
      data = dat, panel = TRUE, control_group = "notyettreated",
      allow_unbalanced_panel = FALSE,  # No longer needed!
      est_method = "reg", bstrap = TRUE, biters = 199,
      cband = FALSE, clustervars = "id"
    )
    agg <- did::aggte(est, type = "simple", na.rm = TRUE)
    list(ok = TRUE, att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se))
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, msg = e$message)
  })
}

cat("Running 50 simulations on balanced panel...\n")
set.seed(12345)
results_bal <- lapply(sample.int(1e8, 50), run_sim_balanced)
ok_bal <- sapply(results_bal, function(r) r$ok)
att_bal <- sapply(results_bal, function(r) r$att)[ok_bal]
se_bal <- sapply(results_bal, function(r) r$se)[ok_bal]

cat("\nBalanced Panel Results:\n")
cat("  Success rate:", sum(ok_bal), "/", length(results_bal), "\n")
cat("  SD(ATT):", round(sd(att_bal), 4), "\n")
cat("  Mean(SE):", round(mean(se_bal), 4), "\n")
cat("  SE inflation:", round(mean(se_bal) / sd(att_bal), 4), "\n")

p_vals <- 2 * pnorm(-abs(att_bal / se_bal))
cat("  Rejection rate:", round(mean(p_vals < 0.05), 4), "\n\n")

if (abs(mean(se_bal) / sd(att_bal) - 1.0) < 0.1 && abs(mean(p_vals < 0.05) - 0.05) < 0.03) {
  cat("*** SUCCESS! Balanced panel fixes the problem! ***\n")
  cat("\nFIX: Balance the panel before running CS-DiD by keeping only\n")
  cat("     time periods that are observed for ALL states.\n")
} else {
  cat("*** Problem persists even with balanced panel. ***\n")
  cat("    Need to investigate further.\n")
}
