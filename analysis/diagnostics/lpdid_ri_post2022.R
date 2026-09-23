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
# WHAT IS PERMUTED. The launch dates of the real launchers INSIDE the design's
# state set are held fixed and shuffled across that state set (panel states
# minus EXCLUDE_STATES, default DESIGN_EXCLUDED_STATES = NV HI MS MN WA).
# Cohort structure -- how many switch and when -- is preserved; only the
# identity of the switchers is randomized.
#
# CORRECTED 2026-09-23 (quality_reports/reviews/2026-09-23_simulation_code_review.md
# A1-A3). The 2026-09-22 version shuffled all 31 real dates -- including NJ IA IL
# DC WY, which are not in the panel -- over 41 states including HI MS MN WA, which
# lpdid_statepanel.R then drops. Every permuted world therefore had ~5 extra
# launchers and fewer controls than the real design (medians 8 switchers / 15
# controls / 101 cells vs the design's 10 / 18 / 115), and its "never the truth"
# guard compared a 31-state set with a panel-only draw, so it could never fire.
# Its output is kept, superseded, in output/lpdid_ri_post2022/. Real outcomes are untouched,
# so the COVID splice, moratoria and rental assistance enter every draw exactly
# as they do in the data.
#
# WHY IT IS THE RIGHT TEST. Under the sharp null of no effect anywhere, the
# permutation distribution IS the finite-sample null distribution of the
# estimator, at the real cluster count, in the real era, on the real
# unbalanced panel. Comparing its spread with the analytic SEs the same fits
# report gives SE/SD for the design itself, with no transfer assumption.
#
# BLINDNESS. The true assignment is never estimated. A draw that reproduces the
# real state->date map on the design's state set is rejected and redrawn. No observed ATT is loaded, computed, printed or stored;
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
# Output: output/lpdid_ri_post2022_v20260923/  (null draws, summary, run
# metadata; NO observed estimate). The summary's studentised columns give the
# design-based MDE as mde_multiplier_studentised x the design's own SE.
# ─────────────────────────────────────────────────────────────────────────────
suppressMessages({ library(tidyverse); library(lubridate); library(glue); library(parallel) })
source("utils/eviction_treatment_schedule.R")

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
N_PERM    <- as.integer(getenv1("N_PERM", "200"))
N_WORKERS <- as.integer(getenv1("N_WORKERS", "6"))
SEED      <- as.integer(getenv1("RI_SEED", "20260922"))
OUT       <- getenv1("OUT_DIR", "output/lpdid_ri_post2022_v20260923")
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
# The design's state set. Parsed exactly as lpdid_statepanel.R parses it and
# passed through explicitly, so the pool and the estimator cannot disagree.
EXCL_RAW <- Sys.getenv("EXCLUDE_STATES", unset = paste(DESIGN_EXCLUDED_STATES, collapse = ","))
EXCLUDE  <- if (tolower(trimws(EXCL_RAW)) == "none") character(0) else
  toupper(trimws(strsplit(EXCL_RAW, ",")[[1]]))
EXCLUDE  <- union(EXCLUDE[nzchar(EXCLUDE)], PRE_PASPA_SPORTS_BETTING)
DESIGN_ENV <- c(DESIGN_ENV, sprintf("EXCLUDE_STATES=%s", paste(EXCLUDE, collapse = ",")))

real <- read_csv(REAL, show_col_types = FALSE)
panel_states <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                         show_col_types = FALSE) %>% distinct(state_abb) %>% pull()
pool <- setdiff(panel_states, EXCLUDE)
abb  <- tibble(state_abb = c(state.abb, "DC"), State = c(state.name, "District of Columbia"))
pool_names <- abb$State[match(pool, abb$state_abb)]
stopifnot(!anyNA(pool_names))
pool_names <- sort(pool_names)
# Only launchers inside the design's state set contribute dates: a launch in a
# state the design never sees (NJ, IA, IL, DC, WY) is not part of its cohorts.
launch <- real %>% filter(!is.na(online_start_date), state %in% pool_names)
dates  <- launch$online_start_date
key    <- function(st, dt) paste(sort(paste(st, format(dt))), collapse = "|")
TRUTH  <- key(launch$state, dates)

cat(glue("RI post-2022 | {length(dates)} launch dates reassigned over {length(pool_names)} ",
         "states ({length(pool_names) - length(dates)} never launch) | excluded: ",
         "{paste(EXCLUDE, collapse = ',')} | {N_PERM} permutations x {N_WORKERS} workers\n"))
cat(glue("design: {paste(DESIGN_ENV, collapse = ' ')}\n\n"))

one_perm <- function(i) {
  set.seed(SEED + 1009L * i)
  repeat {                                    # never the truth (P ~ 0, but checked)
    recip <- sample(pool_names, length(dates))
    if (!identical(key(recip, dates), TRUTH)) break
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
# Studentised columns (added 2026-09-23; the 09-22 ledger figures were computed
# off-script): t_crit95_studentised is the permutation 95th percentile of
# |att/se|, and mde_multiplier_studentised = t_crit95 + z_0.80, so the
# design-based MDE is that multiplier times the design's OWN analytic SE.
summarise_set <- function(dd, label) {
  s <- sd(dd$att_null); ms <- mad_sd(dd$att_null); cstar <- as.numeric(quantile(abs(dd$att_null), 0.95))
  tcrit <- as.numeric(quantile(abs(dd$att_null / dd$se), 0.95))
  tibble(set = label, n_perm = nrow(dd),
         median_switchers = median(dd$n_switch), median_controls = median(dd$n_ctl),
         null_mean = mean(dd$att_null), null_sd = s, null_mad_sd = ms,
         mean_se = mean(dd$se), se_over_sd = mean(dd$se) / s, se_over_madsd = mean(dd$se) / ms,
         reject_005_analytic = mean(abs(dd$att_null / dd$se) >
                                      qt(0.975, pmax(1, dd$n_switch + dd$n_ctl - 1))),
         crit_2sided_05 = cstar, mde80_ri = cstar + qnorm(0.80) * s,
         mde80_analytic = 2.8 * mean(dd$se),
         median_se = median(dd$se),
         t_crit95_studentised = tcrit,
         mde_multiplier_studentised = tcrit + qnorm(0.80))
}
# Strata: every switcher count with >= 30 draws, so a reader can match the
# real design's count without an off-script filter.
by_switch <- d %>% count(n_switch) %>% filter(n >= 30) %>% pull(n_switch)
summ <- bind_rows(
  summarise_set(d, "all_draws"),
  lapply(by_switch, function(k) summarise_set(filter(d, n_switch == k),
                                              sprintf("switchers_%d", k))))
write_csv(summ, file.path(OUT, "ri_summary.csv"))
jsonlite::write_json(list(
  script = "analysis/diagnostics/lpdid_ri_post2022.R", run_at = format(Sys.time()),
  n_perm = N_PERM, n_usable = nrow(d), seed = SEED, design_env = DESIGN_ENV,
  pool_states = sort(pool), n_launch_dates = length(dates),
  panel_md5 = unname(tools::md5sum("data/raw/state_month_panel_with_treatment.csv")),
  schedule_md5 = unname(tools::md5sum(REAL))),
  file.path(OUT, "run_metadata.json"), auto_unbox = TRUE, pretty = TRUE)
cat("\n===== RI NULL DISTRIBUTION, POST-2022 DESIGN (no observed estimate anywhere) =====\n")
print(as.data.frame(summ %>% mutate(across(where(is.numeric), ~round(.x, 4)))), row.names = FALSE)
cat(glue("\nwritten: {file.path(OUT, 'ri_summary.csv')}\n"))
