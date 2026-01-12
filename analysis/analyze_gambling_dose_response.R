#!/usr/bin/env Rscript
################################################################################
# analyze_gambling_dose_response.R
# Explore dose-response: Does gambling VOLUME predict eviction changes?
#
# NOTE: This script has a broken source() reference (line 35)
# Original: source("power_simulation_cs.R")
# This file doesn't exist in the analysis/ directory
#
# To run this script, update line 35 to one of:
# Option 1: source("power_simulation_twfe_statepanel_staggered_parallel_fixed.R")
# Option 2: source("../archive/old_development_code/eviction_gambling/power_simulation_cs.R")
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Gambling Dose-Response Analysis ===\n\n")

# Load gambling data
gambling <- read_csv("lsr_sports_betting_handle_revenue_by_state_month.csv",
                    show_col_types = FALSE) %>%
  mutate(
    state = str_trim(State),
    # Handle is total bets placed (in dollars)
    # Revenue is operator profit (after payouts)
    handle_millions = Handle / 1e6,
    revenue_millions = Revenue / 1e6
  ) %>%
  select(state, month_date, handle_millions, revenue_millions, Hold)

cat(glue("Gambling data: {nrow(gambling)} state-months\n"))
cat(glue("States: {n_distinct(gambling$state)}\n"))
cat(glue("Period: {min(gambling$month_date)} to {max(gambling$month_date)}\n\n"))

# Load eviction panel
source("power_simulation_cs.R")
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)

# Merge gambling data with eviction panel
# Need to match state names
state_name_map <- tribble(
  ~state_abb, ~state,
  "AZ", "Arizona",
  "AR", "Arkansas",
  "CO", "Colorado",
  "CT", "Connecticut",
  "DE", "Delaware",
  "DC", "District of Columbia",
  "IL", "Illinois",
  "IN", "Indiana",
  "IA", "Iowa",
  "KS", "Kansas",
  "KY", "Kentucky",
  "LA", "Louisiana",
  "ME", "Maine",
  "MD", "Maryland",
  "MA", "Massachusetts",
  "MI", "Michigan",
  "MS", "Mississippi",
  "MT", "Montana",
  "NE", "Nebraska",
  "NV", "Nevada",
  "NH", "New Hampshire",
  "NJ", "New Jersey",
  "NY", "New York",
  "NC", "North Carolina",
  "OH", "Ohio",
  "OR", "Oregon",
  "PA", "Pennsylvania",
  "RI", "Rhode Island",
  "SD", "South Dakota",
  "TN", "Tennessee",
  "VT", "Vermont",
  "VA", "Virginia",
  "WV", "West Virginia",
  "WY", "Wyoming"
)

# Merge
gambling_with_abbrev <- gambling %>%
  left_join(state_name_map, by = "state") %>%
  filter(!is.na(state_abb))

cat(glue("After matching state names: {nrow(gambling_with_abbrev)} observations\n"))
cat(glue("Matched states: {n_distinct(gambling_with_abbrev$state_abb)}\n\n"))

# Get treatment dates by state
# treat_schedule has unit_id and g, need to get state_abb from panel_df
treat_dates <- panel_df %>%
  filter(!is.na(state_abb)) %>%
  distinct(state_abb) %>%
  left_join(
    treat_schedule %>%
      left_join(panel_df %>% distinct(unit_id, state_abb), by = "unit_id") %>%
      filter(!is.na(state_abb)) %>%
      distinct(state_abb, g, ever_treated),
    by = "state_abb"
  )

# Merge with eviction panel
panel_with_gambling <- panel_df %>%
  left_join(gambling_with_abbrev, by = c("state_abb", "month_date")) %>%
  left_join(treat_dates, by = "state_abb") %>%
  mutate(
    months_since_treatment = if_else(ever_treated & !is.na(g),
                                     as.numeric(difftime(month_date, g, units = "days")) / 30.44,
                                     NA_real_),
    post_treatment = !is.na(months_since_treatment) & months_since_treatment >= 0,
    # Gambling intensity (handle per capita would be ideal, but use raw for now)
    has_gambling_data = !is.na(handle_millions)
  )

cat("=== Summary Statistics ===\n")
summary_stats <- panel_with_gambling %>%
  summarise(
    n_obs = n(),
    n_states = n_distinct(state_abb),
    n_with_gambling = sum(has_gambling_data),
    pct_with_gambling = round(100 * n_with_gambling / n_obs, 1),
    n_post_treatment = sum(post_treatment, na.rm = TRUE)
  )
print(summary_stats)

# States with gambling data
states_with_gambling <- panel_with_gambling %>%
  filter(has_gambling_data) %>%
  distinct(state_abb) %>%
  pull(state_abb)

cat(glue("\nStates with gambling data: {paste(states_with_gambling, collapse=', ')}\n\n"))

# Calculate average gambling intensity post-treatment
cat("=== Average Gambling Intensity (Post-Treatment) ===\n")
gambling_intensity <- panel_with_gambling %>%
  filter(post_treatment, has_gambling_data) %>%
  group_by(state_abb) %>%
  summarise(
    avg_handle_millions = mean(handle_millions, na.rm = TRUE),
    avg_revenue_millions = mean(revenue_millions, na.rm = TRUE),
    n_months = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(avg_handle_millions))

print(gambling_intensity %>% head(15))

# Analyze: Does gambling intensity correlate with eviction changes?
cat("\n=== Dose-Response Analysis ===\n")
cat("Question: Do states with higher gambling volume show larger eviction changes?\n\n")

# Calculate change in evictions for each state
# Pre-period: 12 months before treatment
# Post-period: 12 months after treatment (if available)

dose_response_data <- panel_with_gambling %>%
  filter(ever_treated, !is.na(months_since_treatment)) %>%
  mutate(
    period = case_when(
      months_since_treatment >= -12 & months_since_treatment < 0 ~ "pre",
      months_since_treatment >= 0 & months_since_treatment < 12 ~ "post",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(state_abb, period) %>%
  summarise(
    mean_evictions = mean(outcome, na.rm = TRUE),
    mean_handle = mean(handle_millions, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = period,
    values_from = c(mean_evictions, mean_handle, n_obs)
  ) %>%
  mutate(
    eviction_change = mean_evictions_post - mean_evictions_pre,
    avg_gambling_post = mean_handle_post
  ) %>%
  filter(!is.na(eviction_change), !is.na(avg_gambling_post))

cat(glue("States with both pre/post data and gambling data: {nrow(dose_response_data)}\n\n"))

if (nrow(dose_response_data) >= 5) {
  print(dose_response_data %>% select(state_abb, eviction_change, avg_gambling_post))

  # Correlation test
  if (nrow(dose_response_data) >= 3) {
    cor_test <- cor.test(dose_response_data$eviction_change,
                        dose_response_data$avg_gambling_post)

    cat(glue("\nCorrelation: {round(cor_test$estimate, 3)}\n"))
    cat(glue("p-value: {round(cor_test$p.value, 4)}\n\n"))

    # Regression
    model <- lm(eviction_change ~ avg_gambling_post, data = dose_response_data)
    cat("Regression: eviction_change ~ avg_gambling_post\n")
    print(summary(model))

    # Plot
    p <- ggplot(dose_response_data, aes(x = avg_gambling_post, y = eviction_change)) +
      geom_point(size = 3, alpha = 0.7) +
      geom_smooth(method = "lm", se = TRUE, color = "#E74C3C") +
      geom_text(aes(label = state_abb), hjust = -0.2, vjust = -0.2, size = 3) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
      labs(
        title = "Dose-Response: Gambling Volume vs Eviction Changes",
        subtitle = "Change in evictions (12mo post - 12mo pre) vs average gambling handle",
        x = "Average Monthly Gambling Handle ($ millions)",
        y = "Change in Eviction Filings per 1,000 Renters",
        caption = glue("Correlation: {round(cor_test$estimate, 3)}, p = {round(cor_test$p.value, 3)}")
      ) +
      theme_minimal(base_size = 12) +
      theme(
        plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(color = "gray30")
      )

    ggsave("dose_response_gambling_evictions.png", p, width = 10, height = 7, dpi = 300)
    cat("\nSaved: dose_response_gambling_evictions.png\n")
  }
} else {
  cat("Not enough states with complete data for dose-response analysis.\n")
}

# Time-varying analysis: Does gambling volume in month t predict evictions in month t?
cat("\n=== Time-Varying Gambling Effects ===\n")
cat("Testing: Does within-state variation in gambling predict evictions?\n\n")

panel_with_lag <- panel_with_gambling %>%
  filter(post_treatment, has_gambling_data) %>%
  group_by(state_abb) %>%
  arrange(month_date) %>%
  mutate(
    handle_lag1 = lag(handle_millions, 1),
    handle_lag3 = lag(handle_millions, 3)
  ) %>%
  ungroup()

if (nrow(panel_with_lag) > 50) {
  # Fixed effects model: within-state variation
  model_fe <- feols(outcome ~ handle_millions + handle_lag1 + handle_lag3 | state_abb + month_date,
                   data = panel_with_lag)

  cat("Model: outcome ~ handle + lag1 + lag3 | state + month FE\n")
  print(summary(model_fe))

  cat("\nInterpretation:\n")
  cat("This tests whether months with higher gambling volume (within a state)\n")
  cat("show higher/lower evictions, controlling for state and time fixed effects.\n")
}

cat("\n=== SUMMARY ===\n")
cat("This analysis explores whether gambling INTENSITY matters:\n")
cat("1. Dose-response: Do high-volume gambling states show bigger effects?\n")
cat("2. Time-varying: Does month-to-month gambling variation predict evictions?\n\n")
cat("Data limitations:\n")
cat("- Gambling data only available 2021+ for most states\n")
cat("- Pre-COVID eviction data ends Feb 2020\n")
cat("- Limited overlap for clean dose-response analysis\n")
