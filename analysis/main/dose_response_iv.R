#!/usr/bin/env Rscript
################################################################################
# dose_response_iv.R
#
# Dose-response IV analysis: effect of gambling handle per capita on evictions,
# instrumented by binary legalization.
#
# Specifications:
#   1) Binary TWFE (reduced form)
#   2) OLS with continuous log handle per 1k renters
#   3) IV/2SLS: log handle per 1k instrumented by binary legalization (MAIN)
#   4) IV with revenue instead of handle
#   5) First stage: legalization -> handle
#   6) Post-COVID IV sub-period
#   7) OLS + state-specific linear trends
#   8) IV + state-specific linear trends
#
# All configuration via environment variables.
# Run via: bash scripts/run_dose_response_iv.sh
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(fixest)
  library(glue)
})

source("utils/eviction_treatment_schedule.R")

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

state_name_to_abb <- eviction_state_name_to_abb

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

fmt_date <- function(d) {
  if (is.na(d)) "<none>" else format(d)
}

################################################################################
# SECTION 2: CONFIGURATION
################################################################################

PANEL_FILE     <- getenv1("PANEL_FILE", "data/raw/state_month_panel_with_treatment.csv")
HANDLE_FILE    <- getenv1("HANDLE_FILE", "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv")
TREAT_SOURCE   <- tolower(getenv1("TREAT_SOURCE", "file"))
TREAT_FILE     <- getenv1("TREAT_FILE", "data/raw/sports_gambling_legalization_dates.csv")
TREAT_DATE_COL <- getenv1("TREAT_DATE_COL", "online_start_date")
EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"))
MIN_DATE       <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE       <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
DROP_START     <- parse_date(getenv1("DROP_START", ""))
DROP_END       <- parse_date(getenv1("DROP_END", ""))
OUTCOME        <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS       <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)
ALPHA          <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
DO_LOO         <- parse_bool(getenv1("LOO", "TRUE"), TRUE)
DO_SUBPERIOD   <- parse_bool(getenv1("SUBPERIOD", "TRUE"), TRUE)
SUBPERIOD_START <- as.Date(getenv1("SUBPERIOD_START", "2022-04-01"))
OUT_DIR        <- getenv1("OUT_DIR", "output/dose_response_iv")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(OUT_DIR, "run_log.txt")
cat("", file = LOG_FILE)

log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- paste0("[", ts, "] ", msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# Clean stale outputs
known_outputs <- c(
  "README.md", "run_log.txt", "panel_summary.csv", "specifications_table.csv",
  "first_stage_detail.csv", "wald_decomposition.csv",
  "event_study_reduced_form.csv", "event_study_first_stage.csv",
  "loo_sensitivity.csv", "subperiod_results.csv",
  "handle_distribution.png", "first_stage_event_study.png",
  "reduced_form_event_study.png", "ols_vs_iv_comparison.png",
  "loo_sensitivity_plot.png"
)
for (f in known_outputs) {
  p <- file.path(OUT_DIR, f)
  if (file.exists(p)) file.remove(p)
}

log_msg("=== Dose-response IV analysis ===")
log_msg(glue("PANEL_FILE: {PANEL_FILE}"))
log_msg(glue("HANDLE_FILE: {HANDLE_FILE}"))
log_msg(glue("TREAT_SOURCE: {TREAT_SOURCE}"))
log_msg(glue("TREAT_FILE: {TREAT_FILE}"))
log_msg(glue("TREAT_DATE_COL: {TREAT_DATE_COL}"))
log_msg(glue("EXCLUDE_STATES: {paste(EXCLUDE_STATES, collapse=',')}"))
log_msg(glue("MIN_DATE: {MIN_DATE}  MAX_DATE: {MAX_DATE}"))
log_msg(glue("DROP_START: {fmt_date(DROP_START)}  DROP_END: {fmt_date(DROP_END)}"))
log_msg(glue("OUTCOME: {OUTCOME}  RATE_EPS: {RATE_EPS}"))
log_msg(glue("ALPHA: {ALPHA}"))
log_msg(glue("LOO: {DO_LOO}  SUBPERIOD: {DO_SUBPERIOD}"))
log_msg(glue("OUT_DIR: {OUT_DIR}"))

if (!file.exists(PANEL_FILE)) stop("PANEL_FILE not found: ", PANEL_FILE, call. = FALSE)
if (!file.exists(HANDLE_FILE)) stop("HANDLE_FILE not found: ", HANDLE_FILE, call. = FALSE)

################################################################################
# SECTION 3: LOAD AND PREPARE PANEL
################################################################################

log_msg("Loading eviction panel...")

panel0_raw <- readr::read_csv(PANEL_FILE, show_col_types = FALSE)
has_panel_treat <- "treat_start" %in% names(panel0_raw)

panel0 <- panel0_raw %>%
  transmute(
    state_abb  = as.character(state_abb),
    month_date = as.Date(month_date),
    panel_treat_start_raw = if (has_panel_treat) as.Date(treat_start) else as.Date(NA),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
    filings_per_1k_renters = as.numeric(filings_per_1k_renters)
  )

if (length(EXCLUDE_STATES) > 0) panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)

if (xor(is.na(DROP_START), is.na(DROP_END))) {
  stop("If setting DROP_START or DROP_END, set both.", call. = FALSE)
}
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  n0 <- nrow(panel0)
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
  log_msg(glue("Dropped months in [{DROP_START}, {DROP_END}]: removed {n0 - nrow(panel0)} rows"))
}

treat_by_state <- resolve_eviction_treatment_schedule(
  panel_df = panel0,
  treat_source = TREAT_SOURCE,
  treat_file = TREAT_FILE,
  treat_date_col = TREAT_DATE_COL,
  panel_treat_col = "panel_treat_start_raw"
)

if (TREAT_SOURCE == "file" && has_panel_treat) {
  panel_treat_by_state <- resolve_eviction_treatment_schedule(
    panel_df = panel0,
    treat_source = "panel",
    panel_treat_col = "panel_treat_start_raw"
  ) %>%
    rename(panel_treat_start = treat_start)

  treat_mismatch <- treat_by_state %>%
    left_join(panel_treat_by_state, by = "state_abb") %>%
    mutate(
      mismatch = xor(is.na(treat_start), is.na(panel_treat_start)) |
        (!is.na(treat_start) & !is.na(panel_treat_start) & treat_start != panel_treat_start)
    ) %>%
    filter(mismatch)

  if (nrow(treat_mismatch) > 0) {
    log_msg(glue(
      "Treatment schedule differs from embedded panel treat_start for {nrow(treat_mismatch)} states: ",
      "{paste(treat_mismatch$state_abb, collapse=', ')}"
    ))
  } else {
    log_msg("Treatment schedule matches embedded panel treat_start for all states in sample.")
  }
}

# --- Load handle data ---
log_msg("Loading handle data...")

handle_raw <- readr::read_csv(HANDLE_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb  = state_name_to_abb(State),
    month_date = as.Date(month_date),
    handle     = suppressWarnings(as.numeric(Handle)),
    revenue    = suppressWarnings(as.numeric(Revenue))
  ) %>%
  filter(!is.na(state_abb), !is.na(month_date))

# Aggregate to state-month (in case of duplicates)
handle <- handle_raw %>%
  group_by(state_abb, month_date) %>%
  summarise(
    handle  = sum(handle, na.rm = TRUE),
    revenue = sum(revenue, na.rm = TRUE),
    .groups = "drop"
  )

# Find first handle date per state (for imputation)
first_handle <- handle %>%
  filter(handle > 0 | revenue > 0) %>%
  group_by(state_abb) %>%
  summarise(first_handle_date = min(month_date), .groups = "drop")

log_msg(glue("Handle data: {nrow(handle)} state-months, {n_distinct(handle$state_abb)} states"))

# --- Merge handle into panel ---
panel <- panel0 %>%
  left_join(treat_by_state, by = "state_abb") %>%
  left_join(handle, by = c("state_abb", "month_date")) %>%
  left_join(first_handle, by = "state_abb")

# Impute 0 for pre-legalization months (handle is literally 0 before legal)
# For treated states without handle data, flag them
treated_no_handle <- panel %>%
  filter(!is.na(treat_start)) %>%
  distinct(state_abb) %>%
  anti_join(first_handle, by = "state_abb")

if (nrow(treated_no_handle) > 0) {
  log_msg(glue("WARNING: {nrow(treated_no_handle)} treated states have no handle data: {paste(treated_no_handle$state_abb, collapse=', ')}"))
  log_msg("These states will be excluded from the dose-response/IV sample.")
}

# States in handle data but not in eviction panel
handle_no_panel <- first_handle %>%
  anti_join(panel0 %>% distinct(state_abb), by = "state_abb")
if (nrow(handle_no_panel) > 0) {
  log_msg(glue("Note: {nrow(handle_no_panel)} states with handle data not in eviction panel: {paste(handle_no_panel$state_abb, collapse=', ')}"))
}

# Impute zeros only when handle is structurally zero. Keep post-launch gaps as NA.
panel <- panel %>%
  mutate(
    handle = case_when(
      is.finite(handle) ~ handle,
      is.na(treat_start) ~ 0,
      month_date < treat_start ~ 0,
      !is.na(first_handle_date) & month_date < first_handle_date ~ 0,
      TRUE ~ NA_real_
    ),
    revenue = case_when(
      is.finite(revenue) ~ revenue,
      is.na(treat_start) ~ 0,
      month_date < treat_start ~ 0,
      !is.na(first_handle_date) & month_date < first_handle_date ~ 0,
      TRUE ~ NA_real_
    )
  )

# --- Compute analysis variables ---
panel <- panel %>%
  mutate(
    id = as.integer(as.factor(state_abb)),
    t  = ym_index(month_date),
    g  = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g  = as.integer(g),
    post_treat = as.integer(g > 0L & t >= g),
    event_time = ifelse(g > 0L, t - g, NA_integer_),

    # Per-capita handle
    handle_per_1k = if_else(
      !is.na(handle) & !is.na(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
      1000 * handle / renter_occupied_housing_units,
      NA_real_
    ),
    revenue_per_1k = if_else(
      !is.na(revenue) & !is.na(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
      1000 * revenue / renter_occupied_housing_units,
      NA_real_
    ),
    log1p_handle_per_1k  = if_else(is.finite(handle_per_1k), log1p(handle_per_1k), NA_real_),
    log1p_revenue_per_1k = if_else(is.finite(revenue_per_1k), log1p(revenue_per_1k), NA_real_),

    # Outcome
    y = dplyr::case_when(
      OUTCOME == "log1p_filings_count" ~ log1p(pmax(filings_count, 0)),
      OUTCOME == "log1p_rate" ~ log(pmax(filings_per_1k_renters, 0) + RATE_EPS),
      TRUE ~ NA_real_
    )
  )

dose_excluded_states <- sort(unique(treated_no_handle$state_abb))
analysis_panel <- if (length(dose_excluded_states) > 0) {
  panel %>% filter(!(state_abb %in% dose_excluded_states))
} else {
  panel
}

post_launch_missing <- analysis_panel %>%
  filter(
    !is.na(first_handle_date),
    month_date >= first_handle_date,
    is.na(handle)
  )

if (nrow(post_launch_missing) > 0) {
  log_msg(glue(
    "WARNING: {nrow(post_launch_missing)} post-launch state-months still have missing handle values ",
    "across {n_distinct(post_launch_missing$state_abb)} states; continuous/IV specs will drop those rows."
  ))
}

# --- Panel summary ---
n_states_full  <- n_distinct(panel$state_abb)
n_treated_full <- n_distinct(panel$state_abb[panel$g > 0L])
n_never_full   <- n_distinct(panel$state_abb[panel$g == 0L])
n_t_full       <- n_distinct(panel$t)

n_states  <- n_distinct(analysis_panel$state_abb)
n_treated <- n_distinct(analysis_panel$state_abb[analysis_panel$g > 0L])
n_never   <- n_distinct(analysis_panel$state_abb[analysis_panel$g == 0L])
n_with_handle <- n_distinct(analysis_panel$state_abb[analysis_panel$state_abb %in% first_handle$state_abb])
n_t       <- n_distinct(analysis_panel$t)

log_msg(glue("Full merged panel: {n_states_full} states ({n_treated_full} treated, {n_never_full} never-treated), {n_t_full} months, {nrow(panel)} obs"))
log_msg(glue("Dose-response sample: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_t} months, {nrow(analysis_panel)} obs"))
log_msg(glue("States with handle data in dose-response sample: {n_with_handle}"))
if (length(dose_excluded_states) > 0) {
  log_msg(glue("Excluded treated states with no handle data: {paste(dose_excluded_states, collapse=', ')}"))
}

# Handle summary for treated states post-treatment
handle_post <- analysis_panel %>% filter(post_treat == 1, handle > 0, is.finite(handle_per_1k))
if (nrow(handle_post) > 0) {
  log_msg(glue("Post-treatment handle: mean={round(mean(handle_post$handle_per_1k), 1)} per 1k, ",
               "median={round(median(handle_post$handle_per_1k), 1)}, ",
               "max={round(max(handle_post$handle_per_1k), 1)} ({n_distinct(handle_post$state_abb)} states)"))
}

panel_summary <- tibble(
  n_states_full = n_states_full,
  n_treated_full = n_treated_full,
  n_never_treated_full = n_never_full,
  n_obs_full = nrow(panel),
  n_states_dose = n_states,
  n_treated_dose = n_treated,
  n_never_treated_dose = n_never,
  n_with_handle_dose = n_with_handle,
  n_months_dose = n_t,
  n_obs_dose = nrow(analysis_panel),
  min_date = min(analysis_panel$month_date),
  max_date = max(analysis_panel$month_date),
  drop_start = fmt_date(DROP_START), drop_end = fmt_date(DROP_END),
  treat_source = TREAT_SOURCE,
  treat_date_col = TREAT_DATE_COL,
  n_excluded_treated_no_handle = length(dose_excluded_states),
  excluded_treated_no_handle = if (length(dose_excluded_states) > 0) paste(dose_excluded_states, collapse = ",") else NA_character_,
  n_post_launch_missing_state_months = nrow(post_launch_missing),
  outcome = OUTCOME,
  mean_handle_per_1k_post = if (nrow(handle_post) > 0) round(mean(handle_post$handle_per_1k), 2) else NA_real_,
  median_handle_per_1k_post = if (nrow(handle_post) > 0) round(median(handle_post$handle_per_1k), 2) else NA_real_
)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

################################################################################
# SECTION 4: DESCRIPTIVE STATISTICS
################################################################################

log_msg("Generating descriptive plots...")

# Handle distribution across treated state-months
handle_treated <- analysis_panel %>%
  filter(post_treat == 1, is.finite(handle_per_1k), handle_per_1k > 0)

if (nrow(handle_treated) > 0) {
  p_dist <- ggplot(handle_treated, aes(x = handle_per_1k)) +
    geom_histogram(bins = 40, fill = "steelblue", color = "white", alpha = 0.8) +
    scale_x_log10(labels = scales::comma_format()) +
    labs(
      title = "Distribution of Handle per 1k Renters (Treated State-Months)",
      x = "Handle per 1k Renter Households (log scale)",
      y = "Count"
    ) +
    theme_minimal(base_size = 12)
  ggsave(file.path(OUT_DIR, "handle_distribution.png"), p_dist, width = 8, height = 5, dpi = 150)
}

################################################################################
# SECTION 5: MAIN SPECIFICATIONS
################################################################################

log_msg("Running main specifications...")

crit <- qnorm(1 - ALPHA / 2)
results <- list()

extract_spec <- function(mod, name, spec_num, is_iv = FALSE, endo_var = NULL) {
  cf <- coef(mod)
  se <- se(mod)

  # For IV, get the endogenous variable coefficient
  if (is_iv && !is.null(endo_var)) {
    idx <- grep(endo_var, names(cf), fixed = TRUE)
    if (length(idx) == 0) idx <- 1
    var_name <- names(cf)[idx[1]]
  } else {
    var_name <- names(cf)[1]
  }

  est  <- cf[var_name]
  s    <- se[var_name]
  p    <- pvalue(mod)[var_name]

  # First-stage F for IV models
  fs_f <- NA_real_
  if (is_iv) {
    tryCatch({
      fs <- fitstat(mod, "ivf")
      fs_f <- fs[[1]]$stat
    }, error = function(e) {})
  }

  tibble(
    spec = spec_num, name = name, variable = var_name,
    coef = unname(est), se = unname(s),
    p_value = unname(p),
    ci_lo = unname(est - crit * s), ci_hi = unname(est + crit * s),
    n_obs = nobs(mod), first_stage_F = fs_f,
    is_iv = is_iv
  )
}

# Spec 1: Binary TWFE (reduced form)
log_msg("  Spec 1: Binary TWFE...")
mod1 <- feols(y ~ post_treat | id + t, data = analysis_panel, cluster = ~id)
results[[1]] <- extract_spec(mod1, "Binary TWFE (reduced form)", 1)

# Spec 2: OLS continuous handle
log_msg("  Spec 2: OLS continuous handle...")
mod2 <- feols(y ~ log1p_handle_per_1k | id + t, data = analysis_panel, cluster = ~id)
results[[2]] <- extract_spec(mod2, "OLS continuous handle", 2)

# Spec 3: IV/2SLS (main specification)
log_msg("  Spec 3: IV/2SLS (main)...")
mod3 <- feols(y ~ 1 | id + t | log1p_handle_per_1k ~ post_treat, data = analysis_panel, cluster = ~id)
results[[3]] <- extract_spec(mod3, "IV/2SLS (main)", 3, is_iv = TRUE, endo_var = "log1p_handle_per_1k")

# Spec 4: IV with revenue
log_msg("  Spec 4: IV with revenue...")
mod4 <- feols(y ~ 1 | id + t | log1p_revenue_per_1k ~ post_treat, data = analysis_panel, cluster = ~id)
results[[4]] <- extract_spec(mod4, "IV revenue", 4, is_iv = TRUE, endo_var = "log1p_revenue_per_1k")

# Spec 5: First stage
log_msg("  Spec 5: First stage...")
mod5 <- feols(log1p_handle_per_1k ~ post_treat | id + t, data = analysis_panel, cluster = ~id)
results[[5]] <- extract_spec(mod5, "First stage (handle)", 5)

# Spec 6: Post-COVID IV sub-period (run later in Section 10 if enabled)
# Placeholder — filled in Section 10

# Spec 7: OLS + state-specific linear trends
log_msg("  Spec 7: OLS + state trends...")
mod7 <- tryCatch(
  feols(y ~ log1p_handle_per_1k | id + t + id[t], data = analysis_panel, cluster = ~id),
  error = function(e) { log_msg(glue("  Spec 7 failed: {e$message}")); NULL }
)
if (!is.null(mod7)) {
  results[[7]] <- extract_spec(mod7, "OLS + state trends", 7)
}

# Spec 8: IV + state-specific linear trends
log_msg("  Spec 8: IV + state trends...")
mod8 <- tryCatch(
  feols(y ~ 1 | id + t + id[t] | log1p_handle_per_1k ~ post_treat, data = analysis_panel, cluster = ~id),
  error = function(e) { log_msg(glue("  Spec 8 failed: {e$message}")); NULL }
)
if (!is.null(mod8)) {
  results[[8]] <- extract_spec(mod8, "IV + state trends", 8, is_iv = TRUE, endo_var = "log1p_handle_per_1k")
}

spec_table <- bind_rows(results)
safe_write_csv(spec_table, file.path(OUT_DIR, "specifications_table.csv"))

log_msg("Specifications summary:")
for (i in seq_len(nrow(spec_table))) {
  r <- spec_table[i, ]
  sig_marker <- if (!is.na(r$p_value) && r$p_value < ALPHA) " *" else ""
  fs_str <- if (!is.na(r$first_stage_F)) glue(", F={round(r$first_stage_F, 1)}") else ""
  log_msg(glue("  {r$spec}. {r$name}: coef={round(r$coef, 4)}, SE={round(r$se, 4)}, p={round(r$p_value, 4)}{sig_marker}{fs_str}"))
}

################################################################################
# SECTION 6: FIRST-STAGE DIAGNOSTICS
################################################################################

log_msg("First-stage diagnostics...")

fs_coef <- coef(mod5)["post_treat"]
fs_se   <- se(mod5)["post_treat"]
fs_p    <- pvalue(mod5)["post_treat"]

# Partial R-squared from the first stage
fs_r2 <- tryCatch(r2(mod5, "ar2"), error = function(e) NA_real_)

# F-stat from IV model
fs_f_from_iv <- tryCatch({
  fs <- fitstat(mod3, "ivf")
  fs[[1]]$stat
}, error = function(e) NA_real_)

first_stage_detail <- tibble(
  first_stage_coef = unname(fs_coef),
  first_stage_se   = unname(fs_se),
  first_stage_p    = unname(fs_p),
  first_stage_F    = fs_f_from_iv,
  adj_r_squared    = if (is.numeric(fs_r2)) unname(fs_r2) else NA_real_,
  interpretation   = glue("Legalization increases log(1+handle_per_1k) by {round(fs_coef, 3)} (SE={round(fs_se, 3)})")
)
safe_write_csv(first_stage_detail, file.path(OUT_DIR, "first_stage_detail.csv"))

log_msg(glue("  First stage: coef={round(fs_coef, 4)}, SE={round(fs_se, 4)}, F={round(fs_f_from_iv, 1)}"))

if (!is.na(fs_f_from_iv) && fs_f_from_iv < 10) {
  log_msg("  WARNING: First-stage F < 10 — weak instrument concern!")
}

################################################################################
# SECTION 7: WALD DECOMPOSITION
################################################################################

log_msg("Wald decomposition...")

rf_coef <- coef(mod1)["post_treat"]
rf_se   <- se(mod1)["post_treat"]

wald_ratio <- unname(rf_coef / fs_coef)

# Delta method SE for ratio: se(a/b) = |a/b| * sqrt((se_a/a)^2 + (se_b/b)^2)
# (assuming independence, which is approximate)
wald_se <- abs(wald_ratio) * sqrt((rf_se / rf_coef)^2 + (fs_se / fs_coef)^2)

# IV coefficient for comparison
iv_coef_main <- spec_table %>% filter(spec == 3) %>% pull(coef)

wald_decomp <- tibble(
  reduced_form_coef = unname(rf_coef),
  reduced_form_se   = unname(rf_se),
  first_stage_coef  = unname(fs_coef),
  first_stage_se    = unname(fs_se),
  wald_ratio        = wald_ratio,
  wald_se_delta     = wald_se,
  iv_coef_feols     = iv_coef_main,
  wald_iv_diff      = wald_ratio - iv_coef_main,
  note              = "wald_ratio should approximately equal iv_coef_feols"
)
safe_write_csv(wald_decomp, file.path(OUT_DIR, "wald_decomposition.csv"))

log_msg(glue("  Wald ratio: {round(wald_ratio, 4)} (delta SE={round(wald_se, 4)})"))
log_msg(glue("  IV from feols: {round(iv_coef_main, 4)}"))
log_msg(glue("  Difference: {round(wald_ratio - iv_coef_main, 6)}"))

################################################################################
# SECTION 8: EVENT STUDY
################################################################################

log_msg("Running event studies...")

# Only treated states for event study
panel_treated <- analysis_panel %>% filter(g > 0L)

# Bin event times: cap at -12 and +24
panel_treated <- panel_treated %>%
  mutate(
    et_bin = case_when(
      event_time < -12L ~ -13L,
      event_time > 24L  ~ 25L,
      TRUE ~ event_time
    )
  )

# Check we have enough variation
n_et <- n_distinct(panel_treated$et_bin[!is.na(panel_treated$et_bin)])
if (n_et < 4) {
  log_msg("WARNING: Too few event-time bins for event study, skipping.")
} else {
  # Reduced-form event study (binary treatment)
  log_msg("  Reduced-form event study...")
  mod_es_rf <- tryCatch(
    feols(y ~ i(et_bin, ref = -1) | id + t, data = panel_treated, cluster = ~id),
    error = function(e) { log_msg(glue("  RF event study failed: {e$message}")); NULL }
  )

  if (!is.null(mod_es_rf)) {
    es_rf <- broom::tidy(mod_es_rf, conf.int = TRUE, conf.level = 1 - ALPHA) %>%
      mutate(
        event_time = as.integer(gsub(".*::(-?\\d+)$", "\\1", term)),
        method = "reduced_form"
      ) %>%
      select(event_time, estimate, std.error, p.value, conf.low, conf.high, method)
    safe_write_csv(es_rf, file.path(OUT_DIR, "event_study_reduced_form.csv"))

    # Plot
    p_rf <- ggplot(es_rf, aes(x = event_time, y = estimate)) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
      geom_vline(xintercept = -0.5, linetype = "dotted", color = "red", alpha = 0.5) +
      geom_ribbon(aes(ymin = conf.low, ymax = conf.high), fill = "steelblue", alpha = 0.2) +
      geom_line(color = "steelblue", linewidth = 0.8) +
      geom_point(color = "steelblue", size = 1.5) +
      labs(
        title = "Reduced-Form Event Study (Binary Treatment)",
        subtitle = "Effect of legalization on log(1+filings), ref = t-1",
        x = "Months Relative to Legalization",
        y = "Coefficient"
      ) +
      theme_minimal(base_size = 12)
    ggsave(file.path(OUT_DIR, "reduced_form_event_study.png"), p_rf, width = 10, height = 6, dpi = 150)
  }

  # First-stage event study (handle by event time)
  log_msg("  First-stage event study...")
  mod_es_fs <- tryCatch(
    feols(log1p_handle_per_1k ~ i(et_bin, ref = -1) | id + t, data = panel_treated, cluster = ~id),
    error = function(e) { log_msg(glue("  FS event study failed: {e$message}")); NULL }
  )

  if (!is.null(mod_es_fs)) {
    es_fs <- broom::tidy(mod_es_fs, conf.int = TRUE, conf.level = 1 - ALPHA) %>%
      mutate(
        event_time = as.integer(gsub(".*::(-?\\d+)$", "\\1", term)),
        method = "first_stage"
      ) %>%
      select(event_time, estimate, std.error, p.value, conf.low, conf.high, method)
    safe_write_csv(es_fs, file.path(OUT_DIR, "event_study_first_stage.csv"))

    # Plot
    p_fs <- ggplot(es_fs, aes(x = event_time, y = estimate)) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
      geom_vline(xintercept = -0.5, linetype = "dotted", color = "red", alpha = 0.5) +
      geom_ribbon(aes(ymin = conf.low, ymax = conf.high), fill = "darkgreen", alpha = 0.2) +
      geom_line(color = "darkgreen", linewidth = 0.8) +
      geom_point(color = "darkgreen", size = 1.5) +
      labs(
        title = "First-Stage Event Study (Handle Ramp-Up)",
        subtitle = "Effect of legalization on log(1+handle_per_1k), ref = t-1",
        x = "Months Relative to Legalization",
        y = "log(1 + Handle per 1k Renters)"
      ) +
      theme_minimal(base_size = 12)
    ggsave(file.path(OUT_DIR, "first_stage_event_study.png"), p_fs, width = 10, height = 6, dpi = 150)
  }
}

################################################################################
# SECTION 9: OLS vs IV COMPARISON PLOT
################################################################################

log_msg("Generating OLS vs IV comparison plot...")

comparison_specs <- spec_table %>%
  filter(spec %in% c(1, 2, 3, 4)) %>%
  mutate(
    label = factor(name, levels = name),
    color = c("gray40", "coral", "steelblue", "darkgreen")[seq_len(n())]
  )

if (nrow(comparison_specs) > 0) {
  p_comp <- ggplot(comparison_specs, aes(x = label, y = coef)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi), size = 0.8, linewidth = 0.8,
                    color = c("gray40", "coral", "steelblue", "darkgreen")[seq_len(nrow(comparison_specs))]) +
    coord_flip() +
    labs(
      title = "Specification Comparison",
      subtitle = glue("N={comparison_specs$n_obs[1]} state-months | {n_states} states | {100*(1-ALPHA)}% CI"),
      x = NULL, y = "Coefficient on Treatment / Handle"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"))
  ggsave(file.path(OUT_DIR, "ols_vs_iv_comparison.png"), p_comp, width = 9, height = 5, dpi = 150)
}

################################################################################
# SECTION 10: LOO SENSITIVITY
################################################################################

if (DO_LOO) {
  log_msg("Running leave-one-out sensitivity (IV)...")

  all_states <- sort(unique(analysis_panel$state_abb))
  loo_results <- list()

  for (s in all_states) {
    panel_loo <- analysis_panel %>% filter(state_abb != s)
    mod_loo <- tryCatch(
      feols(y ~ 1 | id + t | log1p_handle_per_1k ~ post_treat, data = panel_loo, cluster = ~id),
      error = function(e) NULL
    )
    if (!is.null(mod_loo)) {
      cf <- coef(mod_loo)
      idx <- grep("log1p_handle_per_1k", names(cf), fixed = TRUE)
      if (length(idx) == 0) idx <- 1
      vn <- names(cf)[idx[1]]

      fs_loo <- tryCatch({
        fs <- fitstat(mod_loo, "ivf")
        fs[[1]]$stat
      }, error = function(e) NA_real_)

      loo_results[[s]] <- tibble(
        dropped_state = s,
        iv_coef = unname(cf[vn]),
        iv_se = unname(se(mod_loo)[vn]),
        iv_p = unname(pvalue(mod_loo)[vn]),
        first_stage_F = fs_loo,
        n_obs = nobs(mod_loo)
      )
    }
  }

  if (length(loo_results) > 0) {
    loo_df <- bind_rows(loo_results)
    safe_write_csv(loo_df, file.path(OUT_DIR, "loo_sensitivity.csv"))

    # Full-sample IV for reference
    full_iv <- spec_table %>% filter(spec == 3) %>% pull(coef)

    p_loo <- ggplot(loo_df, aes(x = reorder(dropped_state, iv_coef), y = iv_coef)) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
      geom_hline(yintercept = full_iv, linetype = "solid", color = "steelblue", alpha = 0.5) +
      geom_point(size = 2, color = "steelblue") +
      geom_errorbar(aes(ymin = iv_coef - 1.96 * iv_se, ymax = iv_coef + 1.96 * iv_se),
                    width = 0.3, color = "steelblue", alpha = 0.6) +
      coord_flip() +
      labs(
        title = "Leave-One-Out IV Sensitivity",
        subtitle = "IV estimate when each state is dropped (blue line = full sample)",
        x = "Dropped State", y = "IV Coefficient"
      ) +
      theme_minimal(base_size = 11)
    ggsave(file.path(OUT_DIR, "loo_sensitivity_plot.png"), p_loo, width = 9, height = 8, dpi = 150)

    # Check stability
    loo_range <- range(loo_df$iv_coef)
    log_msg(glue("  LOO IV range: [{round(loo_range[1], 4)}, {round(loo_range[2], 4)}]"))
    sign_changes <- sum(sign(loo_df$iv_coef) != sign(full_iv))
    log_msg(glue("  Sign changes: {sign_changes}/{nrow(loo_df)}"))
  }
} else {
  log_msg("LOO sensitivity skipped (LOO=FALSE).")
}

################################################################################
# SECTION 11: SUB-PERIOD ANALYSIS (Post-COVID only)
################################################################################

if (DO_SUBPERIOD) {
  log_msg(glue("Running sub-period analysis (>= {SUBPERIOD_START})..."))

  panel_sub <- analysis_panel %>% filter(month_date >= SUBPERIOD_START)
  n_sub <- nrow(panel_sub)
  n_states_sub <- n_distinct(panel_sub$state_abb)
  n_treated_sub <- n_distinct(panel_sub$state_abb[panel_sub$post_treat == 1])

  log_msg(glue("  Sub-period panel: {n_states_sub} states ({n_treated_sub} with post-treatment obs), {n_sub} obs"))

  sub_results <- list()

  # Sub Spec 1: Binary TWFE
  mod_sub1 <- tryCatch(
    feols(y ~ post_treat | id + t, data = panel_sub, cluster = ~id),
    error = function(e) { log_msg(glue("  Sub spec 1 failed: {e$message}")); NULL }
  )
  if (!is.null(mod_sub1)) sub_results[[1]] <- extract_spec(mod_sub1, "Sub: Binary TWFE", 1)

  # Sub Spec 2: OLS continuous
  mod_sub2 <- tryCatch(
    feols(y ~ log1p_handle_per_1k | id + t, data = panel_sub, cluster = ~id),
    error = function(e) { log_msg(glue("  Sub spec 2 failed: {e$message}")); NULL }
  )
  if (!is.null(mod_sub2)) sub_results[[2]] <- extract_spec(mod_sub2, "Sub: OLS continuous", 2)

  # Sub Spec 3: IV
  mod_sub3 <- tryCatch(
    feols(y ~ 1 | id + t | log1p_handle_per_1k ~ post_treat, data = panel_sub, cluster = ~id),
    error = function(e) { log_msg(glue("  Sub spec 3 failed: {e$message}")); NULL }
  )
  if (!is.null(mod_sub3)) sub_results[[3]] <- extract_spec(mod_sub3, "Sub: IV/2SLS", 3, is_iv = TRUE, endo_var = "log1p_handle_per_1k")

  if (length(sub_results) > 0) {
    sub_table <- bind_rows(sub_results)
    safe_write_csv(sub_table, file.path(OUT_DIR, "subperiod_results.csv"))

    for (i in seq_len(nrow(sub_table))) {
      r <- sub_table[i, ]
      fs_str <- if (!is.na(r$first_stage_F)) glue(", F={round(r$first_stage_F, 1)}") else ""
      log_msg(glue("  {r$name}: coef={round(r$coef, 4)}, SE={round(r$se, 4)}, p={round(r$p_value, 4)}{fs_str}"))
    }
  }
} else {
  log_msg("Sub-period analysis skipped (SUBPERIOD=FALSE).")
}

################################################################################
# SECTION 12: SUMMARY README
################################################################################

log_msg("Assembling README...")

iv_row <- spec_table %>% filter(spec == 3)
rf_row <- spec_table %>% filter(spec == 1)

readme_lines <- c(
  "# Dose-Response IV Analysis: Gambling Handle on Evictions",
  "",
  glue("**Generated**: {Sys.time()}"),
  "",
  "## Design",
  "",
  "Continuous treatment: log(1 + handle per 1k renters), instrumented by binary legalization.",
  glue("- Treatment source: {TREAT_SOURCE} ({TREAT_DATE_COL}) from `{TREAT_FILE}`"),
  glue("- Dose-response sample: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_t} months, {nrow(analysis_panel)} obs"),
  glue("- Full merged panel before dose exclusions: {n_states_full} states, {nrow(panel)} obs"),
  glue("- Date range: {min(analysis_panel$month_date)} to {max(analysis_panel$month_date)}"),
  if (!is.na(DROP_START)) glue("- COVID gap: {DROP_START} to {DROP_END}") else "- No COVID gap",
  glue("- Outcome: {OUTCOME}"),
  glue("- States with handle data: {n_with_handle}"),
  if (length(dose_excluded_states) > 0) {
    glue("- Excluded treated states with no handle data: {paste(dose_excluded_states, collapse=', ')}")
  } else {
    "- Excluded treated states with no handle data: none"
  },
  if (nrow(post_launch_missing) > 0) {
    glue("- Post-launch missing handle observations kept as NA: {nrow(post_launch_missing)}")
  } else {
    "- Post-launch missing handle observations kept as NA: 0"
  },
  "",
  "## Key Results",
  "",
  glue("### Reduced form (binary TWFE)"),
  glue("- Coefficient: {round(rf_row$coef, 4)} (SE = {round(rf_row$se, 4)}, p = {round(rf_row$p_value, 4)})"),
  "",
  glue("### First stage"),
  glue("- Coefficient: {round(fs_coef, 4)} (SE = {round(fs_se, 4)})"),
  glue("- F-statistic: {round(fs_f_from_iv, 1)}"),
  "",
  glue("### IV/2SLS (main specification)"),
  glue("- Coefficient: {round(iv_row$coef, 4)} (SE = {round(iv_row$se, 4)}, p = {round(iv_row$p_value, 4)})"),
  glue("- 95% CI: [{round(iv_row$ci_lo, 4)}, {round(iv_row$ci_hi, 4)}]"),
  glue("- Interpretation: A 1-unit increase in log(1+handle_per_1k) is associated with a"),
  glue("  {round(iv_row$coef, 4)} change in log(1+eviction_filings)"),
  "",
  "### Wald decomposition",
  glue("- Wald ratio: {round(wald_ratio, 4)} (should equal IV coefficient)"),
  "",
  "## Files",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `specifications_table.csv` | All specifications with coefficients, SEs, CIs |",
  "| `first_stage_detail.csv` | First-stage diagnostics |",
  "| `wald_decomposition.csv` | Reduced form / first stage decomposition |",
  "| `event_study_reduced_form.csv` | Binary event study coefficients |",
  "| `event_study_first_stage.csv` | Handle ramp-up by event time |",
  if (DO_LOO) "| `loo_sensitivity.csv` | Leave-one-out IV estimates |" else NULL,
  if (DO_SUBPERIOD) "| `subperiod_results.csv` | Post-COVID sub-period results |" else NULL,
  "| `run_log.txt` | Execution log |",
  ""
)

writeLines(readme_lines[!sapply(readme_lines, is.null)], file.path(OUT_DIR, "README.md"))

log_msg("=== Done ===")
log_msg(glue("Output directory: {OUT_DIR}"))
for (f in list.files(OUT_DIR)) {
  log_msg(glue("  - {f}"))
}
