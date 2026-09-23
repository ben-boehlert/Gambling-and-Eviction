#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# analysis/diagnostics/lpdid_ri_post2022.R   (2026-09-22)
#
# RANDOMIZATION INFERENCE FOR THE POST-JUNE-2022 LP-DiD DESIGN
# (6-18 horizons, 3-month baseline, K = 7, sample starts 2022-06).
#
# THE QUESTION IT ANSWERS. The blinded framework calibrates the analytic SE on
# its `precovid` arm -- 10 pseudo-switchers on PRE-2020 data, SE/SD 0.958 -- and
# that correction is then applied to the real design's post-2022 SE. Its
# `postcovid` arm places only 6 pseudo-switchers and reports SE/SD 0.67, so era
# and cluster count are perfectly confounded and neither arm establishes that
# the analytic SE is calibrated WHERE THE DESIGN ACTUALLY RUNS. RI does: it
# holds the real post-2022 data fixed and permutes WHICH states switch.
#
# WHAT IS PERMUTED. The observed set of launch dates is held fixed and shuffled
# across states eligible to receive one (panel states minus pre-PASPA
# always-treated). Cohort structure -- how many switch and when -- is preserved;
# only the identity of the switchers is randomized. Real outcomes are untouched,
# so the COVID splice, moratoria and rental assistance enter every draw exactly
# as they do in the data.
#
# WHY IT IS THE RIGHT TEST. Under the sharp null of no effect anywhere, the
# permutation distribution IS the finite-sample null distribution of the
# estimator, at the real cluster count, in the real era, on the real
# unbalanced panel. Comparing its spread with the analytic SEs the same fits
# report gives SE/SD for the design itself, with no transfer assumption.
#
# BLINDNESS. The true assignment is never estimated. Draws reproducing it are
# rejected and redrawn. No observed ATT is loaded, computed, printed or stored;
# every `att_null` in the output belongs to a permuted world. Each permutation
# writes to its own scratch OUT_DIR, so the real output/lpdid_statepanel/ files
# are never touched.
#
# Estimator parity: drives analysis/main/lpdid_statepanel.R through its
# TREAT_FILE hook -- the same code path that produces the SE being validated --
# and reads the `post_covid_cohorts` row, the design's own window.
#
# Run from the project root:
#   N_PERM=500 N_WORKERS=6 Rscript analysis/diagnostics/lpdid_ri_post2022.R
# Env knobs: N_PERM (200), N_WORKERS (6), RI_SEED (20260922), and the design
#   knobs POST_MIN/POST/PMD/DROP_END/MIN_HORIZONS/SPLICE_BUFFER/EXCLUDE_STATES.
# Output: output/lpdid_ri_post2022/  (null draws + summary; NO observed estimate)
# ─────────────────────────────────────────────────────────────────────────────
suppressMessages({ library(tidyverse); library(lubridate); library(glue); library(parallel) })
source("utils/eviction_treatment_schedule.R")

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
N_PERM    <- as.integer(getenv1("N_PERM", "200"))
N_WORKERS <- as.integer(getenv1("N_WORKERS", "6"))
SEED      <- as.integer(getenv1("RI_SEED", "20260922"))
OUT       <- getenv1("OUT_DIR", "output/lpdid_ri_post2022")
SCRATCH   <- getenv1("RI_SCRATCH", file.path(tempdir(), "ri_post2022"))
REAL      <- "data/raw/sports_gambling_legalization_dates.csv"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(SCRATCH, recursive = TRUE, showWarnings = FALSE)

# The pending design (FINDINGS §2): 6-18 horizons, pmd 3, sample starts 2022-06
# (covid drop ends 2022-05-31), K = 7, no splice buffer.
DESIGN_ENV <- c("TREAT_DEF=raw", "ANCHOR=event_clean",
                sprintf("PMD=%s",           getenv1("PMD", "3")),
                sprintf("POST=%s",          getenv1("POST", "18")),
                sprintf("POST_MIN=%s",      getenv1("POST_MIN", "6")),
                sprintf("DROP_END=%s",      getenv1("DROP_END", "2022-05-31")),
                sprintf("MIN_HORIZONS=%s",  getenv1("MIN_HORIZONS", "7")),
                sprintf("SPLICE_BUFFER=%s", getenv1("SPLICE_BUFFER", "0")),
                "BASELINE_CLEAN=1", "LPDID_WEIGHTS=ewatt",
                "WILD_CI=0", "BOOT_REPS=1")
if (nzchar(Sys.getenv("EXCLUDE_STATES")))
  DESIGN_ENV <- c(DESIGN_ENV, sprintf("EXCLUDE_STATES=%s", Sys.getenv("EXCLUDE_STATES")))

real <- read_csv(REAL, show_col_types = FALSE)
has_date <- !is.na(real$online_start_date)
panel_states <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                         show_col_types = FALSE) %>% distinct(state_abb) %>% pull()
pool <- setdiff(panel_states, PRE_PASPA_SPORTS_BETTING)
abb  <- tibble(state_abb = c(state.abb, "DC"), State = c(state.name, "District of Columbia"))
pool_names <- abb$State[match(pool, abb$state_abb)]
pool_names <- sort(pool_names[!is.na(pool_names)])
TRUTH <- paste(sort(real$state[has_date]), collapse = "|")

cat(glue("RI post-2022 | {sum(has_date)} launch dates reassigned over {length(pool_names)} ",
         "eligible states | {N_PERM} permutations x {N_WORKERS} workers\n"))
cat(glue("design: {paste(DESIGN_ENV, collapse = ' ')}\n\n"))

one_perm <- function(i) {
  set.seed(SEED + 1009L * i)
  dates <- real$online_start_date[has_date]
  for (attempt in 1:20) {
    recip <- sample(pool_names, length(dates))
    if (!identical(paste(sort(recip), collapse = "|"), TRUTH)) break  # never the truth
  }
  perm_file <- file.path(SCRATCH, sprintf("sched_%04d.csv", i))
  out_dir   <- file.path(SCRATCH, sprintf("run_%04d", i))
  tmpl <- real[1, , drop = FALSE]
  o <- tmpl[rep(1, length(recip)), , drop = FALSE]
  o$state <- recip; o$online_start_date <- dates; o$first_start_date <- dates
  if ("retail_start_date" %in% names(o)) o$retail_start_date <- NA
  write_csv(o, perm_file)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  system2("Rscript", c("--vanilla", "analysis/main/lpdid_statepanel.R"),
          env = c(sprintf("TREAT_FILE=%s", perm_file),
                  sprintf("OUT_DIR=%s", out_dir), DESIGN_ENV),
          stdout = FALSE, stderr = FALSE)
  f <- file.path(out_dir, "lpdid_pooled_windows_raw_event_clean.csv")
  res <- NULL
  if (file.exists(f)) {
    w <- suppressMessages(read_csv(f, show_col_types = FALSE)) %>%
      filter(window == "post_covid_cohorts")
    if (nrow(w) == 1 && is.finite(w$att) && is.finite(w$se))
      res <- tibble(perm = i, att_null = w$att, se = w$se,
                    n_switch = w$n_switch_states, n_ctl = w$n_control_states,
                    n_cells = w$n_cells, n_obs = w$n_obs)
  }
  unlink(perm_file); unlink(out_dir, recursive = TRUE)
  res
}

t0 <- Sys.time()
draws <- mclapply(seq_len(N_PERM), function(i) tryCatch(one_perm(i), error = function(e) NULL),
                  mc.cores = N_WORKERS)
d <- bind_rows(draws)
cat(glue("{nrow(d)}/{N_PERM} permutations usable in {round(as.numeric(difftime(Sys.time(), t0, units='min')),1)} min\n"))
write_csv(d, file.path(OUT, "ri_null_draws.csv"))

mad_sd <- function(x) 1.4826 * median(abs(x - median(x)))
summarise_set <- function(dd, label) {
  s <- sd(dd$att_null); ms <- mad_sd(dd$att_null); cstar <- as.numeric(quantile(abs(dd$att_null), 0.95))
  tibble(set = label, n_perm = nrow(dd),
         median_switchers = median(dd$n_switch), median_controls = median(dd$n_ctl),
         null_mean = mean(dd$att_null), null_sd = s, null_mad_sd = ms,
         mean_se = mean(dd$se), se_over_sd = mean(dd$se) / s, se_over_madsd = mean(dd$se) / ms,
         reject_005_analytic = mean(abs(dd$att_null / dd$se) >
                                      qt(0.975, pmax(1, dd$n_switch + dd$n_ctl - 1))),
         crit_2sided_05 = cstar, mde80_ri = cstar + qnorm(0.80) * s,
         mde80_analytic = 2.8 * mean(dd$se))
}
summ <- bind_rows(
  summarise_set(d, "all_draws"),
  if (sum(d$n_switch >= 9 & d$n_switch <= 11) >= 30)
    summarise_set(filter(d, n_switch >= 9, n_switch <= 11), "switchers_9_to_11") else NULL
)
write_csv(summ, file.path(OUT, "ri_summary.csv"))
cat("\n===== RI NULL DISTRIBUTION, POST-2022 DESIGN (no observed estimate anywhere) =====\n")
print(as.data.frame(summ %>% mutate(across(where(is.numeric), ~round(.x, 4)))), row.names = FALSE)
cat(glue("\nwritten: {file.path(OUT, 'ri_summary.csv')}\n"))
