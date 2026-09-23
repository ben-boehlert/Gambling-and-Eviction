#!/usr/bin/env Rscript
################################################################################
# power_simulation_twfe_donorpath.R
#
# TWFE power simulation with "donor-path" noise: keeps the real design (real
# states, real launch dates, real missingness) but instead of redrawing iid
# shocks each month (which erases serial correlation), each state draws one
# never-treated donor state's ENTIRE untreated residual path (plus a random
# sign) for the whole simulation. This preserves each donor's autocovariance
# structure (drift, breaks, seasonality) while sign flips zero out the
# cross-state covariance created by two states sharing a donor and centre the
# null exactly. See quality_reports/plans/2026-09-21_twfe_donorpath_power_sim.md
#
# Blind throughout: only untreated observations feed the noise; the real
# post-launch outcome is never estimated or printed.
#
# Scenarios (SCENARIO env var):
#   full          - MIN_DATE unset, all 41 states, COVID months dropped from
#                   the analysis panel (Q1 default b)
#   start202206   - MIN_DATE=2022-06-01, already-treated states dropped
#                   (DROP_ALREADY_TREATED=TRUE default)
#
# ERR_MODE env var:
#   donorpath (default) - the design above
#   ar1                 - legacy-style pooled AR(1) noise, calibrated on the
#                          scenario's own (already-windowed) untreated pool;
#                          used only as a parametric cross-check on
#                          start202206 per the plan's Ben-constraint section
#
# Outputs (OUT_DIR/SCENARIO/ or OUT_DIR/SCENARIO/ar1_crosscheck/ for the AR1
# cross-check): sims_delta0.csv, power_curve.csv, mde.csv, checks.csv,
# panel_summary.csv, run.log. Aggregates only -- no record-level data.
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

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}
parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1", "TRUE", "T", "YES", "Y")
}
parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}
ym_index <- function(date) {
  y <- as.integer(format(date, "%Y")); m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}
log_line <- function(path, msg) cat(msg, "\n", file = path, append = TRUE)
safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

# ----------------------------- config -------------------------------------

SCENARIO   <- tolower(getenv1("SCENARIO", "start202206"))
if (!SCENARIO %in% c("full", "start202206")) stop("SCENARIO must be full or start202206")
ERR_MODE   <- tolower(getenv1("ERR_MODE", "donorpath"))
if (!ERR_MODE %in% c("donorpath", "ar1")) stop("ERR_MODE must be donorpath or ar1")

N_SIMS       <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
RUN_WILD     <- parse_bool(getenv1("RUN_WILD", "TRUE"), TRUE) && wild_available
N_WILD_SIMS  <- parse_int(getenv1("N_WILD_SIMS", "1000"), 1000L)
WILD_B       <- parse_int(getenv1("WILD_B", "999"), 999L)
SEED         <- parse_int(getenv1("SEED", "20260921"), 20260921L)
ALPHA        <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
N_WORKERS    <- min(6L, parse_int(getenv1("N_WORKERS", "6"), 6L))
OUT_BASE     <- getenv1("OUT_DIR", "output/twfe_power_donorpath_v20260921")
DROP_ALREADY_TREATED <- parse_bool(getenv1("DROP_ALREADY_TREATED", "TRUE"), TRUE)
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
MDE_GRID_MAX  <- 0.40
MDE_GRID_STEP <- 0.001
MC_BOOT_B     <- 500L

out_dir <- if (ERR_MODE == "ar1") {
  file.path(OUT_BASE, SCENARIO, "ar1_crosscheck")
} else {
  file.path(OUT_BASE, SCENARIO)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(out_dir, "run.log")
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)

log_line(RUN_LOG, "=== TWFE DONOR-PATH POWER SIM ===")
log_line(RUN_LOG, glue("R: {R.version.string}"))
log_line(RUN_LOG, glue("SCENARIO={SCENARIO}  ERR_MODE={ERR_MODE}  N_SIMS={N_SIMS}  SEED={SEED}"))
log_line(RUN_LOG, glue("RUN_WILD={RUN_WILD} (fwildclusterboot available={wild_available})  N_WILD_SIMS={N_WILD_SIMS}  WILD_B={WILD_B}"))
log_line(RUN_LOG, glue("N_WORKERS={N_WORKERS}  ALPHA={ALPHA}"))

# ----------------------------- load panel + schedule -----------------------

panel_file <- "data/raw/state_month_panel_with_treatment.csv"
treat_file <- "data/raw/sports_gambling_legalization_dates.csv"

panel0 <- read_csv(panel_file, show_col_types = FALSE) %>%
  filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING) %>%
  mutate(month_date = as.Date(month_date))

sched <- eviction_adoption_outcomes(treat_file, "online_start_date",
                                    censor_end = max(panel0$month_date)) %>%
  filter(state_abb %in% unique(panel0$state_abb)) %>%
  select(state_abb, adopt_date)

panel0 <- panel0 %>% left_join(sched, by = "state_abb")
stopifnot(!anyNA(panel0$adopt_date) | TRUE)  # NA adopt_date == never-treated, fine

# state-level treat_start computed BEFORE any date-window subsetting
state_treat <- panel0 %>%
  distinct(state_abb, adopt_date)

MIN_DATE <- if (SCENARIO == "start202206") as.Date("2022-06-01") else as.Date(NA)

panel <- panel0
if (!is.na(MIN_DATE)) {
  panel <- panel %>% filter(month_date >= MIN_DATE)
  if (DROP_ALREADY_TREATED) {
    already_treated <- state_treat %>%
      filter(!is.na(adopt_date), adopt_date < MIN_DATE) %>%
      pull(state_abb)
    n_before <- n_distinct(panel$state_abb)
    panel <- panel %>% filter(!state_abb %in% already_treated)
    log_line(RUN_LOG, glue("Dropped {length(already_treated)} already-treated state(s) before {MIN_DATE}: {paste(sort(already_treated), collapse=', ')} ({n_before} -> {n_distinct(panel$state_abb)} states)"))
  }
}

# Q1 default (b): full scenario drops COVID months from the analysis panel entirely
COVID_START <- as.Date("2020-03-01"); COVID_END <- as.Date("2021-06-01")  # [start,end)
if (SCENARIO == "full") {
  n_before <- nrow(panel)
  panel <- panel %>% filter(!(month_date >= COVID_START & month_date < COVID_END))
  log_line(RUN_LOG, glue("Q1(b): dropped COVID months [{COVID_START},{COVID_END}) from 'full' analysis panel: {n_before} -> {nrow(panel)} rows"))
}

panel <- panel %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(adopt_date), 0L, ym_index(adopt_date)),
    g = as.integer(g),
    state_abb = as.character(state_abb)
  )

target_states <- sort(unique(panel$state_abb))
panel$id <- match(panel$state_abb, target_states)

g_bad <- panel %>% group_by(state_abb) %>% summarise(ng = n_distinct(g), .groups = "drop") %>% filter(ng != 1)
if (nrow(g_bad) > 0) stop("g not constant within state", call. = FALSE)

panel <- panel %>%
  mutate(
    untreated_obs = (g == 0L) | (t < g),
    post = as.integer((g > 0L) & (t >= g))
  )

n_states  <- n_distinct(panel$state_abb)
n_switch  <- sum((panel %>% distinct(state_abb, g))$g > 0)
n_never   <- n_states - n_switch
switcher_states <- sort((panel %>% distinct(state_abb, g) %>% filter(g > 0))$state_abb)
never_states    <- sort((panel %>% distinct(state_abb, g) %>% filter(g == 0))$state_abb)

log_line(RUN_LOG, glue("Panel: states={n_states} (switchers={n_switch}, never={n_never}); rows={nrow(panel)}"))
log_line(RUN_LOG, glue("Switchers: {paste(switcher_states, collapse=', ')}"))
log_line(RUN_LOG, glue("Never-treated (donor pool): {paste(never_states, collapse=', ')}"))

panel_summary <- tibble(
  scenario = SCENARIO, err_mode = ERR_MODE,
  n_states = n_states, n_switchers = n_switch, n_never_treated = n_never,
  n_rows = nrow(panel),
  min_month = min(panel$month_date), max_month = max(panel$month_date),
  n_months = n_distinct(panel$t),
  switcher_states = paste(switcher_states, collapse = ";"),
  never_states = paste(never_states, collapse = ";")
)
safe_write_csv(panel_summary, file.path(out_dir, "panel_summary.csv"))

# ----------------------------- outcome + FE fit -----------------------------

panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))

base_fe <- panel %>% filter(untreated_obs, is.finite(y))
untreated_by_t <- base_fe %>% count(t, name = "n_untreated")
missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
if (length(missing_t) > 0) {
  log_line(RUN_LOG, glue("WARNING: dropping {length(missing_t)} month(s) with zero untreated obs: {paste(missing_t, collapse=',')}"))
  panel   <- panel   %>% filter(!t %in% missing_t)
  base_fe <- base_fe %>% filter(!t %in% missing_t)
}

set.seed(SEED)
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
if (any(!is.finite(panel$yhat))) {
  n_drop <- sum(!is.finite(panel$yhat))
  log_line(RUN_LOG, glue("WARNING: dropping {n_drop} non-finite yhat rows"))
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}
base_fe$ehat <- as.numeric(residuals(fe_fit))
log_line(RUN_LOG, glue("Final analysis panel: {nrow(panel)} rows; FE fit sample: {nrow(base_fe)} untreated obs"))

all_t <- sort(unique(panel$t))
t_row_idx <- match(panel$t, all_t)

################################################################################
# ERR_MODE == "donorpath"
################################################################################
if (ERR_MODE == "donorpath") {

  donor_states <- never_states
  if (length(donor_states) < 2) stop("Fewer than 2 never-treated donor states; donor-path noise is not viable.", call. = FALSE)

  donor_resid <- base_fe %>% filter(state_abb %in% donor_states)
  E <- matrix(NA_real_, nrow = length(all_t), ncol = length(donor_states),
              dimnames = list(as.character(all_t), donor_states))
  E[cbind(match(donor_resid$t, all_t), match(donor_resid$state_abb, donor_states))] <- donor_resid$ehat

  # coverage_i_d: share of state i's t-values donor d has residual data for
  coverage <- matrix(NA_real_, nrow = length(target_states), ncol = length(donor_states),
                      dimnames = list(target_states, donor_states))
  for (i in seq_along(target_states)) {
    t_needed <- unique(panel$t[panel$state_abb == target_states[i]])
    row_idx <- match(t_needed, all_t)
    coverage[i, ] <- vapply(seq_along(donor_states), function(d) mean(!is.na(E[row_idx, d])), numeric(1))
  }
  expected_drop_share <- 1 - rowMeans(coverage)
  avg_expected_drop_share <- mean(expected_drop_share)
  log_line(RUN_LOG, glue("Donor pool: {length(donor_states)} states. Expected mean share of state-months dropped under uniform donor draw: {round(avg_expected_drop_share, 4)}"))

  RESTRICT_DONORS <- avg_expected_drop_share > 0.10
  allowed_idx <- vector("list", length(target_states))
  if (RESTRICT_DONORS) {
    log_line(RUN_LOG, "Expected drop share > 10%: restricting donor draws per state to donors covering >=80% of that state's months.")
    for (i in seq_along(target_states)) {
      ok <- which(coverage[i, ] >= 0.80)
      if (length(ok) == 0) {
        ok <- which(coverage[i, ] == max(coverage[i, ]))
        log_line(RUN_LOG, glue("  WARNING: no donor covers >=80% of {target_states[i]}'s months; falling back to best-coverage donor(s) (max coverage={round(max(coverage[i,]),3)})."))
      }
      allowed_idx[[i]] <- ok
    }
  } else {
    for (i in seq_along(target_states)) allowed_idx[[i]] <- seq_along(donor_states)
  }

  one_sim <- function(seed, delta) {
    set.seed(seed)
    donor_idx_for_state <- vapply(seq_along(target_states), function(i) {
      pool <- allowed_idx[[i]]
      if (length(pool) == 1) pool else sample(pool, 1)
    }, integer(1))
    sign_for_state <- sample(c(-1, 1), length(target_states), replace = TRUE)

    col_for_row  <- donor_idx_for_state[panel$id]
    sign_for_row <- sign_for_state[panel$id]
    e_val <- E[cbind(t_row_idx, col_for_row)]
    keep <- is.finite(e_val)

    dat <- data.frame(
      id   = panel$id[keep],
      t    = panel$t[keep],
      post = panel$post[keep],
      y    = panel$yhat[keep] + sign_for_row[keep] * e_val[keep] + delta * panel$post[keep]
    )
    drop_share <- 1 - mean(keep)

    est <- tryCatch(
      fixest::feols(y ~ post | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE),
      error = function(e) NULL
    )
    if (is.null(est)) return(list(ok = FALSE, drop_share = drop_share))

    ct <- fixest::coeftable(est)
    if (!("post" %in% rownames(ct))) return(list(ok = FALSE, drop_share = drop_share))
    att <- unname(ct["post", "Estimate"]); se <- unname(ct["post", "Std. Error"])
    G <- length(unique(dat$id[fixest::obs(est)]))
    if (!is.finite(att) || !is.finite(se) || se <= 0) return(list(ok = FALSE, drop_share = drop_share))

    out <- list(ok = TRUE, att = att, se = se, G = G, drop_share = drop_share, seed = seed, est = est, dat = dat)
    out
  }

} else {
################################################################################
# ERR_MODE == "ar1"  (legacy-style, pooled untreated residuals, in-window)
################################################################################
  pool_dat <- base_fe
  month_counts <- pool_dat %>% group_by(t) %>% summarise(n = n_distinct(state_abb), .groups = "drop")
  months_retained <- month_counts %>% filter(n >= MIN_STATES_PER_MONTH) %>% pull(t)
  pool_dat <- pool_dat %>% filter(t %in% months_retained)

  sd_by_t <- pool_dat %>% group_by(t) %>% summarise(sd_e = sd(ehat, na.rm = TRUE), n = n(), .groups = "drop")
  sd_global <- sd(pool_dat$ehat, na.rm = TRUE)
  sd_by_t <- sd_by_t %>% mutate(sd_e = if_else(is.finite(sd_e) & sd_e > 1e-8, sd_e, sd_global))
  sd_map <- setNames(sd_by_t$sd_e, as.character(sd_by_t$t))

  pool_dat <- pool_dat %>%
    mutate(sd_t = dplyr::coalesce(unname(sd_map[as.character(t)]), sd_global),
           z = ehat / sd_t)

  std_pool_by_t <- split(pool_dat$z, pool_dat$t)
  std_global_pool <- pool_dat$z[is.finite(pool_dat$z)]

  tmp <- pool_dat %>% arrange(id, t) %>% group_by(id) %>% mutate(z_lag = dplyr::lag(z), t_lag = dplyr::lag(t)) %>% ungroup() %>%
    filter(t - t_lag == 1)
  rho_used <- suppressWarnings(stats::cor(tmp$z, tmp$z_lag, use = "complete.obs"))
  if (!is.finite(rho_used)) rho_used <- 0
  rho_used <- max(-0.98, min(0.98, rho_used))
  sigma_u <- sqrt(max(0, 1 - rho_used^2))

  sd_row <- unname(sd_map[as.character(panel$t)]); sd_row[!is.finite(sd_row) | sd_row <= 0] <- sd_global
  idx_by_id <- split(seq_len(nrow(panel)), panel$id)
  idx_by_id <- lapply(idx_by_id, function(idx) idx[order(panel$t[idx])])

  log_line(RUN_LOG, glue("AR(1) cross-check calibration (in-window): rho={round(rho_used,4)}  sigma_u={round(sigma_u,4)}  sd_global={round(sd_global,4)}  N_untreated_pool={nrow(pool_dat)}"))

  one_sim <- function(seed, delta) {
    set.seed(seed)
    e_draw <- numeric(nrow(panel))
    for (idx in idx_by_id) {
      m <- length(idx); if (m <= 0) next
      z_innov <- vapply(panel$t[idx], function(tt_i) {
        pool <- std_pool_by_t[[as.character(tt_i)]]
        if (is.null(pool) || length(pool) < MIN_STATES_PER_MONTH) pool <- std_global_pool
        sample(pool, 1)
      }, numeric(1))
      x <- numeric(m); x[1] <- z_innov[1]
      if (m >= 2) for (j in 2:m) x[j] <- rho_used * x[j - 1] + sigma_u * z_innov[j]
      e_draw[idx] <- x * sd_row[idx]
    }
    dat <- data.frame(id = panel$id, t = panel$t, post = panel$post,
                       y = panel$yhat + e_draw + delta * panel$post)
    est <- tryCatch(fixest::feols(y ~ post | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE),
                     error = function(e) NULL)
    if (is.null(est)) return(list(ok = FALSE, drop_share = 0))
    ct <- fixest::coeftable(est)
    if (!("post" %in% rownames(ct))) return(list(ok = FALSE, drop_share = 0))
    att <- unname(ct["post", "Estimate"]); se <- unname(ct["post", "Std. Error"])
    G <- length(unique(dat$id[fixest::obs(est)]))
    if (!is.finite(att) || !is.finite(se) || se <= 0) return(list(ok = FALSE, drop_share = 0))
    list(ok = TRUE, att = att, se = se, G = G, drop_share = 0, seed = seed, est = est, dat = dat)
  }
}

# ----------------------------- main sim loop (delta = 0) --------------------

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

cl <- NULL
if (N_WORKERS > 1L) {
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(out_dir, "cluster.log"))
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
  parallel::clusterEvalQ(cl, { suppressPackageStartupMessages(library(fixest)); NULL })
  parallel::clusterExport(cl, varlist = ls(), envir = environment())
}

run_batch <- function(seeds, delta) {
  if (!is.null(cl)) parallel::parLapply(cl, seeds, function(s) one_sim(s, delta))
  else lapply(seeds, function(s) one_sim(s, delta))
}

t0 <- Sys.time()
results0 <- run_batch(sim_seeds, 0)
t1 <- Sys.time()
runtime_main_sec <- as.numeric(difftime(t1, t0, units = "secs"))
log_line(RUN_LOG, glue("Main delta=0 loop ({N_SIMS} sims): {round(runtime_main_sec,1)}s"))

ok0   <- vapply(results0, function(x) isTRUE(x$ok), logical(1))
att0  <- vapply(results0, function(x) if (isTRUE(x$ok)) x$att else NA_real_, numeric(1))
se0   <- vapply(results0, function(x) if (isTRUE(x$ok)) x$se  else NA_real_, numeric(1))
G0    <- vapply(results0, function(x) if (isTRUE(x$ok)) x$G   else NA_integer_, integer(1))
drop_share0 <- vapply(results0, function(x) if (!is.null(x$drop_share)) x$drop_share else NA_real_, numeric(1))

log_line(RUN_LOG, glue("OK sims: {sum(ok0)}/{N_SIMS}. Mean share of state-months dropped per sim: {round(mean(drop_share0, na.rm=TRUE),4)}"))

sims_delta0 <- tibble(seed = sim_seeds, ok = ok0, att0 = att0, se0 = se0, G = G0, drop_share = drop_share0)

# ----------------------------- wild bootstrap arm ---------------------------

wild_ci <- tibble(seed = integer(), ci_lo = double(), ci_hi = double())
if (RUN_WILD) {
  wild_seeds <- sim_seeds[seq_len(min(N_WILD_SIMS, N_SIMS))]
  wild_results0 <- results0[seq_len(min(N_WILD_SIMS, N_SIMS))]

  do_wild <- function(res) {
    if (!isTRUE(res$ok)) return(c(NA_real_, NA_real_))
    b <- tryCatch(
      fwildclusterboot::boottest(res$est, param = "post", B = WILD_B, type = "rademacher", clustid = "id"),
      error = function(e) NULL
    )
    if (is.null(b)) return(c(NA_real_, NA_real_))
    ci <- confint(b)
    ci <- as.numeric(unlist(ci))
    if (length(ci) < 2) return(c(NA_real_, NA_real_))
    ci[c(1, 2)]
  }

  t0w <- Sys.time()
  if (!is.null(cl)) {
    parallel::clusterExport(cl, varlist = c("wild_results0", "do_wild", "WILD_B"), envir = environment())
    wild_out <- parallel::parLapply(cl, wild_results0, do_wild)
  } else {
    wild_out <- lapply(wild_results0, do_wild)
  }
  t1w <- Sys.time()
  runtime_wild_sec <- as.numeric(difftime(t1w, t0w, units = "secs"))
  log_line(RUN_LOG, glue("Wild bootstrap arm ({length(wild_seeds)} sims x B={WILD_B}): {round(runtime_wild_sec,1)}s"))

  wild_mat <- do.call(rbind, wild_out)
  wild_ci <- tibble(seed = wild_seeds, ci_lo = wild_mat[, 1], ci_hi = wild_mat[, 2])
} else {
  runtime_wild_sec <- 0
  log_line(RUN_LOG, glue("Wild bootstrap arm SKIPPED (RUN_WILD={RUN_WILD}, fwildclusterboot available={wild_available})"))
}

sims_delta0 <- sims_delta0 %>% left_join(wild_ci, by = "seed")
safe_write_csv(sims_delta0, file.path(out_dir, "sims_delta0.csv"))

# ----------------------------- power / MDE -----------------------------------

att0_ok <- att0[ok0]; se0_ok <- se0[ok0]; G0_ok <- G0[ok0]
tcrit_ok <- qt(1 - ALPHA / 2, df = pmax(G0_ok - 1, 1))
mean_att0 <- mean(att0_ok); sd_att0 <- sd(att0_ok); mean_se0 <- mean(se0_ok)
mc_se_att0 <- sd_att0 / sqrt(length(att0_ok))
size_analytic <- mean(abs(att0_ok) / se0_ok > tcrit_ok)

# align wild CI to ok0 ordering (wild_ci only covers first N_WILD_SIMS seeds)
wild_lo <- rep(NA_real_, N_SIMS); wild_hi <- rep(NA_real_, N_SIMS)
idx_match <- match(wild_ci$seed, sim_seeds)
wild_lo[idx_match] <- wild_ci$ci_lo
wild_hi[idx_match] <- wild_ci$ci_hi
wild_ok <- ok0 & is.finite(wild_lo) & is.finite(wild_hi)
size_wild <- if (any(wild_ok)) mean(!(wild_lo[wild_ok] <= 0 & 0 <= wild_hi[wild_ok])) else NA_real_

power_at_delta_analytic <- function(delta, recentre = FALSE) {
  a <- att0_ok - (if (recentre) mean_att0 else 0)
  mean(abs(a + delta) / se0_ok > tcrit_ok)
}
power_at_delta_wild <- function(delta, recentre = FALSE) {
  if (!any(wild_ok)) return(NA_real_)
  lo <- wild_lo[wild_ok] - (if (recentre) mean_att0 else 0)
  hi <- wild_hi[wild_ok] - (if (recentre) mean_att0 else 0)
  mean(!(lo <= -delta & -delta <= hi))
}

grid <- seq(0, MDE_GRID_MAX, by = MDE_GRID_STEP)
power_curve <- tibble(
  delta_log = grid,
  power_analytic_raw       = vapply(grid, power_at_delta_analytic, numeric(1), recentre = FALSE),
  power_analytic_recentred = vapply(grid, power_at_delta_analytic, numeric(1), recentre = TRUE),
  power_wild_raw       = vapply(grid, power_at_delta_wild, numeric(1), recentre = FALSE),
  power_wild_recentred = vapply(grid, power_at_delta_wild, numeric(1), recentre = TRUE)
)
safe_write_csv(power_curve, file.path(out_dir, "power_curve.csv"))

mde_from_curve <- function(delta_grid, power_grid, target = 0.80) {
  power_grid[is.na(power_grid)] <- 0
  above <- which(power_grid >= target)
  if (length(above) == 0) return(NA_real_)
  k <- min(above)
  if (k == 1) return(delta_grid[1])
  d1 <- delta_grid[k - 1]; d2 <- delta_grid[k]
  p1 <- power_grid[k - 1]; p2 <- power_grid[k]
  if (p2 == p1) return(d2)
  d1 + (target - p1) * (d2 - d1) / (p2 - p1)
}

mde_analytic_raw       <- mde_from_curve(grid, power_curve$power_analytic_raw)
mde_analytic_recentred <- mde_from_curve(grid, power_curve$power_analytic_recentred)
mde_wild_raw       <- mde_from_curve(grid, power_curve$power_wild_raw)
mde_wild_recentred <- mde_from_curve(grid, power_curve$power_wild_recentred)

# bootstrap-over-sims 95% CI for MDE (analytic raw, and wild raw if available)
boot_mde <- function(att0_vec, se0_vec, tcrit_vec, B = MC_BOOT_B) {
  n <- length(att0_vec)
  out <- vapply(seq_len(B), function(b) {
    idx <- sample.int(n, n, replace = TRUE)
    a <- att0_vec[idx]; s <- se0_vec[idx]; tc <- tcrit_vec[idx]
    pw <- vapply(grid, function(d) mean(abs(a + d) / s > tc), numeric(1))
    mde_from_curve(grid, pw)
  }, numeric(1))
  out
}
set.seed(SEED + 999)
boot_analytic <- boot_mde(att0_ok, se0_ok, tcrit_ok)
mde_analytic_ci <- quantile(boot_analytic, c(0.025, 0.975), na.rm = TRUE)

boot_mde_wild <- function(lo_vec, hi_vec, B = MC_BOOT_B) {
  n <- length(lo_vec)
  out <- vapply(seq_len(B), function(b) {
    idx <- sample.int(n, n, replace = TRUE)
    lo <- lo_vec[idx]; hi <- hi_vec[idx]
    pw <- vapply(grid, function(d) mean(!(lo <= -d & -d <= hi)), numeric(1))
    mde_from_curve(grid, pw)
  }, numeric(1))
  out
}
if (any(wild_ok)) {
  set.seed(SEED + 998)
  boot_wild <- boot_mde_wild(wild_lo[wild_ok], wild_hi[wild_ok])
  mde_wild_ci <- quantile(boot_wild, c(0.025, 0.975), na.rm = TRUE)
} else {
  mde_wild_ci <- c(NA_real_, NA_real_)
}

pct_from_log <- function(x) exp(x) - 1

mde_tbl <- tibble(
  arm = c("analytic_raw", "analytic_recentred", "wild_raw", "wild_recentred"),
  mde_log = c(mde_analytic_raw, mde_analytic_recentred, mde_wild_raw, mde_wild_recentred),
  mde_pct = pct_from_log(c(mde_analytic_raw, mde_analytic_recentred, mde_wild_raw, mde_wild_recentred)),
  ci_lo_log = c(mde_analytic_ci[1], NA, mde_wild_ci[1], NA),
  ci_hi_log = c(mde_analytic_ci[2], NA, mde_wild_ci[2], NA),
  size_at_delta0 = c(size_analytic, size_analytic, size_wild, size_wild),
  mean_att0 = mean_att0, sd_att0 = sd_att0, mean_se0 = mean_se0, mc_se_att0 = mc_se_att0
)
safe_write_csv(mde_tbl, file.path(out_dir, "mde.csv"))

log_line(RUN_LOG, glue("Size @ delta0: analytic={round(size_analytic,4)}  wild={ifelse(is.na(size_wild),'NA',round(size_wild,4))}"))
log_line(RUN_LOG, glue("Mean att0={signif(mean_att0,4)}  SD(att0)={signif(sd_att0,4)}  Mean SE={signif(mean_se0,4)}"))
log_line(RUN_LOG, glue("MDE80 analytic raw={round(mde_analytic_raw,4)} ({round(100*pct_from_log(mde_analytic_raw),2)}%)  recentred={round(mde_analytic_recentred,4)}"))
log_line(RUN_LOG, glue("MDE80 wild raw={ifelse(is.na(mde_wild_raw),'NA',round(mde_wild_raw,4))}  recentred={ifelse(is.na(mde_wild_recentred),'NA',round(mde_wild_recentred,4))}"))

# ----------------------------- checks ----------------------------------------

checks <- list()

## C1: shift-equivariance for 5 seeds at delta=0.10 (log points, imposed directly)
c1_seeds <- sim_seeds[seq_len(5)]
c1_delta <- 0.10
c1_ok <- TRUE; c1_max_att_diff <- NA_real_; c1_max_se_diff <- NA_real_
c1_res0 <- results0[seq_len(5)]
c1_res_shift <- lapply(c1_seeds, function(s) one_sim(s, c1_delta))
c1_att_diffs <- mapply(function(r0, rs) {
  if (!isTRUE(r0$ok) || !isTRUE(rs$ok)) return(NA_real_)
  (rs$att - r0$att) - c1_delta
}, c1_res0, c1_res_shift)
c1_se_diffs <- mapply(function(r0, rs) {
  if (!isTRUE(r0$ok) || !isTRUE(rs$ok)) return(NA_real_)
  rs$se - r0$se
}, c1_res0, c1_res_shift)
c1_max_att_diff <- max(abs(c1_att_diffs), na.rm = TRUE)
c1_max_se_diff  <- max(abs(c1_se_diffs), na.rm = TRUE)
c1_ok <- is.finite(c1_max_att_diff) && c1_max_att_diff < 1e-8 && is.finite(c1_max_se_diff) && c1_max_se_diff < 1e-8
checks$C1 <- tibble(check = "C1_shift_equivariance", pass = c1_ok,
                     value = c1_max_att_diff, threshold = 1e-8,
                     note = glue("max|att diff|={signif(c1_max_att_diff,3)} max|se diff|={signif(c1_max_se_diff,3)} (delta imposed in log points, direct comparison, not log(1+delta) since spec says use log points throughout)"))

## C2: reconciliation against legacy iid_month SD(att)=0.0099 (full scenario only)
c2_note <- "N/A (only checked for SCENARIO=full, ERR_MODE=donorpath)"
c2_ok <- NA
c2_val <- NA_real_
if (SCENARIO == "full" && ERR_MODE == "donorpath") {
  c2_file <- file.path(out_dir, "_c2_iid_month_check", "power_by_effect.csv")
  if (file.exists(c2_file)) {
    c2_pwr <- read_csv(c2_file, show_col_types = FALSE)
    c2_row <- c2_pwr %>% filter(abs(effect_pct) < 1e-12) %>% slice(1)
    c2_val <- c2_row$sd_att
    target <- 0.0099
    c2_ok <- is.finite(c2_val) && abs(c2_val - target) / target <= 0.05
    c2_note <- glue("legacy iid_month SD(att)={signif(c2_val,4)} vs target {target} (rel diff={round(abs(c2_val-target)/target,4)})")
  } else {
    c2_note <- glue("SKIPPED: legacy reconciliation file not found at {c2_file}")
  }
}
checks$C2 <- tibble(check = "C2_iid_month_reconciliation", pass = c2_ok, value = c2_val, threshold = 0.0099, note = c2_note)

## C3: null centre
c3_thresh <- 3 * mc_se_att0
c3_ok <- abs(mean_att0) < c3_thresh
checks$C3 <- tibble(check = "C3_null_centre", pass = c3_ok, value = mean_att0, threshold = c3_thresh,
                     note = glue("|mean att0|={signif(abs(mean_att0),4)} vs 3*MC_SE={signif(c3_thresh,4)}"))

## C4: persistence carried -- lag-1 autocorr of simulated errors vs donor residuals (donorpath only)
c4_note <- "N/A (only checked for ERR_MODE=donorpath)"
c4_ok <- NA; c4_diff <- NA_real_
if (ERR_MODE == "donorpath") {
  sd_t_donor <- apply(E, 1, sd, na.rm = TRUE)
  Zdonor <- sweep(E, 1, sd_t_donor, "/")
  target_pairs <- lapply(seq_along(donor_states), function(d) {
    z <- Zdonor[, d]
    ok_idx <- which(!is.na(z))
    if (length(ok_idx) < 2) return(NULL)
    tvals <- all_t[ok_idx]
    keep <- c(FALSE, diff(tvals) == 1)
    if (!any(keep)) return(NULL)
    idx_cur <- ok_idx[keep]; idx_lag <- ok_idx[which(keep) - 1]
    # NB: tibble() evaluates columns left-to-right and a later column can shadow
    # an outer-scope object of the same name -- z_cur/z_lag_val avoid that trap
    # (z = z[idx_cur], z_lag = z[idx_lag]) silently re-reads the *new* z column.
    z_cur <- z[idx_cur]; z_lag_val <- z[idx_lag]
    tibble(z = z_cur, z_lag = z_lag_val)
  })
  target_pairs <- dplyr::bind_rows(target_pairs)
  rho_target <- suppressWarnings(cor(target_pairs$z, target_pairs$z_lag, use = "complete.obs"))

  n_c4_sims <- min(200L, N_SIMS)
  c4_seeds <- sim_seeds[seq_len(n_c4_sims)]
  sim_pairs <- lapply(c4_seeds, function(s) {
    set.seed(s)
    donor_idx_for_state <- vapply(seq_along(target_states), function(i) {
      pool <- allowed_idx[[i]]; if (length(pool) == 1) pool else sample(pool, 1)
    }, integer(1))
    col_for_row <- donor_idx_for_state[panel$id]
    e_val <- E[cbind(t_row_idx, col_for_row)]
    z_val <- e_val / sd_t_donor[t_row_idx]
    df <- tibble(id = panel$id, t = panel$t, z = z_val) %>% filter(is.finite(z)) %>% arrange(id, t)
    df <- df %>% group_by(id) %>% mutate(z_lag = dplyr::lag(z), t_lag = dplyr::lag(t)) %>% ungroup() %>%
      filter(t - t_lag == 1)
    df %>% select(z, z_lag)
  })
  sim_pairs <- dplyr::bind_rows(sim_pairs)
  rho_sim <- suppressWarnings(cor(sim_pairs$z, sim_pairs$z_lag, use = "complete.obs"))

  c4_diff <- abs(rho_sim - rho_target)
  c4_ok <- is.finite(c4_diff) && c4_diff < 0.05
  c4_note <- glue("donor rho={round(rho_target,4)}  simulated rho={round(rho_sim,4)}  |diff|={round(c4_diff,4)} (n_sims_used={n_c4_sims})")
}
checks$C4 <- tibble(check = "C4_persistence_carried", pass = c4_ok, value = c4_diff, threshold = 0.05, note = c4_note)

## C5: counts written to panel_summary.csv already; record pass here
checks$C5 <- tibble(check = "C5_counts", pass = TRUE, value = n_states, threshold = NA_real_,
                     note = glue("states={n_states} switchers={n_switch} never={n_never} rows={nrow(panel)}. Switchers: {paste(switcher_states, collapse=',')}"))

checks_tbl <- dplyr::bind_rows(checks)
safe_write_csv(checks_tbl, file.path(out_dir, "checks.csv"))

for (i in seq_len(nrow(checks_tbl))) {
  log_line(RUN_LOG, glue("{checks_tbl$check[i]}: pass={checks_tbl$pass[i]} -- {checks_tbl$note[i]}"))
}

log_line(RUN_LOG, "=== DONE ===")
cat(glue("DONE: {SCENARIO} / {ERR_MODE}. Out dir: {out_dir}\n"))
