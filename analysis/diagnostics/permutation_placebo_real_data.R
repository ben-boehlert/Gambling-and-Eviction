#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Real-data permutation placebo: which estimators are correctly sized on THIS
# panel, and does the COVID splice break the imputation estimators?
#
# WHY NOT THE EXISTING CALIBRATION. analysis/diagnostics/cs_calibration_multi_
# estimator.R simulates y = predict(feols(y ~ 1 | id + t)) + residuals resampled
# within month across states. That DGP is additive in unit and time effects BY
# CONSTRUCTION, so did2s's global parallel-trends assumption is true in the
# simulation no matter what the real data look like, and the within-month
# resampling destroys exactly the state-specific COVID response at issue. It
# tests whether standard errors are calibrated under an assumption-true DGP —
# not whether the assumption holds.
#
# THIS TEST. Keep the REAL outcomes (COVID splice, state-specific moratoria,
# rental-assistance rollout and all) and randomise only WHO gets treated,
# permuting the observed treatment dates across states. Under the sharp null of
# no effect the permuted assignment carries no signal, so an estimator with
# valid inference should reject at 5%. Any excess rejection is caused by real
# features of the data rather than by the DGP we wrote.
#
# THREE ARMS, designed so one comparison isolates COVID:
#   A. spliced panel, real online dates permuted
#   B. spliced panel, ramp75 (cohort-lagged) dates permuted
#   C. clean PRE-COVID panel only (2016-01 to 2020-02), synthetic staggered
#      dates — no splice anywhere in the panel
# A vs C is the COVID test: if did2s is oversized in A but sized in C, the
# splice is the culprit. A vs B is the treatment-timing test.
#
# CAVEAT: permutation assumes the sharp null. If real effects exist, all arms
# inflate together — so read the CONTRAST between arms, not any arm's level.
#
# Usage: N_REPS=200 N_WORKERS=6 Rscript analysis/diagnostics/permutation_placebo_real_data.R
# Output: output/permutation_placebo/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(fixest); library(glue); library(parallel)
})
HAS_DIDIMP <- requireNamespace("didimputation", quietly = TRUE)
HAS_DID2S  <- requireNamespace("did2s", quietly = TRUE)
if (HAS_DIDIMP) suppressMessages(library(didimputation))
if (HAS_DID2S)  suppressMessages(library(did2s))

source("utils/eviction_treatment_schedule.R")

# fixest (OpenMP) and did/data.table both multithread. Forking a multithreaded
# process via mclapply crashes the workers — every rep died until these were
# pinned to one thread. Parallelism comes from the reps, not from within a fit.
Sys.setenv(OMP_NUM_THREADS = "1")
suppressMessages(data.table::setDTthreads(1))
fixest::setFixest_nthreads(1)

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
N_REPS    <- as.integer(getenv1("N_REPS", "200"))
# Serial by default: mclapply FORKS, and forking these packages segfaults the
# workers (reproduced repeatedly; serial runs the identical code cleanly).
# Raise N_WORKERS only if you have verified forking is safe on your machine.
N_WORKERS <- as.integer(getenv1("N_WORKERS", "1"))
# did::att_gt SEGFAULTS on some permuted assignments (the fastglm 0-row design
# matrix bug that patches/att_gt_safe.R exists for). A segfault kills the whole
# worker process — tryCatch cannot catch it — so CS is off by default. The
# question here is about the imputation estimators; CS is a comparison, not the
# target. Set SKIP_CS=FALSE to include it via the patched wrapper.
SKIP_CS   <- toupper(getenv1("SKIP_CS", "TRUE")) == "TRUE"
SEED      <- 20260814L
ALPHA     <- 0.05

OUT_DIR    <- "output/permutation_placebo"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

MIN_DATE   <- as.Date("2016-01-01")
MAX_DATE   <- as.Date("2024-12-31")
DROP_START <- as.Date("2020-03-01")
DROP_END   <- as.Date("2022-03-31")

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))

# ── Panel builders ───────────────────────────────────────────────────────────
build_panel <- function(drop_covid = TRUE, max_date = MAX_DATE) {
  p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
    transmute(state_abb = as.character(state_abb),
              month_date = as.Date(month_date),
              filings_count = as.numeric(filings_count)) %>%
    filter(month_date >= MIN_DATE, month_date <= max_date)
  if (drop_covid) p <- p %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
  cov <- p %>% count(state_abb, name = "n")
  p <- p %>% filter(state_abb %in% cov$state_abb[cov$n >= max(cov$n)])
  k <- n_distinct(p$state_abb)
  cm <- p %>% count(month_date, name = "j") %>% filter(j == k) %>% pull(month_date)
  p %>% filter(month_date %in% cm) %>%
    mutate(y = log1p(pmax(filings_count, 0)), t = ym_index(month_date),
           id = as.integer(as.factor(state_abb)))
}

compute_t_p <- function(att, se, df) {
  if (is.finite(att) && is.finite(se) && se > 0) 2 * stats::pt(-abs(att / se), df = df) else NA_real_
}

# ── One placebo replication ──────────────────────────────────────────────────
# `g_pool` is the multiset of treatment months (0 = never treated) to scatter
# across states at random. Permuting preserves the exact cohort structure.
one_rep <- function(seed, panel, g_pool, n_states) {
  suppressMessages(data.table::setDTthreads(1))
  fixest::setFixest_nthreads(1)
  set.seed(seed)
  ids <- sort(unique(panel$id))
  g_assign <- tibble(id = ids, g = sample(g_pool, length(ids), replace = FALSE))

  dat <- panel %>% select(id, t, y, state_abb) %>% left_join(g_assign, by = "id") %>%
    # g MUST be double for did::att_gt: it recodes never-treated g==0 to Inf,
    # and in an INTEGER column Inf truncates to NA, silently dropping every
    # never-treated unit (bug found 2026-08-28; see docs/findings-archive/).
    mutate(g = as.numeric(g),
           post_treat = as.integer(g > 0L & t >= g),
           first_treat = ifelse(g == 0L, NA_integer_, g),
           rel_time = ifelse(g == 0L, NA_integer_, t - g)) %>%
    as.data.frame()

  # A placebo draw can leave no post-treatment observations at all.
  if (sum(dat$post_treat) == 0) return(NULL)

  # Each estimator returns c(att, se, p) or NA on failure. Using a helper that
  # RETURNS its result (rather than assigning into an outer `out` list) keeps
  # every fit in its own scope, so one estimator's failure cannot corrupt or
  # abort the others.
  safe <- function(expr) {
    r <- tryCatch(suppressMessages(suppressWarnings(expr)), error = function(e) NULL)
    if (is.null(r) || !all(is.finite(r[1:2]))) c(NA_real_, NA_real_, NA_real_) else r
  }
  df_t <- n_states - 1

  twfe <- safe({
    f <- feols(y ~ post_treat | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE)
    c(as.numeric(coef(f)[1]), as.numeric(se(f)[1]), as.numeric(pvalue(f)[1]))
  })

  sunab_r <- safe({
    # sunab must use g (0 = never-treated): fixest drops NA-cohort rows, so
    # sunab(first_treat, t) silently ran without never-treated controls
    # (bug found 2026-08-28; see docs/findings-archive/). first_treat stays
    # NA-encoded for did_imputation below.
    fs <- feols(y ~ sunab(g, t) | id + t, data = dat, cluster = ~id,
                warn = FALSE, notes = FALSE)
    a <- summary(fs, agg = "att")
    c(as.numeric(coef(a)[1]), as.numeric(se(a)[1]), as.numeric(pvalue(a)[1]))
  })

  cs_r <- if (!SKIP_CS) safe({
    cs <- did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g", data = dat,
                      est_method = "reg", control_group = "notyettreated",
                      bstrap = FALSE, cband = FALSE, allow_unbalanced_panel = TRUE,
                      # faster_mode = FALSE required: the patched default TRUE routes
                      # through pre_process_did2, which truncates integer g==0 -> Inf
                      # to NA and drops never-treated units; also repo policy
                      # (found 2026-08-28).
                      print_details = FALSE, faster_mode = FALSE)
    ag <- did::aggte(cs, type = "simple")
    c(ag$overall.att, ag$overall.se, compute_t_p(ag$overall.att, ag$overall.se, df_t))
  }) else c(NA_real_, NA_real_, NA_real_)

  didimp_r <- if (HAS_DIDIMP) safe({
    di <- did_imputation(data = dat, yname = "y", gname = "first_treat", tname = "t",
                         idname = "id", cluster_var = "id")
    c(di$estimate[1], di$std.error[1], compute_t_p(di$estimate[1], di$std.error[1], df_t))
  }) else c(NA_real_, NA_real_, NA_real_)

  did2s_r <- if (HAS_DID2S) safe({
    d2 <- did2s(data = dat, yname = "y", first_stage = ~ 0 | id + t,
                second_stage = ~ post_treat, treatment = "post_treat", cluster_var = "id")
    v <- stats::vcov(d2)
    a <- as.numeric(coef(d2)[1]); s <- sqrt(diag(v))[1]
    c(a, s, compute_t_p(a, s, df_t))
  }) else c(NA_real_, NA_real_, NA_real_)

  tibble(seed = seed,
         twfe_att = twfe[1],     twfe_se = twfe[2],     twfe_p = twfe[3],
         sunab_att = sunab_r[1], sunab_se = sunab_r[2], sunab_p = sunab_r[3],
         cs_att = cs_r[1],       cs_se = cs_r[2],       cs_p = cs_r[3],
         didimp_att = didimp_r[1], didimp_se = didimp_r[2], didimp_p = didimp_r[3],
         did2s_att = did2s_r[1], did2s_se = did2s_r[2], did2s_p = did2s_r[3])
}

summarise_arm <- function(res, label) {
  ests <- c("twfe", "sunab", "cs", "didimp", "did2s")
  map_dfr(ests, function(e) {
    att <- res[[paste0(e, "_att")]]; se <- res[[paste0(e, "_se")]]; p <- res[[paste0(e, "_p")]]
    if (is.null(att)) return(NULL)
    ok <- is.finite(att) & is.finite(se) & is.finite(p)
    if (!any(ok)) return(tibble(arm = label, estimator = e, n_ok = 0L, reject = NA_real_,
                                mean_se = NA_real_, sd_att = NA_real_, se_over_sd = NA_real_))
    tibble(arm = label, estimator = e, n_ok = sum(ok),
           reject = mean(p[ok] < ALPHA), mean_se = mean(se[ok]),
           sd_att = sd(att[ok]), se_over_sd = mean(se[ok]) / sd(att[ok]))
  })
}

run_arm <- function(panel, g_pool, label) {
  n_states <- n_distinct(panel$id)
  cat(glue("\n--- Arm {label}: {n_states} states, {n_distinct(panel$t)} months, ",
           "{sum(g_pool > 0)} treated, {sum(g_pool == 0)} never-treated ---"), "\n")
  seeds <- SEED + seq_len(N_REPS)
  runner <- if (N_WORKERS > 1) function(f) mclapply(seeds, f, mc.cores = N_WORKERS) else
                                function(f) lapply(seeds, f)
  res <- runner(function(s) one_rep(s, panel, g_pool, n_states)) %>% compact() %>% bind_rows()
  cat(glue("  completed {nrow(res)} / {N_REPS} reps"), "\n")
  write_csv(res, file.path(OUT_DIR, glue("raw_{label}.csv")))
  summarise_arm(res, label)
}

# ── Assemble arms ────────────────────────────────────────────────────────────
panel_full <- build_panel(drop_covid = TRUE)
n_full <- n_distinct(panel_full$state_abb)
cat(glue("Spliced panel: {n_full} states, {n_distinct(panel_full$t)} months"), "\n")

sched_raw <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = panel_full$state_abb)

abb <- tibble(State = c(state.name, "District of Columbia"), state_abb = c(state.abb, "DC"))
lags <- read_csv("data/processed/cohort_ramp_lags.csv", show_col_types = FALSE) %>%
  left_join(abb, by = "State") %>% select(state_abb, ramp75_date)

states_tbl <- tibble(state_abb = sort(unique(panel_full$state_abb))) %>%
  left_join(sched_raw, by = "state_abb") %>%
  left_join(lags, by = "state_abb")

tmax <- max(panel_full$t)
pool_raw <- states_tbl %>%
  mutate(g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
         g = ifelse(g > tmax, 0L, g)) %>% pull(g)
pool_ramp <- states_tbl %>%
  mutate(g = ifelse(is.na(ramp75_date), 0L, ym_index(ramp75_date)),
         g = ifelse(g > tmax, 0L, g)) %>% pull(g)

# Arm C: clean pre-COVID panel, synthetic staggered dates matching the number
# of treated states, spread over the interior so every cohort has pre and post.
panel_pre <- build_panel(drop_covid = FALSE, max_date = as.Date("2020-02-29"))
t_pre <- sort(unique(panel_pre$t))
n_treated <- sum(pool_raw > 0)
interior <- t_pre[round(0.30 * length(t_pre)):round(0.80 * length(t_pre))]
set.seed(SEED)
pool_pre <- c(sample(interior, n_treated, replace = TRUE),
              rep(0L, n_distinct(panel_pre$id) - n_treated))

summ <- bind_rows(
  run_arm(panel_full, pool_raw,  "A_spliced_rawdates"),
  run_arm(panel_full, pool_ramp, "B_spliced_ramp75"),
  run_arm(panel_pre,  pool_pre,  "C_precovid_clean")
)

sink(file.path(OUT_DIR, "permutation_placebo_report.txt"), split = TRUE)
cat(glue("REAL-DATA PERMUTATION PLACEBO — {N_REPS} reps per arm, alpha = {ALPHA}\n\n"))
cat("Rejection rate should be 0.05 for a correctly sized estimator.\n")
cat("se_over_sd should be 1.0; below 1 means standard errors are too small.\n\n")
print(summ %>% mutate(across(where(is.numeric), ~round(.x, 3))) %>% as.data.frame(), row.names = FALSE)
cat("\nKEY CONTRASTS\n")
cat("  A vs C -> does the COVID splice break the estimator?\n")
cat("  A vs B -> does cohort-lagged treatment timing change size?\n")
sink()

write_csv(summ, file.path(OUT_DIR, "permutation_placebo_summary.csv"))
cat(glue("\nWrote {OUT_DIR}/\n"))
