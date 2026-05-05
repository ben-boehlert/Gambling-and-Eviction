#!/usr/bin/env Rscript
################################################################################
# power_simulation_mortgage_delinquency.R
#
# Power simulation for mortgage delinquency outcome (% 90+ days late),
# parallel to the eviction filings power analysis.
#
# Two estimators:
#   A) TWFE — feols(y ~ post_treat | id + t, cluster = ~id)
#   B) CS-DiD — did::att_gt() with aggte(type="simple") overall ATT
#
# Data: state-month mortgage delinquency panel (wide-format CSV)
# Treatment: staggered online sports gambling legalization
#
# Approach:
#   1) Build balanced state-month panel from mortgage delinquency data
#   2) Merge treatment schedule (online legalization dates)
#   3) Fit unit + time FE on untreated observations, extract residuals
#   4) Simulate outcomes: yhat + resampled_residuals + effect * post_treat
#   5) Estimate TWFE (and optionally CS-DiD) on each simulated dataset
#   6) Compute rejection rates = power at each effect size
#
# Env vars:
#   MORTGAGE_FILE   default data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv
#   TREAT_FILE      default data/raw/sports_gambling_legalization_dates.csv
#   TREAT_DATE_COL  default online_start_date
#   OUT_DIR         default output/power_mortgage_delinquency
#   OUTCOME         delinq_pct (default) or log_delinq_pct
#   N_SIMS          default 2000
#   EFFECT_SIZES    default "0,0.05,0.10,0.15,0.20,0.30,0.50"
#                   (proportional change for log; absolute pp change for levels)
#   ALPHA           default 0.05
#   SEED            default 20260409
#   N_WORKERS       default 8
#   BATCH_SIZE      default 50
#   ERR_MODE        iid_month (only mode currently implemented)
#   DROP_START / DROP_END   optional COVID exclusion window
#   RUN_CS          TRUE (default) or FALSE — whether to run CS-DiD simulations
#   CS_N_SIMS       default 500 (CS is slower)
#   CS_BITERS       default 50 (bootstrap iterations for CS)
#   CS_CONTROL_GROUP  notyettreated (default) or nevertreated
#   CS_EST_METHOD   reg (default) or ipw
################################################################################

# Force single-threaded BLAS to avoid contention under parallel
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(glue)
  library(fixest)
  library(tibble)
  library(did)
})

set.seed(20260409)

################################################################################
# HELPERS
################################################################################

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

parse_num_list <- function(x, default = numeric()) {
  if (!nzchar(x)) return(default)
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  out <- suppressWarnings(as.numeric(trimws(parts)))
  out[is.finite(out)]
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

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
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
  if (!file.exists(path)) readr::write_csv(df, path) else readr::write_csv(df, path, append = TRUE)
}

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d < end)
}

################################################################################
# CONFIGURATION
################################################################################

MORTGAGE_FILE  <- getenv1("MORTGAGE_FILE", "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
TREAT_FILE     <- getenv1("TREAT_FILE", "data/raw/sports_gambling_legalization_dates.csv")
TREAT_DATE_COL <- getenv1("TREAT_DATE_COL", "online_start_date")
OUT_DIR        <- getenv1("OUT_DIR", "output/power_mortgage_delinquency")

OUTCOME    <- getenv1("OUTCOME", "delinq_pct")
N_SIMS     <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
EFFECT_SIZES <- parse_num_list(
  getenv1("EFFECT_SIZES", "0,0.05,0.10,0.15,0.20,0.30,0.50"),
  default = c(0, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50)
)
ALPHA      <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED       <- parse_int(getenv1("SEED", "20260409"), 20260409L)
BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "50"), 50L)
N_WORKERS  <- max(1L, parse_int(getenv1("N_WORKERS", "8"), 8L))
ERR_MODE   <- tolower(getenv1("ERR_MODE", "iid_month"))

DROP_START <- parse_date(getenv1("DROP_START", ""))
DROP_END   <- parse_date(getenv1("DROP_END", ""))
MIN_DATE   <- parse_date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE   <- parse_date(getenv1("MAX_DATE", "2024-12-31"))

RUN_CS         <- parse_bool(getenv1("RUN_CS", "TRUE"), TRUE)
CS_N_SIMS      <- parse_int(getenv1("CS_N_SIMS", "500"), 500L)
CS_BITERS      <- parse_int(getenv1("CS_BITERS", "50"), 50L)
CS_CONTROL_GROUP <- getenv1("CS_CONTROL_GROUP", "notyettreated")
CS_EST_METHOD  <- getenv1("CS_EST_METHOD", "reg")

MIN_STATES_PER_MONTH <- 5L

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
cat("", file = RUN_LOG)

log_line(RUN_LOG, "=== MORTGAGE DELINQUENCY POWER SIMULATION ===")
log_line(RUN_LOG, glue("Start: {Sys.time()}"))
log_line(RUN_LOG, glue("MORTGAGE_FILE: {MORTGAGE_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE: {TREAT_FILE}  TREAT_DATE_COL: {TREAT_DATE_COL}"))
log_line(RUN_LOG, glue("OUTCOME: {OUTCOME}"))
log_line(RUN_LOG, glue("N_SIMS: {N_SIMS}  ALPHA: {ALPHA}  SEED: {SEED}"))
log_line(RUN_LOG, glue("EFFECT_SIZES: {paste(EFFECT_SIZES, collapse=', ')}"))
log_line(RUN_LOG, glue("ERR_MODE: {ERR_MODE}  N_WORKERS: {N_WORKERS}"))
log_line(RUN_LOG, glue("DROP: {ifelse(!is.na(DROP_START), paste0('[', DROP_START, ',', DROP_END, ')'), 'none')}"))
log_line(RUN_LOG, glue("RUN_CS: {RUN_CS}  CS_N_SIMS: {CS_N_SIMS}  CS_BITERS: {CS_BITERS}"))

################################################################################
# LOAD AND BUILD PANEL
################################################################################

cat("Loading mortgage delinquency data...\n")

if (!file.exists(MORTGAGE_FILE)) stop("MORTGAGE_FILE not found: ", MORTGAGE_FILE, call. = FALSE)
if (!file.exists(TREAT_FILE))    stop("TREAT_FILE not found: ", TREAT_FILE, call. = FALSE)

mort_wide <- readr::read_csv(MORTGAGE_FILE, show_col_types = FALSE)
mort_wide <- mort_wide %>% filter(RegionType == "State")

all_cols <- colnames(mort_wide)
month_cols <- grep("^\\d{4}-\\d{2}$", all_cols, value = TRUE)

mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(
    cols = all_of(month_cols),
    names_to = "month_str",
    values_to = "delinq_pct"
  ) %>%
  mutate(
    state_abb  = state_name_to_abb(Name),
    month_date = as.Date(paste0(month_str, "-01")),
    delinq_pct = as.numeric(delinq_pct)
  ) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, delinq_pct)

cat(glue("  Mortgage panel: {nrow(mort_long)} rows, {n_distinct(mort_long$state_abb)} states"), "\n")

# Load treatment schedule
treat_raw <- readr::read_csv(TREAT_FILE, show_col_types = FALSE)
treat_sched <- treat_raw %>%
  transmute(
    state_abb = state_name_to_abb(state),
    treat_start = as.Date(.data[[TREAT_DATE_COL]])
  ) %>%
  filter(!is.na(state_abb))

# Merge
panel0 <- mort_long %>%
  left_join(treat_sched, by = "state_abb")

# Date filters
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)

# Drop window (COVID)
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  n0 <- nrow(panel0)
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date < DROP_END))
  cat(glue("  Dropped COVID window [{DROP_START}, {DROP_END}): {n0 - nrow(panel0)} rows"), "\n")
}

# Balance to common months (all states observed)
n_states_all <- n_distinct(panel0$state_abb)
common_months <- panel0 %>%
  count(month_date, name = "n_states") %>%
  filter(n_states == n_states_all) %>%
  pull(month_date)
panel <- panel0 %>% filter(month_date %in% common_months)

# Create DiD identifiers
panel <- panel %>%
  mutate(
    id = as.integer(as.factor(state_abb)),
    t  = ym_index(month_date),
    g  = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g  = as.integer(g),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = (g > 0L) & (t >= g),
    y = dplyr::case_when(
      OUTCOME == "delinq_pct"     ~ delinq_pct,
      OUTCOME == "log_delinq_pct" ~ log(pmax(delinq_pct, 0.001)),
      TRUE ~ NA_real_
    )
  )

n_states  <- n_distinct(panel$state_abb)
n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
n_never   <- n_distinct(panel$state_abb[panel$g == 0L])
n_months  <- n_distinct(panel$t)

cat(glue("  Panel: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_months} months, {nrow(panel)} obs"), "\n")
log_line(RUN_LOG, glue("Panel: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_months} months, {nrow(panel)} obs"))

panel_summary <- tibble(
  n_states = n_states, n_treated = n_treated, n_never_treated = n_never,
  n_months = n_months, n_obs = nrow(panel),
  min_date = min(panel$month_date), max_date = max(panel$month_date),
  outcome = OUTCOME, treatment = TREAT_DATE_COL
)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

################################################################################
# BASELINE FE FIT + RESIDUAL POOL
################################################################################

cat("Fitting baseline FE on untreated observations...\n")

base_fe <- panel %>% filter(untreated_obs, is.finite(y))

set.seed(SEED)
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)

panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
if (any(!is.finite(panel$yhat))) {
  n_drop <- sum(!is.finite(panel$yhat))
  cat(glue("  WARNING: dropping {n_drop} non-finite yhat rows"), "\n")
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}

base_fe$ehat <- as.numeric(residuals(fe_fit))

# Build residual pool (excluding any exclusion window)
pool_dat <- base_fe

# Month-specific pools
resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
global_pool <- pool_dat$ehat[is.finite(pool_dat$ehat)]

residual_sd <- sd(global_pool)
cat(glue("  Residual SD: {round(residual_sd, 4)}"), "\n")
log_line(RUN_LOG, glue("Residual SD: {round(residual_sd, 4)}; pool size: {length(global_pool)}"))

################################################################################
# ERROR DRAWING
################################################################################

draw_errors_iid_month <- function(tt, resid_pool_by_t, global_pool) {
  vapply(tt, function(tt_i) {
    pool <- resid_pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < MIN_STATES_PER_MONTH) pool <- global_pool
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

################################################################################
# EFFECT SIZE INTERPRETATION
#
# For OUTCOME = "delinq_pct" (levels, ~1-5 pp range):
#   EFFECT_SIZES are ABSOLUTE percentage point changes added to the level.
#   e.g., 0.10 = +0.10 pp increase in delinquency rate
#
# For OUTCOME = "log_delinq_pct" (log):
#   EFFECT_SIZES are proportional changes, effect_log = log(1 + effect_pct)
#   e.g., 0.10 = 10% increase
################################################################################

if (OUTCOME == "delinq_pct") {
  # For levels: effect sizes are in pp. The mean delinq_pct is ~1-4 pp,
  # so 0.05 = 0.05 pp, 0.10 = 0.10 pp, etc.
  # Also express as % of baseline mean for interpretability
  baseline_mean <- mean(base_fe$y, na.rm = TRUE)
  cat(glue("  Baseline mean delinquency: {round(baseline_mean, 3)} pp"), "\n")
  cat(glue("  Effect sizes are in absolute pp: {paste(EFFECT_SIZES, collapse=', ')}"), "\n")
  log_line(RUN_LOG, glue("Baseline mean: {round(baseline_mean, 3)} pp"))

  effect_tbl <- tibble(
    effect_size = EFFECT_SIZES,
    effect_add  = EFFECT_SIZES,
    effect_pct_of_mean = round(100 * EFFECT_SIZES / baseline_mean, 1)
  )
} else {
  # Log outcome: proportional changes
  effect_tbl <- tibble(
    effect_size = EFFECT_SIZES,
    effect_add  = log(1 + EFFECT_SIZES),
    effect_pct_of_mean = round(100 * EFFECT_SIZES, 1)
  )
}

cat(glue("  Effect grid: {nrow(effect_tbl)} sizes"), "\n")

################################################################################
# PART A: TWFE POWER SIMULATION
################################################################################

cat("\n========== TWFE POWER SIMULATION ==========\n")

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

one_sim_twfe <- function(seed, effect_add) {
  set.seed(seed)

  e_draw <- draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_add, 0.0)

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    post_treat = as.integer(panel$post_treat),
    y  = y_sim
  )

  tryCatch({
    est <- fixest::feols(y ~ post_treat | id + t, data = dat,
                         cluster = ~id, warn = FALSE, notes = FALSE)
    ct <- fixest::coeftable(est)
    coef_name <- if ("post_treat" %in% rownames(ct)) "post_treat" else {
      nm <- grep("^post_treat", rownames(ct), value = TRUE)
      if (length(nm) >= 1) nm[1] else NA_character_
    }
    if (is.na(coef_name)) return(list(ok = FALSE, att = NA, se = NA, p = NA))

    att <- unname(ct[coef_name, "Estimate"])
    se  <- unname(ct[coef_name, "Std. Error"])
    p   <- unname(ct[coef_name, "Pr(>|t|)"])

    list(ok = is.finite(att) && is.finite(se) && se > 0 && is.finite(p),
         att = att, se = se, p = p)
  }, error = function(e) {
    list(ok = FALSE, att = NA, se = NA, p = NA)
  })
}

# Parallel setup
use_parallel <- N_WORKERS > 1L
cl <- NULL
if (use_parallel) {
  cat(glue("Starting PSOCK cluster with {N_WORKERS} workers..."), "\n")
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages(library(fixest))
    NULL
  })

  parallel::clusterExport(
    cl,
    varlist = c("panel", "resid_pool_by_t", "global_pool",
                "MIN_STATES_PER_MONTH", "draw_errors_iid_month",
                "one_sim_twfe"),
    envir = environment()
  )
}

twfe_results <- list()

for (k in seq_len(nrow(effect_tbl))) {
  eff_size <- effect_tbl$effect_size[k]
  eff_add  <- effect_tbl$effect_add[k]

  cat(glue("[TWFE] Effect={eff_size} (add={round(eff_add,5)})"), "\n")
  log_line(RUN_LOG, glue("[TWFE] Effect={eff_size} add={round(eff_add,5)}"))

  t0 <- Sys.time()

  n_done <- 0L
  res_rows <- vector("list", N_SIMS)

  while (n_done < N_SIMS) {
    b_lo <- n_done + 1L
    b_hi <- min(N_SIMS, n_done + BATCH_SIZE)
    seeds_batch <- sim_seeds[b_lo:b_hi]

    batch_out <- if (use_parallel) {
      parallel::parLapply(cl, seeds_batch, one_sim_twfe, effect_add = eff_add)
    } else {
      lapply(seeds_batch, function(ss) one_sim_twfe(ss, eff_add))
    }

    res_rows[(n_done + 1L):b_hi] <- batch_out
    n_done <- b_hi

    # Progress every ~500 sims
    if (n_done %% 500 == 0 || n_done == N_SIMS) {
      ok_so_far <- vapply(res_rows[seq_len(n_done)], function(x) isTRUE(x$ok), logical(1))
      p_so_far  <- vapply(res_rows[seq_len(n_done)], function(x) x$p, numeric(1))
      pwr_now <- if (sum(ok_so_far) > 0) mean(p_so_far[ok_so_far] < ALPHA, na.rm = TRUE) else NA
      cat(glue("  {n_done}/{N_SIMS} done, power so far: {round(pwr_now, 3)}"), "\n")
    }
  }

  t1 <- Sys.time()
  elapsed <- round(as.numeric(difftime(t1, t0, units = "secs")), 1)

  ok  <- vapply(res_rows, function(x) isTRUE(x$ok), logical(1))
  p   <- vapply(res_rows, function(x) x$p, numeric(1))
  att <- vapply(res_rows, function(x) x$att, numeric(1))
  se  <- vapply(res_rows, function(x) x$se, numeric(1))

  n_ok <- sum(ok)
  power_val <- if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_

  twfe_results[[k]] <- tibble(
    estimator = "TWFE",
    effect_size = eff_size,
    effect_add = eff_add,
    effect_pct_of_mean = effect_tbl$effect_pct_of_mean[k],
    n_sims = N_SIMS,
    n_ok = n_ok,
    n_fail = N_SIMS - n_ok,
    alpha = ALPHA,
    power = power_val,
    mean_att = if (n_ok > 0) mean(att[ok], na.rm = TRUE) else NA,
    sd_att   = if (n_ok > 1) sd(att[ok], na.rm = TRUE) else NA,
    mean_se  = if (n_ok > 0) mean(se[ok], na.rm = TRUE) else NA,
    se_over_sdatt = if (n_ok > 1) mean(se[ok], na.rm = TRUE) / sd(att[ok], na.rm = TRUE) else NA,
    median_p = if (n_ok > 0) median(p[ok], na.rm = TRUE) else NA,
    elapsed_sec = elapsed
  )

  cat(glue("  Power: {round(power_val, 3)} | mean_se: {round(mean(se[ok], na.rm=TRUE), 4)} | {elapsed}s"), "\n")
  log_line(RUN_LOG, glue("  Power={round(power_val,3)} mean_se={round(mean(se[ok],na.rm=TRUE),4)} elapsed={elapsed}s"))

  # Save incrementally
  safe_write_csv(bind_rows(twfe_results), file.path(OUT_DIR, "twfe_power_by_effect.csv"))
}

twfe_df <- bind_rows(twfe_results)
safe_write_csv(twfe_df, file.path(OUT_DIR, "twfe_power_by_effect.csv"))

# Type I error diagnostic
if (any(abs(twfe_df$effect_size) < 1e-12)) {
  type1 <- twfe_df %>% filter(abs(effect_size) < 1e-12)
  cat(glue("\nTWFE Type I error at effect=0: {round(type1$power, 3)} (nominal: {ALPHA})"), "\n")
  log_line(RUN_LOG, glue("TWFE Type I error: {round(type1$power, 3)}"))
}

# TWFE power curve plot
if (any(is.finite(twfe_df$power))) {
  png(file.path(OUT_DIR, "twfe_power_curve.png"), width = 900, height = 650)
  plot(twfe_df$effect_size, twfe_df$power, type = "b", pch = 19,
       xlab = if (OUTCOME == "delinq_pct") "Effect size (pp)" else "Effect size (proportional)",
       ylab = "Power (rejection rate)",
       ylim = c(0, 1))
  abline(h = 0.80, lty = 2, col = "gray50")
  abline(h = ALPHA, lty = 3, col = "red")
  grid()
  dev.off()
}

################################################################################
# PART B: CS-DiD POWER SIMULATION
################################################################################

if (isTRUE(RUN_CS)) {

  cat("\n========== CS-DiD POWER SIMULATION ==========\n")

  cs_sim_seeds <- SEED + seq_len(CS_N_SIMS) * 20011L

  one_sim_cs <- function(seed, effect_add) {
    set.seed(seed)

    e_draw <- draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
    y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_add, 0.0)

    dat <- data.frame(
      id = panel$id,
      t  = panel$t,
      g  = panel$g,
      y  = y_sim
    )

    tryCatch({
      cs_out <- did::att_gt(
        yname  = "y",
        tname  = "t",
        idname = "id",
        gname  = "g",
        data   = dat,
        control_group = CS_CONTROL_GROUP,
        est_method    = CS_EST_METHOD,
        bstrap        = TRUE,
        biters        = CS_BITERS,
        cband         = FALSE,
        base_period   = "universal",
        allow_unbalanced_panel = TRUE
      )

      agg <- did::aggte(cs_out, type = "simple")

      att <- agg$overall.att
      se  <- agg$overall.se

      # Two-sided p-value from t-stat
      tstat <- att / se
      p <- 2 * pt(-abs(tstat), df = max(1, n_states - 1))

      list(ok = is.finite(att) && is.finite(se) && se > 0 && is.finite(p),
           att = att, se = se, p = p)
    }, error = function(e) {
      list(ok = FALSE, att = NA, se = NA, p = NA, err = conditionMessage(e))
    })
  }

  # For CS, run sequentially (did::att_gt is already somewhat slow)
  # or use parallel if workers are available
  if (use_parallel) {
    parallel::clusterExport(
      cl,
      varlist = c("one_sim_cs", "CS_CONTROL_GROUP", "CS_EST_METHOD",
                   "CS_BITERS", "n_states"),
      envir = environment()
    )
    parallel::clusterEvalQ(cl, {
      suppressPackageStartupMessages(library(did))
      NULL
    })
  }

  cs_results <- list()

  for (k in seq_len(nrow(effect_tbl))) {
    eff_size <- effect_tbl$effect_size[k]
    eff_add  <- effect_tbl$effect_add[k]

    cat(glue("[CS] Effect={eff_size} (add={round(eff_add,5)})"), "\n")
    log_line(RUN_LOG, glue("[CS] Effect={eff_size} add={round(eff_add,5)}"))

    t0 <- Sys.time()

    seeds_cs <- cs_sim_seeds[seq_len(CS_N_SIMS)]

    res_cs <- if (use_parallel) {
      parallel::parLapply(cl, seeds_cs, one_sim_cs, effect_add = eff_add)
    } else {
      lapply(seeds_cs, function(ss) one_sim_cs(ss, eff_add))
    }

    t1 <- Sys.time()
    elapsed <- round(as.numeric(difftime(t1, t0, units = "secs")), 1)

    ok  <- vapply(res_cs, function(x) isTRUE(x$ok), logical(1))
    p   <- vapply(res_cs, function(x) if (is.null(x$p)) NA_real_ else x$p, numeric(1))
    att <- vapply(res_cs, function(x) if (is.null(x$att)) NA_real_ else x$att, numeric(1))
    se  <- vapply(res_cs, function(x) if (is.null(x$se)) NA_real_ else x$se, numeric(1))

    n_ok <- sum(ok)
    power_val <- if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_

    cs_results[[k]] <- tibble(
      estimator = "CS-DiD",
      effect_size = eff_size,
      effect_add = eff_add,
      effect_pct_of_mean = effect_tbl$effect_pct_of_mean[k],
      n_sims = CS_N_SIMS,
      n_ok = n_ok,
      n_fail = CS_N_SIMS - n_ok,
      alpha = ALPHA,
      power = power_val,
      mean_att = if (n_ok > 0) mean(att[ok], na.rm = TRUE) else NA,
      sd_att   = if (n_ok > 1) sd(att[ok], na.rm = TRUE) else NA,
      mean_se  = if (n_ok > 0) mean(se[ok], na.rm = TRUE) else NA,
      se_over_sdatt = if (n_ok > 1) mean(se[ok], na.rm = TRUE) / sd(att[ok], na.rm = TRUE) else NA,
      median_p = if (n_ok > 0) median(p[ok], na.rm = TRUE) else NA,
      elapsed_sec = elapsed
    )

    cat(glue("  Power: {round(power_val, 3)} | mean_se: {if(n_ok>0) round(mean(se[ok],na.rm=TRUE),4) else NA} | ok: {n_ok}/{CS_N_SIMS} | {elapsed}s"), "\n")
    log_line(RUN_LOG, glue("  Power={round(power_val,3)} n_ok={n_ok} elapsed={elapsed}s"))

    safe_write_csv(bind_rows(cs_results), file.path(OUT_DIR, "cs_power_by_effect.csv"))
  }

  cs_df <- bind_rows(cs_results)
  safe_write_csv(cs_df, file.path(OUT_DIR, "cs_power_by_effect.csv"))

  # CS Type I error
  if (any(abs(cs_df$effect_size) < 1e-12)) {
    cs_type1 <- cs_df %>% filter(abs(effect_size) < 1e-12)
    cat(glue("\nCS-DiD Type I error at effect=0: {round(cs_type1$power, 3)} (nominal: {ALPHA})"), "\n")
    log_line(RUN_LOG, glue("CS Type I error: {round(cs_type1$power, 3)}"))
    cat(glue("CS-DiD SE/SD(ATT): {round(cs_type1$se_over_sdatt, 3)} (should be ~1.0)"), "\n")
    log_line(RUN_LOG, glue("CS SE/SD(ATT): {round(cs_type1$se_over_sdatt, 3)}"))
  }

  # CS power curve plot
  if (any(is.finite(cs_df$power))) {
    png(file.path(OUT_DIR, "cs_power_curve.png"), width = 900, height = 650)
    plot(cs_df$effect_size, cs_df$power, type = "b", pch = 19, col = "blue",
         xlab = if (OUTCOME == "delinq_pct") "Effect size (pp)" else "Effect size (proportional)",
         ylab = "Power (rejection rate)",
         ylim = c(0, 1))
    abline(h = 0.80, lty = 2, col = "gray50")
    abline(h = ALPHA, lty = 3, col = "red")
    grid()
    dev.off()
  }
}

################################################################################
# COMBINED RESULTS
################################################################################

all_power <- if (exists("cs_df") && nrow(cs_df) > 0) {
  bind_rows(twfe_df, cs_df)
} else {
  twfe_df
}

safe_write_csv(all_power, file.path(OUT_DIR, "power_by_effect_all.csv"))

# Combined power curve
if (exists("cs_df") && nrow(cs_df) > 0 && any(is.finite(cs_df$power))) {
  png(file.path(OUT_DIR, "power_curve_combined.png"), width = 900, height = 650)
  ylim <- c(0, 1)
  plot(twfe_df$effect_size, twfe_df$power, type = "b", pch = 19, col = "black",
       xlab = if (OUTCOME == "delinq_pct") "Effect size (pp)" else "Effect size (proportional)",
       ylab = "Power (rejection rate)",
       ylim = ylim)
  lines(cs_df$effect_size, cs_df$power, type = "b", pch = 17, col = "blue")
  abline(h = 0.80, lty = 2, col = "gray50")
  abline(h = ALPHA, lty = 3, col = "red")
  legend("bottomright", legend = c("TWFE", "CS-DiD"),
         col = c("black", "blue"), pch = c(19, 17), lty = 1)
  grid()
  dev.off()
}

# Summary
cat("\n========== SUMMARY ==========\n")
cat(glue("Panel: {n_states} states, {n_months} months"), "\n")
cat(glue("Outcome: {OUTCOME}"), "\n")

cat("\nTWFE Power:\n")
for (i in seq_len(nrow(twfe_df))) {
  r <- twfe_df[i, ]
  cat(glue("  Effect={r$effect_size}: power={round(r$power, 3)} mean_se={round(r$mean_se, 4)}"), "\n")
}

if (exists("cs_df") && nrow(cs_df) > 0) {
  cat("\nCS-DiD Power:\n")
  for (i in seq_len(nrow(cs_df))) {
    r <- cs_df[i, ]
    cat(glue("  Effect={r$effect_size}: power={round(r$power, 3)} mean_se={if(!is.na(r$mean_se)) round(r$mean_se, 4) else NA}"), "\n")
  }
}

# MDE estimate (effect at which power >= 0.80)
twfe_mde <- twfe_df %>% filter(power >= 0.80, effect_size > 0) %>% slice_min(effect_size, n = 1)
if (nrow(twfe_mde) > 0) {
  cat(glue("\nTWFE MDE (80% power): {twfe_mde$effect_size} {if(OUTCOME=='delinq_pct') 'pp' else '(proportional)'}"), "\n")
  log_line(RUN_LOG, glue("TWFE MDE: {twfe_mde$effect_size}"))
} else {
  cat("\nTWFE: 80% power not reached at any tested effect size.\n")
  log_line(RUN_LOG, "TWFE: 80% power not reached")
}

if (exists("cs_df") && nrow(cs_df) > 0) {
  cs_mde <- cs_df %>% filter(power >= 0.80, effect_size > 0) %>% slice_min(effect_size, n = 1)
  if (nrow(cs_mde) > 0) {
    cat(glue("CS-DiD MDE (80% power): {cs_mde$effect_size} {if(OUTCOME=='delinq_pct') 'pp' else '(proportional)'}"), "\n")
    log_line(RUN_LOG, glue("CS MDE: {cs_mde$effect_size}"))
  } else {
    cat("CS-DiD: 80% power not reached at any tested effect size.\n")
    log_line(RUN_LOG, "CS: 80% power not reached")
  }
}

log_line(RUN_LOG, glue("=== DONE: {Sys.time()} ==="))
cat(glue("\nOutputs in: {OUT_DIR}"), "\n")
