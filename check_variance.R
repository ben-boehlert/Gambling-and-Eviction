#!/usr/bin/env Rscript
# Check if the simulated variance matches the real data

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
})

# Load the real data
panel <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)
treat <- read_csv("state_month_panel_with_treatment.csv", show_col_types = FALSE)

# Basic processing (from the main script)
panel <- panel %>%
  mutate(
    month_date = as.Date(month_date),
    y = log1p(pmax(filings_count, 0))
  )

# Merge treatment
panel <- panel %>%
  left_join(treat %>% select(state_abb, month_date, treated),
            by = c("state_abb", "month_date"))

cat("=== VARIANCE ANALYSIS ===\n\n")

# Overall variance
cat("Overall outcome variance:\n")
cat("  SD of log1p(filings_count):", sd(panel$y, na.rm = TRUE), "\n")
cat("  Mean:", mean(panel$y, na.rm = TRUE), "\n\n")

# Within-state variance (after state FE)
state_means <- panel %>%
  group_by(state_abb) %>%
  summarise(mean_y = mean(y, na.rm = TRUE), .groups = "drop")

panel <- panel %>%
  left_join(state_means, by = "state_abb") %>%
  mutate(y_demeaned = y - mean_y)

cat("After state fixed effects:\n")
cat("  SD of demeaned outcome:", sd(panel$y_demeaned, na.rm = TRUE), "\n\n")

# Fit a simple 2WFE model to get the residual SD
cat("Fitting two-way FE model on full panel...\n")
fe_full <- feols(y ~ 1 | state_abb + month_date, data = panel, notes = FALSE, warn = FALSE)
resid_full <- residuals(fe_full)
cat("  Residual SD:", sd(resid_full, na.rm = TRUE), "\n")
cat("  R-squared:", summary(fe_full)$r.squared, "\n\n")

# Compare to what the simulation uses
cat("What the power simulation should see:\n")
cat("  If the simulation residuals have SD ~", sd(resid_full, na.rm = TRUE), "\n")
cat("  And you're estimating an effect of 0.18 (20% increase)\n")
cat("  With 23 treated states over ~167 months\n")
cat("  The SE should be approximately:\n")
cat("    ", sd(resid_full, na.rm = TRUE) / sqrt(23), "assuming simple calculation\n")
cat("    (actual will depend on treatment timing)\n\n")

# Check ATT from real data if there's variation in treatment
if (any(panel$treated == 1, na.rm = TRUE)) {
  cat("Checking actual treatment effect in real data:\n")
  treated_mean <- mean(panel$y[panel$treated == 1], na.rm = TRUE)
  control_mean <- mean(panel$y[panel$treated == 0], na.rm = TRUE)
  cat("  Treated mean:", treated_mean, "\n")
  cat("  Control mean:", control_mean, "\n")
  cat("  Difference:", treated_mean - control_mean, "\n\n")
}

cat("=== ANALYSIS COMPLETE ===\n")
