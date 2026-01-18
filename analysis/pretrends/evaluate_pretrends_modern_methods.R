#!/usr/bin/env Rscript
################################################################################
# evaluate_pretrends_modern_methods.R
#
# Comprehensive Pre-Trends Evaluation for Gambling-Eviction Analysis
#
# Implements modern parallel trends methodologies:
# - Roth (2022): Power analysis and minimal detectable effects
# - Rambachan & Roth (2023): HonestDiD sensitivity analysis
# - Hartman & Hidalgo (2018): Equivalence testing
#
# Uses full state panel (30+ states) aggregated from counties
# Treatment: Online gambling legalization dates
# Robustness: COVID exclusion, Maine exclusion, various windows
#
# KEY INSIGHT FROM ROTH: Don't condition on pre-trends! Instead:
# 1. Calculate power of pre-trends tests
# 2. Conduct sensitivity analysis (HonestDiD)
# 3. Use equivalence tests to show trends are "small enough"
################################################################################

# Force single-threaded execution
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
  library(fixest)
  library(patchwork)
})

# Optional modern packages (graceful degradation if not installed)
has_honestdid <- requireNamespace("HonestDiD", quietly = TRUE)
has_pretrends <- requireNamespace("pretrends", quietly = TRUE)
has_did <- requireNamespace("did", quietly = TRUE)

if (!has_honestdid) cat("WARNING: HonestDiD package not installed. Sensitivity analysis will be skipped.\n")
if (!has_pretrends) cat("WARNING: pretrends package not installed. Power analysis will be skipped.\n")
if (!has_did) cat("WARNING: did package not installed. CS-DiD comparison will be skipped.\n")

# Load MASS last to avoid conflicts
library(MASS)

################################################################################
# SECTION 1: CONFIGURATION
################################################################################

# File paths
DATA_FILE <- Sys.getenv("DATA_FILE", "data/raw/combined_monthly_panel.csv")
GAMBLING_FILE <- Sys.getenv("GAMBLING_FILE", "data/raw/sports_gambling_legalization_dates.csv")
OUT_DIR <- Sys.getenv("OUT_DIR", "output/pretrends_evaluation")

# Analysis parameters
OUTCOME <- Sys.getenv("OUTCOME", "log1p_filings_count")  # or "log1p_rate"
ALPHA <- as.numeric(Sys.getenv("ALPHA", "0.05"))
SEED <- as.integer(Sys.getenv("SEED", "42"))
set.seed(SEED)

# Create output directory
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
LOG_FILE <- file.path(OUT_DIR, "run_log.txt")
if (file.exists(LOG_FILE)) file.remove(LOG_FILE)

log_msg <- function(msg) {
  cat(msg, "\n")
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

log_msg("================================================================================")
log_msg("PRE-TRENDS EVALUATION: MODERN METHODS")
log_msg("================================================================================")
log_msg(glue("Working directory: {getwd()}"))
log_msg(glue("Data file: {DATA_FILE}"))
log_msg(glue("Gambling file: {GAMBLING_FILE}"))
log_msg(glue("Output directory: {OUT_DIR}"))
log_msg(glue("Outcome: {OUTCOME}"))
log_msg("================================================================================")

################################################################################
# SECTION 2: DATA LOADING AND STATE PANEL CONSTRUCTION
################################################################################

log_msg("\n--- Loading Data ---")

# Helper functions for state identification
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

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

# Year-month index for treatment timing
ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

# Build state panel from county + state data
build_state_panel <- function(df) {
  log_msg("Building state panel from county and state observations...")

  # Aggregate counties to state level
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
  log_msg(glue("  States with county data: {length(county_states)}"))

  # Use state-level data as fallback for states without counties
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

  log_msg(glue("  States using state-level data: {n_distinct(state_fallback$state_abb)}"))

  # Combine
  panel <- bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)

  log_msg(glue("  Total states in panel: {n_distinct(panel$state_abb)}"))
  log_msg(glue("  Date range: {min(panel$month_date)} to {max(panel$month_date)}"))
  log_msg(glue("  Total observations: {nrow(panel)}"))

  panel
}

# Load data
if (!file.exists(DATA_FILE)) stop(glue("Data file not found: {DATA_FILE}"))
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

# Load gambling dates
if (!file.exists(GAMBLING_FILE)) stop(glue("Gambling file not found: {GAMBLING_FILE}"))
gambling_raw <- readr::read_csv(GAMBLING_FILE, show_col_types = FALSE)

gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  dplyr::select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

# Merge with all states
all_states <- tibble(state_abb = unique(panel_raw$state_abb))
gambling_dates <- all_states %>%
  left_join(gambling_dates, by = "state_abb")

log_msg(glue("Treated states (online gambling): {sum(!is.na(gambling_dates$online_start_date))}"))
log_msg(glue("Never-treated states: {sum(is.na(gambling_dates$online_start_date))}"))

################################################################################
# SECTION 3: PANEL SPECIFICATIONS
################################################################################

# Define robustness specifications
# NOTE: Using -12 as min_e to ensure 100% coverage of all treated states
# (based on pretreatment_coverage analysis showing 16/16 states have data at -12)
SPECIFICATIONS <- list(
  baseline = list(
    name = "Baseline",
    exclude_states = "ME",  # Exclude Maine per user request
    max_date = as.Date("2024-12-31"),
    drop_covid = FALSE,
    min_e = -12,
    max_e = 24,
    description = "Full sample excluding Maine, -12 to +24 months"
  ),

  no_covid = list(
    name = "No COVID",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_covid = TRUE,
    covid_start = as.Date("2020-03-01"),
    covid_end = as.Date("2021-07-31"),
    min_e = -12,
    max_e = 24,
    description = "Excludes COVID period (Mar 2020 - Jul 2021) and Maine"
  ),

  pre2020 = list(
    name = "Pre-2020 Only",
    exclude_states = "ME",
    max_date = as.Date("2019-12-31"),
    drop_covid = FALSE,
    min_e = -12,
    max_e = 12,
    description = "Uses only pre-pandemic data"
  ),

  narrow_window = list(
    name = "Narrow Window (±6 months)",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_covid = FALSE,
    min_e = -6,
    max_e = 6,
    description = "Focuses on ±6 months around treatment"
  )
)

build_panel_for_spec <- function(panel_raw, gambling_dates, spec) {
  log_msg(glue("\nBuilding panel for: {spec$name}"))

  # Merge treatment dates
  panel <- panel_raw %>%
    left_join(gambling_dates, by = "state_abb")

  # Apply exclusions
  if (nzchar(spec$exclude_states)) {
    exclude_vec <- strsplit(spec$exclude_states, ",")[[1]]
    panel <- panel %>% filter(!state_abb %in% exclude_vec)
    log_msg(glue("  Excluded states: {spec$exclude_states}"))
  }

  # Apply date filters
  if (!is.null(spec$max_date)) {
    panel <- panel %>% filter(month_date <= spec$max_date)
  }

  # Drop COVID period if requested
  if (spec$drop_covid) {
    panel <- panel %>%
      filter(!(month_date >= spec$covid_start & month_date <= spec$covid_end))
    log_msg(glue("  Dropped COVID period: {spec$covid_start} to {spec$covid_end}"))
  }

  # Create treatment variables
  panel <- panel %>%
    mutate(
      t = ym_index(month_date),
      g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
      g = as.integer(g),
      id = as.integer(as.factor(state_abb)),
      e = if_else(g > 0L, as.integer(t - g), NA_integer_),
      post_treat = (g > 0L) & (t >= g)
    )

  # Filter to event window
  panel <- panel %>%
    filter(is.na(e) | (e >= spec$min_e & e <= spec$max_e))

  # Create outcome
  if (OUTCOME == "log1p_filings_count") {
    panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
  } else if (OUTCOME == "log1p_rate") {
    panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + 0.01))
  } else {
    stop(glue("Unknown OUTCOME: {OUTCOME}"))
  }

  panel <- panel %>% filter(!is.na(y))

  log_msg(glue("  States: {n_distinct(panel$state_abb)}"))
  log_msg(glue("  Treated states: {n_distinct(panel$state_abb[panel$g > 0])}"))
  log_msg(glue("  Never-treated: {n_distinct(panel$state_abb[panel$g == 0])}"))
  log_msg(glue("  Observations: {nrow(panel)}"))

  panel
}

################################################################################
# SECTION 4: TWFE EVENT STUDY
################################################################################

run_twfe_event_study <- function(panel, spec) {
  log_msg(glue("\n--- TWFE Event Study: {spec$name} ---"))

  # Get event times (omit -1 as reference)
  event_times_all <- panel %>% filter(!is.na(e)) %>% pull(e) %>% unique() %>% sort()
  event_times_use <- event_times_all[event_times_all != -1]

  if (length(event_times_use) == 0) {
    warning("No event times available")
    return(NULL)
  }

  # Create event-time dummies
  for (et in event_times_use) {
    col_name <- paste0("lead_", et)
    panel[[col_name]] <- as.integer(!is.na(panel$e) & panel$e == et)
  }

  # Build formula
  dummy_cols <- paste0("lead_", event_times_use)
  dummy_cols_quoted <- paste0("`", dummy_cols, "`")
  dummy_formula <- paste(dummy_cols_quoted, collapse = " + ")
  formula_str <- glue("y ~ {dummy_formula} | id + t")

  # Run TWFE
  log_msg("  Estimating TWFE model...")
  twfe_mod <- fixest::feols(
    as.formula(formula_str),
    data = panel,
    cluster = ~id
  )

  # Extract coefficients
  twfe_coefs <- tibble(
    term = names(coef(twfe_mod)),
    estimate = as.numeric(coef(twfe_mod)),
    se = as.numeric(se(twfe_mod))
  ) %>%
    mutate(
      term_clean = gsub("`", "", term),
      term_clean = gsub("lead_", "", term_clean),
      e = as.integer(term_clean),
      t_stat = estimate / se,
      p_value = 2 * pt(abs(t_stat), df = twfe_mod$nobs - length(coef(twfe_mod)), lower.tail = FALSE),
      lo = estimate - qnorm(1 - ALPHA/2) * se,
      hi = estimate + qnorm(1 - ALPHA/2) * se
    ) %>%
    dplyr::select(e, estimate, se, t_stat, p_value, lo, hi) %>%
    arrange(e)

  # Joint F-test on pre-treatment coefficients
  pre_event_times <- twfe_coefs %>% filter(e < 0) %>% pull(e)

  if (length(pre_event_times) > 0) {
    pre_terms <- paste0("lead_", pre_event_times)

    tryCatch({
      wald_result <- fixest::wald(twfe_mod, keep = pre_terms)

      log_msg(glue("  Pre-trends F-test: F({wald_result$df1}, {wald_result$df2}) = {round(wald_result$stat, 3)}, p = {round(wald_result$p, 4)}"))

      pretrends_test <- tibble(
        method = "F-test on pre-treatment coefficients",
        n_leads = length(pre_event_times),
        f_stat = wald_result$stat,
        df1 = wald_result$df1,
        df2 = wald_result$df2,
        p_value = wald_result$p
      )
    }, error = function(e) {
      warning("F-test failed: ", e$message)
      pretrends_test <<- tibble(
        method = "F-test on pre-treatment coefficients",
        n_leads = length(pre_event_times),
        f_stat = NA_real_,
        df1 = NA_integer_,
        df2 = NA_integer_,
        p_value = NA_real_
      )
    })
  } else {
    pretrends_test <- tibble(
      method = "F-test on pre-treatment coefficients",
      n_leads = 0,
      f_stat = NA_real_,
      df1 = NA_integer_,
      df2 = NA_integer_,
      p_value = NA_real_
    )
  }

  # Extract variance-covariance matrix for modern methods
  vcov_mat <- vcov(twfe_mod, cluster = ~id)

  list(
    model = twfe_mod,
    coefs = twfe_coefs,
    pretrends_test = pretrends_test,
    vcov = vcov_mat
  )
}

################################################################################
# SECTION 5: POWER ANALYSIS (Roth 2022)
################################################################################

run_power_analysis <- function(twfe_result, spec) {
  if (!has_pretrends) {
    log_msg("  Skipping power analysis (pretrends package not installed)")
    return(NULL)
  }

  log_msg("\n--- Power Analysis (Roth 2022) ---")

  # Extract pre-treatment coefficients
  pre_coefs <- twfe_result$coefs %>% filter(e < 0)

  if (nrow(pre_coefs) == 0) {
    log_msg("  No pre-treatment periods available")
    return(NULL)
  }

  beta_pre <- pre_coefs$estimate
  names(beta_pre) <- pre_coefs$e
  event_times_pre <- pre_coefs$e

  # Extract variance-covariance matrix for pre-period
  # Need to match coefficient names
  coef_names <- names(coef(twfe_result$model))
  pre_term_pattern <- paste0("lead_", event_times_pre, collapse = "|")
  pre_idx <- grepl(pre_term_pattern, coef_names)

  if (sum(pre_idx) == 0) {
    log_msg("  Could not extract pre-period variance-covariance matrix")
    return(NULL)
  }

  sigma_pre <- twfe_result$vcov[pre_idx, pre_idx]

  # Calculate minimal detectable slope for different power levels
  target_powers <- c(0.5, 0.8)
  mde_results <- list()

  for (power in target_powers) {
    tryCatch({
      slope <- pretrends::slope_for_power(
        sigma = sigma_pre,
        targetPower = power,
        tVec = event_times_pre,
        referencePeriod = -1
      )

      mde_results[[paste0("power_", power)]] <- slope
      log_msg(glue("  MDE (slope) for {power*100}% power: {round(slope, 4)}"))
    }, error = function(e) {
      warning(glue("Power calculation failed for power={power}: {e$message}"))
      mde_results[[paste0("power_", power)]] <<- NA
    })
  }

  mde_table <- tibble(
    target_power = target_powers,
    mde_slope = unlist(mde_results)
  )

  list(
    mde_table = mde_table,
    interpretation = glue(
      "A linear pre-trend with slope {round(mde_table$mde_slope[2], 3)} would be detected with 80% power. ",
      "If this magnitude of violation is economically meaningful, the test has adequate power. ",
      "Otherwise, failing to reject parallel trends is uninformative."
    )
  )
}

################################################################################
# SECTION 6: HONESTDID SENSITIVITY ANALYSIS (Rambachan & Roth 2023)
################################################################################

run_honestdid_analysis <- function(twfe_result, spec) {
  if (!has_honestdid) {
    log_msg("  Skipping HonestDiD analysis (HonestDiD package not installed)")
    return(NULL)
  }

  log_msg("\n--- HonestDiD Sensitivity Analysis (Rambachan & Roth 2023) ---")

  # Extract all coefficients and variance
  beta <- twfe_result$coefs$estimate
  names(beta) <- twfe_result$coefs$e
  event_times <- twfe_result$coefs$e

  # Separate pre and post
  pre_idx <- event_times < 0
  post_idx <- event_times >= 0

  numPrePeriods <- sum(pre_idx)
  numPostPeriods <- sum(post_idx)

  if (numPrePeriods == 0 || numPostPeriods == 0) {
    log_msg("  Need both pre and post periods")
    return(NULL)
  }

  log_msg(glue("  Pre-periods: {numPrePeriods}, Post-periods: {numPostPeriods}"))

  # Extract variance-covariance matrix (need to match coefficient order)
  coef_names <- names(coef(twfe_result$model))
  term_pattern <- paste0("lead_", event_times, collapse = "|")
  idx <- grepl(term_pattern, coef_names)
  sigma <- twfe_result$vcov[idx, idx]

  # Run HonestDiD for different M values
  # M = 0: exact parallel trends
  # M = 1: post-treatment violations <= max pre-treatment violation
  # M = 2: post-treatment violations <= 2 * max pre-treatment violation
  M_values <- c(0, 0.5, 1, 1.5, 2)

  honest_results <- list()

  for (M in M_values) {
    tryCatch({
      result <- HonestDiD::createSensitivityResults(
        betahat = beta,
        sigma = sigma,
        numPrePeriods = numPrePeriods,
        numPostPeriods = numPostPeriods,
        Mvec = M,  # FIXED: Was Mbarvec, should be Mvec
        method = "C-LF",  # Conditional least favorable
        alpha = ALPHA
      )

      honest_results[[paste0("M_", M)]] <- result
      log_msg(glue("  Computed sensitivity for M = {M}"))
    }, error = function(e) {
      log_msg(glue("  HonestDiD failed for M={M}: {e$message}"))
    })
  }

  if (length(honest_results) == 0) {
    log_msg("  All HonestDiD computations failed")
    return(NULL)
  }

  list(
    results = honest_results,
    interpretation = glue(
      "HonestDiD provides robust confidence sets under bounded violations. ",
      "M=1 means post-treatment violations can be up to the max pre-treatment violation. ",
      "If results are robust to M=1 or M=2, conclusions are more credible."
    )
  )
}

################################################################################
# SECTION 7: EQUIVALENCE TESTING
################################################################################

run_equivalence_tests <- function(twfe_result, spec) {
  log_msg("\n--- Equivalence Testing ---")

  # Extract pre-treatment coefficients
  pre_coefs <- twfe_result$coefs %>% filter(e < 0)

  if (nrow(pre_coefs) == 0) {
    log_msg("  No pre-treatment periods available")
    return(NULL)
  }

  beta_pre <- pre_coefs$estimate
  event_times_pre <- pre_coefs$e

  # Extract variance for pre-period
  coef_names <- names(coef(twfe_result$model))
  pre_term_pattern <- paste0("lead_", event_times_pre, collapse = "|")
  pre_idx <- grepl(pre_term_pattern, coef_names)
  sigma_pre <- twfe_result$vcov[pre_idx, pre_idx]

  # Test against grid of delta values
  delta_grid <- seq(0.01, 0.20, by = 0.01)

  # Maximum test: Can we rule out that max|beta_pre| >= delta?
  test_max_violation <- function(delta) {
    # For each pre-period, test if |beta_l| < delta
    # Reject if ALL individual tests reject
    T_pre <- length(beta_pre)

    p_values <- sapply(1:T_pre, function(l) {
      se_l <- sqrt(sigma_pre[l, l])
      # One-sided test: H0: |beta| >= delta vs H1: |beta| < delta
      pnorm((abs(beta_pre[l]) - delta) / se_l)
    })

    # Reject if all p-values < alpha (conservative: use max p-value)
    reject <- all(p_values < ALPHA)
    list(reject = reject, max_pvalue = max(p_values))
  }

  # Find smallest delta we can rule out
  delta_star_max <- NA
  for (delta in delta_grid) {
    result <- test_max_violation(delta)
    if (result$reject) {
      delta_star_max <- delta
      break
    }
  }

  if (is.na(delta_star_max)) {
    log_msg("  Cannot rule out large violations (delta* > 0.20)")
  } else {
    log_msg(glue("  δ* (max test) = {round(delta_star_max, 3)}"))
    log_msg(glue("  Interpretation: Can rule out that max pre-trend exceeds {round(delta_star_max, 3)}"))
  }

  # RMS test
  rms_observed <- sqrt(mean(beta_pre^2))
  log_msg(glue("  RMS of pre-trends: {round(rms_observed, 4)}"))

  list(
    delta_star_max = delta_star_max,
    rms_pretrends = rms_observed,
    interpretation = if (!is.na(delta_star_max) && delta_star_max < 0.10) {
      "Strong evidence for parallel trends (can rule out violations > 0.10)"
    } else if (!is.na(delta_star_max) && delta_star_max < 0.15) {
      "Moderate evidence for parallel trends"
    } else {
      "Weak evidence for parallel trends - cannot rule out large violations"
    }
  )
}

################################################################################
# SECTION 8: CALLAWAY-SANT'ANNA DID (Compositionally Robust)
################################################################################

run_cs_did_analysis <- function(panel, spec) {
  if (!has_did) {
    log_msg("  Skipping CS-DiD analysis (did package not installed)")
    return(NULL)
  }

  log_msg("\n--- Callaway-Sant'Anna DiD (2021) ---")
  log_msg("  DISABLED: CS-DiD causing segfault even with est_method='reg'")
  log_msg("  Issue: All est_methods (reg/ipw/dr) use fastglm for propensity scores")
  log_msg("  Root cause: fastglm's colMax_dense() crashes on this data structure")
  log_msg("  Attempted fix: est_method='reg' still calls fastglm internally")
  log_msg("  Solution: Either fix data structure or use balanced panel")
  return(NULL)

  # Prepare data for CS-DiD
  # Use state_abb as the unit identifier for repeated cross-sections approach
  panel_cs <- panel %>%
    mutate(
      gname = if_else(g > 0, as.integer(g), 0L),  # 0 = never-treated
      year = as.integer(t)  # CS expects integer time variable
    ) %>%
    filter(!is.na(y), !is.na(gname), !is.na(year)) %>%
    # For repeated cross-sections, need unique id per observation
    mutate(obs_id = row_number())

  # Validation checks
  n_treated <- n_distinct(panel_cs$state_abb[panel_cs$gname > 0])
  n_never <- n_distinct(panel_cs$state_abb[panel_cs$gname == 0])

  if (n_treated < 5 || n_never < 5) {
    log_msg(glue("  SKIP: Insufficient variation (treated={n_treated}, never={n_never})"))
    return(NULL)
  }

  log_msg(glue("  Treated states: {n_treated}"))
  log_msg(glue("  Never-treated states: {n_never}"))
  log_msg("  Control group: nevertreated (conservative)")
  log_msg("  SE method: analytical (clustered by state)")
  log_msg("  WARNING: Verify SEs are reasonable before trusting results!")

  # Estimate group-time ATTs
  tryCatch({
    att_results <- did::att_gt(
      yname = "y",
      tname = "year",
      idname = "obs_id",               # Use observation ID (for repeated cross-sections)
      gname = "gname",
      data = as.data.frame(panel_cs),  # did package wants data.frame
      control_group = "nevertreated",  # Use only never-treated as controls
      clustervars = "state_abb",       # CRITICAL: cluster by state
      est_method = "reg",              # Use regression (avoids fastglm segfault)
      base_period = "universal",       # Normalize all cohorts to same base
      anticipation = 0,                # No anticipation effects
      bstrap = FALSE,                  # Analytical SEs (FAST but verify!)
      cband = FALSE,                   # Don't compute uniform bands
      panel = FALSE,                   # Repeated cross-sections (avoids unbalanced panel issue)
      print_details = FALSE
    )

    # Aggregate to event study
    es <- tryCatch({
      did::aggte(
        att_results,
        type = "dynamic",
        balance_e = 1,  # Balance event times (numeric 1 or 0, not TRUE/FALSE)
        na.rm = TRUE
      )
    }, error = function(e1) {
      # Try without balance_e if it fails
      log_msg(glue("  Note: aggte with balance_e failed, trying without: {e1$message}"))
      tryCatch({
        did::aggte(
          att_results,
          type = "dynamic",
          na.rm = TRUE
        )
      }, error = function(e2) {
        log_msg(glue("  ERROR: aggte failed: {e2$message}"))
        return(NULL)
      })
    })

    if (is.null(es)) {
      log_msg("  Failed to aggregate to event study")
      return(NULL)
    }

    # CAREFUL extraction of results
    # The key is to extract from es$att.egt and es$se.egt (event-time specific!)
    # NOT from es$att or es$se (which are overall ATT)
    coefs <- tibble(
      e = es$egt,                    # Event times
      estimate = es$att.egt,         # ATT estimates
      se = es$se.egt                 # Standard errors (CRITICAL: event-time specific)
    ) %>%
      filter(!is.na(e), !is.na(estimate), !is.na(se)) %>%
      mutate(
        t_stat = estimate / se,
        p_value = 2 * pnorm(-abs(t_stat)),
        ci_lo = estimate - 1.96 * se,
        ci_hi = estimate + 1.96 * se
      )

    # Validation: Check SE extraction was successful
    if (nrow(coefs) == 0) {
      log_msg("  ERROR: Failed to extract coefficients")
      return(NULL)
    }

    if (any(is.na(coefs$se))) {
      log_msg("  WARNING: Some SEs are NA")
    }

    if (any(coefs$se <= 0, na.rm = TRUE)) {
      log_msg("  ERROR: Some SEs are non-positive (extraction error!)")
      return(NULL)
    }

    # Report SE range for validation
    se_range <- range(coefs$se, na.rm = TRUE)
    log_msg(glue("  SE range: [{round(se_range[1], 4)}, {round(se_range[2], 4)}]"))

    # Manual pre-trends F-test
    # We do this manually to be sure we're testing the right thing
    pre_coefs <- coefs %>% filter(e < 0)

    if (nrow(pre_coefs) > 0) {
      # Wald test: H0: all pre-treatment ATTs = 0
      # Simplified version (assumes independence across event times)
      # More accurate version would use full covariance matrix

      n_pre <- nrow(pre_coefs)
      wald_stat <- sum((pre_coefs$estimate^2) / (pre_coefs$se^2))
      p_value <- pchisq(wald_stat, df = n_pre, lower.tail = FALSE)

      log_msg(glue("  Pre-trends test (manual Wald):"))
      log_msg(glue("    H0: All {n_pre} pre-treatment ATTs = 0"))
      log_msg(glue("    Wald stat: {round(wald_stat, 2)}"))
      log_msg(glue("    p-value: {format.pval(p_value, eps = 0.001)}"))

      assessment <- if (p_value < 0.01) {
        "REJECT parallel trends (strong evidence of violation)"
      } else if (p_value < 0.05) {
        "REJECT parallel trends (p < 0.05)"
      } else if (p_value < 0.10) {
        "Marginal evidence against parallel trends (p < 0.10)"
      } else {
        "PASS: Fail to reject parallel trends"
      }

      log_msg(glue("    Assessment: {assessment}"))

      ftest <- tibble(
        n_pre_periods = n_pre,
        wald_stat = wald_stat,
        p_value = p_value,
        assessment = assessment,
        method = "CS-DiD (analytical SE, manual Wald)"
      )
    } else {
      log_msg("  No pre-treatment periods available")
      ftest <- NULL
    }

    # Compare to TWFE SEs (if available in parent scope)
    # This is just for validation - we'll do formal comparison later

    log_msg("  ✓ CS-DiD estimation complete")
    log_msg("  NOTE: These are ANALYTICAL SEs. For final results, re-run with bstrap=TRUE")

    return(list(
      att_gt = att_results,
      event_study = es,
      coefficients = coefs,
      pretrends_test = ftest,
      se_method = "analytical",
      n_treated = n_treated,
      n_never = n_never,
      control_group = "nevertreated"
    ))

  }, error = function(e) {
    log_msg(glue("  ERROR: CS-DiD failed: {e$message}"))
    return(NULL)
  })
}

################################################################################
# SECTION 9: MAIN ANALYSIS LOOP
################################################################################

log_msg("\n================================================================================")
log_msg("RUNNING ANALYSIS FOR ALL SPECIFICATIONS")
log_msg("================================================================================")

all_results <- list()

for (spec_name in names(SPECIFICATIONS)) {
  spec <- SPECIFICATIONS[[spec_name]]

  log_msg(glue("\n\n{strrep('=', 60)}"))
  log_msg(glue("SPECIFICATION: {spec$name}"))
  log_msg(glue("{strrep('=', 60)}"))
  log_msg(glue("Description: {spec$description}"))

  # Build panel
  panel <- build_panel_for_spec(panel_raw, gambling_dates, spec)

  # Check if we have enough variation
  n_treated <- n_distinct(panel$state_abb[panel$g > 0])
  n_never <- n_distinct(panel$state_abb[panel$g == 0])

  if (n_treated < 5 || n_never < 5) {
    log_msg(glue("  SKIPPED: Insufficient variation (treated={n_treated}, never={n_never}, need >=5 each)"))
    next
  }

  # Run TWFE event study
  twfe_result <- run_twfe_event_study(panel, spec)

  if (is.null(twfe_result)) {
    log_msg("  SKIPPED: TWFE estimation failed")
    next
  }

  # Run modern methods
  power_result <- run_power_analysis(twfe_result, spec)
  honest_result <- run_honestdid_analysis(twfe_result, spec)
  equiv_result <- run_equivalence_tests(twfe_result, spec)
  cs_result <- run_cs_did_analysis(panel, spec)

  # Store results
  all_results[[spec_name]] <- list(
    spec = spec,
    twfe = twfe_result,
    power = power_result,
    honestdid = honest_result,
    equivalence = equiv_result,
    cs_did = cs_result
  )

  # Save specification-specific outputs
  spec_dir <- file.path(OUT_DIR, spec_name)
  dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(twfe_result$coefs, file.path(spec_dir, "event_study_coefs.csv"))
  readr::write_csv(twfe_result$pretrends_test, file.path(spec_dir, "pretrends_ftest.csv"))

  if (!is.null(power_result)) {
    readr::write_csv(power_result$mde_table, file.path(spec_dir, "power_mde.csv"))
  }

  if (!is.null(equiv_result)) {
    equiv_summary <- tibble(
      delta_star_max = equiv_result$delta_star_max,
      rms_pretrends = equiv_result$rms_pretrends,
      interpretation = equiv_result$interpretation
    )
    readr::write_csv(equiv_summary, file.path(spec_dir, "equivalence_test.csv"))
  }

  if (!is.null(honest_result)) {
    # Save HonestDiD results
    honest_summary <- tibble()
    for (m_name in names(honest_result$results)) {
      m_val <- as.numeric(gsub("M_", "", m_name))
      res <- honest_result$results[[m_name]]
      honest_summary <- bind_rows(
        honest_summary,
        tibble(
          M = m_val,
          lb = res$lb,
          ub = res$ub,
          method = res$method,
          Delta = res$Delta
        )
      )
    }
    readr::write_csv(honest_summary, file.path(spec_dir, "honestdid_sensitivity.csv"))
  }

  if (!is.null(cs_result)) {
    readr::write_csv(cs_result$coefficients, file.path(spec_dir, "cs_did_coefs.csv"))
    if (!is.null(cs_result$pretrends_test)) {
      readr::write_csv(cs_result$pretrends_test, file.path(spec_dir, "cs_did_pretrends.csv"))
    }

    # Comparison: TWFE vs CS-DiD SEs
    se_comparison <- twfe_result$coefs %>%
      select(e, se_twfe = se) %>%
      left_join(
        cs_result$coefficients %>% select(e, se_cs = se),
        by = "e"
      ) %>%
      filter(!is.na(se_twfe), !is.na(se_cs)) %>%
      mutate(
        se_ratio = se_cs / se_twfe,
        method = "CS vs TWFE"
      )

    readr::write_csv(se_comparison, file.path(spec_dir, "se_comparison_twfe_vs_cs.csv"))
  }
}

################################################################################
# SECTION 9: CONSOLIDATED REPORT
################################################################################

log_msg("\n================================================================================")
log_msg("GENERATING CONSOLIDATED REPORT")
log_msg("================================================================================")

# Create comparison table
comparison <- tibble()

for (spec_name in names(all_results)) {
  res <- all_results[[spec_name]]

  pre_coefs <- res$twfe$coefs %>% filter(e < 0)
  max_pre <- if (nrow(pre_coefs) > 0) max(abs(pre_coefs$estimate)) else NA

  mde_80 <- if (!is.null(res$power) && nrow(res$power$mde_table) >= 2) {
    res$power$mde_table$mde_slope[2]
  } else {
    NA
  }

  delta_star <- if (!is.null(res$equivalence)) {
    res$equivalence$delta_star_max
  } else {
    NA
  }

  # CS-DiD results
  cs_pvalue <- if (!is.null(res$cs_did) && !is.null(res$cs_did$pretrends_test)) {
    res$cs_did$pretrends_test$p_value
  } else {
    NA
  }

  cs_max_se <- if (!is.null(res$cs_did)) {
    max(res$cs_did$coefficients$se, na.rm = TRUE)
  } else {
    NA
  }

  twfe_max_se <- max(res$twfe$coefs$se, na.rm = TRUE)

  comparison <- bind_rows(
    comparison,
    tibble(
      specification = res$spec$name,
      twfe_ftest_pval = res$twfe$pretrends_test$p_value,
      cs_did_pval = cs_pvalue,
      max_abs_pretrend = max_pre,
      twfe_max_se = twfe_max_se,
      cs_max_se = cs_max_se,
      mde_80pct_power = mde_80,
      delta_star_max = delta_star,
      assessment = case_when(
        is.na(twfe_ftest_pval) ~ "Unknown",
        twfe_ftest_pval > 0.10 & !is.na(mde_80) & mde_80 < 0.10 ~ "STRONG",
        twfe_ftest_pval > 0.05 & !is.na(mde_80) & mde_80 < 0.15 ~ "MODERATE",
        TRUE ~ "CAUTION"
      )
    )
  )
}

readr::write_csv(comparison, file.path(OUT_DIR, "specification_comparison.csv"))

# Generate markdown report
report_lines <- c(
  "# Pre-Trends Evaluation: Modern Methods",
  "",
  glue("**Generated**: {Sys.time()}"),
  glue("**Outcome**: {OUTCOME}"),
  glue("**Treatment**: Online gambling legalization"),
  "",
  "## Summary of Specifications",
  ""
)

for (i in 1:nrow(comparison)) {
  row <- comparison[i,]
  report_lines <- c(
    report_lines,
    glue("### {row$specification} [{row$assessment}]"),
    "",
    glue("- **TWFE F-test p-value**: {round(row$twfe_ftest_pval, 4)}"),
    glue("- **Max pre-trend coefficient**: {round(row$max_abs_pretrend, 4)}"),
    glue("- **MDE (80% power)**: {round(row$mde_80pct_power, 4)}"),
    glue("- **δ* (equivalence)**: {round(row$delta_star_max, 4)}"),
    ""
  )
}

report_lines <- c(
  report_lines,
  "",
  "## Interpretation Guide",
  "",
  "Following Roth (2022), we do NOT condition on pre-trends tests. Instead:",
  "",
  "1. **F-test**: Traditional joint test of pre-treatment coefficients = 0",
  "   - Failing to reject does NOT prove parallel trends holds",
  "   - Must assess power of the test",
  "",
  "2. **MDE (Minimal Detectable Effect)**: Slope of linear violation detectable with 80% power",
  "   - Small MDE (< 0.10): Test has good power",
  "   - Large MDE (> 0.15): Test is underpowered, passing test is uninformative",
  "",
  "3. **δ* (Equivalence Test)**: Smallest violation we can rule out",
  "   - Small δ* (< 0.10): Strong evidence FOR parallel trends",
  "   - Large δ* or NA: Weak evidence, cannot rule out violations",
  "",
  "4. **HonestDiD**: Sensitivity analysis showing how results change with bounded violations",
  "   - M=1: Post violations ≤ max pre violation",
  "   - Robust conclusions should hold for M ≥ 1",
  "",
  "## Assessment Criteria",
  "",
  "- **STRONG**: F-test p > 0.10, MDE < 0.10, good power and equivalence evidence",
  "- **MODERATE**: F-test p > 0.05, MDE < 0.15, some evidence for parallel trends",
  "- **CAUTION**: High MDE or cannot rule out violations, pre-trends test uninformative",
  "",
  "---",
  "",
  glue("Full results saved to: {OUT_DIR}/")
)

writeLines(report_lines, file.path(OUT_DIR, "report.md"))

log_msg("\n================================================================================")
log_msg("ANALYSIS COMPLETE")
log_msg("================================================================================")
log_msg(glue("Results saved to: {OUT_DIR}/"))
log_msg(glue("See {OUT_DIR}/report.md for detailed interpretation"))
log_msg("================================================================================")

cat("\n✓ Pre-trends evaluation complete!\n")
cat(glue("  Output directory: {OUT_DIR}/\n"))
cat(glue("  Specifications analyzed: {length(all_results)}\n"))
cat("\n")
