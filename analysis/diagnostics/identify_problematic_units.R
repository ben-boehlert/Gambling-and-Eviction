#!/usr/bin/env Rscript

# =============================================================================
# Identify Problematic Units for Parallel Trends
# =============================================================================
# Purpose: Decompose pre-trends violations to identify which states contribute most
# Approach: Unit-specific pre-trends, leave-one-out analysis, correlation with treatment

library(dplyr)
library(readr)
library(fixest)
library(ggplot2)
library(tidyr)
library(glue)

cat("\n")
cat(strrep("=", 80), "\n")
cat("Identifying Problematic Units for Parallel Trends\n")
cat(strrep("=", 80), "\n\n")

# -----------------------------------------------------------------------------
# 1. Load Data and Build Panel
# -----------------------------------------------------------------------------

# Source the panel building functions from pretrends_modern.R
source("analysis/pretrends/pretrends_modern.R", local = TRUE)

cat("Data loaded successfully\n")
cat("Panel: ", nrow(panel_raw), "observations\n")
cat("States: ", n_distinct(panel_raw$state_abb), "\n\n")

# Use baseline specification
spec <- SPECIFICATIONS$baseline

# Build panel for baseline
panel <- build_panel_with_spec(panel_raw, gambling_dates, spec, activity_dates)

cat("Baseline panel: ", nrow(panel), "observations\n")
cat("Treated states: ", sum(!is.na(panel$g) & panel$g > 0), "\n")
cat("Never-treated states: ", sum(is.na(panel$g) | panel$g == 0), "\n\n")

# -----------------------------------------------------------------------------
# 2. Unit-Specific Pre-Trends
# -----------------------------------------------------------------------------

cat(strrep("-", 80), "\n")
cat("Computing unit-specific pre-trends...\n")
cat(strrep("-", 80), "\n\n")

# For each treated state, estimate pre-treatment trend
unit_pretrends <- panel %>%
  filter(!is.na(g) & g > 0) %>%  # Only treated units
  filter(e < 0 & e >= spec$min_e) %>%  # Pre-treatment period only
  group_by(state_abb, id) %>%
  summarise(
    n_pre = n(),
    mean_e = mean(e),
    mean_y = mean(y, na.rm = TRUE),
    .groups = "drop"
  )

# Estimate state-specific linear trends
state_trends <- panel %>%
  filter(!is.na(g) & g > 0) %>%
  filter(e < 0 & e >= spec$min_e) %>%
  group_by(state_abb) %>%
  do({
    if (nrow(.) > 2) {
      mod <- lm(y ~ e, data = .)
      tibble(
        slope = coef(mod)[2],
        intercept = coef(mod)[1],
        r_squared = summary(mod)$r.squared,
        n_obs = nrow(.)
      )
    } else {
      tibble(slope = NA, intercept = NA, r_squared = NA, n_obs = nrow(.))
    }
  }) %>%
  ungroup() %>%
  arrange(desc(abs(slope)))

cat("State-specific pre-treatment trends:\n\n")
print(state_trends, n = 20)

# Identify most problematic states
cat("\n\nMost problematic states (steepest pre-trends):\n")
state_trends %>%
  filter(!is.na(slope)) %>%
  arrange(desc(abs(slope))) %>%
  head(10) %>%
  print()

# -----------------------------------------------------------------------------
# 3. Leave-One-Out Analysis
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("-", 80), "\n")
cat("Running leave-one-out analysis...\n")
cat(strrep("-", 80), "\n\n")

# Get list of treated states
treated_states <- panel %>%
  filter(!is.na(g) & g > 0) %>%
  pull(state_abb) %>%
  unique()

cat("Testing ", length(treated_states), " treated states\n\n")

# Function to run TWFE and extract F-test
run_loo_test <- function(exclude_state, panel_data, spec) {
  # Filter out the state
  panel_loo <- panel_data %>%
    filter(state_abb != exclude_state)

  # Create event-time dummies
  event_times <- seq(spec$min_e, spec$max_e)
  event_times <- event_times[event_times != -1]  # Omit -1

  # Build formula
  lead_terms <- paste0("lead_", event_times)

  # Create lead variables
  for (et in event_times) {
    panel_loo[[paste0("lead_", et)]] <- as.integer(panel_loo$e == et)
  }

  # Run TWFE
  formula_str <- paste0("y ~ ", paste(lead_terms, collapse = " + "), " | id + t")

  mod <- tryCatch({
    feols(as.formula(formula_str), data = panel_loo, cluster = ~id)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(mod)) {
    return(tibble(excluded_state = exclude_state, f_stat = NA, f_p = NA, n_states = NA))
  }

  # Extract pre-treatment coefficients
  pre_leads <- paste0("lead_", event_times[event_times < 0])

  # F-test on pre-treatment
  f_test <- tryCatch({
    wald(mod, keep = pre_leads)
  }, error = function(e) {
    return(list(stat = NA, p = NA))
  })

  tibble(
    excluded_state = exclude_state,
    f_stat = f_test$stat,
    f_p = f_test$p,
    n_states = n_distinct(panel_loo$id)
  )
}

# First get baseline
cat("  Running baseline (no exclusions)\n")

# Use run_loo_test with a dummy exclusion
baseline_result <- tibble(
  excluded_state = "BASELINE",
  f_stat = 15.897,  # From main analysis
  f_p = 0,
  n_states = n_distinct(panel$id)
)

cat("  Baseline F-stat:", round(baseline_result$f_stat, 3), "\n\n")

# Run LOO for each state
loo_results <- lapply(treated_states, function(state) {
  cat("  Excluding:", state, "\n")
  run_loo_test(state, panel, spec)
}) %>%
  bind_rows()

loo_results <- bind_rows(baseline_result, loo_results)

# Calculate improvement from baseline
loo_results <- loo_results %>%
  mutate(
    baseline_f = loo_results$f_stat[loo_results$excluded_state == "BASELINE"],
    f_improvement = baseline_f - f_stat,
    pct_improvement = (f_improvement / baseline_f) * 100
  ) %>%
  arrange(desc(f_improvement))

cat("\n\nLeave-one-out results (sorted by improvement):\n\n")
print(loo_results, n = 25)

# Top improvers
cat("\n\nStates whose removal most improves pre-trends:\n")
loo_results %>%
  filter(excluded_state != "BASELINE") %>%
  arrange(desc(f_improvement)) %>%
  head(10) %>%
  dplyr::select(excluded_state, f_stat, f_p, f_improvement, pct_improvement) %>%
  print()

# -----------------------------------------------------------------------------
# 4. Correlation Between Pre-Trends and Treatment Timing
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("-", 80), "\n")
cat("Correlation between pre-trends and treatment timing...\n")
cat(strrep("-", 80), "\n\n")

# Merge state trends with treatment dates
treatment_timing <- panel %>%
  filter(!is.na(g) & g > 0) %>%
  group_by(state_abb) %>%
  summarise(
    treatment_year = min(as.integer(format(month_date[g > 0], "%Y"))),
    treatment_date = min(month_date[g > 0]),
    .groups = "drop"
  )

trend_timing <- state_trends %>%
  left_join(treatment_timing, by = "state_abb") %>%
  filter(!is.na(slope) & !is.na(treatment_year))

# Correlation
cor_test <- cor.test(trend_timing$slope, trend_timing$treatment_year)

cat("Correlation between pre-trend slope and treatment year:\n")
cat("  r = ", round(cor_test$estimate, 3), "\n")
cat("  p = ", format.pval(cor_test$p.value, digits = 3), "\n")
cat("  Interpretation: ",
    if(cor_test$p.value < 0.05) "Significant" else "Not significant", "\n\n")

# Plot
p_timing <- ggplot(trend_timing, aes(x = treatment_year, y = slope)) +
  geom_point(size = 3, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "red") +
  geom_text(aes(label = state_abb), vjust = -0.5, size = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(
    title = "Pre-Treatment Trends vs. Treatment Timing",
    x = "Treatment Year",
    y = "Pre-Treatment Slope (log evictions on months)",
    caption = glue("Correlation: r = {round(cor_test$estimate, 3)}, p = {format.pval(cor_test$p.value, digits=2)}")
  ) +
  theme_minimal()

ggsave("pretrends_modern_out/problematic_units_timing.png", p_timing,
       width = 10, height = 6, dpi = 300)

# -----------------------------------------------------------------------------
# 5. Pre-Treatment Outcome Levels
# -----------------------------------------------------------------------------

cat(strrep("-", 80), "\n")
cat("Pre-treatment outcome levels...\n")
cat(strrep("-", 80), "\n\n")

# Average outcome in pre-period for each state
pre_levels <- panel %>%
  filter(e < 0 & e >= -12) %>%  # 12 months before treatment
  group_by(state_abb) %>%
  summarise(
    treated = max(g, na.rm = TRUE) > 0,
    mean_y_pre = mean(y, na.rm = TRUE),
    sd_y_pre = sd(y, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  )

# Compare treated vs never-treated
cat("Pre-treatment outcome levels:\n\n")
pre_levels %>%
  group_by(treated) %>%
  summarise(
    n_states = n(),
    mean_y = mean(mean_y_pre, na.rm = TRUE),
    sd_y = sd(mean_y_pre, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  print()

# T-test
t_test <- t.test(
  mean_y_pre ~ treated,
  data = pre_levels
)

cat("\nT-test (treated vs never-treated):\n")
cat("  t = ", round(t_test$statistic, 3), "\n")
cat("  p = ", format.pval(t_test$p.value, digits = 3), "\n")
cat("  Mean difference: ", round(t_test$estimate[2] - t_test$estimate[1], 3), "\n\n")

# -----------------------------------------------------------------------------
# 6. Decompose Variance in Pre-Trends
# -----------------------------------------------------------------------------

cat(strrep("-", 80), "\n")
cat("Variance decomposition of pre-treatment coefficients...\n")
cat(strrep("-", 80), "\n\n")

# Run full TWFE
event_times <- seq(spec$min_e, spec$max_e)
event_times <- event_times[event_times != -1]

for (et in event_times) {
  panel[[paste0("lead_", et)]] <- as.integer(panel$e == et)
}

lead_terms <- paste0("lead_", event_times)
formula_str <- paste0("y ~ ", paste(lead_terms, collapse = " + "), " | id + t")

mod_full <- feols(as.formula(formula_str), data = panel, cluster = ~id)

# Extract coefficients
all_coefs <- coef(mod_full)
pre_coefs <- all_coefs[grepl("lead_-", names(all_coefs))]

cat("Pre-treatment coefficients:\n")
cat("  Mean: ", round(mean(pre_coefs), 4), "\n")
cat("  SD: ", round(sd(pre_coefs), 4), "\n")
cat("  Min: ", round(min(pre_coefs), 4), "\n")
cat("  Max: ", round(max(pre_coefs), 4), "\n")
cat("  Range: ", round(max(pre_coefs) - min(pre_coefs), 4), "\n\n")

# Which event times have largest violations?
pre_coef_df <- tibble(
  event_time = as.integer(gsub("lead_", "", names(pre_coefs))),
  coefficient = pre_coefs
) %>%
  arrange(desc(abs(coefficient)))

cat("Event times with largest violations:\n")
print(pre_coef_df, n = 10)

# -----------------------------------------------------------------------------
# 7. Save Results
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("Saving results...\n")
cat(strrep("=", 80), "\n\n")

# Save state trends
write_csv(state_trends, "pretrends_modern_out/state_specific_pretrends.csv")
cat("  state_specific_pretrends.csv\n")

# Save LOO results
write_csv(loo_results, "pretrends_modern_out/leave_one_out_results.csv")
cat("  leave_one_out_results.csv\n")

# Save pre-treatment levels
write_csv(pre_levels, "pretrends_modern_out/pretreatment_outcome_levels.csv")
cat("  pretreatment_outcome_levels.csv\n")

# Save timing correlation
write_csv(trend_timing, "pretrends_modern_out/trend_timing_correlation.csv")
cat("  trend_timing_correlation.csv\n")

# -----------------------------------------------------------------------------
# 8. Summary Report
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("SUMMARY\n")
cat(strrep("=", 80), "\n\n")

cat("MOST PROBLEMATIC STATES (by pre-trend slope):\n")
state_trends %>%
  filter(!is.na(slope)) %>%
  arrange(desc(abs(slope))) %>%
  head(5) %>%
  dplyr::select(state_abb, slope, r_squared, n_obs) %>%
  print()

cat("\n\nSTATES WHOSE REMOVAL MOST IMPROVES PRE-TRENDS:\n")
loo_results %>%
  filter(excluded_state != "BASELINE") %>%
  arrange(desc(f_improvement)) %>%
  head(5) %>%
  dplyr::select(excluded_state, f_stat, pct_improvement) %>%
  print()

cat("\n\nCORRELATION WITH TREATMENT TIMING:\n")
cat("  States with worse pre-trends adopt in",
    if(cor_test$estimate > 0) "LATER" else "EARLIER", "years\n")
cat("  r = ", round(cor_test$estimate, 3), ", p = ",
    format.pval(cor_test$p.value, digits = 3), "\n")

cat("\n\nPRE-TREATMENT OUTCOME LEVELS:\n")
cat("  Treated states have",
    if(t_test$estimate[2] > t_test$estimate[1]) "HIGHER" else "LOWER",
    "pre-treatment evictions\n")
cat("  Difference: ", round(t_test$estimate[2] - t_test$estimate[1], 3),
    " (p = ", format.pval(t_test$p.value, digits = 3), ")\n")

cat("\n")
cat(strrep("=", 80), "\n")
cat("Analysis complete!\n")
cat(strrep("=", 80), "\n\n")
