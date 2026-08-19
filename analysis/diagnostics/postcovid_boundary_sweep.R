#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# How does the choice of the "post-COVID" start date affect the stability of
# never-treated state effects — the input did2s's global parallel-trends
# assumption needs?
#
# Repo context (two conventions in use):
#   * Power framework (load_blinded_panel covid: "post"): post-COVID begins
#     2021-08-01 (config covid_drop ends 2021-07-31). All post-COVID power
#     runs (state + county, 2026-08-17 and 2026-08-19) use THIS.
#   * Trend diagnostics + analysis/main/lpdid_statepanel.R: COVID window ends
#     2022-03-31, so their "post" begins 2022-04-01.
#
# For each candidate boundary b, on the SAME 9 never-treated states:
#   1. within-window drift: half-split state-shift SD on months >= b
#      (the residual global-PT risk of a design estimated on that window);
#   2. across-gap shift SD: state-effect shifts of (months >= b) vs the fixed
#      pre-COVID era (2016-01..2020-02) — relevant only if a design SPLICES
#      pre and post together;
#   3. slope dispersion: SD across states of within-window linear trends;
#   4. window length in months (the power cost of moving b later).
#
# Never-treated only; real outcomes; blindness-compatible (untreated data).
# Inference note: state-level regressors clustered by state → Wald tests are
# degenerate; magnitudes only.
#
# Usage:  Rscript analysis/diagnostics/postcovid_boundary_sweep.R
# Output: output/covid_global_pt/postcovid_boundary_sweep.csv
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(fixest); library(glue)
})
theme_set(theme_minimal())

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/covid_global_pt"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

NT_STATES <- c("AK", "GA", "ID", "MN", "MT", "ND", "OK", "TX", "UT")
PRE_END   <- as.Date("2020-02-01")   # last clean pre-COVID month
MAX_DATE  <- as.Date("2025-11-01")   # state panel end (matches power runs)

ym_index <- function(d) {
  (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))
}

panel <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb),
            month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(state_abb %in% NT_STATES,
         month_date >= as.Date("2016-01-01"), month_date <= MAX_DATE,
         !is.na(filings_count)) %>%
  mutate(y = log1p(pmax(filings_count, 0)), t = ym_index(month_date))

# Keep months covered by all 9 states (balance within every window).
n_st <- n_distinct(panel$state_abb)
common <- panel %>% count(month_date) %>% filter(n == n_st) %>% pull(month_date)
panel <- panel %>% filter(month_date %in% common)
cat(glue("{n_st} never-treated states; balanced months {format(min(common))}..",
         "{format(max(common))} ({length(common)} total)"), "\n\n")

half_split_sd <- function(d) {
  if (n_distinct(d$t) < 8L) return(NA_real_)
  mid <- median(unique(d$t))
  d <- d %>% mutate(late = t > mid, state_abb = factor(state_abb))
  m <- feols(y ~ i(state_abb, late) | state_abb + t, data = d,
             cluster = ~state_abb)
  sh <- c(broom::tidy(m) %>% filter(str_detect(term, "state_abb")) %>%
            pull(estimate), 0)
  sd(sh - mean(sh))
}

pre <- panel %>% filter(month_date <= PRE_END)

boundaries <- as.Date(c("2021-08-01", "2021-12-01", "2022-04-01",
                        "2022-10-01", "2023-04-01", "2023-10-01",
                        "2024-04-01"))

sweep <- map_dfr(boundaries, function(b) {
  post <- panel %>% filter(month_date >= b)
  n_mo <- n_distinct(post$month_date)

  # Across-gap shifts vs the fixed pre era (splice designs only).
  both <- bind_rows(pre, post) %>%
    mutate(is_post = month_date >= b, state_abb = factor(state_abb))
  m <- feols(y ~ i(state_abb, is_post) | state_abb + t, data = both,
             cluster = ~state_abb)
  sh <- c(broom::tidy(m) %>% filter(str_detect(term, "state_abb")) %>%
            pull(estimate), 0)

  # Within-window slope dispersion (differential linear trends).
  slopes <- post %>% group_by(state_abb) %>%
    summarise(slope = coef(lm(y ~ t))[["t"]], .groups = "drop")

  tibble(post_start = b, n_months = n_mo,
         across_gap_shift_sd = sd(sh - mean(sh)),
         within_halfsplit_sd = half_split_sd(post),
         slope_sd_annpp = 100 * (exp(12 * sd(slopes$slope)) - 1))
})

cat("=== Post-COVID boundary sweep (9 never-treated states) ===\n")
print(sweep %>% mutate(across(where(is.numeric), ~round(.x, 3))) %>%
        as.data.frame(), row.names = FALSE)
cat("\nBenchmarks: pre-COVID era half-split SD = 0.416; across-COVID shift SD\n",
    "(2022-04 convention, 2024-12 panel) = 0.467 (covid_global_pt_diagnostic.R).\n")

write_csv(sweep, file.path(OUT_DIR, "postcovid_boundary_sweep.csv"))
cat(glue("Wrote {OUT_DIR}/postcovid_boundary_sweep.csv\n"))
