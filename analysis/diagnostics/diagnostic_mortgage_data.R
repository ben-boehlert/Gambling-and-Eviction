#!/usr/bin/env Rscript
################################################################################
# diagnostic_mortgage_data.R
#
# Comprehensive diagnostics for mortgage delinquency pre-trends analysis
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(tidyr)
})

cat("=== Mortgage Data Diagnostics ===\n\n")

# Load data
panel <- readr::read_csv("data/processed/mortgage_treatment_panel.csv", show_col_types = FALSE)

cat("1. DATA STRUCTURE\n")
cat("   Total observations:", nrow(panel), "\n")
cat("   Date range:", as.character(min(panel$month_date)), "to", as.character(max(panel$month_date)), "\n")
cat("   States:", length(unique(panel$state_abb)), "\n\n")

# Treatment assignment
cat("2. TREATMENT ASSIGNMENT\n")
treatment_summary <- panel %>%
  group_by(state_abb, treated) %>%
  summarise(
    n_obs = n(),
    treatment_date = first(treatment_date),
    .groups = "drop"
  ) %>%
  arrange(treated, treatment_date)

cat("   Treated states:", sum(treatment_summary$treated), "\n")
cat("   Control states:", sum(!treatment_summary$treated), "\n\n")

# Show treatment timing
cat("   Treatment timing:\n")
treated_states <- treatment_summary %>%
  filter(treated) %>%
  mutate(year = format(treatment_date, "%Y")) %>%
  group_by(year) %>%
  summarise(n_states = n(), .groups = "drop")
print(treated_states)

# Missing values
cat("\n3. MISSING VALUES\n")
cat("   Missing delinquency_rate:", sum(is.na(panel$delinquency_rate)), "\n")
cat("   Missing log_delinquency_rate:", sum(is.na(panel$log_delinquency_rate)), "\n")
cat("   Non-finite log_delinquency_rate:", sum(!is.finite(panel$log_delinquency_rate)), "\n\n")

# Outcome distribution
cat("4. OUTCOME DISTRIBUTION\n")
cat("   Delinquency rate (%):\n")
print(summary(panel$delinquency_rate))
cat("\n   Log delinquency rate:\n")
print(summary(panel$log_delinquency_rate))

# Check for zero/negative values
cat("\n   Zero delinquency rates:", sum(panel$delinquency_rate == 0, na.rm = TRUE), "\n")
cat("   Negative delinquency rates:", sum(panel$delinquency_rate < 0, na.rm = TRUE), "\n\n")

# Balance check
cat("5. PANEL BALANCE\n")
balance <- panel %>%
  group_by(state_abb) %>%
  summarise(
    n_obs = n(),
    min_date = min(month_date),
    max_date = max(month_date),
    .groups = "drop"
  )

cat("   Observations per state:\n")
print(summary(balance$n_obs))
cat("\n   Unbalanced states:\n")
unbalanced <- balance %>% filter(n_obs != max(balance$n_obs))
if (nrow(unbalanced) > 0) {
  print(unbalanced)
} else {
  cat("   (None - fully balanced panel)\n")
}

# Pre-post treatment periods
cat("\n6. PRE-POST TREATMENT AVAILABILITY\n")
pre_post <- panel %>%
  filter(treated) %>%
  mutate(
    relative_month = as.numeric(difftime(month_date, treatment_date, units = "days")) / 30.44
  ) %>%
  summarise(
    min_pre = min(relative_month[relative_month < 0], na.rm = TRUE),
    max_post = max(relative_month[relative_month >= 0], na.rm = TRUE)
  )

cat("   Min pre-treatment months available:", round(pre_post$min_pre, 1), "\n")
cat("   Max post-treatment months available:", round(pre_post$max_post, 1), "\n\n")

# Visualize trends
cat("7. CREATING TREND VISUALIZATIONS\n")

# Average trends by treatment status
trends <- panel %>%
  mutate(year = format(month_date, "%Y")) %>%
  group_by(year, treated) %>%
  summarise(
    mean_delinq = mean(delinquency_rate, na.rm = TRUE),
    .groups = "drop"
  )

p1 <- ggplot(trends, aes(x = year, y = mean_delinq, group = treated, color = treated)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  labs(
    title = "Average Mortgage Delinquency Rates Over Time",
    subtitle = "By Treatment Status",
    x = "Year",
    y = "Average Delinquency Rate (%)",
    color = "Eventually Treated"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(face = "bold")
  )

ggsave("mortgage_delinquency_out/diagnostics_trends.png", p1, width = 10, height = 6, dpi = 300)
cat("   Saved: mortgage_delinquency_out/diagnostics_trends.png\n")

# Distribution of outcomes
p2 <- ggplot(panel, aes(x = log_delinquency_rate)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
  geom_vline(xintercept = median(panel$log_delinquency_rate, na.rm = TRUE),
             linetype = "dashed", color = "red") +
  labs(
    title = "Distribution of Log Delinquency Rates",
    x = "Log(Delinquency Rate + 0.01)",
    y = "Count"
  ) +
  theme_minimal()

ggsave("mortgage_delinquency_out/diagnostics_distribution.png", p2, width = 8, height = 5, dpi = 300)
cat("   Saved: mortgage_delinquency_out/diagnostics_distribution.png\n")

# State-specific trends
state_trends <- panel %>%
  filter(treated) %>%
  mutate(
    relative_month = as.numeric(difftime(month_date, treatment_date, units = "days")) / 30.44
  ) %>%
  filter(relative_month >= -24, relative_month <= 24)

p3 <- ggplot(state_trends, aes(x = relative_month, y = log_delinquency_rate, group = state_abb)) +
  geom_line(alpha = 0.3, color = "steelblue") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red") +
  stat_summary(aes(group = 1), fun = mean, geom = "line",
               color = "darkblue", linewidth = 1.5) +
  labs(
    title = "Individual State Trajectories (Treated States)",
    subtitle = "Light lines = individual states, Dark line = average",
    x = "Months Relative to Online Gambling Legalization",
    y = "Log(Delinquency Rate + 0.01)"
  ) +
  theme_minimal()

ggsave("mortgage_delinquency_out/diagnostics_state_trajectories.png", p3, width = 10, height = 6, dpi = 300)
cat("   Saved: mortgage_delinquency_out/diagnostics_state_trajectories.png\n")

cat("\n8. POTENTIAL ISSUES IDENTIFIED\n")

issues <- list()

# Check for extreme F-stats (indicating issues)
if (file.exists("mortgage_delinquency_out/comparison/pretrends_summary.csv")) {
  pretrends <- readr::read_csv("mortgage_delinquency_out/comparison/pretrends_summary.csv",
                               show_col_types = FALSE)

  extreme_f <- pretrends %>% filter(f_stat > 1000)
  if (nrow(extreme_f) > 0) {
    issues <- c(issues, "Very large F-statistics suggest strong pre-trends violations")
  }

  most_pass <- pretrends %>% filter(p_value > 0.05)
  if (nrow(most_pass) < nrow(pretrends) / 2) {
    issues <- c(issues, "Most specifications fail pre-trends test")
  }
}

# Check for treatment effect heterogeneity
treatment_year_effects <- panel %>%
  filter(treated) %>%
  mutate(
    treatment_year = format(treatment_date, "%Y"),
    post = month_date >= treatment_date
  ) %>%
  group_by(treatment_year, post) %>%
  summarise(
    mean_delinq = mean(delinquency_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = post, values_from = mean_delinq, names_prefix = "post_") %>%
  mutate(diff = post_TRUE - post_FALSE)

if (sd(treatment_year_effects$diff, na.rm = TRUE) > mean(treatment_year_effects$diff, na.rm = TRUE)) {
  issues <- c(issues, "High heterogeneity in treatment effects across cohorts")
}

if (length(issues) > 0) {
  for (i in seq_along(issues)) {
    cat("   [!]", issues[[i]], "\n")
  }
} else {
  cat("   No major issues detected\n")
}

cat("\n=== Diagnostics Complete ===\n")
