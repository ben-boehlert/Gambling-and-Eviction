#!/usr/bin/env Rscript
################################################################################
# eviction_stabilization_timing.R
#
# Question: when do state eviction filing series stop moving -- i.e. when does
# each state settle onto a flat, pre-COVID-volatility plateau after the pandemic
# disruption?  Answers the practical question of where the post-COVID window
# boundary should sit, instead of inheriting a legacy cutoff.
#
# Substrate: data/raw/state_month_panel_with_treatment.csv (rebuilt 2026-08-20,
# FIXED COUNTY BASKET -- so reporting-composition churn cannot masquerade as a
# level shift).  Counts, not rates: the renter denominator is annual and its
# steps would inject drift that has nothing to do with filings.
#
# Method, per state:
#   1. y = log(filings + 1)
#   2. Deseasonalize with month-of-year effects fit on PRE-COVID months only
#      (2016-01 .. 2020-02), so the pandemic cannot contaminate the seasonal.
#   3. Pre-COVID reference: baseline level b and residual SD sigma around a
#      linear trend over the same window.
#   4. Plateau onset = earliest month m (>= 2021-01) such that over [m, end]:
#        (a) |annualized trend| <= FLAT_TOL log points/year,
#        (b) trend slope not significant at 5%,
#        (c) residual SD <= VOL_SETTLE * (that state's MINIMUM achievable
#            residual SD over any later start) -- i.e. volatility has bottomed
#            out.  NOTE: an absolute "back to pre-COVID SD" test is the WRONG
#            one here: this project has already measured that post-COVID series
#            are permanently ~1.9x (2.7x on strict never-legalizers) as noisy as
#            pre-COVID (output/longdiff_era_variance/era_ratio.csv), so that
#            test never fires for ~half the panel.  The criterion is therefore
#            self-calibrated per state; the pre-COVID ratio is REPORTED, not
#            imposed.
#        (d) at least MIN_WIN months remain.
#   5. Separately: first month the level re-enters +/-LEVEL_TOL of pre-COVID
#      baseline and never leaves ("level recovery") -- many states never do.
#
# Outputs -> output/eviction_stabilization/
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(ggplot2); library(lubridate)
})

theme_set(theme_minimal())

PANEL      <- "data/raw/state_month_panel_with_treatment.csv"
QA         <- "data/processed/state_panel_coverage_qa.csv"
SCHED      <- "data/raw/sports_gambling_legalization_dates.csv"
OUT        <- "output/eviction_stabilization"

PRE_START  <- as.Date("2016-01-01")
PRE_END    <- as.Date("2020-02-01")   # last clean pre-pandemic month
SEARCH_MIN <- as.Date("2021-01-01")   # earliest plateau onset we entertain
FLAT_TOL   <- 0.05                    # <= 5% per year drift counts as flat
VOL_SETTLE <- 1.25                    # residual SD within 1.25x of its own floor
LEVEL_TOL  <- 0.20                    # +/-20% band for "level recovery"
MIN_WIN    <- 12L                     # plateau must run >= 12 months

dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

panel <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  filter(month_date >= PRE_START, !is.na(filings_count))

qa <- read_csv(QA, show_col_types = FALSE)

# Keep composition-stable substrates only.
ok_states <- qa %>% filter(composition_risk == "ok") %>% pull(state_abb)
keep_src  <- c("county_download_fixed_basket",
               "nh_court_source_repair_2026-07-23",
               "wi_court_source_repair_2026-07-23",
               "md_judiciary_lt_complaint_filings")

panel <- panel %>%
  filter(panel_source %in% keep_src) %>%
  filter(state_abb %in% ok_states |
           panel_source %in% c("nh_court_source_repair_2026-07-23",
                               "wi_court_source_repair_2026-07-23",
                               "md_judiciary_lt_complaint_filings"))

analyze_state <- function(d) {
  d <- d %>% arrange(month_date) %>%
    mutate(y = log(filings_count + 1), moy = month(month_date),
           tt = as.numeric(month_date - PRE_START) / 365.25)

  pre <- d %>% filter(month_date >= PRE_START, month_date <= PRE_END)
  if (nrow(pre) < 30 || n_distinct(pre$moy) < 12) return(NULL)

  # seasonal from pre-COVID only
  seas_fit <- lm(y ~ factor(moy), data = pre)
  seas <- tibble(moy = 1:12,
                 s = predict(seas_fit, newdata = tibble(moy = 1:12)))
  seas$s <- seas$s - mean(seas$s)
  d <- d %>% left_join(seas, by = "moy") %>% mutate(ya = y - s)

  pre_a  <- d %>% filter(month_date >= PRE_START, month_date <= PRE_END)
  base   <- mean(pre_a$ya)
  sigma  <- sd(residuals(lm(ya ~ tt, data = pre_a)))

  post <- d %>% filter(month_date >= SEARCH_MIN)
  if (nrow(post) < MIN_WIN) return(NULL)
  end_m <- max(post$month_date)

  cands <- post$month_date[post$month_date <= end_m %m-% months(MIN_WIN - 1L)]
  grid <- lapply(cands, function(m) {
    w <- post %>% filter(month_date >= m)
    if (nrow(w) < MIN_WIN) return(NULL)
    fit <- lm(ya ~ tt, data = w)
    tibble(m = m, slope = unname(coef(fit)[2]),
           p = summary(fit)$coefficients[2, 4], rsd = sd(residuals(fit)))
  }) %>% bind_rows()
  if (!nrow(grid)) return(NULL)

  vol_floor <- min(grid$rsd)                       # this state's own noise floor
  pass <- grid %>% filter(abs(slope) <= FLAT_TOL, p > 0.05,
                          rsd <= VOL_SETTLE * vol_floor)

  onset <- if (nrow(pass)) min(pass$m) else as.Date(NA)
  onset_slope <- if (nrow(pass)) pass$slope[which.min(pass$m)] else NA_real_
  onset_p     <- if (nrow(pass)) pass$p[which.min(pass$m)]     else NA_real_
  onset_sd    <- if (nrow(pass)) pass$rsd[which.min(pass$m)]   else NA_real_

  # level recovery: last time it was outside the band, +1 month
  post_lv <- post %>% mutate(dev = ya - base, outside = abs(dev) > LEVEL_TOL)
  recov <- if (!any(post_lv$outside)) min(post_lv$month_date) else {
    last_out <- max(post_lv$month_date[post_lv$outside])
    if (last_out == max(post_lv$month_date)) as.Date(NA) else
      post_lv$month_date[post_lv$month_date > last_out][1]
  }

  plateau_lvl <- if (!is.na(onset)) {
    exp(mean(post$ya[post$month_date >= onset]) - base) - 1
  } else NA_real_

  tibble(
    state_abb      = d$state_abb[1],
    n_months       = nrow(d),
    coverage_end   = end_m,
    pre_sigma      = sigma,
    plateau_onset  = onset,
    plateau_slope_yr = onset_slope,
    plateau_slope_p  = onset_p,
    plateau_sd_ratio = onset_sd / sigma,
    vol_floor_ratio  = vol_floor / sigma,
    plateau_vs_pre   = plateau_lvl,
    level_recovery   = recov
  )
}

res <- panel %>% group_split(state_abb) %>% lapply(analyze_state) %>% bind_rows()

sched <- read_csv(SCHED, show_col_types = FALSE) %>%
  transmute(state = state, online_start_date = as.Date(online_start_date))
st_map <- tibble(state = state.name, abb = state.abb) %>%
  add_row(state = "District of Columbia", abb = "DC")
sched <- sched %>% left_join(st_map, by = "state") %>%
  transmute(state_abb = abb, online_start_date)

res <- res %>% left_join(sched, by = "state_abb") %>%
  mutate(ever_online = !is.na(online_start_date)) %>%
  arrange(plateau_onset)

write_csv(res, file.path(OUT, "stabilization_by_state.csv"))

cat("\n================ PLATEAU ONSET BY STATE ================\n")
print(as.data.frame(res %>% transmute(
  state_abb, ever_online,
  plateau_onset = format(plateau_onset, "%Y-%m"),
  slope_yr = round(plateau_slope_yr, 3),
  sd_vs_pre = round(plateau_sd_ratio, 2),
  lvl_vs_pre = sprintf("%+.0f%%", 100 * plateau_vs_pre),
  level_recovery = format(level_recovery, "%Y-%m"),
  cov_end = format(coverage_end, "%Y-%m"))), row.names = FALSE)

ons <- res$plateau_onset[!is.na(res$plateau_onset)]
cat("\n================ SUMMARY ================\n")
cat("States analyzed:              ", nrow(res), "\n")
cat("With an identified plateau:   ", length(ons), "\n")
if (length(ons)) {
  cat("Median plateau onset:         ", format(median(ons), "%Y-%m"), "\n")
  cat("IQR:                          ", format(quantile(ons, .25, type = 1), "%Y-%m"),
      "to", format(quantile(ons, .75, type = 1), "%Y-%m"), "\n")
  cat("Earliest / latest:            ", format(min(ons), "%Y-%m"), "/",
      format(max(ons), "%Y-%m"), "\n")
  for (cut in as.Date(c("2021-08-01","2022-01-01","2022-07-01","2023-01-01"))) {
    cut <- as.Date(cut, origin = "1970-01-01")
    cat(sprintf("  stabilized by %s: %2d of %d (%.0f%%)\n", format(cut, "%Y-%m"),
                sum(ons <= cut), length(ons), 100*mean(ons <= cut)))
  }
}
nr <- sum(is.na(res$level_recovery))
cat("Never return to +/-20% of pre-COVID level:", nr, "of", nrow(res), "\n")
cat("Median plateau level vs pre-COVID:        ",
    sprintf("%+.0f%%", 100*median(res$plateau_vs_pre, na.rm = TRUE)), "\n")
cat("Median post-era noise floor vs pre-COVID:  ",
    sprintf("%.2fx", median(res$vol_floor_ratio, na.rm = TRUE)),
    " (never returns to 1.0x -- matches era-variance finding)\n")

# ---- figure -----------------------------------------------------------------
plot_dat <- panel %>%
  filter(state_abb %in% res$state_abb) %>%
  arrange(state_abb, month_date) %>%
  group_by(state_abb) %>%
  group_modify(~{
    d <- .x %>% mutate(y = log(filings_count + 1), moy = month(month_date))
    pre <- d %>% filter(month_date <= PRE_END)
    sf <- lm(y ~ factor(moy), data = pre)
    s  <- predict(sf, newdata = tibble(moy = 1:12)); s <- s - mean(s)
    d %>% mutate(ya = y - s[moy], dev = ya - mean((d %>% filter(month_date <= PRE_END) %>%
      mutate(ya = y - s[moy]))$ya))
  }) %>% ungroup()

p <- ggplot(plot_dat, aes(month_date, dev, group = state_abb)) +
  geom_hline(yintercept = 0, colour = "grey55") +
  geom_hline(yintercept = c(-LEVEL_TOL, LEVEL_TOL), linetype = 3, colour = "grey70") +
  geom_line(alpha = .28, linewidth = .35) +
  annotate("rect", xmin = as.Date("2020-03-01"), xmax = as.Date("2021-07-31"),
           ymin = -Inf, ymax = Inf, fill = "grey80", alpha = .35) +
  geom_line(alpha = .28, linewidth = .35) +
  geom_vline(xintercept = median(ons), colour = "firebrick", linetype = 2) +
  annotate("text", x = median(ons), y = max(plot_dat$dev, na.rm = TRUE),
           label = paste(" median plateau onset:", format(median(ons), "%b %Y")),
           hjust = 0, colour = "firebrick", size = 3.2) +
  labs(x = NULL, y = "Deseasonalized log filings, deviation from 2016–2019 baseline",
       subtitle = paste0("Shaded: framework COVID window (2020-03 to 2021-07). ",
                         "Dotted: \u00b120% band around pre-COVID baseline."))
ggsave(file.path(OUT, "stabilization_paths.png"), p, width = 10, height = 5.5, dpi = 160)

cat("\nWrote:", file.path(OUT, "stabilization_by_state.csv"), "\n")
cat("Wrote:", file.path(OUT, "stabilization_paths.png"), "\n")
