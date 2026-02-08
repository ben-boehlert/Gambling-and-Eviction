#!/usr/bin/env Rscript
################################################################################
# simple_event_study.R
#
# Create simple event study plots from the panel data
# Uses a basic regression approach instead of CS-DiD
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(fixest)

cat("\n")
cat("================================================================================\n")
cat("SIMPLE EVENT STUDY ANALYSIS\n")
cat("================================================================================\n\n")

# Load data
cat("Loading data...\n")
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

# Prepare data
cat("Preparing data...\n")
panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,  # Already a Date
    # Calculate event time in actual months
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),  # Round to nearest month
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0)
  ) %>%
  filter(!is.na(log_evictions))

cat(sprintf("  Total observations: %d\n", nrow(panel_data)))
cat(sprintf("  States: %d\n", n_distinct(panel_data$state_abb)))
cat(sprintf("  Treated states: %d\n", sum(panel_data$treated_ever == 1 & !duplicated(panel_data$state_abb))))
cat(sprintf("  Never-treated states: %d\n\n", sum(panel_data$treated_ever == 0 & !duplicated(panel_data$state_abb))))

# Create event time bins
# Focus on -12 to +24 months window
# Pre-trends: only -12 to -1 (exclude earlier periods with changing cohorts)
# Post-treatment: 0 to +24
cat("Creating event time bins...\n")
cat("  Pre-treatment window: -12 to -1 months (for pre-trends test)\n")
cat("  Post-treatment window: 0 to +24 months\n\n")

panel_data <- panel_data %>%
  mutate(
    event_bin = case_when(
      is.na(event_time) ~ "Never treated",
      event_time < -12 ~ "Exclude",  # Exclude earlier periods
      event_time == -12 ~ "-12",
      event_time == -11 ~ "-11",
      event_time == -10 ~ "-10",
      event_time == -9 ~ "-9",
      event_time == -8 ~ "-8",
      event_time == -7 ~ "-7",
      event_time == -6 ~ "-6",
      event_time == -5 ~ "-5",
      event_time == -4 ~ "-4",
      event_time == -3 ~ "-3",
      event_time == -2 ~ "-2",
      event_time == -1 ~ "-1",  # Reference period
      event_time == 0 ~ "0",
      event_time == 1 ~ "1",
      event_time == 2 ~ "2",
      event_time == 3 ~ "3",
      event_time == 4 ~ "4",
      event_time == 5 ~ "5",
      event_time == 6 ~ "6",
      event_time == 7 ~ "7",
      event_time == 8 ~ "8",
      event_time == 9 ~ "9",
      event_time == 10 ~ "10",
      event_time == 11 ~ "11",
      event_time == 12 ~ "12",
      event_time == 13 ~ "13",
      event_time == 14 ~ "14",
      event_time == 15 ~ "15",
      event_time == 16 ~ "16",
      event_time == 17 ~ "17",
      event_time == 18 ~ "18",
      event_time == 19 ~ "19",
      event_time == 20 ~ "20",
      event_time == 21 ~ "21",
      event_time == 22 ~ "22",
      event_time == 23 ~ "23",
      event_time == 24 ~ "24",
      event_time > 24 ~ "Exclude"  # Exclude later periods
    )
  ) %>%
  filter(event_bin != "Exclude") %>%  # Remove excluded periods
  mutate(event_bin = factor(event_bin, levels = c("Never treated", "-12", "-11", "-10", "-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24")))

# Simple event study regression with state and time fixed effects
cat("Running event study regression...\n")
# Remove reference category (-1) and never treated
panel_reg <- panel_data %>%
  filter(event_bin != "-1") %>%
  mutate(
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m"))
  )

# Estimate with fixest
es_model <- feols(log_evictions ~ event_bin | state_id + year_month,
                  data = panel_reg,
                  cluster = ~state_id)

cat("  Model estimated\n\n")

# Extract coefficients
coefs <- summary(es_model)$coeftable
event_study_results <- data.frame(
  event_bin = rownames(coefs),
  coef = coefs[, "Estimate"],
  se = coefs[, "Std. Error"],
  row.names = NULL
)

# Add reference period
event_study_results <- event_study_results %>%
  filter(grepl("event_bin", event_bin)) %>%
  mutate(
    event_bin = gsub("event_bin", "", event_bin),
    ci_lower = coef - 1.96 * se,
    ci_upper = coef + 1.96 * se
  ) %>%
  bind_rows(data.frame(
    event_bin = "-1",
    coef = 0,
    se = 0,
    ci_lower = 0,
    ci_upper = 0
  )) %>%
  mutate(
    event_time_numeric = as.numeric(event_bin)
  ) %>%
  arrange(event_time_numeric)

# Create output directory
dir.create("output/csdid_pretrends/figures", showWarnings = FALSE, recursive = TRUE)

# Plot event study
cat("Creating event study plot...\n")
p <- ggplot(event_study_results, aes(x = event_time_numeric, y = coef)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.5) +
  geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(aes(shape = event_time_numeric < 0), color = "steelblue", size = 2.5) +
  scale_shape_manual(values = c("TRUE" = 1, "FALSE" = 19),
                     labels = c("Pre-treatment", "Post-treatment"),
                     name = "") +
  labs(
    title = "Event Study: Effect of Gambling Legalization on Evictions",
    subtitle = "Two-way fixed effects regression with state and time fixed effects (12 months pre, 24 months post)",
    x = "Months relative to gambling legalization",
    y = "Effect on log(eviction filings + 1)",
    caption = "95% confidence intervals shown. Standard errors clustered at state level. Reference period: t = -1.\nPre-treatment window restricted to 12 months to avoid changing cohort composition."
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  ) +
  annotate("rect",
           xmin = -12.5,
           xmax = -0.5,
           ymin = -Inf, ymax = Inf,
           alpha = 0.1, fill = "orange") +
  annotate("text",
           x = -6.5,
           y = Inf,
           label = "Pre-treatment window\n(12 months for parallel trends test)",
           vjust = 1.5, hjust = 0.5,
           size = 3, color = "orange4", fontface = "italic")

ggsave("output/csdid_pretrends/figures/event_study.pdf", p,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/figures/event_study.png", p,
       width = 12, height = 7, dpi = 300)

cat("  Saved: event_study.pdf and .png\n\n")

# Pre-trends test (12 months before treatment only)
cat("Testing pre-trends (12-month window: t = -12 to t = -2)...\n")
pre_results <- event_study_results %>%
  filter(event_time_numeric >= -12, event_time_numeric < 0, !is.na(coef), !is.na(se), se > 0)

cat(sprintf("  Number of pre-treatment periods: %d\n", nrow(pre_results)))

# Joint F-test for pre-treatment coefficients
# H0: all pre-treatment coefficients = 0
if (nrow(pre_results) > 0) {
  # Chi-squared test
  chi_sq <- sum((pre_results$coef / pre_results$se)^2, na.rm = TRUE)
  df <- nrow(pre_results)
  p_value <- 1 - pchisq(chi_sq, df)

  if (!is.na(p_value) && !is.nan(p_value)) {
    cat(sprintf("  Joint test: χ²(%d) = %.2f, p = %.4f\n", df, chi_sq, p_value))
    if (p_value >= 0.05) {
      cat("  ✓ Fail to reject H0: Pre-trends not significantly different from zero\n")
      cat("    (Parallel trends assumption supported in 12-month window)\n\n")
    } else {
      cat("  ✗ Reject H0: Pre-trends significantly different from zero\n")
      cat("    (Parallel trends assumption violated in 12-month window)\n\n")
    }
  } else {
    cat("  Note: Could not compute joint test (insufficient pre-treatment periods)\n\n")
  }
} else {
  cat("  Note: No pre-treatment periods available for testing\n\n")
}

# Save results
write.csv(event_study_results, "output/csdid_pretrends/event_study_results.csv",
          row.names = FALSE)
cat("  Saved: event_study_results.csv\n\n")

cat("================================================================================\n")
cat("COMPLETE!\n")
cat("================================================================================\n\n")

cat("Output files:\n")
cat("  • output/csdid_pretrends/figures/event_study.pdf\n")
cat("  • output/csdid_pretrends/figures/event_study.png\n")
cat("  • output/csdid_pretrends/event_study_results.csv\n\n")

cat("View plot:\n")
cat("  open output/csdid_pretrends/figures/event_study.pdf\n\n")
