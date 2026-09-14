# =============================================================================
# state_pre_post_month_budget.R  (2026-09-14)
#
# Per-state month budget around online legalization: how many observed months
# each state has BEFORE and AFTER its launch, and whether that is enough for
# the clean-anchor design.
#
# "Observed" = present in the panel AFTER the COVID drop (2020-03..2021-07),
# because that is what the estimator actually sees. Raw counts are shown
# alongside so the COVID cost is visible per state.
#
# Design thresholds flagged:
#   baseline : all 6 CALENDAR months [L-6, L-1] must survive (strict PMD=6)
#   outcome  : months in [L+12, L+24] that survive (13 = full window)
#
# Descriptive only: blindness-safe.
# Output: output/state_month_budget/state_pre_post_months.csv
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
EXCL <- c("NV","ID","HI","MS")
OUT <- "output/state_month_budget"; dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  mutate(month_date = as.Date(month_date))
ab <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",
  Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",`New Hampshire`="NH",Illinois="IL",
  Michigan="MI",Colorado="CO",`District of Columbia`="DC",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Wyoming="WY",Connecticut="CT",Louisiana="LA",Maryland="MD",
  Kansas="KS",Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",
  Missouri="MO",Mississippi="MS",Montana="MT",`North Dakota`="ND",`New Mexico`="NM",
  `South Dakota`="SD",Washington="WA",Wisconsin="WI")
launch <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
  transmute(state_abb = ab[state], L = as.Date(online_start_date)) %>% filter(!is.na(state_abb))

raw <- split(pan$month_date, pan$state_abb)
liv <- pan %>% filter(month_date < CS | month_date > CE) %>% { split(.$month_date, .$state_abb) }

tab <- tibble(state_abb = sort(unique(pan$state_abb))) %>%
  left_join(launch, by="state_abb") %>%
  rowwise() %>%
  mutate(
    total_raw  = length(raw[[state_abb]]),
    total_live = length(liv[[state_abb]]),
    covid_lost = total_raw - total_live,
    pre_raw    = if (is.na(L)) NA_integer_ else sum(raw[[state_abb]] <  L),
    pre_live   = if (is.na(L)) NA_integer_ else sum(liv[[state_abb]] <  L),
    post_raw   = if (is.na(L)) NA_integer_ else sum(raw[[state_abb]] >= L),
    post_live  = if (is.na(L)) NA_integer_ else sum(liv[[state_abb]] >= L),
    base6      = if (is.na(L)) NA_integer_ else
      sum(seq(L %m-% months(6), by="month", length.out=6) %in% liv[[state_abb]]),
    out1224    = if (is.na(L)) NA_integer_ else
      sum(seq(L %m+% months(12), L %m+% months(24), by="month") %in% liv[[state_abb]])
  ) %>% ungroup() %>%
  mutate(status = case_when(
    state_abb %in% EXCL        ~ "excluded",
    is.na(L)                   ~ "control (no online date)",
    base6 < 6                  ~ "no baseline",
    out1224 == 0               ~ "no outcome",
    out1224 == 13              ~ "SWITCHER full",
    TRUE                       ~ "SWITCHER partial")) %>%
  arrange(is.na(L), L)

write_csv(tab, file.path(OUT, "state_pre_post_months.csv"))

fmt <- tab %>% transmute(
  st = state_abb,
  launch = if_else(is.na(L), "--", format(L, "%Y-%m")),
  `pre(raw)` = pre_raw, `pre(live)` = pre_live,
  `post(raw)` = post_raw, `post(live)` = post_live,
  `covid lost` = covid_lost, `base 6/6` = base6, `out /13` = out1224, status)
print(as.data.frame(fmt), row.names = FALSE, na.print = "--")
cat(glue("\nlive = after the COVID drop (2020-03..2021-07), which is what the estimator sees\n"))
cat(glue("wrote {OUT}/state_pre_post_months.csv\n"))
