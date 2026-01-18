#!/usr/bin/env Rscript

# =============================================================================
# Identify Problematic Units for Parallel Trends (Simple Version)
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(glue)
library(lubridate)

cat("\n")
cat(strrep("=", 80), "\n")
cat("Identifying Problematic Units for Parallel Trends\n")
cat(strrep("=", 80), "\n\n")

# Load gambling dates and eviction panel
gambling_dates <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)
panel <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)

# Filter to state-level only and standardize names
panel_state <- panel %>%
  filter(geo_level == "state") %>%
  mutate(
    # Standardize state names to title case
    state_name = tools::toTitleCase(tolower(geo_name)),
    y = log1p(filings_count)
  ) %>%
  dplyr::select(state_name, month_date, filings_count, y)

# Add treatment dates
panel_state <- panel_state %>%
  left_join(
    gambling_dates %>% dplyr::select(state, online_start_date),
    by = c("state_name" = "state")
  ) %>%
  mutate(
    treated = !is.na(online_start_date),
    months_to_treatment = if_else(
      treated,
      as.numeric(difftime(month_date, online_start_date, units = "days")) / 30.44,
      NA_real_
    ),
    treatment_year = if_else(treated, as.integer(format(online_start_date, "%Y")), NA_integer_)
  )

cat("Panel: ", nrow(panel_state), "state-months\n")
cat("Treated states: ", sum(!is.na(panel_state$online_start_date)), "\n")
cat("Never-treated states: ", sum(is.na(panel_state$online_start_date)), "\n\n")

# -----------------------------------------------------------------------------
# 1. State-Specific Pre-Trends
# -----------------------------------------------------------------------------

cat(strrep("-", 80), "\n")
cat("State-specific pre-treatment trends\n")
cat(strrep("-", 80), "\n\n")

# For treated states, estimate pre-trend (12-24 months before treatment)
pre_trends <- panel_state %>%
  filter(treated & months_to_treatment >= -24 & months_to_treatment < 0) %>%
  group_by(state_name) %>%
  do({
    if (nrow(.) >= 3) {
      mod <- lm(y ~ months_to_treatment, data = .)
      tibble(
        slope = coef(mod)[2],
        intercept = coef(mod)[1],
        r_squared = summary(mod)$r.squared,
        n_obs = nrow(.),
        treatment_year = unique(.$treatment_year)
      )
    } else {
      tibble(
        slope = NA_real_,
        intercept = NA_real_,
        r_squared = NA_real_,
        n_obs = nrow(.),
        treatment_year = unique(.$treatment_year)
      )
    }
  }) %>%
  ungroup() %>%
  arrange(desc(abs(slope)))

cat("State-specific pre-trends (slope of log evictions on months before treatment):\n\n")
print(pre_trends, n = 20)

# Top 10 most problematic
cat("\n\nTOP 10 MOST PROBLEMATIC STATES:\n")
pre_trends %>%
  filter(!is.na(slope)) %>%
  mutate(abs_slope = abs(slope)) %>%
  arrange(desc(abs_slope)) %>%
  head(10) %>%
  dplyr::select(state_name, slope, r_squared, treatment_year, n_obs) %>%
  print()

# -----------------------------------------------------------------------------
# 2. Correlation with Treatment Timing
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("-", 80), "\n")
cat("Correlation: Pre-trends vs. Treatment Timing\n")
cat(strrep("-", 80), "\n\n")

trend_timing <- pre_trends %>%
  filter(!is.na(slope) & !is.na(treatment_year))

if (nrow(trend_timing) > 2) {
  cor_test <- cor.test(trend_timing$slope, trend_timing$treatment_year)

  cat("Pearson correlation:\n")
  cat("  r = ", round(cor_test$estimate, 3), "\n")
  cat("  p = ", format.pval(cor_test$p.value, digits = 3), "\n\n")

  if (cor_test$p.value < 0.05) {
    cat("INTERPRETATION: States with",
        if (cor_test$estimate > 0) "POSITIVE" else "NEGATIVE",
        "pre-trends adopted\n")
    cat("               gambling in",
        if (cor_test$estimate > 0) "LATER" else "EARLIER",
        "years (p < 0.05)\n\n")
  } else {
    cat("INTERPRETATION: No significant correlation with treatment timing\n\n")
  }

  # Plot
  p_timing <- ggplot(trend_timing, aes(x = treatment_year, y = slope)) +
    geom_point(aes(size = n_obs), alpha = 0.7) +
    geom_smooth(method = "lm", se = TRUE, color = "red") +
    ggrepel::geom_text_repel(aes(label = state_name), size = 3, max.overlaps = 20) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    labs(
      title = "Pre-Treatment Trends vs. Treatment Year",
      subtitle = glue("r = {round(cor_test$estimate, 3)}, p = {format.pval(cor_test$p.value, digits=3)}"),
      x = "Treatment Year (Online Gambling Legalized)",
      y = "Pre-Treatment Slope\n(Change in log evictions per month)",
      size = "Observations"
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  ggsave("pretrends_modern_out/problematic_units_timing.png", p_timing,
         width = 10, height = 7, dpi = 300)

  cat("Plot saved: pretrends_modern_out/problematic_units_timing.png\n\n")
}

# -----------------------------------------------------------------------------
# 3. Pre-Treatment Outcome Levels
# -----------------------------------------------------------------------------

cat(strrep("-", 80), "\n")
cat("Pre-treatment eviction levels: Treated vs. Never-Treated\n")
cat(strrep("-", 80), "\n\n")

# Average outcome 12 months before treatment (or same period for never-treated)
pre_levels <- panel_state %>%
  group_by(state_name) %>%
  mutate(
    baseline_period = if_else(
      treated,
      month_date >= (online_start_date %m+% months(-12)) & month_date < online_start_date,
      month_date >= as.Date("2017-01-01") & month_date < as.Date("2018-01-01")
    )
  ) %>%
  filter(baseline_period) %>%
  summarise(
    treated = first(treated),
    mean_y = mean(y, na.rm = TRUE),
    sd_y = sd(y, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  )

cat("Pre-treatment outcome levels (log evictions):\n\n")
summary_stats <- pre_levels %>%
  group_by(treated) %>%
  summarise(
    n_states = n(),
    mean_log_evictions = mean(mean_y, na.rm = TRUE),
    sd_log_evictions = sd(mean_y, na.rm = TRUE),
    median_log_evictions = median(mean_y, na.rm = TRUE),
    .groups = "drop"
  )

print(summary_stats)

# T-test
t_test_levels <- t.test(mean_y ~ treated, data = pre_levels)

cat("\n\nT-test (treated vs. never-treated):\n")
cat("  t-statistic = ", round(t_test_levels$statistic, 3), "\n")
cat("  p-value = ", format.pval(t_test_levels$p.value, digits = 3), "\n")
cat("  Mean difference = ", round(diff(t_test_levels$estimate), 3), "\n\n")

if (t_test_levels$p.value < 0.05) {
  cat("INTERPRETATION: Treated states have SIGNIFICANTLY",
      if (diff(t_test_levels$estimate) > 0) "HIGHER" else "LOWER",
      "pre-treatment evictions\n")
} else {
  cat("INTERPRETATION: No significant difference in pre-treatment levels\n")
}

# -----------------------------------------------------------------------------
# 4. Direction of Pre-Trends
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("-", 80), "\n")
cat("Direction of pre-trends\n")
cat(strrep("-", 80), "\n\n")

direction_summary <- pre_trends %>%
  filter(!is.na(slope)) %>%
  mutate(
    direction = case_when(
      slope > 0.01 ~ "Increasing (>0.01)",
      slope < -0.01 ~ "Decreasing (<-0.01)",
      TRUE ~ "Flat (±0.01)"
    )
  ) %>%
  count(direction)

cat("States by pre-trend direction:\n")
print(direction_summary)

# -----------------------------------------------------------------------------
# 5. Save Results
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("Saving results\n")
cat(strrep("=", 80), "\n\n")

write_csv(pre_trends, "pretrends_modern_out/state_specific_pretrends.csv")
cat("  state_specific_pretrends.csv\n")

write_csv(pre_levels, "pretrends_modern_out/pretreatment_outcome_levels.csv")
cat("  pretreatment_outcome_levels.csv\n")

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("SUMMARY\n")
cat(strrep("=", 80), "\n\n")

cat("MOST PROBLEMATIC STATES (steepest pre-trends):\n\n")
pre_trends %>%
  filter(!is.na(slope)) %>%
  arrange(desc(abs(slope))) %>%
  head(5) %>%
  dplyr::select(state_name, slope, r_squared, treatment_year) %>%
  mutate(
    direction = if_else(slope > 0, "Increasing ↗", "Decreasing ↘")
  ) %>%
  print()

cat("\n")
cat(strrep("=", 80), "\n")
cat("Analysis complete!\n")
cat(strrep("=", 80), "\n\n")
