#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# LP-DiD (Dube, Girardi, Jorda & Taylor 2023, NBER w31184) on the state panel.
#
# WHY LP-DiD HERE. did2s fits Y(0) = alpha_i + lambda_t on ALL untreated
# observations and imputes counterfactuals from it, so a state's level shift
# across the COVID window propagates into every imputed counterfactual in the
# panel. LP-DiD never estimates alpha_i: the outcome at each horizon is a long
# difference from the month before that state's own treatment, so the unit
# effect is differenced out and identification is LOCAL in event time.
#
# Implemented directly with fixest, following the authors' own R example
# (github.com/danielegirardi/lpdid, "R example files"), rather than via the R
# port, because this panel needs gap handling no packaged version exposes.
#
#   post horizon h:  D_h y = y_{t+h} - y_{t-1}          (h = 0..POST)
#   pre  horizon h:  Dm_h y = y_{t-h} - y_{t-1}         (h = 2..PRE)
#   clean controls:  switchers at t, plus units not yet treated through t+h
#   regression:      feols(D_h y ~ D_treat | time, weights = ~rw, vcov = ~unit)
#
# THE COVID GAP — the reason this is hand-rolled. The panel drops the COVID
# window (default 2020-03..2021-07, matching R/power/config.R and the pretrends
# pipeline). Lags and leads are therefore computed on TRUE CALENDAR MONTHS, not
# on row position: a row-wise lag would silently make Feb 2020 the "t-1"
# baseline for a state treated in mid-2022, differencing straight across the
# pandemic without saying so. Every horizon whose [t-1, t+h] window spans the
# dropped window is counted and flagged, and can be excluded entirely with
# DROP_STRADDLING=TRUE.
#
# Inference: LP-DiD is plain OLS, so the wild cluster bootstrap applies
# directly per horizon — which matters at 26 state clusters. Reported alongside
# analytic cluster-robust SEs.
#
# Usage:
#   Rscript analysis/main/lpdid_statepanel.R
#   TREAT_DEF=ramp75 PMD=4 DROP_STRADDLING=TRUE Rscript analysis/main/lpdid_statepanel.R
#   DROP_END=2022-03-31 Rscript analysis/main/lpdid_statepanel.R   # calibration-script window
#
# NOTE: results in output/lpdid_statepanel/ generated before 2026-08-17 used
# DROP_END = 2022-03-31 and are NOT comparable to the current default. Rerun
# before quoting any of them.
# Output: output/lpdid_statepanel/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(fixest); library(glue)
})
HAS_BOOT <- requireNamespace("fwildclusterboot", quietly = TRUE)
if (HAS_BOOT) suppressMessages(library(fwildclusterboot))

theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
TREAT_DEF       <- getenv1("TREAT_DEF", "raw")          # "raw" | "ramp75"
POST            <- as.integer(getenv1("POST", "18"))    # months after treatment
PRE             <- as.integer(getenv1("PRE",  "12"))    # months before (pre-trend)
PMD             <- as.integer(getenv1("PMD",  "3"))     # pre-mean-difference baseline
DROP_STRADDLING <- toupper(getenv1("DROP_STRADDLING", "FALSE")) == "TRUE"
BOOT_REPS       <- as.integer(getenv1("BOOT_REPS", "9999"))
REWEIGHT        <- TRUE                                  # EWATT, not VWATT

OUT_DIR <- "output/lpdid_statepanel"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# COVID drop window. Default matches the two specs this script has to be
# comparable with: R/power/config.R (covid_drop) and the pretrends pipeline
# default in scripts/run_pretrends_statepanel.sh, both 2020-03-01..2021-07-31.
#
# This script previously hard-coded DROP_END = 2022-03-31, copied from
# analysis/diagnostics/cs_calibration_multi_estimator.R, which is 8 months
# longer than either. The length is not cosmetic here: a switcher is usable
# only if its pre-treatment baseline months exist in the panel, so extending
# the hole silently disqualifies states whose treatment falls inside it (NY
# 2022-01 and AR 2022-03 among them). Override deliberately, not by drift.
MIN_DATE   <- as.Date(getenv1("MIN_DATE",   "2016-01-01"))
MAX_DATE   <- as.Date(getenv1("MAX_DATE",   "2024-12-31"))
DROP_START <- as.Date(getenv1("DROP_START", "2020-03-01"))
DROP_END   <- as.Date(getenv1("DROP_END",   "2021-07-31"))

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))
G_DROP <- c(ym_index(DROP_START), ym_index(DROP_END))    # gap in calendar-month index

# ── Panel ────────────────────────────────────────────────────────────────────
p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb), month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

cov_tbl <- p %>% count(state_abb, name = "n")
p <- p %>% filter(state_abb %in% cov_tbl$state_abb[cov_tbl$n >= max(cov_tbl$n)])
k  <- n_distinct(p$state_abb)
cm <- p %>% count(month_date, name = "j") %>% filter(j == k) %>% pull(month_date)
p  <- p %>% filter(month_date %in% cm) %>%
  mutate(y = log1p(pmax(filings_count, 0)), t = ym_index(month_date))

sched <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = p$state_abb)
abb  <- tibble(State = c(state.name, "District of Columbia"), state_abb = c(state.abb, "DC"))
lags <- read_csv("data/processed/cohort_ramp_lags.csv", show_col_types = FALSE) %>%
  left_join(abb, by = "State") %>% select(state_abb, ramp75_date)

treat_tbl <- tibble(state_abb = sort(unique(p$state_abb))) %>%
  left_join(sched, by = "state_abb") %>% left_join(lags, by = "state_abb") %>%
  mutate(treat_date = if (TREAT_DEF == "ramp75") ramp75_date else treat_start,
         g = ifelse(is.na(treat_date), NA_integer_, ym_index(treat_date)))

panel <- p %>% left_join(treat_tbl %>% select(state_abb, g), by = "state_abb")
t_max <- max(panel$t)
# Treatment dates beyond the panel are never-treated for this sample.
panel <- panel %>% mutate(g = ifelse(!is.na(g) & g > t_max, NA_integer_, g))

n_treat <- n_distinct(panel$state_abb[!is.na(panel$g)])
cat(glue("LP-DiD | treatment definition: {TREAT_DEF} | PMD baseline: {PMD} month(s)"), "\n")
cat(glue("Panel: {n_distinct(panel$state_abb)} states ({n_treat} treated, ",
         "{n_distinct(panel$state_abb) - n_treat} never-treated), {n_distinct(panel$t)} months"), "\n")
cat(glue("Dropped COVID window in calendar index: [{G_DROP[1]}, {G_DROP[2]}]"), "\n\n")

# Calendar-indexed lookup: y_lookup[[state]][[as.character(t)]]. Absent months
# (the COVID gap, or outside coverage) return NA rather than an adjacent month.
y_lookup <- panel %>% select(state_abb, t, y) %>%
  { split(setNames(.$y, .$t), .$state_abb) }

y_at <- function(state, tt) {
  v <- y_lookup[[state]][as.character(tt)]
  as.numeric(ifelse(is.na(names(v)) | is.na(v), NA_real_, v))
}

# Baseline: mean of the PMD months ending at t-1 (pre-mean differencing).
# PMD = 1 reproduces the plain t-1 baseline of the paper's default.
baseline_at <- function(state, tt) {
  b <- vapply(seq(tt - PMD, tt - 1L), function(s) y_at(state, s), numeric(1))
  if (any(is.na(b))) NA_real_ else mean(b)
}

spans_gap <- function(lo, hi) lo <= G_DROP[2] && hi >= G_DROP[1]

# ── Build the LP-DiD stacked sample for one horizon ─────────────────────────
# For each (unit, base period t) we need: a treatment-switch indicator at t,
# and the clean-control condition. Absorbing treatment, so a unit is a clean
# control at horizon h if it is still untreated at t+h.
states <- sort(unique(panel$state_abb))
t_grid <- sort(unique(panel$t))

build_h <- function(h, side = c("post", "pre")) {
  side <- match.arg(side)
  rows <- map_dfr(states, function(s) {
    g_s <- treat_tbl$g[treat_tbl$state_abb == s]
    g_s <- if (length(g_s) == 0 || is.na(g_s) || g_s > t_max) NA_integer_ else g_s
    map_dfr(t_grid, function(tt) {
      # switcher: this unit becomes treated exactly at t
      is_switch <- !is.na(g_s) && g_s == tt
      # clean control: never treated, or not yet treated at the far end
      far <- if (side == "post") tt + h else tt - h
      is_clean_ctrl <- is.na(g_s) || g_s > max(tt, far)
      if (!is_switch && !is_clean_ctrl) return(NULL)

      base <- baseline_at(s, tt)
      yfar <- y_at(s, far)
      if (is.na(base) || is.na(yfar)) return(NULL)

      lo <- min(far, tt - PMD); hi <- max(far, tt - 1L)
      tibble(state_abb = s, t = tt, D_treat = as.integer(is_switch),
             dy = yfar - base, straddles = spans_gap(lo, hi))
    })
  })
  if (nrow(rows) == 0) return(rows)
  if (DROP_STRADDLING) rows <- rows %>% filter(!straddles)
  # A horizon is identified only if both switchers and controls survive.
  rows %>% group_by(t) %>% filter(n_distinct(D_treat) == 2) %>% ungroup()
}

# ── Estimate one horizon ─────────────────────────────────────────────────────
# reweight: regress D_treat on time FE within the clean sample, invert the
# implied OLS variance weights so each treated unit counts equally (EWATT).
estimate_h <- function(d, h, side) {
  if (nrow(d) == 0 || sum(d$D_treat) == 0) return(NULL)
  d <- d %>% mutate(time = factor(t))

  if (REWEIGHT) {
    aux <- feols(D_treat ~ 1 | time, data = d, warn = FALSE, notes = FALSE)
    w <- as.numeric(residuals(aux))^2
    # as.numeric(): tapply returns an ARRAY, and fixest rejects array weights.
    wt <- as.numeric(tapply(w, d$t, mean)[as.character(d$t)])
    d$rw <- as.numeric(ifelse(is.finite(wt) & wt > 0, 1 / wt, NA_real_))
    d <- d %>% filter(is.finite(rw))
  } else d$rw <- 1

  if (nrow(d) == 0 || sum(d$D_treat) == 0) return(NULL)

  fit <- tryCatch(
    feols(dy ~ D_treat | time, data = d, weights = ~rw, vcov = ~state_abb,
          warn = FALSE, notes = FALSE),
    error = function(e) NULL)
  if (is.null(fit) || !("D_treat" %in% names(coef(fit)))) return(NULL)

  p_wild <- NA_real_
  if (HAS_BOOT) p_wild <- tryCatch({
    # fe = NULL is REQUIRED: boottest does not support WLS with absorbed fixed
    # effects. Dummy-expanding ~83 time effects is cheap (unlike the 1,200
    # county FEs that motivated fe = "id" in the power framework).
    bt <- boottest(fit, param = "D_treat", clustid = "state_abb", B = BOOT_REPS,
                   type = "rademacher")
    bt$p_val
  }, error = function(e) NA_real_)

  tibble(side = side,
         event_time = if (side == "post") h else -h,
         att = as.numeric(coef(fit)["D_treat"]),
         se  = as.numeric(se(fit)["D_treat"]),
         p_analytic = as.numeric(pvalue(fit)["D_treat"]),
         p_wild = p_wild,
         n_obs = nobs(fit),
         n_switchers = sum(d$D_treat),
         n_clean_controls = sum(d$D_treat == 0),
         n_straddling = sum(d$straddles))
}

# ── Event study ──────────────────────────────────────────────────────────────
# ── Which treated states can enter at all? ───────────────────────────────────
# A state can only be a switcher if its baseline months (t-PMD .. t-1) exist in
# the panel. States legalizing INSIDE the dropped COVID window have no baseline
# and are structurally excluded — the LP-DiD analogue of the COVID problem.
usable <- treat_tbl %>% filter(!is.na(g), g <= t_max) %>%
  rowwise() %>%
  mutate(has_baseline = !is.na(baseline_at(state_abb, g)),
         g_in_gap = g >= G_DROP[1] & g <= G_DROP[2]) %>%
  ungroup()
cat("=== TREATED-STATE ELIGIBILITY ===\n")
cat(glue("  Usable as switchers: {sum(usable$has_baseline)} of {nrow(usable)} ",
         "({paste(sort(usable$state_abb[usable$has_baseline]), collapse=', ')})"), "\n")
cat(glue("  Excluded (no pre-treatment baseline in panel): ",
         "{paste(sort(usable$state_abb[!usable$has_baseline]), collapse=', ')}"), "\n")
cat(glue("  ...of which legalized INSIDE the dropped COVID window: ",
         "{paste(sort(usable$state_abb[usable$g_in_gap]), collapse=', ')}"), "\n\n")
write_csv(usable %>% select(state_abb, g, has_baseline, g_in_gap),
          file.path(OUT_DIR, glue("treated_eligibility_{TREAT_DEF}.csv")))

cat("Estimating event study...\n")
es <- bind_rows(
  map_dfr(0:POST, function(h) { d <- build_h(h, "post"); estimate_h(d, h, "post") }),
  map_dfr(2:PRE,  function(h) { d <- build_h(h, "pre");  estimate_h(d, h, "pre") })
) %>% arrange(event_time)

# Reference period: t-1 is the baseline by construction, so ATT(-1) = 0.
es <- bind_rows(es, tibble(side = "pre", event_time = -1, att = 0, se = 0,
                           p_analytic = NA, p_wild = NA, n_obs = NA,
                           n_switchers = NA, n_clean_controls = NA,
                           n_straddling = NA)) %>% arrange(event_time)

# ── Pooled post-treatment effect ─────────────────────────────────────────────
cat("Estimating pooled effect...\n")
pooled_dat <- map_dfr(0:POST, function(h) build_h(h, "post") %>% mutate(h = h))
pooled <- if (nrow(pooled_dat) > 0) {
  d <- pooled_dat %>% mutate(time = factor(paste(t, h, sep = "_")))
  aux <- feols(D_treat ~ 1 | time, data = d, warn = FALSE, notes = FALSE)
  w <- as.numeric(residuals(aux))^2
  wt <- as.numeric(tapply(w, d$time, mean)[as.character(d$time)])
  d$rw <- as.numeric(ifelse(is.finite(wt) & wt > 0, 1 / wt, NA_real_))
  d <- d %>% filter(is.finite(rw))
  fit <- feols(dy ~ D_treat | time, data = d, weights = ~rw, vcov = ~state_abb,
               warn = FALSE, notes = FALSE)
  pw <- if (HAS_BOOT) tryCatch(
    boottest(fit, param = "D_treat", clustid = "state_abb", B = BOOT_REPS,
             type = "rademacher")$p_val, error = function(e) NA_real_) else NA_real_
  tibble(att = as.numeric(coef(fit)["D_treat"]), se = as.numeric(se(fit)["D_treat"]),
         p_analytic = as.numeric(pvalue(fit)["D_treat"]), p_wild = pw,
         n_obs = nobs(fit), n_straddling = sum(d$straddles))
} else NULL

# ── Joint pre-trend test ─────────────────────────────────────────────────────
pre_rows <- es %>% filter(event_time < -1, is.finite(att), se > 0)
pretrend_p <- if (nrow(pre_rows) > 0) {
  z <- pre_rows$att / pre_rows$se
  stats::pchisq(sum(z^2), df = nrow(pre_rows), lower.tail = FALSE)
} else NA_real_

# ── Report ───────────────────────────────────────────────────────────────────
sink(file.path(OUT_DIR, glue("lpdid_report_{TREAT_DEF}.txt")), split = TRUE)
cat(glue("LP-DiD — Dube, Girardi, Jorda & Taylor (2023)\n"))
cat(glue("Treatment: {TREAT_DEF} | PMD baseline: {PMD} | drop straddling horizons: {DROP_STRADDLING}\n"))
cat(glue("Panel: {n_distinct(panel$state_abb)} states, {n_treat} treated, ",
         "{n_distinct(panel$t)} months, COVID window {DROP_START}..{DROP_END} dropped\n\n"))

cat("=== EVENT STUDY ===\n")
cat("n_straddling counts observations whose [t-PMD, t+h] window spans the dropped\n")
cat("COVID months. Those comparisons difference across the pandemic.\n\n")
print(es %>% mutate(across(c(att, se, p_analytic, p_wild), ~round(.x, 4))) %>%
        as.data.frame(), row.names = FALSE)

if (!is.null(pooled)) {
  cat("\n=== POOLED POST-TREATMENT ATT (horizons 0..", POST, ") ===\n", sep = "")
  print(pooled %>% mutate(across(c(att, se, p_analytic, p_wild), ~round(.x, 4))) %>%
          as.data.frame(), row.names = FALSE)
  cat(glue("\n  In filings terms: {round(100 * (exp(pooled$att) - 1), 2)}% ",
           "(95% CI {round(100 * (exp(pooled$att - 1.96 * pooled$se) - 1), 2)}% to ",
           "{round(100 * (exp(pooled$att + 1.96 * pooled$se) - 1), 2)}%)"), "\n")
}

cat(glue("\n=== JOINT PRE-TREND TEST (event time < -1) ===\n",
         "  chi-sq p = {ifelse(is.na(pretrend_p), 'NA', round(pretrend_p, 4))} ",
         "on {nrow(pre_rows)} pre-period coefficients\n"))

cat("\n=== CLEAN-CONTROL AVAILABILITY BY HORIZON ===\n")
cat("The clean-control pool shrinks as the horizon grows; this is the binding\n")
cat("constraint on how far out LP-DiD can look with only 9 never-treated states.\n\n")
print(es %>% filter(side == "post") %>%
        select(event_time, n_switchers, n_clean_controls, n_straddling) %>%
        as.data.frame(), row.names = FALSE)
sink()

write_csv(es, file.path(OUT_DIR, glue("lpdid_event_study_{TREAT_DEF}.csv")))
if (!is.null(pooled)) write_csv(pooled, file.path(OUT_DIR, glue("lpdid_pooled_{TREAT_DEF}.csv")))

# ── Figure ───────────────────────────────────────────────────────────────────
pl <- es %>% filter(is.finite(att)) %>%
  mutate(lo = att - 1.96 * se, hi = att + 1.96 * se,
         flag = !is.na(n_straddling) & n_straddling > 0)
p1 <- ggplot(pl, aes(event_time, att)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey60") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15) +
  geom_line() + geom_point(aes(shape = flag), size = 2) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  labs(x = "Months since treatment", y = "ATT (log filings)",
       subtitle = str_wrap(glue("LP-DiD, {TREAT_DEF} dates, PMD baseline {PMD}. Hollow points have comparisons differencing across the dropped COVID window."), 95))
ggsave(file.path(OUT_DIR, glue("lpdid_event_study_{TREAT_DEF}.png")), p1,
       width = 8, height = 4.5, dpi = 150)

cat(glue("\nWrote {OUT_DIR}/\n"))
