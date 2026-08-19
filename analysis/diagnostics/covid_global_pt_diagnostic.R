#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Does COVID break the GLOBAL parallel trends assumption that imputation
# estimators (did2s, didimputation) rely on?
#
# Why this test exists. did2s fits Y(0) = alpha_i + lambda_t on ALL untreated
# observations and imputes counterfactuals from it. That requires the additive
# two-way structure to hold across the WHOLE panel — a global assumption. CS
# instead uses local (g,t) comparisons against a nearby base period, so a
# structural break in the middle of the panel contaminates it far less.
#
# The existing null calibration (analysis/diagnostics/cs_calibration_multi_
# estimator.R) CANNOT detect a violation of this, because it simulates
# y = predict(feols(y ~ 1 | id + t)) + resampled residuals. The additive model
# is true by construction in that DGP, and residuals are resampled within month
# ACROSS states, which destroys exactly the state-specific COVID response we
# care about. It tests inference calibration, not the identifying assumption.
#
# This script tests the assumption directly on REAL outcomes, using only
# never-treated states so that treatment cannot confound the answer:
#   H0: state deviations from the common time path are the same before and
#       after the COVID window (alpha_i is stable across the splice).
# Rejecting H0 means the pooled additive model is misspecified globally, which
# is precisely the input did2s's first stage assumes.
#
# Usage: Rscript analysis/diagnostics/covid_global_pt_diagnostic.R
# Output: output/covid_global_pt/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(fixest); library(glue)
})
theme_set(theme_minimal())

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/covid_global_pt"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

MIN_DATE   <- as.Date("2016-01-01")
MAX_DATE   <- as.Date("2024-12-31")
DROP_START <- as.Date("2020-03-01")
DROP_END   <- as.Date("2022-03-31")

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))

panel0 <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb),
            month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

# Balance to common coverage, as the pretrends pipeline does. ME is NOT excluded
# here: it was repaired from the court source on 2026-07-23 and is a valid
# never-treated control (the older calibration script still hardcodes its
# exclusion).
coverage   <- panel0 %>% count(state_abb, name = "n")
keep       <- coverage %>% filter(n >= max(n)) %>% pull(state_abb)
panel0     <- panel0 %>% filter(state_abb %in% keep)
n_st       <- n_distinct(panel0$state_abb)
common_mo  <- panel0 %>% count(month_date, name = "k") %>% filter(k == n_st) %>% pull(month_date)
panel0     <- panel0 %>% filter(month_date %in% common_mo)

treat <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = panel0$state_abb)

panel <- panel0 %>%
  left_join(treat, by = "state_abb") %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         post_covid = month_date > DROP_END,
         never_treated = is.na(treat_start))

nt <- panel %>% filter(never_treated)

cat(glue("Panel: {n_distinct(panel$state_abb)} states, {n_distinct(panel$t)} months"), "\n")
cat(glue("Never-treated states used for the test: {n_distinct(nt$state_abb)} ",
         "({paste(sort(unique(nt$state_abb)), collapse=', ')})"), "\n\n")

# ── Test: are state effects stable across the COVID splice? ──────────────────
# y_it = alpha_i + lambda_t + delta_i * 1{post-COVID} + e_it, on never-treated
# states only. Under global parallel trends every delta_i = 0.
nt <- nt %>% mutate(state_abb = factor(state_abb))

# One interaction is collinear with the time effects (their sum is post_covid);
# fixest drops it automatically and we recentre the estimates below.
m_shift <- feols(y ~ i(state_abb, post_covid) | state_abb + t,
                 data = nt, cluster = ~state_abb)

w <- wald(m_shift, keep = "state_abb", print = FALSE)
cat("=== JOINT TEST: state-specific level shifts across COVID (never-treated) ===\n")
cat(glue("  Wald F = {round(w$stat, 2)} on ({w$df1}, {w$df2}) df, p = {format.pval(w$p, digits = 3)}"), "\n")

sh <- broom::tidy(m_shift) %>%
  filter(str_detect(term, "state_abb")) %>%
  mutate(state = str_extract(term, "(?<=state_abb::)[A-Z]{2}")) %>%
  select(state, shift = estimate, se = std.error)
sh <- sh %>% mutate(shift_c = shift - mean(shift))

cat(glue("\n  SD of state shifts: {round(sd(sh$shift_c), 3)} log points ",
         "({round(100 * sd(sh$shift_c), 1)}% in filings terms)"), "\n")
cat(glue("  Range: {round(min(sh$shift_c), 2)} to {round(max(sh$shift_c), 2)} log points"), "\n\n")
print(sh %>% arrange(shift_c) %>% mutate(across(where(is.numeric), ~round(.x, 3))) %>%
        as.data.frame(), row.names = FALSE)

# ── Benchmark: how big is that relative to the effect we are hunting? ────────
cat(glue("\n  For scale: the state-panel MDE is ~5 log points and the CS overall ",
         "ATT is 0.011.\n  The COVID splice moves states around by SD = ",
         "{round(sd(sh$shift_c), 3)} log points."), "\n")

# ── Same test allowing differential TRENDS, not just levels ──────────────────
nt <- nt %>% mutate(trend = t - min(t))
m_trend <- feols(y ~ i(state_abb, trend) | state_abb + t,
                 data = nt, cluster = ~state_abb)
wt <- wald(m_trend, keep = "state_abb", print = FALSE)
cat(glue("\n=== JOINT TEST: state-specific linear trends (never-treated) ===\n",
         "  Wald F = {round(wt$stat, 2)}, p = {format.pval(wt$p, digits = 3)}"), "\n")

# ── Placebo comparison: split the PRE-COVID era in half ─────────────────────
# If the COVID shift is special rather than generic instability, an arbitrary
# split of the clean pre-period should produce much smaller state shifts.
pre <- nt %>% filter(!post_covid)
mid <- median(unique(pre$t))
pre <- pre %>% mutate(post_fake = t > mid)
m_fake <- feols(y ~ i(state_abb, post_fake) | state_abb + t,
                data = pre, cluster = ~state_abb)
wf <- wald(m_fake, keep = "state_abb", print = FALSE)
sf <- broom::tidy(m_fake) %>% filter(str_detect(term, "state_abb")) %>% pull(estimate)
cat(glue("\n=== PLACEBO: arbitrary split of the pre-COVID era ===\n",
         "  Wald F = {round(wf$stat, 2)}, p = {format.pval(wf$p, digits = 3)}\n",
         "  SD of state shifts: {round(sd(c(sf, 0) - mean(c(sf, 0))), 3)} log points ",
         "(vs {round(sd(sh$shift_c), 3)} across COVID)"), "\n")

write_csv(sh, file.path(OUT_DIR, "state_covid_shifts.csv"))

p <- sh %>% mutate(state = fct_reorder(state, shift_c)) %>%
  ggplot(aes(shift_c, state)) +
  geom_col(fill = "grey40") + geom_vline(xintercept = 0) +
  labs(x = "Level shift across the COVID window (log filings)", y = NULL,
       subtitle = "Never-treated states only; global parallel trends requires all of these to be zero")
ggsave(file.path(OUT_DIR, "state_covid_shifts.png"), p, width = 7, height = 5, dpi = 150)

cat(glue("\nWrote {OUT_DIR}/\n"))
