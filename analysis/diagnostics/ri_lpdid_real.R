#!/usr/bin/env Rscript
# ============================================================================
# ri_lpdid_real.R  (2026-09-17)
#
# RANDOMIZATION INFERENCE for the clean 12-24 LP-DiD design on the REAL panel.
#
# WHY. Inference here rests on 9 treated clusters. Cluster-robust SEs are
# biased down in that regime and the wild bootstrap's resolution is driven by
# the treated count, so both lean on asymptotics the design does not have. RI
# makes no cluster-count claim: under the sharp null of no effect anywhere, the
# observed launch dates carry no signal, so reassigning them across states
# generates the exact finite-sample null distribution of the estimator.
#
# WHAT IT PERMUTES. The observed set of launch dates is held fixed and shuffled
# across the states eligible to receive one, preserving the cohort structure
# (how many switch, and when) while destroying WHICH state switches. Real
# outcomes -- COVID splice, moratoria, rental assistance -- are untouched.
#
# BLINDNESS. This script reads and writes ONLY the null distribution. It never
# loads, prints or stores the observed ATT. The MDE approximation below uses
# the null's critical value and spread, not the estimate.
#
# MDE. With c* the two-sided 5% critical value from the null draws and s the
# null SD, an effect is detected 80% of the time when it exceeds roughly
#   MDE ~= c* + qnorm(0.80) * s
# i.e. it must clear the rejection threshold and then some, to beat sampling
# noise 80% of the time. This assumes the sampling spread under an alternative
# is about the null spread -- standard for an approximation, and conservative
# where treatment adds variance.
#
# Usage: N_PERM=200 N_WORKERS=4 Rscript analysis/diagnostics/ri_lpdid_real.R
# Output: output/ri_lpdid/ (null draws + summary; NO observed estimate)
# ============================================================================
suppressMessages({ library(tidyverse); library(lubridate); library(glue) })

N_PERM    <- as.integer(Sys.getenv("N_PERM", "200"))
SEED      <- as.integer(Sys.getenv("RI_SEED", "20260917"))
OUT       <- "output/ri_lpdid"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SCRATCH   <- Sys.getenv("RI_SCRATCH", tempdir())
REAL      <- "data/raw/sports_gambling_legalization_dates.csv"

real <- read_csv(REAL, show_col_types = FALSE)
has_date <- !is.na(real$online_start_date)
cat(glue("RI: {sum(has_date)} observed launch dates to reassign; {N_PERM} permutations\n\n"))

# States eligible to RECEIVE a permuted date: every state in the panel that is
# not pre-PASPA always-treated. Reassigning within this pool preserves the
# number of switchers and their calendar spacing.
panel_states <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                         show_col_types = FALSE) %>% distinct(state_abb) %>% pull()
source("utils/eviction_treatment_schedule.R")
pool <- setdiff(panel_states, PRE_PASPA_SPORTS_BETTING)
abb  <- tibble(state_abb = c(state.abb, "DC"), State = c(state.name, "District of Columbia"))
pool_names <- abb$State[match(pool, abb$state_abb)]
pool_names <- pool_names[!is.na(pool_names)]
cat(glue("eligible recipient pool: {length(pool_names)} states\n"))

set.seed(SEED)
draws <- vector("list", N_PERM)
for (i in seq_len(N_PERM)) {
  perm_file <- file.path(SCRATCH, sprintf("ri_sched_%04d.csv", i))
  dates <- real$online_start_date[has_date]
  recip <- sample(pool_names, length(dates))
  # The real file has NO ROW for a never-legalizer (absent, not NA), so a
  # permuted schedule is BUILT from the recipients rather than edited in place:
  # one row per state that receives a date, none for the rest. Column structure
  # is copied from the real file so the loader sees the same shape.
  tmpl <- real[1, , drop = FALSE]
  out  <- tmpl[rep(1, length(recip)), , drop = FALSE]
  out$state <- recip
  out$online_start_date <- dates
  # first_start drives blindness cutoffs elsewhere; keep it aligned so the
  # permuted world is internally consistent.
  out$first_start_date  <- dates
  if ("retail_start_date" %in% names(out)) out$retail_start_date <- NA
  write_csv(out, perm_file)
  res <- system2("Rscript", c("--vanilla", "analysis/main/lpdid_statepanel.R"),
                 env = c(sprintf("TREAT_FILE=%s", perm_file),
                         "TREAT_DEF=shift12", "ANCHOR=event_clean", "PMD=6",
                         "POST=12", "POST_MIN=0", "MIN_HORIZONS=7",
                         "SPLICE_BUFFER=3", "BASELINE_CLEAN=1",
                         "LPDID_WEIGHTS=ewatt", "WILD_CI=0", "BOOT_REPS=1"),
                 stdout = FALSE, stderr = FALSE)
  f <- "output/lpdid_statepanel/lpdid_pooled_windows_shift12_event_clean.csv"
  if (file.exists(f)) {
    w <- suppressMessages(read_csv(f, show_col_types = FALSE)) %>%
      filter(window == "full_pooled")
    if (nrow(w) == 1 && is.finite(w$att))
      draws[[i]] <- tibble(perm = i, att_null = w$att, se = w$se,
                           n_switch = w$n_switch_states, n_ctl = w$n_control_states)
  }
  unlink(perm_file)
  if (i %% 20 == 0) cat(glue("  {i}/{N_PERM}\n"))
}
d <- bind_rows(draws)
write_csv(d, file.path(OUT, "ri_null_draws.csv"))

s   <- sd(d$att_null); cstar <- quantile(abs(d$att_null), 0.95)
mde <- cstar + qnorm(0.80) * s
summ <- tibble(n_perm_ok = nrow(d), null_sd = s, null_mean = mean(d$att_null),
               crit_2sided_05 = as.numeric(cstar),
               mde_80 = as.numeric(mde),
               median_switchers = median(d$n_switch), median_controls = median(d$n_ctl))
write_csv(summ, file.path(OUT, "ri_summary.csv"))
cat("\n== RI null distribution (NO observed estimate anywhere in this output) ==\n")
print(as.data.frame(summ %>% mutate(across(where(is.numeric), ~round(.x, 4)))), row.names = FALSE)
