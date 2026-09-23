#!/usr/bin/env Rscript
################################################################################
# power_simulation_twfe_donorpath_v2.R
#
# Second pass on the donor-path TWFE power sim. Implements the reviewer
# amendments in quality_reports/plans/2026-09-21_twfe_donorpath_power_sim.md
# ("Review amendments" section), as refined by the coordinator's follow-up
# message (2026-09-21):
#
#   R1  exact-size critical value: empirical 95th pct of |att0/se0| (analytic)
#       and an analogous CI-rescale calibration for the wild arm; reported
#       BESIDE the nominal t_{G-1} / CI-based rejection rate in mde.csv.
#   R2  ex-ante eligible donor set (never-treated states covering >=80% of the
#       SCENARIO WINDOW's months -- one set, not a per-host restriction), no
#       row-dropping: every host draws one primary + one backup donor
#       (independent draws, same host sign); a missing primary month is
#       filled from the backup; only a simultaneous primary+backup gap drops
#       a state-month (logged).
#   R3  leave-one-eligible-donor-out: re-run with each eligible donor excluded
#       (400 sims, analytic only), write mde_leave_one_donor_out.csv.
#   S1  rescaling sensitivity: donor paths standardized to unit SD by their
#       OWN in-window SD, then scaled to the receiving host's own in-window
#       untreated residual SD (>=12 obs; else median of qualifying hosts).
#   Q3  secondary row keeping already-treated states (DROP_ALREADY_TREATED=F).
#
# Pass 3 (2026-09-21 afternoon) additions -- code-review fixes + WA/MN
# exclusion (see plan file, "## Pass 3" section). Edited IN PLACE (per the
# task spec); pass-1/pass-2 outputs under _v20260921/ and _v20260921b/ are
# untouched. New output root: output/twfe_power_donorpath_v20260921c/.
#   1  Wild arm seeded through BOTH base R (set.seed) and dqrng::dqset.seed
#      (fwildclusterboot's `sampling="dqrng"` default bypasses base R's RNG
#      stream) -- per sim, seed derived from that sim's own seed, so results
#      do not depend on N_WORKERS.
#   2  Q3 fix: yhat<-0 (not row-dropped) for states with no in-window
#      untreated obs; new check C6 verifies att0/se0 invariance to yhat.
#   3  DF_CORRECT option: donor residual matrix inflated by sqrt(N/(N-K)).
#   4  wild_failed flag per sim; wild MDE reported both with failed draws
#      dropped and with failed draws replaced by that sim's analytic CI.
#   5  EXCLUDE_STATES option: named states removed before anything else.
#
# This file does not edit power_simulation_twfe_donorpath.R (pass 1) or its
# outputs. All outputs from this pass go under a NEW output root
# (output/twfe_power_donorpath_v20260921b/ for pass 2,
#  output/twfe_power_donorpath_v20260921c/ for pass 3) so earlier passes are
# preserved.
#
# Blind throughout: only untreated observations feed the noise; the real
# post-launch outcome is never estimated or printed.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(fixest)
  library(glue)
})

source("utils/eviction_treatment_schedule.R")

wild_available <- requireNamespace("fwildclusterboot", quietly = TRUE)

# ----------------------------- helpers ----------------------------------------

getenv1 <- function(key, default = "") { v <- Sys.getenv(key, unset = default); if (!nzchar(v)) default else v }
parse_bool <- function(x, default = FALSE) { if (!nzchar(x)) return(default); toupper(trimws(x)) %in% c("1","TRUE","T","YES","Y") }
parse_num  <- function(x, default = NA_real_) { if (!nzchar(x)) return(default); suppressWarnings(as.numeric(x)) }
parse_int  <- function(x, default = NA_integer_) { if (!nzchar(x)) return(default); suppressWarnings(as.integer(x)) }
ym_index <- function(date) { y <- as.integer(format(date,"%Y")); m <- as.integer(format(date,"%m")); as.integer(y*12L+m) }
log_line <- function(path, msg) cat(msg, "\n", file = path, append = TRUE)
safe_write_csv <- function(df, path) { dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); readr::write_csv(df, path) }
mde_from_curve <- function(delta_grid, power_grid, target = 0.80) {
  power_grid[is.na(power_grid)] <- 0
  above <- which(power_grid >= target)
  if (length(above) == 0) return(NA_real_)
  k <- min(above)
  if (k == 1) return(delta_grid[1])
  d1 <- delta_grid[k-1]; d2 <- delta_grid[k]; p1 <- power_grid[k-1]; p2 <- power_grid[k]
  if (p2 == p1) return(d2)
  d1 + (target - p1) * (d2 - d1) / (p2 - p1)
}
pct_from_log <- function(x) exp(x) - 1
safe_sample <- function(pool, n) if (length(pool) == 1) rep(pool, n) else sample(pool, n, replace = TRUE)

# ----------------------------- config -------------------------------------

SCENARIO   <- tolower(getenv1("SCENARIO", "start202206"))
if (!SCENARIO %in% c("full", "start202206")) stop("SCENARIO must be full or start202206")

RUN_MODE   <- tolower(getenv1("RUN_MODE", "main"))   # main | loo
RESCALE_DONORS <- parse_bool(getenv1("RESCALE_DONORS", "FALSE"), FALSE)
DROP_ALREADY_TREATED <- parse_bool(getenv1("DROP_ALREADY_TREATED", "TRUE"), TRUE)
MIN_ELIGIBLE_COVERAGE <- parse_num(getenv1("MIN_ELIGIBLE_COVERAGE", "0.80"), 0.80)
MIN_DONOR_OWN_OBS <- parse_int(getenv1("MIN_DONOR_OWN_OBS", "12"), 12L)  # S1 host-scale threshold
DF_CORRECT <- parse_bool(getenv1("DF_CORRECT", "FALSE"), FALSE)  # Pass-3 fix 3

# Pass-3 fix 5: states removed from the panel before anything else -- neither
# controls, switchers, nor noise donors. Comma list, e.g. "WA,MN".
# Default (2026-09-23): DESIGN_EXCLUDED_STATES from utils/eviction_treatment_schedule.R
# (HI, MS, MN, WA; NV is dropped separately below as pre-PASPA) -- the same state set
# as analysis/main/lpdid_statepanel.R. Until 2026-09-21 the default was MN, WA only, so
# HI and MS stayed in as never-treated controls and the TWFE MDE was not on LP-DiD's
# state set. Pass EXCLUDE_STATES=none to keep every state.
EXCLUDE_STATES_RAW <- getenv1("EXCLUDE_STATES",
  paste(setdiff(DESIGN_EXCLUDED_STATES, PRE_PASPA_SPORTS_BETTING), collapse = ","))
EXCLUDE_STATES <- if (tolower(EXCLUDE_STATES_RAW) == "none") character(0) else toupper(trimws(strsplit(EXCLUDE_STATES_RAW, ",")[[1]]))
EXCLUDE_REASON <- getenv1("EXCLUDE_REASON", "DESIGN_EXCLUDED_STATES default: HI/MS short LSC series; WA pre-filing program 2021-11..2023-06; MN expungement (see utils/eviction_treatment_schedule.R)")

N_SIMS       <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
RUN_WILD     <- parse_bool(getenv1("RUN_WILD", "TRUE"), TRUE) && wild_available
N_WILD_SIMS  <- parse_int(getenv1("N_WILD_SIMS", "1000"), 1000L)
WILD_B       <- parse_int(getenv1("WILD_B", "999"), 999L)
SEED         <- parse_int(getenv1("SEED", "20260921"), 20260921L)
ALPHA        <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
N_WORKERS    <- min(6L, parse_int(getenv1("N_WORKERS", "6"), 6L))
OUT_DIR      <- getenv1("OUT_DIR", "output/twfe_power_donorpath_default/start202206_design_excl")
LOO_N_SIMS   <- parse_int(getenv1("LOO_N_SIMS", "400"), 400L)

MDE_GRID_MAX <- 0.40; MDE_GRID_STEP <- 0.001; grid <- seq(0, MDE_GRID_MAX, by = MDE_GRID_STEP)
MC_BOOT_B <- 500L
COVID_START <- as.Date("2020-03-01"); COVID_END <- as.Date("2021-06-01")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)
log_line(RUN_LOG, "=== TWFE DONOR-PATH POWER SIM v2 (R1/R2/R3/S1/Q3 + Pass-3 fixes 1-5) ===")
log_line(RUN_LOG, glue("R: {R.version.string}"))
log_line(RUN_LOG, glue("SCENARIO={SCENARIO}  RUN_MODE={RUN_MODE}  RESCALE_DONORS={RESCALE_DONORS}  DROP_ALREADY_TREATED={DROP_ALREADY_TREATED}"))
log_line(RUN_LOG, glue("MIN_ELIGIBLE_COVERAGE={MIN_ELIGIBLE_COVERAGE}  N_SIMS={N_SIMS}  SEED={SEED}  RUN_WILD={RUN_WILD}  N_WILD_SIMS={N_WILD_SIMS}  N_WORKERS={N_WORKERS}"))
log_line(RUN_LOG, glue("DF_CORRECT={DF_CORRECT}  EXCLUDE_STATES={paste(EXCLUDE_STATES, collapse=',')}  EXCLUDE_REASON={EXCLUDE_REASON}"))

# ----------------------------- load panel + schedule -----------------------

panel_file <- "data/raw/state_month_panel_with_treatment.csv"
treat_file <- "data/raw/sports_gambling_legalization_dates.csv"

panel0 <- read_csv(panel_file, show_col_types = FALSE) %>%
  filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING) %>%
  mutate(month_date = as.Date(month_date))
sched <- eviction_adoption_outcomes(treat_file, "online_start_date", censor_end = max(panel0$month_date)) %>%
  filter(state_abb %in% unique(panel0$state_abb)) %>% select(state_abb, adopt_date)
panel0 <- panel0 %>% left_join(sched, by = "state_abb")

if (length(EXCLUDE_STATES) > 0) {
  present <- intersect(EXCLUDE_STATES, unique(panel0$state_abb))
  missing_excl <- setdiff(EXCLUDE_STATES, present)
  if (length(missing_excl) > 0) log_line(RUN_LOG, glue("WARNING: EXCLUDE_STATES names not in panel: {paste(missing_excl, collapse=', ')}"))
  n_before_excl <- n_distinct(panel0$state_abb)
  panel0 <- panel0 %>% filter(!state_abb %in% EXCLUDE_STATES)
  log_line(RUN_LOG, glue("EXCLUDE_STATES: removed {paste(present, collapse=', ')} ({n_before_excl} -> {n_distinct(panel0$state_abb)} states). Reason: {ifelse(nzchar(EXCLUDE_REASON), EXCLUDE_REASON, '(none given)')}"))
} else {
  log_line(RUN_LOG, "EXCLUDE_STATES: none")
}
state_treat <- panel0 %>% distinct(state_abb, adopt_date)

MIN_DATE <- if (SCENARIO == "start202206") as.Date("2022-06-01") else as.Date(NA)
panel <- panel0
already_treated <- character(0)
if (!is.na(MIN_DATE)) {
  panel <- panel %>% filter(month_date >= MIN_DATE)
  already_treated <- state_treat %>% filter(!is.na(adopt_date), adopt_date < MIN_DATE) %>% pull(state_abb)
  if (DROP_ALREADY_TREATED) {
    n_before <- n_distinct(panel$state_abb)
    panel <- panel %>% filter(!state_abb %in% already_treated)
    log_line(RUN_LOG, glue("Dropped {length(already_treated)} already-treated state(s) before {MIN_DATE}: {paste(sort(already_treated), collapse=', ')} ({n_before} -> {n_distinct(panel$state_abb)} states)"))
  } else {
    log_line(RUN_LOG, glue("Q3: KEEPING {length(already_treated)} already-treated state(s) before {MIN_DATE}: {paste(sort(already_treated), collapse=', ')}"))
  }
}
if (SCENARIO == "full") {
  n_before <- nrow(panel)
  panel <- panel %>% filter(!(month_date >= COVID_START & month_date < COVID_END))
  log_line(RUN_LOG, glue("Q1(b): dropped COVID months [{COVID_START},{COVID_END}) from 'full' analysis panel: {n_before} -> {nrow(panel)} rows"))
}

panel <- panel %>% mutate(t = ym_index(month_date), g = ifelse(is.na(adopt_date), 0L, ym_index(adopt_date)), state_abb = as.character(state_abb))
target_states <- sort(unique(panel$state_abb))
panel$id <- match(panel$state_abb, target_states)
g_bad <- panel %>% group_by(state_abb) %>% summarise(ng = n_distinct(g), .groups = "drop") %>% filter(ng != 1)
if (nrow(g_bad) > 0) stop("g not constant within state", call. = FALSE)
panel <- panel %>% mutate(untreated_obs = (g == 0L) | (t < g), post = as.integer((g > 0L) & (t >= g)))

# ----------------------------- outcome + FE fit -----------------------------

panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
base_fe <- panel %>% filter(untreated_obs, is.finite(y))
untreated_by_t <- base_fe %>% count(t, name = "n_untreated")
missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
if (length(missing_t) > 0) {
  log_line(RUN_LOG, glue("WARNING: dropping {length(missing_t)} month(s) with zero untreated obs: {paste(missing_t, collapse=',')}"))
  panel <- panel %>% filter(!t %in% missing_t); base_fe <- base_fe %>% filter(!t %in% missing_t)
}
set.seed(SEED)
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
# Pass-3 fix 2 (Q3 row is vacuous): att0/se0 from `feols(y ~ post | id + t)` do
# NOT depend on yhat, because yhat lies exactly in the span of that same
# regression's own id and t fixed effects, which fully re-absorb any level
# added to y (this is verified empirically by check C6 below). So states with
# no untreated in-window observations (predict() returns NA for an id level
# fe_fit never saw -- e.g. already-treated states under Q3's
# DROP_ALREADY_TREATED=FALSE) get yhat <- 0 instead of being dropped; they
# stay in the panel as pure post-only rows for those states/months.
n_yhat_zeroed <- sum(!is.finite(panel$yhat))
if (n_yhat_zeroed > 0) {
  zeroed_states <- sort(unique(panel$state_abb[!is.finite(panel$yhat)]))
  log_line(RUN_LOG, glue("Q3 fix: yhat <- 0 for {n_yhat_zeroed} non-finite rows (states with no in-window untreated obs: {paste(zeroed_states, collapse=', ')}) -- NOT dropped"))
  # A zero for SOME rows is not in the id + t span when other rows keep a
  # month-varying yhat (pass-3 C3/C6 failure on the Q3 row). Zero for ALL rows is.
  panel$yhat <- 0
}
# feols drops singleton observations silently; keep base_fe aligned with its residuals.
base_fe <- base_fe[fixest::obs(fe_fit), ]
base_fe$ehat <- as.numeric(residuals(fe_fit))
log_line(RUN_LOG, glue("Final analysis panel: {nrow(panel)} rows; FE fit sample: {nrow(base_fe)} untreated obs"))

# Pass-3 fix 2: all counts computed AFTER every row drop (missing_t only --
# the yhat fix above no longer drops rows).
n_states <- n_distinct(panel$state_abb)
n_switch <- sum((panel %>% distinct(state_abb, g))$g > 0)
n_never  <- n_states - n_switch
switcher_states <- sort((panel %>% distinct(state_abb, g) %>% filter(g > 0))$state_abb)
never_states    <- sort((panel %>% distinct(state_abb, g) %>% filter(g == 0))$state_abb)
log_line(RUN_LOG, glue("Panel: states={n_states} (switchers={n_switch}, never={n_never}); rows={nrow(panel)}"))

panel_summary <- tibble(scenario = SCENARIO, run_mode = RUN_MODE, rescale_donors = RESCALE_DONORS,
                         drop_already_treated = DROP_ALREADY_TREATED,
                         exclude_states = paste(EXCLUDE_STATES, collapse = ";"), exclude_reason = EXCLUDE_REASON,
                         n_states = n_states, n_switchers = n_switch, n_never_treated = n_never,
                         n_rows = nrow(panel), min_month = min(panel$month_date), max_month = max(panel$month_date),
                         n_months = n_distinct(panel$t),
                         switcher_states = paste(switcher_states, collapse = ";"),
                         never_states = paste(never_states, collapse = ";"),
                         n_yhat_zeroed = n_yhat_zeroed)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

all_t <- sort(unique(panel$t))
t_row_idx <- match(panel$t, all_t)

# ----------------------------- R2: eligible donor set (ex ante) -------------

donor_states <- never_states
if (length(donor_states) < 2) stop("Fewer than 2 never-treated donor states.", call. = FALSE)

donor_resid <- base_fe %>% filter(state_abb %in% donor_states)
E <- matrix(NA_real_, nrow = length(all_t), ncol = length(donor_states),
            dimnames = list(as.character(all_t), donor_states))
E[cbind(match(donor_resid$t, all_t), match(donor_resid$state_abb, donor_states))] <- donor_resid$ehat

# Pass-3 fix 3: DF_CORRECT -- inflate donor residuals by sqrt(N/(N-K)) to
# offset the downward bias of OLS residuals as variance estimates of the true
# error (N = FE-fit observations, K = absorbed two-way-FE parameter count,
# both from fe_fit itself so K reflects fixest's own connected-component
# count, not a naive n_id+n_t-1). Only bites the unscaled (RESCALE_DONORS=
# FALSE) arm: under S1 rescaling, Z divides E by its own column SD, so a
# constant multiplicative factor on E cancels exactly.
DF_N <- nrow(base_fe); DF_K <- fe_fit$nparams; DF_FACTOR <- sqrt(DF_N / (DF_N - DF_K))
if (DF_CORRECT) {
  E <- E * DF_FACTOR
  log_line(RUN_LOG, glue("DF_CORRECT: TRUE. N={DF_N} K={DF_K} factor=sqrt(N/(N-K))={round(DF_FACTOR,5)}. Donor residual matrix E scaled by this factor."))
} else {
  log_line(RUN_LOG, glue("DF_CORRECT: FALSE (would be N={DF_N} K={DF_K} factor={round(DF_FACTOR,5)} if enabled)."))
}

coverage_window <- vapply(seq_along(donor_states), function(d) mean(!is.na(E[, d])), numeric(1))
names(coverage_window) <- donor_states
eligible_states  <- donor_states[coverage_window >= MIN_ELIGIBLE_COVERAGE]
excluded_states  <- setdiff(donor_states, eligible_states)
log_line(RUN_LOG, glue("R2 donor coverage vs scenario window ({length(all_t)} months), threshold={MIN_ELIGIBLE_COVERAGE}:"))
for (d in donor_states) log_line(RUN_LOG, glue("  {d}: coverage={round(coverage_window[[d]],3)}  {ifelse(coverage_window[[d]]>=MIN_ELIGIBLE_COVERAGE,'ELIGIBLE','excluded')}"))
log_line(RUN_LOG, glue("Eligible donors ({length(eligible_states)}): {paste(eligible_states, collapse=', ')}"))
log_line(RUN_LOG, glue("Excluded donors ({length(excluded_states)}): {paste(excluded_states, collapse=', ')}"))

if (length(eligible_states) < 2) {
  stop(glue("R2: fewer than 2 eligible donors at MIN_ELIGIBLE_COVERAGE={MIN_ELIGIBLE_COVERAGE} for SCENARIO={SCENARIO}. ",
            "See run.log coverage table -- this threshold may need to be relaxed for this scenario (documented deviation, not silently patched)."), call. = FALSE)
}
eligible_idx_full <- match(eligible_states, donor_states)

# ----------------------------- S1: rescale prep -----------------------------

donor_own_sd <- apply(E, 2, sd, na.rm = TRUE)
Z <- sweep(E, 2, donor_own_sd, "/")  # donor paths standardized to unit SD by their OWN in-window SD

own_sd_tbl <- base_fe %>% group_by(state_abb) %>% summarise(sd_own = sd(ehat), n = dplyr::n(), .groups = "drop")
own_sd_map <- setNames(own_sd_tbl$sd_own, own_sd_tbl$state_abb)
own_n_map  <- setNames(own_sd_tbl$n, own_sd_tbl$state_abb)
qualifying <- own_sd_tbl %>% filter(n >= MIN_DONOR_OWN_OBS, is.finite(sd_own))
median_scale <- median(qualifying$sd_own)
target_scale <- vapply(target_states, function(s) {
  n_s <- unname(own_n_map[s]); sd_s <- unname(own_sd_map[s])
  if (!is.na(n_s) && n_s >= MIN_DONOR_OWN_OBS && is.finite(sd_s)) sd_s else median_scale
}, numeric(1))
names(target_scale) <- target_states
n_fallback <- sum(!(target_states %in% qualifying$state_abb))
log_line(RUN_LOG, glue("S1 rescale prep: {nrow(qualifying)}/{length(target_states)} states qualify with >={MIN_DONOR_OWN_OBS} own in-window untreated obs; median fallback scale={round(median_scale,4)} used for {n_fallback} states."))

# ----------------------------- simulation core ------------------------------

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

one_sim <- function(seed, delta, active_idx, rescale) {
  set.seed(seed)
  n <- length(target_states)
  primary <- safe_sample(active_idx, n)
  backup  <- safe_sample(active_idx, n)
  sign    <- sample(c(-1, 1), n, replace = TRUE)

  col_p <- primary[panel$id]; col_b <- backup[panel$id]; sign_row <- sign[panel$id]
  if (rescale) {
    scale_row <- target_scale[panel$id]
    val_p <- Z[cbind(t_row_idx, col_p)] * scale_row
    val_b <- Z[cbind(t_row_idx, col_b)] * scale_row
  } else {
    val_p <- E[cbind(t_row_idx, col_p)]
    val_b <- E[cbind(t_row_idx, col_b)]
  }
  e_val <- ifelse(is.na(val_p), val_b, val_p)
  keep <- is.finite(e_val)
  filled_share <- mean(is.na(val_p)[keep])   # share of KEPT rows that needed the backup
  drop_share   <- 1 - mean(keep)             # rows where primary AND backup both missing

  dat <- data.frame(id = panel$id[keep], t = panel$t[keep], post = panel$post[keep],
                     y = panel$yhat[keep] + sign_row[keep] * e_val[keep] + delta * panel$post[keep])

  est <- tryCatch(fixest::feols(y ~ post | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE), error = function(e) NULL)
  if (is.null(est)) return(list(ok = FALSE, drop_share = drop_share, filled_share = filled_share))
  ct <- fixest::coeftable(est)
  if (!("post" %in% rownames(ct))) return(list(ok = FALSE, drop_share = drop_share, filled_share = filled_share))
  att <- unname(ct["post", "Estimate"]); se <- unname(ct["post", "Std. Error"])
  G <- length(unique(dat$id[fixest::obs(est)]))
  if (!is.finite(att) || !is.finite(se) || se <= 0) return(list(ok = FALSE, drop_share = drop_share, filled_share = filled_share))
  list(ok = TRUE, att = att, se = se, G = G, drop_share = drop_share, filled_share = filled_share, seed = seed, est = est, dat = dat)
}

# Top-level (global-env) worker wrapper: parLapply's extra `...` args are
# passed by value on every call, avoiding any ambiguity about which lexical
# frame a nested closure's free variables (active_idx, rescale) would need to
# be serialized from -- the actual root cause of an earlier "object not found"
# failure under N_WORKERS>1 when one_sim was wrapped in a closure defined
# inside run_delta0_batch's own call frame.
worker_one_sim <- function(s, active_idx, rescale) one_sim(s, 0, active_idx, rescale)

run_delta0_batch <- function(seeds, active_idx, rescale, workers) {
  if (workers > 1L) {
    cl <- parallel::makeCluster(workers, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster.log"))
    on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
    parallel::clusterEvalQ(cl, { suppressPackageStartupMessages(library(fixest)); NULL })
    parallel::clusterExport(cl, varlist = c("one_sim","safe_sample","panel","E","Z","target_scale",
                                             "t_row_idx","target_states","donor_states"), envir = environment())
    parallel::parLapply(cl, seeds, worker_one_sim, active_idx = active_idx, rescale = rescale)
  } else {
    lapply(seeds, function(s) one_sim(s, 0, active_idx, rescale))
  }
}

# ----------------------------- exact-size (R1) helpers ----------------------

exact_crit_analytic <- function(att0, se0) unname(quantile(abs(att0) / se0, 0.95, na.rm = TRUE))

# wild-arm exact-size: scale each sim's CI half-width by a common factor k so
# the empirical delta=0 rejection rate is exactly ALPHA (bisection on k)
calibrate_wild_k <- function(att0, lo, hi, target_alpha = ALPHA) {
  center <- (lo + hi) / 2; half <- (hi - lo) / 2
  reject_rate <- function(k) mean(!(-k * half <= (0 - center) & (0 - center) <= k * half))
  lo_k <- 0.1; hi_k <- 20
  # bisection: reject_rate is decreasing in k
  for (i in 1:60) {
    mid <- (lo_k + hi_k) / 2
    if (reject_rate(mid) > target_alpha) lo_k <- mid else hi_k <- mid
  }
  (lo_k + hi_k) / 2
}

################################################################################
# MAIN RUN (delta=0 sims, analytic + optional wild), + power/MDE + checks
################################################################################

run_main <- function(active_idx, rescale, tag_suffix = "") {
  t0 <- Sys.time()
  results0 <- run_delta0_batch(sim_seeds, active_idx, rescale, N_WORKERS)
  t1 <- Sys.time()
  log_line(RUN_LOG, glue("Main delta=0 loop{tag_suffix} ({N_SIMS} sims): {round(as.numeric(difftime(t1,t0,units='secs')),1)}s"))

  ok0  <- vapply(results0, function(x) isTRUE(x$ok), logical(1))
  att0 <- vapply(results0, function(x) if (isTRUE(x$ok)) x$att else NA_real_, numeric(1))
  se0  <- vapply(results0, function(x) if (isTRUE(x$ok)) x$se  else NA_real_, numeric(1))
  G0   <- vapply(results0, function(x) if (isTRUE(x$ok)) x$G   else NA_integer_, integer(1))
  drop_share0   <- vapply(results0, function(x) if (!is.null(x$drop_share)) x$drop_share else NA_real_, numeric(1))
  filled_share0 <- vapply(results0, function(x) if (!is.null(x$filled_share)) x$filled_share else NA_real_, numeric(1))
  log_line(RUN_LOG, glue("OK sims: {sum(ok0)}/{N_SIMS}. Mean share needing backup fill: {round(mean(filled_share0, na.rm=TRUE),4)}. Mean share dropped (primary+backup both missing): {round(mean(drop_share0, na.rm=TRUE),4)}"))

  sims_delta0 <- tibble(seed = sim_seeds, ok = ok0, att0 = att0, se0 = se0, G = G0,
                         drop_share = drop_share0, filled_share = filled_share0)

  wild_ci <- tibble(seed = integer(), ci_lo = double(), ci_hi = double())
  if (RUN_WILD) {
    wild_seeds <- sim_seeds[seq_len(min(N_WILD_SIMS, N_SIMS))]
    wild_results0 <- results0[seq_len(min(N_WILD_SIMS, N_SIMS))]
    do_wild <- function(res) {
      if (!isTRUE(res$ok)) return(c(NA_real_, NA_real_))
      # Pass-3 fix 1: fwildclusterboot draws its Rademacher weights through
      # dqrng, which base R's set.seed() does not touch -- seed BOTH streams,
      # per sim, from that sim's own (worker-count-independent) seed.
      set.seed(res$seed); dqrng::dqset.seed(res$seed)
      b <- tryCatch(fwildclusterboot::boottest(res$est, param = "post", B = WILD_B, type = "rademacher", clustid = "id"), error = function(e) NULL)
      if (is.null(b)) return(c(NA_real_, NA_real_))
      ci <- as.numeric(unlist(confint(b))); if (length(ci) < 2) return(c(NA_real_, NA_real_))
      ci[c(1, 2)]
    }
    t0w <- Sys.time()
    if (N_WORKERS > 1L) {
      cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster_wild.log"))
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterEvalQ(cl, { suppressPackageStartupMessages({ library(fwildclusterboot); library(dqrng) }); NULL })
      parallel::clusterExport(cl, varlist = c("wild_results0","do_wild","WILD_B"), envir = environment())
      wild_out <- parallel::parLapply(cl, wild_results0, do_wild)
      try(parallel::stopCluster(cl), silent = TRUE)
    } else {
      wild_out <- lapply(wild_results0, do_wild)
    }
    t1w <- Sys.time()
    log_line(RUN_LOG, glue("Wild bootstrap arm{tag_suffix} ({length(wild_seeds)} sims x B={WILD_B}): {round(as.numeric(difftime(t1w,t0w,units='secs')),1)}s"))
    wild_mat <- do.call(rbind, wild_out)
    wild_ci <- tibble(seed = wild_seeds, ci_lo = wild_mat[, 1], ci_hi = wild_mat[, 2])
  } else {
    log_line(RUN_LOG, glue("Wild bootstrap arm{tag_suffix} SKIPPED (RUN_WILD={RUN_WILD})"))
  }
  sims_delta0 <- sims_delta0 %>% left_join(wild_ci, by = "seed")
  # Pass-3 fix 4: wild_failed -- ok0==TRUE (analytic fit succeeded) but the
  # wild bootstrap CI came back NA (boottest() errored or returned <2 bounds).
  # NA outside the attempted wild_seeds window (never attempted) is left NA,
  # not counted as a failure.
  sims_delta0$wild_failed <- NA
  if (RUN_WILD) {
    attempted <- sims_delta0$seed %in% wild_ci$seed
    sims_delta0$wild_failed <- ifelse(attempted, sims_delta0$ok & !(is.finite(sims_delta0$ci_lo) & is.finite(sims_delta0$ci_hi)), NA)
  }

  att0_ok <- att0[ok0]; se0_ok <- se0[ok0]; G0_ok <- G0[ok0]
  tcrit_nom_ok <- qt(1 - ALPHA / 2, df = pmax(G0_ok - 1, 1))
  crit_exact <- exact_crit_analytic(att0_ok, se0_ok)
  mean_att0 <- mean(att0_ok); sd_att0 <- sd(att0_ok); mean_se0 <- mean(se0_ok)
  mc_se_att0 <- sd_att0 / sqrt(length(att0_ok))

  wild_lo <- rep(NA_real_, N_SIMS); wild_hi <- rep(NA_real_, N_SIMS)
  idx_match <- match(wild_ci$seed, sim_seeds); wild_lo[idx_match] <- wild_ci$ci_lo; wild_hi[idx_match] <- wild_ci$ci_hi
  wild_ok <- ok0 & is.finite(wild_lo) & is.finite(wild_hi)
  wild_k_exact <- NA_real_
  if (any(wild_ok)) wild_k_exact <- calibrate_wild_k(att0[wild_ok], wild_lo[wild_ok], wild_hi[wild_ok])

  # Pass-3 fix 4: failed wild draws -- diagnostics + two MDE treatments.
  wild_failed_diag <- tibble(arm = character(), n = integer(), mean_abs_tstat = double(), p90_abs_tstat = double())
  wild_lo_filled <- wild_lo; wild_hi_filled <- wild_hi
  if (RUN_WILD) {
    attempted_idx <- which(sims_delta0$seed %in% wild_ci$seed & ok0)
    failed_idx  <- attempted_idx[sims_delta0$wild_failed[attempted_idx] %in% TRUE]
    success_idx <- setdiff(attempted_idx, failed_idx)
    abs_t <- abs(att0 / se0)
    wild_failed_diag <- tibble(
      arm = c("wild_failed", "wild_success"),
      n = c(length(failed_idx), length(success_idx)),
      mean_abs_tstat = c(mean(abs_t[failed_idx]), mean(abs_t[success_idx])),
      p90_abs_tstat = c(unname(quantile(abs_t[failed_idx], 0.90, na.rm = TRUE)), unname(quantile(abs_t[success_idx], 0.90, na.rm = TRUE)))
    )
    log_line(RUN_LOG, glue("Wild failed draws{tag_suffix}: {length(failed_idx)}/{length(attempted_idx)} attempted. |att0/se0| mean(failed)={round(wild_failed_diag$mean_abs_tstat[1],3)} p90(failed)={round(wild_failed_diag$p90_abs_tstat[1],3)} vs mean(success)={round(wild_failed_diag$mean_abs_tstat[2],3)} p90(success)={round(wild_failed_diag$p90_abs_tstat[2],3)}"))
    # "replaced": fill the failed draws' CI with that sim's own analytic CI
    # (att0 +/- t_{G-1,0.975}*se0) instead of dropping them from the wild arm.
    if (length(failed_idx) > 0) {
      tcrit_i <- qt(1 - ALPHA/2, df = pmax(G0[failed_idx] - 1, 1))
      wild_lo_filled[failed_idx] <- att0[failed_idx] - tcrit_i * se0[failed_idx]
      wild_hi_filled[failed_idx] <- att0[failed_idx] + tcrit_i * se0[failed_idx]
    }
  }
  wild_ok_filled <- ok0 & is.finite(wild_lo_filled) & is.finite(wild_hi_filled)
  pw_wild_nominal_dropped <- vapply(grid, function(d) if (!any(wild_ok)) NA_real_ else
    mean(!( (wild_lo[wild_ok]) <= -d & -d <= (wild_hi[wild_ok]) )), numeric(1))
  pw_wild_nominal_replaced <- vapply(grid, function(d) if (!any(wild_ok_filled)) NA_real_ else
    mean(!( (wild_lo_filled[wild_ok_filled]) <= -d & -d <= (wild_hi_filled[wild_ok_filled]) )), numeric(1))
  mde_wild_nominal_dropped  <- mde_from_curve(grid, pw_wild_nominal_dropped)
  mde_wild_nominal_replaced <- mde_from_curve(grid, pw_wild_nominal_replaced)
  log_line(RUN_LOG, glue("Wild MDE (nominal), failed draws DROPPED: {round(mde_wild_nominal_dropped,4)} ({round(100*pct_from_log(mde_wild_nominal_dropped),2)}%); failed draws REPLACED by analytic CI: {round(mde_wild_nominal_replaced,4)} ({round(100*pct_from_log(mde_wild_nominal_replaced),2)}%)"))

  power_analytic <- function(delta, crit, recentre) {
    a <- att0_ok - (if (recentre) mean_att0 else 0)
    if (length(crit) == 1) mean(abs(a + delta) / se0_ok > crit) else mean(abs(a + delta) / se0_ok > crit)
  }
  power_wild <- function(delta, k, recentre) {
    if (!any(wild_ok)) return(NA_real_)
    center <- (wild_lo[wild_ok] + wild_hi[wild_ok]) / 2 - (if (recentre) mean_att0 else 0)
    half <- (wild_hi[wild_ok] - wild_lo[wild_ok]) / 2 * k
    lo <- center - half; hi <- center + half
    mean(!(lo <= -delta & -delta <= hi))
  }

  power_curve <- tibble(
    delta_log = grid,
    power_analytic_nominal_raw       = vapply(grid, power_analytic, numeric(1), crit = tcrit_nom_ok, recentre = FALSE),
    power_analytic_nominal_recentred = vapply(grid, power_analytic, numeric(1), crit = tcrit_nom_ok, recentre = TRUE),
    power_analytic_exact_raw         = vapply(grid, power_analytic, numeric(1), crit = crit_exact,   recentre = FALSE),
    power_analytic_exact_recentred   = vapply(grid, power_analytic, numeric(1), crit = crit_exact,   recentre = TRUE),
    power_wild_nominal_raw       = vapply(grid, power_wild, numeric(1), k = 1,            recentre = FALSE),
    power_wild_nominal_recentred = vapply(grid, power_wild, numeric(1), k = 1,            recentre = TRUE),
    power_wild_exact_raw         = vapply(grid, power_wild, numeric(1), k = wild_k_exact, recentre = FALSE),
    power_wild_exact_recentred   = vapply(grid, power_wild, numeric(1), k = wild_k_exact, recentre = TRUE)
  )
  safe_write_csv(power_curve, file.path(OUT_DIR, glue("power_curve{tag_suffix}.csv")))

  size_analytic_nominal <- mean(abs(att0_ok) / se0_ok > tcrit_nom_ok)
  size_analytic_exact   <- mean(abs(att0_ok) / se0_ok > crit_exact)
  size_wild_nominal <- if (any(wild_ok)) mean(!(wild_lo[wild_ok] <= 0 & 0 <= wild_hi[wild_ok])) else NA_real_
  size_wild_exact   <- if (any(wild_ok)) power_wild(0, wild_k_exact, FALSE) else NA_real_

  boot_mde_analytic <- function(crit_fun_is_exact) {
    n <- length(att0_ok)
    vapply(seq_len(MC_BOOT_B), function(b) {
      idx <- sample.int(n, n, replace = TRUE)
      a <- att0_ok[idx]; s <- se0_ok[idx]
      crit <- if (crit_fun_is_exact) exact_crit_analytic(a, s) else qt(1 - ALPHA/2, df = pmax(G0_ok[idx] - 1, 1))
      pw <- if (crit_fun_is_exact) vapply(grid, function(d) mean(abs(a + d) / s > crit), numeric(1))
            else vapply(grid, function(d) mean(abs(a + d) / s > crit), numeric(1))
      mde_from_curve(grid, pw)
    }, numeric(1))
  }
  set.seed(SEED + 999)
  boot_nom <- boot_mde_analytic(FALSE)
  set.seed(SEED + 998)
  boot_exact <- boot_mde_analytic(TRUE)
  ci_nom <- quantile(boot_nom, c(0.025, 0.975), na.rm = TRUE)
  ci_exact <- quantile(boot_exact, c(0.025, 0.975), na.rm = TRUE)

  mde_tbl <- tibble(
    arm = c("analytic_nominal_raw","analytic_nominal_recentred","analytic_exact_raw","analytic_exact_recentred",
            "wild_nominal_raw","wild_nominal_recentred","wild_exact_raw","wild_exact_recentred",
            "wild_nominal_raw_failed_dropped","wild_nominal_raw_failed_replaced"),
    mde_log = c(mde_from_curve(grid, power_curve$power_analytic_nominal_raw),
                mde_from_curve(grid, power_curve$power_analytic_nominal_recentred),
                mde_from_curve(grid, power_curve$power_analytic_exact_raw),
                mde_from_curve(grid, power_curve$power_analytic_exact_recentred),
                mde_from_curve(grid, power_curve$power_wild_nominal_raw),
                mde_from_curve(grid, power_curve$power_wild_nominal_recentred),
                mde_from_curve(grid, power_curve$power_wild_exact_raw),
                mde_from_curve(grid, power_curve$power_wild_exact_recentred),
                mde_wild_nominal_dropped, mde_wild_nominal_replaced)
  ) %>% mutate(mde_pct = pct_from_log(mde_log))
  mde_tbl$ci_lo_log <- c(ci_nom[1], NA, ci_exact[1], NA, NA, NA, NA, NA, NA, NA)
  mde_tbl$ci_hi_log <- c(ci_nom[2], NA, ci_exact[2], NA, NA, NA, NA, NA, NA, NA)
  mde_tbl$size_at_delta0 <- c(size_analytic_nominal, size_analytic_nominal, size_analytic_exact, size_analytic_exact,
                               size_wild_nominal, size_wild_nominal, size_wild_exact, size_wild_exact, NA, NA)
  mde_tbl$crit_value <- c(mean(tcrit_nom_ok), mean(tcrit_nom_ok), crit_exact, crit_exact, 1, 1, wild_k_exact, wild_k_exact, 1, 1)
  mde_tbl$mean_att0 <- mean_att0; mde_tbl$sd_att0 <- sd_att0; mde_tbl$mean_se0 <- mean_se0; mde_tbl$mc_se_att0 <- mc_se_att0
  safe_write_csv(mde_tbl, file.path(OUT_DIR, glue("mde{tag_suffix}.csv")))
  if (RUN_WILD) safe_write_csv(wild_failed_diag, file.path(OUT_DIR, glue("wild_failed_diag{tag_suffix}.csv")))

  log_line(RUN_LOG, glue("R1: analytic nominal crit(mean)={round(mean(tcrit_nom_ok),4)} size={round(size_analytic_nominal,4)} MDE={round(mde_tbl$mde_log[1],4)} ({round(100*mde_tbl$mde_pct[1],2)}%)"))
  log_line(RUN_LOG, glue("R1: analytic EXACT crit={round(crit_exact,4)} size={round(size_analytic_exact,4)} MDE={round(mde_tbl$mde_log[3],4)} ({round(100*mde_tbl$mde_pct[3],2)}%)"))
  if (any(wild_ok)) {
    log_line(RUN_LOG, glue("R1: wild nominal size={round(size_wild_nominal,4)} MDE={round(mde_tbl$mde_log[5],4)}"))
    log_line(RUN_LOG, glue("R1: wild EXACT k={round(wild_k_exact,4)} size={round(size_wild_exact,4)} MDE={round(mde_tbl$mde_log[7],4)}"))
  }

  safe_write_csv(sims_delta0, file.path(OUT_DIR, glue("sims_delta0{tag_suffix}.csv")))

  list(results0 = results0, sims_delta0 = sims_delta0, mde_tbl = mde_tbl,
       att0_ok = att0_ok, se0_ok = se0_ok, G0_ok = G0_ok, sd_att0 = sd_att0,
       tcrit_nom_ok = tcrit_nom_ok, crit_exact = crit_exact, wild_ok = wild_ok,
       wild_lo = wild_lo, wild_hi = wild_hi, wild_k_exact = wild_k_exact)
}

main_out <- run_main(eligible_idx_full, RESCALE_DONORS)

################################################################################
# CHECKS (C1-C6), only for RUN_MODE == "main"
################################################################################

if (RUN_MODE == "main") {
  checks <- list()
  results0 <- main_out$results0

  ## C1 shift-equivariance (+ wild-arm translation extension at 1e-4)
  c1_seeds <- sim_seeds[seq_len(5)]; c1_delta <- 0.10
  c1_res0 <- results0[seq_len(5)]
  c1_res_shift <- lapply(c1_seeds, function(s) one_sim(s, c1_delta, eligible_idx_full, RESCALE_DONORS))
  c1_att_diffs <- mapply(function(r0, rs) if (isTRUE(r0$ok) && isTRUE(rs$ok)) (rs$att - r0$att) - c1_delta else NA_real_, c1_res0, c1_res_shift)
  c1_se_diffs  <- mapply(function(r0, rs) if (isTRUE(r0$ok) && isTRUE(rs$ok)) rs$se - r0$se else NA_real_, c1_res0, c1_res_shift)
  c1_max_att <- max(abs(c1_att_diffs), na.rm = TRUE); c1_max_se <- max(abs(c1_se_diffs), na.rm = TRUE)
  c1_ok <- is.finite(c1_max_att) && c1_max_att < 1e-8 && is.finite(c1_max_se) && c1_max_se < 1e-8

  c1_wild_note <- "N/A (RUN_WILD=FALSE)"
  c1_wild_ok <- NA
  if (RUN_WILD) {
    wild_diffs <- vector("list", 5)
    for (i in seq_len(5)) {
      r0 <- c1_res0[[i]]; rs <- c1_res_shift[[i]]
      if (!isTRUE(r0$ok) || !isTRUE(rs$ok)) { wild_diffs[[i]] <- c(NA, NA); next }
      # Same Rademacher weight draw for both fits (set.seed right before each
      # call) -- otherwise the CI-shift check compares two independently
      # resampled bootstrap distributions and the 1e-4 tolerance is pure MC
      # noise, not a genuine equivariance failure.
      set.seed(c1_seeds[i] + 777L); dqrng::dqset.seed(c1_seeds[i] + 777L)
      b0 <- tryCatch(fwildclusterboot::boottest(r0$est, param = "post", B = WILD_B, type = "rademacher", clustid = "id"), error = function(e) NULL)
      set.seed(c1_seeds[i] + 777L); dqrng::dqset.seed(c1_seeds[i] + 777L)
      bs <- tryCatch(fwildclusterboot::boottest(rs$est, param = "post", B = WILD_B, type = "rademacher", clustid = "id"), error = function(e) NULL)
      if (is.null(b0) || is.null(bs)) { wild_diffs[[i]] <- c(NA, NA); next }
      ci0 <- as.numeric(unlist(confint(b0))); cis <- as.numeric(unlist(confint(bs)))
      wild_diffs[[i]] <- c((cis[1] - ci0[1]) - c1_delta, (cis[2] - ci0[2]) - c1_delta)
    }
    wd <- do.call(rbind, wild_diffs)
    c1_wild_max <- max(abs(wd), na.rm = TRUE)
    c1_wild_ok <- is.finite(c1_wild_max) && c1_wild_max < 1e-4
    c1_wild_note <- glue("max|CI shift diff|={signif(c1_wild_max,3)} vs tol 1e-4")
  }
  checks$C1 <- tibble(check = "C1_shift_equivariance", pass = c1_ok && (is.na(c1_wild_ok) || isTRUE(c1_wild_ok)),
                       value = c1_max_att, threshold = 1e-8,
                       note = glue("analytic: max|att diff|={signif(c1_max_att,3)} max|se diff|={signif(c1_max_se,3)}. wild (R1 extension, tol 1e-4): {c1_wild_note}"))

  ## C2 N/A for v2 (unchanged legacy reconciliation lives in pass 1; not re-run here)
  checks$C2 <- tibble(check = "C2_iid_month_reconciliation", pass = NA, value = NA_real_, threshold = 0.0099,
                       note = "N/A in v2 -- unchanged from pass 1 (see output/twfe_power_donorpath_v20260921/full/checks.csv)")

  ## C3 null centre
  c3_thresh <- 3 * (main_out$sd_att0 / sqrt(length(main_out$att0_ok)))
  c3_ok <- abs(mean(main_out$att0_ok)) < c3_thresh
  checks$C3 <- tibble(check = "C3_null_centre", pass = c3_ok, value = mean(main_out$att0_ok), threshold = c3_thresh,
                       note = glue("|mean att0|={signif(abs(mean(main_out$att0_ok)),4)} vs 3*MC_SE={signif(c3_thresh,4)}"))

  ## C4 persistence carried (R2 fix: uniform draw over the ONE eligible set, backup-filled)
  sd_t_donor <- apply(E, 1, sd, na.rm = TRUE)
  Zx <- sweep(E, 1, sd_t_donor, "/")
  target_pairs <- lapply(eligible_idx_full, function(d) {
    zc <- Zx[, d]; ok_idx <- which(!is.na(zc))
    if (length(ok_idx) < 2) return(NULL)
    tvals <- all_t[ok_idx]; keep <- c(FALSE, diff(tvals) == 1)
    if (!any(keep)) return(NULL)
    idx_cur <- ok_idx[keep]; idx_lag <- ok_idx[which(keep) - 1]
    # NB tibble() shadowing trap (fixed in pass 1): compute both subsets from
    # the outer zc vector BEFORE naming any tibble column the same thing.
    z_cur <- zc[idx_cur]; z_lag_val <- zc[idx_lag]
    tibble(z = z_cur, z_lag = z_lag_val)
  })
  target_pairs <- dplyr::bind_rows(target_pairs)
  rho_target <- suppressWarnings(cor(target_pairs$z, target_pairs$z_lag, use = "complete.obs"))

  n_c4_sims <- min(200L, N_SIMS)
  c4_seeds <- sim_seeds[seq_len(n_c4_sims)]
  sim_pairs <- lapply(c4_seeds, function(s) {
    set.seed(s)
    n <- length(target_states)
    primary <- safe_sample(eligible_idx_full, n); backup <- safe_sample(eligible_idx_full, n)
    col_p <- primary[panel$id]; col_b <- backup[panel$id]
    val_p <- E[cbind(t_row_idx, col_p)]; val_b <- E[cbind(t_row_idx, col_b)]
    e_val <- ifelse(is.na(val_p), val_b, val_p)
    z_val <- e_val / sd_t_donor[t_row_idx]
    df <- tibble(id = panel$id, t = panel$t, z = z_val) %>% filter(is.finite(z)) %>% arrange(id, t)
    df <- df %>% group_by(id) %>% mutate(z_lag = dplyr::lag(z), t_lag = dplyr::lag(t)) %>% ungroup() %>% filter(t - t_lag == 1)
    df %>% select(z, z_lag)
  })
  sim_pairs <- dplyr::bind_rows(sim_pairs)
  rho_sim <- suppressWarnings(cor(sim_pairs$z, sim_pairs$z_lag, use = "complete.obs"))
  c4_diff <- abs(rho_sim - rho_target)
  c4_ok <- is.finite(c4_diff) && c4_diff < 0.05
  checks$C4 <- tibble(check = "C4_persistence_carried", pass = c4_ok, value = c4_diff, threshold = 0.05,
                       note = glue("donor rho={round(rho_target,4)} (eligible-set only, unweighted)  simulated rho={round(rho_sim,4)} (uniform draw + backup fill)  |diff|={round(c4_diff,4)} (n_sims_used={n_c4_sims})"))

  ## C5 counts
  checks$C5 <- tibble(check = "C5_counts", pass = TRUE, value = n_states, threshold = NA_real_,
                       note = glue("states={n_states} switchers={n_switch} never={n_never} eligible_donors={length(eligible_states)} rows={nrow(panel)}"))

  ## C6 (Pass 3 fix 2): att0/se0 must be invariant to yhat, since yhat lies in
  ## the span of the estimating regression's own id+t FE and is fully
  ## re-absorbed -- this is what licenses yhat<-0 for states with no in-window
  ## untreated obs instead of dropping them. Compare 5 seeds: panel$yhat as
  ## computed (FE prediction, zeroed only where non-finite) vs yhat forced to
  ## 0 for EVERY row.
  c6_seeds <- sim_seeds[seq_len(5)]
  c6_res_normal <- results0[seq_len(5)]
  one_sim_yhat0 <- function(seed, active_idx, rescale) {
    set.seed(seed)
    n <- length(target_states)
    primary <- safe_sample(active_idx, n); backup <- safe_sample(active_idx, n)
    sign <- sample(c(-1, 1), n, replace = TRUE)
    col_p <- primary[panel$id]; col_b <- backup[panel$id]; sign_row <- sign[panel$id]
    if (rescale) {
      scale_row <- target_scale[panel$id]
      val_p <- Z[cbind(t_row_idx, col_p)] * scale_row; val_b <- Z[cbind(t_row_idx, col_b)] * scale_row
    } else {
      val_p <- E[cbind(t_row_idx, col_p)]; val_b <- E[cbind(t_row_idx, col_b)]
    }
    e_val <- ifelse(is.na(val_p), val_b, val_p)
    keep <- is.finite(e_val)
    dat <- data.frame(id = panel$id[keep], t = panel$t[keep], post = panel$post[keep],
                       y = sign_row[keep] * e_val[keep])   # yhat forced to 0 everywhere, delta = 0
    est <- tryCatch(fixest::feols(y ~ post | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE), error = function(e) NULL)
    if (is.null(est)) return(list(ok = FALSE))
    ct <- fixest::coeftable(est)
    if (!("post" %in% rownames(ct))) return(list(ok = FALSE))
    list(ok = TRUE, att = unname(ct["post", "Estimate"]), se = unname(ct["post", "Std. Error"]))
  }
  c6_res_zero <- lapply(c6_seeds, function(s) one_sim_yhat0(s, eligible_idx_full, RESCALE_DONORS))
  c6_att_diffs <- mapply(function(rn, rz) if (isTRUE(rn$ok) && isTRUE(rz$ok)) rn$att - rz$att else NA_real_, c6_res_normal, c6_res_zero)
  c6_se_diffs  <- mapply(function(rn, rz) if (isTRUE(rn$ok) && isTRUE(rz$ok)) rn$se  - rz$se  else NA_real_, c6_res_normal, c6_res_zero)
  c6_max_att <- max(abs(c6_att_diffs), na.rm = TRUE); c6_max_se <- max(abs(c6_se_diffs), na.rm = TRUE)
  c6_ok <- is.finite(c6_max_att) && c6_max_att < 1e-8 && is.finite(c6_max_se) && c6_max_se < 1e-8
  checks$C6 <- tibble(check = "C6_yhat_invariance", pass = c6_ok, value = c6_max_att, threshold = 1e-8,
                       note = glue("max|att diff|={signif(c6_max_att,3)} max|se diff|={signif(c6_max_se,3)} (yhat=FE-prediction vs yhat=0, 5 seeds)"))

  checks_tbl <- dplyr::bind_rows(checks)
  safe_write_csv(checks_tbl, file.path(OUT_DIR, "checks.csv"))
  for (i in seq_len(nrow(checks_tbl))) log_line(RUN_LOG, glue("{checks_tbl$check[i]}: pass={checks_tbl$pass[i]} -- {checks_tbl$note[i]}"))

  safe_write_csv(tibble(state_abb = eligible_states, coverage = coverage_window[eligible_states], status = "eligible") %>%
                   bind_rows(tibble(state_abb = excluded_states, coverage = coverage_window[excluded_states], status = "excluded")) %>%
                   arrange(desc(status), desc(coverage)),
                 file.path(OUT_DIR, "eligible_donors.csv"))
}

################################################################################
# R3: leave-one-eligible-donor-out (analytic only)
################################################################################

if (RUN_MODE == "loo") {
  loo_rows <- list()
  for (dstate in eligible_states) {
    active_idx <- setdiff(eligible_idx_full, match(dstate, donor_states))
    if (length(active_idx) < 2) { log_line(RUN_LOG, glue("LOO skip {dstate}: fewer than 2 donors remain")); next }
    loo_seeds <- sim_seeds[seq_len(LOO_N_SIMS)]
    t0 <- Sys.time()
    res <- if (N_WORKERS > 1L) {
      cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster_loo.log"))
      parallel::clusterEvalQ(cl, { suppressPackageStartupMessages(library(fixest)); NULL })
      parallel::clusterExport(cl, varlist = c("one_sim","safe_sample","panel","E","Z","target_scale",
                                               "t_row_idx","target_states","donor_states"), envir = environment())
      out <- parallel::parLapply(cl, loo_seeds, worker_one_sim, active_idx = active_idx, rescale = RESCALE_DONORS)
      parallel::stopCluster(cl); out
    } else {
      lapply(loo_seeds, function(s) one_sim(s, 0, active_idx, RESCALE_DONORS))
    }
    t1 <- Sys.time()
    ok <- vapply(res, function(x) isTRUE(x$ok), logical(1))
    att <- vapply(res, function(x) if (isTRUE(x$ok)) x$att else NA_real_, numeric(1))
    se  <- vapply(res, function(x) if (isTRUE(x$ok)) x$se  else NA_real_, numeric(1))
    G   <- vapply(res, function(x) if (isTRUE(x$ok)) x$G   else NA_integer_, integer(1))
    att_ok <- att[ok]; se_ok <- se[ok]; G_ok <- G[ok]
    tcrit_nom <- qt(1 - ALPHA/2, df = pmax(G_ok - 1, 1))
    crit_exact <- exact_crit_analytic(att_ok, se_ok)
    pw_nom   <- vapply(grid, function(d) mean(abs(att_ok + d) / se_ok > tcrit_nom), numeric(1))
    pw_exact <- vapply(grid, function(d) mean(abs(att_ok + d) / se_ok > crit_exact), numeric(1))
    mde_nom <- mde_from_curve(grid, pw_nom); mde_exact <- mde_from_curve(grid, pw_exact)
    loo_rows[[dstate]] <- tibble(donor_dropped = dstate, n_sims = LOO_N_SIMS, n_ok = sum(ok),
                                  sd_att0 = sd(att_ok), mean_att0 = mean(att_ok), mean_se0 = mean(se_ok),
                                  crit_exact = crit_exact,
                                  mde_nominal_log = mde_nom, mde_nominal_pct = pct_from_log(mde_nom),
                                  mde_exact_log = mde_exact, mde_exact_pct = pct_from_log(mde_exact))
    log_line(RUN_LOG, glue("LOO drop {dstate} ({round(as.numeric(difftime(t1,t0,units='secs')),1)}s): SD(att0)={round(sd(att_ok),4)}  MDE_nom={round(mde_nom,4)}  MDE_exact={round(mde_exact,4)}"))
  }
  loo_tbl <- dplyr::bind_rows(loo_rows)
  safe_write_csv(loo_tbl, file.path(OUT_DIR, "mde_leave_one_donor_out.csv"))

  jack_se <- function(x) { n <- length(x); sqrt((n-1)/n * sum((x - mean(x, na.rm = TRUE))^2, na.rm = TRUE)) }
  log_line(RUN_LOG, glue("LOO summary: MDE_nominal min={round(min(loo_tbl$mde_nominal_log),4)} max={round(max(loo_tbl$mde_nominal_log),4)} jackknife_SE={round(jack_se(loo_tbl$mde_nominal_log),5)}"))
  log_line(RUN_LOG, glue("LOO summary: MDE_exact   min={round(min(loo_tbl$mde_exact_log),4)} max={round(max(loo_tbl$mde_exact_log),4)} jackknife_SE={round(jack_se(loo_tbl$mde_exact_log),5)}"))
  log_line(RUN_LOG, glue("LOO donor moving nominal MDE most (max): {loo_tbl$donor_dropped[which.max(loo_tbl$mde_nominal_log)]}; least (min): {loo_tbl$donor_dropped[which.min(loo_tbl$mde_nominal_log)]}"))
}

log_line(RUN_LOG, "=== DONE ===")
cat(glue("DONE: {SCENARIO} / {RUN_MODE} / rescale={RESCALE_DONORS} / drop_already_treated={DROP_ALREADY_TREATED}. Out dir: {OUT_DIR}\n"))
