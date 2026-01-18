#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_reg_statepanel_staggered_parallel.R (REVISED)
#
# Callaway-Sant'Anna DiD power simulation using regression adjustment estimator.
# Matches structure and safeguards of power_simulation_twfe_statepanel_staggered_parallel_fixed.R
#
# REVISION CHECKLIST:
# [X] Use est_method="reg" (avoids fastglm IPW bug)
# [X] Match TWFE panel build (county->state aggregation with state fallback)
# [X] Match TWFE FE fitting (untreated only, drop months with no untreated obs)
# [X] Match TWFE residual pooling (MIN_STATES_PER_MONTH, EXCLUDE/DROP windows)
# [X] Match TWFE error generation (iid_month and ar1 with same logic)
# [X] Effect sizes as proportional: effect_log = log1p(effect_pct)
# [X] CS-specific: use did::att_gt with reg estimator + aggte(type="simple")
# [X] Rejection rule: use provided p-value or compute with t-distribution
# [X] DID_CONTROL_GROUP default "notyettreated" (matches main analysis)
# [X] Parallel+batching with PROGRESS_BATCHES like TWFE
# [X] Fail-fast: abort if fail_rate > 0.25, write errors_by_effect.csv
# [X] Comprehensive logging to run.log
# [X] Same output files as TWFE (treatment_schedule, panel_summary, power_by_effect, etc.)
#
# HOW TO RUN:
#
# Quick tiny test (local, N_SIMS=50, serial):
#   export DATA_FILE=combined_monthly_panel.csv
#   export TREAT_FILE=state_month_panel_with_treatment.csv
#   export N_SIMS=50
#   export N_WORKERS=1
#   export EFFECT_PCTS="0,0.05"
#   Rscript power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R
#
# Full run (Della, N_SIMS=2000, exclude COVID):
#   export DATA_FILE=combined_monthly_panel.csv
#   export TREAT_FILE=state_month_panel_with_treatment.csv
#   export N_SIMS=2000
#   export N_WORKERS=20
#   export EFFECT_PCTS="0,0.05,0.10,0.15,0.20"
#   export EXCLUDE_START=2020-03-01
#   export EXCLUDE_END=2021-07-01
#   export ALPHA=0.05
#   export DID_CONTROL_GROUP=notyettreated
#   export DID_BSTRAP=TRUE
#   export DID_BITERS=199
#   Rscript power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R
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

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
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

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d < end)
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

BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "100"), 100L)
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
if (!is.finite(MIN_STATES_PER_MONTH) || MIN_STATES_PER_MONTH < 2L) MIN_STATES_PER_MONTH <- 2L

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

# Windows
EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))
EXCLUDE_END   <- as.Date(getenv1("EXCLUDE_END", ""))
DROP_START <- as.Date(getenv1("DROP_START", ""))
DROP_END   <- as.Date(getenv1("DROP_END", ""))

# State/date filtering
EXCLUDE_STATES <- getenv1("EXCLUDE_STATES", "")
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}
EXCLUDE_STATES_VEC <- parse_state_list(EXCLUDE_STATES)

# DID options - CRITICAL: Use est_method="reg" to avoid fastglm bug
# Default control group to "notyettreated" to match main analysis
did_method <- "reg"
did_control_group <- getenv1("DID_CONTROL_GROUP", "notyettreated")
if (!did_control_group %in% c("nevertreated", "notyettreated")) {
  stop(glue("DID_CONTROL_GROUP must be nevertreated or notyettreated; got {did_control_group}"), call. = FALSE)
}
did_bstrap <- parse_bool(getenv1("DID_BSTRAP", "TRUE"), TRUE)
did_biters <- parse_int(getenv1("DID_BITERS", "199"), 199L)
if (!is.finite(did_biters) || did_biters < 10L) did_biters <- 199L
did_cband  <- parse_bool(getenv1("DID_CBAND", "FALSE"), FALSE)
did_allow_unbalanced <- parse_bool(getenv1("DID_ALLOW_UNBALANCED_PANEL", "TRUE"), TRUE)

AGG_TYPE <- getenv1("AGG_TYPE", "simple")
if (!AGG_TYPE %in% c("simple", "dynamic")) AGG_TYPE <- "simple"

# ----------------------------- logging ----------------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
file.create(file.path(OUT_DIR, "STARTED.txt"))

log_line(RUN_LOG, "=== CS DiD POWER SIM (REG ESTIMATOR) ===")
log_line(RUN_LOG, glue("SCRIPT: {basename(commandArgs(trailingOnly = FALSE)[1])}"))
log_line(RUN_LOG, glue("WD: {getwd()}"))
log_line(RUN_LOG, glue("R: {R.version.string}"))
log_line(RUN_LOG, glue("DATA_FILE: {DATA_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE: {TREAT_FILE}"))
log_line(RUN_LOG, glue("OUT_DIR: {OUT_DIR}"))
log_line(RUN_LOG, glue("OUTCOME: {OUTCOME}  RATE_EPS={RATE_EPS}"))
log_line(RUN_LOG, glue("N_SIMS: {N_SIMS}  BATCH_SIZE={BATCH_SIZE}  ALPHA={ALPHA}  SEED={SEED}"))
log_line(RUN_LOG, glue("EFFECT_PCTS: {paste(EFFECT_PCTS, collapse=', ')}"))
log_line(RUN_LOG, glue("N_WORKERS: {N_WORKERS}  SLURM_CPUS_PER_TASK={getenv1('SLURM_CPUS_PER_TASK','')}"))
log_line(RUN_LOG, glue("DID: est_method=reg, control_group={did_control_group}, bstrap={did_bstrap}, biters={did_biters}, cband={did_cband}, allow_unbalanced={did_allow_unbalanced}"))
log_line(RUN_LOG, glue("DID: AGG_TYPE={AGG_TYPE}"))
log_line(RUN_LOG, glue("ERR_MODE: {ERR_MODE} (rho={ifelse(is.finite(ERR_AR1_RHO), ERR_AR1_RHO, 'estimate')}, clip={ERR_AR1_CLIP}) MIN_STATES_PER_MONTH={MIN_STATES_PER_MONTH}"))
exclude_str <- if (!is.na(EXCLUDE_START) && !is.na(EXCLUDE_END)) glue('[{EXCLUDE_START},{EXCLUDE_END})') else 'none'
log_line(RUN_LOG, glue("EXCLUDE (resid pool only): {exclude_str}"))
log_line(RUN_LOG, glue("DROP (analysis panel): {if (!is.na(DROP_START) && !is.na(DROP_END)) glue('[{DROP_START},{DROP_END})') else 'none'}"))
log_line(RUN_LOG, glue("FILTERS: EXCLUDE_STATES={ifelse(nzchar(EXCLUDE_STATES), EXCLUDE_STATES, 'none')}  MAX_DATE={ifelse(is.finite(MAX_DATE), as.character(MAX_DATE), 'none')}"))
log_line(RUN_LOG, "========================================")

# ----------------------------- load + build panel -----------------------------

if (!file.exists(DATA_FILE)) stop(glue("DATA_FILE not found: {DATA_FILE}"), call. = FALSE)
if (!file.exists(TREAT_FILE)) stop(glue("TREAT_FILE not found: {TREAT_FILE}"), call. = FALSE)

# Map geo_id -> state abbreviation
state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

# FIPS state lookup
fips_to_state_abb <- function(state_fips) {
  lookup <- c(
    `1`="AL", `2`="AK", `4`="AZ", `5`="AR", `6`="CA", `8`="CO", `9`="CT",
    `10`="DE", `11`="DC", `12`="FL", `13`="GA", `15`="HI", `16`="ID",
    `17`="IL", `18`="IN", `19`="IA", `20`="KS", `21`="KY", `22`="LA",
    `23`="ME", `24`="MD", `25`="MA", `26`="MI", `27`="MN", `28`="MS",
    `29`="MO", `30`="MT", `31`="NE", `32`="NV", `33`="NH", `34`="NJ",
    `35`="NM", `36`="NY", `37`="NC", `38`="ND", `39`="OH", `40`="OK",
    `41`="OR", `42`="PA", `44`="RI", `45`="SC", `46`="SD", `47`="TN",
    `48`="TX", `49`="UT", `50`="VT", `51`="VA", `53`="WA", `54`="WV",
    `55`="WI", `56`="WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

# County -> state-month aggregation with state fallback (matches TWFE)
build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      filings_per_1k_renters = if_else(
        is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        as.numeric(NA)
      )
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
      filings_per_1k_renters = as.numeric(filings_per_1k_renters)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

log_line(RUN_LOG, "Loading and building panel...")
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

state_list <- sort(unique(panel_raw$state_abb))
safe_write_csv(tibble(state_abb = state_list), file.path(OUT_DIR, "states_in_panel_raw.csv"))
if (length(state_list) < 30) stop(glue("Panel build produced only {length(state_list)} states."), call. = FALSE)

treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  ) %>%
  arrange(state_abb, month_date)

panel <- panel_raw %>%
  left_join(treat, by = c("state_abb","month_date")) %>%
  filter(state_abb %in% unique(treat$state_abb))

# Apply optional state and date filters
n_rows_initial <- nrow(panel)
log_line(RUN_LOG, glue("Initial panel rows: {n_rows_initial}"))

if (length(EXCLUDE_STATES_VEC) > 0) {
  n_before <- n_distinct(panel$state_abb)
  n_rows_before <- nrow(panel)
  panel <- panel %>% filter(!state_abb %in% EXCLUDE_STATES_VEC)
  n_after <- n_distinct(panel$state_abb)
  n_rows_after <- nrow(panel)
  cat(glue("Excluded {length(EXCLUDE_STATES_VEC)} state(s): {paste(EXCLUDE_STATES_VEC, collapse=', ')}"), "\n")
  cat(glue("States: {n_before} -> {n_after}; rows: {n_rows_before} -> {n_rows_after}"), "\n")
  log_line(RUN_LOG, glue("Excluded states: {paste(EXCLUDE_STATES_VEC, collapse=', ')} ({n_before} -> {n_after} states; {n_rows_before} -> {n_rows_after} rows)"))
}

if (is.finite(MAX_DATE)) {
  n_before <- nrow(panel)
  panel <- panel %>% filter(month_date <= MAX_DATE)
  n_after <- nrow(panel)
  cat(glue("Filtered to MAX_DATE={MAX_DATE}: {n_before} -> {n_after} rows"), "\n")
  log_line(RUN_LOG, glue("MAX_DATE filter: {MAX_DATE} ({n_before} -> {n_after} rows)"))
}

if (all(is.na(panel$treat_start))) stop("treat_start missing for all rows after merge.", call. = FALSE)

# One adoption date per state
panel <- panel %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup()

# Optional drop window from analysis panel entirely
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  keep <- !in_window(panel$month_date, DROP_START, DROP_END)
  panel <- panel[keep, , drop = FALSE]
}

panel <- panel %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = (g > 0L) & (t >= g)
  )

# Guard: g constant within state
g_bad <- panel %>% group_by(state_abb) %>% summarise(ng = n_distinct(g), .groups="drop") %>% filter(ng != 1)
if (nrow(g_bad) > 0) stop("g is not constant within state.", call. = FALSE)

sched <- panel %>%
  group_by(state_abb) %>%
  summarise(
    g = first(g),
    treat_start = first(treat_start_state),
    ever_treated = first(g) > 0L,
    .groups = "drop"
  )

n_states <- n_distinct(panel$state_abb)
n_switch <- sum(sched$ever_treated)
n_never  <- n_states - n_switch

safe_write_csv(sched, file.path(OUT_DIR, "treatment_schedule.csv"))

panel_summary <- tibble(
  n_states = n_states,
  n_switchers = n_switch,
  n_never_treated = n_never,
  n_rows = nrow(panel),
  min_month = min(panel$month_date, na.rm = TRUE),
  max_month = max(panel$month_date, na.rm = TRUE),
  n_months = n_distinct(panel$month_date),
  share_untreated_obs = mean(panel$untreated_obs, na.rm = TRUE)
)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

n_rows_before_fe_fit <- nrow(panel)
log_line(RUN_LOG, glue("Panel before FE fit: states={n_states} (switchers={n_switch}, never={n_never}); months={panel_summary$n_months}; rows={n_rows_before_fe_fit}"))

# ----------------------------- outcome ----------------------------------------

if (OUTCOME == "log1p_filings_count") {
  panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
} else if (OUTCOME == "log1p_rate") {
  if (!("filings_per_1k_renters" %in% names(panel))) stop("filings_per_1k_renters missing", call. = FALSE)
  panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + RATE_EPS))
} else {
  stop(glue("Unknown OUTCOME: {OUTCOME}"), call. = FALSE)
}

# ----------------------------- baseline FE + residual pool --------------------

# FE fit sample: untreated obs only (matches TWFE)
base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))

# Ensure at least one untreated obs per month (for time FE predictions)
untreated_by_t <- base_fe %>% count(t, name = "n_untreated")
missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
if (length(missing_t) > 0) {
  log_line(RUN_LOG, glue("WARNING: dropping {length(missing_t)} months with zero untreated obs (needed for FE)."))
  panel   <- panel   %>% filter(!t %in% missing_t)
  base_fe <- base_fe %>% filter(!t %in% missing_t)
}

set.seed(SEED)
log_line(RUN_LOG, "Fitting FE on untreated observations: y ~ 1 | id + t")
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)

panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
n_rows_before_yhat_drop <- nrow(panel)

if (any(!is.finite(panel$yhat))) {
  n_non_finite <- sum(!is.finite(panel$yhat))
  log_line(RUN_LOG, glue("WARNING: {n_non_finite} non-finite yhat rows after FE prediction; dropping them."))
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  n_rows_after_yhat_drop <- nrow(panel)
  log_line(RUN_LOG, glue("Rows after dropping non-finite yhat: {n_rows_before_yhat_drop} -> {n_rows_after_yhat_drop}"))
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
} else {
  log_line(RUN_LOG, glue("All yhat values finite after FE prediction (no rows dropped)."))
}

n_rows_final_analysis <- nrow(panel)
log_line(RUN_LOG, glue("Final analysis panel N: {n_rows_final_analysis}"))

# Residuals on FE fit sample
base_fe$ehat <- as.numeric(residuals(fe_fit))

# Build residual pool with exclusion window and MIN_STATES_PER_MONTH threshold (matches TWFE)
n_untreated_before_exclude <- nrow(base_fe)
exclude_active <- !is.na(EXCLUDE_START) && !is.na(EXCLUDE_END)

pool_dat_before_month_filter <- if (exclude_active) {
  base_fe %>% filter(!in_window(month_date, EXCLUDE_START, EXCLUDE_END))
} else {
  base_fe
}
n_untreated_after_exclude <- nrow(pool_dat_before_month_filter)

# Count states per month and filter months with insufficient untreated states
month_state_counts <- pool_dat_before_month_filter %>%
  group_by(month_date, t) %>%
  summarise(n_states = n_distinct(state_abb), .groups = "drop")

months_retained <- month_state_counts %>%
  filter(n_states >= MIN_STATES_PER_MONTH)

n_months_retained <- nrow(months_retained)
n_months_fallback_global <- nrow(month_state_counts) - n_months_retained

pool_dat <- pool_dat_before_month_filter %>%
  filter(t %in% months_retained$t)

# Pools by t
resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
global_pool <- pool_dat$ehat
global_pool <- global_pool[is.finite(global_pool)]
if (length(global_pool) < 20) stop("Too few finite residuals in global pool.", call. = FALSE)

log_line(RUN_LOG, glue("Residual pool construction:"))
log_line(RUN_LOG, glue("  Untreated obs before exclusion window: {n_untreated_before_exclude}"))
if (exclude_active) {
  log_line(RUN_LOG, glue("  Exclusion window [{EXCLUDE_START}, {EXCLUDE_END}): dropped {n_untreated_before_exclude - n_untreated_after_exclude} obs"))
  log_line(RUN_LOG, glue("  Untreated obs after exclusion: {n_untreated_after_exclude}"))
} else {
  log_line(RUN_LOG, glue("  No exclusion window applied"))
}
log_line(RUN_LOG, glue("  MIN_STATES_PER_MONTH threshold: {MIN_STATES_PER_MONTH}"))
log_line(RUN_LOG, glue("  Months with >={MIN_STATES_PER_MONTH} untreated states (month-specific pool): {n_months_retained}"))
log_line(RUN_LOG, glue("  Months with <{MIN_STATES_PER_MONTH} untreated states (fallback to global pool): {n_months_fallback_global}"))
log_line(RUN_LOG, glue("  Final residual pool size: {nrow(pool_dat)} obs across {n_months_retained} months; ERR_MODE={ERR_MODE}"))

# AR(1) calibration objects (matches TWFE)
rho_used <- NA_real_
sigma_u  <- NA_real_
sd_row   <- NULL
idx_by_id <- NULL
std_pool_by_t <- NULL
std_global_pool <- NULL

if (ERR_MODE == "ar1") {
  log_line(RUN_LOG, "Calibrating AR(1) on standardized untreated residuals (post-exclusion).")

  sd_by_t <- pool_dat %>%
    group_by(t) %>%
    summarise(n = dplyr::n(), sd_e = sd(ehat, na.rm = TRUE), .groups = "drop")

  sd_global <- sd(global_pool, na.rm = TRUE)
  if (!is.finite(sd_global) || sd_global <= 0) sd_global <- 1

  sd_by_t <- sd_by_t %>%
    mutate(sd_e = if_else(is.finite(sd_e) & sd_e > 1e-8 & n >= MIN_STATES_PER_MONTH, sd_e, sd_global))

  sd_map <- setNames(sd_by_t$sd_e, as.character(sd_by_t$t))

  pool_dat <- pool_dat %>%
    mutate(
      sd_t = dplyr::coalesce(unname(sd_map[as.character(t)]), sd_global),
      sd_t = if_else(is.finite(sd_t) & sd_t > 0, sd_t, sd_global),
      z = ehat / sd_t
    )

  std_pool_by_t <- split(pool_dat$z, pool_dat$t)
  std_global_pool <- pool_dat$z
  std_global_pool <- std_global_pool[is.finite(std_global_pool)]
  if (length(std_global_pool) < 20) stop("Too few standardized residuals for AR(1).", call. = FALSE)

  tmp <- pool_dat %>%
    arrange(state_abb, t) %>%
    group_by(state_abb) %>%
    mutate(z_lag = lag(z)) %>%
    ungroup() %>%
    filter(is.finite(z_lag))

  if (nrow(tmp) < 50) {
    rho_used <- 0.5
    log_line(RUN_LOG, glue("  Too few pairs for AR(1) estimation; using rho={rho_used}"))
  } else {
    if (is.finite(ERR_AR1_RHO)) {
      rho_used <- ERR_AR1_RHO
      log_line(RUN_LOG, glue("  Using user-specified rho={rho_used}"))
    } else {
      ar1_lm <- lm(z ~ z_lag - 1, data = tmp)
      rho_est <- coef(ar1_lm)[1]
      rho_used <- max(-0.99, min(ERR_AR1_CLIP, rho_est))
      log_line(RUN_LOG, glue("  Estimated rho={round(rho_est,3)}, clipped to rho={round(rho_used,3)}"))
    }
  }

  sigma_u <- sqrt(1 - rho_used^2)

  sd_by_id <- base_fe %>%
    group_by(state_abb) %>%
    summarise(sd_e = sd(ehat, na.rm = TRUE), .groups = "drop") %>%
    mutate(sd_e = if_else(is.finite(sd_e) & sd_e > 0, sd_e, sd_global))

  panel <- panel %>% left_join(sd_by_id, by = "state_abb")
  panel$sd_e[!is.finite(panel$sd_e) | panel$sd_e <= 0] <- sd_global

  sd_row <- panel$sd_e
  idx_by_id <- split(seq_len(nrow(panel)), panel$id)

  log_line(RUN_LOG, glue("  AR(1) calibration: rho={round(rho_used,3)}, sigma_u={round(sigma_u,3)}"))
}

# ----------------------------- error generation functions ---------------------

draw_errors_iid_month <- function(t_vec, pool_by_t, fallback_pool, min_states) {
  e <- numeric(length(t_vec))
  for (t_val in unique(t_vec)) {
    idx <- which(t_vec == t_val)
    pool <- pool_by_t[[as.character(t_val)]]
    if (is.null(pool) || length(pool) < min_states) pool <- fallback_pool
    e[idx] <- sample(pool, size = length(idx), replace = TRUE)
  }
  e
}

draw_errors_ar1 <- function(t_vec, idx_by_id, std_pool_by_t, std_global_pool, sd_vec, rho, sigma_u, min_states) {
  e_draw <- numeric(length(t_vec))

  for (id_val in names(idx_by_id)) {
    idx <- idx_by_id[[id_val]]
    n_t <- length(idx)
    x <- numeric(n_t)
    t_seq <- t_vec[idx]

    # First period
    t_first <- t_seq[1]
    pool_first <- std_pool_by_t[[as.character(t_first)]]
    if (is.null(pool_first) || length(pool_first) < min_states) pool_first <- std_global_pool
    x[1] <- sample(pool_first, 1)

    # Subsequent periods: AR(1)
    if (n_t > 1) {
      for (i in 2:n_t) {
        t_curr <- t_seq[i]
        pool_curr <- std_pool_by_t[[as.character(t_curr)]]
        if (is.null(pool_curr) || length(pool_curr) < min_states) pool_curr <- std_global_pool

        u <- sample(pool_curr, 1)
        x[i] <- rho * x[i-1] + sigma_u * u
      }
    }

    e_draw[idx] <- x * sd_vec[idx]
  }

  e_draw
}

# ----------------------------- one simulation ---------------------------------

one_sim_cs <- function(seed, effect_log) {
  set.seed(seed)

  e_draw <- if (ERR_MODE == "iid_month") {
    draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool, MIN_STATES_PER_MONTH)
  } else {
    draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool, sd_row, rho_used, sigma_u, MIN_STATES_PER_MONTH)
  }

  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_log, 0.0)

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    g  = panel$g,
    y  = y_sim
  )

  out <- tryCatch({
    est <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat,
      panel = TRUE,
      control_group = did_control_group,
      allow_unbalanced_panel = did_allow_unbalanced,
      est_method = "reg",
      faster_mode = FALSE,
      bstrap = did_bstrap,
      biters = did_biters,
      cband = did_cband,
      clustervars = "id"
    )

    agg <- did::aggte(est, type = AGG_TYPE, na.rm = TRUE)

    att <- as.numeric(agg$overall.att)
    se  <- as.numeric(agg$overall.se)

    # ROBUST P-VALUE COMPUTATION
    # DO NOT trust agg$overall.pval - compute p-value directly from z-statistic
    # Use two-sided test: H0: att = 0 vs H1: att != 0
    # Bootstrap SEs are asymptotically normal, so use normal distribution (matches did package)
    p <- NA_real_
    if (is.finite(att) && is.finite(se) && se > 0) {
      z_stat <- att / se
      # Two-sided p-value with normal distribution (standard for bootstrap inference)
      p <- 2 * pnorm(-abs(z_stat))
    }

    list(ok = is.finite(att) && is.finite(se) && se > 0 && is.finite(p),
         att = att, se = se, p = p)
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = conditionMessage(e))
  })

  if (!isTRUE(out$ok)) {
    if (is.null(out$err) || !nzchar(out$err)) out$err <- "cs_reg failed"
  }
  out
}

one_sim_cs_worker <- function(seed, eff_log) one_sim_cs(seed, eff_log)

# ----------------------------- parallel setup ---------------------------------

cl <- NULL
if (use_parallel) {
  log_line(RUN_LOG, glue("Parallel: starting PSOCK cluster with {N_WORKERS} workers"))
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster.log"))
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(did)
    })
    NULL
  })

  parallel::clusterExport(
    cl,
    varlist = c(
      "panel","resid_pool_by_t","global_pool","MIN_STATES_PER_MONTH","n_states",
      "ERR_MODE","idx_by_id","std_pool_by_t","std_global_pool","sd_row","rho_used","sigma_u",
      "did_control_group","did_allow_unbalanced","did_bstrap","did_biters","did_cband","AGG_TYPE",
      "draw_errors_iid_month","draw_errors_ar1","one_sim_cs","one_sim_cs_worker"
    ),
    envir = environment()
  )
}

# ----------------------------- run simulation ---------------------------------

PROGRESS_BATCHES <- file.path(OUT_DIR, "progress_batches.csv")
if (!file.exists(PROGRESS_BATCHES)) {
  append_csv(tibble(
    ts = character(),
    effect_pct = double(),
    effect_log = double(),
    batch_lo = integer(),
    batch_hi = integer(),
    n_done = integer(),
    n_sims = integer(),
    ok_cum = integer(),
    fail_cum = integer(),
    fail_rate_cum = double(),
    power_so_far = double(),
    mean_se_so_far = double()
  ), PROGRESS_BATCHES)
}

all_draws <- list()
errors_by_effect <- list()

for (eff_pct in EFFECT_PCTS) {
  # Effect size as proportional change: effect_log = log1p(eff_pct)
  effect_log <- log1p(eff_pct)

  log_line(RUN_LOG, "")
  log_line(RUN_LOG, glue("======== effect_pct={eff_pct} (effect_log={round(effect_log,4)}) ========"))

  set.seed(SEED + as.integer(eff_pct * 1000))
  seeds <- sample.int(1e8, N_SIMS)

  n_batches <- ceiling(N_SIMS / BATCH_SIZE)
  results_eff <- vector("list", N_SIMS)

  ok_cum <- 0L
  fail_cum <- 0L
  p_cum <- numeric()

  # NULL DIAGNOSTIC: Save first 200 p-values for effect_pct = 0
  null_pvals_diagnostic <- if (eff_pct == 0) numeric() else NULL

  for (b in seq_len(n_batches)) {
    batch_lo <- (b - 1) * BATCH_SIZE + 1L
    batch_hi <- min(b * BATCH_SIZE, N_SIMS)
    batch_size <- batch_hi - batch_lo + 1L

    batch_seeds <- seeds[batch_lo:batch_hi]

    t0 <- Sys.time()
    if (use_parallel) {
      # Pass effect_log to each worker by creating a wrapper that captures it
      eff_log_fixed <- effect_log
      batch_results <- parallel::parLapply(cl, batch_seeds, function(s, elog) {
        one_sim_cs_worker(s, elog)
      }, elog = eff_log_fixed)
    } else {
      batch_results <- lapply(batch_seeds, function(s) one_sim_cs(s, effect_log))
    }
    t1 <- Sys.time()

    results_eff[batch_lo:batch_hi] <- batch_results

    # Update cumulative stats
    batch_ok <- sapply(batch_results, function(r) isTRUE(r$ok))
    batch_p  <- sapply(batch_results, function(r) r$p)

    ok_cum <- ok_cum + sum(batch_ok)
    fail_cum <- fail_cum + sum(!batch_ok)
    p_cum <- c(p_cum, batch_p[batch_ok])

    # NULL DIAGNOSTIC: Collect first 200 p-values for effect_pct = 0
    if (!is.null(null_pvals_diagnostic) && length(null_pvals_diagnostic) < 200) {
      new_pvals <- batch_p[batch_ok]
      new_pvals <- new_pvals[is.finite(new_pvals)]
      n_needed <- 200 - length(null_pvals_diagnostic)
      if (length(new_pvals) > 0) {
        null_pvals_diagnostic <- c(null_pvals_diagnostic, head(new_pvals, n_needed))
      }
    }

    fail_rate_cum <- fail_cum / (ok_cum + fail_cum)
    power_so_far <- if (length(p_cum) > 0) mean(p_cum < ALPHA, na.rm = TRUE) else NA_real_

    se_vals <- sapply(batch_results, function(r) if (isTRUE(r$ok)) r$se else NA_real_)
    mean_se_so_far <- mean(se_vals, na.rm = TRUE)

    append_csv(tibble(
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      effect_pct = eff_pct,
      effect_log = effect_log,
      batch_lo = batch_lo,
      batch_hi = batch_hi,
      n_done = batch_hi,
      n_sims = N_SIMS,
      ok_cum = ok_cum,
      fail_cum = fail_cum,
      fail_rate_cum = fail_rate_cum,
      power_so_far = power_so_far,
      mean_se_so_far = mean_se_so_far
    ), PROGRESS_BATCHES)

    # Print to console after EVERY batch (like TWFE)
    cat(glue("[{format(Sys.time(), '%H:%M:%S')}] eff={eff_pct} batch={batch_lo}-{batch_hi} ok={ok_cum}/{batch_hi} power={ifelse(is.finite(power_so_far), round(power_so_far,3), NA)}\n"))
    flush.console()

    # Log to file after EVERY batch (like TWFE)
    log_line(RUN_LOG, glue("Batch {batch_lo}-{batch_hi}/{N_SIMS}: elapsed={round(as.numeric(difftime(t1,t0,units='secs')),1)}s"))
  }

  # Collect errors
  error_msgs <- character()
  for (r in results_eff) {
    if (!isTRUE(r$ok)) {
      err_msg <- r$err
      if (is.null(err_msg) || !nzchar(err_msg)) err_msg <- "unknown error"
      error_msgs <- c(error_msgs, err_msg)
    }
  }

  if (length(error_msgs) > 0) {
    err_tbl <- sort(table(error_msgs), decreasing = TRUE)
    errors_by_effect[[length(errors_by_effect) + 1]] <- tibble(
      effect_pct = eff_pct,
      error = names(err_tbl),
      count = as.integer(err_tbl)
    )
  }

  # Fail-fast: abort if fail_rate > 0.25
  if (fail_rate_cum > 0.25) {
    log_line(RUN_LOG, glue("ERROR: Fail rate {round(100*fail_rate_cum,1)}% > 25% at effect={eff_pct}"))
    log_line(RUN_LOG, "Top 10 errors:")
    if (length(error_msgs) > 0) {
      err_tbl <- head(sort(table(error_msgs), decreasing = TRUE), 10)
      for (i in seq_along(err_tbl)) {
        log_line(RUN_LOG, glue("  {i}. ({err_tbl[i]} times): {names(err_tbl)[i]}"))
      }
    }
    stop(glue("Simulation aborted: fail_rate > 25% at effect={eff_pct}. See run.log for details."), call. = FALSE)
  }

  # Convert results to data frame
  df_eff <- data.frame(
    effect_pct = eff_pct,
    effect_log = effect_log,
    seed = seeds,
    ok = sapply(results_eff, function(r) isTRUE(r$ok)),
    att = sapply(results_eff, function(r) r$att),
    se = sapply(results_eff, function(r) r$se),
    p = sapply(results_eff, function(r) r$p)
  )

  all_draws[[length(all_draws) + 1]] <- df_eff

  # NULL DIAGNOSTIC: Report first 200 p-values for effect_pct = 0
  if (!is.null(null_pvals_diagnostic) && length(null_pvals_diagnostic) > 0) {
    null_diag_df <- tibble(
      sim_index = seq_along(null_pvals_diagnostic),
      p_value = null_pvals_diagnostic
    )
    safe_write_csv(null_diag_df, file.path(OUT_DIR, "null_pvalues_first200.csv"))

    quants <- quantile(null_pvals_diagnostic, probs = c(0.05, 0.50, 0.95), na.rm = TRUE)
    rej_rate <- mean(null_pvals_diagnostic < ALPHA, na.rm = TRUE)

    log_line(RUN_LOG, "")
    log_line(RUN_LOG, "=== NULL P-VALUE DIAGNOSTIC (first 200 sims) ===")
    log_line(RUN_LOG, glue("  N p-values collected: {length(null_pvals_diagnostic)}"))
    log_line(RUN_LOG, glue("  5th percentile: {round(quants[1], 4)}  (expect ~0.05)"))
    log_line(RUN_LOG, glue("  50th percentile: {round(quants[2], 4)}  (expect ~0.50)"))
    log_line(RUN_LOG, glue("  95th percentile: {round(quants[3], 4)}  (expect ~0.95)"))
    log_line(RUN_LOG, glue("  Rejection rate at alpha={ALPHA}: {round(100*rej_rate, 2)}%  (expect ~{round(100*ALPHA, 1)}%)"))
    log_line(RUN_LOG, "===============================================")

    cat(glue("\nNULL DIAGNOSTIC (effect=0, first 200 sims):\n"))
    cat(glue("  P-value quantiles: 5%={round(quants[1],4)}, 50%={round(quants[2],4)}, 95%={round(quants[3],4)}\n"))
    cat(glue("  Rejection rate: {round(100*rej_rate,2)}% (expect ~{round(100*ALPHA,1)}%)\n\n"))
  }

  log_line(RUN_LOG, glue("  Final: ok={ok_cum}/{N_SIMS}; fail_rate={round(100*fail_rate_cum,1)}%; power={round(100*power_so_far,1)}%"))
}

# ----------------------------- save results -----------------------------------

all_df <- bind_rows(all_draws)

# Save sample draws
sample_draws <- all_df %>%
  group_by(effect_pct) %>%
  slice_head(n = 5) %>%
  ungroup()
safe_write_csv(sample_draws, file.path(OUT_DIR, "draws_sample.csv"))

# Power by effect
power_summary <- all_df %>%
  filter(ok) %>%
  group_by(effect_pct, effect_log) %>%
  summarise(
    n_sims = n(),
    n_ok = n(),
    n_fail = N_SIMS - n(),
    fail_rate = (N_SIMS - n()) / N_SIMS,
    power = mean(p < ALPHA, na.rm = TRUE),
    mean_att = mean(att, na.rm = TRUE),
    sd_att = sd(att, na.rm = TRUE),
    mean_se = mean(se, na.rm = TRUE),
    se_att_ratio = mean_se / sd_att,
    .groups = "drop"
  )
safe_write_csv(power_summary, file.path(OUT_DIR, "power_by_effect.csv"))

# Null diagnostics
null_df <- all_df %>% filter(effect_pct == 0, ok)
if (nrow(null_df) > 0) {
  p_quants <- quantile(null_df$p, c(0.01, 0.05, 0.10, 0.50, 0.90), na.rm = TRUE)

  null_diag <- tibble(
    n_states = n_states,
    n_sims = nrow(null_df),
    mean_att0 = mean(null_df$att, na.rm = TRUE),
    sd_att0 = sd(null_df$att, na.rm = TRUE),
    mean_se0 = mean(null_df$se, na.rm = TRUE),
    se_inflation = mean(null_df$se, na.rm = TRUE) / sd(null_df$att, na.rm = TRUE),
    type1_at_effect0 = mean(null_df$p < ALPHA, na.rm = TRUE),
    p01 = p_quants[1],
    p05 = p_quants[2],
    p10 = p_quants[3],
    p50 = p_quants[4],
    p90 = p_quants[5]
  )
  safe_write_csv(null_diag, file.path(OUT_DIR, "diagnostics_sanity.csv"))

  log_line(RUN_LOG, "")
  log_line(RUN_LOG, "=== NULL DIAGNOSTICS ===")
  log_line(RUN_LOG, glue("Type I error: {round(100*null_diag$type1_at_effect0,2)}%"))
  log_line(RUN_LOG, glue("SE inflation: {round(null_diag$se_inflation,3)}x"))
  log_line(RUN_LOG, glue("P-value quantiles: p01={round(null_diag$p01,3)}, p05={round(null_diag$p05,3)}, p10={round(null_diag$p10,3)}, p50={round(null_diag$p50,3)}, p90={round(null_diag$p90,3)}"))
  log_line(RUN_LOG, "========================")
}

# Errors by effect
if (length(errors_by_effect) > 0) {
  errors_df <- bind_rows(errors_by_effect)
  safe_write_csv(errors_df, file.path(OUT_DIR, "errors_by_effect.csv"))
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
      subtitle = glue("n_states={n_states}, n_sims={N_SIMS}, control_group={did_control_group}"),
      x = "Effect size (proportional)",
      y = "Power"
    ) +
    theme_minimal()

  ggsave(file.path(OUT_DIR, "power_curve.png"), p, width = 8, height = 6)
}

log_line(RUN_LOG, "")
log_line(RUN_LOG, "=== SIMULATION COMPLETE ===")
log_line(RUN_LOG, glue("Results saved to: {OUT_DIR}"))

cat("\nSimulation complete! Results in:", OUT_DIR, "\n")
cat("See run.log for full details.\n")
