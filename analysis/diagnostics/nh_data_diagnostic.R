#!/usr/bin/env Rscript
################################################################################
# nh_data_diagnostic.R
#
# Diagnoses NH's data quality issue. The per-state did2s found NH with
# ATT = -57% (-0.84 log-points) and pre-period coefficients reaching 1.55
# log-points. Is this:
#   - A one-time level shift (data definition change at a specific date)?
#   - A long-run trend?
#   - Idiosyncratic county-specific volatility?
#   - A coverage issue (counties dropping in/out of the panel)?
#
# Diagnostics:
#   1. Raw NH state-aggregate time series (sum of filings across NH counties)
#   2. NH per-county time series
#   3. ETS coverage by NH county over time (which counties have data when?)
#   4. NH's event study coefficients (from earlier did2s output)
#   5. Compare NH levels to a similar small-county state for sanity
#
# Outputs:
#   output/border_diagnostic/nh_diagnostic/
#     nh_state_timeseries.png
#     nh_county_timeseries.png
#     nh_coverage_heatmap.png
#     nh_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(ggplot2)
  library(tidyr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic", "nh_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count),
         renter_occupied_housing_units =
           as.numeric(renter_occupied_housing_units))

nh <- county_raw %>%
  filter(state_fips == 33L) %>%
  arrange(fips, month_date)

cat("NH summary:\n")
cat("  Counties:", n_distinct(nh$fips), "\n")
cat("  Month range:", as.character(min(nh$month_date)), "to",
    as.character(max(nh$month_date)), "\n")
cat("  Total obs:", nrow(nh), "\n")
cat("  Counties in data:\n")
print(nh %>% distinct(fips, name) %>%
        left_join(nh %>% count(fips, name = "n_months"), by = "fips") %>%
        arrange(fips))

# ----------------------------- state-level time series ------------------------

nh_state <- nh %>%
  group_by(month_date) %>%
  summarise(
    n_counties_reporting = n_distinct(fips),
    total_filings = sum(filings_count, na.rm = TRUE),
    total_renters = sum(renter_occupied_housing_units, na.rm = TRUE),
    filings_per_1k = if_else(total_renters > 0,
                              1000 * total_filings / total_renters,
                              NA_real_),
    .groups = "drop"
  )

write_csv(nh_state, file.path(out_dir, "nh_state_timeseries.csv"))

p_state <- nh_state %>%
  pivot_longer(c(total_filings, n_counties_reporting, filings_per_1k),
               names_to = "series", values_to = "value") %>%
  mutate(series = factor(series,
                         levels = c("n_counties_reporting", "total_filings",
                                    "filings_per_1k"),
                         labels = c("Counties reporting in NH",
                                    "Total NH filings (sum)",
                                    "NH filings per 1,000 renters"))) %>%
  ggplot(aes(x = month_date, y = value)) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 0.7) +
  geom_vline(xintercept = as.Date("2019-12-01"),
             linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = as.Date("2020-03-01"),
             linetype = "dotted", color = "grey60") +
  geom_vline(xintercept = as.Date("2022-04-01"),
             linetype = "dotted", color = "grey60") +
  facet_wrap(~ series, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain", size = rel(0.95)))

ggsave(file.path(out_dir, "nh_state_timeseries.png"), p_state,
       width = 8, height = 6, dpi = 300, bg = "transparent")

# ----------------------------- county-level time series -----------------------

p_county <- nh %>%
  ggplot(aes(x = month_date, y = filings_count)) +
  geom_line(color = "grey20", linewidth = 0.4) +
  geom_point(color = "grey20", size = 0.4) +
  geom_vline(xintercept = as.Date("2019-12-01"),
             linetype = "dashed", color = "grey50") +
  facet_wrap(~ name, ncol = 3, scales = "free_y") +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(x = NULL, y = "Monthly eviction filings (count)") +
  theme_minimal(base_size = 9, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain", size = rel(0.9)))

ggsave(file.path(out_dir, "nh_county_timeseries.png"), p_county,
       width = 10, height = 8, dpi = 300, bg = "transparent")

# ----------------------------- coverage heatmap -------------------------------

coverage_df <- nh %>%
  mutate(year_month = format(month_date, "%Y-%m"),
         has_data = !is.na(filings_count) & filings_count >= 0)

p_cov <- coverage_df %>%
  ggplot(aes(x = month_date, y = factor(name), fill = has_data)) +
  geom_tile(color = "white", linewidth = 0.1) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  scale_fill_manual(values = c(`FALSE` = "grey90", `TRUE` = "grey25"),
                    name = NULL,
                    labels = c("Missing", "Reporting")) +
  labs(x = NULL, y = "NH county") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(legend.position = "bottom",
        panel.grid = element_blank(),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "nh_coverage_heatmap.png"), p_cov,
       width = 9, height = 4, dpi = 300, bg = "transparent")

# ----------------------------- summary statistics by year ---------------------

nh_yearly <- nh %>%
  mutate(year = as.integer(format(month_date, "%Y"))) %>%
  group_by(year) %>%
  summarise(
    n_county_months = n(),
    n_counties = n_distinct(fips),
    mean_filings_per_county_month = mean(filings_count, na.rm = TRUE),
    median_filings = median(filings_count, na.rm = TRUE),
    sd_filings = sd(filings_count, na.rm = TRUE),
    total_state_filings = sum(filings_count, na.rm = TRUE),
    .groups = "drop"
  )
write_csv(nh_yearly, file.path(out_dir, "nh_yearly_summary.csv"))

cat("\n=== NH YEARLY SUMMARY ===\n")
print(nh_yearly)

# ----------------------------- check for the shift around 2019-12 -------------

# Pre-treatment (before Dec 2019) vs post-treatment for state aggregate.
shift_check <- nh %>%
  mutate(
    period = case_when(
      month_date < as.Date("2019-01-01") ~ "2016-2018",
      month_date >= as.Date("2019-01-01") &
        month_date < as.Date("2019-12-01")  ~ "2019_pre_treat",
      month_date >= as.Date("2019-12-01") &
        month_date < as.Date("2020-03-01")  ~ "2019-12_to_2020-02",
      month_date >= as.Date("2022-04-01") &
        month_date < as.Date("2023-01-01")  ~ "2022_post_covid",
      month_date >= as.Date("2023-01-01")   ~ "2023-2024",
      TRUE                                  ~ "COVID_drop"
    )
  ) %>%
  group_by(period) %>%
  summarise(
    n_obs = n(),
    n_counties = n_distinct(fips),
    mean_filings = mean(filings_count, na.rm = TRUE),
    median_filings = median(filings_count, na.rm = TRUE),
    sd_filings = sd(filings_count, na.rm = TRUE),
    n_zero_or_missing = sum(filings_count == 0 | is.na(filings_count)),
    .groups = "drop"
  )
write_csv(shift_check, file.path(out_dir, "nh_period_summary.csv"))

cat("\n=== NH PERIOD SUMMARY (mean filings per county-month) ===\n")
print(shift_check)

cat("\nWrote outputs to:", out_dir, "\n")
