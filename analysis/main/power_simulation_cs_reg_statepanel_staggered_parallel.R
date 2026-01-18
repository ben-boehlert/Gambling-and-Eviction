#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_reg_statepanel_staggered_parallel.R
#
# Callaway-Sant'Anna DiD power simulation using REGRESSION adjustment estimator
# (est_method="reg") - FIXED VERSION that avoids fastglm bug with IPW
#
# Key differences from IPW version:
#   - Uses est_method="reg" (regression adjustment) instead of "ipw"
#   - Avoids fastglm formula bug that causes 100% simulation failure
#   - Faster and more stable than IPW with no covariates
#   - Appropriate for power simulations with known DGP
#
# Key pieces:
#   1) Build state-month panel from combined_monthly_panel.csv
#   2) Merge treatment schedule from state_month_panel_with_treatment.csv
#   3) Simulate outcomes using untreated variation:
#      - Fit unit + time FE on untreated observations: y ~ 1 | id + t
#      - Resample residuals within month (iid_month) or generate AR(1)
#      - Add constant post-adoption treatment effect on log scale
#   4) Estimate CS DiD each simulation:
#      - did::att_gt(est_method="reg", bstrap=TRUE, clustervars="id")
#      - Aggregate to scalar ATT using aggte(type="simple")
#      - Use t-test with df=n_states-1 for inference
#
# Outputs (in OUT_DIR):
#   run.log
#   treatment_schedule.csv
#   panel_summary.csv
#   power_by_effect.csv
#   diagnostics_sanity.csv
#   draws_sample.csv
#   power_curve.png
#   simulation_diagnostics.csv (success rate, error messages)
#
# Env vars:
#   DATA_FILE      default combined_monthly_panel.csv
#   TREAT_FILE     default state_month_panel_with_treatment.csv
#   OUT_DIR        default ./cs_reg_power_out
#   OUTCOME        log1p_filings_count (default) or log1p_rate
#   N_SIMS         default 2000
#   EFFECT_PCTS    default "0,0.05,0.10,0.15,0.20"
#   ALPHA          default 0.05
#   SEED           default 123
#   N_WORKERS      default 20
#   BATCH_SIZE     default 50
#   ERR_MODE       iid_month (default) or ar1
#
#   DID_CONTROL_GROUP  "nevertreated" (default) or "notyettreated"
#   DID_BSTRAP         "TRUE" (default) - use bootstrap inference
#   DID_BITERS         199 (default) - bootstrap iterations
#
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
  library(tibble)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x

# ----------------------------- helpers ----------------------------------------

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1","TRUE","T","YES","Y")
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

parse_num_list <- function(x, default = numeric()) {
  if (!nzchar(x)) return(default)
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  out <- suppressWarnings(as.numeric(trimws(parts)))
  out[is.finite(out)]
}

log_line <- function(path, msg) {
  cat(msg, "\n", file = path, append = TRUE)
}

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

append_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path)) {
    readr::write_csv(df, path)
  } else {
    readr::write_csv(df, path, append = TRUE)
  }
}

fmt_eff <- function(x) {
  gsub("\\.", "p", format(x, trim = TRUE, scientific = FALSE))
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

# ----------------------------- config -----------------------------------------

DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "cs_reg_power_out")

OUTCOME    <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS   <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

N_SIMS     <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
EFFECT_PCTS <- parse_num_list(getenv1("EFFECT_PCTS", "0,0.05,0.10,0.15,0.20"),
                              default = c(0,0.05,0.10,0.15,0.20))
ALPHA      <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED       <- parse_int(getenv1("SEED", "123"), 123L)

BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "50"), 50L)
MIN_POOL   <- parse_int(getenv1("MIN_POOL", "10"), 10L)

ERR_MODE <- tolower(getenv1("ERR_MODE", "iid_month"))
if (!ERR_MODE %in% c("iid_month", "ar1")) {
  stop("ERR_MODE must be iid_month or ar1", call. = FALSE)
}

ERR_AR1_RHO  <- parse_num(getenv1("ERR_AR1_RHO", ""), NA_real_)
ERR_AR1_CLIP <- parse_num(getenv1("ERR_AR1_CLIP", "0.98"), 0.98)

# Parallel
req_workers <- parse_int(getenv1("N_WORKERS", "20"), 20L)
slurm_cpus  <- parse_int(getenv1("SLURM_CPUS_PER_TASK", ""), NA_integer_)
if (is.finite(slurm_cpus) && slurm_cpus > 0L) req_workers <- min(req_workers, slurm_cpus)
N_WORKERS <- max(1L, req_workers)
use_parallel <- (N_WORKERS > 1L)

# DID options - CRITICAL: Use est_method="reg" to avoid fastglm bug
did_method <- "reg"  # FIXED: Always use regression adjustment
did_control_group <- getenv1("DID_CONTROL_GROUP", "nevertreated")
did_bstrap <- parse_bool(getenv1("DID_BSTRAP", "TRUE"), TRUE)
did_biters <- parse_int(getenv1("DID_BITERS", "199"), 199L)

# State/date filtering
EXCLUDE_STATES <- getenv1("EXCLUDE_STATES", "")
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}
EXCLUDE_STATES_VEC <- parse_state_list(EXCLUDE_STATES)

# Windows for exclusion
EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))
EXCLUDE_END   <- as.Date(getenv1("EXCLUDE_END", ""))

in_exclude_window <- function(d) {
  if (is.na(EXCLUDE_START) || is.na(EXCLUDE_END)) return(rep(FALSE, length(d)))
  (d >= EXCLUDE_START) & (d < EXCLUDE_END)
}

cat("=== CS DiD POWER SIMULATION (REGRESSION ESTIMATOR) ===\n")
cat("Version: 2026-01-13 (Fixed: uses est_method=reg)\n")
cat("Fix: Avoids fastglm bug with IPW/DR methods\n")
cat("Estimator: Regression adjustment (not IPW)\n")
cat("=======================================================\n\n")

# ----------------------------- logging ----------------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")

log_line(RUN_LOG, "=== CS DiD POWER SIM (REG ESTIMATOR) ===")
log_line(RUN_LOG, glue("DATA_FILE: {DATA_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE: {TREAT_FILE}"))
log_line(RUN_LOG, glue("OUT_DIR: {OUT_DIR}"))
log_line(RUN_LOG, glue("OUTCOME: {OUTCOME}"))
log_line(RUN_LOG, glue("N_SIMS: {N_SIMS}  ALPHA={ALPHA}  SEED={SEED}"))
log_line(RUN_LOG, glue("N_WORKERS: {N_WORKERS} (SLURM_CPUS_PER_TASK={getenv1('SLURM_CPUS_PER_TASK','')})"))
log_line(RUN_LOG, glue("DID: est_method=reg (FIXED), control_group={did_control_group}, bstrap={did_bstrap}, biters={did_biters}"))
log_line(RUN_LOG, glue("ERR_MODE: {ERR_MODE} (rho={ifelse(is.finite(ERR_AR1_RHO), ERR_AR1_RHO, 'estimate')}, clip={ERR_AR1_CLIP})"))
log_line(RUN_LOG, glue("FILTERS: EXCLUDE_STATES={ifelse(nzchar(EXCLUDE_STATES), EXCLUDE_STATES, 'none')}  MAX_DATE={ifelse(is.finite(MAX_DATE), as.character(MAX_DATE), 'none')}"))
log_line(RUN_LOG, "========================================")

# ----------------------------- load data --------------------------------------

if (!file.exists(DATA_FILE)) stop(glue("DATA_FILE not found: {DATA_FILE}"), call. = FALSE)
if (!file.exists(TREAT_FILE)) stop(glue("TREAT_FILE not found: {TREAT_FILE}"), call. = FALSE)

log_line(RUN_LOG, "Loading data...")

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

# Load panel data
raw <- readr::read_csv(DATA_FILE, show_col_types = FALSE)

# Build state panel
panel_raw <- raw %>%
  mutate(
    state = if ("state" %in% names(.)) state else state_abbr_from_geoid(geo_id),
    month_date = as.Date(month_date)
  ) %>%
  filter(!is.na(state), !is.na(month_date), is.finite(get(OUTCOME)))

# Apply state filtering
if (length(EXCLUDE_STATES_VEC) > 0) {
  log_line(RUN_LOG, glue("Excluding states: {paste(EXCLUDE_STATES_VEC, collapse=', ')}"))
  panel_raw <- panel_raw %>% filter(!state %in% EXCLUDE_STATES_VEC)
}

# Apply date filtering
if (is.finite(MAX_DATE)) {
  log_line(RUN_LOG, glue("Excluding dates after: {MAX_DATE}"))
  panel_raw <- panel_raw %>% filter(month_date <= MAX_DATE)
}

# Aggregate to state-month
panel <- panel_raw %>%
  group_by(state, month_date) %>%
  summarise(
    y = mean(get(OUTCOME), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(is.finite(y))

# Load treatment schedule
treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  select(state, treatment_date) %>%
  distinct()

# Merge treatment
panel <- panel %>%
  left_join(treat, by = "state") %>%
  mutate(
    treatment_date = as.Date(treatment_date),
    treatment_date = if_else(is.na(treatment_date), as.Date("2099-12-31"), treatment_date)
  )

# Create time indices
panel <- panel %>%
  arrange(state, month_date) %>%
  mutate(
    t = ym_index(month_date),
    g = ym_index(treatment_date)
  )

# Set never-treated to g=0
panel <- panel %>%
  mutate(
    g = if_else(treatment_date >= as.Date("2099-01-01"), 0L, g),
    post_treat = (g > 0) & (t >= g),
    untreated_obs = !post_treat
  )

# Create numeric IDs
state_map <- panel %>%
  distinct(state) %>%
  arrange(state) %>%
  mutate(id = row_number())

panel <- panel %>%
  left_join(state_map, by = "state")

n_states <- length(unique(panel$id))
n_months <- length(unique(panel$t))
n_obs <- nrow(panel)

log_line(RUN_LOG, glue("Panel: {n_states} states, {n_months} months, {n_obs} observations"))

# Save treatment schedule
treat_summary <- panel %>%
  group_by(state, id, g, treatment_date) %>%
  summarise(
    n_obs = n(),
    n_treated = sum(post_treat),
    .groups = "drop"
  ) %>%
  arrange(g, state)

safe_write_csv(treat_summary, file.path(OUT_DIR, "treatment_schedule.csv"))

# Save panel summary
panel_summary <- tibble::tibble(
  n_states = n_states,
  n_months = n_months,
  n_obs = n_obs,
  outcome = OUTCOME,
  n_never_treated = sum((panel %>% distinct(id, g))$g == 0),
  n_eventually_treated = sum((panel %>% distinct(id, g))$g > 0)
)

safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

log_line(RUN_LOG, glue("  Never treated: {panel_summary$n_never_treated}"))
log_line(RUN_LOG, glue("  Eventually treated: {panel_summary$n_eventually_treated}"))

# ----------------------------- FE fit -----------------------------------------

log_line(RUN_LOG, "Fitting unit+time FE on untreated observations...")

base_fe <- panel %>%
  filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))

if (nrow(base_fe) < 100) {
  stop("Too few untreated observations for FE fitting", call. = FALSE)
}

fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)

panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

if (any(!is.finite(panel$yhat))) {
  bad <- which(!is.finite(panel$yhat))
  log_line(RUN_LOG, glue("WARNING: {length(bad)} observations have non-finite yhat"))
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
}

# Residuals
base_fe$ehat <- as.numeric(residuals(fe_fit))

# Residual pools by month (for iid_month mode)
pool_dat <- base_fe %>% filter(!in_exclude_window(month_date))
resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
global_pool <- pool_dat$ehat

log_line(RUN_LOG, glue("Residual pool: {length(global_pool)} observations across {length(unique(pool_dat$t))} months"))

# AR(1) setup if needed
if (ERR_MODE == "ar1") {
  # Estimate rho if not provided
  if (!is.finite(ERR_AR1_RHO)) {
    log_line(RUN_LOG, "Estimating AR(1) parameter...")

    ar1_dat <- base_fe %>%
      arrange(id, t) %>%
      group_by(id) %>%
      mutate(
        ehat_lag = lag(ehat),
        valid = !is.na(ehat_lag) & is.finite(ehat_lag)
      ) %>%
      filter(valid)

    if (nrow(ar1_dat) > 50) {
      ar1_fit <- lm(ehat ~ ehat_lag - 1, data = ar1_dat)
      rho_est <- coef(ar1_fit)[1]
      rho_used <- max(-0.99, min(ERR_AR1_CLIP, rho_est))
      log_line(RUN_LOG, glue("  Estimated rho={round(rho_est, 3)}, using rho={round(rho_used, 3)}"))
    } else {
      rho_used <- 0.5
      log_line(RUN_LOG, glue("  Too few obs for AR(1) estimation, using rho={rho_used}"))
    }
  } else {
    rho_used <- ERR_AR1_RHO
    log_line(RUN_LOG, glue("Using user-specified rho={rho_used}"))
  }

  # Standardized residuals by month
  std_pool_by_t <- lapply(resid_pool_by_t, function(r) {
    if (length(r) >= MIN_POOL) (r - mean(r)) / sd(r) else numeric(0)
  })
  std_global_pool <- (global_pool - mean(global_pool)) / sd(global_pool)

  # By-state SD for scaling
  sd_by_id <- base_fe %>%
    group_by(id) %>%
    summarise(sd_ehat = sd(ehat, na.rm = TRUE)) %>%
    arrange(id)

  sd_row <- sd_by_id$sd_ehat[match(panel$id, sd_by_id$id)]

  # AR(1) innovation variance
  sigma_u <- sqrt(1 - rho_used^2)

  # Index for AR(1) generation
  idx_by_id <- split(seq_len(nrow(panel)), panel$id)
}

# ----------------------------- simulation functions ---------------------------

draw_errors_iid_month <- function(t_vec, pool_by_t, fallback_pool) {
  e <- numeric(length(t_vec))
  for (t_val in unique(t_vec)) {
    idx <- which(t_vec == t_val)
    pool <- pool_by_t[[as.character(t_val)]]
    if (is.null(pool) || length(pool) < MIN_POOL) pool <- fallback_pool
    e[idx] <- sample(pool, size = length(idx), replace = TRUE)
  }
  e
}

draw_errors_ar1 <- function(t_vec, idx_by_id, std_pool_by_t, std_global_pool, sd_vec, rho, sigma_u) {
  e_draw <- numeric(length(t_vec))

  for (id_val in names(idx_by_id)) {
    idx <- idx_by_id[[id_val]]
    n_t <- length(idx)

    # Initialize
    x <- numeric(n_t)
    t_seq <- t_vec[idx]

    # First period: sample from standardized pool
    t_first <- t_seq[1]
    pool_first <- std_pool_by_t[[as.character(t_first)]]
    if (is.null(pool_first) || length(pool_first) < MIN_POOL) pool_first <- std_global_pool
    x[1] <- sample(pool_first, 1)

    # Subsequent periods: AR(1)
    for (i in 2:n_t) {
      t_curr <- t_seq[i]
      pool_curr <- std_pool_by_t[[as.character(t_curr)]]
      if (is.null(pool_curr) || length(pool_curr) < MIN_POOL) pool_curr <- std_global_pool

      u <- sample(pool_curr, 1)
      x[i] <- rho * x[i-1] + sigma_u * u
    }

    # Scale by state-specific SD
    e_draw[idx] <- x * sd_vec[idx]
  }

  e_draw
}

# One simulation
one_sim <- function(seed, effect_log) {
  set.seed(seed)

  # Draw errors
  e_draw <- if (ERR_MODE == "iid_month") {
    draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  } else {
    draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool, sd_row, rho_used, sigma_u)
  }

  # Generate outcome
  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_log, 0.0)

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    g  = panel$g,
    y  = y_sim
  )

  # Estimate CS DiD with regression adjustment
  out <- tryCatch({
    suppressWarnings({
      est <- did::att_gt(
        yname = "y",
        tname = "t",
        idname = "id",
        gname = "g",
        xformla = ~ 1,
        data = dat,
        panel = TRUE,
        control_group = did_control_group,
        allow_unbalanced_panel = TRUE,
        est_method = "reg",  # CRITICAL: Use regression, not IPW
        faster_mode = FALSE,
        bstrap = did_bstrap,
        biters = did_biters,
        cband = FALSE,
        clustervars = "id"
      )

      # Check for sparse ATT(g,t) cells
      att_vec <- est$att
      miss_share <- if (is.null(att_vec)) 0 else mean(is.na(att_vec))
      if (!is.finite(miss_share) || miss_share >= 0.25) {
        stop(glue("Too many missing ATT(g,t) cells: miss_share={round(miss_share,3)}"))
      }

      # Aggregate to scalar
      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)

      # Compute p-value using t-distribution
      z <- att / se
      p <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_

      list(ok = TRUE, att = att, se = se, p = p)
    })
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = conditionMessage(e))
  })

  # Validate results
  if (!isTRUE(out$ok) || !is.finite(out$att) || !is.finite(out$se) || out$se <= 0 || !is.finite(out$p)) {
    err_msg <- out$err
    if (is.null(err_msg) || !nzchar(as.character(err_msg))) err_msg <- "non-finite att/se/p"
    return(list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = err_msg))
  }

  out
}

# ----------------------------- run simulations --------------------------------

log_line(RUN_LOG, glue("Starting simulations: {N_SIMS} per effect, {length(EFFECT_PCTS)} effects"))

if (use_parallel) {
  log_line(RUN_LOG, glue("Using parallel execution: {N_WORKERS} workers"))
  library(parallel)
  cl <- parallel::makeCluster(N_WORKERS)
  on.exit(parallel::stopCluster(cl), add = TRUE)

  parallel::clusterExport(cl, varlist = c(
    "panel", "n_states", "did_control_group", "did_bstrap", "did_biters",
    "resid_pool_by_t", "global_pool", "ERR_MODE", "MIN_POOL",
    "idx_by_id", "std_pool_by_t", "std_global_pool", "sd_row", "rho_used", "sigma_u",
    "draw_errors_iid_month", "draw_errors_ar1"
  ), envir = environment())

  parallel::clusterEvalQ(cl, {
    library(did)
    library(dplyr)
  })
}

all_results <- list()
diagnostics <- list()

for (eff_pct in EFFECT_PCTS) {
  effect_log <- eff_pct

  log_line(RUN_LOG, glue("Effect={eff_pct} ({effect_log} log points)"))

  set.seed(SEED + as.integer(eff_pct * 1000))
  seeds <- sample.int(1e8, N_SIMS)

  # Run simulations
  if (use_parallel) {
    results <- parallel::parLapply(cl, seeds, function(s) one_sim(s, effect_log))
  } else {
    results <- lapply(seeds, function(s) one_sim(s, effect_log))
  }

  # Convert to data frame
  df <- data.frame(
    effect_pct = eff_pct,
    effect_log = effect_log,
    seed = seeds,
    ok = sapply(results, function(r) isTRUE(r$ok)),
    att = sapply(results, function(r) r$att),
    se = sapply(results, function(r) r$se),
    p = sapply(results, function(r) r$p)
  )

  all_results[[length(all_results) + 1]] <- df

  # Success rate check
  success_rate <- mean(df$ok)

  log_line(RUN_LOG, glue("  Success: {sum(df$ok)}/{nrow(df)} ({round(100*success_rate,1)}%)"))

  # FAIL-FAST CHECK
  if (success_rate < 0.95) {
    # Collect error messages
    errors <- sapply(results, function(r) {
      if (!isTRUE(r$ok) && !is.null(r$err)) as.character(r$err) else NA_character_
    })
    errors <- errors[!is.na(errors)]

    if (length(errors) > 0) {
      unique_errors <- unique(errors)
      error_counts <- sapply(unique_errors, function(e) sum(errors == e))

      log_line(RUN_LOG, "ERROR: Low success rate!")
      log_line(RUN_LOG, glue("  Success rate: {round(100*success_rate,1)}% < 95%"))
      log_line(RUN_LOG, "  Top errors:")
      for (i in seq_len(min(3, length(unique_errors)))) {
        log_line(RUN_LOG, glue("    {i}. ({error_counts[i]} times): {unique_errors[i]}"))
      }

      stop("Simulation failed: success rate < 95%. See run.log for details.")
    }
  }

  # Compute power/type I error
  df_ok <- df %>% filter(ok)

  if (nrow(df_ok) > 0) {
    power <- mean(df_ok$p < ALPHA, na.rm = TRUE)
    mean_att <- mean(df_ok$att, na.rm = TRUE)
    mean_se <- mean(df_ok$se, na.rm = TRUE)

    log_line(RUN_LOG, glue("  Power: {round(100*power,1)}%  ATT: {round(mean_att,4)}  SE: {round(mean_se,4)}"))
  }
}

# Combine results
all_df <- bind_rows(all_results)

# Save sample draws
sample_draws <- all_df %>%
  group_by(effect_pct) %>%
  slice_head(n = 5) %>%
  ungroup()

safe_write_csv(sample_draws, file.path(OUT_DIR, "draws_sample.csv"))

# Compute power by effect
power_summary <- all_df %>%
  filter(ok) %>%
  group_by(effect_pct, effect_log) %>%
  summarise(
    n_sims = n(),
    power = mean(p < ALPHA, na.rm = TRUE),
    mean_att = mean(att, na.rm = TRUE),
    sd_att = sd(att, na.rm = TRUE),
    mean_se = mean(se, na.rm = TRUE),
    se_att_ratio = mean_se / sd_att,
    .groups = "drop"
  )

safe_write_csv(power_summary, file.path(OUT_DIR, "power_by_effect.csv"))

# Diagnostics for null (effect=0)
null_df <- all_df %>% filter(effect_pct == 0, ok)

if (nrow(null_df) > 0) {
  null_diag <- tibble::tibble(
    n_states = n_states,
    n_sims = nrow(null_df),
    mean_att0 = mean(null_df$att, na.rm = TRUE),
    sd_att0 = sd(null_df$att, na.rm = TRUE),
    mean_se0 = mean(null_df$se, na.rm = TRUE),
    se_inflation = mean(null_df$se, na.rm = TRUE) / sd(null_df$att, na.rm = TRUE),
    type1_at_effect0 = mean(null_df$p < ALPHA, na.rm = TRUE)
  )

  safe_write_csv(null_diag, file.path(OUT_DIR, "diagnostics_sanity.csv"))

  log_line(RUN_LOG, "")
  log_line(RUN_LOG, "=== NULL DIAGNOSTICS ===")
  log_line(RUN_LOG, glue("Type I error: {round(100*null_diag$type1_at_effect0,2)}%"))
  log_line(RUN_LOG, glue("SE inflation: {round(null_diag$se_inflation,3)}x"))
  log_line(RUN_LOG, "========================")
}

# Plot power curve
if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)

  p <- ggplot(power_summary, aes(x = effect_pct, y = power)) +
    geom_line() +
    geom_point() +
    geom_hline(yintercept = ALPHA, linetype = "dashed", color = "red") +
    labs(
      title = "CS DiD Power Curve (Regression Estimator)",
      subtitle = glue("n_states={n_states}, n_sims={N_SIMS}"),
      x = "Effect size (log points)",
      y = "Power"
    ) +
    theme_minimal()

  ggsave(file.path(OUT_DIR, "power_curve.png"), p, width = 8, height = 6)
}

log_line(RUN_LOG, "")
log_line(RUN_LOG, "=== SIMULATION COMPLETE ===")
log_line(RUN_LOG, glue("Results saved to: {OUT_DIR}"))

cat("\nSimulation complete! Results in:", OUT_DIR, "\n")
