#!/usr/bin/env Rscript
# Monthly adult (18+) population by state, 2018-2026, for per-capita handle.
# Source: ACS 1-year, table B09021_001 (population 18 years and over).
# 2020 ACS1 was not released (COVID); we interpolate through it.
# Post-2023 months are extrapolated on the 2021-2023 log-linear trend.
#
# Usage: Rscript analysis/exploratory/build_state_population.R
# Output: data/processed/state_adult_population_monthly.csv

library(tidyverse)
library(tidycensus)

YEARS   <- c(2018, 2019, 2021, 2022, 2023)   # 2020 ACS1 not released
OUT     <- "data/processed/state_adult_population_monthly.csv"
MONTHS  <- seq(as.Date("2018-01-01"), as.Date("2026-12-01"), by = "month")

acs <- map_dfr(YEARS, function(y) {
  get_acs(geography = "state", variables = c(pop18 = "B09021_001"),
          year = y, survey = "acs1", cache_table = TRUE) %>%
    transmute(State = NAME, year = y, pop18 = estimate)
})

cat(sprintf("ACS pulled: %d states x %d years\n",
            n_distinct(acs$State), n_distinct(acs$year)))

# Log-linear interpolation within observed years; extrapolate the tail on the
# 2021-2023 slope (post-2020 migration patterns differ from 2018-19).
pop_monthly <- acs %>%
  group_by(State) %>%
  group_modify(function(d, key) {
    d <- arrange(d, year)
    yr_num <- d$year + 0.5                      # ACS1 ~ mid-year
    lp <- log(d$pop18)
    tail_slope <- (lp[d$year == 2023] - lp[d$year == 2021]) / 2

    t <- as.numeric(format(MONTHS, "%Y")) +
         (as.numeric(format(MONTHS, "%m")) - 0.5) / 12

    out <- approx(yr_num, lp, xout = t, rule = 1)$y   # NA outside range
    last_t <- max(yr_num); last_v <- lp[which.max(yr_num)]
    first_t <- min(yr_num); first_v <- lp[which.min(yr_num)]
    out[t > last_t]  <- last_v  + tail_slope * (t[t > last_t] - last_t)
    out[t < first_t] <- first_v + tail_slope * (t[t < first_t] - first_t)

    tibble(month_date = MONTHS, pop18 = exp(out))
  }) %>%
  ungroup()

stopifnot(!anyNA(pop_monthly$pop18), !anyDuplicated(pop_monthly[c("State", "month_date")]))

write_csv(pop_monthly, OUT)
cat(sprintf("Wrote %s (%d rows, %d states)\n", OUT, nrow(pop_monthly),
            n_distinct(pop_monthly$State)))
