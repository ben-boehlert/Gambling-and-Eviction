#!/usr/bin/env Rscript
################################################################################
# cs_calibration_unified.R
#
# Source-of-truth CS-only calibration harness.
#
# This script exists to resolve contradictions across earlier diagnostics by
# fixing three things at once:
#   1. one explicit panel construction
#   2. one explicit simulation DGP
#   3. actual CS estimation on every simulation draw
#
# It does NOT fall back to TWFE inference and it does NOT use shift-the-statistic
# shortcuts. Every reported target is computed from did::att_gt() / did::aggte().
#
# Reported targets:
#   - simple_overall: aggte(type = "simple")
#   - dynamic_h0:     aggte(type = "dynamic", min_e = 0,  max_e = 0)
#   - dynamic_post_0_12: aggte(type = "dynamic", min_e = 0, max_e = 12)
#
# Defaults match scripts/run_pretrends_statepanel.sh:
#   - exclude ME
#   - sample 2016-01-01 to 2024-12-31
#   - drop 2020-03-01 to 2021-07-31
#   - balance common months
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(fixest)
  library(did)
  library(glue)
})

source("utils/eviction_treatment_schedule.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
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
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

run_serial_or_parallel <- function(X, FUN, cores = 1L) {
  cores <- as.integer(max(1L, cores))
  if (cores <= 1L) return(lapply(X, FUN))
  if (.Platform$OS.type == "windows") return(lapply(X, FUN))
  parallel::mclapply(X, FUN, mc.cores = cores)
}

compute_t_p <- function(att, se, df) {
  if (is.finite(att) && is.finite(se) && se > 0) {
    2 * stats::pt(-abs(att / se), df = df)
  } else {
    NA_real_
  }
}

true_effect_fn <- function(event_time,
                           effect_log,
                           shape = "step",
                           ramp_months = 6L,
                           delay_months = 0L) {
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

draw_err_from_pool_iid_month <- function(tt, pool_by_t, fallback, min_states) {
  vapply(tt, function(tt_i) {
    pool <- pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < min_states) pool <- fallback
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

draw_err_from_pool_ar1_state <- function(tt,
                                         idx_list,
                                         std_pool_by_t,
                                         std_global_pool,
                                         sd_row,
                                         rho_used,
                                         sigma_u_used,
                                         min_states) {
  e_draw <- numeric(length(tt))
  for (id_val in names(idx_list)) {
    idx <- idx_list[[id_val]]
    idx <- idx[order(tt[idx])]
    m <- length(idx)
    if (m <= 0) next

    x <- numeric(m)
    t_seq <- tt[idx]
    pool_first <- std_pool_by_t[[as.character(t_seq[1])]]
    if (is.null(pool_first) || length(pool_first) < min_states) pool_first <- std_global_pool
    x[1] <- sample(pool_first, 1L)

    if (m >= 2L) {
      for (j in 2:m) {
        pool_curr <- std_pool_by_t[[as.character(t_seq[j])]]
        if (is.null(pool_curr) || length(pool_curr) < min_states) pool_curr <- std_global_pool
        u <- sample(pool_curr, 1L)
        x[j] <- rho_used * x[j - 1L] + sigma_u_used * u
      }
    }

    e_draw[idx] <- x * sd_row[idx]
  }
  e_draw
}

extract_agg_target <- function(mp, target_name, bstrap, biters, alpha) {
  if (target_name == "simple_overall") {
    agg <- did::aggte(mp, type = "simple", na.rm = TRUE,
                      bstrap = bstrap, biters = biters, cband = FALSE, alp = alpha)
    return(list(att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se)))
  }

  if (target_name == "dynamic_h0") {
    agg <- did::aggte(mp, type = "dynamic", min_e = 0L, max_e = 0L, na.rm = TRUE,
                      bstrap = bstrap, biters = biters, cband = FALSE, alp = alpha)
    return(list(att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se)))
  }

  if (target_name == "dynamic_post_0_12") {
    agg <- did::aggte(mp, type = "dynamic", min_e = 0L, max_e = 12L, na.rm = TRUE,
                      bstrap = bstrap, biters = biters, cband = FALSE, alp = alpha)
    return(list(att = as.numeric(agg$overall.att), se = as.numeric(agg$overall.se)))
  }

  stop("Unknown target_name: ", target_name, call. = FALSE)
}

# ----------------------------- configuration -----------------------------------

PANEL_FILE <- getenv1("PANEL_FILE", "data/raw/state_month_panel_with_treatment.csv")
TREAT_SOURCE <- tolower(getenv1("TREAT_SOURCE", "file"))
TREAT_FILE <- getenv1("TREAT_FILE", "data/raw/sports_gambling_legalization_dates.csv")
TREAT_DATE_COL <- getenv1("TREAT_DATE_COL", "online_start_date")
EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"))
MIN_DATE <- parse_date(getenv1("MIN_DATE", "2016-01-01"), as.Date("2016-01-01"))
MAX_DATE <- parse_date(getenv1("MAX_DATE", "2024-12-31"), as.Date("2024-12-31"))
DROP_START <- parse_date(getenv1("DROP_START", "2020-03-01"), as.Date("2020-03-01"))
DROP_END <- parse_date(getenv1("DROP_END", "2021-07-31"), as.Date("2021-07-31"))
COVERAGE_THRESHOLD_RAW <- getenv1("COVERAGE_THRESHOLD", "")
COVERAGE_THRESHOLD <- if (nzchar(COVERAGE_THRESHOLD_RAW)) parse_int(COVERAGE_THRESHOLD_RAW, 0L) else NA_integer_
BALANCE_COMMON_MONTHS <- parse_bool(getenv1("BALANCE_COMMON_MONTHS", "TRUE"), TRUE)

OUTCOME <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

CONTROL_GROUP <- getenv1("CONTROL_GROUP", "notyettreated")
EST_METHOD <- getenv1("EST_METHOD", "reg")
ALLOW_UNBALANCED <- parse_bool(getenv1("ALLOW_UNBALANCED_PANEL", "TRUE"), TRUE)
CS_FASTER_MODE <- parse_bool(getenv1("CS_FASTER_MODE", "TRUE"), TRUE)

N_SIMS <- parse_int(getenv1("N_SIMS", "200"), 200L)
SEED <- parse_int(getenv1("SEED", "123"), 123L)
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
N_CORES <- max(1L, parse_int(getenv1("N_CORES", "1"), 1L))

ERR_MODE <- tolower(trimws(getenv1("ERR_MODE", "resid_pool_ar1_state")))
RESID_POOL_MIN_STATES <- parse_int(getenv1("RESID_POOL_MIN_STATES", "5"), 5L)
RHO <- parse_num(getenv1("RHO", "0.6"), 0.6)
SIGMA_E <- parse_num(getenv1("SIGMA_E", "1.0"), 1.0)
SIGMA_A <- parse_num(getenv1("SIGMA_A", "1.0"), 1.0)
SIGMA_G <- parse_num(getenv1("SIGMA_G", "1.0"), 1.0)

EFFECT_LOG <- parse_num(getenv1("EFFECT_LOG", "0.0"), 0.0)
EFFECT_SHAPE <- getenv1("EFFECT_SHAPE", "step")
RAMP_MONTHS <- parse_int(getenv1("RAMP_MONTHS", "6"), 6L)
DELAY_MONTHS <- parse_int(getenv1("DELAY_MONTHS", "0"), 0L)

RUN_ANALYTIC <- parse_bool(getenv1("RUN_ANALYTIC", "TRUE"), TRUE)
RUN_BOOTSTRAP <- parse_bool(getenv1("RUN_BOOTSTRAP", "FALSE"), FALSE)
BOOTSTRAP_BITERS <- parse_int(getenv1("BOOTSTRAP_BITERS", "199"), 199L)

OUT_DIR <- getenv1("OUT_DIR", "output/cs_calibration_unified")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== CS UNIFIED CALIBRATION ===\n")
cat(glue("PANEL_FILE={PANEL_FILE}\n"))
cat(glue("TREAT_SOURCE={TREAT_SOURCE} TREAT_DATE_COL={TREAT_DATE_COL}\n"))
cat(glue("EXCLUDE_STATES={paste(EXCLUDE_STATES, collapse=',')} MIN_DATE={MIN_DATE} MAX_DATE={MAX_DATE}\n"))
cat(glue("DROP_START={DROP_START} DROP_END={DROP_END} BALANCE_COMMON_MONTHS={BALANCE_COMMON_MONTHS}\n"))
cat(glue("OUTCOME={OUTCOME} N_SIMS={N_SIMS} ALPHA={ALPHA} SEED={SEED} N_CORES={N_CORES}\n"))
cat(glue("ERR_MODE={ERR_MODE} EFFECT_LOG={EFFECT_LOG} EFFECT_SHAPE={EFFECT_SHAPE}\n"))
cat(glue("RUN_ANALYTIC={RUN_ANALYTIC} RUN_BOOTSTRAP={RUN_BOOTSTRAP} BOOTSTRAP_BITERS={BOOTSTRAP_BITERS}\n\n"))

if (!file.exists(PANEL_FILE)) stop("PANEL_FILE not found: ", PANEL_FILE, call. = FALSE)

# ----------------------------- panel build -------------------------------------

panel0_raw <- readr::read_csv(PANEL_FILE, show_col_types = FALSE)
has_panel_treat <- "treat_start" %in% names(panel0_raw)

panel0 <- panel0_raw %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    panel_treat_start_raw = if (has_panel_treat) as.Date(treat_start) else as.Date(NA),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
    filings_per_1k_renters = as.numeric(filings_per_1k_renters)
  )

if (length(EXCLUDE_STATES) > 0L) panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
}

coverage <- panel0 %>%
  count(state_abb, name = "n_months") %>%
  arrange(desc(n_months), state_abb)

max_coverage <- if (nrow(coverage) > 0) max(coverage$n_months, na.rm = TRUE) else NA_integer_
if (!is.finite(COVERAGE_THRESHOLD)) COVERAGE_THRESHOLD <- max_coverage

keep_states <- coverage %>% filter(n_months >= COVERAGE_THRESHOLD) %>% pull(state_abb)
panel <- panel0 %>% filter(state_abb %in% keep_states)

treat_by_state <- resolve_eviction_treatment_schedule(
  panel_df = panel,
  treat_source = TREAT_SOURCE,
  treat_file = TREAT_FILE,
  treat_date_col = TREAT_DATE_COL,
  panel_treat_col = "panel_treat_start_raw"
)

panel <- panel %>% left_join(treat_by_state, by = "state_abb")

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
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
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
n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
n_never <- n_distinct(panel$state_abb[panel$g == 0L])
n_cohorts <- n_distinct(panel$g[panel$g > 0L])
t_vals <- sort(unique(panel$t))
n_t <- length(t_vals)
t_index <- match(panel$t, t_vals)
idx_by_id <- split(seq_len(nrow(panel)), panel$id)

panel_summary <- tibble(
  n_states = n_states,
  n_treated = n_treated,
  n_never_treated = n_never,
  n_cohorts = n_cohorts,
  n_months = n_t,
  n_obs = nrow(panel),
  min_date = min(panel$month_date),
  max_date = max(panel$month_date),
  coverage_threshold = COVERAGE_THRESHOLD,
  outcome = OUTCOME,
  treat_source = TREAT_SOURCE,
  treat_date_col = TREAT_DATE_COL,
  drop_start = DROP_START,
  drop_end = DROP_END,
  balance_common_months = BALANCE_COMMON_MONTHS
)
readr::write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

cat(glue("Panel: {n_states} states ({n_treated} treated, {n_never} never), {n_cohorts} cohorts, {n_t} months, {nrow(panel)} obs\n\n"))

# ----------------------------- simulation baseline -----------------------------

resid_pool_active <- ERR_MODE %in% c("resid_pool_iid_month", "resid_pool_ar1_state")
resid_pool_by_t <- list()
global_pool <- numeric()
std_pool_by_t <- list()
std_global_pool <- numeric()
sd_row <- rep(NA_real_, nrow(panel))
rho_used <- max(-0.99, min(0.99, RHO))
sigma_u_used <- sqrt(max(1e-8, 1 - rho_used^2))
panel$yhat <- NA_real_

if (resid_pool_active) {
  untreated_obs <- ((panel$g == 0L) | (panel$t < panel$g)) & is.finite(panel$y_obs)
  base_fe <- panel %>% filter(untreated_obs)
  if (nrow(base_fe) < 100L) {
    stop("Too few untreated observations for residual-pool calibration.", call. = FALSE)
  }

  fe_fit <- fixest::feols(y_obs ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

  if (any(!is.finite(panel$yhat))) {
    mu_t <- base_fe %>% group_by(t) %>% summarise(mu = mean(y_obs, na.rm = TRUE), .groups = "drop")
    mu_map <- setNames(mu_t$mu, as.character(mu_t$t))
    mu_global <- mean(base_fe$y_obs, na.rm = TRUE)
    miss <- !is.finite(panel$yhat)
    panel$yhat[miss] <- mu_map[as.character(panel$t[miss])]
    panel$yhat[miss & !is.finite(panel$yhat)] <- mu_global
  }

  base_fe <- base_fe %>% mutate(ehat = as.numeric(residuals(fe_fit)))
  resid_pool_by_t <- split(base_fe$ehat[is.finite(base_fe$ehat)], base_fe$t[is.finite(base_fe$ehat)])
  global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]

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
    mutate(
      sd_e = as.numeric(sd_map[as.character(id)]),
      sd_e = if_else(is.finite(sd_e) & sd_e > 0, sd_e, sd_global),
      z = ehat / sd_e
    ) %>%
    filter(is.finite(z))

  std_pool_by_t <- split(base_fe$z, base_fe$t)
  std_global_pool <- base_fe$z[is.finite(base_fe$z)]

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
} else {
  panel$yhat <- 0.0
}

targets <- c("simple_overall", "dynamic_h0", "dynamic_post_0_12")
inference_modes <- character()
if (RUN_ANALYTIC) inference_modes <- c(inference_modes, "analytic")
if (RUN_BOOTSTRAP) inference_modes <- c(inference_modes, "bootstrap")
if (length(inference_modes) == 0L) stop("Set RUN_ANALYTIC=TRUE and/or RUN_BOOTSTRAP=TRUE.", call. = FALSE)

simulate_one <- function(seed) {
  set.seed(seed)

  y0 <- if (ERR_MODE == "iid") {
    alpha_i <- rnorm(n_states, mean = 0, sd = SIGMA_A)
    gamma_t <- rnorm(n_t, mean = 0, sd = SIGMA_G)
    e <- rnorm(nrow(panel), mean = 0, sd = SIGMA_E)
    alpha_i[panel$id] + gamma_t[t_index] + e
  } else if (ERR_MODE == "ar1_state") {
    alpha_i <- rnorm(n_states, mean = 0, sd = SIGMA_A)
    gamma_t <- rnorm(n_t, mean = 0, sd = SIGMA_G)
    rho <- max(-0.99, min(0.99, RHO))
    sigma_u <- SIGMA_E * sqrt(1 - rho^2)
    e <- numeric(nrow(panel))
    for (id_val in names(idx_by_id)) {
      idx <- idx_by_id[[id_val]]
      idx <- idx[order(panel$t[idx])]
      m <- length(idx)
      if (m <= 0) next
      x <- numeric(m)
      x[1] <- rnorm(1L, 0, SIGMA_E)
      if (m >= 2L) {
        for (j in 2:m) x[j] <- rho * x[j - 1L] + rnorm(1L, 0, sigma_u)
      }
      e[idx] <- x
    }
    alpha_i[panel$id] + gamma_t[t_index] + e
  } else if (ERR_MODE == "resid_pool_iid_month") {
    panel$yhat + draw_err_from_pool_iid_month(panel$t, resid_pool_by_t, global_pool, RESID_POOL_MIN_STATES)
  } else if (ERR_MODE == "resid_pool_ar1_state") {
    panel$yhat + draw_err_from_pool_ar1_state(
      panel$t, idx_by_id, std_pool_by_t, std_global_pool, sd_row,
      rho_used, sigma_u_used, RESID_POOL_MIN_STATES
    )
  } else {
    stop("Unknown ERR_MODE: ", ERR_MODE, call. = FALSE)
  }

  te <- rep(0.0, nrow(panel))
  post <- (panel$g > 0L) & (panel$t >= panel$g)
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

  rows <- list()
  for (mode in inference_modes) {
    bstrap <- identical(mode, "bootstrap")
    biters <- if (bstrap) BOOTSTRAP_BITERS else 0L

    mp <- tryCatch({
      suppressMessages(suppressWarnings({
        did::att_gt(
          yname = "y",
          tname = "t",
          idname = "id",
          gname = "g",
          xformla = ~1,
          data = dat,
          panel = TRUE,
          control_group = CONTROL_GROUP,
          allow_unbalanced_panel = ALLOW_UNBALANCED,
          est_method = EST_METHOD,
          faster_mode = CS_FASTER_MODE,
          bstrap = bstrap,
          biters = biters,
          cband = FALSE,
          clustervars = "id"
        )
      }))
    }, error = function(e) e)

    if (inherits(mp, "error")) {
      for (target_name in targets) {
        rows[[length(rows) + 1L]] <- tibble(
          seed = seed,
          inference = mode,
          target = target_name,
          ok = FALSE,
          att = NA_real_,
          se = NA_real_,
          p_value = NA_real_,
          reject = NA,
          err = conditionMessage(mp)
        )
      }
      next
    }

    for (target_name in targets) {
      target_res <- tryCatch({
        extract_agg_target(mp, target_name = target_name, bstrap = bstrap, biters = biters, alpha = ALPHA)
      }, error = function(e) e)

      if (inherits(target_res, "error")) {
        rows[[length(rows) + 1L]] <- tibble(
          seed = seed,
          inference = mode,
          target = target_name,
          ok = FALSE,
          att = NA_real_,
          se = NA_real_,
          p_value = NA_real_,
          reject = NA,
          err = conditionMessage(target_res)
        )
      } else {
        p_value <- compute_t_p(target_res$att, target_res$se, df = n_states - 1L)
        rows[[length(rows) + 1L]] <- tibble(
          seed = seed,
          inference = mode,
          target = target_name,
          ok = is.finite(target_res$att) && is.finite(target_res$se) && target_res$se > 0 && is.finite(p_value),
          att = target_res$att,
          se = target_res$se,
          p_value = p_value,
          reject = ifelse(is.finite(p_value), p_value < ALPHA, NA),
          err = NA_character_
        )
      }
    }
  }

  bind_rows(rows)
}

set.seed(SEED)
seeds <- SEED + seq_len(N_SIMS) * 10007L
cat(glue("Running {N_SIMS} simulations...\n"))
sim_results <- bind_rows(run_serial_or_parallel(seeds, simulate_one, cores = N_CORES))

readr::write_csv(sim_results, file.path(OUT_DIR, "sim_results.csv"))

summarize_group <- function(df) {
  valid <- df$ok & is.finite(df$att) & is.finite(df$se) & df$se > 0 & is.finite(df$p_value)
  n_valid <- sum(valid)
  n_fail <- nrow(df) - n_valid

  if (n_valid == 0L) {
    return(tibble(
      n_valid = 0L,
      n_fail = n_fail,
      rejection = NA_real_,
      mean_att = NA_real_,
      sd_att = NA_real_,
      mean_se = NA_real_,
      se_over_sd = NA_real_
    ))
  }

  att_v <- df$att[valid]
  se_v <- df$se[valid]
  p_v <- df$p_value[valid]

  tibble(
    n_valid = n_valid,
    n_fail = n_fail,
    rejection = mean(p_v < ALPHA, na.rm = TRUE),
    mean_att = mean(att_v, na.rm = TRUE),
    sd_att = if (length(att_v) > 1L) stats::sd(att_v, na.rm = TRUE) else NA_real_,
    mean_se = mean(se_v, na.rm = TRUE),
    se_over_sd = if (length(att_v) > 1L && is.finite(stats::sd(att_v, na.rm = TRUE)) && stats::sd(att_v, na.rm = TRUE) > 0) {
      mean(se_v, na.rm = TRUE) / stats::sd(att_v, na.rm = TRUE)
    } else {
      NA_real_
    }
  )
}

calibration_summary <- sim_results %>%
  group_by(inference, target) %>%
  group_modify(~ summarize_group(.x)) %>%
  ungroup() %>%
  arrange(match(inference, inference_modes), match(target, targets))

readr::write_csv(calibration_summary, file.path(OUT_DIR, "calibration_summary.csv"))

cat("\nCalibration summary:\n")
print(calibration_summary, n = nrow(calibration_summary))
cat(glue("\nWrote:\n - {file.path(OUT_DIR, 'panel_summary.csv')}\n - {file.path(OUT_DIR, 'sim_results.csv')}\n - {file.path(OUT_DIR, 'calibration_summary.csv')}\n"))
