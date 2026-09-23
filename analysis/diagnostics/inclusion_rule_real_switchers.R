################################################################################
# analysis/diagnostics/inclusion_rule_real_switchers.R
#
# The REAL switcher set under the switcher inclusion rule (R/power/
# inclusion_rule.R; Ben's decision 2026-09-16: K = 7 usable outcome months in
# [launch+12, launch+24], 3-month splice buffer, strict 6-month pre-launch
# baseline). COVERAGE ONLY: reads state_abb + month_date from the state panel
# and the launch dates from the shift12 schedule; no outcome column is touched,
# so this is blind-safe. Its output is what the k7 power configs pass as
# `template_states`, so the simulation's D1 template asks only for cohorts the
# real analysis can actually identify.
#
# Output: output/inclusion_rule/real_switchers_k7_buf3.csv (one row per
# state with a launch date: launch, baseline_ok, n_usable, passes).
# Run from the project root:
#   Rscript analysis/diagnostics/inclusion_rule_real_switchers.R
################################################################################
suppressPackageStartupMessages({library(dplyr); library(lubridate); library(readr)})
source("R/power/inclusion_rule.R")
source("utils/eviction_treatment_schedule.R")

K <- as.integer(Sys.getenv("MIN_HORIZONS", "7"))
BUF <- as.integer(Sys.getenv("SPLICE_BUFFER", "3"))
PMD <- 6L
COVID <- as.Date(c("2020-03-01", "2021-07-31"))
EXCL <- c("NV", "HI", "MS")   # ID included from 2026-09-17 (statewide A12 series, verified)

mi <- function(d) year(d) * 12L + (month(d) - 1L)
cov <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                col_select = c("state_abb", "month_date"), show_col_types = FALSE) %>%
  mutate(month_date = floor_date(as.Date(month_date), "month")) %>%
  filter(!state_abb %in% EXCL,
         month_date < floor_date(COVID[1], "month") | month_date > floor_date(COVID[2], "month"))
obs <- split(mi(cov$month_date), cov$state_abb)

sched <- read_csv("data/processed/shift12_schedule.csv", show_col_types = FALSE)
sched$state_abb <- eviction_state_name_to_abb(sched$state)
sched <- sched %>% filter(!is.na(online_start_date), state_abb %in% names(obs)) %>%
  transmute(state_abb, launch = floor_date(as.Date(online_start_date), "month"))

excl <- mi(splice_excluded_months(COVID, BUF))
res <- sched %>% rowwise() %>% mutate(
  L = mi(launch),
  baseline_ok = switcher_usable_horizons(obs[[state_abb]], L, PMD, excluded = excl)$baseline_ok,
  n_usable    = switcher_usable_horizons(obs[[state_abb]], L, PMD, excluded = excl)$n_usable,
  passes      = switcher_inclusion_ok(obs[[state_abb]], L, PMD, K, excluded = excl)) %>%
  ungroup() %>% select(-L) %>% arrange(desc(passes), desc(n_usable), state_abb)
dir.create("output/inclusion_rule", showWarnings = FALSE, recursive = TRUE)
write_csv(res, sprintf("output/inclusion_rule/real_switchers_k%d_buf%d.csv", K, BUF))
cat(sprintf("K = %d, buffer = %d months: %d of %d launched states pass\n", K, BUF, sum(res$passes), nrow(res)))
print(as.data.frame(res), row.names = FALSE)
cat("\ntemplate_states: [", paste(res$state_abb[res$passes], collapse = ", "), "]\n")
