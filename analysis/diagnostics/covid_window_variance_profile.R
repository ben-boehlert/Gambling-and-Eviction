################################################################################
# analysis/diagnostics/covid_window_variance_profile.R
#
# How the COVID drop-window end changes (a) which states qualify as switchers
# under the inclusion rule and (b) how noisy the design is at the calendar
# positions those switchers occupy — separately in the BASELINE window
# [L-6, L-1] and in the OUTCOME window [L+12, L+24].
#
# BLIND-SAFE. Dispersion is measured across UNTREATED states only: the panel is
# the S2 blinded sample (every state truncated at its own anticipation-adjusted
# first_start), so a switcher's own post-launch months are never read. Each
# control state's "long difference" (outcome-window mean minus baseline mean) at
# a switcher's calendar position is a delta = 0 placebo, the same object the
# power framework's size gates use.
#
# Run from the project root:
#   Rscript analysis/diagnostics/covid_window_variance_profile.R
# Output: output/inclusion_rule/covid_window_variance_profile.csv (per switcher)
#         output/inclusion_rule/covid_window_variance_summary.csv (per window)
################################################################################
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(lubridate); library(readr); library(purrr)
})
source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/inclusion_rule.R")
source("R/power/load_blinded_panel.R")
source("utils/eviction_treatment_schedule.R")

K <- 7L; BUF <- 3L; PMD <- 6L
EXCL <- c("NV", "HI", "MS")   # ID included from 2026-09-17 (statewide A12 series, verified)           # matches inclusion_rule_real_switchers.R
COVID_START <- as.Date("2020-03-01")
WINDOW_ENDS <- as.Date(c("2021-06-30", "2021-07-31", "2022-01-31"))

mi <- function(d) year(d) * 12L + (month(d) - 1L)

# S2 blinded panel, COVID filter deferred so each window can be applied here.
cfgp <- read_power_config()
cfgp$schedule <- "data/processed/shift12_schedule.csv"
panel <- load_blinded_panel(level = "state", treat_def = "shift12_start_date",
                            sample = "S2", covid = "keep", config = cfgp) %>%
  filter(!state_abb %in% EXCL) %>%
  transmute(state_abb, m = mi(month_date), y = y_log1p)

# Coverage only (state_abb + month_date, no outcome column): the inclusion rule
# must be evaluated on the real series, since S2 truncates every switcher at its
# own launch and would leave it with no outcome window at all.
cover <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  col_select = c("state_abb", "month_date"), show_col_types = FALSE) %>%
  filter(!state_abb %in% EXCL) %>%
  transmute(state_abb, m = mi(floor_date(as.Date(month_date), "month")))

sched <- read_csv("data/processed/shift12_schedule.csv", show_col_types = FALSE)
sched$state_abb <- eviction_state_name_to_abb(sched$state)
sched <- sched %>%
  filter(!is.na(online_start_date), !state_abb %in% EXCL) %>%
  transmute(state_abb, L = mi(floor_date(as.Date(online_start_date), "month")))

profile_one <- function(end) {
  covid <- c(COVID_START, end)
  drop  <- mi(seq(floor_date(covid[1], "month"), floor_date(covid[2], "month"), by = "month"))
  excl  <- mi(splice_excluded_months(covid, BUF))
  obs   <- split(cover$m[!cover$m %in% drop], cover$state_abb[!cover$m %in% drop])
  pan   <- panel %>% filter(!m %in% drop)          # S2: untreated months only
  ymap  <- split(setNames(pan$y, pan$m), pan$state_abb)
  ctr   <- vapply(ymap, mean, numeric(1))   # state's own long-run clean level

  s <- sched %>% filter(state_abb %in% names(obs))
  pass <- vapply(seq_len(nrow(s)), function(i)
    switcher_inclusion_ok(obs[[s$state_abb[i]]], s$L[i], PMD, K, excluded = excl),
    logical(1))
  sw <- s[pass, , drop = FALSE]

  map_dfr(seq_len(nrow(sw)), function(i) {
    L  <- sw$L[i]
    B  <- (L - PMD):(L - 1L)                                  # baseline months
    O  <- switcher_usable_horizons(obs[[sw$state_abb[i]]], L, PMD,
                                   excluded = excl)$usable    # outcome months
    # Clean controls: untreated states observing the whole baseline and the
    # whole outcome set at this switcher's calendar position.
    obs_bl <- lapply(ymap, function(v) as.integer(names(v)))   # untreated months
    cand   <- setdiff(names(obs_bl), sw$state_abb[i])
    # STRICT: control observes the whole baseline and every outcome month.
    ctl_strict <- keep(cand, ~ all(B %in% obs_bl[[.x]]) && all(O %in% obs_bl[[.x]]))
    # ESTIMATOR-FAITHFUL: .re_lpdid forms one long difference per horizon, so a
    # control needs the baseline and at least K of the outcome months; its
    # outcome mean is taken over the months it actually has.
    ctl <- keep(cand, ~ all(B %in% obs_bl[[.x]]) && sum(O %in% obs_bl[[.x]]) >= K)
    if (length(ctl) < 2L)
      return(tibble(window_end = end, state_abb = sw$state_abb[i], n_ctl = length(ctl),
                    n_strict = length(ctl_strict), n_out = length(O),
                    sd_base = NA_real_, sd_out = NA_real_,
                    sd_ld = NA_real_, corr = NA_real_))
    # Deviations from each control state's OWN long-run clean level, so the
    # baseline and outcome dispersions are on a common reference and their
    # covariance (how much cancels in the difference) is interpretable.
    bm <- vapply(ctl, function(s2) mean(ymap[[s2]][as.character(B)]) - ctr[[s2]], numeric(1))
    om <- vapply(ctl, function(s2) {
      have <- O[O %in% obs_bl[[s2]]]
      mean(ymap[[s2]][as.character(have)]) - ctr[[s2]]
    }, numeric(1))
    tibble(window_end = end, state_abb = sw$state_abb[i], n_ctl = length(ctl),
           n_strict = length(ctl_strict), n_out = length(O),
           sd_base = sd(bm), sd_out = sd(om), sd_ld = sd(om - bm),
           corr = suppressWarnings(cor(bm, om)))
  })
}

res <- map_dfr(WINDOW_ENDS, profile_one)
dir.create("output/inclusion_rule", showWarnings = FALSE, recursive = TRUE)
write_csv(res, "output/inclusion_rule/covid_window_variance_profile.csv")

summ <- res %>% group_by(window_end) %>%
  summarise(n_switchers = n(), n_no_controls = sum(n_ctl < 2L),
            median_n_ctl = median(n_ctl), min_n_ctl = min(n_ctl),
            med_sd_base = median(sd_base, na.rm = TRUE),
            med_sd_out  = median(sd_out,  na.rm = TRUE),
            med_sd_ld   = median(sd_ld,   na.rm = TRUE),
            med_corr    = median(corr,    na.rm = TRUE), .groups = "drop")
write_csv(summ, "output/inclusion_rule/covid_window_variance_summary.csv")

cat("\n== Per-window summary (dispersion across clean untreated controls) ==\n")
print(as.data.frame(summ), row.names = FALSE, digits = 3)
cat("\n== Per switcher ==\n")
print(as.data.frame(res %>% arrange(window_end, state_abb)), row.names = FALSE, digits = 3)
