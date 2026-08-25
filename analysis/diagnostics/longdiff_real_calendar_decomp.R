#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# WHAT DRIVES the cross-state SD of the real-calendar long difference?
#
# longdiff_era_variance.R measured sigma = 0.472 across never-online states for
# the design Ben wants: baseline 2017-01..2018-12 -> endpoint 2024-10..2025-09.
# That sigma sets the whole MDE (MDE-80 ~ 2.80 * sigma * sqrt(1/22 + 1/15)), so
# it is worth knowing whether it is SIGNAL (states genuinely recovered from the
# pandemic at very different rates) or ARTIFACT.
#
# The artifact to rule out first: the ETS state series is a sum over reporting
# counties, and the set of reporting counties can CHANGE between 2017-18 and
# 2024-25. If a state gains or loses counties, its total moves mechanically and
# the long difference picks up a coverage change, not an eviction change. This
# script rebuilds every state aggregate from a FIXED county set observed in
# every month of BOTH windows and re-measures sigma.
#
# Then it separates the remaining dispersion into:
#   - level vs rate  (log counts vs log filings per 1k renters)
#   - COVID-era vs generic drift (same widths at a pre-COVID placement)
#   - how much is carried by the few most extreme states
#
# Usage:  Rscript analysis/diagnostics/longdiff_real_calendar_decomp.R
# Output: output/longdiff_era_variance/real_calendar_decomp_{states,summary}.csv
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({ library(tidyverse); library(lubridate); library(glue) })
theme_set(theme_minimal())

OUT_DIR <- "output/longdiff_era_variance"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

source("utils/eviction_treatment_schedule.R")

BASE <- c(as.Date("2017-01-01"), as.Date("2018-12-01"))   # 24 months
ENDP <- c(as.Date("2024-10-01"), as.Date("2025-09-01"))   # 12 months
# Pre-COVID placebo at the same widths, the longest distance the panel allows.
BASE_PC <- c(as.Date("2016-01-01"), as.Date("2016-12-01"))
ENDP_PC <- c(as.Date("2019-01-01"), as.Date("2019-12-01"))

fips_xwalk <- tibble(
  state_fips = c(1L,2L,4L,5L,6L,8L,9L,10L,11L,12L,13L,15L,16L,17L,18L,19L,20L,
                 21L,22L,23L,24L,25L,26L,27L,28L,29L,30L,31L,32L,33L,34L,35L,
                 36L,37L,38L,39L,40L,41L,42L,44L,45L,46L,47L,48L,49L,50L,51L,
                 53L,54L,55L,56L),
  state_abb  = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI",
                 "ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN",
                 "MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH",
                 "OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA",
                 "WV","WI","WY"))

ever_online <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date") %>%
  filter(!is.na(treat_start)) %>% pull(state_abb)

cty <- read_csv("data/raw/monthly_county_data_download.csv",
                show_col_types = FALSE) %>%
  mutate(month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count)) %>%
  transmute(state_abb, fips = as.character(fips), month_date,
            filings = as.numeric(filings_count),
            renters = as.numeric(renter_occupied_housing_units))

never_online <- setdiff(unique(cty$state_abb), ever_online)

n_months <- function(w) interval(w[1], w[2]) %/% months(1) + 1L

#' State-level long difference, either as-reported or on a fixed county set
long_diff <- function(dat, base, endp, fixed_counties) {
  nb <- n_months(base); ne <- n_months(endp)
  d <- dat %>%
    mutate(win = case_when(
      month_date >= base[1] & month_date <= base[2] ~ "base",
      month_date >= endp[1] & month_date <= endp[2] ~ "endp",
      TRUE ~ NA_character_)) %>%
    filter(!is.na(win))

  if (fixed_counties) {
    # Keep only counties observed in EVERY month of BOTH windows, so a state's
    # aggregate is a constant basket across the two windows.
    ok <- d %>% count(fips, win) %>%
      pivot_wider(names_from = win, values_from = n, values_fill = 0) %>%
      filter(base == nb, endp == ne) %>% pull(fips)
    d <- d %>% filter(fips %in% ok)
  }

  st <- d %>% group_by(state_abb, win, month_date) %>%
    summarise(filings = sum(filings), renters = sum(renters, na.rm = TRUE),
              n_cty = n(), .groups = "drop")

  # A state qualifies only if it has the full month complement in both windows.
  qual <- st %>% count(state_abb, win) %>%
    pivot_wider(names_from = win, values_from = n, values_fill = 0) %>%
    filter(base == nb, endp == ne) %>% pull(state_abb)

  st %>% filter(state_abb %in% qual) %>%
    group_by(state_abb, win) %>%
    summarise(y_log  = mean(log1p(filings)),
              y_rate = mean(log(filings / pmax(renters, 1) * 1000 + 0.01)),
              n_cty  = mean(n_cty), .groups = "drop") %>%
    pivot_wider(names_from = win, values_from = c(y_log, y_rate, n_cty)) %>%
    mutate(dY_log  = y_log_endp - y_log_base,
           dY_rate = y_rate_endp - y_rate_base,
           cty_ratio = n_cty_endp / n_cty_base)
}

summarise_sigma <- function(x, label) {
  tibble(spec = label, n_states = nrow(x),
         sd_log = sd(x$dY_log), sd_rate = sd(x$dY_rate),
         mad_log = mad(x$dY_log),
         sd_log_drop2 = {
           o <- order(abs(x$dY_log - median(x$dY_log)), decreasing = TRUE)
           sd(x$dY_log[-o[1:2]])
         },
         mean_cty_ratio = mean(x$cty_ratio),
         min_cty_ratio = min(x$cty_ratio), max_cty_ratio = max(x$cty_ratio))
}

dat_no <- cty %>% filter(state_abb %in% never_online)

as_reported <- long_diff(dat_no, BASE, ENDP, fixed_counties = FALSE)
fixed_basket <- long_diff(dat_no, BASE, ENDP, fixed_counties = TRUE)
precovid     <- long_diff(dat_no, BASE_PC, ENDP_PC, fixed_counties = TRUE)

summ <- bind_rows(
  summarise_sigma(as_reported,  "real calendar, as-reported counties"),
  summarise_sigma(fixed_basket, "real calendar, FIXED county basket"),
  summarise_sigma(precovid,     "pre-COVID placebo (2016 -> 2019), fixed basket")
)

states_out <- bind_rows(
  as_reported  %>% mutate(spec = "as_reported"),
  fixed_basket %>% mutate(spec = "fixed_basket"),
  precovid     %>% mutate(spec = "precovid")
) %>% select(spec, state_abb, dY_log, dY_rate, n_cty_base, n_cty_endp, cty_ratio)

write_csv(states_out, file.path(OUT_DIR, "real_calendar_decomp_states.csv"))
write_csv(summ,       file.path(OUT_DIR, "real_calendar_decomp_summary.csv"))

cat("\n===== SIGMA DECOMPOSITION =====\n")
print(as.data.frame(summ), digits = 3)
cat("\n===== PER-STATE long differences, real calendar =====\n")
print(as.data.frame(
  as_reported %>% select(state_abb, dY_log, dY_rate, n_cty_base, n_cty_endp,
                         cty_ratio) %>% arrange(dY_log)), digits = 3)
cat("\n===== same states, FIXED county basket =====\n")
print(as.data.frame(
  fixed_basket %>% select(state_abb, dY_log, dY_rate, n_cty_base, n_cty_endp) %>%
    arrange(dY_log)), digits = 3)
cat("\nIn filings terms, exp(dY_log) - 1 is the proportional change from the\n",
    "2017-18 baseline to the 2024-25 endpoint.\n", sep = "")
