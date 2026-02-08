#!/usr/bin/env Rscript
################################################################################
# analyze_gambling_dose_no_ny.R
# Dose-response analysis EXCLUDING New York (outlier)
#
# Run from project root directory.
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Gambling Dose-Response Analysis (Excluding NY) ===\n\n")

# Load gambling data
gambling <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
                    show_col_types = FALSE) %>%
  mutate(
    state = str_trim(State),
    handle_millions = Handle / 1e6,
    revenue_millions = Revenue / 1e6
  ) %>%
  select(state, month_date, handle_millions, revenue_millions, Hold)

# State name mapping
state_name_map <- tribble(
  ~state_abb, ~state,
  "AZ", "Arizona", "AR", "Arkansas", "CO", "Colorado", "CT", "Connecticut",
  "DE", "Delaware", "DC", "District of Columbia", "IL", "Illinois",
  "IN", "Indiana", "IA", "Iowa", "KS", "Kansas", "KY", "Kentucky",
  "LA", "Louisiana", "ME", "Maine", "MD", "Maryland", "MA", "Massachusetts",
  "MI", "Michigan", "MS", "Mississippi", "MT", "Montana", "NE", "Nebraska",
  "NV", "Nevada", "NH", "New Hampshire", "NJ", "New Jersey", "NY", "New York",
  "NC", "North Carolina", "OH", "Ohio", "OR", "Oregon", "PA", "Pennsylvania",
  "RI", "Rhode Island", "SD", "South Dakota", "TN", "Tennessee",
  "VT", "Vermont", "VA", "Virginia", "WV", "West Virginia", "WY", "Wyoming"
)

gambling_with_abbrev <- gambling %>%
  left_join(state_name_map, by = "state") %>%
  filter(!is.na(state_abb))

# Load eviction panel
source("power_simulation_cs.R")
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)

# Get treatment dates
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

# Merge
panel_with_gambling <- panel_df %>%
  left_join(gambling_with_abbrev, by = c("state_abb", "month_date")) %>%
  left_join(treat_dates, by = "state_abb") %>%
  mutate(
    months_since_treatment = if_else(ever_treated & !is.na(g),
                                     as.numeric(difftime(month_date, g, units = "days")) / 30.44,
                                     NA_real_),
    post_treatment = !is.na(months_since_treatment) & months_since_treatment >= 0,
    has_gambling_data = !is.na(handle_millions)
  )

# Calculate change in evictions
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

cat(glue("=== WITH New York (n={nrow(dose_response_data)}) ===\n"))
print(dose_response_data %>% select(state_abb, eviction_change, avg_gambling_post) %>% arrange(desc(avg_gambling_post)))

# Analyze WITH NY
cor_with <- cor.test(dose_response_data$eviction_change, dose_response_data$avg_gambling_post)
model_with <- lm(eviction_change ~ avg_gambling_post, data = dose_response_data)

cat(glue("\nWith NY - Correlation: {round(cor_with$estimate, 3)}, p = {round(cor_with$p.value, 4)}\n"))
cat(glue("With NY - Coefficient: {round(coef(model_with)[2], 5)}, p = {round(summary(model_with)$coefficients[2,4], 4)}\n\n"))

# EXCLUDE New York
dose_response_no_ny <- dose_response_data %>%
  filter(state_abb != "NY")

cat(glue("=== WITHOUT New York (n={nrow(dose_response_no_ny)}) ===\n"))
print(dose_response_no_ny %>% select(state_abb, eviction_change, avg_gambling_post) %>% arrange(desc(avg_gambling_post)))

if (nrow(dose_response_no_ny) >= 3) {
  # Correlation test
  cor_without <- cor.test(dose_response_no_ny$eviction_change, dose_response_no_ny$avg_gambling_post)

  cat(glue("\nWithout NY - Correlation: {round(cor_without$estimate, 3)}, p = {round(cor_without$p.value, 4)}\n"))

  # Regression
  model_without <- lm(eviction_change ~ avg_gambling_post, data = dose_response_no_ny)
  cat("Regression WITHOUT NY:\n")
  print(summary(model_without))

  # Compare
  cat("\n=== COMPARISON ===\n")
  cat(glue("WITH NY:    r = {round(cor_with$estimate, 3)}, p = {round(cor_with$p.value, 4)}, coef = {round(coef(model_with)[2], 5)}\n"))
  cat(glue("WITHOUT NY: r = {round(cor_without$estimate, 3)}, p = {round(cor_without$p.value, 4)}, coef = {round(coef(model_without)[2], 5)}\n\n"))

  # Plots side-by-side
  p_with <- ggplot(dose_response_data, aes(x = avg_gambling_post, y = eviction_change)) +
    geom_point(aes(color = state_abb == "NY"), size = 3, alpha = 0.7) +
    geom_smooth(method = "lm", se = TRUE, color = "#E74C3C") +
    geom_text(aes(label = state_abb), hjust = -0.2, vjust = -0.2, size = 3) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    scale_color_manual(values = c("FALSE" = "black", "TRUE" = "red"), guide = "none") +
    labs(
      title = "A. Including NY",
      x = "Avg Monthly Gambling Handle ($M)",
      y = "Change in Evictions per 1k",
      caption = glue("r = {round(cor_with$estimate, 3)}, p = {round(cor_with$p.value, 3)}")
    ) +
    theme_minimal(base_size = 11)

  p_without <- ggplot(dose_response_no_ny, aes(x = avg_gambling_post, y = eviction_change)) +
    geom_point(size = 3, alpha = 0.7, color = "black") +
    geom_smooth(method = "lm", se = TRUE, color = "#3498DB") +
    geom_text(aes(label = state_abb), hjust = -0.2, vjust = -0.2, size = 3) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    labs(
      title = "B. Excluding NY",
      x = "Avg Monthly Gambling Handle ($M)",
      y = "Change in Evictions per 1k",
      caption = glue("r = {round(cor_without$estimate, 3)}, p = {round(cor_without$p.value, 3)}")
    ) +
    theme_minimal(base_size = 11)

  library(patchwork)
  combined <- p_with + p_without +
    plot_annotation(
      title = "Dose-Response Sensitivity to New York",
      subtitle = "Effect of excluding the largest gambling market",
      theme = theme(plot.title = element_text(size = 14, face = "bold"))
    )

  ggsave("dose_response_with_without_ny.png", combined, width = 14, height = 6, dpi = 300)
  cat("\nSaved: dose_response_with_without_ny.png\n")

  # Influential point analysis
  cat("\n=== Influence Diagnostics ===\n")
  cooksd_with <- cooks.distance(model_with)
  influential <- which(cooksd_with > 4/nrow(dose_response_data))

  if (length(influential) > 0) {
    cat("Influential observations (Cook's D > 4/n):\n")
    print(dose_response_data[influential, c("state_abb", "eviction_change", "avg_gambling_post")])
  }

  cat("\n=== INTERPRETATION ===\n")
  if (cor_without$p.value < 0.10 & cor_with$p.value < 0.10) {
    cat("Result: Dose-response relationship ROBUST to excluding NY\n")
    cat("Conclusion: Effect is NOT driven by NY outlier alone\n")
  } else if (cor_with$p.value < 0.10 & cor_without$p.value >= 0.10) {
    cat("Result: Dose-response relationship DRIVEN by NY outlier\n")
    cat("Conclusion: Effect disappears when NY excluded - not robust\n")
  } else {
    cat("Result: No significant dose-response in either specification\n")
  }
}
