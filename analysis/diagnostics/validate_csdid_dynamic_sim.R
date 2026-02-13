#!/usr/bin/env Rscript
################################################################################
# validate_csdid_dynamic_sim.R
#
# Goal: Validate that a CS-DiD workflow can (a) recover a known dynamic treatment
# effect pattern and (b) deliver roughly calibrated SEs (Type I error ~ alpha)
# BEFORE running on observed outcomes.
#
# Key idea:
# - Use the real staggered adoption design (state-month + treatment timing),
#   but simulate outcomes from a known DGP with optional dynamic effects.
# - Re-estimate did::att_gt() and did::aggte(type="dynamic") on each draw.
#
# This avoids "shift-the-statistic" shortcuts (estimate once at effect=0, then
# add a constant to ATT), which cannot validate dynamic behavior.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(fixest)
  library(did)
  library(parallel)
})

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

true_effect_fn <- function(event_time, effect_log, shape = "step", ramp_months = 6L, delay_months = 0L) {
  shape <- tolower(trimws(shape))
  et <- as.integer(event_time)
  out <- rep(0.0, length(et))

  post <- is.finite(et) & (et >= delay_months)
  if (!any(post)) return(out)

  if (shape == "step") {
    out[post] <- effect_log
    return(out)
  }

  if (shape == "ramp") {
    rm <- as.integer(max(1L, ramp_months))
    k <- pmin(pmax(et[post] - delay_months, 0L), rm)
    out[post] <- effect_log * (k / rm)
    return(out)
  }

  if (shape == "delayed") {
    out[post] <- effect_log
    return(out)
  }

  stop("Unknown EFFECT_SHAPE: ", shape, call. = FALSE)
}

# ------------------------------ configuration ---------------------------------

PANEL_FILE <- getenv1("PANEL_FILE", "data/raw/state_month_panel_with_treatment.csv")
OUT_DIR <- getenv1("OUT_DIR", "output/csdid_dynamic_validation_sim")

SEED <- parse_int(getenv1("SEED", "123"), 123L)
N_SIMS <- parse_int(getenv1("N_SIMS", "200"), 200L)
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
TARGET_H <- parse_int(getenv1("TARGET_H", "0"), 0L)

EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"), character())
MIN_DATE <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
# If unset, we auto-pick max feasible coverage to get a balanced panel by default.
COVERAGE_THRESHOLD_RAW <- getenv1("COVERAGE_THRESHOLD", "")
COVERAGE_THRESHOLD <- if (nzchar(COVERAGE_THRESHOLD_RAW)) {
  parse_int(COVERAGE_THRESHOLD_RAW, 0L)
} else {
  NA_integer_
}
BALANCE_COMMON_MONTHS <- parse_bool(getenv1("BALANCE_COMMON_MONTHS", "TRUE"), TRUE)

EFFECT_LOG <- parse_num(getenv1("EFFECT_LOG", "0.0"), 0.0) # set 0.0 for null calibration
EFFECT_SHAPE <- getenv1("EFFECT_SHAPE", "step")            # step | ramp | delayed
RAMP_MONTHS <- parse_int(getenv1("RAMP_MONTHS", "6"), 6L)
DELAY_MONTHS <- parse_int(getenv1("DELAY_MONTHS", "0"), 0L)

OUTCOME <- getenv1("OUTCOME", "log1p_filings_count")          # log1p_filings_count | log1p_rate
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

# ar1_state | iid | resid_pool_iid_month | resid_pool_ar1_state
ERR_MODE <- tolower(trimws(getenv1("ERR_MODE", "ar1_state")))
RESID_POOL_MIN_STATES <- parse_int(getenv1("RESID_POOL_MIN_STATES", "5"), 5L)
RHO <- parse_num(getenv1("RHO", "0.6"), 0.6)
SIGMA_E <- parse_num(getenv1("SIGMA_E", "1.0"), 1.0)
SIGMA_A <- parse_num(getenv1("SIGMA_A", "1.0"), 1.0)
SIGMA_G <- parse_num(getenv1("SIGMA_G", "1.0"), 1.0)

# NOTE: the state-month skeleton is typically unbalanced; default to TRUE so the
# validation harness runs out-of-the-box.
DID_ALLOW_UNBALANCED <- parse_bool(getenv1("DID_ALLOW_UNBALANCED_PANEL", "TRUE"), TRUE)
DID_FASTER_MODE <- parse_bool(getenv1("DID_FASTER_MODE", "TRUE"), TRUE)
DID_BSTRAP <- parse_bool(getenv1("DID_BSTRAP", "FALSE"), FALSE)
DID_BITERS <- parse_int(getenv1("DID_BITERS", "199"), 199L)

req_cores <- parse_int(getenv1("N_CORES", ""), NA_integer_)
if (!is.finite(req_cores) || req_cores < 1L) req_cores <- 1L
N_CORES <- max(1L, req_cores)

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("CS-DiD dynamic validation sim\n")
cat("PANEL_FILE:", PANEL_FILE, "\n")
cat("OUT_DIR:", OUT_DIR, "\n")
cat("N_SIMS:", N_SIMS, "ALPHA:", ALPHA, "SEED:", SEED, "\n")
cat("TARGET_H:", TARGET_H, "\n")
cat("MIN_DATE:", as.character(MIN_DATE), "\n")
cat("MAX_DATE:", as.character(MAX_DATE), "\n")
cat("EXCLUDE_STATES:", ifelse(length(EXCLUDE_STATES) > 0, paste(EXCLUDE_STATES, collapse = ","), "none"), "\n")
cat("COVERAGE_THRESHOLD (requested):", ifelse(is.finite(COVERAGE_THRESHOLD), COVERAGE_THRESHOLD, NA), "\n")
cat("BALANCE_COMMON_MONTHS:", BALANCE_COMMON_MONTHS, "\n")
cat("EFFECT_LOG:", EFFECT_LOG, "EFFECT_SHAPE:", EFFECT_SHAPE, "RAMP_MONTHS:", RAMP_MONTHS, "DELAY_MONTHS:", DELAY_MONTHS, "\n")
cat("OUTCOME:", OUTCOME, "RATE_EPS:", RATE_EPS, "\n")
cat("ERR_MODE:", ERR_MODE, "RHO:", RHO, "SIGMA_E:", SIGMA_E, "SIGMA_A:", SIGMA_A, "SIGMA_G:", SIGMA_G, "\n")
cat("RESID_POOL_MIN_STATES:", RESID_POOL_MIN_STATES, "\n")
cat("DID_ALLOW_UNBALANCED_PANEL:", DID_ALLOW_UNBALANCED, "\n")
cat("DID_FASTER_MODE:", DID_FASTER_MODE, "DID_BSTRAP:", DID_BSTRAP, "DID_BITERS:", DID_BITERS, "\n")
cat("N_CORES:", N_CORES, "\n\n")

if (!file.exists(PANEL_FILE)) stop("PANEL_FILE not found: ", PANEL_FILE, call. = FALSE)

# ------------------------------ panel skeleton --------------------------------

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

coverage <- panel0 %>%
  count(state_abb, name = "n_months") %>%
  arrange(desc(n_months), state_abb)

max_coverage <- if (nrow(coverage) > 0) max(coverage$n_months, na.rm = TRUE) else NA_integer_
if (!is.finite(COVERAGE_THRESHOLD)) {
  COVERAGE_THRESHOLD <- max_coverage
}

cat("COVERAGE_THRESHOLD (used):", COVERAGE_THRESHOLD, " (max_coverage=", max_coverage, ")\n", sep = "")

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
    y_obs = dplyr::case_when(
      OUTCOME == "log1p_filings_count" ~ log1p(pmax(filings_count, 0)),
      OUTCOME == "log1p_rate" ~ log(pmax(filings_per_1k_renters, 0) + RATE_EPS),
      TRUE ~ NA_real_
    )
  )

if (!OUTCOME %in% c("log1p_filings_count", "log1p_rate")) {
  stop("Unknown OUTCOME: ", OUTCOME, call. = FALSE)
}

n_states <- n_distinct(panel$id)
t_vals <- sort(unique(panel$t))
n_t <- length(t_vals)

if (n_states < 8L) stop("Too few states after filtering; n_states=", n_states, call. = FALSE)

idx_by_id <- split(seq_len(nrow(panel)), panel$id)
t_index <- match(panel$t, t_vals)

# ------------------------------ simulation core -------------------------------

crit_t <- function(alpha, df) stats::qt(1 - alpha / 2, df = df)

resid_pool_active <- ERR_MODE %in% c("resid_pool_iid_month", "resid_pool_ar1_state")
resid_pool_by_t <- list()
global_pool <- numeric()
std_pool_by_t <- list()
std_global_pool <- numeric()
sd_row <- rep(NA_real_, nrow(panel))
rho_used <- max(-0.99, min(0.99, RHO))
sigma_u_used <- sqrt(max(1e-8, 1 - rho_used^2))

if (resid_pool_active) {
  untreated_obs <- ((panel$g == 0L) | (panel$t < panel$g)) & is.finite(panel$y_obs)
  base_fe <- panel %>% filter(untreated_obs)
  if (nrow(base_fe) < 100L) {
    stop("Too few untreated observations for residual-pool calibration (n=", nrow(base_fe), ").", call. = FALSE)
  }

  fe_fit <- fixest::feols(y_obs ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

  if (any(!is.finite(panel$yhat))) {
    mu_t <- base_fe %>%
      group_by(t) %>%
      summarise(mu = mean(y_obs, na.rm = TRUE), .groups = "drop")
    mu_map <- setNames(mu_t$mu, as.character(mu_t$t))
    mu_global <- mean(base_fe$y_obs, na.rm = TRUE)
    miss <- !is.finite(panel$yhat)
    panel$yhat[miss] <- mu_map[as.character(panel$t[miss])]
    panel$yhat[miss & !is.finite(panel$yhat)] <- mu_global
  }

  base_fe <- base_fe %>%
    mutate(ehat = as.numeric(residuals(fe_fit)))

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

  base_fe <- base_fe %>%
    mutate(sd_e = as.numeric(sd_map[as.character(id)]),
           sd_e = if_else(is.finite(sd_e) & sd_e > 0, sd_e, sd_global),
           z = ehat / sd_e) %>%
    filter(is.finite(z))

  std_pool_by_t <- split(base_fe$z, base_fe$t)
  std_global_pool <- base_fe$z[is.finite(base_fe$z)]
  if (length(std_global_pool) < 50L) {
    stop("Standardized residual pool too small (n=", length(std_global_pool), ").", call. = FALSE)
  }

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
  cat("Residual-pool calibration: rho_used=", round(rho_used, 3), " pool_n=", length(global_pool), "\n", sep = "")
}

draw_err_from_pool_iid_month <- function(tt) {
  vapply(tt, function(tt_i) {
    pool <- resid_pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < RESID_POOL_MIN_STATES) pool <- global_pool
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

draw_err_from_pool_ar1_state <- function(tt, idx_list) {
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

simulate_one <- function(seed) {
  set.seed(seed)

  e <- numeric(nrow(panel))
  if (ERR_MODE == "iid") {
    alpha_i <- rnorm(n_states, mean = 0, sd = SIGMA_A)
    gamma_t <- rnorm(n_t, mean = 0, sd = SIGMA_G)
    e <- rnorm(nrow(panel), mean = 0, sd = SIGMA_E)
    y0 <- alpha_i[panel$id] + gamma_t[t_index] + e
  } else if (ERR_MODE == "ar1_state") {
    alpha_i <- rnorm(n_states, mean = 0, sd = SIGMA_A)
    gamma_t <- rnorm(n_t, mean = 0, sd = SIGMA_G)
    rho <- max(-0.99, min(0.99, RHO))
    sigma_u <- SIGMA_E * sqrt(1 - rho^2)

    for (id_val in names(idx_by_id)) {
      idx <- idx_by_id[[id_val]]
      idx <- idx[order(panel$t[idx])]
      m <- length(idx)
      if (m <= 0) next

      x <- numeric(m)
      x[1] <- rnorm(1, 0, SIGMA_E)
      if (m >= 2) {
        for (j in 2:m) x[j] <- rho * x[j - 1] + rnorm(1, 0, sigma_u)
      }
      e[idx] <- x
    }
    y0 <- alpha_i[panel$id] + gamma_t[t_index] + e
  } else if (ERR_MODE == "resid_pool_iid_month") {
    e <- draw_err_from_pool_iid_month(panel$t)
    y0 <- panel$yhat + e
  } else if (ERR_MODE == "resid_pool_ar1_state") {
    e <- draw_err_from_pool_ar1_state(panel$t, idx_by_id)
    y0 <- panel$yhat + e
  } else {
    stop("Unknown ERR_MODE: ", ERR_MODE, call. = FALSE)
  }

  post <- (panel$g > 0L) & (panel$t >= panel$g)
  te <- rep(0.0, nrow(panel))
  te[post] <- true_effect_fn(panel$event_time[post], EFFECT_LOG,
                             shape = EFFECT_SHAPE,
                             ramp_months = RAMP_MONTHS,
                             delay_months = DELAY_MONTHS)
  y <- y0 + te

  dat <- data.frame(
    id = panel$id,
    t = panel$t,
    g = panel$g,
    y = y
  )

  out <- tryCatch({
    suppressMessages(suppressWarnings({
      mp <- did::att_gt(
        yname = "y",
        tname = "t",
        idname = "id",
        gname = "g",
        xformla = ~ 1,
        data = dat,
        panel = TRUE,
        control_group = "notyettreated",
        allow_unbalanced_panel = DID_ALLOW_UNBALANCED,
        est_method = "reg",
        faster_mode = DID_FASTER_MODE,
        bstrap = DID_BSTRAP,
        biters = DID_BITERS,
        cband = TRUE,
        clustervars = "id"
      )

      dyn <- did::aggte(mp, type = "dynamic", na.rm = TRUE)

      df_dyn <- tibble(
        sim = seed,
        egt = as.integer(dyn$egt),
        att = as.numeric(dyn$att.egt),
        se = as.numeric(dyn$se.egt),
        crit = as.numeric(dyn$crit.val.egt)
      ) %>%
        mutate(ok = is.finite(att) & is.finite(se) & se > 0)

      idx <- which(df_dyn$egt == TARGET_H & df_dyn$ok)
      if (length(idx) == 0L) stop("target_h missing or non-finite in dynamic results")
      i <- idx[1]

      tcrit <- crit_t(ALPHA, df = n_states - 1L)
      z <- df_dyn$att[i] / df_dyn$se[i]
      reject <- abs(z) > tcrit

      list(ok = TRUE,
           reject = reject,
           est_h = df_dyn$att[i],
           se_h = df_dyn$se[i],
           z_h = z,
           dyn = df_dyn)
    }))
  }, error = function(e) {
    list(ok = FALSE,
         reject = NA,
         est_h = NA_real_,
         se_h = NA_real_,
         z_h = NA_real_,
         dyn = NULL,
         err = conditionMessage(e))
  })

  out
}

set.seed(SEED)
seeds <- SEED + seq_len(N_SIMS) * 10007L

cat("Running", N_SIMS, "simulations...\n")
res <- run_serial_or_parallel(seeds, simulate_one, cores = N_CORES)

ok <- vapply(res, function(x) isTRUE(x$ok), logical(1))
n_ok <- sum(ok)
n_fail <- sum(!ok)

cat("Done. ok=", n_ok, "fail=", n_fail, "\n", sep = "")

if (n_ok == 0L) {
  err <- vapply(res, function(x) {
    v <- x$err
    if (!is.character(v) || length(v) != 1L || !nzchar(v)) NA_character_ else v
  }, character(1))
  err <- err[is.finite(match(err, err))]
  err <- err[!is.na(err)]
  if (length(err) > 0) {
    cat("\nTop errors (first 8):\n")
    print(utils::head(sort(table(err), decreasing = TRUE), 8))
  } else {
    cat("\nAll simulations failed with no error messages captured.\n")
  }

  overall <- tibble(
    panel_file = PANEL_FILE,
    n_sims = N_SIMS,
    n_ok = n_ok,
    n_fail = n_fail,
    n_states = n_states,
    n_rows = nrow(panel),
    coverage_threshold = COVERAGE_THRESHOLD,
    alpha = ALPHA,
    target_h = TARGET_H,
    effect_log = EFFECT_LOG,
    effect_shape = EFFECT_SHAPE,
    ramp_months = RAMP_MONTHS,
    delay_months = DELAY_MONTHS,
    err_mode = ERR_MODE,
    rho = RHO,
    sigma_e = SIGMA_E,
    type1_target_h = NA_real_,
    mean_se_target_h = NA_real_,
    sd_est_target_h = NA_real_,
    se_over_sd_est_target_h = NA_real_
  )
  write_csv(overall, file.path(OUT_DIR, "summary_overall.csv"))
  cat("\nWrote:\n")
  cat(" -", file.path(OUT_DIR, "summary_overall.csv"), "\n")
  stop("No successful simulations; see errors above. Try DID_ALLOW_UNBALANCED_PANEL=TRUE, COVERAGE_THRESHOLD, or DID_FASTER_MODE.", call. = FALSE)
}

target_df <- tibble(
  sim = seeds,
  ok = ok,
  reject = vapply(res, function(x) x$reject, logical(1)),
  est_h = vapply(res, function(x) x$est_h, numeric(1)),
  se_h = vapply(res, function(x) x$se_h, numeric(1)),
  z_h = vapply(res, function(x) x$z_h, numeric(1))
)

dyn_all <- bind_rows(lapply(res[ok], function(x) x$dyn))

true_dyn <- tibble(egt = sort(unique(dyn_all$egt))) %>%
  mutate(true_att = true_effect_fn(egt, EFFECT_LOG, shape = EFFECT_SHAPE,
                                  ramp_months = RAMP_MONTHS, delay_months = DELAY_MONTHS))

event_summary <- dyn_all %>%
  group_by(egt) %>%
  summarise(
    n = sum(ok),
    mean_att = mean(att, na.rm = TRUE),
    sd_att = sd(att, na.rm = TRUE),
    mean_se = mean(se, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(true_dyn, by = "egt") %>%
  mutate(bias = mean_att - true_att)

type1 <- if (n_ok > 0) mean(target_df$reject[target_df$ok], na.rm = TRUE) else NA_real_
mean_se_h <- if (n_ok > 0) mean(target_df$se_h[target_df$ok], na.rm = TRUE) else NA_real_
sd_est_h <- if (n_ok > 1) sd(target_df$est_h[target_df$ok], na.rm = TRUE) else NA_real_
se_over_sd <- if (is.finite(mean_se_h) && is.finite(sd_est_h) && sd_est_h > 0) mean_se_h / sd_est_h else NA_real_

overall <- tibble(
  panel_file = PANEL_FILE,
  n_sims = N_SIMS,
  n_ok = n_ok,
  n_fail = n_fail,
  n_states = n_states,
  n_rows = nrow(panel),
  coverage_threshold = COVERAGE_THRESHOLD,
  alpha = ALPHA,
  target_h = TARGET_H,
  effect_log = EFFECT_LOG,
  effect_shape = EFFECT_SHAPE,
  ramp_months = RAMP_MONTHS,
  delay_months = DELAY_MONTHS,
  err_mode = ERR_MODE,
  rho = RHO,
  sigma_e = SIGMA_E,
  type1_target_h = type1,
  mean_se_target_h = mean_se_h,
  sd_est_target_h = sd_est_h,
  se_over_sd_est_target_h = se_over_sd
)

write_csv(overall, file.path(OUT_DIR, "summary_overall.csv"))
write_csv(event_summary, file.path(OUT_DIR, "summary_by_event_time.csv"))
write_csv(target_df, file.path(OUT_DIR, "raw_target_h.csv"))

cat("\nWrote:\n")
cat(" -", file.path(OUT_DIR, "summary_overall.csv"), "\n")
cat(" -", file.path(OUT_DIR, "summary_by_event_time.csv"), "\n")
cat(" -", file.path(OUT_DIR, "raw_target_h.csv"), "\n")

if (EFFECT_LOG == 0) {
  cat("\nInterpretation (null): type1_target_h should be ~", ALPHA, "\n", sep = "")
} else {
  cat("\nInterpretation (non-null): compare mean_att vs true_att in summary_by_event_time.csv\n")
}
