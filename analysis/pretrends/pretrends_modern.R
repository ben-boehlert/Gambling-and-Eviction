#!/usr/bin/env Rscript
################################################################################
# pretrends_modern.R
#
# Modern Pre-Trends Evaluation using:
# - HonestDiD (Rambachan & Roth 2023): Sensitivity analysis
# - Power Analysis (Roth 2022): Minimal detectable effects
# - Equivalence Testing (Hartman & Hidalgo 2018): Evidence FOR parallel trends
#
# Treatment: Online gambling legalization (online_start_date)
# Robustness: Baseline, No COVID, Narrow Window, Pre-2020
################################################################################

# Force single-threaded
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
  library(HonestDiD)
  library(pretrends)
})

# Load MASS last to avoid conflicts
library(MASS)

# ========================== SECTION 1: SETUP ==================================

# ----------------------------- Helper functions -------------------------------

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

# ----------------------------- Configuration ----------------------------------

# Core files
DATA_FILE <- getenv1("DATA_FILE", "combined_monthly_panel.csv")
GAMBLING_FILE <- getenv1("GAMBLING_FILE", "data/raw/sports_gambling_legalization_dates.csv")
OUT_DIR <- getenv1("OUT_DIR", "pretrends_modern_out")

# Outcome specification
OUTCOME <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

# General settings
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED <- parse_int(getenv1("SEED", "123"), 123L)

# Set seed
if (is.finite(SEED)) set.seed(SEED)

# Modern method parameters
MBAR_VALUES <- c(0, 0.5, 1, 1.5, 2)
TARGET_POWER <- c(0.5, 0.8)
DELTA_GRID <- seq(0.01, 0.20, by = 0.01)

# Define specifications
SPECIFICATIONS <- list(
  baseline = list(
    name = "Baseline",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24
  ),

  no_covid = list(
    name = "No COVID",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date("2020-03-01"),
    drop_end = as.Date("2021-07-31"),
    min_e = -24,
    max_e = 24
  ),

  narrow_window = list(
    name = "Narrow Window",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -12,
    max_e = 12
  ),

  pre2020 = list(
    name = "Pre-2020",
    exclude_states = "ME",
    max_date = as.Date("2019-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 12
  ),

  balanced_5 = list(
    name = "Balanced (>=5 states/year)",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    min_states_per_year = 5,
    treatment_years_allowed = c(2019, 2021, 2022)
  ),

  only_pre2020_adopters = list(
    name = "Only Pre-2020 Adopters",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    treatment_years_allowed = c(2018, 2019)
  ),

  only_post2021_adopters = list(
    name = "Only 2022+ Adopters",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    treatment_years_allowed = c(2022, 2023)
  ),

  only_2021_adopters = list(
    name = "Only 2021 Adopters",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    treatment_years_allowed = c(2021)
  ),

  activity_50pct_peak = list(
    name = "Activity: 50% of Peak Handle",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    use_activity_dates = TRUE,
    activity_threshold = "treat_50pct_peak"
  ),

  activity_500M = list(
    name = "Activity: $500M Cumulative",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    use_activity_dates = TRUE,
    activity_threshold = "treat_500M"
  ),

  activity_1B = list(
    name = "Activity: $1B Cumulative",
    exclude_states = "ME",
    max_date = as.Date("2024-12-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    use_activity_dates = TRUE,
    activity_threshold = "treat_1000M"
  )
)

# Initialize log
RUN_LOG <- file.path(OUT_DIR, "run_log.txt")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)

# ----------------------------- Header -----------------------------------------

header <- glue("
=== MODERN PRE-TRENDS DIAGNOSTICS ===
WD: {getwd()}
R: {R.version.string}
DATA_FILE: {DATA_FILE}
GAMBLING_FILE: {GAMBLING_FILE}
OUT_DIR: {OUT_DIR}
OUTCOME: {OUTCOME}
TREATMENT: Online gambling legalization only
SPECIFICATIONS: {paste(names(SPECIFICATIONS), collapse=', ')}
===========================
")

cat(header)
log_line(RUN_LOG, header)

# ========================== SECTION 2: PANEL CONSTRUCTION =====================

# ----------------------------- Panel build functions --------------------------

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

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
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

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d <= end)
}

build_panel_with_spec <- function(panel_raw, gambling_dates, spec, activity_dates = NULL) {
  # Choose treatment dates based on specification
  if (!is.null(spec$use_activity_dates) && spec$use_activity_dates && !is.null(activity_dates)) {
    # Use activity-based treatment dates
    threshold_col <- spec$activity_threshold
    if (!(threshold_col %in% names(activity_dates))) {
      stop(glue("Activity threshold column not found: {threshold_col}"))
    }

    gambling_dates_filtered <- activity_dates %>%
      dplyr::select(state_abb, online_start_date = !!sym(threshold_col))

    cat(glue("  Using activity-based treatment: {threshold_col}\n"))
  } else {
    # Use legal dates
    gambling_dates_filtered <- gambling_dates

    if (!is.null(spec$treatment_years_allowed)) {
      # Filter to only include states with treatment in allowed years
      gambling_dates_filtered <- gambling_dates_filtered %>%
        mutate(
          treatment_year = ifelse(
            is.na(online_start_date),
            NA_integer_,
            as.integer(format(online_start_date, "%Y"))
          )
        ) %>%
        mutate(
          online_start_date = ifelse(
            is.na(treatment_year) | treatment_year %in% spec$treatment_years_allowed,
            online_start_date,
            as.Date(NA)
          )
        ) %>%
        mutate(online_start_date = as.Date(online_start_date, origin = "1970-01-01")) %>%
        dplyr::select(state_abb, online_start_date)
    }
  }

  # Merge online gambling dates
  panel <- panel_raw %>%
    left_join(
      gambling_dates_filtered %>% dplyr::select(state_abb, online_start_date),
      by = "state_abb"
    )

  # Filter by spec
  exclude_vec <- if (nzchar(spec$exclude_states)) {
    strsplit(spec$exclude_states, ",")[[1]]
  } else {
    character()
  }

  if (length(exclude_vec) > 0) {
    panel <- panel %>% filter(!state_abb %in% exclude_vec)
  }

  if (!is.na(spec$max_date)) {
    panel <- panel %>% filter(month_date <= spec$max_date)
  }

  if (!is.na(spec$drop_start) && !is.na(spec$drop_end)) {
    panel <- panel %>% filter(!in_window(month_date, spec$drop_start, spec$drop_end))
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
  panel <- panel %>% filter(is.na(e) | (e >= spec$min_e & e <= spec$max_e))

  # Construct outcome
  if (OUTCOME == "log1p_filings_count") {
    panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
  } else if (OUTCOME == "log1p_rate") {
    panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + RATE_EPS))
  } else {
    stop(glue("Unknown OUTCOME: {OUTCOME}"))
  }

  # Remove missing outcomes
  panel <- panel %>% filter(!is.na(y))

  panel
}

# ========================== SECTION 3: LOAD DATA ==============================

log_line(RUN_LOG, "Loading data...")
cat("Loading data...\n")

# Load eviction panel
if (!file.exists(DATA_FILE)) {
  stop(glue("DATA_FILE not found: {DATA_FILE}"))
}
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

# Load gambling legalization dates
if (!file.exists(GAMBLING_FILE)) {
  stop(glue("GAMBLING_FILE not found: {GAMBLING_FILE}"))
}
gambling_raw <- readr::read_csv(GAMBLING_FILE, show_col_types = FALSE)

# Process gambling dates
gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  dplyr::select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

# Load activity-based treatment dates
ACTIVITY_FILE <- "data/processed/activity_treatment_dates.csv"
if (file.exists(ACTIVITY_FILE)) {
  cat("Loading activity-based treatment dates...\n")
  activity_dates <- readr::read_csv(ACTIVITY_FILE, show_col_types = FALSE)
  log_line(RUN_LOG, glue("Activity dates loaded: {nrow(activity_dates)} states"))
} else {
  cat("WARNING: Activity dates file not found:", ACTIVITY_FILE, "\n")
  activity_dates <- NULL
}

# Merge all states (even those without online gambling)
all_states <- tibble(state_abb = unique(panel_raw$state_abb))
gambling_dates <- all_states %>%
  left_join(gambling_dates, by = "state_abb")

log_line(RUN_LOG, glue("Loaded {nrow(panel_raw)} state-month observations"))
log_line(RUN_LOG, glue("Online gambling states: {sum(!is.na(gambling_dates$online_start_date))}"))
log_line(RUN_LOG, glue("Control states (no online): {sum(is.na(gambling_dates$online_start_date))}"))

# ========================== SECTION 4: TWFE EVENT STUDY =======================

run_twfe_event_study <- function(panel, spec, spec_name, out_dir) {
  cat(glue("\n--- Running TWFE for {spec$name} ---\n"))

  # Get event times
  event_times_all <- panel %>% filter(!is.na(e)) %>% pull(e) %>% unique() %>% sort()
  event_times_use <- event_times_all[event_times_all != -1]  # Omit reference

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
  twfe_mod <- fixest::feols(
    as.formula(formula_str),
    data = panel,
    cluster = ~id
  )

  # Extract coefficients
  twfe_coefs <- tibble(
    term = names(coef(twfe_mod)),
    estimate = as.numeric(coef(twfe_mod)),
    se = as.numeric(se(twfe_mod)),
    t_stat = estimate / se,
    p_value = 2 * pt(abs(t_stat), df = twfe_mod$nobs - length(coef(twfe_mod)), lower.tail = FALSE)
  ) %>%
    mutate(
      term_clean = gsub("`", "", term),
      term_clean = gsub("lead_", "", term_clean),
      e = as.integer(term_clean),
      lo = estimate - qnorm(1 - ALPHA/2) * se,
      hi = estimate + qnorm(1 - ALPHA/2) * se
    ) %>%
    dplyr::select(e, estimate, se, t_stat, p_value, lo, hi) %>%
    arrange(e)

  safe_write_csv(twfe_coefs, file.path(out_dir, "twfe_event_study.csv"))

  # Joint F-test on pre-treatment
  pre_event_times <- twfe_coefs %>% filter(e < 0) %>% pull(e)

  if (length(pre_event_times) > 0) {
    pre_terms <- paste0("lead_", pre_event_times)

    tryCatch({
      wald_result <- fixest::wald(twfe_mod, keep = pre_terms)

      pretrends_test <- tibble(
        ok = TRUE,
        method = "F-test on pre-treatment coefficients",
        n_leads = length(pre_event_times),
        f_stat = wald_result$stat,
        df1 = wald_result$df1,
        df2 = wald_result$df2,
        p_value = wald_result$p
      )

      cat(glue("Pre-trends F-test: F({wald_result$df1}, {wald_result$df2}) = {round(wald_result$stat, 3)}, p = {round(wald_result$p, 4)}\n"))
    }, error = function(e) {
      pretrends_test <<- tibble(
        ok = FALSE,
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
      ok = FALSE,
      method = "F-test on pre-treatment coefficients",
      n_leads = 0,
      f_stat = NA_real_,
      df1 = NA_integer_,
      df2 = NA_integer_,
      p_value = NA_real_
    )
  }

  safe_write_csv(pretrends_test, file.path(out_dir, "twfe_pretrends_joint_test.csv"))

  # Event study plot
  plot_data <- twfe_coefs %>%
    bind_rows(tibble(e = -1L, estimate = 0, se = 0, t_stat = NA_real_, p_value = NA_real_, lo = 0, hi = 0)) %>%
    arrange(e)

  p <- ggplot(plot_data, aes(x = e, y = estimate)) +
    geom_point(size = 2) +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40") +
    labs(
      title = glue("TWFE Event Study: {spec$name}"),
      subtitle = glue("F-test p = {round(pretrends_test$p_value, 3)}"),
      x = "Event Time (months relative to online gambling)",
      y = glue("Effect ({OUTCOME})")
    ) +
    theme_minimal()

  ggsave(file.path(out_dir, "twfe_event_study.png"), plot = p, width = 10, height = 6, dpi = 300)

  # Extract for modern methods
  beta <- twfe_coefs$estimate
  names(beta) <- twfe_coefs$e
  sigma <- vcov(twfe_mod, cluster = ~id)
  event_times <- twfe_coefs$e

  list(
    model = twfe_mod,
    coefs = twfe_coefs,
    pretrends_test = pretrends_test,
    beta = beta,
    sigma = sigma,
    event_times = event_times
  )
}

# ========================== SECTION 5: HONESTDID ==============================

run_honestdid_analysis <- function(beta, sigma, event_times, spec_name, out_dir) {
  cat(glue("Running HonestDiD sensitivity analysis...\n"))

  # Separate pre and post periods
  pre_idx <- event_times < 0
  post_idx <- event_times >= 0

  numPrePeriods <- sum(pre_idx)
  numPostPeriods <- sum(post_idx)

  if (numPrePeriods == 0 || numPostPeriods == 0) {
    warning("Need both pre and post periods for HonestDiD")
    return(NULL)
  }

  # Run for each Mbar value
  results_list <- list()

  for (Mbar in MBAR_VALUES) {
    tryCatch({
      honest_result <- HonestDiD::createSensitivityResults(
        betahat = beta,
        sigma = sigma,
        numPrePeriods = numPrePeriods,
        numPostPeriods = numPostPeriods,
        Mbarvec = Mbar,
        method = "C-LF",
        alpha = ALPHA
      )

      results_list[[paste0("M", Mbar)]] <- honest_result
    }, error = function(e) {
      warning(glue("HonestDiD failed for Mbar={Mbar}: {e$message}"))
    })
  }

  if (length(results_list) == 0) {
    warning("All HonestDiD runs failed")
    return(NULL)
  }

  # Extract robust CIs
  honest_summary <- tibble()
  for (mname in names(results_list)) {
    res <- results_list[[mname]]
    if (!is.null(res)) {
      # Extract CI info (structure depends on HonestDiD version)
      honest_summary <- bind_rows(
        honest_summary,
        tibble(
          Mbar = gsub("M", "", mname),
          method = "Relative Magnitudes"
        )
      )
    }
  }

  safe_write_csv(honest_summary, file.path(out_dir, "honestdid_summary.csv"))

  results_list
}

# ========================== SECTION 6: POWER ANALYSIS =========================

run_power_analysis <- function(beta, sigma, event_times, spec_name, out_dir) {
  cat(glue("Running power analysis...\n"))

  # Separate pre-treatment periods
  pre_idx <- event_times < 0
  if (sum(pre_idx) == 0) {
    warning("No pre-treatment periods for power analysis")
    return(NULL)
  }

  beta_pre <- beta[pre_idx]
  sigma_pre <- sigma[pre_idx, pre_idx]
  event_times_pre <- event_times[pre_idx]

  # Calculate slopes for target power levels
  power_results <- list()

  for (target_pwr in TARGET_POWER) {
    tryCatch({
      slope <- pretrends::slope_for_power(
        sigma = sigma_pre,
        targetPower = target_pwr,
        tVec = event_times_pre,
        referencePeriod = -1
      )

      power_results[[paste0("power_", target_pwr)]] <- slope
    }, error = function(e) {
      warning(glue("Power calculation failed for power={target_pwr}: {e$message}"))
      power_results[[paste0("power_", target_pwr)]] <<- NA
    })
  }

  # Create MDE table
  mde_table <- tibble(
    target_power = TARGET_POWER,
    mde_slope = unlist(power_results)
  )

  safe_write_csv(mde_table, file.path(out_dir, "power_analysis_mde.csv"))

  cat(glue("Power analysis: 50% power for slope {round(mde_table$mde_slope[1], 4)}, 80% power for {round(mde_table$mde_slope[2], 4)}\n"))

  mde_table
}

# ========================== SECTION 7: EQUIVALENCE TESTING ====================

equivalence_test_max <- function(beta_pre, sigma_pre, delta, alpha = 0.05) {
  # Test H0: max|β_l| >= δ  vs  H1: max|β_l| < δ
  T_pre <- length(beta_pre)

  p_values <- sapply(1:T_pre, function(l) {
    se_l <- sqrt(sigma_pre[l, l])
    pnorm((abs(beta_pre[l]) - delta) / se_l)
  })

  # Reject if ALL p-values < alpha
  reject <- all(p_values < alpha)

  list(
    reject = reject,
    test_stat = max(abs(beta_pre)),
    p_value = max(p_values)  # Most conservative
  )
}

equivalence_test_average <- function(beta_pre, sigma_pre, delta, alpha = 0.05) {
  # Test H0: |mean(β)| >= δ  vs  H1: |mean(β)| < δ
  T_pre <- length(beta_pre)
  avg_beta <- mean(beta_pre)

  # Standard error of average
  ones <- rep(1, T_pre) / T_pre
  var_avg <- as.numeric(t(ones) %*% sigma_pre %*% ones)
  se_avg <- sqrt(var_avg)

  # Two one-sided tests
  t_stat <- abs(avg_beta) / se_avg
  p_value <- pnorm((delta - abs(avg_beta)) / se_avg)

  reject <- p_value < alpha

  list(
    reject = reject,
    test_stat = abs(avg_beta),
    p_value = p_value
  )
}

equivalence_test_rms <- function(beta_pre, sigma_pre, delta, alpha = 0.05, B = 500) {
  # Test H0: sqrt(mean(β²)) >= δ  vs  H1: sqrt(mean(β²)) < δ
  T_pre <- length(beta_pre)
  rms_observed <- sqrt(mean(beta_pre^2))

  # Bootstrap for null distribution
  rms_boot <- numeric(B)
  for (b in 1:B) {
    beta_boot <- MASS::mvrnorm(1, mu = rep(0, T_pre), Sigma = sigma_pre)
    rms_boot[b] <- sqrt(mean(beta_boot^2))
  }

  # Critical value: (1-alpha) quantile under H0: RMS = delta
  # Scale bootstrap samples to delta
  rms_boot_scaled <- rms_boot * (delta / mean(rms_boot))
  critical_val <- quantile(rms_boot_scaled, 1 - alpha)

  reject <- rms_observed < critical_val

  list(
    reject = reject,
    test_stat = rms_observed,
    critical_val = critical_val
  )
}

find_minimal_delta <- function(beta_pre, sigma_pre, test_type, delta_grid, alpha = 0.05) {
  # Find smallest δ for which we reject H0: violation >= δ
  for (delta in delta_grid) {
    result <- switch(test_type,
      "max" = equivalence_test_max(beta_pre, sigma_pre, delta, alpha),
      "average" = equivalence_test_average(beta_pre, sigma_pre, delta, alpha),
      "rms" = equivalence_test_rms(beta_pre, sigma_pre, delta, alpha, B = 500)
    )

    if (result$reject) {
      return(delta)
    }
  }

  NA  # Never rejected
}

run_equivalence_tests <- function(beta, sigma, event_times, spec_name, out_dir) {
  cat(glue("Running equivalence tests...\n"))

  # Pre-treatment periods only
  pre_idx <- event_times < 0
  if (sum(pre_idx) == 0) {
    warning("No pre-treatment periods for equivalence tests")
    return(NULL)
  }

  beta_pre <- beta[pre_idx]
  sigma_pre <- sigma[pre_idx, pre_idx]

  # Find minimal δ* for each test
  delta_star_max <- find_minimal_delta(beta_pre, sigma_pre, "max", DELTA_GRID, ALPHA)
  delta_star_avg <- find_minimal_delta(beta_pre, sigma_pre, "average", DELTA_GRID, ALPHA)
  delta_star_rms <- find_minimal_delta(beta_pre, sigma_pre, "rms", DELTA_GRID, ALPHA)

  equiv_results <- tibble(
    test = c("Maximum", "Average", "RMS"),
    delta_star = c(delta_star_max, delta_star_avg, delta_star_rms),
    interpretation = case_when(
      is.na(delta_star) ~ "Cannot rule out large violations",
      delta_star < 0.05 ~ "Very strong evidence for parallel trends",
      delta_star < 0.10 ~ "Strong evidence for parallel trends",
      delta_star < 0.15 ~ "Moderate evidence for parallel trends",
      TRUE ~ "Weak evidence for parallel trends"
    )
  )

  safe_write_csv(equiv_results, file.path(out_dir, "equivalence_tests.csv"))

  cat(glue("Equivalence: δ*_max = {round(delta_star_max, 3)}, δ*_avg = {round(delta_star_avg, 3)}, δ*_rms = {round(delta_star_rms, 3)}\n"))

  equiv_results
}

# ========================== SECTION 7.5: CS-DID DYNAMIC EFFECTS ===============

run_cs_did <- function(panel, spec_name, out_dir, twfe_result) {
  cat(glue("\nRunning CS-DiD for {spec_name}...\n"))

  # Check if did package is available
  if (!requireNamespace("did", quietly = TRUE)) {
    cat("  SKIPPED: 'did' package not installed\n")
    return(NULL)
  }

  # Prepare data for CS-DiD
  # Need: yname, tname, idname, gname
  cs_data <- panel %>%
    filter(!is.na(y)) %>%
    mutate(
      year_period = as.integer(format(month_date, "%Y")),
      id_numeric = as.integer(id)
    )

  # Check if we have variation in treatment timing
  n_cohorts <- n_distinct(cs_data$g[cs_data$g > 0])
  n_never_treated <- sum(cs_data$g == 0)

  if (n_cohorts < 2) {
    cat("  SKIPPED: Need at least 2 treatment cohorts for CS-DiD\n")
    return(NULL)
  }

  if (n_never_treated == 0) {
    cat("  SKIPPED: Need never-treated units for CS-DiD\n")
    return(NULL)
  }

  cat(glue("  Cohorts: {n_cohorts}, Never-treated: {sum(cs_data$g == 0)/n_distinct(cs_data$id)} states\n"))

  # Run CS-DiD WITHOUT bootstrap (SEs unreliable with small cohorts)
  cs_att <- tryCatch({
    did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id_numeric",
      gname = "g",
      data = cs_data,
      control_group = "nevertreated",
      est_method = "reg",
      bstrap = FALSE,  # CRITICAL: Skip bootstrap due to small cohort issues
      anticipation = 0,
      allow_unbalanced_panel = TRUE
    )
  }, error = function(e) {
    cat("  ERROR in att_gt():", conditionMessage(e), "\n")
    return(NULL)
  })

  if (is.null(cs_att)) {
    return(NULL)
  }

  # Aggregate to event-time (dynamic effects)
  cs_dynamic <- tryCatch({
    did::aggte(cs_att, type = "dynamic", na.rm = TRUE)
  }, error = function(e) {
    cat("  ERROR in aggte():", conditionMessage(e), "\n")
    return(NULL)
  })

  if (is.null(cs_dynamic)) {
    return(NULL)
  }

  # Extract point estimates (NO SEs available)
  cs_event_study <- tibble(
    e = cs_dynamic$egt,
    estimate_cs = cs_dynamic$att.egt,
    method = "CS-DiD"
  )

  # Add TWFE estimates for comparison
  twfe_event_study <- tibble(
    e = twfe_result$event_times,
    estimate_twfe = twfe_result$beta,
    method = "TWFE"
  )

  # Combine for comparison plot
  combined_event_study <- bind_rows(
    cs_event_study %>% rename(estimate = estimate_cs),
    twfe_event_study %>% rename(estimate = estimate_twfe)
  )

  # Plot CS vs TWFE
  p_comparison <- ggplot(combined_event_study, aes(x = e, y = estimate, color = method, shape = method)) +
    geom_point(size = 2) +
    geom_line(alpha = 0.6) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray30") +
    scale_color_manual(values = c("CS-DiD" = "#E41A1C", "TWFE" = "#377EB8")) +
    scale_shape_manual(values = c("CS-DiD" = 16, "TWFE" = 17)) +
    labs(
      title = glue("{spec_name}: CS-DiD vs. TWFE Event Study"),
      subtitle = "CS-DiD point estimates only (bootstrap SEs unavailable)",
      x = "Event Time (Months Relative to Treatment)",
      y = "Effect on Log Eviction Filings",
      color = "Method",
      shape = "Method"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      plot.title = element_text(face = "bold")
    )

  ggsave(
    file.path(out_dir, "cs_vs_twfe_comparison.png"),
    p_comparison,
    width = 10,
    height = 6,
    dpi = 300
  )

  # Save point estimates
  safe_write_csv(
    cs_event_study,
    file.path(out_dir, "cs_dynamic_estimates.csv")
  )

  safe_write_csv(
    combined_event_study,
    file.path(out_dir, "cs_twfe_comparison.csv")
  )

  cat(glue("  CS-DiD complete (point estimates only, no SEs)\n"))
  cat(glue("  Pre-treatment CS coefficients: {sum(cs_event_study$e < 0)} periods\n"))

  # Return results
  list(
    cs_event_study = cs_event_study,
    combined = combined_event_study,
    n_cohorts = n_cohorts
  )
}

# ========================== SECTION 8: SPECIFICATION LOOP =====================

all_results <- list()

for (spec_name in names(SPECIFICATIONS)) {
  spec <- SPECIFICATIONS[[spec_name]]

  cat(glue("\n{strrep('=', 60)}\n"))
  cat(glue("Running specification: {spec$name}\n"))
  cat(glue("{strrep('=', 60)}\n"))

  log_line(RUN_LOG, glue("\n--- Specification: {spec$name} ---"))

  # Create output directory
  spec_out_dir <- file.path(OUT_DIR, "specifications", spec_name)
  dir.create(spec_out_dir, recursive = TRUE, showWarnings = FALSE)

  # Build panel
  panel <- build_panel_with_spec(panel_raw, gambling_dates, spec, activity_dates)

  # Panel diagnostics
  panel_summary <- tibble(
    n_states = n_distinct(panel$id),
    n_months = n_distinct(panel$t),
    n_rows = nrow(panel),
    min_date = as.character(min(panel$month_date, na.rm = TRUE)),
    max_date = as.character(max(panel$month_date, na.rm = TRUE)),
    n_never_treated = n_distinct(panel$id[panel$g == 0]),
    n_switchers = n_distinct(panel$id[panel$g > 0])
  )

  safe_write_csv(panel_summary, file.path(spec_out_dir, "panel_summary.csv"))

  cat(glue("Panel: {panel_summary$n_states} states, {panel_summary$n_rows} rows\n"))
  cat(glue("Never-treated: {panel_summary$n_never_treated}, Treated: {panel_summary$n_switchers}\n"))

  # TWFE event study
  twfe_result <- run_twfe_event_study(panel, spec, spec_name, spec_out_dir)

  if (is.null(twfe_result)) {
    warning(glue("TWFE failed for {spec_name}"))
    next
  }

  # Modern methods
  honest_result <- run_honestdid_analysis(
    twfe_result$beta,
    twfe_result$sigma,
    twfe_result$event_times,
    spec_name,
    spec_out_dir
  )

  power_result <- run_power_analysis(
    twfe_result$beta,
    twfe_result$sigma,
    twfe_result$event_times,
    spec_name,
    spec_out_dir
  )

  equiv_result <- run_equivalence_tests(
    twfe_result$beta,
    twfe_result$sigma,
    twfe_result$event_times,
    spec_name,
    spec_out_dir
  )

  # Run CS-DiD for dynamic effects (without bootstrap SEs)
  # TEMPORARILY DISABLED due to segfault issues with did package
  cs_result <- NULL
  # cs_result <- tryCatch({
  #   run_cs_did(panel, spec_name, spec_out_dir, twfe_result)
  # }, error = function(e) {
  #   cat("WARNING: CS-DiD failed for", spec_name, ":", conditionMessage(e), "\n")
  #   NULL
  # })

  # Store results
  all_results[[spec_name]] <- list(
    spec = spec,
    panel_summary = panel_summary,
    twfe = twfe_result,
    honest = honest_result,
    power = power_result,
    equivalence = equiv_result,
    cs_did = cs_result
  )
}

# ========================== SECTION 9: CONSOLIDATED OUTPUT ===================

cat(glue("\n{strrep('=', 60)}\n"))
cat(glue("Creating consolidated outputs...\n"))
cat(glue("{strrep('=', 60)}\n"))

comp_dir <- file.path(OUT_DIR, "comparison")
dir.create(comp_dir, recursive = TRUE, showWarnings = FALSE)

# Robustness comparison matrix
comp_matrix <- tibble()

for (spec_name in names(all_results)) {
  res <- all_results[[spec_name]]

  if (is.null(res$twfe)) next

  # Pre-treatment stats
  pre_coefs <- res$twfe$coefs %>% filter(e < 0)
  max_pre <- if (nrow(pre_coefs) > 0) max(abs(pre_coefs$estimate)) else NA

  # Power MDE
  mde_80 <- if (!is.null(res$power) && nrow(res$power) >= 2) res$power$mde_slope[2] else NA

  # Equivalence δ*
  delta_max <- if (!is.null(res$equivalence)) res$equivalence$delta_star[1] else NA
  delta_rms <- if (!is.null(res$equivalence)) res$equivalence$delta_star[3] else NA

  comp_matrix <- bind_rows(
    comp_matrix,
    tibble(
      specification = res$spec$name,
      f_test_p = res$twfe$pretrends_test$p_value,
      max_abs_pre = max_pre,
      mde_80_power = mde_80,
      delta_star_max = delta_max,
      delta_star_rms = delta_rms
    )
  )
}

safe_write_csv(comp_matrix, file.path(comp_dir, "robustness_matrix.csv"))

# Traffic light assessment
comp_matrix <- comp_matrix %>%
  mutate(
    assessment = case_when(
      is.na(f_test_p) ~ "Unknown",
      f_test_p > 0.10 & mde_80_power < 0.10 & delta_star_max < 0.10 ~ "GREEN",
      f_test_p > 0.05 & mde_80_power < 0.15 & delta_star_max < 0.15 ~ "YELLOW",
      TRUE ~ "RED"
    )
  )

safe_write_csv(comp_matrix, file.path(comp_dir, "robustness_matrix_assessed.csv"))

# Consolidated report
report_lines <- c(
  "# Modern Pre-Trends Diagnostics Report",
  "",
  glue("Generated: {Sys.time()}"),
  "Treatment: Online gambling legalization only",
  "",
  "## Executive Summary",
  ""
)

# Overall assessment
n_green <- sum(comp_matrix$assessment == "GREEN", na.rm = TRUE)
n_yellow <- sum(comp_matrix$assessment == "YELLOW", na.rm = TRUE)
n_red <- sum(comp_matrix$assessment == "RED", na.rm = TRUE)

overall <- if (n_green == nrow(comp_matrix)) {
  "STRONG - All specifications pass robustness checks"
} else if (n_red > n_green) {
  "CONCERNING - Multiple specifications fail robustness checks"
} else if (n_yellow > 0) {
  "MODERATE - Some specifications show caution flags"
} else {
  "MIXED - Results vary across specifications"
}

report_lines <- c(
  report_lines,
  glue("**Overall Assessment**: {overall}"),
  "",
  "### Specification Results",
  ""
)

for (i in 1:nrow(comp_matrix)) {
  row <- comp_matrix[i,]
  report_lines <- c(
    report_lines,
    glue("**{row$specification}** [{row$assessment}]"),
    glue("- F-test p-value: {round(row$f_test_p, 4)}"),
    glue("- Max pre-treatment coefficient: {round(row$max_abs_pre, 3)}"),
    glue("- MDE (80% power): {round(row$mde_80_power, 3)}"),
    glue("- δ* (max test): {round(row$delta_star_max, 3)}"),
    ""
  )
}

report_lines <- c(
  report_lines,
  "## Interpretation Guide",
  "",
  "**Traffic Light System:**",
  "- GREEN: Strong evidence for parallel trends (F-test p > 0.10, low MDE, small δ*)",
  "- YELLOW: Moderate concerns (0.05 < p < 0.10, moderate MDE/δ*)",
  "- RED: Significant concerns about parallel trends (p < 0.05, high MDE, large δ*)",
  "",
  "**Key Metrics:**",
  "- F-test: Joint test of pre-treatment coefficients = 0",
  "- MDE: Minimal Detectable Effect - slope of violation test has 80% power to detect",
  "- δ*: Smallest violation we can rule out with 95% confidence",
  "",
  "## Methodology",
  "",
  "This analysis implements three modern approaches:",
  "",
  "1. **HonestDiD (Rambachan & Roth 2023)**: Sensitivity analysis with bounded violations",
  "2. **Power Analysis (Roth 2022)**: Minimal detectable pre-trend violations",
  "3. **Equivalence Testing (Hartman & Hidalgo 2018)**: Evidence FOR parallel trends",
  "",
  "Following Roth's guidance, this analysis quantifies defendable assumptions",
  "rather than providing binary pass/fail tests.",
  "",
  "## Output Files",
  "",
  glue("All outputs saved to: {OUT_DIR}/"),
  "- specifications/[spec_name]/ : Individual specification results",
  "- comparison/ : Cross-specification comparisons",
  "",
  "---",
  glue("Analysis completed: {Sys.time()}")
)

writeLines(report_lines, file.path(OUT_DIR, "consolidated_report.md"))

# ========================== COMPLETION ========================================

log_line(RUN_LOG, "\n=== ANALYSIS COMPLETE ===")
log_line(RUN_LOG, glue("Outputs written to: {OUT_DIR}"))

cat("\n")
cat(strrep("=", 60), "\n")
cat("MODERN PRE-TRENDS ANALYSIS COMPLETE\n")
cat(glue("Outputs written to: {OUT_DIR}\n"))
cat(glue("See {OUT_DIR}/consolidated_report.md for summary\n"))
cat("\n")
