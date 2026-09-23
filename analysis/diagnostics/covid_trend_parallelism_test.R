#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Are post-COVID trends parallel to pre-COVID trends?
#
# WHY. The LP-DiD spec forbids "straddle" cells (pre-COVID baseline, post-COVID
# outcome) via lpdid_base_gapmax, which costs every state that legalised between
# 2019-05 and 2021-01. But the design memo (LP DiD Justification.docx) claims
# skipping the COVID period is a FEATURE. Whether a straddle cell is valid turns
# on whether a state's trajectory resumes where the common path predicts.
#
# timing_covid_recovery_test.R already tests two of the three pieces:
#   Test A  pre-COVID SLOPE vs legalisation timing        (passes, p = 0.70)
#   Test B  cross-COVID LEVEL SHIFT vs timing             (n.s., SD 0.225)
# It never compares the post-COVID slope to the pre-COVID slope. That is the
# piece that decides whether straddle bias GROWS with horizon: a pure level
# shift contaminates every horizon equally, but a slope change contaminates
# h = 24 twice as much as h = 12.
#
# THIS TEST (Test C). For each state, using PRE-TREATMENT months only so no
# treatment effect can enter, fit the slope of z (outcome net of the
# never-treated common time path) separately before and after the COVID window,
# then ask whether the CHANGE in slope is systematic.
#
#   C1  does the slope change predict legalisation timing?  (bias channel)
#   C2  do treated and never-treated states differ in mean slope change?
#   C3  how disperse is the slope change?                   (variance channel)
#   C4  implied straddle contamination at h = 18..24 months
#
# Never-treated states define lambda_t, exactly as in the companion script, so
# treated states cannot contaminate their own benchmark.
#
# Usage:
#   Rscript analysis/diagnostics/covid_trend_parallelism_test.R
#   COVID_END=2022-03-31 Rscript analysis/diagnostics/covid_trend_parallelism_test.R
# Output: output/covid_trend_parallelism/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({ library(tidyverse); library(fixest); library(glue) })
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/covid_trend_parallelism"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

env_or <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
MIN_DATE   <- as.Date("2016-01-01")
MAX_DATE   <- as.Date("2026-06-30")
DROP_START <- as.Date(env_or("COVID_START", "2020-03-01"))
DROP_END   <- as.Date(env_or("COVID_END",   "2021-07-31"))   # matches lpdid configs
MIN_OBS    <- 6L

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))

cat(glue("COVID window dropped: {format(DROP_START)} .. {format(DROP_END)}"), "\n\n")

p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb), month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE,
         !(month_date >= DROP_START & month_date <= DROP_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)), t = ym_index(month_date))

sched <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = unique(p$state_abb))

panel <- p %>% left_join(sched, by = "state_abb") %>%
  mutate(g = ifelse(is.na(treat_start), Inf, ym_index(treat_start)),
         cohort = ifelse(is.na(treat_start), NA_integer_, year(treat_start)),
         post_covid = month_date > DROP_END)

nt <- panel %>% filter(is.infinite(g))
cat(glue("Never-treated states defining lambda_t: {n_distinct(nt$state_abb)} ",
         "({paste(sort(unique(nt$state_abb)), collapse=', ')})"), "\n\n")
lam <- fixef(feols(y ~ 1 | state_abb + t, data = nt, warn = FALSE, notes = FALSE))$t
panel <- panel %>% mutate(z = y - as.numeric(lam[as.character(t)])) %>% filter(!is.na(z))

# ── slopes on each side of the gap, PRE-TREATMENT months only ────────────────
side <- function(dat) dat %>% group_by(state_abb, cohort) %>%
  filter(n() >= MIN_OBS) %>%
  summarise(slope = coef(lm(z ~ t))[2] * 12, lvl = mean(z), n = n(), .groups = "drop")

pre  <- side(panel %>% filter(!post_covid, t < g)) %>% rename(slope_pre = slope,  lvl_pre = lvl,  n_pre = n)
post <- side(panel %>% filter( post_covid, t < g)) %>% rename(slope_post = slope, lvl_post = lvl, n_post = n)

d <- inner_join(pre, post, by = c("state_abb", "cohort")) %>%
  mutate(d_slope = slope_post - slope_pre,
         shift   = lvl_post - lvl_pre,
         treated = !is.na(cohort))
write_csv(d, file.path(OUT_DIR, "covid_slope_change_by_state.csv"))

cat(glue("States with >= {MIN_OBS} PRE-TREATMENT months on BOTH sides of the gap: ",
         "{nrow(d)} ({sum(d$treated)} treated, {sum(!d$treated)} never-treated)"), "\n\n")

cat("=== C1: does the slope CHANGE predict legalisation timing? ===\n")
if (sum(d$treated) >= 4) {
  m <- lm(d_slope ~ cohort, data = d %>% filter(treated)); s <- summary(m)
  cat(glue("  slope on cohort year {round(coef(m)[2],4)} (SE {round(s$coefficients[2,2],4)}), ",
           "p = {round(s$coefficients[2,4],3)}, n = {nobs(m)}"), "\n")
} else cat(glue("  only {sum(d$treated)} treated states qualify — not testable\n"))

cat("\n=== C2: treated vs never-treated mean slope change ===\n")
if (sum(d$treated) >= 2 && sum(!d$treated) >= 2) {
  tt <- t.test(d_slope ~ treated, data = d)
  cat(glue("  difference {round(diff(rev(tt$estimate)),4)} log pts/yr, p = {round(tt$p.value,3)}"), "\n")
}

cat("\n=== C3: dispersion (the variance channel) ===\n")
cat(glue("  SD of slope change across states : {round(sd(d$d_slope),4)} log pts/yr"), "\n")
cat(glue("  SD of level shift across states  : {round(sd(d$shift),4)} log pts"), "\n")
cat(glue("  SD among never-treated only      : slope {round(sd(d$d_slope[!d$treated]),4)}, ",
         "level {round(sd(d$shift[!d$treated]),4)}"), "\n")

cat("\n=== C4: implied straddle contamination, h = 18..24 months ===\n")
h <- 18:24 / 12
cat(glue("  A straddle cell carries the level shift PLUS slope drift x horizon.\n"))
for (hh in c(18, 24)) {
  tot <- sqrt(sd(d$shift)^2 + (sd(d$d_slope) * hh/12)^2)
  cat(glue("   h = {hh}: SD(level) {round(sd(d$shift),3)} + SD(slope)x{round(hh/12,2)}yr ",
           "{round(sd(d$d_slope)*hh/12,3)} -> combined {round(tot,3)} log pts"), "\n")
}

g <- d %>% ggplot(aes(slope_pre, slope_post, colour = treated)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
  geom_hline(yintercept = 0, colour = "grey85") + geom_vline(xintercept = 0, colour = "grey85") +
  geom_point(size = 2.5, alpha = .85) + ggrepel::geom_text_repel(aes(label = state_abb), size = 3, show.legend = FALSE) +
  labs(x = "Pre-COVID slope (log pts/yr)", y = "Post-COVID slope (log pts/yr)",
       colour = "Treated",
       subtitle = "Points on the dashed line resumed their pre-COVID trend. Pre-treatment months only.")
ggsave(file.path(OUT_DIR, "pre_vs_post_covid_slope.png"), g, width = 8, height = 6, dpi = 150)
cat(glue("\nWrote {OUT_DIR}/covid_slope_change_by_state.csv and pre_vs_post_covid_slope.png"), "\n")
