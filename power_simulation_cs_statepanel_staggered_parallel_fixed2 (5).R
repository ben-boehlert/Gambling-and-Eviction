#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_statepanel_staggered_parallel.R
#
# Staggered-adoption DiD power simulation using an observed treatment schedule
# (switchers + never-treated) and untreated variation (never-treated + pre-periods).
#
# - Uses did::att_gt (Callaway & Sant'Anna) with control_group="never-treated"
# - Simulates outcomes by:
#     1) estimating unit+time FE on untreated observations
#     2) resampling residuals *within month* from untreated observations
#     3) adding a constant post-adoption effect (on log scale) for treated units
# - Parallel on Della via PSOCK workers (default 20; respects SLURM_CPUS_PER_TASK)
# - Writes progress + sanity diagnostics to OUT_DIR
#
# Inputs (env vars):
#   DATA_FILE   : combined_monthly_panel.csv (default)
#   TREAT_FILE  : state_month_panel_with_treatment.csv (default)
#   OUT_DIR     : output directory (default ./cs_power_out)
#   OUTCOME     : log1p_filings_count (default) or log1p_rate
#   RATE_EPS    : epsilon added inside log for rates (default 0.01)
#   N_SIMS      : simulations per effect (default 2000; TEST_MODE clamps lower)
#   EFFECT_PCTS : comma list of effect sizes as proportional changes (default "0,0.05,0.10,0.15,0.20")
#   ALPHA       : significance level (default 0.05)
#   SEED        : RNG seed (default 123)
#   N_WORKERS   : workers (default 20; if SLURM_CPUS_PER_TASK set, uses min)
#   BATCH_SIZE  : sims per batch (default 50)  (progress updates between batches)
#   TEST_MODE   : TRUE/FALSE (default FALSE). If TRUE: clamps N_SIMS to <= 200 and effects to <= 6.
#   DRY_RUN     : TRUE/FALSE (default FALSE). If TRUE: validates inputs, writes schedule + exits (no did).
#
# Outputs (in OUT_DIR):
#   run.log
#   treatment_schedule.csv
#   panel_summary.csv
#   power_by_effect.csv
#   diagnostics_sanity.csv
#   draws_sample.csv         (small sample of simulated draws + pvalues; for debugging)
#   power_curve.png
#   pvalues_hist_effect0.png (if effect 0 included)
#
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

# base year-month index (integer) for did
ym_index <- function(date) {
  # date: Date
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

# map geo_id (lowercase state name) -> USPS abbreviation
state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)  # removes spaces/underscores/etc
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
  # nice file-safe effect label (e.g., 0.3 -> "0p3")
  gsub("\\.", "p", format(x, trim = TRUE, scientific = FALSE))
}


# robust z p-value
pval_from_z <- function(z) {
  if (!is.finite(z)) return(NA_real_)
  2 * pnorm(-abs(z))
}

# ----------------------------- config -----------------------------------------

DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "cs_power_out")
ERR_MODE <- getenv1("ERR_MODE", "iid_month")  # iid_month (current), ar1
ERR_AR1_RHO <- parse_num(getenv1("ERR_AR1_RHO", ""), NA_real_)  # if NA, estimate from untreated residuals
ERR_AR1_CLIP <- parse_num(getenv1("ERR_AR1_CLIP", "0.98"), 0.98)
did_biters <- parse_int(getenv1("DID_BITERS", "199"), 199L)

OUTCOME    <- getenv1("OUTCOME", "log1p_filings_count")   # or log1p_rate
RATE_EPS   <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

N_SIMS     <- parse_int(getenv1("N_SIMS", "2000"), 2000L)
EFFECT_PCTS <- parse_num_list(getenv1("EFFECT_PCTS", "0,0.05,0.10,0.15,0.20"),
                              default = c(0,0.05,0.10,0.15,0.20))
ALPHA      <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED       <- parse_int(getenv1("SEED", "123"), 123L)

TEST_MODE  <- parse_bool(getenv1("TEST_MODE", "FALSE"), FALSE)
DRY_RUN    <- parse_bool(getenv1("DRY_RUN",   "FALSE"), FALSE)

BATCH_SIZE <- parse_int(getenv1("BATCH_SIZE", "50"), 50L)

# workers: default 20, but respect SLURM_CPUS_PER_TASK if present
req_workers <- parse_int(getenv1("N_WORKERS", "20"), 20L)
slurm_cpus  <- parse_int(getenv1("SLURM_CPUS_PER_TASK", ""), NA_integer_)
if (is.finite(slurm_cpus) && slurm_cpus > 0L) req_workers <- min(req_workers, slurm_cpus)
N_WORKERS <- max(1L, req_workers)

# In TEST_MODE, cap runtime
if (TEST_MODE) {
  N_SIMS <- min(N_SIMS, 200L)
  EFFECT_PCTS <- head(EFFECT_PCTS, 6)
  BATCH_SIZE <- min(BATCH_SIZE, 25L)
}

# ----------------------------- prelude/logging --------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run.log")
file.create(file.path(OUT_DIR, "STARTED.txt"))

PROGRESS_BATCHES <- file.path(OUT_DIR, "progress_batches.csv")
POWER_RUNNING    <- file.path(OUT_DIR, "power_by_effect_running.csv")

# initialize progress file with header (if not exists)
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
log_line(RUN_LOG, glue("SCRIPT_PATH: ", getwd()))
log_line(RUN_LOG, glue("R_VERSION  : {R.version.string}"))
log_line(RUN_LOG, glue("DATA_FILE  : {DATA_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE : {TREAT_FILE}"))
log_line(RUN_LOG, glue("OUT_DIR    : {OUT_DIR}"))
log_line(RUN_LOG, glue("OUTCOME    : {OUTCOME}  RATE_EPS={RATE_EPS}"))
log_line(RUN_LOG, glue("N_SIMS     : {N_SIMS}  BATCH_SIZE={BATCH_SIZE}"))
log_line(RUN_LOG, glue("EFFECT_PCTS: {paste(EFFECT_PCTS, collapse=', ')}"))
log_line(RUN_LOG, glue("ALPHA      : {ALPHA}  SEED={SEED}"))
log_line(RUN_LOG, glue("N_WORKERS  : {N_WORKERS} (SLURM_CPUS_PER_TASK={getenv1('SLURM_CPUS_PER_TASK','')})"))
log_line(RUN_LOG, glue("TEST_MODE  : {TEST_MODE}  DRY_RUN={DRY_RUN}"))
log_line(RUN_LOG, "=== END PRELUDE ===")

# ----------------------------- load + build panel -----------------------------

if (!file.exists(DATA_FILE)) {
  stop(glue("DATA_FILE not found: {DATA_FILE}"), call. = FALSE)
}
if (!file.exists(TREAT_FILE)) {
  stop(glue("TREAT_FILE not found: {TREAT_FILE}"), call. = FALSE)
}

# --- helpers for county->state mapping ---
# --- helpers for county->state mapping ---
# --- helpers for county->state mapping (no external datasets) ---
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
  
  # A) counties -> state-month (preferred when available)
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
  
  # B) state series fallback for states that lack county coverage in this file
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

# --- build the panel ---
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

# hard guard: if this isn't ~38, stop and show what you have
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

# Require treat_start coverage (it drives g)
if (all(is.na(panel$treat_start))) {
  stop("After merging, treat_start is missing for all rows. Check state_abbr mapping and TREAT_FILE.", call. = FALSE)
}

panel <- panel %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb))
  )
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

# Determine untreated observation: never-treated OR pre-treatment
panel <- panel %>%
  mutate(untreated_obs = (g == 0L) | (t < g))

# Basic checks + summaries
sched <- panel %>%
  group_by(state_abb) %>%
  summarise(
    g = first(g),
    treat_start = first(treat_start),
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

# FE model on untreated observations only (never-treated + pre)
base_dat <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))

# Ensure at least one untreated obs per month (needed for time FE prediction)
untreated_by_t <- base_dat %>% count(t, name = "n_untreated")
missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
if (length(missing_t) > 0) {
  # Drop months with no untreated obs at all (rare but possible late in sample)
  log_line(RUN_LOG, glue("WARNING: {length(missing_t)} months have zero untreated observations; dropping these months from simulation."))
  panel <- panel %>% filter(!t %in% missing_t)
  base_dat <- base_dat %>% filter(!t %in% missing_t)
}

# Fit unit+time FE on untreated
set.seed(SEED)
log_line(RUN_LOG, "Fitting unit+time FE on untreated observations...")
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_dat, notes = FALSE, warn = FALSE)

# Predict for all obs in (possibly trimmed) panel
panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

if (any(!is.finite(panel$yhat))) {
  # If there are any NA predictions (shouldn't happen), restrict to supported ids/t
  bad <- which(!is.finite(panel$yhat))
  log_line(RUN_LOG, glue("WARNING: {length(bad)} observations have non-finite yhat; dropping them from simulation."))
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_dat <- panel %>% filter(untreated_obs, is.finite(y))
}

# Residuals on untreated sample
base_dat$ehat <- as.numeric(residuals(fe_fit))

# residual pools by month t
resid_pool_by_t <- split(base_dat$ehat, base_dat$t)
global_pool <- base_dat$ehat
global_pool <- global_pool[is.finite(global_pool)]
# --- indices by state for fast within-state simulation ---
idx_by_id_time <- split(seq_len(nrow(panel)), panel$id)
idx_by_id_time <- lapply(idx_by_id_time, function(ii) ii[order(panel$t[ii])])

# --- AR(1) parameter estimate from untreated residuals (optional) ---
rho_hat <- ERR_AR1_RHO
if (!is.finite(rho_hat) && ERR_MODE == "ar1") {
  tmp <- base_dat[order(base_dat$id, base_dat$t), c("id","t","ehat")]
  tmp$ehat_lag <- ave(tmp$ehat, tmp$id, FUN = function(x) c(NA_real_, x[-length(x)]))
  ok <- is.finite(tmp$ehat) & is.finite(tmp$ehat_lag)
  if (sum(ok) < 50) {
    rho_hat <- 0
  } else {
    rho_hat <- sum(tmp$ehat[ok] * tmp$ehat_lag[ok]) / sum(tmp$ehat_lag[ok]^2)
  }
  rho_hat <- max(min(rho_hat, ERR_AR1_CLIP), -ERR_AR1_CLIP)
}

sigma_e <- stats::sd(global_pool, na.rm = TRUE)
sigma_u <- if (ERR_MODE == "ar1") sigma_e * sqrt(max(1 - rho_hat^2, 1e-8)) else NA_real_

# --- standardize residual pools by month for AR(1) innovations ---
mu_by_t <- tapply(base_dat$ehat, base_dat$t, mean, na.rm = TRUE)
sd_by_t <- tapply(base_dat$ehat, base_dat$t, sd,   na.rm = TRUE)

global_mu <- mean(global_pool, na.rm = TRUE)
global_sd <- stats::sd(global_pool, na.rm = TRUE)
sd_by_t[!is.finite(sd_by_t) | sd_by_t <= 0] <- global_sd

# month-specific standardized pools z = (e - mu_t)/sd_t
z_all <- (base_dat$ehat - mu_by_t[as.character(base_dat$t)]) / sd_by_t[as.character(base_dat$t)]
std_pool_by_t <- split(z_all[is.finite(z_all)], base_dat$t)

std_global <- (global_pool - global_mu) / global_sd
std_global <- std_global[is.finite(std_global)]

if (length(global_pool) < 20) {
  stop("Too few untreated residuals to simulate. Check panel/untreated definition.", call. = FALSE)
}

# ----------------------------- simulation core --------------------------------

# effect sizes on log scale
effect_tbl <- tibble::tibble(
  effect_pct = EFFECT_PCTS,
  effect_log = log(1 + EFFECT_PCTS)
)

# "post" indicator using observed adoption
panel$post_treat <- (panel$g > 0L) & (panel$t >= panel$g)

# deterministic seeds per sim to make parallel reproducible
sim_seeds <- SEED + seq_len(N_SIMS) * 10007L


# estimator choice for did::att_gt
did_method <- getenv1("DID_EST_METHOD", "ipw")

did_faster_mode <- parse_bool(getenv1("DID_FASTER_MODE", "FALSE"), FALSE)

did_control_group <- getenv1("DID_CONTROL_GROUP", "nevertreated")
if (!did_control_group %in% c("nevertreated", "notyettreated")) {
  stop(glue("DID_CONTROL_GROUP must be nevertreated or notyettreated; got {did_control_group}"), call. = FALSE)
}

# estimate one sim for a given effect
one_sim <- function(seed, effect_log, panel, resid_pool_by_t, global_pool,
                    alpha, did_method, did_control_group, did_faster_mode) {
  
  set.seed(seed)
  
  if (ERR_MODE == "iid_month") {
    tt <- panel$t
    e_draw <- vapply(tt, function(tt_i) {
      pool <- resid_pool_by_t[[as.character(tt_i)]]
      if (is.null(pool) || length(pool) < 2L) pool <- global_pool
      sample(pool, size = 1L, replace = TRUE)
    }, FUN.VALUE = 0.0)
    
  } else if (ERR_MODE == "ar1") {
    
    e_draw <- numeric(nrow(panel))
    
    for (ii in idx_by_id_time) {
      e_prev <- stats::rnorm(1L, mean = 0, sd = sigma_e)
      
      for (r in ii) {
        tt_chr <- as.character(panel$t[r])
        pool_z <- std_pool_by_t[[tt_chr]]
        if (is.null(pool_z) || length(pool_z) < 2L) pool_z <- std_global
        
        z <- sample(pool_z, size = 1L, replace = TRUE)
        e_prev <- rho_hat * e_prev + sigma_u * z
        e_draw[r] <- e_prev
      }
    }
    
  } else {
    stop(glue("Unknown ERR_MODE: {ERR_MODE}"), call. = FALSE)
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
        bstrap = TRUE,
        clustervars = "id"
      )
      
      
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
        biters = did_biters,
        clustervars = "id"
      )
      
      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)
      
      # Prefer package-provided p-value if present
      p <- if (!is.null(agg$overall.pval)) {
        as.numeric(agg$overall.pval)
      } else {
        z <- att / se
        if (is.finite(z)) 2 * stats::pnorm(-abs(z)) else NA_real_
      }
      
      
      if (!is.finite(miss_share) || miss_share >= 0.25) {
        stop(glue("Too many missing ATT(g,t) cells: miss_share={round(miss_share,3)}"))
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

one_sim_worker <- function(seed, effect_log) {
  one_sim(
    seed = seed,
    effect_log = effect_log,
    panel = panel,
    resid_pool_by_t = resid_pool_by_t,
    global_pool = global_pool,
    alpha = ALPHA,
    did_method = did_method,
    did_control_group = did_control_group,
    did_faster_mode = did_faster_mode,
  )
  if (use_parallel) {
    batch_out <- parallel::parLapply(cl, seeds_batch, one_sim_worker, effect_log = eff_log)
  } else {
    batch_out <- lapply(seeds_batch, one_sim_worker, effect_log = eff_log)
  }
  
}

# ----------------------------- parallel setup ---------------------------------

use_parallel <- (N_WORKERS > 1L)

if (use_parallel) {
  log_line(RUN_LOG, glue("Parallel: requested_workers={N_WORKERS}; using_workers={N_WORKERS}"))
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK", outfile = file.path(OUT_DIR, "cluster.log"))
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  # load packages on workers
  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(did)
      library(fixest)
    })
    NULL
  })

  # export objects + functions (avoid missing-function issues)
  parallel::clusterExport(
    cl,
    varlist = c(
      "one_sim","one_sim_worker","panel","resid_pool_by_t","global_pool",
      "ALPHA","did_method","did_control_group","did_faster_mode",
      "ERR_MODE","ERR_AR1_RHO","ERR_AR1_CLIP",
      "idx_by_id_time","rho_hat","sigma_e","sigma_u","std_pool_by_t","std_global"
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

  # run in batches for progress + checkpointing
  n_done <- 0L
  res_rows <- vector("list", N_SIMS)

  while (n_done < N_SIMS) {
    b_lo <- n_done + 1L
    b_hi <- min(N_SIMS, n_done + BATCH_SIZE)
    seeds_batch <- sim_seeds[b_lo:b_hi]

    t0 <- Sys.time()
    if (use_parallel) {
      batch_out <- parallel::parLapply(
        cl,
        seeds_batch,
        one_sim_worker,
        effect_log = eff_log
      )
    } else {
      batch_out <- lapply(
        seeds_batch,
        function(ss) one_sim(ss, effect_log = eff_log,
                             panel = panel,
                             resid_pool_by_t = resid_pool_by_t,
                             global_pool = global_pool,
                             alpha = ALPHA,
                             did_method = did_method)
      )
    }
    t1 <- Sys.time()

    # store
    idx <- seq_along(batch_out) + n_done
    res_rows[idx] <- batch_out
    n_done <- b_hi

    # progress
    ok_now <- sum(vapply(batch_out, function(x) isTRUE(x$ok), logical(1)))
    fail_now <- length(batch_out) - ok_now
    log_line(RUN_LOG, glue("Batch {b_lo}-{b_hi}/{N_SIMS}: ok={ok_now} fail={fail_now}  elapsed={round(as.numeric(difftime(t1,t0,units='secs')),1)}s"))
    
    # -------- streaming diagnostics (per batch) --------
    
    # Extract current batch vectors
    ok_b   <- vapply(batch_out, function(x) isTRUE(x$ok), logical(1))
    p_b    <- vapply(batch_out, function(x) x$p, numeric(1))
    att_b  <- vapply(batch_out, function(x) x$att, numeric(1))
    se_b   <- vapply(batch_out, function(x) x$se, numeric(1))
    
    # Cumulative vectors up to n_done (res_rows already filled up to n_done)
    ok_c   <- vapply(res_rows[seq_len(n_done)], function(x) isTRUE(x$ok), logical(1))
    p_c    <- vapply(res_rows[seq_len(n_done)], function(x) x$p, numeric(1))
    att_c  <- vapply(res_rows[seq_len(n_done)], function(x) x$att, numeric(1))
    se_c   <- vapply(res_rows[seq_len(n_done)], function(x) x$se, numeric(1))
    
    ok_c_n   <- sum(ok_c, na.rm = TRUE)
    fail_c_n <- n_done - ok_c_n
    fail_rate_cum <- fail_c_n / n_done
    
    # “Power so far” = Pr(p < alpha | ok)
    power_so_far <- if (ok_c_n > 0) mean(p_c[ok_c] < ALPHA, na.rm = TRUE) else NA_real_
    mean_att_so_far <- if (ok_c_n > 0) mean(att_c[ok_c], na.rm = TRUE) else NA_real_
    mean_se_so_far  <- if (ok_c_n > 0) mean(se_c[ok_c], na.rm = TRUE) else NA_real_
    
    # Type I so far (only meaningful for effect=0)
    type1_so_far <- NA_real_
    if (abs(eff_pct) < 1e-12 && ok_c_n > 0) {
      type1_so_far <- mean(p_c[ok_c] < ALPHA, na.rm = TRUE)
    }
    
    elapsed_sec <- as.numeric(difftime(t1, t0, units = "secs"))
    
    # Append one row to progress log
    append_csv(tibble::tibble(
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      effect_pct = eff_pct,
      effect_log = eff_log,
      batch_lo = b_lo,
      batch_hi = b_hi,
      n_done = n_done,
      n_sims = N_SIMS,
      ok_batch = sum(ok_b),
      fail_batch = sum(!ok_b),
      ok_cum = ok_c_n,
      fail_cum = fail_c_n,
      fail_rate_cum = fail_rate_cum,
      power_so_far = power_so_far,
      mean_att_so_far = mean_att_so_far,
      mean_se_so_far = mean_se_so_far,
      type1_so_far = type1_so_far,
      elapsed_sec_batch = elapsed_sec
    ), PROGRESS_BATCHES)
    
    # Update a “power_by_effect_running.csv” snapshot (appended each batch)
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
    
    # Running error counts for this effect (only write if there were failures)
    if (any(!ok_b)) {
      
      err_counts_path <- file.path(
        OUT_DIR,
        paste0("error_counts_running_effect_", fmt_eff(eff_pct), ".csv")
      )
      
      err_vec <- vapply(batch_out, function(x) {
        if (isTRUE(x$ok)) NA_character_ else as.character(x$err)
      }, character(1))
      
      err_tab <- tibble::tibble(err = err_vec) %>%
        dplyr::filter(!is.na(err), nzchar(err)) %>%
        dplyr::count(err, name = "n", sort = TRUE) %>%
        dplyr::mutate(n = as.integer(n))
      
      if (file.exists(err_counts_path)) {
        old <- readr::read_csv(
          err_counts_path,
          show_col_types = FALSE,
          col_types = readr::cols(
            err = readr::col_character(),
            n   = readr::col_integer()
          )
        ) %>%
          dplyr::mutate(n = as.integer(n))
        
        err_tab <- dplyr::bind_rows(old, err_tab) %>%
          dplyr::group_by(err) %>%
          dplyr::summarise(n = as.integer(sum(n, na.rm = TRUE)), .groups = "drop") %>%
          dplyr::arrange(dplyr::desc(n))
      }
      
      safe_write_csv(err_tab, err_counts_path)
    }
    
    # Also echo a short line to stdout (shows up in sbatch output)
    cat(glue::glue(
      "[{format(Sys.time(), '%H:%M:%S')}] eff={eff_pct} batch={b_lo}-{b_hi} ",
      "ok_cum={ok_c_n}/{n_done} fail_rate={round(fail_rate_cum,3)} ",
      "power_so_far={ifelse(is.finite(power_so_far), round(power_so_far,3), NA)}\n"
    ))
    flush.console()
    
    
    # checkpoint a tiny sample of draws for debugging
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

  # summarise this effect
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

  # write checkpoint
  safe_write_csv(dplyr::bind_rows(all_results), file.path(OUT_DIR, "power_by_effect.csv"))
}

# Draws sample (tiny)
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
  alpha = ALPHA,
  share_months_with_any_untreated = mean(table(base_dat$t) > 0)
)

# If effect 0 included, compute p-value distribution using draws_sample if present
if (any(abs(pwr$effect_pct) < 1e-12)) {
  # we don't store all p's; so do a quick additional run (small) for diagnostics
  n_diag <- min(400L, N_SIMS)
  diag_seeds <- sim_seeds[seq_len(n_diag)]
  eff0 <- 0.0

  log_line(RUN_LOG, glue("Computing diagnostics at effect=0 with n={n_diag}..."))

  if (use_parallel) {
    diag_out <- parallel::parLapply(cl, diag_seeds, one_sim_worker, effect_log = eff0)
  } else {
    diag_out <- lapply(diag_seeds, function(ss) {
      one_sim(ss, effect_log = eff0,
             panel = panel,
             resid_pool_by_t = resid_pool_by_t,
             global_pool = global_pool,
             alpha = ALPHA,
             did_method = did_method)
    })
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

  # Save histogram for effect=0 (only ok p-values)
  # Save histogram for effect=0 (only if we have at least a couple finite p-values)
  p0_ok <- p0[ok0]
  p0_ok <- p0_ok[is.finite(p0_ok)]
  
  # If nothing worked, write out the most common error messages to help debugging
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
    abline(v = ALPHA)
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
       main = glue("Power curve (N_SIMS={N_SIMS}, alpha={ALPHA}, method={did_method})"))
  grid()
  dev.off()
} else {
  log_line(RUN_LOG, "Skipping power_curve.png: no finite power values (all sims failed or p-values undefined).")
}


log_line(RUN_LOG, "=== DONE ===")
cat("Done. Outputs written to:", OUT_DIR, "\n")
