#!/usr/bin/env Rscript
################################################################################
# power_simulation_twfe_statepanel_staggered_parallel.R
#
# Traditional TWFE DiD power simulation for a staggered-adoption state panel.
#
# Key pieces:
#   1) Build a state-month panel from combined_monthly_panel.csv
#      - Aggregates county rows to state-month when available; otherwise uses
#        state-level rows as fallback (same logic as your CS scripts)
#   2) Merge an observed treatment schedule from state_month_panel_with_treatment.csv
#      - One adoption date per state; never-treated have g=0
#   3) Simulate outcomes using untreated variation (never-treated + pre-periods):
#      - Fit unit + time FE on untreated observations only: y ~ 1 | id + t
#      - Resample residuals within month (iid_month), or generate AR(1) within state
#      - Add a constant post-adoption treatment effect on the log scale
#   4) Estimate TWFE each simulation:
#      - feols(y_sim ~ post_treat | id + t, cluster = ~id)
#      - Uses fixest’s clustered SEs + p-values (so type-I at effect=0 should
#        be ~ALPHA, up to Monte Carlo error)
#
# Outputs (in OUT_DIR):
#   run.log
#   treatment_schedule.csv
#   panel_summary.csv
#   power_by_effect.csv
#   diagnostics_sanity.csv
#   draws_sample.csv
#   power_curve.png
#
# Env vars:
#   DATA_FILE      default combined_monthly_panel.csv
#   TREAT_FILE     default state_month_panel_with_treatment.csv
#   OUT_DIR        default ./twfe_power_out
#   OUTCOME        log1p_filings_count (default) or log1p_rate
#   RATE_EPS       default 0.01 (used in log for rates)
#   N_SIMS         default 2000
#   EFFECT_PCTS    default "0,0.05,0.10,0.15,0.20"
#   ALPHA          default 0.05
#   SEED           default 123
#   N_WORKERS      default 20 (respects SLURM_CPUS_PER_TASK if set)
#   BATCH_SIZE     default 50
#   ERR_MODE       iid_month (default) or ar1
#   ERR_AR1_RHO    optional (if empty, estimated from untreated residuals)
#   ERR_AR1_CLIP   default 0.98
#   MIN_POOL       default 10  (min # residuals in a month pool before fallback)
#
#   EXCLUDE_START / EXCLUDE_END
#     Optional Date window (YYYY-MM-DD) to *exclude from residual pool* only.
#     Example: EXCLUDE_START=2020-03-01 EXCLUDE_END=2021-07-01
#
#   DROP_START / DROP_END
#     Optional Date window (YYYY-MM-DD) to *drop months from the analysis panel*
#     (FE fit, simulation, and TWFE estimation). Use this if you want “no COVID
#     months in the analysis,” not just “no COVID months in residual resampling.”
#
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(tibble)
})

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
  if (!file.exists(path)) readr::write_csv(df, path) else readr::write_csv(df, path, append = TRUE)
}

fmt_eff <- function(x) gsub("\\.", "p", format(x, trim = TRUE, scientific = FALSE))

# ----------------------------- config -----------------------------------------

DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "twfe_power_out")

OUTCOME    <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS   <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

N_SIMS     <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
EFFECT_PCTS <- parse_num_list(getenv1("EFFECT_PCTS", "0,0.05,0.10,0.15,0.20"),
                              default = c(0,0.05,0.06,0.07,0.08, 0.09,0.1))
ALPHA      <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED       <- parse_int(getenv1("SEED", "123"), 123L)

BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "50"), 50L)
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
if (!is.finite(MIN_STATES_PER_MONTH) || MIN_STATES_PER_MONTH < 2L) MIN_STATES_PER_MONTH <- 2L

ERR_MODE <- tolower(getenv1("ERR_MODE", "iid_month"))
if (!ERR_MODE %in% c("iid_month", "ar1")) stop("ERR_MODE must be iid_month or ar1", call. = FALSE)
ERR_AR1_RHO  <- parse_num(getenv1("ERR_AR1_RHO", ""), NA_real_)
ERR_AR1_CLIP <- parse_num(getenv1("ERR_AR1_CLIP", "0.98"), 0.98)

# parallel
req_workers <- parse_int(getenv1("N_WORKERS", "20"), 20L)
slurm_cpus  <- parse_int(getenv1("SLURM_CPUS_PER_TASK", ""), NA_integer_)
if (is.finite(slurm_cpus) && slurm_cpus > 0L) req_workers <- min(req_workers, slurm_cpus)
N_WORKERS <- max(1L, req_workers)
use_parallel <- (N_WORKERS > 1L)

# windows
EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))
EXCLUDE_END   <- as.Date(getenv1("EXCLUDE_END", ""))

DROP_START <- as.Date(getenv1("DROP_START", ""))
DROP_END   <- as.Date(getenv1("DROP_END", ""))

# state/date filtering
EXCLUDE_STATES <- getenv1("EXCLUDE_STATES", "")  # Comma-separated, e.g. "ME,AK"
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))  # e.g. "2024-12-31"

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}
EXCLUDE_STATES_VEC <- parse_state_list(EXCLUDE_STATES)

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d < end)
}

# ----------------------------- logging ----------------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
log_line(RUN_LOG, "=== TWFE POWER SIM ===")
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
log_line(RUN_LOG, glue("ERR_MODE: {ERR_MODE} (rho={ifelse(is.finite(ERR_AR1_RHO), ERR_AR1_RHO, 'estimate')}, clip={ERR_AR1_CLIP}) MIN_STATES_PER_MONTH={MIN_STATES_PER_MONTH}"))
exclude_str <- if (!is.na(EXCLUDE_START) && !is.na(EXCLUDE_END)) glue('[{EXCLUDE_START},{EXCLUDE_END})') else 'none'
log_line(RUN_LOG, glue("EXCLUDE (resid pool only): {exclude_str}"))
log_line(RUN_LOG, glue("DROP (analysis panel): {if (!is.na(DROP_START) && !is.na(DROP_END)) glue('[{DROP_START},{DROP_END})') else 'none'}"))
log_line(RUN_LOG, glue("FILTERS: EXCLUDE_STATES={ifelse(nzchar(EXCLUDE_STATES), EXCLUDE_STATES, 'none')}  MAX_DATE={ifelse(is.finite(MAX_DATE), as.character(MAX_DATE), 'none')}"))
log_line(RUN_LOG, "======================")

# ----------------------------- load + build panel -----------------------------

if (!file.exists(DATA_FILE)) stop(glue("DATA_FILE not found: {DATA_FILE}"), call. = FALSE)
if (!file.exists(TREAT_FILE)) stop(glue("TREAT_FILE not found: {TREAT_FILE}"), call. = FALSE)

# map geo_id -> state abbreviation (state.name / state.abb)
state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

# fips state lookup (no external data)
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

build_state_panel <- function(df) {
  # county -> state-month aggregation
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

  # fallback to state-level rows where county coverage is absent in this file
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

# one adoption date per state
panel <- panel %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup()

# optional drop window from the analysis panel entirely
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

# guard: g constant in state
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

# FE fit sample: untreated obs only
base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))

# ensure at least one untreated obs per month (for time FE predictions)
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

# residuals on FE fit sample
base_fe$ehat <- as.numeric(residuals(fe_fit))

# Build residual pool with exclusion window and min states per month threshold
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

# pools by t
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

# AR(1) calibration objects
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
    arrange(id, t) %>%
    group_by(id) %>%
    mutate(z_lag = lag(z)) %>%
    ungroup()

  rho_hat <- suppressWarnings(stats::cor(tmp$z, tmp$z_lag, use = "complete.obs"))
  if (!is.finite(rho_hat)) rho_hat <- 0
  if (is.finite(ERR_AR1_RHO)) rho_hat <- ERR_AR1_RHO

  rho_used <- max(-ERR_AR1_CLIP, min(ERR_AR1_CLIP, rho_hat))
  sigma_u  <- sqrt(max(0, 1 - rho_used^2))

  sd_row <- unname(sd_map[as.character(panel$t)])
  sd_row[!is.finite(sd_row) | sd_row <= 0] <- sd_global

  idx_by_id <- split(seq_len(nrow(panel)), panel$id)
  idx_by_id <- lapply(idx_by_id, function(idx) idx[order(panel$t[idx])])

  log_line(RUN_LOG, glue("AR(1): rho_used={round(rho_used,4)} sigma_u={round(sigma_u,4)} sd_global={round(sd_global,4)}"))
}

# ----------------------------- error drawing ----------------------------------

draw_errors_iid_month <- function(tt, resid_pool_by_t, global_pool, min_states_per_month) {
  vapply(tt, function(tt_i) {
    pool <- resid_pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < min_states_per_month) pool <- global_pool
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

draw_errors_ar1 <- function(panel_t, idx_by_id, std_pool_by_t, std_global_pool,
                            sd_row, rho_used, sigma_u, min_states_per_month) {
  e_draw <- numeric(length(panel_t))
  for (idx in idx_by_id) {
    m <- length(idx)
    if (m <= 0) next

    z_innov <- vapply(panel_t[idx], function(tt_i) {
      pool <- std_pool_by_t[[as.character(tt_i)]]
      if (is.null(pool) || length(pool) < min_states_per_month) pool <- std_global_pool
      sample(pool, size = 1L, replace = TRUE)
    }, FUN.VALUE = 0.0)

    x <- numeric(m)
    x[1] <- z_innov[1]
    if (m >= 2) for (j in 2:m) x[j] <- rho_used * x[j - 1] + sigma_u * z_innov[j]

    e_draw[idx] <- x * sd_row[idx]
  }
  e_draw
}

# ----------------------------- simulation core --------------------------------

effect_tbl <- tibble(
  effect_pct = EFFECT_PCTS,
  effect_log = log(1 + EFFECT_PCTS)
)

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

# single sim for a given effect
one_sim_twfe <- function(seed, effect_log) {
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
    # IMPORTANT: make this numeric 0/1 so fixest names the coefficient `post_treat`
    post_treat = as.integer(panel$post_treat),
    y  = y_sim
  )

  out <- tryCatch({
    est <- fixest::feols(y ~ post_treat | id + t, data = dat,
                         cluster = ~id, warn = FALSE, notes = FALSE)

    ct <- fixest::coeftable(est)

    # Coefficient name can differ if post_treat is non-numeric; handle defensively
    coef_name <- if ("post_treat" %in% rownames(ct)) {
      "post_treat"
    } else {
      nm <- grep("^post_treat", rownames(ct), value = TRUE)
      if (length(nm) >= 1) nm[1] else NA_character_
    }
    if (!is.character(coef_name) || !nzchar(coef_name)) {
      stop("post_treat coefficient missing", call. = FALSE)
    }

    att <- unname(ct[coef_name, "Estimate"])
    se  <- unname(ct[coef_name, "Std. Error"])
    p   <- unname(ct[coef_name, "Pr(>|t|)"])

    list(ok = is.finite(att) && is.finite(se) && se > 0 && is.finite(p),
         att = att, se = se, p = p)
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = conditionMessage(e))
  })

  if (!isTRUE(out$ok)) {
    if (is.null(out$err) || !nzchar(out$err)) out$err <- "twfe failed"
  }
  out
}

one_sim_twfe_worker <- function(seed, eff_log) one_sim_twfe(seed, eff_log)

# ----------------------------- parallel setup ---------------------------------

cl <- NULL
if (use_parallel) {
  log_line(RUN_LOG, glue("Parallel: starting PSOCK cluster with {N_WORKERS} workers"))
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster.log"))
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(fixest)
    })
    NULL
  })

  # export all objects used inside one_sim_twfe
  parallel::clusterExport(
    cl,
    varlist = c(
      "panel","resid_pool_by_t","global_pool","MIN_STATES_PER_MONTH",
      "ERR_MODE","idx_by_id","std_pool_by_t","std_global_pool","sd_row","rho_used","sigma_u",
      "draw_errors_iid_month","draw_errors_ar1","one_sim_twfe","one_sim_twfe_worker"
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

all_results <- list()
draws_sample <- list()

for (k in seq_len(nrow(effect_tbl))) {
  eff_pct <- effect_tbl$effect_pct[k]
  eff_log <- effect_tbl$effect_log[k]
  log_line(RUN_LOG, glue("=== Effect {eff_pct} (log={round(eff_log,5)}) ==="))

  n_done <- 0L
  res_rows <- vector("list", N_SIMS)

  while (n_done < N_SIMS) {
    b_lo <- n_done + 1L
    b_hi <- min(N_SIMS, n_done + BATCH_SIZE)
    seeds_batch <- sim_seeds[b_lo:b_hi]

    t0 <- Sys.time()
    batch_out <- if (use_parallel) {
      parallel::parLapply(cl, seeds_batch, one_sim_twfe_worker, eff_log = eff_log)
    } else {
      lapply(seeds_batch, function(ss) one_sim_twfe(ss, eff_log))
    }
    t1 <- Sys.time()

    idx <- seq_along(batch_out) + n_done
    res_rows[idx] <- batch_out
    n_done <- b_hi

    ok_c <- vapply(res_rows[seq_len(n_done)], function(x) isTRUE(x$ok), logical(1))
    p_c  <- vapply(res_rows[seq_len(n_done)], function(x) x$p, numeric(1))
    se_c <- vapply(res_rows[seq_len(n_done)], function(x) x$se, numeric(1))

    ok_n <- sum(ok_c, na.rm = TRUE)
    fail_n <- n_done - ok_n
    power_so_far <- if (ok_n > 0) mean(p_c[ok_c] < ALPHA, na.rm = TRUE) else NA_real_
    mean_se_so_far <- if (ok_n > 0) mean(se_c[ok_c], na.rm = TRUE) else NA_real_

    append_csv(tibble(
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      effect_pct = eff_pct,
      effect_log = eff_log,
      batch_lo = b_lo,
      batch_hi = b_hi,
      n_done = n_done,
      n_sims = N_SIMS,
      ok_cum = ok_n,
      fail_cum = fail_n,
      fail_rate_cum = fail_n / n_done,
      power_so_far = power_so_far,
      mean_se_so_far = mean_se_so_far
    ), PROGRESS_BATCHES)

    cat(glue("[{format(Sys.time(), '%H:%M:%S')}] eff={eff_pct} batch={b_lo}-{b_hi} ok={ok_n}/{n_done} power={ifelse(is.finite(power_so_far), round(power_so_far,3), NA)}\n"))
    flush.console()

    if (length(draws_sample) < 200 && (b_lo == 1L || b_hi == N_SIMS)) {
      ss <- batch_out[seq_len(min(5, length(batch_out)))]
      draws_sample[[length(draws_sample)+1]] <- tibble(
        effect_pct = eff_pct,
        seed = seeds_batch[seq_len(min(5, length(seeds_batch)))],
        ok = vapply(ss, function(x) isTRUE(x$ok), logical(1)),
        att = vapply(ss, function(x) x$att, numeric(1)),
        se  = vapply(ss, function(x) x$se, numeric(1)),
        p   = vapply(ss, function(x) x$p, numeric(1))
      )
    }

    # log batch elapsed
    log_line(RUN_LOG, glue("Batch {b_lo}-{b_hi}/{N_SIMS}: elapsed={round(as.numeric(difftime(t1,t0,units='secs')),1)}s"))
  }

  ok  <- vapply(res_rows, function(x) isTRUE(x$ok), logical(1))
  p   <- vapply(res_rows, function(x) x$p, numeric(1))
  att <- vapply(res_rows, function(x) x$att, numeric(1))
  se  <- vapply(res_rows, function(x) x$se, numeric(1))

  n_ok <- sum(ok)
  n_fail <- N_SIMS - n_ok

  all_results[[k]] <- tibble(
    effect_pct = eff_pct,
    effect_log = eff_log,
    n_sims = N_SIMS,
    n_ok = n_ok,
    n_fail = n_fail,
    fail_rate = n_fail / N_SIMS,
    alpha = ALPHA,
    power = if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_,
    mean_att = if (n_ok > 0) mean(att[ok], na.rm = TRUE) else NA_real_,
    sd_att   = if (n_ok > 1) sd(att[ok], na.rm = TRUE) else NA_real_,
    mean_se  = if (n_ok > 0) mean(se[ok], na.rm = TRUE) else NA_real_,
    median_p = if (n_ok > 0) median(p[ok], na.rm = TRUE) else NA_real_,
    share_p_lt_alpha = if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_
  )

  safe_write_csv(bind_rows(all_results), file.path(OUT_DIR, "power_by_effect.csv"))
}

if (length(draws_sample) > 0) safe_write_csv(bind_rows(draws_sample), file.path(OUT_DIR, "draws_sample.csv"))

# diagnostics at effect=0 (if included)
pwr <- readr::read_csv(file.path(OUT_DIR, "power_by_effect.csv"), show_col_types = FALSE)

diag <- tibble(
  n_states = n_states,
  n_switchers = n_switch,
  n_never = n_never,
  n_sims = N_SIMS,
  outcome = OUTCOME,
  alpha = ALPHA,
  err_mode = ERR_MODE,
  rho_used = rho_used,
  min_states_per_month = MIN_STATES_PER_MONTH,
  exclude_start = ifelse(is.na(EXCLUDE_START), NA_character_, as.character(EXCLUDE_START)),
  exclude_end   = ifelse(is.na(EXCLUDE_END),   NA_character_, as.character(EXCLUDE_END)),
  drop_start    = ifelse(is.na(DROP_START),    NA_character_, as.character(DROP_START)),
  drop_end      = ifelse(is.na(DROP_END),      NA_character_, as.character(DROP_END))
)

# type-I from draws_sample is too small; do a quick dedicated null diagnostic
if (any(abs(pwr$effect_pct) < 1e-12)) {
  n_diag <- min(400L, N_SIMS)
  diag_seeds <- sim_seeds[seq_len(n_diag)]
  diag_out <- if (use_parallel) {
    parallel::parLapply(cl, diag_seeds, one_sim_twfe_worker, eff_log = 0.0)
  } else {
    lapply(diag_seeds, function(ss) one_sim_twfe(ss, 0.0))
  }

  ok0 <- vapply(diag_out, function(x) isTRUE(x$ok), logical(1))
  p0  <- vapply(diag_out, function(x) x$p, numeric(1))
  att0<- vapply(diag_out, function(x) x$att, numeric(1))
  se0 <- vapply(diag_out, function(x) x$se, numeric(1))

  diag <- diag %>%
    mutate(
      type1_at_effect0 = if (sum(ok0) > 0) mean(p0[ok0] < ALPHA, na.rm = TRUE) else NA_real_,
      fail_rate_effect0 = mean(!ok0),
      p0_q05 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.05, na.rm = TRUE)) else NA_real_,
      p0_q50 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.50, na.rm = TRUE)) else NA_real_,
      p0_q95 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.95, na.rm = TRUE)) else NA_real_,
      mean_att0 = if (sum(ok0) > 0) mean(att0[ok0], na.rm = TRUE) else NA_real_,
      mean_se0  = if (sum(ok0) > 0) mean(se0[ok0], na.rm = TRUE) else NA_real_
    )
}

safe_write_csv(diag, file.path(OUT_DIR, "diagnostics_sanity.csv"))

# power curve plot
if (any(is.finite(pwr$power))) {
  png(file.path(OUT_DIR, "power_curve.png"), width = 900, height = 650)
  plot(pwr$effect_pct, pwr$power, type = "b",
       xlab = "Effect size (proportional change)", ylab = "Estimated power",
       main = glue("TWFE power curve (N_SIMS={N_SIMS}, alpha={ALPHA}, err={ERR_MODE})"))
  abline(h = 0.80, lty = 2, col = "gray")
  grid()
  dev.off()
}

log_line(RUN_LOG, "=== DONE ===")
cat("Done. Outputs written to:", OUT_DIR, "\n")
