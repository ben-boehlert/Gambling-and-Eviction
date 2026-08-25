#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/10_exposure_timing_update.R
#
# Exposure-vs-eviction-recovery timing table (maintained version of the inline
# 2026-08-13 analysis), updated for the Codex handle refresh (2026-08-14):
# LSR file now covers 35 states incl. WV and runs through 2026-05, and
# data/processed/activity_treatment_dates.csv provides handle-based maturity
# dates (e.g. treat_50pct_peak = first month handle reaches 50% of the state's
# non-COVID peak, calibration capped 2024-12 by
# data_prep/build_panel_handle50_treatment.R).
#
# Recovery anchor R = 2021-09-01: first month never-treated ETS states'
# filings sustained >=95% of their 2016-2019 same-calendar-month baseline
# (robust to 90%/95%/100% thresholds; eviction panel unchanged by the refresh).
#
# Outputs (out_dir = output/cheap_power_sim/county_covidclean):
#   exposure_post_recovery_by_state.csv  (refreshed + handle50 columns)
#   -> feed 09_exposure_viz.R to refresh the figure
#
# Run from repo root:  Rscript analysis/cheap_sims/10_exposure_timing_update.R
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
source("utils/eviction_treatment_schedule.R")

R_MONTH <- as.Date("2021-09-01")
out_dir <- "output/cheap_power_sim/county_covidclean"

h <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
              show_col_types = FALSE) %>%
  transmute(state_abb = eviction_state_name_to_abb(State),
            month_date = floor_date(as.Date(month_date), "month"),
            handle = as.numeric(Handle)) %>%
  filter(!is.na(state_abb), !is.na(handle), handle > 0)
cat(sprintf("LSR handle: %d states, through %s\n",
            n_distinct(h$state_abb), format(max(h$month_date))))

sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE) %>%
  mutate(state_abb = eviction_state_name_to_abb(state)) %>%
  filter(!is.na(online_start_date), state_abb != "NV") %>%
  transmute(state_abb, g = as.Date(online_start_date))

act <- read_csv("data/processed/activity_treatment_dates.csv",
                show_col_types = FALSE) %>%
  transmute(state_abb, handle50_date = as.Date(treat_50pct_peak))

tab <- sched %>%
  left_join(h, by = "state_abb", relationship = "one-to-many") %>%
  filter(is.na(month_date) | month_date >= g) %>%
  group_by(state_abb, g) %>%
  summarise(n_mo = sum(!is.na(handle)),
            total_handle_bn = sum(handle, na.rm = TRUE) / 1e9,
            pct_post_recovery = ifelse(n_mo == 0, NA,
              100 * sum(handle[month_date > R_MONTH], na.rm = TRUE) /
                sum(handle, na.rm = TRUE)),
            .groups = "drop") %>%
  left_join(act, by = "state_abb") %>%
  mutate(
    class = case_when(g < as.Date("2020-03-01") ~ "pre-COVID",
                      g <= R_MONTH ~ "during COVID",
                      TRUE ~ "post-recovery"),
    handle50_class = case_when(
      is.na(handle50_date) ~ NA_character_,
      handle50_date <= R_MONTH ~ "matured before recovery",
      TRUE ~ "matured after recovery"),
    handle50_lag_mo = round(as.numeric(
      difftime(handle50_date, g, units = "days")) / 30.44)
  ) %>%
  arrange(g)

write_csv(tab, file.path(out_dir, "exposure_post_recovery_by_state.csv"))

cat("\n--- Exposure share after eviction recovery (Sep 2021), by state ---\n")
print(as.data.frame(tab %>% select(state_abb, g, class, pct_post_recovery,
                                   total_handle_bn, handle50_date,
                                   handle50_lag_mo, handle50_class)),
      row.names = FALSE, digits = 3)

cat("\n--- Counts ---\n")
print(table(tab$class))
cat("\nMarket maturity (handle first reaches 50% of non-COVID peak):\n")
print(table(tab$class, tab$handle50_class, useNA = "ifany"))

wt <- tab %>% filter(!is.na(pct_post_recovery)) %>%
  summarise(w = sum(pct_post_recovery / 100 * total_handle_bn) /
              sum(total_handle_bn))
cat(sprintf("\nDollar-weighted share of all online-era handle post-recovery: %.1f%%\n",
            100 * wt$w))
