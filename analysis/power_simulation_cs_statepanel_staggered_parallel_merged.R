#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_statepanel_staggered_parallel_merged.R
#
# ⚠️ WORK IN PROGRESS - NOT RECOMMENDED FOR PRIMARY ANALYSIS ⚠️
#
# Callaway-Sant'Anna DiD power simulation (alternative approach)
#
# KNOWN ISSUE: CS-DiD with bstrap=FALSE gives incorrect inference
#   - Type-I error ~0% instead of 5% at null
#   - Standard errors don't properly account for clustering
#   - Bootstrap (bstrap=TRUE) fixes this but is VERY slow
#
# RECOMMENDATION: Use power_simulation_twfe_statepanel_staggered_parallel_fixed.R
#   - Proper cluster-robust SEs without bootstrap
#   - Correct type-I error (~5%)
#   - Faster and more reliable
#
# This file is included for comparison purposes only.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
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

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
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

pval_from_z <- function(z) {
  if (!is.finite(z)) return(NA_real_)
  2 * pnorm(-abs(z))
}

# ----------------------------- config -----------------------------------------

DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "cs_power_out")

# Optional filtering
EXCLUDE_STATES <- getenv1("EXCLUDE_STATES", "")  # Comma-separated, e.g. "ME,AK"
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))  # e.g. "2024-12-31"

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}
EXCLUDE_STATES_VEC <- parse_state_list(EXCLUDE_STATES)

# Error mode: iid_month (default) or ar1 (with autocorrelation)
ERR_MODE <- tolower(getenv1("ERR_MODE", "iid_month"))
if (!ERR_MODE %in% c("iid_month", "ar1")) {
  stop(glue("ERR_MODE must be iid_month or ar1; got {ERR_MODE}"), call. = FALSE)
}
ERR_AR1_RHO  <- parse_num(getenv1("ERR_AR1_RHO", ""), NA_real_)   # if NA, estimate from data
ERR_AR1_CLIP <- parse_num(getenv1("ERR_AR1_CLIP", "0.98"), 0.98)

OUTCOME    <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS   <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

N_SIMS     <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
EFFECT_PCTS <- parse_num_list(getenv1("EFFECT_PCTS", "0,0.05,0.10,0.15,0.20"),
                              default = c(0,0.05,0.10,0.15,0.20))
ALPHA      <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED       <- parse_int(getenv1("SEED", "123"), 123L)

TEST_MODE  <- parse_bool(getenv1("TEST_MODE", "FALSE"), FALSE)
DRY_RUN    <- parse_bool(getenv1("DRY_RUN",   "FALSE"), FALSE)

BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "50"), 50L)

# Workers
req_workers <- parse_int(getenv1("N_WORKERS", "20"), 20L)
slurm_cpus  <- parse_int(getenv1("SLURM_CPUS_PER_TASK", ""), NA_integer_)
if (is.finite(slurm_cpus) && slurm_cpus > 0L) req_workers <- min(req_workers, slurm_cpus)
N_WORKERS <- max(1L, req_workers)

if (TEST_MODE) {
  N_SIMS <- min(N_SIMS, 200L)
  EFFECT_PCTS <- head(EFFECT_PCTS, 6)
  BATCH_SIZE <- min(BATCH_SIZE, 25L)
}

# DID options
did_method <- getenv1("DID_EST_METHOD", "ipw")
did_faster_mode <- parse_bool(getenv1("DID_FASTER_MODE", "FALSE"), FALSE)
did_control_group <- getenv1("DID_CONTROL_GROUP", "nevertreated")
if (!did_control_group %in% c("nevertreated", "notyettreated")) {
  stop(glue("DID_CONTROL_GROUP must be nevertreated or notyettreated; got {did_control_group}"), call. = FALSE)
}

# Bootstrap inference (NEW from AR1 file)
did_bstrap <- parse_bool(getenv1("DID_BSTRAP", "TRUE"), TRUE)
did_biters <- parse_int(getenv1("DID_BITERS", "199"), 199L)
if (!is.finite(did_biters) || did_biters < 10L) did_biters <- 199L

cat("=== SCRIPT VERSION CHECK ===\n")
cat("Running: power_simulation_cs_statepanel_staggered_parallel_merged.R\n")
cat("Version: 2026-01-07-v6 (Added state and date filtering)\n")
cat("Changes: Added EXCLUDE_STATES and MAX_DATE options for filtering panel\n")
cat("============================\n\n")

# ----------------------------- prelude/logging --------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
file.create(file.path(OUT_DIR, "STARTED.txt"))

PROGRESS_BATCHES <- file.path(OUT_DIR, "progress_batches.csv")
POWER_RUNNING    <- file.path(OUT_DIR, "power_by_effect_running.csv")

if (!file.exists(PROGRESS_BATCHES)) {
  append_csv(tibble::tibble(
    ts = character(),
    effect_pct = double(),
    effect_log = double(),
    batch_lo = integer(),
    batch_hi = integer(),
    n_done = integer(),
    n_sims = integer(),
    ok_batch = integer(),
    fail_batch = integer(),
    ok_cum = integer(),
    fail_cum = integer(),
    fail_rate_cum = double(),
    power_so_far = double(),
    mean_att_so_far = double(),
    mean_se_so_far = double(),
    type1_so_far = double(),
    elapsed_sec_batch = double()
  ), PROGRESS_BATCHES)
}

if (!file.exists(POWER_RUNNING)) {
  append_csv(tibble::tibble(
    ts = character(),
    effect_pct = double(),
    effect_log = double(),
    n_done = integer(),
    ok_cum = integer(),
    fail_cum = integer(),
    fail_rate_cum = double(),
    power_so_far = double(),
    mean_att_so_far = double(),
    mean_se_so_far = double(),
    type1_so_far = double()
  ), POWER_RUNNING)
}

log_line(RUN_LOG, "=== PRELUDE ===")
log_line(RUN_LOG, "VERSION: 2026-01-07-v6 (Added EXCLUDE_STATES and MAX_DATE filtering)")
log_line(RUN_LOG, glue("SCRIPT_PATH: {getwd()}"))
log_line(RUN_LOG, glue("R_VERSION  : {R.version.string}"))
log_line(RUN_LOG, glue("DATA_FILE  : {DATA_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE : {TREAT_FILE}"))
log_line(RUN_LOG, glue("OUT_DIR    : {OUT_DIR}"))
log_line(RUN_LOG, glue("OUTCOME    : {OUTCOME}  RATE_EPS={RATE_EPS}"))
log_line(RUN_LOG, glue("N_SIMS     : {N_SIMS}  BATCH_SIZE={BATCH_SIZE}"))
log_line(RUN_LOG, glue("EFFECT_PCTS: {paste(EFFECT_PCTS, collapse=', ')}"))
log_line(RUN_LOG, glue("ALPHA      : {ALPHA}  SEED={SEED}"))
log_line(RUN_LOG, glue("N_WORKERS  : {N_WORKERS} (SLURM_CPUS_PER_TASK={getenv1('SLURM_CPUS_PER_TASK','')})"))
log_line(RUN_LOG, glue("DID        : control_group={did_control_group} est_method={did_method} faster_mode={did_faster_mode} bstrap={did_bstrap} biters={did_biters}"))
log_line(RUN_LOG, glue("ERR_MODE   : {ERR_MODE} (ERR_AR1_RHO={ifelse(is.finite(ERR_AR1_RHO), ERR_AR1_RHO, 'estimate')}, clip={ERR_AR1_CLIP})"))
log_line(RUN_LOG, glue("FILTERS    : EXCLUDE_STATES={ifelse(nzchar(EXCLUDE_STATES), EXCLUDE_STATES, 'none')}  MAX_DATE={ifelse(is.finite(MAX_DATE), as.character(MAX_DATE), 'none')}"))
log_line(RUN_LOG, glue("TEST_MODE  : {TEST_MODE}  DRY_RUN={DRY_RUN}"))
log_line(RUN_LOG, "=== END PRELUDE ===")

# ----------------------------- load + build panel -----------------------------

if (!file.exists(DATA_FILE)) {
  stop(glue("DATA_FILE not found: {DATA_FILE}"), call. = FALSE)
}
if (!file.exists(TREAT_FILE)) {
  stop(glue("TREAT_FILE not found: {TREAT_FILE}"), call. = FALSE)
}

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
  county_state <- df %>%
    dplyr::filter(geo_level == "county") %>%
    dplyr::mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    dplyr::filter(!is.na(state_abb), !is.na(month_date)) %>%
    dplyr::group_by(state_abb, month_date) %>%
    dplyr::summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      filings_per_1k_renters = dplyr::if_else(
        is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        as.numeric(NA)
      )
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    dplyr::filter(geo_level == "state") %>%
    dplyr::transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
      filings_per_1k_renters = as.numeric(filings_per_1k_renters)
    ) %>%
    dplyr::filter(!is.na(state_abb), !is.na(month_date)) %>%
    dplyr::filter(!(state_abb %in% county_states))

  out <- dplyr::bind_rows(county_state, state_fallback) %>%
    dplyr::arrange(state_abb, month_date)

  out
}

df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

state_list <- sort(unique(panel_raw$state_abb))
safe_write_csv(tibble::tibble(state_abb = state_list),
               file.path(OUT_DIR, "states_in_panel_raw.csv"))

if (length(state_list) < 30) {
  stop(glue("Panel build produced only {length(state_list)} states. See states_in_panel_raw.csv"),
       call. = FALSE)
}

treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  ) %>%
  arrange(state_abb, month_date)

panel <- panel_raw %>%
  left_join(treat, by = c("state_abb", "month_date")) %>%
  filter(state_abb %in% unique(treat$state_abb))

# Apply optional filters
if (length(EXCLUDE_STATES_VEC) > 0) {
  n_before <- n_distinct(panel$state_abb)
  panel <- panel %>% filter(!state_abb %in% EXCLUDE_STATES_VEC)
  n_after <- n_distinct(panel$state_abb)
  cat(glue("Excluded {length(EXCLUDE_STATES_VEC)} state(s): {paste(EXCLUDE_STATES_VEC, collapse=', ')}"), "\n")
  cat(glue("States: {n_before} -> {n_after}"), "\n")
}

if (is.finite(MAX_DATE)) {
  n_before <- nrow(panel)
  panel <- panel %>% filter(month_date <= MAX_DATE)
  n_after <- nrow(panel)
  cat(glue("Filtered to MAX_DATE={MAX_DATE}: {n_before} -> {n_after} rows"), "\n")
}

if (all(is.na(panel$treat_start))) {
  stop("After merging, treat_start is missing for all rows. Check state_abbr mapping and TREAT_FILE.", call. = FALSE)
}

panel <- panel %>%
  group_by(state_abb) %>%
  mutate(
    treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb))
  )

# HARD GUARD: g must be constant within id/state
g_bad <- panel %>%
  group_by(state_abb) %>%
  summarise(ng = n_distinct(g), .groups = "drop") %>%
  filter(ng != 1)
if (nrow(g_bad) > 0) {
  stop("g is not constant within state. Fix treat_start so each state has one adoption date.", call. = FALSE)
}

panel <- panel %>% mutate(
  untreated_obs = (g == 0L) | (t < g),
  post_treat = (g > 0L) & (t >= g)
)

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

panel_summary <- tibble::tibble(
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

log_line(RUN_LOG, glue("Panel: states={n_states} (switchers={n_switch}, never={n_never}); months={panel_summary$n_months}; rows={nrow(panel)}"))
log_line(RUN_LOG, glue("Untreated observations (never + pre): {sum(panel$untreated_obs, na.rm=TRUE)} / {nrow(panel)}"))

if (DRY_RUN) {
  log_line(RUN_LOG, "DRY_RUN requested: stopping after data validation + schedule export.")
  cat("DRY_RUN complete. See:", OUT_DIR, "\n")
  quit(status = 0)
}

# ----------------------------- outcome ----------------------------------------

if (OUTCOME == "log1p_filings_count") {
  panel <- panel %>% mutate(y = log1p(pmax(filings_count, 0)))
} else if (OUTCOME == "log1p_rate") {
  if (!("filings_per_1k_renters" %in% names(panel))) {
    stop("OUTCOME=log1p_rate but filings_per_1k_renters missing in panel.", call. = FALSE)
  }
  panel <- panel %>% mutate(y = log(pmax(filings_per_1k_renters, 0) + RATE_EPS))
} else {
  stop(glue("Unknown OUTCOME: {OUTCOME}"), call. = FALSE)
}

# ----------------------------- baseline FE + residual pools -------------------

# Optional exclusion window (e.g., to exclude COVID volatility from residual pool)
EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))  # e.g. "2020-03-01"
EXCLUDE_END   <- as.Date(getenv1("EXCLUDE_END",   ""))  # e.g. "2021-04-01"

in_exclude_window <- function(d) {
  if (!is.finite(EXCLUDE_START) || !is.finite(EXCLUDE_END)) return(rep(FALSE, length(d)))
  (d >= EXCLUDE_START) & (d < EXCLUDE_END)
}

# 1) FE estimation sample: untreated obs ONLY, but keep *all months* so yhat is defined
base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))

# Ensure at least one untreated obs per month for FE
untreated_by_t <- base_fe %>% count(t, name = "n_untreated")
missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
if (length(missing_t) > 0) {
  log_line(RUN_LOG, glue("WARNING: {length(missing_t)} months have zero untreated observations; dropping these months from panel."))
  panel   <- panel   %>% filter(!t %in% missing_t)
  base_fe <- base_fe %>% filter(!t %in% missing_t)
}

set.seed(SEED)
log_line(RUN_LOG, "Fitting unit+time FE on untreated observations...")
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)

panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

if (any(!is.finite(panel$yhat))) {
  bad <- which(!is.finite(panel$yhat))
  log_line(RUN_LOG, glue("WARNING: {length(bad)} observations have non-finite yhat; dropping them from panel."))
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
}

# Residuals (on FE sample)
base_fe$ehat <- as.numeric(residuals(fe_fit))

# 2) Residual pool sample: drop excluded window *here*, not in FE fit
pool_dat <- base_fe %>% filter(!in_exclude_window(month_date))

if (nrow(pool_dat) < 20) stop("Too few residuals after exclusion window.", call. = FALSE)

# Residual pools by month for iid_month mode
resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
global_pool <- pool_dat$ehat
global_pool <- global_pool[is.finite(global_pool)]

log_line(RUN_LOG, glue(
  "Residual pool exclusion: ",
  if (is.finite(EXCLUDE_START) && is.finite(EXCLUDE_END)) glue("[{EXCLUDE_START}, {EXCLUDE_END})") else "none",
  " | kept={nrow(pool_dat)}/{nrow(base_fe)} untreated obs"
))

if (length(global_pool) < 20) {
  stop("Too few untreated residuals to simulate. Check panel/untreated definition.", call. = FALSE)
}

# Objects for AR(1) mode (from boot_ar1.R)
rho_used <- NA_real_
sigma_u <- NA_real_
sd_row <- NULL
idx_by_id <- NULL
std_pool_by_t <- NULL
std_global_pool <- NULL

if (ERR_MODE == "ar1") {
  log_line(RUN_LOG, "Calibrating AR(1) from untreated residuals (post-exclusion)...")

  # Use pool_dat (post-exclusion) for AR(1) calibration
  sd_by_t_df <- pool_dat %>%
    group_by(t) %>%
    summarise(sd_e = sd(ehat, na.rm = TRUE), .groups = "drop")

  sd_global <- sd(global_pool, na.rm = TRUE)
  if (!is.finite(sd_global) || sd_global <= 0) sd_global <- 1

  sd_by_t_df <- sd_by_t_df %>%
    mutate(sd_e = if_else(is.finite(sd_e) & sd_e > 1e-8, sd_e, sd_global))

  sd_map <- setNames(sd_by_t_df$sd_e, as.character(sd_by_t_df$t))

  pool_dat <- pool_dat %>%
    mutate(
      sd_t = dplyr::coalesce(unname(sd_map[as.character(t)]), sd_global),
      sd_t = ifelse(is.finite(sd_t) & sd_t > 0, sd_t, sd_global),
      z    = ehat / sd_t
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
  sigma_u <- sqrt(max(0, 1 - rho_used^2))

  sd_row <- sd_map[as.character(panel$t)]
  sd_row[!is.finite(sd_row) | sd_row <= 0] <- sd_global

  idx_by_id <- split(seq_len(nrow(panel)), panel$id)
  idx_by_id <- lapply(idx_by_id, function(idx) idx[order(panel$t[idx])])

  log_line(RUN_LOG, glue("AR(1) rho_used={round(rho_used,4)} sigma_u={round(sigma_u,4)} sd_global={round(sd_global,4)}"))
}

# ----------------------------- simulation core --------------------------------

effect_tbl <- tibble::tibble(
  effect_pct = EFFECT_PCTS,
  effect_log = log(1 + EFFECT_PCTS)
)

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

# Error drawing functions (from boot_ar1.R)
draw_errors_iid_month <- function(tt, resid_pool_by_t, global_pool) {
  vapply(tt, function(tt_i) {
    pool <- resid_pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < 2L) pool <- global_pool
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

draw_errors_ar1 <- function(panel_t, idx_by_id, std_pool_by_t, std_global_pool, sd_row, rho_used, sigma_u) {
  e_draw <- numeric(length(panel_t))
  for (idx in idx_by_id) {
    m <- length(idx)
    if (m <= 0) next

    z_innov <- vapply(panel_t[idx], function(tt_i) {
      pool <- std_pool_by_t[[as.character(tt_i)]]
      if (is.null(pool) || length(pool) < 2L) pool <- std_global_pool
      sample(pool, size = 1L, replace = TRUE)
    }, FUN.VALUE = 0.0)

    x <- numeric(m)
    x[1] <- z_innov[1]
    if (m >= 2) {
      for (j in 2:m) x[j] <- rho_used * x[j - 1] + sigma_u * z_innov[j]
    }

    e_draw[idx] <- x * sd_row[idx]
  }
  e_draw
}

# One simulation (FIXED: no duplicate att_gt call)
one_sim <- function(seed, effect_log) {
  set.seed(seed)

  e_draw <- if (ERR_MODE == "iid_month") {
    draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  } else {
    draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool, sd_row, rho_used, sigma_u)
  }

  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_log, 0.0)

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    g  = panel$g,
    y  = y_sim
  )

  out <- tryCatch({
    suppressWarnings({
      # SINGLE att_gt call (bug fix from fixed2)
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
        est_method = did_method,
        faster_mode = did_faster_mode,
        bstrap = did_bstrap,
        biters = did_biters,
        cband = FALSE,
        clustervars = "id"
      )

      att_vec <- est$att
      miss_share <- if (is.null(att_vec)) 0 else mean(is.na(att_vec))
      if (!is.finite(miss_share) || miss_share >= 0.25) {
        stop(glue("Too many missing ATT(g,t) cells: miss_share={round(miss_share,3)}"))
      }

      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)

      # Prefer did's own p-value when bootstrapping
      p <- NA_real_
      if (isTRUE(did_bstrap) && !is.null(agg$overall.pval) && is.finite(agg$overall.pval)) {
        # Use bootstrap p-value when available
        p <- as.numeric(agg$overall.pval)
      } else {
        # Use t-distribution with df = n_states - 1 (cluster-robust inference)
        z <- att / se
        p <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_
      }

      list(ok = TRUE, att = att, se = se, p = p)
    })
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = conditionMessage(e))
  })

  if (!isTRUE(out$ok) || !is.finite(out$att) || !is.finite(out$se) || out$se <= 0 || !is.finite(out$p)) {
    err_msg <- out$err
    if (is.null(err_msg) || !nzchar(as.character(err_msg))) err_msg <- "non-finite att/se/p"
    return(list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_, err = err_msg))
  }
  out
}

# ----------------------------- parallel setup ---------------------------------

use_parallel <- (N_WORKERS > 1L)

if (use_parallel) {
  log_line(RUN_LOG, glue("Parallel: requested_workers={N_WORKERS}; using_workers={N_WORKERS}"))
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster.log"))
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(did)
      library(fixest)
      library(dplyr)
    })
    NULL
  })

  parallel::clusterExport(
    cl,
    varlist = c(
      "one_sim","panel","resid_pool_by_t","global_pool",
      "did_method","did_control_group","did_faster_mode","did_bstrap","did_biters",
      "ERR_MODE","idx_by_id","std_pool_by_t","std_global_pool","sd_row","rho_used","sigma_u",
      "draw_errors_iid_month","draw_errors_ar1","pval_from_z","n_states"
    ),
    envir = environment()
  )
}

# ----------------------------- run simulation ---------------------------------

set.seed(SEED)

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
      parallel::clusterApply(cl, seeds_batch, one_sim, effect_log = eff_log)
    } else {
      lapply(seeds_batch, function(ss) one_sim(ss, eff_log))
    }
    t1 <- Sys.time()

    idx <- seq_along(batch_out) + n_done
    res_rows[idx] <- batch_out
    n_done <- b_hi

    ok_now <- sum(vapply(batch_out, function(x) isTRUE(x$ok), logical(1)))
    fail_now <- length(batch_out) - ok_now
    log_line(RUN_LOG, glue("Batch {b_lo}-{b_hi}/{N_SIMS}: ok={ok_now} fail={fail_now}  elapsed={round(as.numeric(difftime(t1,t0,units='secs')),1)}s"))

    # Cumulative statistics
    ok_c   <- vapply(res_rows[seq_len(n_done)], function(x) isTRUE(x$ok), logical(1))
    p_c    <- vapply(res_rows[seq_len(n_done)], function(x) x$p, numeric(1))
    att_c  <- vapply(res_rows[seq_len(n_done)], function(x) x$att, numeric(1))
    se_c   <- vapply(res_rows[seq_len(n_done)], function(x) x$se, numeric(1))

    ok_c_n   <- sum(ok_c, na.rm = TRUE)
    fail_c_n <- n_done - ok_c_n
    fail_rate_cum <- fail_c_n / n_done

    power_so_far <- if (ok_c_n > 0) mean(p_c[ok_c] < ALPHA, na.rm = TRUE) else NA_real_
    mean_att_so_far <- if (ok_c_n > 0) mean(att_c[ok_c], na.rm = TRUE) else NA_real_
    mean_se_so_far  <- if (ok_c_n > 0) mean(se_c[ok_c], na.rm = TRUE) else NA_real_

    type1_so_far <- NA_real_
    if (abs(eff_pct) < 1e-12 && ok_c_n > 0) {
      type1_so_far <- mean(p_c[ok_c] < ALPHA, na.rm = TRUE)
    }

    elapsed_sec <- as.numeric(difftime(t1, t0, units = "secs"))

    # Progress logs
    append_csv(tibble::tibble(
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      effect_pct = eff_pct,
      effect_log = eff_log,
      batch_lo = b_lo,
      batch_hi = b_hi,
      n_done = n_done,
      n_sims = N_SIMS,
      ok_batch = ok_now,
      fail_batch = fail_now,
      ok_cum = ok_c_n,
      fail_cum = fail_c_n,
      fail_rate_cum = fail_rate_cum,
      power_so_far = power_so_far,
      mean_att_so_far = mean_att_so_far,
      mean_se_so_far = mean_se_so_far,
      type1_so_far = type1_so_far,
      elapsed_sec_batch = elapsed_sec
    ), PROGRESS_BATCHES)

    append_csv(tibble::tibble(
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      effect_pct = eff_pct,
      effect_log = eff_log,
      n_done = n_done,
      ok_cum = ok_c_n,
      fail_cum = fail_c_n,
      fail_rate_cum = fail_rate_cum,
      power_so_far = power_so_far,
      mean_att_so_far = mean_att_so_far,
      mean_se_so_far = mean_se_so_far,
      type1_so_far = type1_so_far
    ), POWER_RUNNING)

    # Error tracking (from fixed2)
    if (any(!vapply(batch_out, function(x) isTRUE(x$ok), logical(1)))) {
      err_counts_path <- file.path(OUT_DIR, paste0("error_counts_running_effect_", fmt_eff(eff_pct), ".csv"))

      err_vec <- vapply(batch_out, function(x) {
        if (isTRUE(x$ok)) NA_character_ else as.character(x$err)
      }, character(1))

      err_tab <- tibble::tibble(err = err_vec) %>%
        dplyr::filter(!is.na(err), nzchar(err)) %>%
        dplyr::count(err, name = "n", sort = TRUE) %>%
        dplyr::mutate(n = as.integer(n))

      if (file.exists(err_counts_path)) {
        old <- readr::read_csv(err_counts_path, show_col_types = FALSE)
        err_tab <- dplyr::bind_rows(old, err_tab) %>%
          dplyr::group_by(err) %>%
          dplyr::summarise(n = as.integer(sum(n, na.rm = TRUE)), .groups = "drop") %>%
          dplyr::arrange(dplyr::desc(n))
      }

      safe_write_csv(err_tab, err_counts_path)
    }

    # Console progress
    cat(glue::glue(
      "[{format(Sys.time(), '%H:%M:%S')}] eff={eff_pct} batch={b_lo}-{b_hi} ",
      "ok_cum={ok_c_n}/{n_done} fail_rate={round(fail_rate_cum,3)} ",
      "power_so_far={ifelse(is.finite(power_so_far), round(power_so_far,3), NA)}\n"
    ))
    flush.console()

    # Sample draws for debugging
    if (length(draws_sample) < 200 && (b_lo == 1L || b_hi == N_SIMS)) {
      ss <- batch_out[seq_len(min(5, length(batch_out)))]
      draws_sample[[length(draws_sample)+1]] <- tibble::tibble(
        effect_pct = eff_pct,
        seed = seeds_batch[seq_len(min(5, length(seeds_batch)))],
        ok = vapply(ss, function(x) isTRUE(x$ok), logical(1)),
        att = vapply(ss, function(x) x$att, numeric(1)),
        se  = vapply(ss, function(x) x$se, numeric(1)),
        p   = vapply(ss, function(x) x$p, numeric(1))
      )
    }
  }

  # Summarize this effect
  ok <- vapply(res_rows, function(x) isTRUE(x$ok), logical(1))
  p  <- vapply(res_rows, function(x) x$p, numeric(1))
  att<- vapply(res_rows, function(x) x$att, numeric(1))
  se <- vapply(res_rows, function(x) x$se, numeric(1))

  n_fail <- sum(!ok)
  n_ok   <- sum(ok)
  pow    <- if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_

  all_results[[k]] <- tibble::tibble(
    effect_pct = eff_pct,
    effect_log = eff_log,
    n_sims = N_SIMS,
    n_ok = n_ok,
    n_fail = n_fail,
    fail_rate = n_fail / N_SIMS,
    alpha = ALPHA,
    power = pow,
    mean_att = if (n_ok > 0) mean(att[ok], na.rm = TRUE) else NA_real_,
    sd_att   = if (n_ok > 1) sd(att[ok], na.rm = TRUE) else NA_real_,
    mean_se  = if (n_ok > 0) mean(se[ok], na.rm = TRUE) else NA_real_,
    median_p = if (n_ok > 0) median(p[ok], na.rm = TRUE) else NA_real_,
    share_p_lt_alpha = if (n_ok > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_
  )

  safe_write_csv(dplyr::bind_rows(all_results), file.path(OUT_DIR, "power_by_effect.csv"))
}

if (length(draws_sample) > 0) {
  safe_write_csv(dplyr::bind_rows(draws_sample), file.path(OUT_DIR, "draws_sample.csv"))
}

# ----------------------------- sanity diagnostics -----------------------------

pwr <- readr::read_csv(file.path(OUT_DIR, "power_by_effect.csv"), show_col_types = FALSE)

diag <- tibble::tibble(
  n_states = n_states,
  n_switchers = n_switch,
  n_never = n_never,
  n_sims = N_SIMS,
  outcome = OUTCOME,
  did_method = did_method,
  did_control_group = did_control_group,
  did_bstrap = did_bstrap,
  did_biters = did_biters,
  alpha = ALPHA,
  err_mode = ERR_MODE,
  rho_used = rho_used,
  share_months_with_any_untreated = mean(table(base_fe$t) > 0)
)

if (any(abs(pwr$effect_pct) < 1e-12)) {
  n_diag <- min(400L, N_SIMS)
  diag_seeds <- sim_seeds[seq_len(n_diag)]

  log_line(RUN_LOG, glue("Computing diagnostics at effect=0 with n={n_diag}..."))

  diag_out <- if (use_parallel) {
    parallel::clusterApply(cl, diag_seeds, one_sim, effect_log = 0.0)
  } else {
    lapply(diag_seeds, function(ss) one_sim(ss, 0.0))
  }

  ok0 <- vapply(diag_out, function(x) isTRUE(x$ok), logical(1))
  p0  <- vapply(diag_out, function(x) x$p, numeric(1))
  att0<- vapply(diag_out, function(x) x$att, numeric(1))
  se0 <- vapply(diag_out, function(x) x$se, numeric(1))

  type1 <- if (sum(ok0) > 0) mean(p0[ok0] < ALPHA, na.rm = TRUE) else NA_real_

  diag <- diag %>%
    mutate(
      type1_at_effect0 = type1,
      fail_rate_effect0 = mean(!ok0),
      p0_q05 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.05, na.rm = TRUE)) else NA_real_,
      p0_q50 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.50, na.rm = TRUE)) else NA_real_,
      p0_q95 = if (sum(ok0) > 0) unname(quantile(p0[ok0], 0.95, na.rm = TRUE)) else NA_real_,
      mean_att0 = if (sum(ok0) > 0) mean(att0[ok0], na.rm = TRUE) else NA_real_,
      mean_se0  = if (sum(ok0) > 0) mean(se0[ok0], na.rm = TRUE) else NA_real_
    )

  # Histogram
  p0_ok <- p0[ok0]
  p0_ok <- p0_ok[is.finite(p0_ok)]

  if (sum(!ok0) > 0) {
    err_counts <- tibble::tibble(err = vapply(diag_out, function(x) {
      if (isTRUE(x$ok)) NA_character_ else as.character(x$err)
    }, character(1))) %>%
      dplyr::filter(!is.na(err), nzchar(err)) %>%
      dplyr::count(err, sort = TRUE)

    safe_write_csv(err_counts, file.path(OUT_DIR, "diagnostics_effect0_error_counts.csv"))
  }

  if (length(p0_ok) >= 2L) {
    png(file.path(OUT_DIR, "pvalues_hist_effect0.png"), width = 900, height = 650)
    hist(p0_ok, breaks = 30, main = "P-values at effect=0 (sanity check)", xlab = "p-value")
    abline(v = ALPHA, col = "red", lwd = 2)
    dev.off()
  } else {
    log_line(RUN_LOG, "Skipping p-values histogram at effect=0: no successful finite p-values.")
  }
}

safe_write_csv(diag, file.path(OUT_DIR, "diagnostics_sanity.csv"))

# ----------------------------- plot power curve -------------------------------

if (any(is.finite(pwr$power))) {
  png(file.path(OUT_DIR, "power_curve.png"), width = 900, height = 650)
  plot(pwr$effect_pct, pwr$power, type = "b",
       xlab = "Effect size (proportional change)", ylab = "Estimated power",
       main = glue("Power curve (N_SIMS={N_SIMS}, alpha={ALPHA}, method={did_method}, err={ERR_MODE}, bstrap={did_bstrap})"))
  abline(h = 0.80, lty = 2, col = "gray")
  grid()
  dev.off()
} else {
  log_line(RUN_LOG, "Skipping power_curve.png: no finite power values.")
}

log_line(RUN_LOG, "=== DONE ===")
cat("Done. Outputs written to:", OUT_DIR, "\n")
