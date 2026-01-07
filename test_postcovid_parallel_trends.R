#!/usr/bin/env Rscript
################################################################################
# test_postcovid_parallel_trends.R
# Test whether parallel trends hold in post-COVID period (2021-07 onwards)
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Post-COVID Parallel Trends Test ===\n\n")

# Load panel
source("power_simulation_cs.R")
panel_full <- load_panel(cfg)

# Filter to post-COVID period only
# Note: We need sufficient pre-treatment data for late adopters
# Using 2021-01-01 gives us at least 8 months pre-treatment for earliest adopters (AZ: Sep 2021)
POST_COVID_START <- as.Date("2021-01-01")

panel_post <- panel_full %>%
  filter(month_date >= POST_COVID_START)

cat(glue("Post-COVID period: {POST_COVID_START} to {max(panel_post$month_date)}\n"))
cat(glue("Total observations: {nrow(panel_post)}\n"))
cat(glue("States: {n_distinct(panel_post$state_abb)}\n"))
cat(glue("Months: {n_distinct(panel_post$month_date)}\n\n"))

# Load treatment dates
# Convert full state names to abbreviations
state_name_to_abb <- c(
  "Alabama" = "AL", "Alaska" = "AK", "Arizona" = "AZ", "Arkansas" = "AR",
  "California" = "CA", "Colorado" = "CO", "Connecticut" = "CT", "Delaware" = "DE",
  "Florida" = "FL", "Georgia" = "GA", "Hawaii" = "HI", "Idaho" = "ID",
  "Illinois" = "IL", "Indiana" = "IN", "Iowa" = "IA", "Kansas" = "KS",
  "Kentucky" = "KY", "Louisiana" = "LA", "Maine" = "ME", "Maryland" = "MD",
  "Massachusetts" = "MA", "Michigan" = "MI", "Minnesota" = "MN", "Mississippi" = "MS",
  "Missouri" = "MO", "Montana" = "MT", "Nebraska" = "NE", "Nevada" = "NV",
  "New Hampshire" = "NH", "New Jersey" = "NJ", "New Mexico" = "NM", "New York" = "NY",
  "North Carolina" = "NC", "North Dakota" = "ND", "Ohio" = "OH", "Oklahoma" = "OK",
  "Oregon" = "OR", "Pennsylvania" = "PA", "Rhode Island" = "RI", "South Carolina" = "SC",
  "South Dakota" = "SD", "Tennessee" = "TN", "Texas" = "TX", "Utah" = "UT",
  "Vermont" = "VT", "Virginia" = "VA", "Washington" = "WA", "West Virginia" = "WV",
  "Wisconsin" = "WI", "Wyoming" = "WY", "District of Columbia" = "DC"
)

treat_info <- read_csv("sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  select(state, online_start_date) %>%
  mutate(state_abb = state_name_to_abb[state]) %>%
  select(state_abb, online_start_date) %>%
  mutate(
    # Post-COVID adopters: adopted Sep 2021 or later (to ensure sufficient pre-treatment data)
    treated_post_covid = !is.na(online_start_date) & online_start_date >= as.Date("2021-09-01"),
    # Controls: never treated OR adopted before Sep 2021
    control_post_covid = is.na(online_start_date) | online_start_date < as.Date("2021-09-01"),
    # Exclude COVID-disruption adopters (Mar 2020 - Aug 2021)
    # This includes states that adopted during COVID + VA, MI that adopted Jan 2021
    covid_disruption = !is.na(online_start_date) &
                       online_start_date >= as.Date("2020-03-01") &
                       online_start_date < as.Date("2021-09-01")
  )

cat("=== Treatment Classification ===\n")
cat("\nPost-COVID Adopters (treated 2021-09+):\n")
print(treat_info %>%
  filter(treated_post_covid) %>%
  arrange(online_start_date) %>%
  select(state_abb, online_start_date))

cat("\nCOVID Disruption Adopters (2020-03 to 2021-08) - EXCLUDED:\n")
print(treat_info %>%
  filter(covid_disruption) %>%
  arrange(online_start_date) %>%
  select(state_abb, online_start_date))

cat("\nControl States (never treated + pre-2020-03 adopters):\n")
control_states <- treat_info %>%
  filter(control_post_covid, !covid_disruption) %>%
  pull(state_abb)
cat(paste(control_states, collapse = ", "), "\n")

# Merge treatment info with panel
panel_post_full <- panel_post %>%
  left_join(treat_info, by = "state_abb") %>%
  # Exclude COVID-disruption states
  filter(!covid_disruption | is.na(covid_disruption))

cat(glue("\nAfter excluding COVID-disruption states: {nrow(panel_post_full)} obs\n\n"))

# For parallel trends test, use only PRE-TREATMENT periods for post-COVID adopters
# This means: before their adoption date
baseline_post <- panel_post_full %>%
  filter(
    # Control states: all periods
    control_post_covid |
    # Post-COVID treated states: only pre-treatment periods
    (treated_post_covid & month_date < online_start_date)
  )

cat("=== Baseline Sample for Pre-Trends Test ===\n")
cat(glue("Total observations: {nrow(baseline_post)}\n"))

baseline_summary <- baseline_post %>%
  group_by(treated_post_covid) %>%
  summarise(
    n_obs = n(),
    n_states = n_distinct(state_abb),
    min_date = min(month_date),
    max_date = max(month_date),
    states = paste(unique(state_abb), collapse = ", "),
    .groups = "drop"
  )

print(baseline_summary)

# Check that we have enough pre-treatment data for treated states
cat("\n=== Pre-Treatment Months by Post-COVID Adopter ===\n")
pretreatment_counts <- baseline_post %>%
  filter(treated_post_covid) %>%
  group_by(state_abb, online_start_date) %>%
  summarise(
    n_pretreatment_months = n_distinct(month_date),
    first_month = min(month_date),
    last_month = max(month_date),
    .groups = "drop"
  ) %>%
  arrange(online_start_date)

print(pretreatment_counts)

min_pretreatment <- min(pretreatment_counts$n_pretreatment_months)
cat(glue("\nMinimum pre-treatment months: {min_pretreatment}\n"))

if (min_pretreatment < 6) {
  cat("⚠️  WARNING: Some states have very few pre-treatment months!\n")
  cat("   Parallel trends test may be underpowered.\n\n")
}

# Residualize outcome (remove unit + time FE)
cat("\n=== Residualizing Outcomes ===\n")

baseline_resid <- baseline_post %>%
  mutate(
    unit_id = as.integer(factor(state_abb)),
    time_id = as.integer(factor(month_date))
  )

m <- feols(outcome ~ 1 | unit_id + time_id, data = baseline_resid)

baseline_resid <- baseline_resid %>%
  mutate(outcome_resid = resid(m) + mean(outcome, na.rm = TRUE))

# Test for differential trends
cat("\n=== Differential Trends Test ===\n")
cat("Model: outcome_resid ~ time_id * treated_post_covid\n\n")

pretrends_model <- lm(outcome_resid ~ time_id * treated_post_covid, data = baseline_resid)

interaction_coef <- summary(pretrends_model)$coefficients["time_id:treated_post_covidTRUE", ]

cat(sprintf("Differential trend coefficient: %.4f\n", interaction_coef["Estimate"]))
cat(sprintf("Standard error: %.4f\n", interaction_coef["Std. Error"]))
cat(sprintf("t-statistic: %.2f\n", interaction_coef["t value"]))
cat(sprintf("p-value: %.4f\n", interaction_coef["Pr(>|t|)"]))

cat("\n=== RESULT ===\n")
if (interaction_coef["Pr(>|t|)"] > 0.05) {
  cat("✓ Parallel trends HOLD in post-COVID period (p > 0.05)\n")
  cat("  → Dual-period power analysis is VIABLE\n")
  pt_holds <- TRUE
} else {
  cat("✗ Parallel trends VIOLATED in post-COVID period (p < 0.05)\n")
  cat("  → Fall back to pre-COVID only analysis\n")
  pt_holds <- FALSE
}

# Visual check: plot trends
cat("\n=== Creating Trend Plot ===\n")

trend_plot_data <- baseline_resid %>%
  group_by(month_date, treated_post_covid) %>%
  summarise(
    mean_outcome = mean(outcome_resid, na.rm = TRUE),
    se = sd(outcome_resid, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

library(ggplot2)

p <- ggplot(trend_plot_data, aes(x = month_date, y = mean_outcome, color = treated_post_covid)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2.5) +
  geom_ribbon(
    aes(ymin = mean_outcome - 1.96*se, ymax = mean_outcome + 1.96*se, fill = treated_post_covid),
    alpha = 0.2,
    color = NA
  ) +
  labs(
    title = "Post-COVID Pre-Treatment Parallel Trends Test",
    subtitle = glue("Period: {POST_COVID_START} onwards (pre-treatment periods only)\n",
                    "Differential trend p-value: {round(interaction_coef['Pr(>|t|)'], 4)}"),
    x = "Month",
    y = "Eviction Filings per 1,000 Renters\n(residualized: unit + time FE removed)",
    color = "Group",
    fill = "Group"
  ) +
  scale_color_manual(
    values = c("TRUE" = "#E74C3C", "FALSE" = "#3498DB"),
    labels = c("TRUE" = "Post-COVID Adopters (AZ, CT, NY, AR, KS, OH)",
               "FALSE" = "Controls (never-treated + pre-COVID adopters)")
  ) +
  scale_fill_manual(
    values = c("TRUE" = "#E74C3C", "FALSE" = "#3498DB"),
    labels = c("TRUE" = "Post-COVID Adopters (AZ, CT, NY, AR, KS, OH)",
               "FALSE" = "Controls (never-treated + pre-COVID adopters)")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.position = "bottom",
    legend.text = element_text(size = 10)
  )

ggsave("postcovid_pretrends.png", p, width = 12, height = 7, dpi = 300)
cat("Saved: postcovid_pretrends.png\n")

# Additional robustness: plot RAW (non-residualized) trends
p_raw <- baseline_post %>%
  group_by(month_date, treated_post_covid) %>%
  summarise(mean_outcome = mean(outcome, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = month_date, y = mean_outcome, color = treated_post_covid)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2.5) +
  labs(
    title = "Post-COVID Raw Trends (Pre-Treatment Periods)",
    subtitle = "No residualization - showing raw eviction rates",
    x = "Month",
    y = "Eviction Filings per 1,000 Renters (raw)",
    color = "Group"
  ) +
  scale_color_manual(
    values = c("TRUE" = "#E74C3C", "FALSE" = "#3498DB"),
    labels = c("TRUE" = "Post-COVID Adopters", "FALSE" = "Controls")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.position = "bottom"
  )

ggsave("postcovid_raw_trends.png", p_raw, width = 12, height = 7, dpi = 300)
cat("Saved: postcovid_raw_trends.png\n")

# Summary for next steps
cat("\n=== NEXT STEPS ===\n")
if (pt_holds) {
  cat("\n✓ POST-COVID PARALLEL TRENDS HOLD\n\n")
  cat("Recommended: Proceed with dual-period power analysis\n\n")
  cat("To run post-COVID power simulation:\n")
  cat("1. Modify load_panel() in power_simulation_cs.R to support:\n")
  cat("   - restrict_to_postcovid = TRUE\n")
  cat("   - postcovid_start = as.Date('2021-07-01')\n")
  cat("   - exclude_states = c('CO', 'TN', 'VA')\n")
  cat("2. Create cfg_postcovid.rds configuration\n")
  cat("3. Run: cfg <- readRDS('cfg_postcovid.rds'); source('power_simulation_cs.R')\n")
  cat("4. Compare pre-COVID and post-COVID MDEs\n")
} else {
  cat("\n✗ POST-COVID PARALLEL TRENDS VIOLATED\n\n")
  cat("Recommended: Stick with pre-COVID only analysis\n\n")
  cat("The violation suggests post-COVID adopters had different pre-trends.\n")
  cat("Possible reasons:\n")
  cat("- Different state characteristics (late adopters vs early adopters)\n")
  cat("- Differential COVID recovery trajectories\n")
  cat("- Housing market heterogeneity\n\n")
  cat("Use pre-COVID analysis only (cfg_precovid.rds).\n")
}

cat("\n=== Type I Error Simulation (Quick Check) ===\n")
cat("Running small simulation to estimate Type I error in post-COVID period...\n\n")

# Quick Type I error check
if (nrow(baseline_resid) >= 100) {
  set.seed(456)

  quick_typeI <- function() {
    # Assign random placebo treatment
    states <- unique(baseline_resid$state_abb)
    n_treated <- max(3, round(length(states) * 0.25))

    placebo_treated <- sample(states, n_treated)

    sim_data <- baseline_resid %>%
      mutate(
        placebo_treat = state_abb %in% placebo_treated,
        placebo_g = if_else(placebo_treat,
                           sample(unique(month_date), 1),
                           as.Date(NA))
      )

    # Run simple test
    tryCatch({
      m <- lm(outcome_resid ~ placebo_treat, data = sim_data)
      p_val <- summary(m)$coefficients["placebo_treatTRUE", "Pr(>|t|)"]
      return(p_val < 0.05)
    }, error = function(e) NA)
  }

  # Run 50 quick sims
  n_quick_sims <- 50
  type1_results <- replicate(n_quick_sims, quick_typeI())
  type1_rate <- mean(type1_results, na.rm = TRUE)

  cat(glue("Quick Type I error estimate (n={n_quick_sims}): {round(100*type1_rate, 1)}%\n"))
  cat(glue("Target: 5% (acceptable range: 3-10%)\n\n"))

  if (type1_rate > 0.15) {
    cat("⚠️  Type I error elevated - may indicate identification issues\n")
  } else if (type1_rate < 0.02) {
    cat("⚠️  Type I error very low - may indicate overly conservative test\n")
  } else {
    cat("✓ Type I error in acceptable range\n")
  }
}

cat("\nDone!\n")
