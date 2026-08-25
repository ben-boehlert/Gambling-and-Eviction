#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Is online-legalization timing correlated with a state's eviction trajectory?
#
# The bias channel the permutation placebo CANNOT test. Permuting treatment
# across states destroys any correlation between real legalization timing and
# state-specific COVID recovery paths — which is exactly the concern. An
# imputation estimator fits Y(0) = alpha_i + lambda_t globally and imputes
# counterfactuals from it; if late-legalizing states recovered from COVID
# differently from early-legalizing ones for reasons unrelated to gambling,
# that difference is loaded onto the treatment effect.
#
# Both tests below use ONLY PRE-TREATMENT observations, so nothing measured
# here can contain a treatment effect. If timing is uncorrelated with these
# pre-treatment trajectory features, the bias channel is empirically small.
#
#   Test A — pre-COVID trend: does a state's 2016-2020 eviction trend predict
#            when it legalized? (All states contribute; classic parallel-trends
#            question, independent of COVID.)
#   Test B — COVID level shift: does the jump across the COVID window, measured
#            before the state was treated, predict when it legalized? (Only
#            states with post-COVID pre-treatment months contribute.)
#
# The common time path lambda_t is estimated on NEVER-TREATED states only, so
# treated states cannot contaminate the benchmark they are compared against.
#
# Usage: Rscript analysis/diagnostics/timing_covid_recovery_test.R
# Output: output/timing_covid_recovery/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({ library(tidyverse); library(fixest); library(glue) })
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/timing_covid_recovery"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

MIN_DATE   <- as.Date("2016-01-01")
MAX_DATE   <- as.Date("2024-12-31")
DROP_START <- as.Date("2020-03-01")
DROP_END   <- as.Date("2022-03-31")
MIN_OBS    <- 6L      # months needed on each side to measure a state

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))

# ── Panel ────────────────────────────────────────────────────────────────────
p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb), month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))
cov <- p %>% count(state_abb, name = "n")
p <- p %>% filter(state_abb %in% cov$state_abb[cov$n >= max(cov$n)])
k <- n_distinct(p$state_abb)
cm <- p %>% count(month_date, name = "j") %>% filter(j == k) %>% pull(month_date)
p <- p %>% filter(month_date %in% cm) %>%
  mutate(y = log1p(pmax(filings_count, 0)), t = ym_index(month_date))

sched <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = p$state_abb)

abb  <- tibble(State = c(state.name, "District of Columbia"), state_abb = c(state.abb, "DC"))
lags <- read_csv("data/processed/cohort_ramp_lags.csv", show_col_types = FALSE) %>%
  left_join(abb, by = "State") %>% select(state_abb, ramp75_date)

panel <- p %>% left_join(sched, by = "state_abb") %>% left_join(lags, by = "state_abb") %>%
  mutate(g_raw   = ifelse(is.na(treat_start), Inf, ym_index(treat_start)),
         g_ramp  = ifelse(is.na(ramp75_date), Inf, ym_index(ramp75_date)),
         cohort  = ifelse(is.na(treat_start), NA_integer_, year(treat_start)),
         post_covid = month_date > DROP_END)

cat(glue("Panel: {n_distinct(panel$state_abb)} states, {n_distinct(panel$t)} months"), "\n")

# ── Common time path from never-treated states only ──────────────────────────
nt <- panel %>% filter(is.infinite(g_raw))
cat(glue("Never-treated states defining lambda_t: {n_distinct(nt$state_abb)} ",
         "({paste(sort(unique(nt$state_abb)), collapse=', ')})"), "\n\n")

lam_fit <- feols(y ~ 1 | state_abb + t, data = nt, warn = FALSE, notes = FALSE)
lam <- fixef(lam_fit)$t
panel <- panel %>% mutate(lambda = as.numeric(lam[as.character(t)]),
                          z = y - lambda)   # state series net of the common path

# ── Test A: pre-COVID trend vs legalization timing ───────────────────────────
# Slope of z on time, using pre-COVID months that are also pre-treatment.
trend_tbl <- panel %>%
  filter(!post_covid, t < g_raw) %>%
  group_by(state_abb, cohort) %>%
  filter(n() >= MIN_OBS) %>%
  summarise(trend = coef(lm(z ~ t))[2] * 12, n_obs = n(), .groups = "drop") %>%
  mutate(treated = !is.na(cohort))

cat("=== TEST A: does the pre-COVID eviction trend predict legalization timing? ===\n")
cat(glue("  States: {nrow(trend_tbl)} ({sum(trend_tbl$treated)} treated, ",
         "{sum(!trend_tbl$treated)} never-treated)\n"))
ta <- lm(trend ~ cohort, data = trend_tbl %>% filter(treated))
sa <- summary(ta)
cat(glue("  Slope on cohort year: {round(coef(ta)[2], 4)} ",
         "(SE {round(sa$coefficients[2,2], 4)}), p = {round(sa$coefficients[2,4], 3)}, ",
         "R2 = {round(sa$r.squared, 3)}, n = {nobs(ta)}"), "\n")
tt <- t.test(trend ~ treated, data = trend_tbl)
cat(glue("  Treated vs never-treated mean trend: {round(diff(rev(tt$estimate)), 4)} ",
         "log pts/yr, p = {round(tt$p.value, 3)}"), "\n\n")

# ── Test B: COVID level shift (pre-treatment only) vs timing ────────────────
shift_for <- function(gcol, label) {
  d <- panel %>% filter(t < .data[[gcol]]) %>%
    group_by(state_abb, cohort) %>%
    summarise(n_pre  = sum(!post_covid), n_post = sum(post_covid),
              shift  = mean(z[post_covid]) - mean(z[!post_covid]), .groups = "drop") %>%
    filter(n_pre >= MIN_OBS, n_post >= MIN_OBS) %>%
    mutate(treated = !is.na(cohort), spec = label)
  d
}

for (spec in list(c("g_raw", "raw online dates"), c("g_ramp", "ramp75 lagged dates"))) {
  d <- shift_for(spec[1], spec[2])
  cat(glue("=== TEST B ({spec[2]}): does the COVID shift predict timing? ===\n"))
  cat(glue("  States with >= {MIN_OBS} pre-treatment months on BOTH sides of COVID: ",
           "{nrow(d)} ({sum(d$treated)} treated, {sum(!d$treated)} never-treated)\n"))
  if (sum(d$treated) >= 4) {
    tb <- lm(shift ~ cohort, data = d %>% filter(treated)); sb <- summary(tb)
    cat(glue("  Slope on cohort year: {round(coef(tb)[2], 4)} ",
             "(SE {round(sb$coefficients[2,2], 4)}), p = {round(sb$coefficients[2,4], 3)}, ",
             "R2 = {round(sb$r.squared, 3)}, n = {nobs(tb)}"), "\n")
  } else {
    cat("  Too few treated states with a clean pre-treatment post-COVID window.\n")
  }
  if (sum(d$treated) >= 2 && sum(!d$treated) >= 2) {
    tt2 <- t.test(shift ~ treated, data = d)
    cat(glue("  Treated vs never-treated mean shift: {round(diff(rev(tt2$estimate)), 3)} ",
             "log pts, p = {round(tt2$p.value, 3)}"), "\n")
  }
  cat(glue("  SD of shift across states: {round(sd(d$shift), 3)} log points\n\n"))
  write_csv(d, file.path(OUT_DIR, glue("covid_shift_{make.names(spec[2])}.csv")))
  if (spec[1] == "g_raw") d_main <- d
}

write_csv(trend_tbl, file.path(OUT_DIR, "precovid_trends.csv"))

# ── Figures ──────────────────────────────────────────────────────────────────
p1 <- trend_tbl %>% filter(treated) %>%
  ggplot(aes(cohort, trend)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_point(size = 2) + geom_smooth(method = "lm", se = TRUE, colour = "firebrick") +
  geom_hline(yintercept = mean(trend_tbl$trend[!trend_tbl$treated]),
             linetype = "dashed", colour = "grey40") +
  labs(x = "Online legalization cohort", y = "Pre-COVID trend (log filings per year)",
       subtitle = "Pre-treatment months only; grey dashed = never-treated mean")
ggsave(file.path(OUT_DIR, "precovid_trend_by_cohort.png"), p1, width = 7, height = 4.5, dpi = 150)

if (exists("d_main") && sum(d_main$treated) >= 4) {
  p2 <- ggplot(d_main, aes(cohort, shift)) +
    geom_hline(yintercept = mean(d_main$shift[!d_main$treated]),
               linetype = "dashed", colour = "grey40") +
    geom_point(size = 2) + geom_smooth(method = "lm", se = TRUE, colour = "firebrick") +
    labs(x = "Online legalization cohort", y = "COVID level shift (log filings)",
         subtitle = "Measured on pre-treatment months only; grey dashed = never-treated mean")
  ggsave(file.path(OUT_DIR, "covid_shift_by_cohort.png"), p2, width = 7, height = 4.5, dpi = 150)
}

cat(glue("Wrote {OUT_DIR}/\n"))
