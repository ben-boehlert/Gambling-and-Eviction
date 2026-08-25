#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# How long until a state's legal sports-betting regime is "established"?
#
# Improves on analysis/exploratory/quintile_timing_analysis.R in three ways:
#   1. Seasonality. Monthly handle is dominated by the NFL calendar (Sep-Jan).
#      "Months to X% of peak month" is partly a statement about when the first
#      football season lands. We use trailing-12-month handle (T12) and
#      year-over-year growth, both of which are seasonally neutral.
#   2. Right-censoring. Recent entrants (KY, ME, VT, NC, MO) cannot have
#      "matured" yet; their peak month is mechanically their last observed
#      month. We treat time-to-maturity as a survival outcome and use
#      Kaplan-Meier so censored states inform the estimate without biasing it.
#   3. Clock start. We report both clocks: first handle of any kind (retail
#      for retail-first states) and the online launch date, which is the
#      project's treatment date.
#
# Definition of "established" (primary): year-over-year growth in monthly
# handle falls below THRESH and stays there for 3 consecutive months. That is,
# the market has stopped expanding, whatever level it settled at.
#
# Secondary: trailing-12-month handle first reaches 80% of the state's plateau,
# where plateau = mean T12 over the final 12 observed months. Only defined for
# states with a credible plateau (>= 36 months of data and flat recent growth).
#
# Usage: Rscript analysis/exploratory/market_maturation_timing.R
# ─────────────────────────────────────────────────────────────────────────────

library(tidyverse)
library(survival)
library(zoo)

theme_set(theme_minimal())

OUT_DIR <- "output/market_maturation"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

THRESH_MAIN <- 0.15   # YoY growth below 15% = no longer expanding
THRESH_SENS <- c(0.10, 0.15, 0.25)
SUSTAIN     <- 3      # consecutive months below threshold
PLATEAU_SHR <- 0.80

# COVID sports shutdown: leagues suspended 2020-03, essentially back by 2020-08.
# Two consequences, both handled below:
#   (a) States whose first months overlap this window have a distorted ramp.
#   (b) YoY growth is meaningless whenever EITHER the current month or its
#       12-month base falls in the shutdown. Without masking, every 2018-19
#       entrant registers a spurious "maturity" in 2020-03 because handle
#       collapsed. These months are dropped from the maturity rule.
COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2020-08-01")

# ── Load ─────────────────────────────────────────────────────────────────────
handle <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
                   show_col_types = FALSE) %>%
  filter(!is.na(Handle), Handle > 0) %>%
  select(State, month_date, Handle) %>%
  arrange(State, month_date)

dates <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE) %>%
  select(State = state, online_start_date, retail_start_date, first_start_date)

end_of_sample <- max(handle$month_date)

cat(sprintf("Handle panel: %d states, %s to %s\n",
            n_distinct(handle$State),
            format(min(handle$month_date)), format(end_of_sample)))

# Fill internal month gaps so lag(12) is a true 12-month lag
panel <- handle %>%
  group_by(State) %>%
  complete(month_date = seq(min(month_date), max(month_date), by = "month")) %>%
  arrange(State, month_date) %>%
  mutate(
    first_handle_date = min(month_date),
    mo_since_first    = interval(first_handle_date, month_date) %/% months(1),
    t12               = rollapplyr(Handle, 12, sum, fill = NA, na.rm = FALSE),
    yoy               = Handle / lag(Handle, 12) - 1,
    yoy               = if_else(
      (month_date >= COVID_START & month_date <= COVID_END) |
      (month_date >= COVID_START + months(12) & month_date <= COVID_END + months(12)),
      NA_real_, yoy)
  ) %>%
  ungroup() %>%
  left_join(dates, by = "State") %>%
  mutate(
    mo_since_online = if_else(is.na(online_start_date), NA_integer_,
                              interval(online_start_date, month_date) %/% months(1)),
    covid_launch    = first_handle_date >= COVID_START - months(6) &
                      first_handle_date <= COVID_END
  )

# ── Maturity date under the growth-stabilization rule ────────────────────────
# First month at which YoY growth has been below `thresh` for `sustain`
# CONSECUTIVE CALENDAR months. The run resets across COVID-masked months, so a
# gap cannot be bridged to manufacture a sustained run.
maturity_date <- function(d, thresh, sustain = SUSTAIN, from = NULL) {
  d <- d %>% arrange(month_date)
  if (!is.null(from) && !is.na(from)) d <- d %>% filter(month_date >= from)
  if (nrow(d) < sustain) return(as.Date(NA))
  run <- 0L
  for (i in seq_len(nrow(d))) {
    contiguous <- i > 1 &&
      interval(d$month_date[i - 1], d$month_date[i]) %/% months(1) == 1
    ok <- !is.na(d$yoy[i]) && d$yoy[i] < thresh
    run <- if (ok && (contiguous || run == 0L)) run + 1L else if (ok) 1L else 0L
    if (run >= sustain) return(d$month_date[i - sustain + 1L])
  }
  as.Date(NA)
}

state_rows <- panel %>%
  group_by(State) %>%
  group_modify(function(d, key) {
    base <- tibble(
      first_handle_date = d$first_handle_date[1],
      online_start_date = d$online_start_date[1],
      retail_first      = !is.na(d$retail_start_date[1]) &
                          !is.na(d$online_start_date[1]) &
                          d$retail_start_date[1] < d$online_start_date[1],
      covid_launch      = d$covid_launch[1],
      n_months          = sum(!is.na(d$Handle)),
      last_obs          = max(d$month_date[!is.na(d$Handle)])
    )
    for (th in THRESH_SENS) {
      base[[sprintf("mat_%02d", round(th * 100))]] <- maturity_date(d, th)
      # Online clock: search only months at or after the online launch, so a
      # retail plateau years before online (DE, AR, NY) is not counted.
      base[[sprintf("matonl_%02d", round(th * 100))]] <-
        maturity_date(d, th, from = d$online_start_date[1])
    }
    base
  }) %>%
  ungroup()

# Time-to-event on each clock, with censoring at end of sample
add_survival <- function(df, col, clock_start) {
  mat <- df[[col]]
  start <- df[[clock_start]]
  tibble(
    time  = if_else(!is.na(mat),
                    interval(start, mat) %/% months(1),
                    interval(start, df$last_obs) %/% months(1)),
    event = as.integer(!is.na(mat))
  )
}

surv_tbl <- function(df, col, clock_start, label) {
  s <- add_survival(df, col, clock_start)
  d <- bind_cols(df %>% select(State), s) %>% filter(time >= 0)
  fit <- survfit(Surv(time, event) ~ 1, data = d)
  q <- quantile(fit, probs = c(0.25, 0.5, 0.75))
  tibble(
    spec      = label,
    n_states  = nrow(d),
    n_matured = sum(d$event),
    n_censored= sum(d$event == 0),
    p25       = q$quantile[[1]],
    median    = q$quantile[[2]],
    median_lo = q$lower[[2]],
    median_hi = q$upper[[2]],
    p75       = q$quantile[[3]]
  )
}

analysis_set <- state_rows %>% filter(n_months >= 13)  # need one YoY obs

res <- bind_rows(
  lapply(THRESH_SENS, function(th) {
    col <- sprintf("mat_%02d", round(th * 100))
    bind_rows(
      surv_tbl(analysis_set, col, "first_handle_date",
               sprintf("YoY<%d%%, clock = first handle", round(th * 100))),
      surv_tbl(analysis_set %>% filter(!is.na(online_start_date)),
               sprintf("matonl_%02d", round(th * 100)),
               "online_start_date",
               sprintf("YoY<%d%%, clock = online launch", round(th * 100)))
    )
  })
)

# Excluding COVID-distorted launches
res_nocovid <- bind_rows(
  lapply(THRESH_SENS, function(th) {
    col <- sprintf("mat_%02d", round(th * 100))
    surv_tbl(analysis_set %>% filter(!covid_launch), col, "first_handle_date",
             sprintf("YoY<%d%%, clock = first handle, excl. COVID launches",
                     round(th * 100)))
  })
)

# Retail-first vs online-at-launch
res_split <- bind_rows(
  surv_tbl(analysis_set %>% filter(retail_first), sprintf("mat_%02d", THRESH_MAIN * 100),
           "first_handle_date", "YoY<15%, retail-first states"),
  surv_tbl(analysis_set %>% filter(!retail_first), sprintf("mat_%02d", THRESH_MAIN * 100),
           "first_handle_date", "YoY<15%, online-at-launch states")
)

# ── Secondary: months to 80% of plateau (T12 basis) ──────────────────────────
plateau_tbl <- panel %>%
  filter(!is.na(Handle)) %>%
  group_by(State) %>%
  filter(n() >= 36) %>%
  group_modify(function(d, key) {
    plateau <- mean(tail(d$t12[!is.na(d$t12)], 12))
    hit <- d %>% filter(!is.na(t12), t12 >= PLATEAU_SHR * plateau) %>% slice(1)
    tibble(
      plateau_bn   = plateau / 1e9,
      mo_to_80pct  = if (nrow(hit)) hit$mo_since_first[1] else NA_integer_,
      mo_to_80_onl = if (nrow(hit)) hit$mo_since_online[1] else NA_integer_,
      still_growing = tail(d$yoy[!is.na(d$yoy)], 1) > THRESH_MAIN
    )
  }) %>%
  ungroup()

# ── Report ───────────────────────────────────────────────────────────────────
sink(file.path(OUT_DIR, "maturation_summary.txt"), split = TRUE)

cat("\n=== TIME TO AN ESTABLISHED MARKET (Kaplan-Meier, months) ===\n")
cat("Event = YoY handle growth below threshold for 3 consecutive months.\n")
cat(sprintf("Sample ends %s; states not yet matured are right-censored.\n\n",
            format(end_of_sample)))
print(res %>% mutate(across(where(is.numeric), ~round(., 1))), n = 30)

cat("\n=== SENSITIVITY: excluding COVID-window launches ===\n")
print(res_nocovid %>% mutate(across(where(is.numeric), ~round(., 1))), n = 20)

cat("\n=== BY LAUNCH TYPE (threshold 15%, clock = first handle) ===\n")
print(res_split %>% mutate(across(where(is.numeric), ~round(., 1))), n = 20)

cat("\n=== PER-STATE MATURITY (threshold 15%) ===\n")
per_state <- analysis_set %>%
  mutate(
    mat     = .data[[sprintf("mat_%02d", THRESH_MAIN * 100)]],
    mat_onl = .data[[sprintf("matonl_%02d", THRESH_MAIN * 100)]],
    mo_from_first  = interval(first_handle_date, mat) %/% months(1),
    mo_from_online = interval(online_start_date, mat_onl) %/% months(1),
    status = if_else(is.na(mat), "still growing", "matured")
  ) %>%
  select(State, first_handle_date, online_start_date, retail_first,
         mat, mo_from_first, mat_onl, mo_from_online, n_months, status) %>%
  arrange(status, mo_from_first)
print(per_state, n = 40)

cat("\n=== MONTHS TO 80% OF PLATEAU (trailing-12 basis, >=36 mo states) ===\n")
print(plateau_tbl %>% mutate(across(where(is.numeric), ~round(., 1))) %>%
        arrange(mo_to_80pct), n = 40)
cat(sprintf("\n  Median months to 80%% of plateau (first-handle clock): %.1f\n",
            median(plateau_tbl$mo_to_80pct, na.rm = TRUE)))
cat(sprintf("  Median months to 80%% of plateau (online clock):       %.1f\n",
            median(plateau_tbl$mo_to_80_onl[plateau_tbl$mo_to_80_onl >= 0],
                   na.rm = TRUE)))
cat(sprintf("  States still growing >%.0f%% YoY at end of sample:      %d of %d\n",
            THRESH_MAIN * 100, sum(plateau_tbl$still_growing, na.rm = TRUE),
            nrow(plateau_tbl)))

sink()

write_csv(res, file.path(OUT_DIR, "km_summary.csv"))
write_csv(per_state, file.path(OUT_DIR, "per_state_maturity.csv"))
write_csv(plateau_tbl, file.path(OUT_DIR, "plateau_shares.csv"))

# ── Figures ──────────────────────────────────────────────────────────────────
km_d <- bind_cols(
  analysis_set %>% select(State),
  add_survival(analysis_set, sprintf("mat_%02d", THRESH_MAIN * 100),
               "first_handle_date")
)
fit <- survfit(Surv(time, event) ~ 1, data = km_d)
km_df <- tibble(time = fit$time, surv = fit$surv,
                lo = fit$lower, hi = fit$upper)

p1 <- ggplot(km_df, aes(time, 1 - surv)) +
  geom_ribbon(aes(ymin = 1 - hi, ymax = 1 - lo), alpha = 0.15) +
  geom_step(linewidth = 0.8) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "Months since first handle",
       y = "Share of states with an established market",
       subtitle = sprintf("Established = YoY handle growth < %d%% for 3 consecutive months; Kaplan-Meier, %d states",
                          round(THRESH_MAIN * 100), nrow(km_d)))
ggsave(file.path(OUT_DIR, "km_time_to_maturity.png"), p1,
       width = 8, height = 5, dpi = 150)

traj <- panel %>%
  filter(!is.na(t12)) %>%
  group_by(State) %>%
  mutate(plateau = mean(tail(t12, 12)), share = t12 / plateau) %>%
  ungroup()

p2 <- ggplot(traj, aes(mo_since_first, share, group = State)) +
  geom_line(alpha = 0.3) +
  stat_summary(aes(group = 1), fun = median, geom = "line",
               linewidth = 1.1, colour = "firebrick") +
  geom_hline(yintercept = PLATEAU_SHR, linetype = "dashed") +
  coord_cartesian(ylim = c(0, 1.6)) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "Months since first handle",
       y = "Trailing-12-month handle, share of current plateau",
       subtitle = "Grey = states; red = median across states; dashed = 80% of plateau")
ggsave(file.path(OUT_DIR, "t12_trajectories.png"), p2,
       width = 8, height = 5, dpi = 150)

cat(sprintf("\nWrote outputs to %s/\n", OUT_DIR))
