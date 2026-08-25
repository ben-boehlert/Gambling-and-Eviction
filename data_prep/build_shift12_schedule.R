################################################################################
# build_shift12_schedule.R
#
# shift12 treatment definition: online launch + 12 months, uniformly.
#
# WHY THIS EXISTS (2026-08-21). The ramp75 definition dates each state by when
# its handle reaches 75% of its own PEAK handle, where "peak" is the maximum
# OBSERVED month. That makes the treatment date a function of how long we have
# watched the state: the measured ramp75 lag past launch correlates 0.957 with
# months of post-launch handle data (slope 0.257 months of lag per month of
# observation, t = 17.4). Median lag by observation window: <2yr 0.0mo,
# 2-4yr 10.1, 4-6yr 18.0, 6yr+ 22.0. Because observation length is a
# deterministic function of launch date, ramp75 redates EARLY cohorts later and
# LATE cohorts earlier -- distorting event time along exactly the cohort
# dimension a staggered DiD identifies from. It is also a blindness violation:
# handle is post-treatment and outcome-adjacent.
#
# shift12 has none of that. It is a fixed, pre-specifiable lag requiring zero
# outcome data, and it is defined for every state with an online launch.
#
# It is NOT a substitute for ramp75 on timing: ramp75's median lag is ~18
# months, shift12's is 12 by construction. The point of running it is to test
# whether ramse75's size-gate advantage over raw online dating comes from the
# LAG or from the handle-specific timing.
################################################################################

suppressPackageStartupMessages(library(tidyverse))
library(lubridate)

IN  <- "data/raw/sports_gambling_legalization_dates.csv"
OUT <- "data/processed/shift12_schedule.csv"
SHIFT_MONTHS <- 12L

raw <- read_csv(IN, show_col_types = FALSE)

sched <- raw %>%
  transmute(
    state,
    first_start_date  = as.Date(first_start_date),
    online_start_date = as.Date(online_start_date),
    shift12_start_date = if_else(is.na(online_start_date), as.Date(NA),
                                 online_start_date %m+% months(SHIFT_MONTHS))
  )

# Mirror the ramp75 schedule's shape exactly so the loader path is identical.
ramp <- read_csv("data/processed/ramp75_schedule.csv", show_col_types = FALSE)
stopifnot(
  identical(sort(sched$state), sort(ramp$state)),
  nrow(sched) == nrow(ramp),
  # every state with an online date gets a shift12 date, and it is exactly +12mo
  all(is.na(sched$shift12_start_date) == is.na(sched$online_start_date)),
  all(interval(sched$online_start_date, sched$shift12_start_date) %/% months(1) == SHIFT_MONTHS,
      na.rm = TRUE)
)

write_csv(sched, OUT)
cat("wrote", OUT, "|", nrow(sched), "states |",
    sum(!is.na(sched$shift12_start_date)), "with a shift12 date\n\n")

cmp <- sched %>%
  select(state, online_start_date, shift12_start_date) %>%
  inner_join(ramp %>% select(state, ramp75_start_date), by = "state") %>%
  filter(!is.na(online_start_date), !is.na(ramp75_start_date)) %>%
  mutate(ramp_lag = interval(online_start_date, ramp75_start_date) %/% months(1))
cat("ramp75 lag vs the uniform 12: median", median(cmp$ramp_lag),
    "| ramp75 EARLIER than shift12 for", sum(cmp$ramp_lag < 12), "of", nrow(cmp), "states\n")
