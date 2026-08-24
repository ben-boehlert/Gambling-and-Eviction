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
TREAT_DEF       <- getenv1("TREAT_DEF", "raw")          # "raw" | "ramp75" | "shift12"
# CELL ANCHOR: which of the two dates times the SWITCH (and therefore which
# months the PMD baseline is drawn from). "event" is historical: under a
# redated spec (ramp75/shift12) the baseline is the PMD months ending just
# before MATURITY, i.e. inside the buildup window, so buildup exposure enters
# with negative weight through the baseline. "launch" anchors the cell at the
# online launch, so the baseline is pre-launch and clean, buildup exposure is
# carried by the LOW horizons, and the existing h >= 12 buildup window
# (pool_window) is what gives those horizons zero weight. Under TREAT_DEF=raw
# the two dates coincide and the setting is inert.
ANCHOR          <- getenv1("ANCHOR", "event")           # "event" | "launch"
stopifnot(ANCHOR %in% c("event", "launch"))
POST            <- as.integer(getenv1("POST", "18"))    # months after treatment
PRE             <- as.integer(getenv1("PRE",  "12"))    # months before (pre-trend)
PMD             <- as.integer(getenv1("PMD",  "3"))     # pre-mean-difference baseline
DROP_STRADDLING <- toupper(getenv1("DROP_STRADDLING", "FALSE")) == "TRUE"
BOOT_REPS       <- as.integer(getenv1("BOOT_REPS", "9999"))
JOINT_SEED      <- as.integer(getenv1("JOINT_SEED", "20260820"))  # joint pre-trend bootstrap
REWEIGHT        <- TRUE                                  # weight cells (see below)
# Cell weighting scheme. CORRECTED 2026-08-24 -- this script previously used
# 1/Var_cell(D) and called it EWATT; that weights each cell by its TOTAL size
# (switchers + surviving clean controls), which is neither the equally-
# weighted ATT nor the variance-weighted one. See lpdid_cell_weights() below.
#   ewatt    (default) Dube-Girardi-Jorda-Taylor sec. 2.5.2 reweighted LP-DiD
#   cellsize           the pre-2026-08-24 behavior, for paired comparison only
#   vwatt              unweighted OLS = the paper's variance-weighted LP-DiD
LPDID_WEIGHTS   <- match.arg(getenv1("LPDID_WEIGHTS", "ewatt"),
                             c("ewatt", "cellsize", "vwatt"))

# Output tag: the historical filenames are keyed on TREAT_DEF alone, so a
# launch-anchored run must NOT reuse them (it would silently overwrite the
# 2026-08-20 event-anchored results). Non-default anchors get their own suffix.
TAG <- if (identical(ANCHOR, "event")) TREAT_DEF else paste0(TREAT_DEF, "_launch")

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
  mutate(treat_date = dplyr::case_when(
           TREAT_DEF == "ramp75"  ~ ramp75_date,
           # Uniform NY-Fed-style buildup shift: g* = launch + 12 months. The
           # "pre-period" e in [-12,-2] then covers the state's own RAMP months,
           # so the pre-trend test doubles as a placebo on immature-market
           # effects. NOTE the shared caveat with ramp75: clean controls are
           # judged by the SHIFTED date, so launched-but-<12-months states sit
           # in the control pool (dirty-window contamination).
           TREAT_DEF == "shift12" ~ treat_start %m+% months(12L),
           TRUE                   ~ treat_start),
         # HYBRID CONTROL CODING (2026-08-20). Two dates, two roles:
         #   g        (event date, ramp75/shift12/raw) times the SWITCH;
         #   g_launch (actual online launch)           gates CONTROL status.
         # Under redated specs a launched-but-not-yet-mature state is neither
         # a valid switcher nor a valid counterfactual: it is DIRTY and must
         # be excluded, not pooled with the controls. Under raw dating the two
         # dates coincide and behavior is unchanged (regression-checked).
         g        = ifelse(is.na(treat_date),  NA_integer_, ym_index(treat_date)),
         g_launch = ifelse(is.na(treat_start), NA_integer_, ym_index(treat_start))) %>%
  # Anchor = the month a switcher switches. The switcher SET stays defined by
  # a non-missing `g` under either setting (see build_h), so a launched-but-
  # never-mature state remains a dirty non-switcher rather than becoming a new
  # treated unit -- only the switch month, and hence the baseline, moves.
  mutate(g_anchor = if (identical(ANCHOR, "launch")) g_launch else g)

panel <- p %>% left_join(treat_tbl %>% select(state_abb, g), by = "state_abb")
t_max <- max(panel$t)
# Treatment dates beyond the panel are never-treated for this sample.
panel <- panel %>% mutate(g = ifelse(!is.na(g) & g > t_max, NA_integer_, g))

n_treat <- n_distinct(panel$state_abb[!is.na(panel$g)])
cat(glue("LP-DiD | treatment definition: {TREAT_DEF} | cell anchor: {ANCHOR} ",
         "| PMD baseline: {PMD} month(s)"), "\n")
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
    # launch date gates control eligibility; a launch beyond the panel never
    # contaminates the sample window, so it stays NA (= control-eligible).
    g_l <- treat_tbl$g_launch[treat_tbl$state_abb == s]
    g_l <- if (length(g_l) == 0 || is.na(g_l) || g_l > t_max) NA_integer_ else g_l
    # ANCHOR month: event date (historical) or launch date. Gated on g_s being
    # a real switcher either way.
    g_a <- treat_tbl$g_anchor[treat_tbl$state_abb == s]
    g_a <- if (length(g_a) == 0 || is.na(g_a) || g_a > t_max) NA_integer_ else g_a
    map_dfr(t_grid, function(tt) {
      # switcher: this unit's ANCHOR month is exactly t (and it is a switcher
      # at all, i.e. it has an event date inside the panel).
      is_switch <- !is.na(g_s) && !is.na(g_a) && g_a == tt
      far <- if (side == "post") tt + h else tt - h
      # clean control: no LIVE GAMBLING through the far end of the window.
      # Judged by launch, not by the event date -- a live-but-immature market
      # is dirty, excluded from the cell entirely.
      is_clean_ctrl <- is.na(g_l) || g_l > max(tt, far)
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

# ── Cell weights ─────────────────────────────────────────────────────────────
# By Frisch-Waugh-Lovell, a cell-FE regression of dy on D contributes each
# cell's own DiD with weight  w_c * N_c * Var_c(D), and Var_c(D) = Dbar(1-Dbar).
# So the observation weight determines the estimand:
#
#   w = 1              -> cell weight  N_c Var_c(D)   VWATT (= Cengiz et al.
#                         2019 stacked regression)
#   w = 1/(1 - Dbar_c) -> cell weight  N_treated,c    EWATT (Dube, Girardi,
#                         Jorda & Taylor 2023 sec. 2.5.2: the weight is
#                         1/(omega_g,h / N_g), and omega/N_g is the D-residual
#                         of a TREATED unit, which equals 1 - Dbar_c)
#   w = 1/Var_c(D)     -> cell weight  N_c            NEITHER -- what this
#                         script did before 2026-08-24 while labelling it EWATT
#
# All three are convex combinations of cell-specific DiDs and so are unbiased
# under parallel trends; they differ in which cohorts and horizons get weight.
# The old scheme over-weights early cohorts and short horizons, where the
# clean-control pool is largest.
lpdid_cell_weights <- function(D, cell, scheme = LPDID_WEIGHTS) {
  dbar <- as.numeric(tapply(D, cell, mean)[as.character(cell)])
  switch(scheme,
         ewatt    = as.numeric(ifelse(is.finite(dbar) & dbar < 1,
                                      1 / (1 - dbar), NA_real_)),
         cellsize = {
           v <- dbar * (1 - dbar)
           as.numeric(ifelse(is.finite(v) & v > 0, 1 / v, NA_real_))
         },
         vwatt    = rep(1, length(D)),
         stop("unknown LPDID_WEIGHTS: ", scheme, call. = FALSE))
}

# ── Estimate one horizon ─────────────────────────────────────────────────────
# Weight cells per lpdid_cell_weights() so the pooled coefficient targets the
# scheme named by LPDID_WEIGHTS (default EWATT).
estimate_h <- function(d, h, side) {
  if (nrow(d) == 0 || sum(d$D_treat) == 0) return(NULL)
  d <- d %>% mutate(time = factor(t))

  if (REWEIGHT) {
    d$rw <- lpdid_cell_weights(d$D_treat, d$t)
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
          file.path(OUT_DIR, glue("treated_eligibility_{TAG}.csv")))

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
  d$rw <- lpdid_cell_weights(d$D_treat, d$time)
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

# ── Pooled effects by horizon window and cohort era ──────────────────────────
# NY Fed SR 1184 (Mangrum & Goss) buildup-window aggregation: their headline
# averages post-treatment event-time coefficients "beginning four quarters
# after legalization to allow credit outcomes to respond to the buildup in
# betting activity", and their baseline uses post-pandemic cohorts. Analogue
# here: (a) a buildup window pooling h >= 12 months only, and (b) an era split
# on the SWITCH month (pre-COVID vs post-COVID cohorts) -- the honest unit of
# analysis given that no LP-DiD comparison crosses the dropped COVID months,
# so the two eras are separate experiments pooled by the full estimate.
# Treatment dates are NOT shifted: early post-launch months stay coded treated
# (and stay excluded from clean controls); the buildup average just does not
# REPORT them. Era of a cell = era of its base period t (cells never straddle:
# the 17-month gap exceeds every usable horizon, verified n_straddling = 0).
pool_window <- function(dat, h_lo, h_hi, era, label) {
  d <- dat %>% filter(h >= h_lo, h <= h_hi)
  d <- switch(era,
    all  = d,
    pre  = d %>% filter(t <  G_DROP[1]),
    post = d %>% filter(t >  G_DROP[2]))
  base_row <- tibble(window = label, era = era, h_lo = h_lo, h_hi = h_hi,
                     att = NA_real_, se = NA_real_, p_analytic = NA_real_,
                     p_wild = NA_real_, n_switch_states = 0L,
                     n_control_states = NA_integer_, n_cells = NA_integer_,
                     n_obs = NA_integer_, note = NA_character_)
  if (nrow(d) == 0 || sum(d$D_treat) == 0)
    return(base_row %>% mutate(note = "no switch cells in this era/window"))
  d <- d %>% mutate(time = factor(paste(t, h, sep = "_")))
  d$rw <- lpdid_cell_weights(d$D_treat, d$time)
  d <- d %>% filter(is.finite(rw))
  if (nrow(d) == 0 || sum(d$D_treat) == 0 || n_distinct(d$D_treat) < 2)
    return(base_row %>% mutate(note = "not identified after reweighting"))
  fit <- tryCatch(feols(dy ~ D_treat | time, data = d, weights = ~rw,
                        vcov = ~state_abb, warn = FALSE, notes = FALSE),
                  error = function(e) NULL)
  if (is.null(fit) || !("D_treat" %in% names(coef(fit))))
    return(base_row %>% mutate(note = "fit failed"))
  pw <- if (HAS_BOOT) tryCatch(
    boottest(fit, param = "D_treat", clustid = "state_abb", B = BOOT_REPS,
             type = "rademacher")$p_val, error = function(e) NA_real_) else NA_real_
  base_row %>% mutate(
    att = as.numeric(coef(fit)["D_treat"]), se = as.numeric(se(fit)["D_treat"]),
    p_analytic = as.numeric(pvalue(fit)["D_treat"]), p_wild = as.numeric(pw),
    n_switch_states  = n_distinct(d$state_abb[d$D_treat == 1]),
    n_control_states = n_distinct(d$state_abb[d$D_treat == 0]),
    n_cells = n_distinct(d$time), n_obs = nobs(fit))
}

cat("Estimating window/era pooled effects...\n")
windows <- bind_rows(
  pool_window(pooled_dat, 0L,  POST, "all",  "full_pooled"),
  pool_window(pooled_dat, 12L, POST, "all",  "buildup_e12plus"),
  pool_window(pooled_dat, 0L,  POST, "pre",  "pre_covid_cohorts"),
  pool_window(pooled_dat, 0L,  POST, "post", "post_covid_cohorts"),
  pool_window(pooled_dat, 12L, POST, "pre",  "buildup_pre"),
  pool_window(pooled_dat, 12L, POST, "post", "buildup_post"))

# ── Joint pre-trend test ─────────────────────────────────────────────────────
# NOTE (2026-08-20). The original test was
#     z <- att/se ; pchisq(sum(z^2), df = length(z))
# which is the Wald statistic ONLY IF the horizon estimates are independent.
# They are not. In build_h() every horizon differences against the SAME
# baseline -- `base <- baseline_at(s, tt)` does not depend on h -- so all
# horizons share that additive term, on top of sharing states, the t grid and
# heavily overlapping clean-control sets. Shared baselines induce POSITIVE
# cross-horizon correlation, under which sum(z^2) keeps mean k but gains
# variance beyond chi-sq's 2k; the chi-sq tails are then too thin and the test
# OVER-rejects (in the perfect-correlation limit with k=11 the nominal 5%
# critical value corresponds to a true rejection rate near 18%).
#
# The fix stacks every pre-horizon into ONE regression with horizon-specific
# treatment indicators and horizon-specific time fixed effects -- algebraically
# identical per-horizon coefficients, but now with the full cross-horizon
# covariance available from a single state-clustered vcov.
#
# With k = 11 restrictions and only ~26 clusters the analytic Wald is still
# anti-conservative (Cameron-Gelbach-Miller), so the headline number is a
# null-imposed wild cluster (Rademacher) bootstrap; chi-sq and F(k, G-1) are
# reported alongside for comparison, and the naive statistic is retained purely
# to document what changed.
pre_rows <- es %>% filter(event_time < -1, is.finite(att), se > 0)

pretrend_p_naive <- if (nrow(pre_rows) > 0) {
  z <- pre_rows$att / pre_rows$se
  stats::pchisq(sum(z^2), df = nrow(pre_rows), lower.tail = FALSE)
} else NA_real_

#' Stack all pre-horizons, replicating estimate_h()'s per-horizon cell weights
build_pre_stack <- function(hs) {
  map_dfr(hs, function(h) {
    d <- build_h(h, "pre")
    if (nrow(d) == 0 || sum(d$D_treat) == 0) return(NULL)
    d <- d %>% mutate(time = factor(t))
    if (REWEIGHT) {
      d$rw <- lpdid_cell_weights(d$D_treat, d$t)
      d <- d %>% filter(is.finite(rw))
    } else d$rw <- 1
    if (nrow(d) == 0 || sum(d$D_treat) == 0) return(NULL)
    d %>% mutate(h = h)
  })
}

pre_h <- sort(unique(-pre_rows$event_time))
stk <- build_pre_stack(pre_h)

joint <- list(p_boot = NA_real_, p_chisq = NA_real_, p_F = NA_real_,
              W = NA_real_, k = 0L, G = NA_integer_, max_coef_gap = NA_real_)

if (!is.null(stk) && nrow(stk) > 0) {
  hs <- sort(unique(stk$h))
  # horizon-specific treatment indicators and horizon-specific time FE
  for (h in hs) stk[[paste0("Dh", h)]] <- stk$D_treat * (stk$h == h)
  stk$th <- interaction(stk$t, stk$h, drop = TRUE)
  dvars  <- paste0("Dh", hs)
  f_u <- as.formula(paste("dy ~", paste(dvars, collapse = " + "), "| th"))

  fit_u <- tryCatch(feols(f_u, data = stk, weights = ~rw, vcov = ~state_abb,
                          warn = FALSE, notes = FALSE), error = function(e) NULL)
  if (!is.null(fit_u)) {
    b <- coef(fit_u)[dvars]
    V <- vcov(fit_u)[dvars, dvars, drop = FALSE]
    k <- length(b); G <- n_distinct(stk$state_abb)

    # Sanity: stacking must reproduce the per-horizon ATTs exactly.
    ref <- pre_rows %>% transmute(h = -event_time, att) %>% arrange(h)
    gap <- suppressWarnings(max(abs(b[paste0("Dh", ref$h)] - ref$att), na.rm = TRUE))

    W <- tryCatch(as.numeric(t(b) %*% solve(V) %*% b), error = function(e) NA_real_)

    # Null-imposed wild cluster bootstrap of the joint Wald statistic.
    p_boot <- NA_real_
    if (is.finite(W)) {
      f_r <- as.formula("dy ~ 1 | th")
      fit_r <- tryCatch(feols(f_r, data = stk, weights = ~rw,
                              warn = FALSE, notes = FALSE), error = function(e) NULL)
      if (!is.null(fit_r)) {
        yhat_r <- as.numeric(predict(fit_r)); uhat_r <- as.numeric(residuals(fit_r))
        cl <- as.character(stk$state_abb); ucl <- unique(cl)
        B <- max(199L, min(BOOT_REPS, 1999L))
        set.seed(JOINT_SEED)
        Wb <- vapply(seq_len(B), function(bb) {
          v <- setNames(sample(c(-1, 1), length(ucl), replace = TRUE), ucl)
          stk$dy_b <- yhat_r + v[cl] * uhat_r
          f_b <- as.formula(paste("dy_b ~", paste(dvars, collapse = " + "), "| th"))
          fb <- tryCatch(feols(f_b, data = stk, weights = ~rw, vcov = ~state_abb,
                               warn = FALSE, notes = FALSE), error = function(e) NULL)
          if (is.null(fb)) return(NA_real_)
          bb_ <- coef(fb)[dvars]; Vb <- vcov(fb)[dvars, dvars, drop = FALSE]
          tryCatch(as.numeric(t(bb_) %*% solve(Vb) %*% bb_), error = function(e) NA_real_)
        }, numeric(1))
        Wb <- Wb[is.finite(Wb)]
        if (length(Wb) > 0) p_boot <- (1 + sum(Wb >= W)) / (length(Wb) + 1)
      }
    }
    joint <- list(
      p_boot  = p_boot,
      p_chisq = if (is.finite(W)) stats::pchisq(W, df = k, lower.tail = FALSE) else NA_real_,
      p_F     = if (is.finite(W)) stats::pf(W / k, df1 = k, df2 = max(G - 1L, 1L),
                                            lower.tail = FALSE) else NA_real_,
      W = W, k = k, G = G, max_coef_gap = gap)
  }
}

# Headline joint p-value: the bootstrap when available, else F, else chi-sq.
pretrend_p <- dplyr::coalesce(joint$p_boot, joint$p_F, joint$p_chisq)

# ── Report ───────────────────────────────────────────────────────────────────
sink(file.path(OUT_DIR, glue("lpdid_report_{TAG}.txt")), split = TRUE)
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

cat("\n=== POOLED EFFECTS BY HORIZON WINDOW AND COHORT ERA ===\n")
cat("Buildup window per NY Fed SR 1184: report only h >= 12 so markets have\n")
cat("ramped. Era = switch-month cohort; the two eras are disjoint experiments.\n")
cat("pct = effect in filings terms, exp(att) - 1.\n\n")
print(windows %>%
        mutate(pct = ifelse(is.finite(att), round(100 * (exp(att) - 1), 2), NA),
               across(c(att, se, p_analytic, p_wild), ~round(.x, 4))) %>%
        select(window, era, h_lo, h_hi, att, se, p_analytic, p_wild, pct,
               n_switch_states, n_control_states, n_cells, note) %>%
        as.data.frame(), row.names = FALSE)

cat(glue("\n=== JOINT PRE-TREND TEST (event time < -1) ===\n"))
cat(glue("  {joint$k} pre-period coefficients, {joint$G} state clusters\n"))
cat(glue("  Wald (full cross-horizon covariance, state-clustered) = ",
         "{ifelse(is.finite(joint$W), round(joint$W, 3), 'NA')}\n"))
cat(glue("  p, wild cluster bootstrap (HEADLINE) = ",
         "{ifelse(is.na(joint$p_boot), 'NA', round(joint$p_boot, 4))}\n"))
cat(glue("  p, F({joint$k}, {joint$G - 1})                        = ",
         "{ifelse(is.na(joint$p_F), 'NA', round(joint$p_F, 4))}\n"))
cat(glue("  p, chi-sq({joint$k})                          = ",
         "{ifelse(is.na(joint$p_chisq), 'NA', round(joint$p_chisq, 4))}\n"))
cat(glue("  [superseded] naive sum(z^2), independence assumed = ",
         "{ifelse(is.na(pretrend_p_naive), 'NA', round(pretrend_p_naive, 4))}\n"))
cat(glue("  stacking check: max |stacked coef - per-horizon ATT| = ",
         "{ifelse(is.finite(joint$max_coef_gap), signif(joint$max_coef_gap, 3), 'NA')}\n"))
cat("  The naive statistic assumed independent horizons. Every horizon shares\n")
cat("  the same baseline (build_h: base does not depend on h), so they are\n")
cat("  positively correlated and the naive test over-rejects. Do not cite it.\n")

cat("\n=== CLEAN-CONTROL AVAILABILITY BY HORIZON ===\n")
cat("The clean-control pool shrinks as the horizon grows; this is the binding\n")
cat("constraint on how far out LP-DiD can look with only 9 never-treated states.\n\n")
print(es %>% filter(side == "post") %>%
        select(event_time, n_switchers, n_clean_controls, n_straddling) %>%
        as.data.frame(), row.names = FALSE)
sink()

write_csv(es, file.path(OUT_DIR, glue("lpdid_event_study_{TAG}.csv")))
write_csv(windows, file.path(OUT_DIR, glue("lpdid_pooled_windows_{TAG}.csv")))
write_csv(tibble(k = joint$k, n_clusters = joint$G, wald = joint$W,
                 p_wild_bootstrap = joint$p_boot, p_F = joint$p_F,
                 p_chisq = joint$p_chisq, p_naive_superseded = pretrend_p_naive,
                 max_coef_gap = joint$max_coef_gap),
          file.path(OUT_DIR, glue("lpdid_pretrend_joint_{TAG}.csv")))
if (!is.null(pooled)) write_csv(pooled, file.path(OUT_DIR, glue("lpdid_pooled_{TAG}.csv")))

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
ggsave(file.path(OUT_DIR, glue("lpdid_event_study_{TAG}.png")), p1,
       width = 8, height = 4.5, dpi = 150)

cat(glue("\nWrote {OUT_DIR}/\n"))
