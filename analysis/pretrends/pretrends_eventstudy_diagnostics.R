#!/usr/bin/env Rscript
################################################################################
# pretrends_eventstudy_diagnostics.R
#
# Pre-trends / event-study diagnostics pipeline combining:
#   - Callaway–Sant'Anna DiD (did package)
#   - TWFE event-study (fixest)
#   - Pre-trends testing methods (Roth et al.)
#
# Uses identical env vars + panel build as TWFE power simulation script
################################################################################

# Force single-threaded to prevent conflicts/crashes
Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(tibble)
  library(ggplot2)
  library(did)
  library(fixest)
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

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

log_line <- function(path, msg) cat(msg, "\n", file = path, append = TRUE)

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d < end)
}

# ----------------------------- config -----------------------------------------

# Core files
DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "pretrends_out")

# Outcome specification
OUTCOME  <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

# General settings
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED  <- parse_int(getenv1("SEED", "123"), 123L)
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
if (!is.finite(MIN_STATES_PER_MONTH) || MIN_STATES_PER_MONTH < 2L) MIN_STATES_PER_MONTH <- 2L

# Filtering
EXCLUDE_STATES_VEC <- parse_state_list(getenv1("EXCLUDE_STATES", ""))
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))
EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))
EXCLUDE_END   <- as.Date(getenv1("EXCLUDE_END", ""))
DROP_START <- as.Date(getenv1("DROP_START", ""))
DROP_END   <- as.Date(getenv1("DROP_END", ""))

# CS-DiD specific settings
DID_EST_METHOD       <- tolower(getenv1("DID_EST_METHOD", "reg"))
DID_CONTROL_GROUP    <- tolower(getenv1("DID_CONTROL_GROUP", "notyettreated"))
DID_ALLOW_UNBALANCED <- parse_bool(getenv1("DID_ALLOW_UNBALANCED", "TRUE"), TRUE)
DID_BSTRAP           <- parse_bool(getenv1("DID_BSTRAP", "TRUE"), TRUE)
DID_BITERS           <- parse_int(getenv1("DID_BITERS", "999"), 999L)

# Event window
MIN_E <- parse_int(getenv1("MIN_E", "-24"), -24L)
MAX_E <- parse_int(getenv1("MAX_E", "24"), 24L)
BALANCE_E_STR <- getenv1("BALANCE_E", "")
BALANCE_E <- if (nzchar(BALANCE_E_STR)) parse_int(BALANCE_E_STR, NA_integer_) else NA_integer_

# TWFE event study toggle
RUN_TWFE_ES <- parse_bool(getenv1("RUN_TWFE_ES", "FALSE"), FALSE)

# Validation
if (!DID_EST_METHOD %in% c("reg","dr","ipw")) stop("DID_EST_METHOD must be reg/dr/ipw", call. = FALSE)
if (!DID_CONTROL_GROUP %in% c("notyettreated","nevertreated")) stop("DID_CONTROL_GROUP must be notyettreated/nevertreated", call. = FALSE)

# ----------------------------- logging ----------------------------------------

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run_pretrends.log")

# Clear log if exists
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)

log_line(RUN_LOG, "=== PRE-TRENDS EVENT-STUDY DIAGNOSTICS ===")
log_line(RUN_LOG, glue("WD: {getwd()}"))
log_line(RUN_LOG, glue("R: {R.version.string}"))
log_line(RUN_LOG, glue("DATA_FILE: {DATA_FILE}"))
log_line(RUN_LOG, glue("TREAT_FILE: {TREAT_FILE}"))
log_line(RUN_LOG, glue("OUT_DIR: {OUT_DIR}"))
log_line(RUN_LOG, glue("OUTCOME: {OUTCOME}  RATE_EPS={RATE_EPS}"))
log_line(RUN_LOG, glue("ALPHA: {ALPHA}  SEED: {SEED}"))
log_line(RUN_LOG, glue("FILTERS: EXCLUDE_STATES={ifelse(length(EXCLUDE_STATES_VEC)>0, paste(EXCLUDE_STATES_VEC, collapse=','), 'none')}  MAX_DATE={ifelse(is.finite(MAX_DATE), as.character(MAX_DATE), 'none')}"))
log_line(RUN_LOG, glue("DROP (analysis panel): {if (!is.na(DROP_START) && !is.na(DROP_END)) glue('[{DROP_START},{DROP_END})') else 'none'}"))
log_line(RUN_LOG, glue("EXCLUDE (documented but unused): {if (!is.na(EXCLUDE_START) && !is.na(EXCLUDE_END)) glue('[{EXCLUDE_START},{EXCLUDE_END})') else 'none'}"))
log_line(RUN_LOG, glue("MIN_STATES_PER_MONTH (diagnostic threshold): {MIN_STATES_PER_MONTH}"))
log_line(RUN_LOG, glue("CS-DiD: est_method={DID_EST_METHOD}, control_group={DID_CONTROL_GROUP}, allow_unbalanced={DID_ALLOW_UNBALANCED}, bstrap={DID_BSTRAP}, biters={DID_BITERS}"))
log_line(RUN_LOG, glue("Event window: MIN_E={MIN_E}, MAX_E={MAX_E}, BALANCE_E={ifelse(is.finite(BALANCE_E), BALANCE_E, 'none')}"))
log_line(RUN_LOG, glue("RUN_TWFE_ES: {RUN_TWFE_ES}"))
log_line(RUN_LOG, "===========================")

# ----------------------------- fail-fast checks -------------------------------

if (!file.exists(DATA_FILE)) {
  msg <- glue("FATAL: DATA_FILE not found: {DATA_FILE}")
  log_line(RUN_LOG, msg)
  stop(msg, call. = FALSE)
}
if (!file.exists(TREAT_FILE)) {
  msg <- glue("FATAL: TREAT_FILE not found: {TREAT_FILE}")
  log_line(RUN_LOG, msg)
  stop(msg, call. = FALSE)
}
if (!OUTCOME %in% c("log1p_filings_count", "log1p_rate")) {
  msg <- glue("FATAL: OUTCOME must be log1p_filings_count or log1p_rate, got: {OUTCOME}")
  log_line(RUN_LOG, msg)
  stop(msg, call. = FALSE)
}

log_line(RUN_LOG, "Fail-fast checks passed.")

# ----------------------------- load + build panel -----------------------------

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
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

log_line(RUN_LOG, "Loading data...")
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

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

if (length(EXCLUDE_STATES_VEC) > 0) panel <- panel %>% filter(!state_abb %in% EXCLUDE_STATES_VEC)
if (is.finite(MAX_DATE)) panel <- panel %>% filter(month_date <= MAX_DATE)

if (!is.na(DROP_START) && !is.na(DROP_END)) {
  panel <- panel %>% filter(!in_window(month_date, DROP_START, DROP_END))
}

# One adoption date per state
panel <- panel %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup()

panel <- panel %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = (g > 0L) & (t >= g),
    event_time = if_else(g > 0L, as.integer(t - g), NA_integer_)
  )

# Outcome
if (OUTCOME == "log1p_filings_count") {
  panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
} else if (OUTCOME == "log1p_rate") {
  panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + RATE_EPS))
}

set.seed(SEED)

log_line(RUN_LOG, glue("Panel constructed: {nrow(panel)} rows"))

# ----------------------------- panel summary ----------------------------------

panel_summary <- tibble(
  n_states = n_distinct(panel$id),
  n_months = n_distinct(panel$t),
  n_rows = nrow(panel),
  min_date = as.character(min(panel$month_date, na.rm = TRUE)),
  max_date = as.character(max(panel$month_date, na.rm = TRUE)),
  n_never_treated = n_distinct(panel$id[panel$g == 0]),
  n_switchers = n_distinct(panel$id[panel$g > 0])
)

safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))
log_line(RUN_LOG, glue("Panel summary: {panel_summary$n_states} states, {panel_summary$n_months} months, {panel_summary$n_rows} rows"))
log_line(RUN_LOG, glue("  Never-treated: {panel_summary$n_never_treated}, Switchers: {panel_summary$n_switchers}"))

# ----------------------------- support diagnostics ----------------------------

untreated_support_by_month <- panel %>%
  group_by(month_date, t) %>%
  summarise(
    n_states_obs = n_distinct(id),
    n_untreated_states = n_distinct(id[untreated_obs]),
    .groups = "drop"
  ) %>%
  arrange(month_date)

safe_write_csv(untreated_support_by_month, file.path(OUT_DIR, "untreated_support_by_month.csv"))

support_by_event_time <- panel %>%
  filter(g > 0L, !is.na(event_time)) %>%
  group_by(event_time) %>%
  summarise(
    n_treated_state_months = n(),
    n_treated_states = n_distinct(id),
    avg_untreated_states_same_month = mean(
      untreated_support_by_month$n_untreated_states[match(t, untreated_support_by_month$t)],
      na.rm = TRUE
    ),
    min_untreated_states_same_month = min(
      untreated_support_by_month$n_untreated_states[match(t, untreated_support_by_month$t)],
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  arrange(event_time)

safe_write_csv(support_by_event_time, file.path(OUT_DIR, "support_by_event_time.csv"))

log_line(RUN_LOG, "Support diagnostics written.")

# ----------------------------- CS-DiD event study -----------------------------

log_line(RUN_LOG, "Running CS-DiD (did::att_gt + aggte)...")

# Diagnostic: Check cohort sizes
cohort_sizes <- panel %>%
  filter(g > 0) %>%
  group_by(g) %>%
  summarise(
    n_units = n_distinct(id),
    first_period = min(t),
    n_pre_periods = min(g) - first_period,
    .groups = "drop"
  )
safe_write_csv(cohort_sizes, file.path(OUT_DIR, "cohort_sizes.csv"))
log_line(RUN_LOG, glue("Cohort diagnostics: {nrow(cohort_sizes)} treatment cohorts"))

# Check control group availability
control_availability <- panel %>%
  group_by(t) %>%
  summarise(
    n_never_treated = n_distinct(id[g == 0]),
    n_not_yet_treated = n_distinct(id[g == 0 | t < g]),
    n_total = n_distinct(id),
    .groups = "drop"
  )
safe_write_csv(control_availability, file.path(OUT_DIR, "control_availability.csv"))

min_never_treated <- min(control_availability$n_never_treated)
min_not_yet_treated <- min(control_availability$n_not_yet_treated)
log_line(RUN_LOG, glue("Control availability: min never-treated={min_never_treated}, min not-yet-treated={min_not_yet_treated}"))

if (DID_CONTROL_GROUP == "nevertreated" && min_never_treated < 2) {
  log_line(RUN_LOG, "ERROR: control_group='nevertreated' but < 2 never-treated units available")
  cat("ERROR: Insufficient never-treated control units\n")
}
if (DID_CONTROL_GROUP == "notyettreated" && min_not_yet_treated < 2) {
  log_line(RUN_LOG, "WARNING: control_group='notyettreated' but < 2 not-yet-treated units in some periods")
  cat("WARNING: Limited not-yet-treated control units\n")
}

# Warn about small cohorts
small_cohorts <- cohort_sizes %>% filter(n_units < 3)
if (nrow(small_cohorts) > 0) {
  log_line(RUN_LOG, glue("WARNING: {nrow(small_cohorts)} cohorts have < 3 units (may cause singularity issues)"))
}

# Warn about cohorts with few pre-periods
few_pre <- cohort_sizes %>% filter(n_pre_periods < 2)
if (nrow(few_pre) > 0) {
  log_line(RUN_LOG, glue("WARNING: {nrow(few_pre)} cohorts have < 2 pre-periods (may cause estimation issues)"))
}

cs_success <- FALSE
tryCatch({
  # Try with default settings first
  log_line(RUN_LOG, "  Attempting CS-DiD with default settings...")
  cs_out <- tryCatch({
    suppressWarnings(
      did::att_gt(
        yname = "y",
        tname = "t",
        idname = "id",
        gname = "g",
        xformla = ~ 1,
        data = panel,
        panel = TRUE,
        control_group = DID_CONTROL_GROUP,
        est_method = DID_EST_METHOD,
        allow_unbalanced_panel = DID_ALLOW_UNBALANCED,
        bstrap = DID_BSTRAP,
        biters = DID_BITERS,
        clustervars = "id"
      )
    )
  }, error = function(e) {
    # If default fails, try with faster_mode=FALSE (suggested workaround)
    if (grepl("faster_mode", e$message, fixed = TRUE) || grepl("singular matrix", e$message, fixed = TRUE)) {
      log_line(RUN_LOG, glue("  Default failed ({substr(e$message, 1, 50)}...), retrying with faster_mode=FALSE..."))
      cat("Note: Retrying CS-DiD with faster_mode=FALSE (this may take longer)...\n")

      result <- tryCatch({
        suppressWarnings(
          did::att_gt(
            yname = "y",
            tname = "t",
            idname = "id",
            gname = "g",
            xformla = ~ 1,
            data = panel,
            panel = TRUE,
            control_group = DID_CONTROL_GROUP,
            est_method = DID_EST_METHOD,
            allow_unbalanced_panel = DID_ALLOW_UNBALANCED,
            bstrap = DID_BSTRAP,
            biters = DID_BITERS,
            clustervars = "id",
            faster_mode = FALSE  # Workaround for singular matrix issues
          )
        )
      }, error = function(e2) {
        # If faster_mode=FALSE still fails and we're using notyettreated, try nevertreated
        if (DID_CONTROL_GROUP == "notyettreated") {
          log_line(RUN_LOG, "  faster_mode=FALSE failed, trying control_group='nevertreated'...")
          cat("Note: Retrying CS-DiD with control_group='nevertreated'...\n")
          suppressWarnings(
            did::att_gt(
              yname = "y",
              tname = "t",
              idname = "id",
              gname = "g",
              xformla = ~ 1,
              data = panel,
              panel = TRUE,
              control_group = "nevertreated",  # Alternative control group
              est_method = DID_EST_METHOD,
              allow_unbalanced_panel = DID_ALLOW_UNBALANCED,
              bstrap = DID_BSTRAP,
              biters = DID_BITERS,
              clustervars = "id",
              faster_mode = FALSE
            )
          )
        } else {
          stop(e2)  # Re-throw if already using nevertreated
        }
      })

      result
    } else {
      stop(e)  # Re-throw if not a known error
    }
  })

  cs_es <- if (is.finite(BALANCE_E)) {
    did::aggte(cs_out, type = "dynamic", min_e = MIN_E, max_e = MAX_E, balance_e = BALANCE_E, na.rm = TRUE)
  } else {
    did::aggte(cs_out, type = "dynamic", min_e = MIN_E, max_e = MAX_E, na.rm = TRUE)
  }

  zcrit <- stats::qnorm(1 - ALPHA / 2)

  cs_tbl <- tibble(
    e = cs_es$egt,
    att = cs_es$att.egt,
    se = cs_es$se.egt
  ) %>%
    mutate(
      z = att / se,
      p = 2 * stats::pnorm(-abs(z)),
      lo = att - zcrit * se,
      hi = att + zcrit * se
    ) %>%
    arrange(e)

  # Diagnostic: Check for problematic SEs
  n_na_se <- sum(is.na(cs_tbl$se))
  n_zero_se <- sum(cs_tbl$se == 0, na.rm = TRUE)
  n_huge_se <- sum(cs_tbl$se > 10 * abs(cs_tbl$att), na.rm = TRUE)

  if (n_na_se > 0) {
    log_line(RUN_LOG, glue("WARNING: {n_na_se} event times have NA standard errors"))
    cat(glue("WARNING: {n_na_se}/{nrow(cs_tbl)} event times have NA standard errors\n"))
  }
  if (n_zero_se > 0) {
    log_line(RUN_LOG, glue("WARNING: {n_zero_se} event times have zero standard errors"))
    cat(glue("WARNING: {n_zero_se}/{nrow(cs_tbl)} event times have zero standard errors\n"))
  }
  if (n_huge_se > 0) {
    log_line(RUN_LOG, glue("WARNING: {n_huge_se} event times have SE > 10x|ATT| (very imprecise)"))
  }

  # Check if bootstrap was actually used
  if (!DID_BSTRAP) {
    log_line(RUN_LOG, "NOTE: Bootstrap disabled (DID_BSTRAP=FALSE), SEs may be unreliable or NA")
    cat("NOTE: Bootstrap disabled - standard errors may be unreliable\n")
  } else if (DID_BITERS < 100) {
    log_line(RUN_LOG, glue("WARNING: Only {DID_BITERS} bootstrap iterations - SEs may be imprecise"))
    cat(glue("WARNING: Only {DID_BITERS} bootstrap iterations (recommend ≥199)\n"))
  }

  safe_write_csv(cs_tbl, file.path(OUT_DIR, "cs_event_study.csv"))

  # Joint Wald test for pre-trends
  grab_vcov <- function(obj) {
    cand <- c("V", "V_egt", "V.dynamic", "V_agg", "vcov")
    for (nm in cand) {
      if (!is.null(obj[[nm]]) && is.matrix(obj[[nm]])) return(obj[[nm]])
    }
    NULL
  }

  V <- grab_vcov(cs_es)

  joint <- tibble(
    ok = FALSE,
    method = NA_character_,
    n_leads = NA_integer_,
    wald = NA_real_,
    df = NA_integer_,
    p_value = NA_real_
  )

  lead_idx <- which(cs_tbl$e < 0)

  if (length(lead_idx) >= 1 && !is.null(V) &&
      nrow(V) == nrow(cs_tbl) && ncol(V) == nrow(cs_tbl)) {
    a <- cs_tbl$att[lead_idx]
    Vsub <- V[lead_idx, lead_idx, drop = FALSE]

    # Check for issues with the variance-covariance matrix
    n_na_leads <- sum(is.na(a))
    if (n_na_leads > 0) {
      log_line(RUN_LOG, glue("WARNING: {n_na_leads}/{length(a)} pre-treatment ATTs are NA - joint test may be unreliable"))
      cat(glue("WARNING: {n_na_leads} pre-treatment ATTs are NA\n"))
    }

    # Check if vcov is usable
    vcov_ok <- !any(is.na(Vsub)) && !any(is.infinite(Vsub))
    if (!vcov_ok) {
      log_line(RUN_LOG, "WARNING: VCOV matrix has NA/Inf values - joint test unreliable")
      cat("WARNING: Variance-covariance matrix has problems - joint test unreliable\n")
    }

    ok_solve <- TRUE
    stat <- NA_real_
    tryCatch({
      stat <- as.numeric(t(a) %*% solve(Vsub, a))
    }, error = function(e) {
      ok_solve <<- FALSE
      log_line(RUN_LOG, glue("WARNING: Joint test failed - {e$message}"))
    })

    if (ok_solve && is.finite(stat)) {
      df_w <- length(a)
      joint <- tibble(
        ok = TRUE,
        method = "chi-square Wald using aggte vcov",
        n_leads = df_w,
        wald = stat,
        df = df_w,
        p_value = 1 - stats::pchisq(stat, df = df_w)
      )

      # Warn if p-value seems suspicious
      if (joint$p_value < 0.001 || joint$p_value > 0.999) {
        log_line(RUN_LOG, glue("NOTE: Joint test p-value is extreme ({round(joint$p_value, 4)}) - verify interpretation"))
      }
    } else {
      log_line(RUN_LOG, "WARNING: Joint test computation failed - likely VCOV singularity")
      cat("WARNING: Could not compute joint pre-trends test\n")
    }
  } else {
    # No valid pre-treatment periods or no VCOV
    if (length(lead_idx) == 0) {
      log_line(RUN_LOG, "WARNING: No pre-treatment periods in event window for joint test")
    } else if (is.null(V)) {
      log_line(RUN_LOG, "WARNING: No VCOV matrix available (bootstrap may have failed)")
      cat("WARNING: No variance-covariance matrix - joint test unavailable\n")
    }
  }

  safe_write_csv(joint, file.path(OUT_DIR, "cs_pretrends_joint_test.csv"))

  # Plot
  p1 <- ggplot(cs_tbl, aes(x = e, y = att)) +
    geom_hline(yintercept = 0, linetype = 2) +
    geom_vline(xintercept = -0.5, linetype = 3) +
    geom_point() +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2) +
    labs(
      title = "CS-DiD Event Study",
      subtitle = glue("est_method={DID_EST_METHOD}, control_group={DID_CONTROL_GROUP}, bstrap={DID_BSTRAP}, biters={DID_BITERS}"),
      x = "Event time (t - g)",
      y = "ATT"
    ) +
    theme_minimal()

  ggsave(file.path(OUT_DIR, "cs_event_study.png"), p1, width = 9, height = 6, dpi = 160)

  cs_success <- TRUE
  log_line(RUN_LOG, glue("CS-DiD completed successfully. Event-time range: [{min(cs_tbl$e)}, {max(cs_tbl$e)}]"))

  # Log pre-trends test result
  if (joint$ok) {
    log_line(RUN_LOG, glue("Pre-trends test: Wald={round(joint$wald, 2)}, df={joint$df}, p={round(joint$p_value, 4)}"))
    if (joint$p_value > ALPHA) {
      log_line(RUN_LOG, "  → No evidence against parallel trends (fail to reject)")
    } else {
      log_line(RUN_LOG, "  → WARNING: Evidence of pre-trends (reject null)")
    }
  }

}, error = function(e) {
  log_line(RUN_LOG, glue("CS-DiD FAILED: {e$message}"))
  cat(glue("WARNING: CS-DiD failed: {e$message}\n"))

  # Write empty placeholders so pipeline doesn't break
  safe_write_csv(tibble(e=numeric(), att=numeric(), se=numeric(), z=numeric(), p=numeric(), lo=numeric(), hi=numeric()),
                 file.path(OUT_DIR, "cs_event_study.csv"))
  safe_write_csv(tibble(ok=FALSE, method="FAILED", n_leads=NA_integer_, wald=NA_real_, df=NA_integer_, p_value=NA_real_),
                 file.path(OUT_DIR, "cs_pretrends_joint_test.csv"))
})

# ----------------------------- TWFE event study -------------------------------

if (RUN_TWFE_ES) {
  log_line(RUN_LOG, "Running TWFE event study (fixest::feols)...")

  twfe_success <- FALSE
  tryCatch({
    # Create event-time indicators, setting reference period to -1
    # Filter to event window
    twfe_data <- panel %>%
      filter(!is.na(event_time), event_time >= MIN_E, event_time <= MAX_E) %>%
      mutate(
        event_time_fac = as.factor(event_time),
        state_abb_fac = as.factor(state_abb)
      )

    # Run TWFE with event-time fixed effects, using -1 as reference
    twfe_fit <- fixest::feols(
      y ~ i(event_time, ref = -1) | id + t,
      data = twfe_data,
      cluster = ~ id
    )

    # Extract coefficients
    twfe_coef <- summary(twfe_fit)$coefficients

    # Parse coefficient names to get event times
    coef_names <- rownames(twfe_coef)
    event_times <- as.integer(gsub("event_time::", "", coef_names))

    # Create output table
    zcrit <- stats::qnorm(1 - ALPHA / 2)

    twfe_tbl <- tibble(
      e = event_times,
      coef = twfe_coef[, "Estimate"],
      se = twfe_coef[, "Std. Error"],
      z = coef / se,
      p = 2 * stats::pnorm(-abs(z)),
      lo = coef - zcrit * se,
      hi = coef + zcrit * se
    ) %>%
      arrange(e)

    safe_write_csv(twfe_tbl, file.path(OUT_DIR, "twfe_event_study.csv"))

    # Plot
    p2 <- ggplot(twfe_tbl, aes(x = e, y = coef)) +
      geom_hline(yintercept = 0, linetype = 2) +
      geom_vline(xintercept = -0.5, linetype = 3) +
      geom_point() +
      geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2) +
      labs(
        title = "TWFE Event Study",
        subtitle = glue("Reference period: -1, Cluster: state"),
        x = "Event time (t - g)",
        y = "Coefficient"
      ) +
      theme_minimal()

    ggsave(file.path(OUT_DIR, "twfe_event_study.png"), p2, width = 9, height = 6, dpi = 160)

    # Joint F-test on pre-treatment coefficients
    pre_idx <- which(twfe_tbl$e < 0)
    if (length(pre_idx) >= 1) {
      # Use Wald test from fixest
      pre_pattern <- paste0("event_time::", twfe_tbl$e[pre_idx], collapse = "|")
      twfe_joint <- fixest::wald(twfe_fit, keep = pre_pattern, print = FALSE)

      twfe_joint_tbl <- tibble(
        ok = TRUE,
        method = "F-test on pre-treatment coefficients",
        n_leads = length(pre_idx),
        f_stat = twfe_joint["stat"],
        df1 = twfe_joint["df1"],
        df2 = twfe_joint["df2"],
        p_value = twfe_joint["p"]
      )

      safe_write_csv(twfe_joint_tbl, file.path(OUT_DIR, "twfe_pretrends_joint_test.csv"))
    }

    twfe_success <- TRUE
    log_line(RUN_LOG, glue("TWFE event study completed successfully. Event-time range: [{min(twfe_tbl$e)}, {max(twfe_tbl$e)}]"))

    # Log pre-trends test result if available
    if (exists("twfe_joint_tbl") && nrow(twfe_joint_tbl) > 0) {
      log_line(RUN_LOG, glue("Pre-trends F-test: F={round(twfe_joint_tbl$f_stat, 2)}, df1={twfe_joint_tbl$df1}, df2={twfe_joint_tbl$df2}, p={round(twfe_joint_tbl$p_value, 4)}"))
      if (twfe_joint_tbl$p_value > ALPHA) {
        log_line(RUN_LOG, "  → No evidence against parallel trends (fail to reject)")
      } else {
        log_line(RUN_LOG, "  → WARNING: Evidence of pre-trends (reject null)")
      }
    }

  }, error = function(e) {
    log_line(RUN_LOG, glue("TWFE event study FAILED: {e$message}"))
    cat(glue("WARNING: TWFE event study failed: {e$message}\n"))

    # Write empty placeholders
    safe_write_csv(tibble(e=numeric(), coef=numeric(), se=numeric(), z=numeric(), p=numeric(), lo=numeric(), hi=numeric()),
                   file.path(OUT_DIR, "twfe_event_study.csv"))
  })
} else {
  log_line(RUN_LOG, "TWFE event study skipped (RUN_TWFE_ES=FALSE).")
}

# ----------------------------- completion -------------------------------------

# Create diagnostic summary
diagnostic_summary <- tibble(
  item = c(
    "Panel constructed",
    "States (total)",
    "States (never-treated)",
    "States (switchers)",
    "Time periods",
    "Observations",
    "CS-DiD completed",
    "TWFE completed"
  ),
  value = c(
    "Yes",
    as.character(panel_summary$n_states),
    as.character(panel_summary$n_never_treated),
    as.character(panel_summary$n_switchers),
    as.character(panel_summary$n_months),
    as.character(panel_summary$n_rows),
    ifelse(cs_success, "Yes", "FAILED"),
    ifelse(exists("twfe_success") && twfe_success, "Yes", ifelse(RUN_TWFE_ES, "FAILED", "Skipped"))
  )
)

safe_write_csv(diagnostic_summary, file.path(OUT_DIR, "diagnostic_summary.csv"))

log_line(RUN_LOG, "===========================")
log_line(RUN_LOG, "DIAGNOSTICS COMPLETE")
log_line(RUN_LOG, glue("CS-DiD: {ifelse(cs_success, 'SUCCESS', 'FAILED')}"))
if (RUN_TWFE_ES) {
  log_line(RUN_LOG, glue("TWFE: {ifelse(exists('twfe_success') && twfe_success, 'SUCCESS', 'FAILED')}"))
}
log_line(RUN_LOG, glue("Outputs written to: {OUT_DIR}"))
cat("Done. Outputs written to:", OUT_DIR, "\n")
if (cs_success) {
  cat("✓ CS-DiD event study completed\n")
} else {
  cat("✗ CS-DiD event study FAILED\n")
}
if (RUN_TWFE_ES) {
  if (exists("twfe_success") && twfe_success) {
    cat("✓ TWFE event study completed\n")
  } else {
    cat("✗ TWFE event study FAILED\n")
  }
}
