# =============================================================================
# straddle_vs_monthnoise.R  (2026-09-14)
#
# Apples-to-apples: does an EARLIER COVID end contaminate the estimate more or
# less than the STRADDLE CELLS it eliminates?
#
# THE KEY INSIGHT. The estimator's unit is dy = Y[outcome] - B[baseline], a
# LONG DIFFERENCE. So a state's PERSISTENT suppression level cancels -- exactly
# like a unit fixed effect. What survives is the CHANGE in a state's
# suppression between its baseline window and its outcome window, and the
# cross-state SD of that change is the contamination that actually reaches the
# estimate. That is the same object `covid_trend_parallelism` reports for
# straddle cells (0.292 at h=18, 0.350 at h=24), so the two are comparable.
#
# Deviation = each state-month's log filings minus its own 2017-19
# same-calendar-month norm (removes state level and seasonality).
#
# Descriptive only: blindness-safe.
# Output: output/covid_end_sweep/straddle_vs_monthnoise.csv
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
EXCL <- c("NV","ID","HI","MS"); CS <- as.Date("2020-03-01")
OUT <- "output/covid_end_sweep"; dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  mutate(month_date=as.Date(month_date), y=log1p(filings_count)) %>% filter(!state_abb %in% EXCL)
norm <- pan %>% filter(year(month_date) %in% 2017:2019) %>%
  group_by(state_abb, m=month(month_date)) %>%
  summarise(y_norm=mean(y), n=n(), .groups="drop") %>% filter(n>=2)
dev <- pan %>% mutate(m=month(month_date)) %>% inner_join(norm, by=c("state_abb","m")) %>%
  transmute(state_abb, month_date, dev = y - y_norm)
D <- dev %>% { split(setNames(.$dev, format(.$month_date,"%Y-%m")), .$state_abb) }

ab <- c(Delaware="DE",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",Arkansas="AR",
  `New York`="NY",Indiana="IN",`New Hampshire`="NH",Colorado="CO",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Connecticut="CT",Louisiana="LA",Maryland="MD",Kansas="KS",
  Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",Missouri="MO")
L <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
  transmute(st=ab[state], L=as.Date(online_start_date)) %>% filter(!is.na(st), !is.na(L))
raw_obs <- split(pan$month_date, pan$state_abb)
key <- function(d) format(d, "%Y-%m")
mdev <- function(s, months) { v <- D[[s]][key(months)]; v <- v[!is.na(v)]
                              if (!length(v)) NA_real_ else mean(v) }

# For a given COVID end: which states are switchers, and what is the
# baseline->outcome suppression DRIFT for each?
arm <- function(end, gap_tolerant = FALSE) {
  CE <- as.Date(end)
  obs <- map(raw_obs, ~ .x[.x < CS | .x > CE])
  map_dfr(seq_len(nrow(L)), function(i) {
    s <- L$st[i]; l <- L$L[i]
    if (!s %in% names(obs)) return(NULL)
    bwin <- seq(l %m-% months(6), by="month", length.out=6)
    if (gap_tolerant) {                       # last 6 OBSERVED pre-launch months
      pre <- sort(obs[[s]][obs[[s]] < l]); if (length(pre) < 6) return(NULL)
      bwin <- tail(pre, 6)
    } else if (!all(bwin %in% obs[[s]])) return(NULL)
    owin <- seq(l %m+% months(12), l %m+% months(24), by="month")
    owin <- owin[owin %in% obs[[s]]]; if (!length(owin)) return(NULL)
    tibble(st=s, n_out=length(owin),
           base_dev=mdev(s,bwin), out_dev=mdev(s,owin),
           drift = mdev(s,owin) - mdev(s,bwin),
           base_in_covid = any(bwin >= CS & bwin <= as.Date("2021-07-31")))
  })
}

cat("Contamination that actually reaches dy = Y[outcome] - B[baseline]\n")
cat("  (persistent state-level suppression CANCELS in a long difference;\n")
cat("   what survives is cross-state SD of the baseline->outcome DRIFT)\n\n")
cat(sprintf("%-34s %7s %6s %9s %9s\n", "arm", "switch", "full", "SD(drift)", "vs MDE"))
rows <- list()
for (cfg in list(list(e="2021-07-31", g=FALSE, lab="CURRENT: drop..2021-07, strict"),
                 list(e="2021-07-31", g=TRUE,  lab="STRADDLE: drop..2021-07, gap-tol"),
                 list(e="2020-12-31", g=FALSE, lab="SHORTER: drop..2020-12, strict"),
                 list(e="2020-09-30", g=FALSE, lab="SHORTER: drop..2020-09, strict"),
                 list(e="2020-06-30", g=FALSE, lab="SHORTER: drop..2020-06, strict"))) {
  a <- arm(cfg$e, cfg$g) %>% filter(is.finite(drift))
  sd_d <- sd(a$drift)
  cat(sprintf("%-34s %7d %6d %9.3f %8.1fx\n", cfg$lab, nrow(a), sum(a$n_out==13), sd_d, sd_d/0.127))
  rows[[length(rows)+1]] <- tibble(arm=cfg$lab, end=cfg$e, gap_tolerant=cfg$g,
                                   switchers=nrow(a), full=sum(a$n_out==13), sd_drift=sd_d)
}
write_csv(bind_rows(rows), file.path(OUT, "straddle_vs_monthnoise.csv"))
cat("\nBenchmark: covid_trend_parallelism straddle contamination 0.292 (h=18), 0.350 (h=24)\n")
