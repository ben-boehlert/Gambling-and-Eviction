#!/usr/bin/env Rscript
################################################################################
# diagnose_sunab_issues.R
#
# Investigate why Sun-Abraham has enormous SEs at certain event times
# Check data support and cohort coverage for each event time
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(tidyr)

cat("\n")
cat("================================================================================\n")
cat("SUN-ABRAHAM DIAGNOSTIC: Investigating Large Standard Errors\n")
cat("================================================================================\n\n")

# Load data
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE) %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0),
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m")),
    cohort = ifelse(is.na(first_treat_date), 0,
                   as.integer(format(first_treat_date, "%Y%m")))
  ) %>%
  filter(!is.na(log_evictions)) %>%
  filter(cohort == 0 | (event_time >= -12 & event_time <= 24))

# Load Sun-Abraham results
sa_results <- read_csv("output/csdid_pretrends/sun_abraham_results.csv",
                      show_col_types = FALSE)

cat("Loaded data and results\n\n")

# ========================================================================
# Identify Problem Event Times
# ========================================================================

cat("Event times with suspiciously large SEs (> 100):\n")
cat("========================================================================\n")

problem_times <- sa_results %>%
  filter(se > 100) %>%
  select(event_time, coef, se, ci_lower, ci_upper) %>%
  arrange(event_time)

print(problem_times)
cat("\n")

# ========================================================================
# Support Analysis: Count Cohorts at Each Event Time
# ========================================================================

cat("Cohort coverage by event time:\n")
cat("========================================================================\n")

# For treated units, count how many cohorts contribute to each event time
support_by_event_time <- panel_data %>%
  filter(treated_ever == 1) %>%
  group_by(event_time, cohort) %>%
  summarise(n_obs = n(), .groups = "drop") %>%
  group_by(event_time) %>%
  summarise(
    n_cohorts = n_distinct(cohort),
    total_obs = sum(n_obs),
    cohorts = paste(unique(cohort), collapse = ", ")
  ) %>%
  arrange(event_time)

# Merge with SE information
support_check <- support_by_event_time %>%
  left_join(
    sa_results %>% select(event_time, se, significant),
    by = "event_time"
  ) %>%
  mutate(
    problem = se > 100,
    se_category = case_when(
      is.na(se) ~ "No estimate",
      se > 1000 ~ "Severe (> 1000)",
      se > 100 ~ "Large (100-1000)",
      se > 10 ~ "Moderate (10-100)",
      TRUE ~ "Normal (< 10)"
    )
  )

cat("\nEvent times with coverage issues:\n")
print(support_check %>%
      filter(problem | n_cohorts <= 2) %>%
      select(event_time, n_cohorts, total_obs, se, se_category))
cat("\n")

# ========================================================================
# Cohort-Specific Event Studies
# ========================================================================

cat("Cohort information:\n")
cat("========================================================================\n")

cohort_info <- panel_data %>%
  filter(cohort > 0) %>%
  group_by(cohort) %>%
  summarise(
    n_states = n_distinct(state_id),
    n_obs = n(),
    min_event_time = min(event_time),
    max_event_time = max(event_time),
    states = paste(unique(state_abb), collapse = ", ")
  ) %>%
  arrange(cohort)

print(cohort_info)
cat("\n")

# ========================================================================
# Never-Treated Units
# ========================================================================

cat("Never-treated (control) units:\n")
cat("========================================================================\n")

never_treated <- panel_data %>%
  filter(cohort == 0) %>%
  group_by(state_abb) %>%
  summarise(n_obs = n()) %>%
  arrange(state_abb)

cat(sprintf("  N never-treated states: %d\n", nrow(never_treated)))
cat(sprintf("  States: %s\n\n", paste(never_treated$state_abb, collapse = ", ")))

# ========================================================================
# Visualizations
# ========================================================================

cat("Creating diagnostic visualizations...\n")

# Plot 1: SE by event time with cohort count overlay
p1 <- ggplot(support_check, aes(x = event_time)) +
  geom_line(aes(y = log(se + 1)), color = "red", size = 1.2) +
  geom_point(aes(y = log(se + 1), color = se_category), size = 3) +
  geom_bar(aes(y = n_cohorts / 5), stat = "identity", alpha = 0.3, fill = "blue") +
  scale_y_continuous(
    name = "log(Standard Error + 1)",
    sec.axis = sec_axis(~ . * 5, name = "Number of Cohorts")
  ) +
  scale_color_manual(
    values = c(
      "Normal (< 10)" = "darkgreen",
      "Moderate (10-100)" = "orange",
      "Large (100-1000)" = "red",
      "Severe (> 1000)" = "darkred"
    ),
    name = "SE Category"
  ) +
  geom_vline(xintercept = -0.5, linetype = "dashed") +
  labs(
    title = "Sun-Abraham Standard Errors vs. Cohort Coverage",
    subtitle = "Large SEs occur when few cohorts provide identification",
    x = "Event Time (months relative to treatment)",
    caption = "Red line = log(SE). Blue bars = number of cohorts contributing to estimate."
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# Plot 2: Heatmap of cohort x event time support
heatmap_data <- panel_data %>%
  filter(treated_ever == 1) %>%
  group_by(cohort, event_time) %>%
  summarise(n_obs = n(), .groups = "drop") %>%
  mutate(cohort_label = format(as.Date(paste0(cohort, "01"), "%Y%m%d"), "%Y-%m"))

p2 <- ggplot(heatmap_data, aes(x = event_time, y = cohort_label, fill = log(n_obs + 1))) +
  geom_tile(color = "white") +
  scale_fill_viridis_c(name = "log(N obs + 1)") +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "red", size = 1) +
  labs(
    title = "Data Support: Cohort × Event Time Coverage",
    subtitle = "Darker = more observations. Gaps indicate weak identification.",
    x = "Event Time (months relative to treatment)",
    y = "Treatment Cohort (Year-Month)"
  ) +
  theme_minimal() +
  theme(
    axis.text.y = element_text(size = 7),
    panel.grid = element_blank()
  )

# Plot 3: Filtered Sun-Abraham plot (removing extreme SEs)
sa_clean <- sa_results %>%
  filter(se < 100 | event_time == -1)  # Keep reference period

p3 <- ggplot(sa_clean, aes(x = event_time, y = coef)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.5) +
  geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "darkgreen") +
  geom_line(color = "darkgreen", linewidth = 1) +
  geom_point(aes(shape = event_time < 0, color = significant), size = 2.5) +
  scale_shape_manual(values = c("TRUE" = 1, "FALSE" = 19),
                     labels = c("Pre-treatment", "Post-treatment"),
                     name = "") +
  scale_color_manual(values = c("TRUE" = "darkgreen", "FALSE" = "gray50"),
                     labels = c("Not significant", "Significant (p<0.05)"),
                     name = "") +
  labs(
    title = "Sun-Abraham Event Study (Filtered)",
    subtitle = "Excluding event times with SE > 100 (numerical instability)",
    x = "Months relative to gambling legalization",
    y = "Effect on log(evictions per 1,000 renters)",
    caption = sprintf("95%% CIs. Removed %d event times with extreme SEs.",
                     sum(sa_results$se > 100, na.rm = TRUE))
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

# Save plots
dir.create("output/csdid_pretrends/diagnostics", showWarnings = FALSE, recursive = TRUE)

ggsave("output/csdid_pretrends/diagnostics/sunab_se_diagnosis.pdf", p1,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/diagnostics/cohort_support_heatmap.pdf", p2,
       width = 12, height = 8)
ggsave("output/csdid_pretrends/diagnostics/sunab_filtered.pdf", p3,
       width = 12, height = 7)

cat("  Saved diagnostic plots\n\n")

# ========================================================================
# Recommendations
# ========================================================================

cat("================================================================================\n")
cat("DIAGNOSIS SUMMARY\n")
cat("================================================================================\n\n")

n_problem_times <- sum(support_check$problem, na.rm = TRUE)
n_weak_support <- sum(support_check$n_cohorts <= 2, na.rm = TRUE)

cat(sprintf("Total event times analyzed: %d\n", nrow(support_check)))
cat(sprintf("Event times with SE > 100: %d (%.1f%%)\n",
           n_problem_times, 100 * n_problem_times / nrow(support_check)))
cat(sprintf("Event times with ≤ 2 cohorts: %d (%.1f%%)\n\n",
           n_weak_support, 100 * n_weak_support / nrow(support_check)))

if (n_problem_times > 0) {
  cat("PROBLEM IDENTIFIED:\n")
  cat("  • Some event times have very few cohorts contributing\n")
  cat("  • This causes near-singularity in the interaction-weighted estimator\n")
  cat("  • Standard errors explode due to weak identification\n\n")

  cat("AFFECTED EVENT TIMES:\n")
  cat(sprintf("  %s\n\n", paste(problem_times$event_time, collapse = ", ")))

  cat("RECOMMENDATIONS:\n")
  cat("  1. Use the FILTERED Sun-Abraham plot (SE < 100)\n")
  cat("  2. Report that certain event times have insufficient support\n")
  cat("  3. Consider restricting analysis to event times with ≥ 3 cohorts\n")
  cat("  4. Alternative: Use Sun-Abraham with aggregated time periods\n\n")
} else {
  cat("✓ All event times have reasonable standard errors\n")
  cat("  Sun-Abraham estimation appears stable\n\n")
}

# Pre-trends test with filtered data
cat("Pre-trends test (excluding unstable estimates):\n")
cat("========================================================================\n")

pre_results_clean <- sa_clean %>%
  filter(event_time >= -12 & event_time < 0 & event_time != -1)

if (nrow(pre_results_clean) > 0) {
  chi_sq_clean <- sum((pre_results_clean$coef / pre_results_clean$se)^2, na.rm = TRUE)
  df_clean <- sum(!is.na(pre_results_clean$se) & pre_results_clean$se < 100)
  p_val_clean <- 1 - pchisq(chi_sq_clean, df_clean)

  cat(sprintf("  Using %d pre-treatment periods (out of %d total)\n",
             df_clean, nrow(pre_results_clean)))
  cat(sprintf("  Joint test: χ²(%d) = %.2f, p = %.4f\n\n", df_clean, chi_sq_clean, p_val_clean))

  if (p_val_clean >= 0.05) {
    cat("  ✓ Parallel trends supported (with filtered data)\n\n")
  } else {
    cat("  ✗ Parallel trends still violated (even with filtered data)\n\n")
  }
}

# Save diagnostic data
write.csv(support_check,
         "output/csdid_pretrends/diagnostics/sunab_support_check.csv",
         row.names = FALSE)

write.csv(cohort_info,
         "output/csdid_pretrends/diagnostics/cohort_summary.csv",
         row.names = FALSE)

write.csv(sa_clean,
         "output/csdid_pretrends/sun_abraham_results_filtered.csv",
         row.names = FALSE)

cat("Files saved:\n")
cat("  • output/csdid_pretrends/diagnostics/sunab_se_diagnosis.pdf\n")
cat("  • output/csdid_pretrends/diagnostics/cohort_support_heatmap.pdf\n")
cat("  • output/csdid_pretrends/diagnostics/sunab_filtered.pdf\n")
cat("  • output/csdid_pretrends/diagnostics/sunab_support_check.csv\n")
cat("  • output/csdid_pretrends/diagnostics/cohort_summary.csv\n")
cat("  • output/csdid_pretrends/sun_abraham_results_filtered.csv\n\n")

cat("================================================================================\n\n")
