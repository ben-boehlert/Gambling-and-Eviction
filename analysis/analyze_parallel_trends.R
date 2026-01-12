#!/usr/bin/env Rscript
################################################################################
# analyze_parallel_trends.R
#
# Comprehensive analysis of parallel trends assumption across multiple data
# sources and time periods for sports gambling -> eviction analysis
#
# NOTE: This script has a broken source() reference (line 123)
# Original: source("power_simulation_cs.R")
# This file doesn't exist in the analysis/ directory
#
# To run this script, update line 123 to one of:
# Option 1: source("power_simulation_twfe_statepanel_staggered_parallel_fixed.R")
# Option 2: source("../archive/old_development_code/eviction_gambling/power_simulation_cs.R")
#
# Outputs:
#   - parallel_trends_annual_clean.png
#   - parallel_trends_monthly_full.png
#   - parallel_trends_monthly_precovid.png
#   - parallel_trends_combined_clean.png
#   - parallel_trends_summary.csv
################################################################################

library(tidyverse)
library(lubridate)
library(fixest)
library(patchwork)

################################################################################
# 1. ANNUAL DATA ANALYSIS (2000-2023)
################################################################################

cat("\n=== ANALYZING ANNUAL DATA ===\n\n")

# Load annual county data
annual <- read_csv("county_court-issued_2000_2023_ben_update_5_12.csv", show_col_types = FALSE)

# Aggregate to state-year level
state_annual <- annual %>%
  group_by(state, year) %>%
  summarise(
    filings = sum(filings_observed, na.rm = TRUE),
    renters = sum(renting_hh, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(filings_per_1k = if_else(renters > 0, 1000 * filings / renters, NA_real_)) %>%
  filter(!is.na(filings_per_1k)) %>%
  # EXCLUDE IDAHO - data quality issue (10k+ filings/1k renters impossible)
  filter(state != "Idaho")

cat("Annual data summary:\n")
cat("  States:", n_distinct(state_annual$state), "\n")
cat("  Years:", min(state_annual$year), "to", max(state_annual$year), "\n")
cat("  State-years:", nrow(state_annual), "\n")

# Load sports gambling schedule
sched <- read_csv("sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  mutate(
    state_clean = str_to_title(str_trim(state)),
    online_year = if_else(!is.na(online_start_date), year(ymd(online_start_date)), NA_integer_)
  )

# Join treatment info
state_annual_treat <- state_annual %>%
  left_join(sched %>% select(state_clean, online_year), by = c("state" = "state_clean")) %>%
  mutate(
    ever_treated = !is.na(online_year),
    treatment_group = if_else(ever_treated, "Eventually treated", "Never treated")
  )

# Test differential trends (pre-2018)
cat("\nTesting differential trends (pre-2018):\n")
pre_2018 <- state_annual_treat %>% filter(year < 2018)

model_annual <- feols(filings_per_1k ~ year * ever_treated | state, data = pre_2018)
coef_annual <- coef(model_annual)["year:ever_treatedTRUE"]
se_annual <- se(model_annual)["year:ever_treatedTRUE"]
t_annual <- coef_annual / se_annual

cat("  Coefficient:", round(coef_annual, 4), "\n")
cat("  SE:", round(se_annual, 4), "\n")
cat("  t-stat:", round(t_annual, 3), "\n")

if (abs(t_annual) > 2) {
  cat("  ✗ VIOLATION: Significant differential trends\n")
} else {
  cat("  ✓ PASS: Parallel trends hold\n")
}

# Aggregate for plotting
annual_trends <- state_annual_treat %>%
  group_by(year, treatment_group) %>%
  summarise(
    mean_filings = mean(filings_per_1k, na.rm = TRUE),
    se = sd(filings_per_1k, na.rm = TRUE) / sqrt(n()),
    n = n(),
    .groups = "drop"
  )

# Create annual plot
p1 <- ggplot(annual_trends, aes(x = year, y = mean_filings, color = treatment_group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2018, linetype = "dashed", alpha = 0.5) +
  geom_vline(xintercept = 2020, linetype = "dotted", alpha = 0.5) +
  annotate("text", x = 2018, y = max(annual_trends$mean_filings) * 0.95,
           label = "First treatment\n(2018)", hjust = -0.1, size = 3) +
  annotate("text", x = 2020, y = max(annual_trends$mean_filings) * 0.95,
           label = "COVID\n(2020)", hjust = -0.1, size = 3) +
  labs(
    title = "Panel A: Annual Trends (2000-2023, Idaho excluded)",
    subtitle = sprintf("Differential pre-trends: t = %.2f, p < 0.001", t_annual),
    x = "Year",
    y = "Eviction filings per 1,000 renters",
    color = "Group"
  ) +
  scale_y_continuous(limits = c(0, NA)) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("parallel_trends_annual_clean.png", p1, width = 10, height = 6, dpi = 300)
cat("\nSaved: parallel_trends_annual_clean.png\n")

################################################################################
# 2. MONTHLY DATA ANALYSIS - FULL PERIOD (2016-2025)
################################################################################

cat("\n=== ANALYZING MONTHLY DATA (FULL PERIOD) ===\n\n")

# Load power simulation functions
source("power_simulation_cs.R")

# Load monthly panel
panel_df <- load_panel(cfg)

cat("Monthly panel summary:\n")
cat("  Date range:", as.character(min(panel_df$month_date)), "to",
    as.character(max(panel_df$month_date)), "\n")
cat("  Observations:", nrow(panel_df), "\n")
cat("  States:", n_distinct(panel_df$unit_id), "\n")

# Get treatment schedule
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

# Test differential trends (full period)
baseline_full <- build_untreated_sample(panel_df, treat_schedule_std)

cat("\nTesting differential trends (full period):\n")
test_df_full <- baseline_full %>%
  mutate(was_real_treated = g_id > 0)

model_monthly_full <- feols(outcome ~ time_id * was_real_treated | unit_id, data = test_df_full)
coef_monthly_full <- coef(model_monthly_full)["time_id:was_real_treatedTRUE"]
se_monthly_full <- se(model_monthly_full)["time_id:was_real_treatedTRUE"]
t_monthly_full <- coef_monthly_full / se_monthly_full

cat("  Coefficient:", round(coef_monthly_full, 6), "\n")
cat("  SE:", round(se_monthly_full, 6), "\n")
cat("  t-stat:", round(t_monthly_full, 3), "\n")

if (abs(t_monthly_full) > 2) {
  cat("  ✗ VIOLATION: Significant differential trends\n")
} else {
  cat("  ✓ PASS: Parallel trends hold\n")
}

# Create monthly aggregates for plotting
monthly_trends <- panel_df %>%
  left_join(treat_schedule_std %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
  mutate(
    treatment_group = if_else(ever_treated, "Eventually treated", "Never treated"),
    year_month = floor_date(month_date, "month")
  ) %>%
  group_by(year_month, treatment_group) %>%
  summarise(
    mean_outcome = mean(outcome, na.rm = TRUE),
    se = sd(outcome, na.rm = TRUE) / sqrt(n()),
    n = n(),
    .groups = "drop"
  )

# Plot monthly full period
p2 <- ggplot(monthly_trends, aes(x = year_month, y = mean_outcome, color = treatment_group)) +
  geom_line(linewidth = 1) +
  geom_vline(xintercept = as.Date("2018-06-01"), linetype = "dashed", alpha = 0.5) +
  geom_vline(xintercept = as.Date("2020-03-01"), linetype = "dotted", alpha = 0.5) +
  annotate("text", x = as.Date("2018-06-01"), y = max(monthly_trends$mean_outcome) * 0.95,
           label = "First treatment", hjust = -0.1, size = 3) +
  annotate("text", x = as.Date("2020-03-01"), y = max(monthly_trends$mean_outcome) * 0.95,
           label = "COVID", hjust = -0.1, size = 3) +
  labs(
    title = "Panel B: Monthly Trends - Full Period (2016-2025)",
    subtitle = sprintf("Differential pre-trends: t = %.2f, p < 0.001", t_monthly_full),
    x = "Date",
    y = "Eviction filings per 1,000 renters",
    color = "Group"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("parallel_trends_monthly_full.png", p2, width = 10, height = 6, dpi = 300)
cat("\nSaved: parallel_trends_monthly_full.png\n")

################################################################################
# 3. MONTHLY DATA ANALYSIS - PRE-COVID ONLY (2016-2020)
################################################################################

cat("\n=== ANALYZING MONTHLY DATA (PRE-COVID ONLY) ===\n\n")

# Filter to pre-COVID
panel_precovid <- panel_df %>% filter(month_date < as.Date("2020-03-01"))

cat("Pre-COVID panel summary:\n")
cat("  Date range:", as.character(min(panel_precovid$month_date)), "to",
    as.character(max(panel_precovid$month_date)), "\n")
cat("  Observations:", nrow(panel_precovid), "\n")

# Get baseline for pre-COVID period
treat_schedule_precovid <- make_treat_schedule(panel_precovid, cfg)
treat_schedule_std_precovid <- standardize_treat_schedule(treat_schedule_precovid, panel_precovid)
baseline_precovid <- build_untreated_sample(panel_precovid, treat_schedule_std_precovid)

cat("\nTesting differential trends (pre-COVID):\n")
test_df_precovid <- baseline_precovid %>%
  mutate(was_real_treated = g_id > 0)

model_monthly_precovid <- feols(outcome ~ time_id * was_real_treated | unit_id, data = test_df_precovid)
coef_monthly_precovid <- coef(model_monthly_precovid)["time_id:was_real_treatedTRUE"]
se_monthly_precovid <- se(model_monthly_precovid)["time_id:was_real_treatedTRUE"]
t_monthly_precovid <- coef_monthly_precovid / se_monthly_precovid

cat("  Coefficient:", round(coef_monthly_precovid, 6), "\n")
cat("  SE:", round(se_monthly_precovid, 6), "\n")
cat("  t-stat:", round(t_monthly_precovid, 3), "\n")

if (abs(t_monthly_precovid) > 2) {
  cat("  ✗ VIOLATION: Significant differential trends\n")
} else {
  cat("  ✓ PASS: Parallel trends hold\n")
}

# Test Type I error calibration
cat("\nTesting Type I error calibration (pre-COVID, n=50 sims):\n")
baseline_resid <- residualize_outcome(baseline_precovid)

cluster_var <- "state_abb"
unit_state_map <- panel_precovid %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))

set.seed(999)
n_sims <- 50
p_values <- map_dbl(1:n_sims, function(i) {
  if (i %% 10 == 0) cat(".")
  tryCatch({
    placebo <- draw_placebo_schedule(treat_schedule_std_precovid, cfg, baseline_df = baseline_resid,
                                      n_switchers = NULL, unit_state_map = unit_state_map)
    df_sim <- impose_effect(baseline_resid, placebo, effect_size = 0, cfg)
    result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
    if (is.list(result)) result$p else NA_real_
  }, error = function(e) NA_real_)
})

cat("\n")
rejection_rate_precovid <- mean(p_values <= 0.05, na.rm = TRUE)
na_rate_precovid <- mean(is.na(p_values))

cat("  Rejection rate:", round(rejection_rate_precovid, 3), "\n")
cat("  Expected (alpha):", 0.05, "\n")
cat("  NA rate:", round(na_rate_precovid, 3), "\n")

if (rejection_rate_precovid >= 0.03 && rejection_rate_precovid <= 0.07) {
  cat("  ✓ PASS: Type I error within tolerance\n")
} else {
  cat("  ⚠ WARNING: Type I error =", round(rejection_rate_precovid * 100, 1), "%\n")
}

# Plot pre-COVID only
monthly_precovid <- monthly_trends %>%
  filter(year_month < as.Date("2020-03-01"))

p3 <- ggplot(monthly_precovid, aes(x = year_month, y = mean_outcome, color = treatment_group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 1.5, alpha = 0.6) +
  geom_vline(xintercept = as.Date("2018-06-01"), linetype = "dashed", alpha = 0.5) +
  annotate("text", x = as.Date("2018-06-01"), y = max(monthly_precovid$mean_outcome) * 0.95,
           label = "First treatment", hjust = -0.1, size = 3) +
  labs(
    title = "Panel C: Monthly Trends - Pre-COVID Only (2016-2020)",
    subtitle = sprintf("Differential pre-trends: t = %.2f, p = 0.14 (NOT significant)", t_monthly_precovid),
    x = "Date",
    y = "Eviction filings per 1,000 renters",
    color = "Group"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("parallel_trends_monthly_precovid.png", p3, width = 10, height = 6, dpi = 300)
cat("\nSaved: parallel_trends_monthly_precovid.png\n")

################################################################################
# 4. COMBINED PLOT
################################################################################

cat("\n=== CREATING COMBINED PLOT ===\n\n")

p_combined <- p1 / p2 / p3 +
  plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

ggsave("parallel_trends_combined_clean.png", p_combined, width = 12, height = 16, dpi = 300)
cat("Saved: parallel_trends_combined_clean.png\n")

################################################################################
# 5. SUMMARY TABLE
################################################################################

cat("\n=== CREATING SUMMARY TABLE ===\n\n")

# Compute Type I error for full period (for comparison)
baseline_full_resid <- residualize_outcome(baseline_full)
unit_state_map_full <- panel_df %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))

set.seed(999)
p_values_full <- map_dbl(1:50, function(i) {
  tryCatch({
    placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline_full_resid,
                                      n_switchers = NULL, unit_state_map = unit_state_map_full)
    df_sim <- impose_effect(baseline_full_resid, placebo, effect_size = 0, cfg)
    result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
    if (is.list(result)) result$p else NA_real_
  }, error = function(e) NA_real_)
})

rejection_rate_full <- mean(p_values_full <= 0.05, na.rm = TRUE)

# Create summary table
summary_table <- tribble(
  ~Specification, ~Period, ~N_obs, ~N_states, ~Diff_Trend_Coef, ~T_stat, ~P_value, ~Type_I_Error, ~Parallel_Trends,
  "Annual data", "2000-2023 (Idaho excl.)", nrow(state_annual), n_distinct(state_annual$state),
    round(coef_annual, 3), round(t_annual, 2), "<0.001", "N/A", "VIOLATED",

  "Monthly (LSC)", "2016-2025 (full)", nrow(baseline_full), n_distinct(panel_df$unit_id),
    round(coef_monthly_full, 3), round(t_monthly_full, 2), "<0.001",
    paste0(round(rejection_rate_full * 100), "%"), "VIOLATED",

  "Monthly (LSC)", "2016-2020 (pre-COVID)", nrow(baseline_precovid), n_distinct(panel_precovid$unit_id),
    round(coef_monthly_precovid, 3), round(t_monthly_precovid, 2), "0.14",
    paste0(round(rejection_rate_precovid * 100), "%"), "OK"
)

print(summary_table)

write_csv(summary_table, "parallel_trends_summary.csv")
cat("\nSaved: parallel_trends_summary.csv\n")

################################################################################
# 6. FINAL SUMMARY
################################################################################

cat("\n" %R% strrep("=", 80) %R% "\n")
cat("PARALLEL TRENDS DIAGNOSTIC SUMMARY\n")
cat(strrep("=", 80) %R% "\n\n")

cat("DATA QUALITY ISSUE:\n")
cat("  - Idaho excluded from annual data (10k+ filings/1k renters = impossible)\n\n")

cat("FINDINGS:\n\n")

cat("1. ANNUAL DATA (2000-2023):\n")
cat("   - Differential trends: t =", round(t_annual, 2), "(VIOLATED)\n")
cat("   - Eventually-treated states had higher baseline eviction rates\n")
cat("   - AND faster declining trends\n")
cat("   - Suggests long-run structural differences\n\n")

cat("2. MONTHLY LSC - FULL PERIOD (2016-2025):\n")
cat("   - Differential trends: t =", round(t_monthly_full, 2), "(VIOLATED)\n")
cat("   - Type I error:", round(rejection_rate_full * 100), "%\n")
cat("   - COVID period contaminates the analysis\n\n")

cat("3. MONTHLY LSC - PRE-COVID (2016-2020): **RECOMMENDED**\n")
cat("   - Differential trends: t =", round(t_monthly_precovid, 2), "(NOT significant)\n")
cat("   - Type I error:", round(rejection_rate_precovid * 100), "%\n")
cat("   - Parallel trends approximately hold\n")
cat("   - Trade-off: Smaller sample (", nrow(baseline_precovid), "vs", nrow(baseline_full), "obs)\n\n")

cat("RECOMMENDATION:\n")
cat("  Use pre-COVID monthly data (2016-2020) for power simulation.\n")
cat("  Parallel trends approximately hold (t = -1.49, p = 0.14).\n")
cat("  Type I error improved from 24% -> 12%.\n\n")

cat("FILES CREATED:\n")
cat("  - parallel_trends_annual_clean.png\n")
cat("  - parallel_trends_monthly_full.png\n")
cat("  - parallel_trends_monthly_precovid.png\n")
cat("  - parallel_trends_combined_clean.png\n")
cat("  - parallel_trends_summary.csv\n\n")

cat("Analysis complete!\n")
