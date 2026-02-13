#!/usr/bin/env Rscript
################################################################################
# pretrends_statepanel_template.R
#
# Pre-trends diagnostics for state-month eviction panel:
#   A) CS-DiD (Callaway-Sant'Anna) dynamic event study — analytic + bootstrap
#   B) TWFE / Sun-Abraham event study
#   C) Gambling intensity heterogeneity (optional)
#   D) Self-test calibration (optional) — guards against inflated CS SEs
#
# All configuration via environment variables (see SECTION 2).
# Run via: bash scripts/run_pretrends_statepanel.sh
################################################################################

# Force single-threaded BLAS to avoid contention under mclapply
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(fixest)
  library(patchwork)
  library(did)
  library(parallel)
  library(glue)
})

################################################################################
# SECTION 1: HELPER FUNCTIONS
################################################################################

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1", "TRUE", "T", "YES", "Y")
}

parse_chr_list <- function(x, default = character()) {
  if (!nzchar(x)) return(default)
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

parse_date <- function(x, default = as.Date(NA)) {
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.Date(x))
  if (is.na(out)) default else out
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

run_serial_or_parallel <- function(X, FUN, cores = 1L) {
  cores <- as.integer(max(1L, cores))
  if (cores <= 1L) return(lapply(X, FUN))
  if (.Platform$OS.type == "windows") return(lapply(X, FUN))
  mclapply(X, FUN, mc.cores = cores)
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

################################################################################
# SECTION 2: CONFIGURATION
################################################################################

PANEL_FILE    <- getenv1("PANEL_FILE", "data/raw/state_month_panel_with_treatment.csv")
EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"))
MIN_DATE      <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE      <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
DROP_START    <- parse_date(getenv1("DROP_START", ""))
DROP_END      <- parse_date(getenv1("DROP_END", ""))
COVERAGE_THRESHOLD_RAW <- getenv1("COVERAGE_THRESHOLD", "")
COVERAGE_THRESHOLD <- if (nzchar(COVERAGE_THRESHOLD_RAW)) {
  parse_int(COVERAGE_THRESHOLD_RAW, 0L)
} else {
  NA_integer_
}
BALANCE_COMMON_MONTHS <- parse_bool(getenv1("BALANCE_COMMON_MONTHS", "TRUE"), TRUE)

OUTCOME       <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS      <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

CONTROL_GROUP <- getenv1("CONTROL_GROUP", "notyettreated")
EST_METHOD    <- getenv1("EST_METHOD", "reg")
ALLOW_UNBALANCED <- parse_bool(getenv1("ALLOW_UNBALANCED_PANEL", "TRUE"), TRUE)
PRE_WINDOW    <- eval(parse(text = getenv1("PRE_WINDOW", "-12:-1")))

CS_ANALYTIC   <- parse_bool(getenv1("CS_ANALYTIC", "TRUE"), TRUE)
CS_BOOTSTRAP  <- parse_bool(getenv1("CS_BOOTSTRAP", "TRUE"), TRUE)
CS_BITERS     <- parse_int(getenv1("CS_BITERS", "199"), 199L)
CS_FASTER_MODE <- parse_bool(getenv1("CS_FASTER_MODE", "TRUE"), TRUE)

GAMBLING_FILE <- getenv1("GAMBLING_FILE", "")
GAMBLING_AMOUNT_COL <- getenv1("GAMBLING_AMOUNT_COL", "Handle")

ALPHA         <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED          <- parse_int(getenv1("SEED", "123"), 123L)

SELF_TEST     <- parse_bool(getenv1("SELF_TEST", "FALSE"), FALSE)
SELF_TEST_N   <- parse_int(getenv1("SELF_TEST_N", "200"), 200L)
SELF_TEST_ERR_MODE <- tolower(trimws(getenv1("SELF_TEST_ERR_MODE", "resid_pool_ar1_state")))

req_cores <- parse_int(getenv1("N_CORES", ""), NA_integer_)
if (!is.finite(req_cores) || req_cores < 1L) req_cores <- 1L
N_CORES <- max(1L, req_cores)

OUT_DIR       <- getenv1("OUT_DIR", "output/pretrends_statepanel_template")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(OUT_DIR, "run_log.txt")

fmt_date <- function(d) {
  if (is.na(d)) "<none>" else format(d)
}

# Remove previously-generated outputs so failed steps can't leave stale files.
# (This is intentionally conservative: only known filenames in this pipeline.)
known_outputs <- c(
  "README.md",
  "panel_summary.csv",
  "pretrends_summary.csv",
  "event_study_cs_analytic.csv",
  "event_study_cs_bootstrap.csv",
  "event_study_twfe_sunab.csv",
  "gambling_intensity_summary.csv",
  "self_test_raw.csv",
  "self_test_summary.csv",
  "cs_event_study_analytic.png",
  "cs_event_study_bootstrap.png",
  "cs_analytic_vs_bootstrap.png",
  "twfe_sunab_event_study.png",
  "cs_vs_twfe_comparison.png",
  "gambling_heterogeneity.png"
)
for (f in known_outputs) {
  p <- file.path(OUT_DIR, f)
  if (file.exists(p)) file.remove(p)
}

log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- paste0("[", ts, "] ", msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# Initialize log
cat("", file = LOG_FILE)

log_msg("=== Pre-trends diagnostics (state panel) ===")
log_msg(glue("PANEL_FILE: {PANEL_FILE}"))
log_msg(glue("EXCLUDE_STATES: {paste(EXCLUDE_STATES, collapse=',')}"))
log_msg(glue("MIN_DATE: {MIN_DATE}  MAX_DATE: {MAX_DATE}"))
log_msg(glue("DROP_START: {fmt_date(DROP_START)}  DROP_END: {fmt_date(DROP_END)}"))
log_msg(glue("COVERAGE_THRESHOLD (requested): {ifelse(is.finite(COVERAGE_THRESHOLD), COVERAGE_THRESHOLD, 'auto')}"))
log_msg(glue("BALANCE_COMMON_MONTHS: {BALANCE_COMMON_MONTHS}"))
log_msg(glue("OUTCOME: {OUTCOME}  RATE_EPS: {RATE_EPS}"))
log_msg(glue("CONTROL_GROUP: {CONTROL_GROUP}  EST_METHOD: {EST_METHOD}"))
log_msg(glue("ALLOW_UNBALANCED_PANEL: {ALLOW_UNBALANCED}"))
log_msg(glue("PRE_WINDOW: {paste(range(PRE_WINDOW), collapse=' to ')}"))
log_msg(glue("CS_ANALYTIC: {CS_ANALYTIC}  CS_BOOTSTRAP: {CS_BOOTSTRAP}  CS_BITERS: {CS_BITERS}"))
log_msg(glue("CS_FASTER_MODE: {CS_FASTER_MODE}"))
log_msg(glue("GAMBLING_FILE: {ifelse(nzchar(GAMBLING_FILE), GAMBLING_FILE, '<none>')}"))
log_msg(glue("GAMBLING_AMOUNT_COL: {GAMBLING_AMOUNT_COL}"))
log_msg(glue("ALPHA: {ALPHA}  SEED: {SEED}"))
log_msg(glue("SELF_TEST: {SELF_TEST}  SELF_TEST_N: {SELF_TEST_N}  SELF_TEST_ERR_MODE: {SELF_TEST_ERR_MODE}"))
log_msg(glue("N_CORES: {N_CORES}"))
log_msg(glue("OUT_DIR: {OUT_DIR}"))

if (!file.exists(PANEL_FILE)) stop("PANEL_FILE not found: ", PANEL_FILE, call. = FALSE)

################################################################################
# SECTION 3: LOAD AND PREPARE PANEL
################################################################################

log_msg("Loading panel...")

panel0 <- readr::read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
    filings_per_1k_renters = as.numeric(filings_per_1k_renters)
  )

if (length(EXCLUDE_STATES) > 0) panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)

if (xor(is.na(DROP_START), is.na(DROP_END))) {
  stop("If setting DROP_START or DROP_END, set both (e.g., DROP_START=2020-03-01 DROP_END=2021-07-31).", call. = FALSE)
}
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  n0 <- nrow(panel0)
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
  log_msg(glue("Dropped months in [{DROP_START}, {DROP_END}]: removed {n0 - nrow(panel0)} rows"))
}

coverage <- panel0 %>%
  count(state_abb, name = "n_months") %>%
  arrange(desc(n_months), state_abb)

max_coverage <- if (nrow(coverage) > 0) max(coverage$n_months, na.rm = TRUE) else NA_integer_
if (!is.finite(COVERAGE_THRESHOLD)) {
  COVERAGE_THRESHOLD <- max_coverage
}
log_msg(glue("COVERAGE_THRESHOLD (used): {COVERAGE_THRESHOLD}  (max_coverage={max_coverage})"))

keep_states <- coverage %>% filter(n_months >= COVERAGE_THRESHOLD) %>% pull(state_abb)
panel <- panel0 %>% filter(state_abb %in% keep_states)

if (nrow(panel) < 200) stop("Too few rows after filtering; panel size=", nrow(panel), call. = FALSE)

treat_by_state <- panel %>%
  group_by(state_abb) %>%
  summarise(
    treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE),
    .groups = "drop"
  )

panel <- panel %>%
  left_join(treat_by_state, by = "state_abb")

if (isTRUE(BALANCE_COMMON_MONTHS)) {
  n_states_tmp <- n_distinct(panel$state_abb)
  common_months <- panel %>%
    count(month_date, name = "n_states") %>%
    filter(n_states == n_states_tmp) %>%
    pull(month_date)
  panel <- panel %>% filter(month_date %in% common_months)
}

panel <- panel %>%
  mutate(
    id = as.integer(as.factor(state_abb)),
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    event_time = ifelse(g > 0L, t - g, NA_integer_),
    filings_per_1k_renters = if_else(
      is.finite(filings_per_1k_renters),
      filings_per_1k_renters,
      if_else(
        is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0 & is.finite(filings_count),
        1000 * filings_count / renter_occupied_housing_units,
        NA_real_
      )
    ),
    y = dplyr::case_when(
      OUTCOME == "log1p_filings_count" ~ log1p(pmax(filings_count, 0)),
      OUTCOME == "log1p_rate" ~ log(pmax(filings_per_1k_renters, 0) + RATE_EPS),
      TRUE ~ NA_real_
    )
  )

if (!OUTCOME %in% c("log1p_filings_count", "log1p_rate")) {
  stop("Unknown OUTCOME: ", OUTCOME, call. = FALSE)
}

n_states <- n_distinct(panel$id)
n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
n_never <- n_distinct(panel$state_abb[panel$g == 0L])
n_cohorts <- n_distinct(panel$g[panel$g > 0L])
t_vals <- sort(unique(panel$t))
n_t <- length(t_vals)

if (n_states < 8L) stop("Too few states after filtering; n_states=", n_states, call. = FALSE)

# Build lookup structures used by self-test
idx_by_id <- split(seq_len(nrow(panel)), panel$id)
t_index <- match(panel$t, t_vals)

# State mapping for output
id_to_state <- panel %>% distinct(id, state_abb) %>% arrange(id)

log_msg(glue("Panel: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_cohorts} cohorts, {n_t} months, {nrow(panel)} obs"))

panel_summary <- tibble(
  n_states = n_states, n_treated = n_treated, n_never_treated = n_never,
  n_cohorts = n_cohorts, n_months = n_t, n_obs = nrow(panel),
  min_date = min(panel$month_date), max_date = max(panel$month_date),
  coverage_threshold = COVERAGE_THRESHOLD, outcome = OUTCOME
)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

################################################################################
# SECTION 4: SELF-TEST CALIBRATION (optional, runs before main analysis)
################################################################################

HEADLINE_METHOD <- "analytic"  # default; may be overridden by self-test
self_test_results <- NULL

if (SELF_TEST) {
  log_msg(glue("Running self-test calibration: {SELF_TEST_N} sims, ERR_MODE={SELF_TEST_ERR_MODE}"))

  # --- build residual pool ---
  untreated_obs <- ((panel$g == 0L) | (panel$t < panel$g)) & is.finite(panel$y)
  base_fe <- panel %>% filter(untreated_obs)

  if (nrow(base_fe) < 100L) {
    stop("Too few untreated observations for residual-pool calibration (n=", nrow(base_fe), ").", call. = FALSE)
  }

  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

  # Handle non-finite yhat
  if (any(!is.finite(panel$yhat))) {
    mu_t <- base_fe %>%
      group_by(t) %>%
      summarise(mu = mean(y, na.rm = TRUE), .groups = "drop")
    mu_map <- setNames(mu_t$mu, as.character(mu_t$t))
    mu_global <- mean(base_fe$y, na.rm = TRUE)
    miss <- !is.finite(panel$yhat)
    panel$yhat[miss] <- mu_map[as.character(panel$t[miss])]
    panel$yhat[miss & !is.finite(panel$yhat)] <- mu_global
  }

  base_fe <- base_fe %>% mutate(ehat = as.numeric(residuals(fe_fit)))

  resid_pool_by_t <- split(base_fe$ehat[is.finite(base_fe$ehat)], base_fe$t[is.finite(base_fe$ehat)])
  global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]
  if (length(global_pool) < 50L) {
    stop("Residual pool too small after FE calibration (n=", length(global_pool), ").", call. = FALSE)
  }

  sd_global <- stats::sd(global_pool, na.rm = TRUE)
  if (!is.finite(sd_global) || sd_global <= 0) sd_global <- 1.0

  sd_by_id <- base_fe %>%
    group_by(id) %>%
    summarise(sd_e = stats::sd(ehat, na.rm = TRUE), .groups = "drop")
  sd_by_id$sd_e[!is.finite(sd_by_id$sd_e) | sd_by_id$sd_e <= 0] <- sd_global
  sd_map <- setNames(sd_by_id$sd_e, as.character(sd_by_id$id))
  sd_row <- as.numeric(sd_map[as.character(panel$id)])
  sd_row[!is.finite(sd_row) | sd_row <= 0] <- sd_global

  # Standardized residuals and AR(1) estimation
  base_fe <- base_fe %>%
    mutate(
      sd_e = as.numeric(sd_map[as.character(id)]),
      sd_e = if_else(is.finite(sd_e) & sd_e > 0, sd_e, sd_global),
      z = ehat / sd_e
    ) %>%
    filter(is.finite(z))

  std_pool_by_t <- split(base_fe$z, base_fe$t)
  std_global_pool <- base_fe$z[is.finite(base_fe$z)]
  if (length(std_global_pool) < 50L) {
    stop("Standardized residual pool too small (n=", length(std_global_pool), ").", call. = FALSE)
  }

  RESID_POOL_MIN_STATES <- 5L
  rho_used <- 0.6
  sigma_u_used <- sqrt(max(1e-8, 1 - rho_used^2))

  z_pairs <- base_fe %>%
    arrange(id, t) %>%
    group_by(id) %>%
    mutate(z_lag = lag(z)) %>%
    ungroup() %>%
    filter(is.finite(z_lag), is.finite(z))

  if (nrow(z_pairs) >= 20L) {
    rho_fit <- stats::coef(stats::lm(z ~ z_lag - 1, data = z_pairs))[1]
    if (is.finite(rho_fit)) rho_used <- max(-0.99, min(0.99, as.numeric(rho_fit)))
  }
  sigma_u_used <- sqrt(max(1e-8, 1 - rho_used^2))
  log_msg(glue("Residual-pool calibration: rho_used={round(rho_used,3)}, pool_n={length(global_pool)}"))

  # --- error-drawing functions ---
  draw_err_iid_month <- function(tt) {
    vapply(tt, function(tt_i) {
      pool <- resid_pool_by_t[[as.character(tt_i)]]
      if (is.null(pool) || length(pool) < RESID_POOL_MIN_STATES) pool <- global_pool
      sample(pool, size = 1L, replace = TRUE)
    }, FUN.VALUE = 0.0)
  }

  draw_err_ar1_state <- function(tt, idx_list) {
    e_draw <- numeric(length(tt))
    for (id_val in names(idx_list)) {
      idx <- idx_list[[id_val]]
      idx <- idx[order(tt[idx])]
      m <- length(idx)
      if (m <= 0) next

      x <- numeric(m)
      t_seq <- tt[idx]
      pool_first <- std_pool_by_t[[as.character(t_seq[1])]]
      if (is.null(pool_first) || length(pool_first) < RESID_POOL_MIN_STATES) pool_first <- std_global_pool
      x[1] <- sample(pool_first, 1)
      if (m >= 2) {
        for (j in 2:m) {
          pool_curr <- std_pool_by_t[[as.character(t_seq[j])]]
          if (is.null(pool_curr) || length(pool_curr) < RESID_POOL_MIN_STATES) pool_curr <- std_global_pool
          u <- sample(pool_curr, 1)
          x[j] <- rho_used * x[j - 1] + sigma_u_used * u
        }
      }
      e_draw[idx] <- x * sd_row[idx]
    }
    e_draw
  }

  # --- simulation function ---
  crit_t <- function(alpha, df) stats::qt(1 - alpha / 2, df = df)

  simulate_one_selftest <- function(seed) {
    set.seed(seed)

    # Generate null outcome (EFFECT = 0)
    if (SELF_TEST_ERR_MODE == "resid_pool_iid_month") {
      e <- draw_err_iid_month(panel$t)
    } else {
      e <- draw_err_ar1_state(panel$t, idx_by_id)
    }
    y_sim <- panel$yhat + e

    dat <- data.frame(id = panel$id, t = panel$t, g = panel$g, y = y_sim)

    # --- analytic inference ---
    res_analytic <- tryCatch({
      suppressMessages(suppressWarnings({
        mp <- did::att_gt(
          yname = "y", tname = "t", idname = "id", gname = "g",
          xformla = ~1, data = dat, panel = TRUE,
          control_group = CONTROL_GROUP,
          allow_unbalanced_panel = ALLOW_UNBALANCED,
          est_method = EST_METHOD,
          faster_mode = CS_FASTER_MODE,
          bstrap = FALSE, biters = 0, cband = FALSE,
          clustervars = "id"
        )
        ovr <- did::aggte(mp, type = "simple", na.rm = TRUE)
        att_val <- as.numeric(ovr$overall.att)
        se_val <- as.numeric(ovr$overall.se)
        tc <- crit_t(ALPHA, df = n_states - 1L)
        z_val <- att_val / se_val
        list(ok = TRUE, att = att_val, se = se_val, reject = abs(z_val) > tc)
      }))
    }, error = function(e) list(ok = FALSE, att = NA_real_, se = NA_real_, reject = NA))

    # --- bootstrap inference (if requested) ---
    res_bootstrap <- list(ok = FALSE, att = NA_real_, se = NA_real_, reject = NA)
    if (CS_BOOTSTRAP) {
      res_bootstrap <- tryCatch({
        suppressMessages(suppressWarnings({
          mp_b <- did::att_gt(
            yname = "y", tname = "t", idname = "id", gname = "g",
            xformla = ~1, data = dat, panel = TRUE,
            control_group = CONTROL_GROUP,
            allow_unbalanced_panel = ALLOW_UNBALANCED,
            est_method = EST_METHOD,
            faster_mode = CS_FASTER_MODE,
            bstrap = TRUE, biters = CS_BITERS, cband = FALSE,
            clustervars = "id"
          )
          ovr_b <- did::aggte(mp_b, type = "simple", na.rm = TRUE)
          att_b <- as.numeric(ovr_b$overall.att)
          se_b <- as.numeric(ovr_b$overall.se)
          tc <- crit_t(ALPHA, df = n_states - 1L)
          z_b <- att_b / se_b
          list(ok = TRUE, att = att_b, se = se_b, reject = abs(z_b) > tc)
        }))
      }, error = function(e) list(ok = FALSE, att = NA_real_, se = NA_real_, reject = NA))
    }

    list(
      ok_analytic = res_analytic$ok, reject_analytic = res_analytic$reject,
      att_analytic = res_analytic$att, se_analytic = res_analytic$se,
      ok_bootstrap = res_bootstrap$ok, reject_bootstrap = res_bootstrap$reject,
      att_bootstrap = res_bootstrap$att, se_bootstrap = res_bootstrap$se
    )
  }

  set.seed(SEED)
  seeds <- SEED + seq_len(SELF_TEST_N) * 10007L
  log_msg(glue("Running {SELF_TEST_N} self-test simulations (N_CORES={N_CORES})..."))

  st_res <- run_serial_or_parallel(seeds, simulate_one_selftest, cores = N_CORES)

  st_raw <- tibble(
    sim = seq_along(st_res),
    seed = seeds,
    ok_analytic = vapply(st_res, function(x) isTRUE(x$ok_analytic), logical(1)),
    reject_analytic = vapply(st_res, function(x) x$reject_analytic, logical(1)),
    att_analytic = vapply(st_res, function(x) x$att_analytic, numeric(1)),
    se_analytic = vapply(st_res, function(x) x$se_analytic, numeric(1)),
    ok_bootstrap = vapply(st_res, function(x) isTRUE(x$ok_bootstrap), logical(1)),
    reject_bootstrap = vapply(st_res, function(x) x$reject_bootstrap, logical(1)),
    att_bootstrap = vapply(st_res, function(x) x$att_bootstrap, numeric(1)),
    se_bootstrap = vapply(st_res, function(x) x$se_bootstrap, numeric(1))
  )

  safe_write_csv(st_raw, file.path(OUT_DIR, "self_test_raw.csv"))

  # Compute calibration metrics
  ok_a <- st_raw$ok_analytic
  n_ok_a <- sum(ok_a)
  type1_a <- if (n_ok_a > 0) mean(st_raw$reject_analytic[ok_a], na.rm = TRUE) else NA_real_
  mean_se_a <- if (n_ok_a > 0) mean(st_raw$se_analytic[ok_a], na.rm = TRUE) else NA_real_
  sd_est_a <- if (n_ok_a > 1) sd(st_raw$att_analytic[ok_a], na.rm = TRUE) else NA_real_
  se_sd_ratio_a <- if (is.finite(mean_se_a) && is.finite(sd_est_a) && sd_est_a > 0) mean_se_a / sd_est_a else NA_real_

  ok_b <- st_raw$ok_bootstrap
  n_ok_b <- sum(ok_b)
  type1_b <- if (n_ok_b > 0) mean(st_raw$reject_bootstrap[ok_b], na.rm = TRUE) else NA_real_
  mean_se_b <- if (n_ok_b > 0) mean(st_raw$se_bootstrap[ok_b], na.rm = TRUE) else NA_real_
  sd_est_b <- if (n_ok_b > 1) sd(st_raw$att_bootstrap[ok_b], na.rm = TRUE) else NA_real_
  se_sd_ratio_b <- if (is.finite(mean_se_b) && is.finite(sd_est_b) && sd_est_b > 0) mean_se_b / sd_est_b else NA_real_

  st_summary <- tibble(
    err_mode = SELF_TEST_ERR_MODE,
    n_sims = SELF_TEST_N,
    alpha = ALPHA,
    n_ok_analytic = n_ok_a, type1_analytic = type1_a,
    mean_se_analytic = mean_se_a, sd_est_analytic = sd_est_a, se_sd_ratio_analytic = se_sd_ratio_a,
    n_ok_bootstrap = n_ok_b, type1_bootstrap = type1_b,
    mean_se_bootstrap = mean_se_b, sd_est_bootstrap = sd_est_b, se_sd_ratio_bootstrap = se_sd_ratio_b,
    rho_used = rho_used
  )
  safe_write_csv(st_summary, file.path(OUT_DIR, "self_test_summary.csv"))

  log_msg(glue("Self-test: analytic type1={round(type1_a,3)} (n_ok={n_ok_a}), se/sd={round(se_sd_ratio_a,2)}"))
  if (CS_BOOTSTRAP) {
    log_msg(glue("Self-test: bootstrap type1={round(type1_b,3)} (n_ok={n_ok_b}), se/sd={round(se_sd_ratio_b,2)}"))
  }

  # Decision rule
  analytic_unreliable <- is.finite(type1_a) && type1_a < 0.02
  bootstrap_ok <- CS_BOOTSTRAP && is.finite(type1_b) && type1_b >= 0.02 && type1_b <= 0.10

  if (analytic_unreliable) {
    HEADLINE_METHOD <- "bootstrap"
    log_msg("WARNING: Analytic CS inference unreliable (type1 < 2%). Defaulting headline to BOOTSTRAP.")
    if (!bootstrap_ok) {
      log_msg("WARNING: Bootstrap inference also appears miscalibrated. Proceed with caution.")
    }
  } else {
    HEADLINE_METHOD <- "analytic"
    log_msg("Self-test: analytic SEs appear well-calibrated. Headline method = ANALYTIC.")
  }

  self_test_results <- st_summary
}

log_msg(glue("Headline CS inference method: {HEADLINE_METHOD}"))

################################################################################
# SECTION 5: CS-DiD PRETRENDS (Analysis A)
################################################################################

run_cs_pretrends <- function(panel_df, bstrap, biters, label) {
  log_msg(glue("Running CS-DiD pretrends ({label})..."))

  dat <- data.frame(
    id = panel_df$id,
    t  = panel_df$t,
    g  = panel_df$g,
    y  = panel_df$y
  )

  mp <- tryCatch({
    suppressMessages(suppressWarnings({
      did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        xformla = ~1, data = dat, panel = TRUE,
        control_group = CONTROL_GROUP,
        allow_unbalanced_panel = ALLOW_UNBALANCED,
        est_method = EST_METHOD,
        faster_mode = CS_FASTER_MODE,
        bstrap = bstrap,
        biters = biters,
        cband = TRUE,
        clustervars = "id"
      )
    }))
  }, error = function(e) {
    log_msg(glue("  ERROR in att_gt() ({label}): {conditionMessage(e)}"))
    return(NULL)
  })

  if (is.null(mp)) return(NULL)

  dyn <- tryCatch({
    did::aggte(mp, type = "dynamic", na.rm = TRUE)
  }, error = function(e) {
    log_msg(glue("  ERROR in aggte(dynamic) ({label}): {conditionMessage(e)}"))
    return(NULL)
  })

  if (is.null(dyn)) return(NULL)

  n_cl <- n_distinct(panel_df$id)

  es <- tibble(
    egt       = as.integer(dyn$egt),
    att       = as.numeric(dyn$att.egt),
    se        = as.numeric(dyn$se.egt),
    crit_val  = as.numeric(dyn$crit.val.egt),
    method    = label
  ) %>%
    mutate(
      t_stat = ifelse(is.finite(att) & is.finite(se) & se > 0, att / se, NA_real_),
      p_value_ptwise = ifelse(
        is.finite(t_stat),
        2 * pt(-abs(t_stat), df = n_cl - 1),
        NA_real_
      ),
      ci_lo = att - qnorm(1 - ALPHA / 2) * se,
      ci_hi = att + qnorm(1 - ALPHA / 2) * se
    )

  # Pre-trend joint test: Holm-adjusted max-|t|
  pre <- es %>% filter(egt %in% PRE_WINDOW, is.finite(t_stat))
  if (nrow(pre) > 0) {
    raw_p <- pre$p_value_ptwise
    holm_p <- p.adjust(raw_p, method = "holm")
    joint_reject <- any(holm_p < ALPHA)
    joint_min_holm_p <- min(holm_p)
    max_abs_t <- max(abs(pre$t_stat))
  } else {
    joint_reject <- NA
    joint_min_holm_p <- NA_real_
    max_abs_t <- NA_real_
  }

  # Overall ATT
  ovr <- tryCatch({
    did::aggte(mp, type = "simple", na.rm = TRUE)
  }, error = function(e) NULL)

  overall_att <- if (!is.null(ovr)) as.numeric(ovr$overall.att) else NA_real_
  overall_se  <- if (!is.null(ovr)) as.numeric(ovr$overall.se)  else NA_real_

  log_msg(glue("  {label}: {nrow(pre)} pre-periods, joint_reject={joint_reject}, min_holm_p={round(joint_min_holm_p,4)}, overall_att={round(overall_att,4)}"))

  list(
    event_study = es,
    n_pre = nrow(pre),
    joint_reject = joint_reject,
    joint_min_holm_p = joint_min_holm_p,
    max_abs_t = max_abs_t,
    overall_att = overall_att,
    overall_se = overall_se,
    n_clusters = n_cl,
    n_obs = nrow(panel_df),
    mp = mp,
    dyn = dyn
  )
}

cs_analytic_res  <- NULL
cs_bootstrap_res <- NULL

if (CS_ANALYTIC) {
  cs_analytic_res <- run_cs_pretrends(panel, bstrap = FALSE, biters = 0, label = "analytic")
  if (!is.null(cs_analytic_res)) {
    safe_write_csv(cs_analytic_res$event_study, file.path(OUT_DIR, "event_study_cs_analytic.csv"))
  }
}

if (CS_BOOTSTRAP) {
  cs_bootstrap_res <- run_cs_pretrends(panel, bstrap = TRUE, biters = CS_BITERS, label = "bootstrap")
  if (!is.null(cs_bootstrap_res)) {
    safe_write_csv(cs_bootstrap_res$event_study, file.path(OUT_DIR, "event_study_cs_bootstrap.csv"))
  }
}

################################################################################
# SECTION 6: TWFE / SUN-ABRAHAM PRETRENDS (Analysis B)
################################################################################

log_msg("Running TWFE/Sun-Abraham pretrends...")

sa_result <- NULL
sa_mod <- tryCatch({
  fixest::feols(y ~ sunab(g, t) | id + t, data = panel, cluster = ~id)
}, error = function(e) {
  log_msg(glue("ERROR in Sun-Abraham model: {conditionMessage(e)}"))
  NULL
})

if (!is.null(sa_mod)) {
  sa_coefs <- coef(sa_mod)
  sa_ses <- se(sa_mod)
  coef_names <- names(sa_coefs)

  # Parse event times from coefficient names (sunab names: "t::VALUE")
  sunab_mask <- grepl("::", coef_names)
  sunab_names <- coef_names[sunab_mask]

  extract_event_time <- function(name) {
    parts <- strsplit(name, "::", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      return(suppressWarnings(as.integer(parts[length(parts)])))
    }
    NA_integer_
  }

  event_times <- vapply(sunab_names, extract_event_time, integer(1))

  sa_es <- tibble(
    egt = event_times,
    att = as.numeric(sa_coefs[sunab_names]),
    se  = as.numeric(sa_ses[sunab_names]),
    coef_name = sunab_names,
    method = "TWFE_SunAb"
  ) %>%
    filter(!is.na(egt)) %>%
    mutate(
      t_stat = ifelse(is.finite(att) & is.finite(se) & se > 0, att / se, NA_real_),
      # For clustered inference, use a cluster-based df approximation.
      p_value = ifelse(
        is.finite(t_stat),
        2 * pt(-abs(t_stat), df = max(1, n_states - 1L)),
        NA_real_
      ),
      ci_lo = att - qnorm(1 - ALPHA / 2) * se,
      ci_hi = att + qnorm(1 - ALPHA / 2) * se
    ) %>%
    arrange(egt)

  # Add reference period (event_time = -1)
  if (!(-1L %in% sa_es$egt)) {
    sa_es <- bind_rows(
      sa_es,
      tibble(egt = -1L, att = 0, se = 0, coef_name = "Reference",
             method = "TWFE_SunAb", t_stat = NA_real_, p_value = NA_real_,
             ci_lo = 0, ci_hi = 0)
    ) %>%
      arrange(egt)
  }

  # Joint pre-trend test (SunAb): Holm step-down over pointwise p-values.
  # This avoids fixest::wald(keep=...) matching many underlying cohort-expanded
  # terms that aren't what we plot/report here.
  pre_sa <- sa_es %>% filter(egt %in% PRE_WINDOW, is.finite(p_value))
  if (nrow(pre_sa) > 0) {
    holm_p <- p.adjust(pre_sa$p_value, method = "holm")
    joint_reject_sa <- any(holm_p < ALPHA)
    joint_min_holm_p <- min(holm_p)
    max_abs_t_sa <- max(abs(pre_sa$t_stat), na.rm = TRUE)
  } else {
    joint_reject_sa <- NA
    joint_min_holm_p <- NA_real_
    max_abs_t_sa <- NA_real_
  }

  log_msg(glue(
    "  SunAb: {nrow(pre_sa)} pre-periods, joint_reject={joint_reject_sa}, min_holm_p={round(joint_min_holm_p,4)}"
  ))

  sa_result <- list(
    model = sa_mod,
    event_study = sa_es,
    joint_reject = joint_reject_sa,
    joint_min_holm_p = joint_min_holm_p,
    max_abs_t = max_abs_t_sa,
    n_clusters = n_states,
    n_obs = nrow(panel)
  )

  safe_write_csv(sa_es %>% select(-coef_name), file.path(OUT_DIR, "event_study_twfe_sunab.csv"))
}

################################################################################
# SECTION 7: GAMBLING INTENSITY ADD-ON (Analysis C, optional)
################################################################################

gambling_result <- NULL

if (nzchar(GAMBLING_FILE) && file.exists(GAMBLING_FILE)) {
  log_msg(glue("Running gambling intensity diagnostics (file: {GAMBLING_FILE})..."))

  gamb <- readr::read_csv(GAMBLING_FILE, show_col_types = FALSE) %>%
    mutate(
      state_abb = state_name_to_abb(State),
      month_date = as.Date(month_date),
      gambling_amount = as.numeric(.data[[GAMBLING_AMOUNT_COL]])
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date), !is.na(gambling_amount))

  n_gamb_states <- n_distinct(gamb$state_abb)
  n_matched <- sum(unique(gamb$state_abb) %in% unique(panel$state_abb))
  log_msg(glue("  Gambling data: {nrow(gamb)} rows, {n_gamb_states} states, {n_matched} matched to panel"))

  if (n_matched == 0) {
    stop("Gambling merge: zero states matched panel. Check state name crosswalk.", call. = FALSE)
  }

  panel_gamb <- panel %>%
    left_join(
      gamb %>% select(state_abb, month_date, gambling_amount),
      by = c("state_abb", "month_date")
    ) %>%
    mutate(log1p_gambling = log1p(pmax(gambling_amount, 0, na.rm = TRUE)))

  n_with_gamb <- sum(!is.na(panel_gamb$gambling_amount))
  log_msg(glue("  Panel rows with gambling data: {n_with_gamb} / {nrow(panel_gamb)}"))

  # Intensity bins: pre-period average handle for treated states
  pre_avg <- panel_gamb %>%
    filter(g > 0L, t < g, !is.na(gambling_amount)) %>%
    group_by(state_abb) %>%
    summarise(pre_avg_handle = mean(gambling_amount, na.rm = TRUE), .groups = "drop")

  if (nrow(pre_avg) >= 6) {
    pre_avg <- pre_avg %>%
      mutate(intensity_bin = cut(
        pre_avg_handle,
        breaks = quantile(pre_avg_handle, c(0, 1/3, 2/3, 1), na.rm = TRUE),
        include.lowest = TRUE,
        labels = c("Low", "Medium", "High")
      ))

    panel_het <- panel_gamb %>%
      inner_join(pre_avg %>% select(state_abb, intensity_bin), by = "state_abb") %>%
      filter(!is.na(intensity_bin)) %>%
      mutate(intensity_bin = as.factor(intensity_bin))

    log_msg(glue("  Intensity bins: {nrow(pre_avg)} states (Low={sum(pre_avg$intensity_bin=='Low')}, Med={sum(pre_avg$intensity_bin=='Medium')}, High={sum(pre_avg$intensity_bin=='High')})"))

    # Heterogeneous SunAb
    het_mod <- tryCatch({
      fixest::feols(
        y ~ sunab(g, t) : intensity_bin | id + t,
        data = panel_het,
        cluster = ~id
      )
    }, error = function(e) {
      log_msg(glue("  WARNING: Heterogeneous SunAb failed: {conditionMessage(e)}"))
      NULL
    })

    gambling_result <- list(
      pre_avg = pre_avg,
      het_model = het_mod,
      panel_het = panel_het
    )

    safe_write_csv(pre_avg, file.path(OUT_DIR, "gambling_intensity_summary.csv"))
  } else {
    log_msg(glue("  WARNING: Only {nrow(pre_avg)} states have pre-period gambling data. Skipping intensity analysis (need >= 6)."))
  }

} else if (nzchar(GAMBLING_FILE)) {
  log_msg(glue("WARNING: GAMBLING_FILE specified but not found: {GAMBLING_FILE}"))
}

################################################################################
# SECTION 8: PLOTS
################################################################################

log_msg("Generating plots...")

# Build a sample-description label for plot subtitles
sample_label <- glue("{format(min(panel$month_date), '%b %Y')}\u2013{format(max(panel$month_date), '%b %Y')}")
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  sample_label <- glue("{sample_label}, excl. {format(DROP_START, '%b %Y')}\u2013{format(DROP_END, '%b %Y')}")
}

base_theme <- theme_minimal(base_size = 12)
zero_line <- geom_hline(yintercept = 0, linetype = "dashed", color = "red", linewidth = 0.5)
treat_line <- geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40", linewidth = 0.5)

make_es_plot <- function(es_df, title, subtitle = "", color = "steelblue") {
  if (is.null(es_df) || nrow(es_df) == 0) return(NULL)

  es_plot <- es_df %>%
    filter(is.finite(att), is.finite(se), se > 0) %>%
    ggplot(aes(x = egt, y = att)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = color) +
    geom_point(size = 2, color = color) +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, color = color) +
    zero_line + treat_line +
    base_theme +
    labs(
      title = title,
      subtitle = subtitle,
      x = "Event Time (months relative to treatment)",
      y = "ATT Estimate"
    )

  # Shade pre-window
  pre_range <- range(PRE_WINDOW)
  es_plot <- es_plot +
    annotate("rect",
             xmin = pre_range[1] - 0.5, xmax = pre_range[2] + 0.5,
             ymin = -Inf, ymax = Inf,
             alpha = 0.05, fill = "orange")

  es_plot
}

# Plot 1: CS analytic event study
if (!is.null(cs_analytic_res)) {
  p1 <- make_es_plot(
    cs_analytic_res$event_study,
    "CS-DiD Event Study (Analytic SEs)",
    glue("Pre-trend Holm p = {round(cs_analytic_res$joint_min_holm_p, 4)} | {cs_analytic_res$n_clusters} clusters, {cs_analytic_res$n_obs} obs | {sample_label}")
  )
  if (!is.null(p1)) ggsave(file.path(OUT_DIR, "cs_event_study_analytic.png"), p1, width = 10, height = 6, dpi = 300)
}

# Plot 2: CS bootstrap event study
if (!is.null(cs_bootstrap_res)) {
  p2 <- make_es_plot(
    cs_bootstrap_res$event_study,
    "CS-DiD Event Study (Bootstrap SEs)",
    glue("Pre-trend Holm p = {round(cs_bootstrap_res$joint_min_holm_p, 4)} | biters={CS_BITERS} | {cs_bootstrap_res$n_clusters} clusters | {sample_label}"),
    color = "darkgreen"
  )
  if (!is.null(p2)) ggsave(file.path(OUT_DIR, "cs_event_study_bootstrap.png"), p2, width = 10, height = 6, dpi = 300)
}

# Plot 3: CS analytic vs bootstrap comparison
if (!is.null(cs_analytic_res) && !is.null(cs_bootstrap_res)) {
  combined_cs <- bind_rows(
    cs_analytic_res$event_study %>% mutate(method = "Analytic"),
    cs_bootstrap_res$event_study %>% mutate(method = "Bootstrap")
  ) %>%
    filter(is.finite(att), is.finite(se), se > 0)

  if (nrow(combined_cs) > 0) {
    p3 <- ggplot(combined_cs, aes(x = egt, y = att, color = method, fill = method)) +
      geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15) +
      geom_point(size = 2, position = position_dodge(width = 0.3)) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, position = position_dodge(width = 0.3)) +
      zero_line + treat_line + base_theme +
      scale_color_manual(values = c("Analytic" = "steelblue", "Bootstrap" = "darkgreen")) +
      scale_fill_manual(values = c("Analytic" = "steelblue", "Bootstrap" = "darkgreen")) +
      labs(
        title = "CS-DiD: Analytic vs Bootstrap SEs",
        subtitle = glue("Headline method: {toupper(HEADLINE_METHOD)} | {sample_label}"),
        x = "Event Time (months)", y = "ATT Estimate", color = "Inference", fill = "Inference"
      )
    ggsave(file.path(OUT_DIR, "cs_analytic_vs_bootstrap.png"), p3, width = 10, height = 6, dpi = 300)
  }
}

# Plot 4: TWFE/SunAb event study
if (!is.null(sa_result)) {
  sa_subtitle <- glue("Pre-trend Holm p = {round(sa_result$joint_min_holm_p, 4)} | {sa_result$n_clusters} clusters | {sample_label}")
  p4 <- make_es_plot(sa_result$event_study, "Sun-Abraham Event Study (TWFE)", sa_subtitle, color = "darkorange")
  if (!is.null(p4)) ggsave(file.path(OUT_DIR, "twfe_sunab_event_study.png"), p4, width = 10, height = 6, dpi = 300)
}

# Plot 5: CS vs TWFE comparison
headline_cs <- if (HEADLINE_METHOD == "bootstrap" && !is.null(cs_bootstrap_res)) {
  cs_bootstrap_res$event_study %>% mutate(method = "CS-DiD (Bootstrap)")
} else if (!is.null(cs_analytic_res)) {
  cs_analytic_res$event_study %>% mutate(method = "CS-DiD (Analytic)")
} else {
  NULL
}

if (!is.null(headline_cs) && !is.null(sa_result)) {
  combined_all <- bind_rows(
    headline_cs %>% select(egt, att, se, ci_lo, ci_hi, method),
    sa_result$event_study %>% mutate(method = "Sun-Abraham (TWFE)") %>% select(egt, att, se, ci_lo, ci_hi, method)
  ) %>%
    filter(is.finite(att), is.finite(se), se > 0)

  if (nrow(combined_all) > 0) {
    p5 <- ggplot(combined_all, aes(x = egt, y = att, color = method)) +
      geom_point(size = 2, position = position_dodge(width = 0.3)) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, position = position_dodge(width = 0.3)) +
      zero_line + treat_line + base_theme +
      scale_color_manual(values = c(
        "CS-DiD (Analytic)" = "steelblue", "CS-DiD (Bootstrap)" = "darkgreen",
        "Sun-Abraham (TWFE)" = "darkorange"
      )) +
      labs(
        title = "CS-DiD vs Sun-Abraham Comparison",
        subtitle = glue("CS headline: {HEADLINE_METHOD} | {sample_label}"),
        x = "Event Time (months)", y = "ATT Estimate", color = "Method"
      )
    ggsave(file.path(OUT_DIR, "cs_vs_twfe_comparison.png"), p5, width = 10, height = 6, dpi = 300)
  }
}

# Plot 6: Gambling heterogeneity (conditional)
if (!is.null(gambling_result) && !is.null(gambling_result$het_model)) {
  het_mod <- gambling_result$het_model
  het_coefs <- coef(het_mod)
  het_ses <- se(het_mod)
  het_names <- names(het_coefs)

  # Parse: coefficient names have format like "t::-5:intensity_binLow"
  extract_egt <- function(nm) {
    m <- regexec("::(-?[0-9]+)", nm)
    r <- regmatches(nm, m)
    suppressWarnings(as.integer(vapply(r, function(x) if (length(x) >= 2) x[2] else NA_character_, character(1))))
  }
  extract_bin <- function(nm) {
    m <- regexec("(Low|Medium|High)", nm)
    r <- regmatches(nm, m)
    vapply(r, function(x) if (length(x) >= 1) x[1] else NA_character_, character(1))
  }

  het_df <- tibble(coef_name = het_names, att = as.numeric(het_coefs), se = as.numeric(het_ses)) %>%
    mutate(
      egt = extract_egt(coef_name),
      intensity_bin = extract_bin(coef_name),
      ci_lo = att - qnorm(1 - ALPHA / 2) * se,
      ci_hi = att + qnorm(1 - ALPHA / 2) * se
    ) %>%
    filter(!is.na(egt), !is.na(intensity_bin))

  if (nrow(het_df) > 0) {
    p6 <- ggplot(het_df, aes(x = egt, y = att, color = intensity_bin)) +
      geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi, fill = intensity_bin), alpha = 0.1) +
      geom_point(size = 1.5, position = position_dodge(width = 0.3)) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, position = position_dodge(width = 0.3)) +
      zero_line + treat_line + base_theme +
      scale_color_brewer(palette = "Set1") +
      scale_fill_brewer(palette = "Set1") +
      labs(
        title = "Gambling Intensity Heterogeneity (Sun-Abraham)",
        subtitle = glue("Handle terciles | Col = {GAMBLING_AMOUNT_COL} (NOT per-capita)"),
        x = "Event Time (months)", y = "ATT Estimate",
        color = "Intensity", fill = "Intensity"
      )
    ggsave(file.path(OUT_DIR, "gambling_heterogeneity.png"), p6, width = 10, height = 6, dpi = 300)
  }
}

################################################################################
# SECTION 9: OUTPUT ASSEMBLY
################################################################################

log_msg("Assembling outputs...")

# --- pretrends_summary.csv ---
summary_rows <- list()

if (!is.null(cs_analytic_res)) {
  pre_a <- cs_analytic_res$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att))
  summary_rows[["CS_analytic"]] <- tibble(
    method = "CS_analytic",
    n_states = cs_analytic_res$n_clusters,
    n_obs = cs_analytic_res$n_obs,
    n_pre_periods = cs_analytic_res$n_pre,
    joint_test_type = "holm",
    joint_test_stat = cs_analytic_res$max_abs_t,
    joint_test_p = cs_analytic_res$joint_min_holm_p,
    joint_reject = cs_analytic_res$joint_reject,
    max_abs_pre_att = if (nrow(pre_a) > 0) max(abs(pre_a$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_a) > 0) mean(abs(pre_a$att)) else NA_real_,
    overall_att = cs_analytic_res$overall_att,
    overall_se = cs_analytic_res$overall_se,
    headline = (HEADLINE_METHOD == "analytic")
  )
}

if (!is.null(cs_bootstrap_res)) {
  pre_b <- cs_bootstrap_res$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att))
  summary_rows[["CS_bootstrap"]] <- tibble(
    method = "CS_bootstrap",
    n_states = cs_bootstrap_res$n_clusters,
    n_obs = cs_bootstrap_res$n_obs,
    n_pre_periods = cs_bootstrap_res$n_pre,
    joint_test_type = "holm",
    joint_test_stat = cs_bootstrap_res$max_abs_t,
    joint_test_p = cs_bootstrap_res$joint_min_holm_p,
    joint_reject = cs_bootstrap_res$joint_reject,
    max_abs_pre_att = if (nrow(pre_b) > 0) max(abs(pre_b$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_b) > 0) mean(abs(pre_b$att)) else NA_real_,
    overall_att = cs_bootstrap_res$overall_att,
    overall_se = cs_bootstrap_res$overall_se,
    headline = (HEADLINE_METHOD == "bootstrap")
  )
}

if (!is.null(sa_result)) {
  pre_sa <- sa_result$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att), se > 0)
  summary_rows[["TWFE_SunAb"]] <- tibble(
    method = "TWFE_SunAb",
    n_states = sa_result$n_clusters,
    n_obs = sa_result$n_obs,
    n_pre_periods = nrow(pre_sa),
    joint_test_type = "holm",
    joint_test_stat = sa_result$max_abs_t,
    joint_test_p = sa_result$joint_min_holm_p,
    joint_reject = sa_result$joint_reject,
    max_abs_pre_att = if (nrow(pre_sa) > 0) max(abs(pre_sa$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_sa) > 0) mean(abs(pre_sa$att)) else NA_real_,
    overall_att = NA_real_,
    overall_se = NA_real_,
    headline = TRUE
  )
}

if (length(summary_rows) > 0) {
  pretrends_summary <- bind_rows(summary_rows)
  safe_write_csv(pretrends_summary, file.path(OUT_DIR, "pretrends_summary.csv"))
}

# --- README.md ---
readme_lines <- c(
  "# Pre-trends Diagnostics Output",
  "",
  glue("Generated: {Sys.time()}"),
  "",
  "## Configuration",
  glue("- Panel: `{PANEL_FILE}`"),
  glue("- Excluded states: {paste(EXCLUDE_STATES, collapse=', ')}"),
  glue("- Date range: {MIN_DATE} to {MAX_DATE}"),
  glue("- Dropped window: {fmt_date(DROP_START)} to {fmt_date(DROP_END)}"),
  glue("- Coverage threshold: {COVERAGE_THRESHOLD}"),
  glue("- Balance common months: {BALANCE_COMMON_MONTHS}"),
  glue("- Outcome: {OUTCOME}"),
  glue("- Control group: {CONTROL_GROUP}, est_method: {EST_METHOD}"),
  glue("- Allow unbalanced panel: {ALLOW_UNBALANCED}"),
  glue("- Pre-window: {paste(range(PRE_WINDOW), collapse=' to ')}"),
  glue("- Alpha: {ALPHA}"),
  "",
  "## Panel Summary",
  glue("- {n_states} states ({n_treated} treated, {n_never} never-treated)"),
  glue("- {n_cohorts} treatment cohorts"),
  glue("- {n_t} months, {nrow(panel)} observations"),
  "",
  "## Headline CS Inference Method",
  glue("**{toupper(HEADLINE_METHOD)}**"),
  ""
)

if (SELF_TEST && !is.null(self_test_results)) {
  readme_lines <- c(readme_lines,
    "## Self-Test Calibration Results",
    glue("- Error mode: {SELF_TEST_ERR_MODE}"),
    glue("- Simulations: {SELF_TEST_N}"),
    glue("- Analytic: type1 = {round(self_test_results$type1_analytic, 3)}, SE/SD ratio = {round(self_test_results$se_sd_ratio_analytic, 2)}"),
    ""
  )
  if (CS_BOOTSTRAP) {
    readme_lines <- c(readme_lines,
      glue("- Bootstrap: type1 = {round(self_test_results$type1_bootstrap, 3)}, SE/SD ratio = {round(self_test_results$se_sd_ratio_bootstrap, 2)}"),
      ""
    )
  }
  if (is.finite(self_test_results$type1_analytic) && self_test_results$type1_analytic < 0.02) {
    readme_lines <- c(readme_lines,
      "**WARNING**: Analytic CS SEs appear inflated (type1 < 2% under null). Bootstrap is used as headline.",
      ""
    )
  }
}

if (!is.null(cs_analytic_res)) {
  readme_lines <- c(readme_lines,
    "## CS-DiD Pretrends (Analytic)",
    glue("- Pre-periods tested: {cs_analytic_res$n_pre}"),
    glue("- Joint test (Holm): min_p = {round(cs_analytic_res$joint_min_holm_p, 4)}, reject = {cs_analytic_res$joint_reject}"),
    glue("- Overall ATT: {round(cs_analytic_res$overall_att, 4)} (SE = {round(cs_analytic_res$overall_se, 4)})"),
    ""
  )
}

if (!is.null(cs_bootstrap_res)) {
  readme_lines <- c(readme_lines,
    "## CS-DiD Pretrends (Bootstrap)",
    glue("- Pre-periods tested: {cs_bootstrap_res$n_pre}"),
    glue("- Joint test (Holm): min_p = {round(cs_bootstrap_res$joint_min_holm_p, 4)}, reject = {cs_bootstrap_res$joint_reject}"),
    glue("- Overall ATT: {round(cs_bootstrap_res$overall_att, 4)} (SE = {round(cs_bootstrap_res$overall_se, 4)})"),
    glue("- Bootstrap iterations: {CS_BITERS}"),
    ""
  )
}

if (!is.null(sa_result)) {
  readme_lines <- c(readme_lines,
    "## TWFE / Sun-Abraham Pretrends",
    glue("- Joint test (Holm): min_p = {round(sa_result$joint_min_holm_p, 4)}, reject = {sa_result$joint_reject}"),
    ""
  )
}

if (!is.null(gambling_result)) {
  readme_lines <- c(readme_lines,
    "## Gambling Intensity Diagnostics",
    glue("- Source: `{GAMBLING_FILE}`"),
    glue("- Amount column: {GAMBLING_AMOUNT_COL} (raw dollars wagered, NOT per-capita)"),
    glue("- States with pre-period data: {nrow(gambling_result$pre_avg)}"),
    "- Intensity bins: terciles of pre-period average handle",
    "- **Limitation**: Gambling data starts Sept 2021. Pre-period handle is only available for later adopters.",
    ""
  )
}

readme_lines <- c(readme_lines,
  "## Inference Notes",
  "- CS p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test",
  "- SunAb p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test",
  "- CS p-values are NOT computed via TWFE Wald test (explicitly avoided)",
  "",
  "## How to Run",
  "```bash",
  "# Quick (no self-test, no gambling)",
  "bash scripts/run_pretrends_statepanel.sh",
  "",
  "# With gambling intensity",
  "GAMBLING_FILE=data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv \\",
  "  bash scripts/run_pretrends_statepanel.sh",
  "",
  "# With self-test calibration (slow)",
  "SELF_TEST=TRUE N_CORES=4 bash scripts/run_pretrends_statepanel.sh",
  "```",
  ""
)

writeLines(readme_lines, file.path(OUT_DIR, "README.md"))

log_msg("=== Done ===")
log_msg(glue("Output directory: {OUT_DIR}"))

# List outputs
output_files <- list.files(OUT_DIR, full.names = FALSE)
for (f in output_files) {
  log_msg(glue("  - {f}"))
}
