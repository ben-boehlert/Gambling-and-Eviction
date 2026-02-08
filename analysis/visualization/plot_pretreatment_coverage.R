#!/usr/bin/env Rscript
################################################################################
# plot_pretreatment_coverage.R
#
# Plots how many states have data available at different time periods before
# treatment (e.g., -6, -12, -24 months)
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(glue)
})

# File paths
DATA_FILE <- Sys.getenv("DATA_FILE", "data/raw/combined_monthly_panel.csv")
GAMBLING_FILE <- Sys.getenv("GAMBLING_FILE", "data/raw/sports_gambling_legalization_dates.csv")
OUT_DIR <- Sys.getenv("OUT_DIR", "output/pretrends_evaluation")

# Helper functions (same as main script)
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
  # Aggregate counties to state level
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

  # Use state-level data as fallback
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

  # Combine
  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

# Load data
cat("Loading data...\n")
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

# Load gambling dates
gambling_raw <- readr::read_csv(GAMBLING_FILE, show_col_types = FALSE)

gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  dplyr::select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

# Merge with panel
panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%  # Exclude Maine
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_)
  )

# Only keep treated states for this analysis
treated_panel <- panel %>%
  filter(g > 0) %>%
  filter(!is.na(e))

cat(glue("Treated states: {n_distinct(treated_panel$state_abb)}\n"))
cat(glue("Event time range: {min(treated_panel$e)} to {max(treated_panel$e)}\n\n"))

# Calculate coverage at different pre-treatment horizons
horizons <- c(-3, -6, -12, -18, -24, -30, -36, -48, -60)

coverage_summary <- tibble()

for (h in horizons) {
  states_with_data <- treated_panel %>%
    filter(e == h) %>%
    pull(state_abb) %>%
    n_distinct()

  total_treated <- n_distinct(treated_panel$state_abb)

  coverage_summary <- bind_rows(
    coverage_summary,
    tibble(
      horizon = h,
      n_states = states_with_data,
      pct_coverage = 100 * states_with_data / total_treated
    )
  )
}

cat("Pre-treatment coverage summary:\n")
print(coverage_summary)
cat("\n")

# Create plot
p1 <- ggplot(coverage_summary, aes(x = horizon, y = n_states)) +
  geom_line(linewidth = 1, color = "#2c7bb6") +
  geom_point(size = 3, color = "#2c7bb6") +
  geom_text(aes(label = n_states), vjust = -0.8, size = 3.5) +
  scale_x_continuous(
    breaks = horizons,
    labels = abs(horizons)
  ) +
  scale_y_continuous(limits = c(0, max(coverage_summary$n_states) * 1.15)) +
  labs(
    title = "Pre-Treatment Data Availability",
    subtitle = glue("Number of treated states with data at each time before treatment (N = {n_distinct(treated_panel$state_abb)} treated states)"),
    x = "Months Before Treatment",
    y = "Number of States with Data"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

# Create percentage plot
p2 <- ggplot(coverage_summary, aes(x = horizon, y = pct_coverage)) +
  geom_line(linewidth = 1, color = "#d7191c") +
  geom_point(size = 3, color = "#d7191c") +
  geom_hline(yintercept = 50, linetype = "dashed", alpha = 0.5) +
  geom_text(aes(label = sprintf("%.0f%%", pct_coverage)), vjust = -0.8, size = 3.5) +
  scale_x_continuous(
    breaks = horizons,
    labels = abs(horizons)
  ) +
  scale_y_continuous(limits = c(0, 105), labels = function(x) paste0(x, "%")) +
  labs(
    title = "Pre-Treatment Coverage Rate",
    subtitle = "Percentage of treated states with data at each time before treatment",
    x = "Months Before Treatment",
    y = "% of Treated States with Data"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

# Save plots
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ggsave(
  file.path(OUT_DIR, "pretreatment_coverage_counts.png"),
  plot = p1,
  width = 10,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(OUT_DIR, "pretreatment_coverage_pct.png"),
  plot = p2,
  width = 10,
  height = 6,
  dpi = 300
)

# Combined plot
library(patchwork)
p_combined <- p1 / p2
ggsave(
  file.path(OUT_DIR, "pretreatment_coverage_combined.png"),
  plot = p_combined,
  width = 10,
  height = 10,
  dpi = 300
)

# Save data
readr::write_csv(coverage_summary, file.path(OUT_DIR, "pretreatment_coverage.csv"))

# Also create a detailed state-by-state table
state_coverage <- treated_panel %>%
  group_by(state_abb) %>%
  summarise(
    treatment_date = first(online_start_date[g > 0]),
    min_e = min(e, na.rm = TRUE),
    max_e = max(e, na.rm = TRUE),
    n_pre_periods = sum(e < 0, na.rm = TRUE),
    n_post_periods = sum(e >= 0, na.rm = TRUE),
    has_12mo_pre = any(e == -12),
    has_24mo_pre = any(e == -24),
    has_36mo_pre = any(e == -36),
    .groups = "drop"
  ) %>%
  arrange(treatment_date)

readr::write_csv(state_coverage, file.path(OUT_DIR, "state_pretreatment_coverage.csv"))

cat("\nState-by-state coverage:\n")
print(state_coverage, n = Inf)
cat("\n")

cat(glue("\nPlots saved to:\n"))
cat(glue("  {OUT_DIR}/pretreatment_coverage_counts.png\n"))
cat(glue("  {OUT_DIR}/pretreatment_coverage_pct.png\n"))
cat(glue("  {OUT_DIR}/pretreatment_coverage_combined.png\n"))
cat(glue("\nData saved to:\n"))
cat(glue("  {OUT_DIR}/pretreatment_coverage.csv\n"))
cat(glue("  {OUT_DIR}/state_pretreatment_coverage.csv\n"))
