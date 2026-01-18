#!/usr/bin/env Rscript
################################################################################
# test_unbalanced_panel_effect.R
#
# Test if UNBALANCED panel causes SE inflation in CS-DiD
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(did)
})

cat("TESTING: Does Unbalanced Panel Cause SE Inflation?\n")
cat("===================================================\n\n")

################################################################################
# Test 1: Balanced panel (baseline)
################################################################################

set.seed(999)
n_states <- 38  # Match your n_states
n_months <- 120

panel_balanced <- expand.grid(
  id = 1:n_states,
  t = 1:n_months
)

# Staggered treatment (similar to yours)
g_assignment <- c(
  rep(0, 10),   # never treated
  rep(40, 9),   # early adopters
  rep(60, 9),   # mid adopters
  rep(80, 10)   # late adopters
)
panel_balanced$g <- g_assignment[panel_balanced$id]

state_fe <- rnorm(n_states, mean = 5, sd = 1)
time_fe <- rnorm(n_months, mean = 0, sd = 0.5)
panel_balanced$state_fe <- state_fe[panel_balanced$id]
panel_balanced$time_fe <- time_fe[panel_balanced$t]

run_sim_balanced <- function(seed) {
  set.seed(seed)
  e <- rnorm(nrow(panel_balanced), 0, 1)
  y <- panel_balanced$state_fe + panel_balanced$time_fe + e

  dat <- data.frame(
    id = panel_balanced$id,
    t = panel_balanced$t,
    g = panel_balanced$g,
    y = y
  )

  tryCatch({
    est <- did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g", xformla = ~ 1,
      data = dat, panel = TRUE, control_group = "notyettreated",
      est_method = "reg", bstrap = TRUE, biters = 199,
      cband = FALSE, clustervars = "id"
    )
    agg <- did::aggte(est, type = "simple", na.rm = TRUE)
    list(ok = TRUE, att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se))
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_)
  })
}

cat("Test 1: Balanced panel (38 states × 120 months)\n")
set.seed(12345)
results_bal <- lapply(sample.int(1e8, 100), run_sim_balanced)
ok_bal <- sapply(results_bal, function(r) r$ok)
att_bal <- sapply(results_bal, function(r) r$att)[ok_bal]
se_bal <- sapply(results_bal, function(r) r$se)[ok_bal]

cat("  SD(ATT):", round(sd(att_bal), 4), "\n")
cat("  Mean(SE):", round(mean(se_bal), 4), "\n")
cat("  SE inflation:", round(mean(se_bal) / sd(att_bal), 4), "\n\n")

################################################################################
# Test 2: Unbalanced panel (match your structure)
################################################################################

# Create unbalanced panel matching your range: 33 to 165 months
set.seed(999)
months_per_state <- round(runif(n_states, min = 33, max = 165))

panel_unbal <- do.call(rbind, lapply(1:n_states, function(i) {
  n_t <- months_per_state[i]
  data.frame(
    id = i,
    t = 1:n_t
  )
}))

# Same treatment assignment
g_assignment_unbal <- g_assignment[panel_unbal$id]
panel_unbal$g <- g_assignment_unbal

# Same FEs (but time FE needs more periods now)
time_fe_extended <- rnorm(165, mean = 0, sd = 0.5)
panel_unbal$state_fe <- state_fe[panel_unbal$id]
panel_unbal$time_fe <- time_fe_extended[panel_unbal$t]

run_sim_unbalanced <- function(seed) {
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
      allow_unbalanced_panel = TRUE,  # CRITICAL
      est_method = "reg", bstrap = TRUE, biters = 199,
      cband = FALSE, clustervars = "id"
    )
    agg <- did::aggte(est, type = "simple", na.rm = TRUE)
    list(ok = TRUE, att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se))
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_)
  })
}

cat("Test 2: Unbalanced panel (38 states, 33-165 months each)\n")
set.seed(12345)
results_unbal <- lapply(sample.int(1e8, 100), run_sim_unbalanced)
ok_unbal <- sapply(results_unbal, function(r) r$ok)
att_unbal <- sapply(results_unbal, function(r) r$att)[ok_unbal]
se_unbal <- sapply(results_unbal, function(r) r$se)[ok_unbal]

cat("  SD(ATT):", round(sd(att_unbal), 4), "\n")
cat("  Mean(SE):", round(mean(se_unbal), 4), "\n")
cat("  SE inflation:", round(mean(se_unbal) / sd(att_unbal), 4), "\n\n")

################################################################################
# Compare
################################################################################

cat("COMPARISON:\n")
cat("===========\n")
cat("Balanced panel SE inflation:", round(mean(se_bal) / sd(att_bal), 4), "\n")
cat("Unbalanced panel SE inflation:", round(mean(se_unbal) / sd(att_unbal), 4), "\n")
cat("Ratio (unbalanced / balanced):", round((mean(se_unbal)/sd(att_unbal)) / (mean(se_bal)/sd(att_bal)), 4), "\n\n")

if ((mean(se_unbal)/sd(att_unbal)) > 1.5 * (mean(se_bal)/sd(att_bal))) {
  cat("*** UNBALANCED PANEL CAUSES SUBSTANTIAL SE INFLATION! ***\n")
  cat("This explains your 0% rejection.\n")
} else {
  cat("Unbalanced panel does not cause major SE inflation.\n")
  cat("The problem must be elsewhere.\n")
}
