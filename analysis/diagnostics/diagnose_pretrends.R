#!/usr/bin/env Rscript
################################################################################
# diagnose_pretrends.R
#
# Diagnose sources of pre-trends violations:
# 1. De-meaned trends (after removing FEs)
# 2. State-by-state pre-trends
# 3. Identify problematic states
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(glue)
  library(fixest)
  library(tidyr)
  library(patchwork)
})

# Helper functions
fips_to_state_abb <- function(state_fips) {
  lookup <- c(
    `1`="AL", `2`="AK", `4`="AZ", `5`="AR", `6`="CA", `8`="CO", `9`="CT",
    `10`="DE", `11`="DC", `12`="FL", `13`="GA", `15`="HI", `16`="ID",
    `17`="IL", `18`="IN", `19`="IA", `20`="KS", `21`="KY", `22`="LA",
    `23`="ME", `24`="MD", `25`="MA", `26`="MI", `27`="MN", `28`="MS",
    `29`="MO", `30`="MT", `31`="NE", `32`="NV", `33`="NH", `34`="NJ",
    `35`="NM", `36`="NY", `37`="NC", `38`="ND", `39`="OH", `40`="OK",
    `41`="OR", `42`="PA", `44`="RI", `45`="SC", `46`="SD", `47`="TN",
    `48`="TX", `49`="UT", `50`="VT", `51`="VA", `53`="WA", `54`="WV",
    `55`="WI", `56`="WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

# Load data
cat("Loading data...\n")
df_all <- readr::read_csv("data/raw/combined_monthly_panel.csv", show_col_types = FALSE)
gambling_raw <- readr::read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)
OUT_DIR <- "output/pretrends_evaluation"

panel_raw <- build_state_panel(df_all)

gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

# Build panel with baseline specification
panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0)),
    treated = g > 0
  ) %>%
  filter(is.na(e) | (e >= -12 & e <= 24)) %>%
  filter(!is.na(y))

cat(glue("Panel: {nrow(panel)} obs, {n_distinct(panel$state_abb)} states\n\n"))

################################################################################
# PART 1: Extract residuals after removing state + time FE
################################################################################

cat("=== PART 1: De-meaning with State + Time Fixed Effects ===\n")

# Estimate just the fixed effects model (no treatment)
fe_model <- feols(y ~ 1 | id + t, data = panel, cluster = ~id)

# Extract residuals (these are de-meaned)
# Note: fixest drops singletons, so we need to match observations
panel <- panel %>%
  mutate(row_id = row_number())

# Get observations used in model
used_obs <- fe_model$obs_selection$obsRemoved
if (is.null(used_obs)) {
  used_rows <- 1:nrow(panel)
} else {
  used_rows <- setdiff(1:nrow(panel), used_obs)
}

# Add residuals only for used observations
panel$y_resid <- NA_real_
panel$y_resid[used_rows] <- residuals(fe_model)

# Calculate average residuals by treatment status and event time
resid_trends <- panel %>%
  filter(!is.na(e)) %>%
  group_by(e, treated) %>%
  summarise(
    y_resid_mean = mean(y_resid, na.rm = TRUE),
    y_resid_se = sd(y_resid, na.rm = TRUE) / sqrt(n()),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  mutate(
    ci_lo = y_resid_mean - 1.96 * y_resid_se,
    ci_hi = y_resid_mean + 1.96 * y_resid_se,
    group = if_else(treated, "Treated States", "Never-Treated States")
  )

# Plot de-meaned trends
p_demeaned <- ggplot(resid_trends, aes(x = e, y = y_resid_mean, color = group, fill = group)) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50") +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_line(linewidth = 1) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, color = NA) +
  scale_color_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  scale_fill_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  scale_x_continuous(breaks = seq(-12, 24, by = 6)) +
  labs(
    title = "De-meaned Trends (After Removing State + Time FE)",
    subtitle = "This is what the regression tests for parallel trends",
    x = "Months Relative to Treatment",
    y = "Residualized log(Eviction Filings)",
    color = NULL,
    fill = NULL,
    caption = "Non-zero pre-treatment residuals = pre-trends violation"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

ggsave(
  file.path(OUT_DIR, "demeaned_trends.png"),
  plot = p_demeaned,
  width = 12,
  height = 6,
  dpi = 300
)

cat("Saved: demeaned_trends.png\n")

# Save data
readr::write_csv(resid_trends, file.path(OUT_DIR, "demeaned_trends.csv"))

################################################################################
# PART 2: State-by-state pre-trends
################################################################################

cat("\n=== PART 2: State-by-State Pre-Trends Diagnostics ===\n")

# For each treated state, fit a linear trend in the pre-period
state_pretrends <- panel %>%
  filter(treated, !is.na(e), e < 0, e >= -12) %>%
  group_by(state_abb) %>%
  summarise(
    # Run simple linear regression of residuals on event time
    pre_trend_slope = if (n() > 2) coef(lm(y_resid ~ e))[2] else NA_real_,
    pre_trend_se = if (n() > 2) summary(lm(y_resid ~ e))$coefficients[2, 2] else NA_real_,
    n_pre_obs = n(),
    mean_resid = mean(y_resid),
    treatment_date = first(online_start_date),
    .groups = "drop"
  ) %>%
  mutate(
    pre_trend_tstat = pre_trend_slope / pre_trend_se,
    pre_trend_pval = 2 * pt(abs(pre_trend_tstat), df = n_pre_obs - 2, lower.tail = FALSE),
    significant = pre_trend_pval < 0.05
  ) %>%
  arrange(desc(abs(pre_trend_slope)))

cat("\nState-specific pre-trend slopes (sorted by magnitude):\n")
print(state_pretrends %>% select(state_abb, pre_trend_slope, pre_trend_tstat, pre_trend_pval, significant), n = Inf)

# Plot state-specific pre-trends
p_state_slopes <- ggplot(state_pretrends, aes(x = reorder(state_abb, pre_trend_slope), y = pre_trend_slope, fill = significant)) +
  geom_col() +
  geom_hline(yintercept = 0, linetype = "solid", color = "black") +
  scale_fill_manual(
    values = c("TRUE" = "#d7191c", "FALSE" = "#2c7bb6"),
    labels = c("Not significant", "Significant (p<0.05)")
  ) +
  coord_flip() +
  labs(
    title = "State-Specific Pre-Trend Slopes",
    subtitle = "Linear trend in residualized outcome during pre-treatment period (-12 to -1)",
    x = "State",
    y = "Pre-Trend Slope (change per month)",
    fill = NULL,
    caption = "Positive slope = increasing filings before treatment"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

ggsave(
  file.path(OUT_DIR, "state_pretrend_slopes.png"),
  plot = p_state_slopes,
  width = 10,
  height = 8,
  dpi = 300
)

cat("Saved: state_pretrend_slopes.png\n")

readr::write_csv(state_pretrends, file.path(OUT_DIR, "state_pretrends.csv"))

################################################################################
# PART 3: Individual state trajectories
################################################################################

cat("\n=== PART 3: Individual State Trajectories ===\n")

# Identify top 6 states with largest pre-trend slopes (positive and negative)
top_states <- state_pretrends %>%
  arrange(desc(abs(pre_trend_slope))) %>%
  head(6) %>%
  pull(state_abb)

cat("Plotting top 6 states with largest pre-trends:", paste(top_states, collapse = ", "), "\n")

# Plot individual trajectories for problematic states
state_trajectories <- panel %>%
  filter(state_abb %in% top_states, !is.na(e)) %>%
  select(state_abb, e, y_resid, treatment_date = online_start_date)

p_trajectories <- ggplot(state_trajectories, aes(x = e, y = y_resid)) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50", alpha = 0.5) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_line(aes(color = state_abb), linewidth = 0.8) +
  geom_point(aes(color = state_abb), size = 1.5, alpha = 0.6) +
  # Add smooth trend line for pre-period
  geom_smooth(
    data = state_trajectories %>% filter(e < 0),
    aes(color = state_abb),
    method = "lm",
    se = FALSE,
    linetype = "dashed",
    linewidth = 0.6
  ) +
  facet_wrap(~state_abb, ncol = 3, scales = "free_y") +
  scale_x_continuous(breaks = seq(-12, 24, by = 6)) +
  labs(
    title = "States with Largest Pre-Trends",
    subtitle = "Residualized outcome by event time (dashed line = pre-period linear trend)",
    x = "Months Relative to Treatment",
    y = "Residualized log(Eviction Filings)",
    color = "State"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

ggsave(
  file.path(OUT_DIR, "top_states_trajectories.png"),
  plot = p_trajectories,
  width = 14,
  height = 8,
  dpi = 300
)

cat("Saved: top_states_trajectories.png\n")

################################################################################
# PART 4: Summary statistics
################################################################################

cat("\n=== PART 4: Summary Statistics ===\n")

summary_stats <- tibble(
  metric = c(
    "States with significant positive pre-trends",
    "States with significant negative pre-trends",
    "States with insignificant pre-trends",
    "Mean absolute pre-trend slope",
    "Median absolute pre-trend slope",
    "Max positive pre-trend slope",
    "Max negative pre-trend slope"
  ),
  value = c(
    sum(state_pretrends$significant & state_pretrends$pre_trend_slope > 0, na.rm = TRUE),
    sum(state_pretrends$significant & state_pretrends$pre_trend_slope < 0, na.rm = TRUE),
    sum(!state_pretrends$significant, na.rm = TRUE),
    mean(abs(state_pretrends$pre_trend_slope), na.rm = TRUE),
    median(abs(state_pretrends$pre_trend_slope), na.rm = TRUE),
    max(state_pretrends$pre_trend_slope, na.rm = TRUE),
    min(state_pretrends$pre_trend_slope, na.rm = TRUE)
  )
)

cat("\nPre-trends diagnostic summary:\n")
print(summary_stats)

readr::write_csv(summary_stats, file.path(OUT_DIR, "pretrends_summary.csv"))

cat("\n=== DIAGNOSTIC COMPLETE ===\n")
cat("\nFiles created:\n")
cat("  1. demeaned_trends.png - De-meaned trends (what regression tests)\n")
cat("  2. state_pretrend_slopes.png - State-specific pre-trend slopes\n")
cat("  3. top_states_trajectories.png - Individual trajectories for problematic states\n")
cat("  4. demeaned_trends.csv - De-meaned trend data\n")
cat("  5. state_pretrends.csv - State-specific pre-trend estimates\n")
cat("  6. pretrends_summary.csv - Summary statistics\n")
cat("\nAll files saved to:", OUT_DIR, "\n")
