#!/usr/bin/env Rscript
################################################################################
# diagnose_panel_issue.R
#
# Understand why balanced panel with 37 periods fails
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
})

set.seed(999)
n_states <- 38
months_per_state <- round(runif(n_states, min = 33, max = 165))

# Staggered treatment
g_assignment <- c(
  rep(0, 10),   # never treated
  rep(40, 9),   # early adopters
  rep(60, 9),   # mid adopters
  rep(80, 10)   # late adopters
)

cat("Treatment timing:\n")
cat("  Never treated:", sum(g_assignment == 0), "states\n")
cat("  Early (g=40):", sum(g_assignment == 40), "states\n")
cat("  Mid (g=60):", sum(g_assignment == 60), "states\n")
cat("  Late (g=80):", sum(g_assignment == 80), "states\n\n")

cat("Panel time range needed:\n")
cat("  Min months per state:", min(months_per_state), "\n")
cat("  Max months per state:", max(months_per_state), "\n")
cat("  Latest treatment starts at t=80\n\n")

cat("PROBLEM: If we balance to min=37 periods, we have:\n")
cat("  - Time range: 1 to 37\n")
cat("  - Early treatment (g=40): NEVER OCCURS (40 > 37)\n")
cat("  - Mid treatment (g=60): NEVER OCCURS\n")
cat("  - Late treatment (g=80): NEVER OCCURS\n")
cat("  - Result: NO TREATED OBSERVATIONS!\n\n")

cat("SOLUTION OPTIONS:\n")
cat("1. Balance to a longer common period (but this drops many states)\n")
cat("2. Don't use allow_unbalanced_panel (causes segfault)\n")
cat("3. Use a different estimator that handles unbalanced panels\n")
cat("4. Manually balance by filling missing periods with interpolation/imputation\n\n")

# What if we balance to 120 periods?
states_with_120 <- sum(months_per_state >= 120)
cat("If we require 120 periods:\n")
cat("  States remaining:", states_with_120, "/", n_states, "\n")
cat("  This drops", n_states - states_with_120, "states\n\n")

# Distribution
cat("Distribution of months per state:\n")
print(summary(months_per_state))
cat("\nQuantiles:\n")
print(quantile(months_per_state, probs = c(0.1, 0.25, 0.5, 0.75, 0.9)))
