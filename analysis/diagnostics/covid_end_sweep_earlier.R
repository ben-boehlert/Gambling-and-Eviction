# =============================================================================
# covid_end_sweep_earlier.R  (2026-09-14)
#
# Sweeps the COVID drop END date EARLIER than the current 2021-07-31.
#
# WHY THIS DIRECTION IS NEW. `covid_trend_parallelism` (2026-09-03) swept the
# COVID end 2021-07 -> 2022-06 -- LATER only. Later ends shrink straddle-cell
# contamination but cost clean treated states. EARLIER ends work by a different
# mechanism: they do not make straddle cells cleaner, they CONVERT straddle
# cells into ordinary contiguous cells by keeping the months. So the existing
# sweep does not speak to this direction, and slope-drift is not the live
# objection -- moratorium suppression is.
#
# THE COST MEASURE. A national moratorium that suppressed filings EQUALLY
# everywhere is absorbed by time fixed effects and costs nothing. What cannot
# be absorbed is CROSS-STATE VARIANCE in suppression within a month. So for
# every month we compute each state's log deviation from its own pre-COVID
# same-calendar-month norm (2017-2019), then report:
#   mean_dev : common suppression  -> absorbed by time FE, mostly harmless
#   sd_dev   : cross-state spread  -> NOT absorbed, this is the real cost
#
# Benefit measure: switchers / full-window switchers / outcome-months gained.
#
# Descriptive only: blindness-safe.
# Output: output/covid_end_sweep/
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
EXCL <- c("NV","ID","HI","MS"); CS <- as.Date("2020-03-01")
OUT <- "output/covid_end_sweep"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), y = log1p(filings_count)) %>%
  filter(!state_abb %in% EXCL)

# Pre-COVID same-calendar-month norm, per state (2017-2019)
norm <- pan %>% filter(year(month_date) %in% 2017:2019) %>%
  group_by(state_abb, m = month(month_date)) %>%
  summarise(y_norm = mean(y), n_norm = n(), .groups = "drop") %>% filter(n_norm >= 2)

dev <- pan %>% mutate(m = month(month_date)) %>%
  inner_join(norm, by = c("state_abb","m")) %>%
  mutate(dev = y - y_norm) %>%
  filter(month_date >= as.Date("2020-01-01"), month_date <= as.Date("2022-06-01"))

bym <- dev %>% group_by(month_date) %>%
  summarise(n_states = n(), mean_dev = mean(dev), sd_dev = sd(dev), .groups = "drop")
write_csv(bym, file.path(OUT, "monthly_suppression.csv"))

cat("Suppression by month (log deviation from each state's own 2017-19 norm)\n")
cat("  mean = common shock (time FE absorbs it) | sd = cross-state spread (it does NOT)\n\n")
cat(sprintf("%-10s %8s %9s %8s\n", "month", "n", "mean", "sd"))
bym %>% filter(month_date <= as.Date("2021-12-01")) %>% pwalk(function(month_date, n_states, mean_dev, sd_dev)
  cat(sprintf("%-10s %8d %9.3f %8.3f%s\n", format(month_date, "%Y-%m"), n_states, mean_dev, sd_dev,
              if (month_date == as.Date("2021-07-01")) "   <- current drop ends here" else "")))

# ---- benefit side ----------------------------------------------------------
ab <- c(Delaware="DE",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",Arkansas="AR",
  `New York`="NY",Indiana="IN",`New Hampshire`="NH",Colorado="CO",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Connecticut="CT",Louisiana="LA",Maryland="MD",Kansas="KS",
  Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",Missouri="MO")
L <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  transmute(st = ab[state], L = as.Date(online_start_date)) %>% filter(!is.na(st), !is.na(L))
raw_obs <- split(pan$month_date, pan$state_abb)

ENDS <- c("2020-06-30","2020-09-30","2020-12-31","2021-01-31","2021-03-31","2021-07-31")
cat("\n\nCOST vs BENEFIT by COVID end date\n")
cat(sprintf("%-14s %7s %6s %7s | %7s %8s %8s\n",
            "drop ends", "switch", "full", "out-mo", "months", "mean|dev|", "max sd"))
res <- map_dfr(ENDS, function(e) {
  CE <- as.Date(e)
  obs <- map(raw_obs, ~ .x[.x < CS | .x > CE])
  sw <- L %>% rowwise() %>% mutate(
      base = sum(seq(L %m-% months(6), by="month", length.out=6) %in% obs[[st]]),
      out  = sum(seq(L %m+% months(12), L %m+% months(24), by="month") %in% obs[[st]])) %>%
    ungroup() %>% filter(base == 6, out > 0)
  kept <- bym %>% filter(month_date >= CS, month_date <= as.Date("2021-07-01"), month_date > CE)
  tibble(ends = e, switchers = nrow(sw), full = sum(sw$out == 13), out_months = sum(sw$out),
         kept_months = nrow(kept),
         mean_abs_dev = if (nrow(kept)) mean(abs(kept$mean_dev)) else 0,
         max_sd = if (nrow(kept)) max(kept$sd_dev) else 0)
})
pwalk(res, function(ends, switchers, full, out_months, kept_months, mean_abs_dev, max_sd)
  cat(sprintf("%-14s %7d %6d %7d | %7d %8.3f %8.3f%s\n", ends, switchers, full, out_months,
              kept_months, mean_abs_dev, max_sd,
              if (ends == "2021-07-31") "   <- CURRENT" else "")))
write_csv(res, file.path(OUT, "covid_end_cost_benefit.csv"))
cat(glue("\nStraddle-cell benchmark for comparison: per-state contamination 0.350 at h=24 ",
         "(covid_trend_parallelism, 2026-09-03), ~2.8x the 0.127 MDE.\n"))
