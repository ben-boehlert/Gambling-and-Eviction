#!/usr/bin/env Rscript
################################################################################
# plot_treated_untreated_trends.R
#
# Plot raw trends for treated vs untreated states to visualize pre-trends
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(glue)
  library(tidyr)
})

# Helper functions (same as before)
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

# Build panel
panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0)),
    treated = g > 0
  ) %>%
  filter(!is.na(y))

cat(glue("\nPanel: {nrow(panel)} obs, {n_distinct(panel$state_abb)} states\n"))
cat(glue("Treated: {sum(panel$treated)}\n"))
cat(glue("Untreated: {sum(!panel$treated)}\n\n"))

# Calculate average by treatment status and month
avg_trends <- panel %>%
  group_by(month_date, treated) %>%
  summarise(
    y_mean = mean(y, na.rm = TRUE),
    y_se = sd(y, na.rm = TRUE) / sqrt(n()),
    n_states = n_distinct(state_abb),
    .groups = "drop"
  ) %>%
  mutate(
    ci_lo = y_mean - 1.96 * y_se,
    ci_hi = y_mean + 1.96 * y_se,
    group = if_else(treated, "Treated States", "Never-Treated States")
  )

cat("Summary statistics:\n")
print(avg_trends %>%
  group_by(group) %>%
  summarise(
    min_date = min(month_date),
    max_date = max(month_date),
    mean_y = mean(y_mean),
    n_obs = n()
  ))
cat("\n")

# Plot 1: Raw trends
p1 <- ggplot(avg_trends, aes(x = month_date, y = y_mean, color = group, fill = group)) +
  geom_line(linewidth = 1) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, color = NA) +
  scale_color_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  scale_fill_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  labs(
    title = "Eviction Filings: Treated vs Never-Treated States",
    subtitle = "Average log(1 + filings count) over time (±95% CI)",
    x = "Date",
    y = "log(1 + Eviction Filings)",
    color = NULL,
    fill = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

# Save plot 1
ggsave(
  file.path(OUT_DIR, "treated_vs_untreated_raw_trends.png"),
  plot = p1,
  width = 12,
  height = 6,
  dpi = 300
)

cat("Saved: treated_vs_untreated_raw_trends.png\n")

# Plot 2: Event time analysis (for treated states only)
# Calculate average treatment time for each treated state
treated_states <- panel %>%
  filter(treated) %>%
  select(state_abb, online_start_date) %>%
  distinct()

cat(glue("\nTreated states: {nrow(treated_states)}\n"))

# Create event-time averages
event_trends <- panel %>%
  filter(!is.na(e)) %>%
  filter(e >= -24 & e <= 24) %>%
  group_by(e, treated) %>%
  summarise(
    y_mean = mean(y, na.rm = TRUE),
    y_se = sd(y, na.rm = TRUE) / sqrt(n()),
    n_states = n_distinct(state_abb),
    .groups = "drop"
  ) %>%
  mutate(
    ci_lo = y_mean - 1.96 * y_se,
    ci_hi = y_mean + 1.96 * y_se,
    group = if_else(treated, "Treated States", "Never-Treated States")
  )

p2 <- ggplot(event_trends, aes(x = e, y = y_mean, color = group, fill = group)) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "gray50", linewidth = 0.5) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_line(linewidth = 1) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, color = NA) +
  scale_color_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  scale_fill_manual(values = c("Treated States" = "#d7191c", "Never-Treated States" = "#2c7bb6")) +
  scale_x_continuous(breaks = seq(-24, 24, by = 6)) +
  labs(
    title = "Event Study: Treated vs Never-Treated States",
    subtitle = "Average log(1 + filings count) by months relative to treatment (±95% CI)",
    x = "Months Relative to Treatment",
    y = "log(1 + Eviction Filings)",
    color = NULL,
    fill = NULL,
    caption = "Vertical line at treatment period (month 0)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

ggsave(
  file.path(OUT_DIR, "treated_vs_untreated_event_study.png"),
  plot = p2,
  width = 12,
  height = 6,
  dpi = 300
)

cat("Saved: treated_vs_untreated_event_study.png\n")

# Skip plot 3 - can't compute difference without shared event time
cat("\nSkipping difference plot (never-treated states don't have event time)\n")

# Save summary data
readr::write_csv(avg_trends, file.path(OUT_DIR, "treated_untreated_raw_trends.csv"))
readr::write_csv(event_trends, file.path(OUT_DIR, "treated_untreated_event_trends.csv"))

cat("\nData files saved to:", OUT_DIR, "\n")
cat("\nPlots created:\n")
cat("  1. treated_vs_untreated_raw_trends.png - Raw time series\n")
cat("  2. treated_vs_untreated_event_study.png - Event time analysis (treated states only)\n")
