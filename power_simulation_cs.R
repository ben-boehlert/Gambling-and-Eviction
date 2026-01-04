################################################################################
# power_simulation_cs.R
#
# Simulation-based power analysis for staggered-adoption DiD using CS (did::att_gt)
#
# Key fixes vs your prior version:
#   1) COLLAPSE the ETS "states/sites" files to 1 row per unit-month (they’re massively duplicated).
#   2) Use a real treatment schedule (sports_gambling_legalization_dates.csv).
#   3) Keep inference aligned with planned clustering (and bootstrap if that’s your plan).
#   4) Make runtime sane: default did_biters=50 (not 199) + optional parallel execution.
#
# Files used (must be present in data_dir):
#   - allstates_monthly_2020_2021.csv
#   - all_sites_monthly_2020_2021.csv
#   - monthly_county_data_download.csv
#   - sports_gambling_legalization_dates.csv
#
# Outputs:
#   - power_results.csv
#   - power_curve.png
#   - grant_ready_paragraph.txt
################################################################################
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(stringr)
  library(zoo)
  library(did)
  library(fixest)
  library(glue)
  library(future)
  library(furrr)
  library(progressr)
})

set.seed(20251224)
handlers(global = TRUE)
handlers("txtprogressbar")
options(progressr.enable = TRUE)
################################################################################
# 0) CONFIG
################################################################################

if (!exists("cfg", inherits = FALSE)) {
  cfg <- list(
    # Where your CSVs live
    data_dir = ".",   # e.g. "." locally, or "/scratch/..." on Della
    
    # Panel choice:
    #   - "counties" (2016–2025, clean unit-month; state policy at county level)
    #   - "states_ets" (ETS-derived, MUST be collapsed; only 10 states in your file)
    #   - "sites_ets"  (ETS-derived, MUST be collapsed)
    #   - "states_from_counties" (build a full state-month panel by aggregating counties)
    panel_choice = "states_from_counties",  # Use state-level panel for state policies
    
    # Outcome preference (script uses first available)
    outcome_preference = c(
      "filings_per_1k_renters",
      "filings_count_per_1k_renters",
      "filings_count",
      "filings_2020",
      "filings_avg",
      "percent_of_historical_average"
    ),
    
    # Optional weights (did supports weightsname). For county: renters is a natural weight.
    weights_var = "renter_occupied_housing_units",  # set NULL to disable weights
    
    # Treatment definition from sports_gambling_legalization_dates.csv
    # Choose one: "online_start_date", "retail_start_date", "first_start_date"
    treat_date_col = "online_start_date",
    
    # Simulation grid
    n_sims = 25,
    effect_grid = c(0, 1, 2, 3),
    alpha = 0.05,
    power_target = 0.80,
    run_state_switcher_grid = TRUE,
    n_states_grid = c(10, 15, 20, 25),
    n_switchers_grid = c(3, 5, 8, 10),
    
    # Estimand:
    #   - "overall_att" => aggte(type="simple") overall ATT p-value
    #   - "event_time"  => aggte(type="dynamic") p-value at target_h
    estimand = "overall_att",
    target_h = 12,
    
    # Required windows (months) around *placebo* adoption inside untreated baseline
    pre_len = 12,
    post_len = 12,
    
    # Effect path shape
    effect_shape = "step",  # "step" | "ramp" | "delayed"
    delay_h = 6,
    
    # Inference for did::att_gt
    # If you will bootstrap in the paper, keep did_bstrap=TRUE here.
    # Reduce did_biters for feasibility; you can do a “final confirm” with bigger biters at the MDE.
    did_bstrap = TRUE,
    did_biters = 50,
    did_cband = FALSE,
    
    # Clustering choice:
    #   - "unit" => cluster at unit_id
    #   - "state" => cluster at state (works for counties/sites if state is available/derived)
    # NOTE: For counties, MUST use "state" since treatment is state-level
    cluster_level = "state",
    
    # Parallel settings (strongly recommended on Della)
    use_parallel = TRUE,
    workers = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))
  )
}

################################################################################
# 1) Helpers: parsing and indexing
################################################################################

parse_month_to_date <- function(x) {
  # Accept Date/POSIXt directly
  if (inherits(x, "Date"))   return(as.Date(floor_date(x, "month")))
  if (inherits(x, "POSIXt")) return(as.Date(floor_date(as.Date(x), "month")))
  
  x_chr <- as.character(x)
  # NA-safe string vector
  x_chr[is.na(x_chr)] <- ""
  
  out <- rep(as.Date(NA), length(x_chr))
  
  # Helper: NA-safe regex detect
  detect <- function(v, pattern) {
    # v has no NA here, but keep it robust
    r <- str_detect(v, pattern)
    r[is.na(r)] <- FALSE
    r
  }
  
  # ISO datetime like "2024-12-01 12:00:00"
  idx_iso_dt <- detect(x_chr, "^\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2}")
  if (any(idx_iso_dt, na.rm = TRUE)) {
    out[idx_iso_dt] <- suppressWarnings(
      as.Date(floor_date(ymd_hms(x_chr[idx_iso_dt], quiet = TRUE), "month"))
    )
  }
  
  # ISO date like "2018-06-01"
  idx_iso_d <- is.na(out) & detect(x_chr, "^\\d{4}-\\d{2}-\\d{2}$")
  if (any(idx_iso_d, na.rm = TRUE)) {
    out[idx_iso_d] <- suppressWarnings(
      as.Date(floor_date(ymd(x_chr[idx_iso_d], quiet = TRUE), "month"))
    )
  }
  
  # Month-year text: "Jan-20" or "Jun 2018"
  idx_my <- is.na(out) & detect(x_chr, "^[A-Za-z]{3}[-\\s]\\d{2,4}$")
  if (any(idx_my, na.rm = TRUE)) {
    out[idx_my] <- suppressWarnings(
      as.Date(floor_date(parse_date_time(
        x_chr[idx_my],
        orders = c("b-y", "b Y"),
        quiet = TRUE
      ), "month"))
    )
  }
  
  # Last resort: try ymd on anything left
  idx_rest <- is.na(out) & nzchar(x_chr)
  if (any(idx_rest, na.rm = TRUE)) {
    out[idx_rest] <- suppressWarnings(
      as.Date(floor_date(ymd(x_chr[idx_rest], quiet = TRUE), "month"))
    )
  }
  
  out
}


date_to_time_id <- function(d) {
  d <- as.Date(d)
  year(d) * 12L + month(d)
}

g_to_time_id <- function(g) {
  if (inherits(g, "Date")) return(date_to_time_id(g))
  if (is.character(g)) return(date_to_time_id(parse_month_to_date(g)))
  if (is.numeric(g)) return(as.integer(g))
  stop("Unsupported g type. Use Date, character month, or numeric time_id.")
}
# Make state identifiers comparable across sources:
# "Rhode Island" / "rhode_island" / "rhodeisland" -> "rhodeisland"
state_key <- function(x) {
  x %>%
    as.character() %>%
    str_to_lower() %>%
    str_replace_all("[^a-z]", "")
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

################################################################################
# 2) Crosswalks (for counties/sites -> state) so we can assign treatment & cluster
################################################################################

state_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb, ~state_name,
  1, "AL", "Alabama",
  2, "AK", "Alaska",
  4, "AZ", "Arizona",
  5, "AR", "Arkansas",
  6, "CA", "California",
  8, "CO", "Colorado",
  9, "CT", "Connecticut",
  10, "DE", "Delaware",
  11, "DC", "District of Columbia",
  12, "FL", "Florida",
  13, "GA", "Georgia",
  15, "HI", "Hawaii",
  16, "ID", "Idaho",
  17, "IL", "Illinois",
  18, "IN", "Indiana",
  19, "IA", "Iowa",
  20, "KS", "Kansas",
  21, "KY", "Kentucky",
  22, "LA", "Louisiana",
  23, "ME", "Maine",
  24, "MD", "Maryland",
  25, "MA", "Massachusetts",
  26, "MI", "Michigan",
  27, "MN", "Minnesota",
  28, "MS", "Mississippi",
  29, "MO", "Missouri",
  30, "MT", "Montana",
  31, "NE", "Nebraska",
  32, "NV", "Nevada",
  33, "NH", "New Hampshire",
  34, "NJ", "New Jersey",
  35, "NM", "New Mexico",
  36, "NY", "New York",
  37, "NC", "North Carolina",
  38, "ND", "North Dakota",
  39, "OH", "Ohio",
  40, "OK", "Oklahoma",
  41, "OR", "Oregon",
  42, "PA", "Pennsylvania",
  44, "RI", "Rhode Island",
  45, "SC", "South Carolina",
  46, "SD", "South Dakota",
  47, "TN", "Tennessee",
  48, "TX", "Texas",
  49, "UT", "Utah",
  50, "VT", "Vermont",
  51, "VA", "Virginia",
  53, "WA", "Washington",
  54, "WV", "West Virginia",
  55, "WI", "Wisconsin",
  56, "WY", "Wyoming"
)

################################################################################
# 3) Panel prep: read + collapse to 1 row per unit-month
################################################################################

# Collapse helper: sum selected numeric columns, keep other columns via first()
collapse_unit_month <- function(df, unit_col, month_col, sum_cols = NULL, keep_cols = NULL) {
  unit_col <- rlang::ensym(unit_col)
  month_col <- rlang::ensym(month_col)
  
  df %>%
    mutate(
      month_date = parse_month_to_date(!!month_col),
      time_id = date_to_time_id(month_date)
    ) %>%
    group_by(!!unit_col, month_date, time_id) %>%
    summarise(
      across(all_of(sum_cols %||% character(0)), ~ sum(as.numeric(.x), na.rm = TRUE)),
      across(all_of(keep_cols %||% character(0)), ~ dplyr::first(.x)),
      .groups = "drop"
    ) %>%
    rename(unit_id = !!unit_col)
}

pick_outcome <- function(df, cfg) {
  y <- cfg$outcome_preference[cfg$outcome_preference %in% names(df)][1]
  if (is.na(y)) stop("Could not find any preferred outcome column. Update cfg$outcome_preference.")
  df %>% mutate(outcome = as.numeric(.data[[y]])) %>% { attr(., "outcome_var") <- y; . }
}

prep_panel_counties <- function(cfg) {
  path <- file.path(cfg$data_dir, "monthly_county_data_download.csv")
  df <- read_csv(path, show_col_types = FALSE) %>%
    mutate(
      unit_id = as.numeric(fips),  # MUST be numeric for did::att_gt
      month_date = parse_month_to_date(date),
      time_id = date_to_time_id(month_date),
      # derive state from fips (first two digits)
      state_fips = as.integer(floor(as.numeric(fips) / 1000))
    ) %>%
    left_join(state_fips_xwalk, by = "state_fips") %>%
    # Filter out territories (PR=72, VI=78) that lack state_abb after join
    filter(!is.na(state_abb)) %>%
    mutate(
      # canonical county outcome
      filings_count_per_1k_renters = if_else(
        !is.na(filings_count) & !is.na(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        NA_real_
      )
    ) %>%
    arrange(unit_id, time_id)

  df <- pick_outcome(df, cfg)

  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome))
}

prep_panel_states_from_counties <- function(cfg) {
  # Build a proper 50-state panel by aggregating the county file to state-month
  counties <- prep_panel_counties(cfg)
  
  # Sum filings & renters to create a state-month filings per 1k renters
  df <- counties %>%
    group_by(state_abb, state_name, month_date, time_id) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      # Get state FIPS for numeric unit_id (required by did::att_gt)
      state_fips = first(state_fips),
      # Only compute weighted mean if poverty_rate exists; handle NA values properly
      poverty_rate = {
        if ("poverty_rate" %in% names(pick(everything()))) {
          x <- poverty_rate
          w <- renter_occupied_housing_units
          valid <- !is.na(x) & !is.na(w) & w > 0
          if (sum(valid) > 0) weighted.mean(x[valid], w[valid]) else NA_real_
        } else {
          NA_real_
        }
      },
      .groups = "drop"
    ) %>%
    mutate(
      unit_id = as.numeric(state_fips),  # MUST be numeric for did::att_gt
      filings_count_per_1k_renters = if_else(
        renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        NA_real_
      )
    )
  
  # For states-from-counties we prefer per-1k
  cfg2 <- cfg
  cfg2$outcome_preference <- c("filings_count_per_1k_renters", cfg$outcome_preference)
  df <- pick_outcome(df, cfg2)
  
  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

prep_panel_states_ets <- function(cfg) {
  path <- file.path(cfg$data_dir, "allstates_monthly_2020_2021.csv")
  raw <- read_csv(path, show_col_types = FALSE)
  
  # This file has huge duplication by state-month; collapse to state-month.
  df <- collapse_unit_month(
    raw,
    unit_col = state,
    month_col = month,
    sum_cols = intersect(c("filings_2020", "filings_avg"), names(raw))
  ) %>%
    mutate(
      unit_id = state_key(unit_id)
    )
  
  df <- pick_outcome(df, cfg)
  
  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

prep_panel_sites_ets <- function(cfg) {
  path <- file.path(cfg$data_dir, "all_sites_monthly_2020_2021.csv")
  raw <- read_csv(path, show_col_types = FALSE)
  
  df <- collapse_unit_month(
    raw,
    unit_col = city,
    month_col = month,
    sum_cols = intersect(c("filings_2020", "filings_avg", "filings_avg_prepandemic_baseline"), names(raw))
  ) %>%
    mutate(
      # extract state abb from "City, ST"
      state_abb = str_extract(unit_id, "(?<=,\\s)[A-Z]{2}$"),
      unit_id = str_trim(unit_id)
    )
  
  df <- pick_outcome(df, cfg)
  
  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

load_panel <- function(cfg) {
  switch(
    cfg$panel_choice,
    "counties" = prep_panel_counties(cfg),
    "states_from_counties" = prep_panel_states_from_counties(cfg),
    "states_ets" = prep_panel_states_ets(cfg),
    "sites_ets" = prep_panel_sites_ets(cfg),
    stop("cfg$panel_choice must be one of: counties, states_from_counties, states_ets, sites_ets")
  )
}

################################################################################
# 4) Treatment schedule from sports_gambling_legalization_dates.csv
################################################################################

read_sports_schedule <- function(cfg) {
  path <- file.path(cfg$data_dir, "sports_gambling_legalization_dates.csv")
  sch <- read_csv(path, show_col_types = FALSE)
  
  if (!(cfg$treat_date_col %in% names(sch))) {
    stop(glue(
      "cfg$treat_date_col='{cfg$treat_date_col}' not found.\n",
      "Available columns: {paste(names(sch), collapse=', ')}\n",
      "Use e.g. online_start_date / retail_start_date / first_start_date (recommended)."
    ))
  }
  
  sch %>%
    mutate(
      state_name_lc = str_to_lower(str_trim(state)),
      state_key = state_key(state),
      g = parse_month_to_date(.data[[cfg$treat_date_col]]),
      ever_treated = !is.na(g)
    ) %>%
    left_join(
      state_fips_xwalk %>%
        mutate(state_name_lc = str_to_lower(state_name)) %>%
        select(state_abb, state_name_lc),
      by = "state_name_lc"
    ) %>%
    select(state, state_key, state_abb, g, ever_treated, everything())
}


make_treat_schedule <- function(panel_df, cfg) {
  sch <- read_sports_schedule(cfg)
  
  if (!(cfg$treat_date_col %in% names(sch))) {
    stop(glue("cfg$treat_date_col='{cfg$treat_date_col}' not found in sports schedule. Available: {paste(names(sch), collapse=', ')}"))
  }
  
  # unit_id depends on panel choice
  if (cfg$panel_choice %in% c("counties")) {
    sch <- read_sports_schedule(cfg)

    # sch has: state_abb, g (monthly Date), ever_treated
    # panel_df has: unit_id (county), state_abb
    out <- panel_df %>%
      distinct(unit_id, state_abb) %>%
      left_join(
        sch %>% select(state_abb, g, ever_treated),
        by = "state_abb"
      ) %>%
      mutate(
        ever_treated = replace_na(ever_treated, FALSE)
      ) %>%
      select(unit_id, g, ever_treated)

    return(out)
  }

  if (cfg$panel_choice %in% c("states_from_counties")) {
    # For states aggregated from counties, unit_id is numeric state_fips
    # Join sports schedule to panel via state_abb
    sch2 <- sch %>%
      left_join(state_fips_xwalk %>% select(state_fips, state_abb), by = "state_abb") %>%
      select(state_fips, g = .data[[cfg$treat_date_col]]) %>%
      mutate(
        ever_treated = !is.na(g),
        state_fips = as.numeric(state_fips)
      )

    out <- panel_df %>%
      distinct(unit_id, state_abb) %>%
      left_join(sch2, by = c("unit_id" = "state_fips")) %>%
      mutate(ever_treated = replace_na(ever_treated, FALSE)) %>%
      select(unit_id, g, ever_treated)

    return(out)
  }
  
  
  if (cfg$panel_choice %in% c("states_ets")) {
    # ETS unit_id values look like: connecticut, rhode_island, newmexico
    # So join on state_key (canonicalized)
    sch2 <- sch %>%
      transmute(unit_id = state_key, g = g)
    
    out <- panel_df %>%
      distinct(unit_id) %>%
      left_join(sch2, by = "unit_id") %>%
      mutate(ever_treated = !is.na(g))
    
    return(out)
  
  }

  if (cfg$panel_choice %in% c("sites_ets")) {
    # unit_id is "City, ST"; panel_df has state_abb extracted
    sch2 <- sch %>%
      left_join(state_fips_xwalk %>% distinct(state_abb, state_name = str_to_lower(state_name)), by = "state_name") %>%
      transmute(state_abb, g = .data[[cfg$treat_date_col]])
    
    out <- panel_df %>%
      distinct(unit_id, state_abb) %>%
      left_join(sch2, by = "state_abb") %>%
      mutate(ever_treated = !is.na(g)) %>%
      select(unit_id, g, ever_treated)
    
    return(out)
  }
  
  stop("Unhandled panel_choice in make_treat_schedule().")
}

standardize_treat_schedule <- function(treat_schedule, panel_df) {
  # Preserve unit_id type from panel_df (must be numeric for did::att_gt)
  ts <- treat_schedule %>%
    mutate(
      g_id = if_else(is.na(g), 0L, as.integer(g_to_time_id(g))),
      ever_treated = if ("ever_treated" %in% names(.)) as.logical(ever_treated) else (g_id > 0L)
    ) %>%
    select(unit_id, g_id, ever_treated)

  panel_df %>%
    distinct(unit_id) %>%
    left_join(ts, by = "unit_id") %>%
    mutate(
      g_id = replace_na(g_id, 0L),
      ever_treated = replace_na(ever_treated, FALSE)
    )
}

################################################################################
# 5) A: Untreated baseline samples (A1 and A2)
################################################################################

build_untreated_sample <- function(panel_df, treat_schedule_std) {
  # Build untreated sample following Black et al.:
  # - Never-treated units: all periods (measure baseline variation)
  # - Treated units: pre-treatment periods only (also contribute to baseline variation)

  # Pre-balance panel: keep only units with near-complete time coverage
  # This prevents singular matrix errors in CS estimator with imbalanced panels
  time_coverage <- panel_df %>%
    group_by(unit_id) %>%
    summarise(n_periods = n(), .groups = "drop")

  max_periods <- max(time_coverage$n_periods)
  # Keep units with at least 80% of periods (adjust threshold as needed)
  min_periods_threshold <- ceiling(0.8 * max_periods)

  balanced_units <- time_coverage %>%
    filter(n_periods >= min_periods_threshold) %>%
    pull(unit_id)

  # Untreated-by-construction:
  # - never-treated: keep all months
  # - treated: keep months strictly before real g
  panel_df %>%
    filter(unit_id %in% balanced_units) %>%
    left_join(treat_schedule_std %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
    filter((!ever_treated) | (ever_treated & time_id < g_id))
}

residualize_outcome <- function(df_untreated) {
  # Residualize with the planned FE structure (unit + time FE).
  # You can add covariates here if your final spec includes them.
  m <- fixest::feols(outcome ~ 1 | unit_id + time_id, data = df_untreated)

  # Handle singletons: fixest removes them, so residuals are shorter than df
  # Get indices of observations that were kept (not removed as singletons)
  obs_removed <- m$obs_selection$obsRemoved

  # If obs_removed is NULL or all FALSE (no singletons), use simple approach
  if (is.null(obs_removed) || all(!obs_removed)) {
    outcome_mean <- mean(df_untreated$outcome, na.rm = TRUE)
    return(
      df_untreated %>%
        mutate(outcome = resid(m) + outcome_mean)
    )
  }

  # Otherwise, handle singletons carefully
  outcome_mean <- mean(df_untreated$outcome, na.rm = TRUE)

  # Create a vector of residualized outcomes
  outcome_new <- df_untreated$outcome  # Start with original
  outcome_new[!obs_removed] <- resid(m) + outcome_mean  # Replace non-singletons with residuals

  df_untreated %>%
    mutate(outcome = outcome_new)
}

################################################################################
# 6) B: Mimic adoption pattern (permute g among treated units) + shift into untreated
################################################################################

draw_placebo_schedule <- function(treat_schedule_std,
                                  cfg,
                                  baseline_df,
                                  n_switchers = NULL,
                                  unit_state_map = NULL) {
  if ("state_abb" %in% names(baseline_df)) {
    if (is.null(unit_state_map)) {
      unit_state_map <- baseline_df %>% distinct(unit_id, state_abb)
    } else {
      unit_state_map <- unit_state_map %>%
        distinct(unit_id, state_abb) %>%
        filter(!is.na(state_abb))
    }
    
    unit_time_range <- baseline_df %>%
      group_by(unit_id, state_abb) %>%
      summarise(
        min_time_id = min(time_id),
        max_time_id = max(time_id),
        .groups = "drop"
      )
    
    baseline_states <- sort(unique(unit_time_range$state_abb))
    if (length(baseline_states) < 2) stop("Need at least 2 baseline states for placebo assignment.")
    
    state_ts_full <- treat_schedule_std %>%
      left_join(unit_state_map, by = "unit_id") %>%
      filter(!is.na(state_abb)) %>%
      group_by(state_abb) %>%
      summarise(
        g_id = suppressWarnings(max(g_id, na.rm = TRUE)),
        .groups = "drop"
      ) %>%
      mutate(
        g_id = if_else(is.infinite(g_id) | is.na(g_id), 0L, as.integer(g_id)),
        ever_treated = (g_id > 0L)
      )
    
    treatment_dates <- state_ts_full %>%
      filter(ever_treated, g_id > 0L) %>%
      pull(g_id) %>%
      unique() %>%
      sort()
    
    if (length(treatment_dates) == 0) stop("No treatment dates in original schedule to mimic.")
    
    shift_months <- max(cfg$post_len + 1L, 1L)
    min_t <- min(baseline_df$time_id, na.rm = TRUE)
    max_t <- max(baseline_df$time_id, na.rm = TRUE)
    
    placebo_dates <- treatment_dates - shift_months
    placebo_dates <- placebo_dates[
      placebo_dates >= (min_t + cfg$pre_len) &
        placebo_dates <= (max_t - cfg$post_len)
    ]
    
    if (length(placebo_dates) == 0) stop("No valid placebo dates after shifting into baseline window.")
    
    if (is.null(n_switchers)) {
      treated_share <- mean(state_ts_full$ever_treated, na.rm = TRUE)
      n_to_treat <- round(length(baseline_states) * treated_share)
    } else {
      n_to_treat <- as.integer(n_switchers)
    }
    
    n_to_treat <- max(1L, min(n_to_treat, length(baseline_states) - 1L))
    
    treated_states_sample <- sample(baseline_states, size = n_to_treat, replace = FALSE)
    placebo_dates_sample  <- sample(placebo_dates, size = n_to_treat, replace = TRUE)
    
    placebo_state <- tibble(
      state_abb = c(treated_states_sample, setdiff(baseline_states, treated_states_sample)),
      g_placebo = c(placebo_dates_sample, rep(0L, length(baseline_states) - n_to_treat))
    )
    
    placebo_unit <- unit_time_range %>%
      left_join(placebo_state, by = "state_abb") %>%
      mutate(
        g_placebo = replace_na(g_placebo, 0L),
        g_placebo = if_else(
          g_placebo > 0L &
            (g_placebo < min_time_id + cfg$pre_len | g_placebo > max_time_id - cfg$post_len),
          0L,
          g_placebo
        )
      ) %>%
      select(unit_id, g_placebo)
    
    return(placebo_unit)
  }
  
  treated <- treat_schedule_std %>% filter(ever_treated, g_id > 0L)
  never   <- treat_schedule_std %>%
    filter(!ever_treated | g_id == 0L) %>%
    transmute(unit_id, g_placebo = 0L)
  
  if (nrow(treated) == 0) stop("No treated units after standardization.")
  
  shift_months <- max(cfg$post_len + 1L, 1L)
  min_t <- min(baseline_df$time_id, na.rm = TRUE)
  
  treated2 <- treated %>%
    mutate(g_shift = g_id - shift_months) %>%
    filter(g_shift >= (min_t + cfg$pre_len)) %>%
    mutate(g_placebo = sample(g_shift, size = n(), replace = FALSE)) %>%
    select(unit_id, g_placebo)
  
  bind_rows(treated2, never)
}


################################################################################
# 7) Impose effects
################################################################################

impose_effect <- function(df, placebo_schedule, effect_size, cfg) {
  df2 <- df %>%
    left_join(placebo_schedule, by = "unit_id") %>%
    mutate(
      g_placebo = replace_na(g_placebo, 0L),
      D = as.integer(g_placebo > 0L & time_id >= g_placebo),
      event_time = if_else(g_placebo > 0L, time_id - g_placebo, NA_integer_)
    )
  
  mult <- case_when(
    cfg$effect_shape == "step" ~ as.numeric(df2$D),
    cfg$effect_shape == "ramp" ~ if_else(df2$D == 1L,
                                         pmin(1, pmax(0, df2$event_time / max(cfg$post_len, 1L))),
                                         0),
    cfg$effect_shape == "delayed" ~ if_else(df2$D == 1L & df2$event_time >= cfg$delay_h, 1, 0),
    TRUE ~ as.numeric(df2$D)
  )
  
  df2 %>%
    mutate(outcome_sim = outcome + effect_size * mult)
}

################################################################################
# 8) C + D: Run CS estimator and extract the p-value for the reported estimand
################################################################################
as_est_list <- function(x) {
  # Always return list(p, est, se)
  if (is.null(x)) return(list(p = NA_real_, est = NA_real_, se = NA_real_))
  
  # If someone returns a named numeric vector c(p=..., est=..., se=...)
  if (is.atomic(x) && !is.null(names(x))) {
    x <- as.list(x)
  }
  
  if (is.list(x)) {
    return(list(
      p   = x$p   %||% NA_real_,
      est = x$est %||% NA_real_,
      se  = x$se  %||% NA_real_
    ))
  }
  
  # Anything else: treat as failure
  list(p = NA_real_, est = NA_real_, se = NA_real_)
}

att_gt_safe <- function(df_in, cfg, cluster_var) {
  # Convert to data.frame to avoid tibble/data.table conversion issues in did package
  df_in <- as.data.frame(df_in)

  args <- list(
    yname = "outcome_sim",
    tname = "time_id_seq",  # Use remapped sequential time variable
    idname = "unit_id",
    gname = "gname",
    data = df_in,
    panel = TRUE,
    control_group = "notyettreated",
    bstrap = cfg$did_bstrap,
    biters = cfg$did_biters,
    cband = cfg$did_cband,
    clustervars = cluster_var,
    est_method = "ipw"  # Use IPW instead of DR to avoid fastglm segfault
  )

  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_in)) {
    args$weightsname <- cfg$weights_var
  }

  # Some did versions expose allow_unbalanced_panel; add it if available
  if ("allow_unbalanced_panel" %in% names(formals(did::att_gt))) {
    args$allow_unbalanced_panel <- TRUE
  }
  # If did exposes a cores/ncores argument, force it to 1 to avoid nested parallelism
  fmls <- names(formals(did::att_gt))
  if ("cores"  %in% fmls) args$cores  <- 1L
  if ("ncores" %in% fmls) args$ncores <- 1L
  if ("parallel" %in% fmls) args$parallel <- FALSE

  # Call att_gt - errors will be caught by tryCatch in run_estimator_and_extract_p
  do.call(did::att_gt, args)
}
normalize_est <- function(x) {
  # Always return list(p, est, se)
  if (is.null(x)) return(list(p = NA_real_, est = NA_real_, se = NA_real_))
  
  # Named numeric vector -> list
  if (is.atomic(x) && !is.null(names(x))) {
    x <- as.list(x)
  }
  
  if (is.list(x)) {
    return(list(
      p   = if (!is.null(x$p))   as.numeric(x$p)   else NA_real_,
      est = if (!is.null(x$est)) as.numeric(x$est) else NA_real_,
      se  = if (!is.null(x$se))  as.numeric(x$se)  else NA_real_
    ))
  }
  
  # Anything else (plain numeric, character, etc.)
  list(p = NA_real_, est = NA_real_, se = NA_real_)
}

run_estimator_and_extract_p <- function(df_sim, cfg, cluster_var) {
  # Default output
  out <- list(p = NA_real_, est = NA_real_, se = NA_real_)

  # CRITICAL FIX: did package can't handle large time_id values (e.g., 24254 = 2021*12+2)
  # Remap time_id to sequential integers (1, 2, 3, ...) to avoid Inf warnings
  time_mapping <- df_sim %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  # Remap g_placebo values to sequential scale
  g_mapping <- df_sim %>%
    filter(!is.na(g_placebo) & g_placebo > 0L) %>%
    distinct(g_placebo) %>%
    left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
    transmute(g_placebo, g_placebo_seq = time_id_seq)

  df_in <- df_sim %>%
    left_join(time_mapping, by = "time_id") %>%
    left_join(g_mapping, by = "g_placebo") %>%
    mutate(
      # Create gname: 0 for never-treated, sequential time_id for treated
      gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0L, coalesce(g_placebo_seq, 0L))
    )

  if (all(df_in$gname == 0L)) return(out)
  
  tryCatch({
    att <- att_gt_safe(df_in, cfg, cluster_var = cluster_var)

    if (cfg$estimand == "overall_att") {
      # Try aggte first, fall back to manual aggregation if it fails
      agg_result <- tryCatch({
        agg <- did::aggte(att, type = "simple")
        list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
      }, error = function(e) {
        # Manual aggregation when aggte fails due to data.table incompatibility
        # Compute simple mean of all group-time ATTs
        est_manual <- mean(att$att, na.rm = TRUE)

        # Compute SE manually using influence functions if available
        if (!is.null(att$inffunc) && length(dim(att$inffunc)) == 2 && nrow(att$inffunc) > 0) {
          # The influence function for simple aggregation is the row mean
          # inffunc might be a sparse matrix (dgCMatrix), convert to dense if needed
          if (inherits(att$inffunc, "Matrix")) {
            inffunc_dense <- as.matrix(att$inffunc)
          } else {
            inffunc_dense <- att$inffunc
          }
          inf_simple <- rowMeans(inffunc_dense, na.rm = TRUE)
          se_manual <- sqrt(mean(inf_simple^2, na.rm = TRUE))
        } else {
          se_manual <- NA_real_
        }

        list(success = FALSE, att = est_manual, se = se_manual)
      })

      est <- agg_result$att
      se  <- agg_result$se
      p   <- if (is.finite(est) && is.finite(se) && se > 0) 2 * pnorm(-abs(est / se)) else NA_real_
      out <- list(p = p, est = est, se = se)
      return(out)
    }

    # event-time
    agg_result <- tryCatch({
      agg <- did::aggte(att, type = "dynamic")
      list(success = TRUE, agg = agg)
    }, error = function(e) {
      list(success = FALSE)
    })

    if (!agg_result$success) return(out)

    agg <- agg_result$agg
    idx <- which(agg$egt == cfg$target_h)
    if (length(idx) != 1) return(out)

    est <- agg$att.egt[idx]
    se  <- agg$se.egt[idx]
    p   <- if (is.finite(est) && is.finite(se) && se > 0) 2 * pnorm(-abs(est / se)) else NA_real_
    list(p = p, est = est, se = se)

  }, error = function(e) {
    out
  })
}


################################################################################
# 9) Simulation wrapper
################################################################################

compute_mde <- function(power_df, power_target = 0.80) {
  df <- power_df %>% filter(effect_size > 0) %>% arrange(effect_size)
  hit <- which(df$power >= power_target)
  if (length(hit) == 0) return(NA_real_)
  j <- hit[1]
  if (j == 1) return(df$effect_size[1])
  
  x0 <- df$effect_size[j - 1]; y0 <- df$power[j - 1]
  x1 <- df$effect_size[j];     y1 <- df$power[j]
  if (is.na(y0) || is.na(y1) || y1 == y0) return(x1)
  
  x0 + (power_target - y0) * (x1 - x0) / (y1 - y0)
}


simulate_power <- function(panel_df, treat_schedule_std, option = c("A1", "A2"), cfg, cluster_var) {
  option <- match.arg(option)
  
  # ---------------------------------------------------------------------------
  # Build untreated baseline (unbalanced panels are fine)
  # ---------------------------------------------------------------------------
  baseline <- build_untreated_sample(panel_df, treat_schedule_std)
  if (nrow(baseline) == 0) {
    stop("Untreated baseline is empty. Usually means no pre-treatment months for treated units.")
  }
  
  if (option == "A2") {
    baseline <- residualize_outcome(baseline)
  }
  
  # Keep only what we need to reduce memory / serialization overhead
  keep <- c("unit_id", "time_id", "month_date", "outcome", "state_abb")
  keep <- unique(c(keep, cluster_var))
  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(baseline)) {
    keep <- unique(c(keep, cfg$weights_var))
  }
  keep <- keep[keep %in% names(baseline)]
  baseline <- baseline %>% dplyr::select(dplyr::all_of(keep))
  
  # Metadata
  n_units <- dplyr::n_distinct(baseline$unit_id)
  n_clusters <- if (cluster_var %in% names(baseline)) dplyr::n_distinct(baseline[[cluster_var]]) else NA_integer_
  min_date <- min(baseline$month_date, na.rm = TRUE)
  max_date <- max(baseline$month_date, na.rm = TRUE)
  
  if (!is.na(n_clusters) && n_clusters < 30) {
    message(glue::glue("WARNING: Only {n_clusters} clusters (cluster_var={cluster_var}). Small-cluster inference may matter."))
  }
  
  message(sprintf("baseline size: %s", format(object.size(baseline), units = "auto")))
  flush.console()
  
  # ---------------------------------------------------------------------------
  # Helper: if doing event-time inference, require enough pre/post window
  # (works with unbalanced panels; it just drops placebo-treated units that
  # don't have enough coverage around their placebo g)
  # ---------------------------------------------------------------------------
  enforce_windows <- function(df) {
    ok <- df %>%
      dplyr::filter(g_placebo > 0L) %>%
      dplyr::group_by(unit_id, g_placebo) %>%
      dplyr::summarise(
        min_t = min(time_id),
        max_t = max(time_id),
        .groups = "drop"
      ) %>%
      dplyr::mutate(ok = (min_t <= (g_placebo - cfg$pre_len)) & (max_t >= (g_placebo + cfg$post_len)))
    
    ok_units <- ok %>% dplyr::filter(ok) %>% dplyr::pull(unit_id)
    df %>% dplyr::filter(g_placebo == 0L | unit_id %in% ok_units)
  }
  
  # ---------------------------------------------------------------------------
  # One simulation draw (safe: never throws)
  # ---------------------------------------------------------------------------
  one_draw <- function(effect_size, s) {
    tryCatch({
      placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
      
      df_sim <- impose_effect(baseline, placebo, effect_size, cfg)
      
      if (identical(cfg$estimand, "event_time")) {
        df_sim <- enforce_windows(df_sim)
      }
      
      # Minimal feasibility checks
      n_treated_units <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo > 0L])
      n_never_units   <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo == 0L])
      n_treated_obs   <- sum(df_sim$g_placebo > 0L, na.rm = TRUE)
      
      if (n_treated_units < 2) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "too_few_treated_units",
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      if (n_never_units < 2) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "too_few_never_units",
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      if (n_treated_obs == 0) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "no_treated_obs",
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      
      # Keep only what did needs (reduces allocations)
      keep2 <- c("unit_id", "time_id", "outcome_sim", "g_placebo", cluster_var)
      if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_sim)) keep2 <- c(keep2, cfg$weights_var)
      keep2 <- unique(keep2)
      keep2 <- keep2[keep2 %in% names(df_sim)]
      df_sim <- df_sim %>% dplyr::select(dplyr::all_of(keep2))
      
      # Silence the repeated "You have an unbalanced panel. Proceeding as such." chatter
      est_raw <- suppressMessages(run_estimator_and_extract_p(df_sim, cfg, cluster_var = cluster_var))
      
      tibble::tibble(
        sim = s,
        p   = as.numeric(est_raw$p),
        est = as.numeric(est_raw$est),
        se  = as.numeric(est_raw$se),
        fail = est_raw$fail %||% NA_character_,
        n_treated_units = n_treated_units,
        n_never_units   = n_never_units,
        n_treated_obs   = n_treated_obs
      )
    }, error = function(e) {
      tibble::tibble(
        sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
        fail = paste0("one_draw_error: ", conditionMessage(e)),
        n_treated_units = NA_integer_, n_never_units = NA_integer_, n_treated_obs = NA_integer_
      )
    })
  }
  
  # ---------------------------------------------------------------------------
  # Run over effect sizes (with timestamps + progress + partial CSV checkpoints)
  # ---------------------------------------------------------------------------
  res_list <- vector("list", length(cfg$effect_grid))
  
  for (k in seq_along(cfg$effect_grid)) {
    eff <- cfg$effect_grid[k]
    
    t0 <- Sys.time()
    message(glue::glue("[{t0}] {option}: effect {k}/{length(cfg$effect_grid)} (eff={eff}) starting..."))
    flush.console()
    
    if (isTRUE(cfg$use_parallel)) {
      draws <- progressr::with_progress({
        p <- progressr::progressor(steps = cfg$n_sims)
        furrr::future_map_dfr(
          1:cfg$n_sims,
          ~ { p(); one_draw(eff, .x) },
          .options = furrr::furrr_options(seed = TRUE)
        )
      })
    } else {
      pb <- utils::txtProgressBar(min = 0, max = cfg$n_sims, style = 3)
      draws <- purrr::map_dfr(
        1:cfg$n_sims,
        function(s) { utils::setTxtProgressBar(pb, s); one_draw(eff, s) }
      )
      close(pb)
    }
    
    t1 <- Sys.time()
    message(glue::glue(
      "[{t1}] {option}: effect {k}/{length(cfg$effect_grid)} done in {round(as.numeric(difftime(t1, t0, units='mins')), 2)} min"
    ))
    flush.console()
    
    print(draws %>% dplyr::count(fail, sort = TRUE))
    print(mean(is.na(draws$p)))
    
    power <- mean(draws$p <= cfg$alpha, na.rm = TRUE)
    
    sig <- draws %>% dplyr::filter(!is.na(p), p <= cfg$alpha)
    sign_error <- if (eff == 0 || nrow(sig) == 0) NA_real_ else mean(sign(sig$est) != sign(eff), na.rm = TRUE)
    severe_mag <- if (eff == 0 || nrow(sig) == 0) NA_real_ else mean(abs(sig$est) > 2 * abs(eff), na.rm = TRUE)
    exaggeration_ratio <- if (eff == 0 || nrow(sig) == 0) NA_real_ else mean(abs(sig$est) / abs(eff), na.rm = TRUE)
    
    res_list[[k]] <- tibble::tibble(
      option = option,
      panel_choice = cfg$panel_choice,
      estimand = cfg$estimand,
      target_h = dplyr::if_else(cfg$estimand == "event_time", cfg$target_h, NA_integer_),
      effect_size = eff,
      power = power,
      mean_est = mean(draws$est, na.rm = TRUE),
      mean_se = mean(draws$se, na.rm = TRUE),
      sign_error_rate_sig = sign_error,
      severe_mag_error_rate_sig = severe_mag,
      mean_exaggeration_ratio_sig = exaggeration_ratio,
      n_sims = cfg$n_sims,
      n_units = n_units,
      n_clusters = n_clusters,
      start_date = min_date,
      end_date = max_date
    )
    
    # Checkpoint file you can tail -f while job runs
    readr::write_csv(
      dplyr::bind_rows(res_list[1:k]),
      file.path(cfg$data_dir, glue::glue("power_{option}_partial.csv"))
    )
  }
  
  dplyr::bind_rows(res_list)
}

make_baseline_once <- function(panel_df, treat_schedule_std, option = c("A1", "A2"), cfg, cluster_var) {
  option <- match.arg(option)
  
  baseline <- build_untreated_sample(panel_df, treat_schedule_std)
  if (nrow(baseline) == 0) stop("Untreated baseline is empty.")
  
  if (option == "A2") {
    baseline <- residualize_outcome(baseline)
  }
  
  keep <- c("unit_id", "time_id", "month_date", "outcome", "state_abb")
  keep <- unique(c(keep, cluster_var))
  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(baseline)) {
    keep <- unique(c(keep, cfg$weights_var))
  }
  keep <- keep[keep %in% names(baseline)]
  
  baseline %>% select(all_of(keep))
}

subset_baseline_to_n_clusters <- function(baseline, cluster_var, n_clusters, seed = NULL) {
  if (!(cluster_var %in% names(baseline))) {
    stop(glue::glue("cluster_var='{cluster_var}' not in baseline."))
  }
  
  clusters <- sort(unique(baseline[[cluster_var]]))
  if (n_clusters > length(clusters)) {
    stop(glue::glue("Requested {n_clusters} clusters but baseline only has {length(clusters)}."))
  }
  
  if (!is.null(seed)) set.seed(seed)
  chosen <- sample(clusters, size = n_clusters, replace = FALSE)
  
  baseline %>% filter(.data[[cluster_var]] %in% chosen)
}

simulate_power_from_baseline <- function(baseline,
                                         treat_schedule_std,
                                         option = c("A1", "A2"),
                                         cfg,
                                         cluster_var,
                                         n_switchers = NULL,
                                         unit_state_map = NULL,
                                         scenario_seed = 1L) {
  option <- match.arg(option)
  set.seed(scenario_seed)
  
  n_units    <- dplyr::n_distinct(baseline$unit_id)
  n_clusters <- if (cluster_var %in% names(baseline)) dplyr::n_distinct(baseline[[cluster_var]]) else NA_integer_
  min_date <- min(baseline$month_date, na.rm = TRUE)
  max_date <- max(baseline$month_date, na.rm = TRUE)
  
  enforce_windows <- function(df) {
    ok <- df %>%
      dplyr::filter(g_placebo > 0L) %>%
      dplyr::group_by(unit_id, g_placebo) %>%
      dplyr::summarise(
        min_t = min(time_id),
        max_t = max(time_id),
        .groups = "drop"
      ) %>%
      dplyr::mutate(ok = (min_t <= (g_placebo - cfg$pre_len)) & (max_t >= (g_placebo + cfg$post_len)))
    
    ok_units <- ok %>% dplyr::filter(ok) %>% dplyr::pull(unit_id)
    df %>% dplyr::filter(g_placebo == 0L | unit_id %in% ok_units)
  }
  
  one_draw <- function(effect_size, s) {
    tryCatch({
      placebo <- draw_placebo_schedule(
        treat_schedule_std = treat_schedule_std,
        cfg = cfg,
        baseline_df = baseline,
        n_switchers = n_switchers,
        unit_state_map = unit_state_map
      )
      
      df_sim <- impose_effect(baseline, placebo, effect_size, cfg)
      
      if (identical(cfg$estimand, "event_time")) {
        df_sim <- enforce_windows(df_sim)
      }
      
      treated_clusters <- if (cluster_var %in% names(df_sim)) {
        dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo > 0L])
      } else {
        NA_integer_
      }
      
      never_clusters <- if (cluster_var %in% names(df_sim)) {
        dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo == 0L])
      } else {
        NA_integer_
      }
      
      n_treated_units <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo > 0L])
      n_never_units   <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo == 0L])
      n_treated_obs   <- sum(df_sim$g_placebo > 0L, na.rm = TRUE)
      
      if (!is.na(treated_clusters) && treated_clusters < 2) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "too_few_treated_clusters",
          treated_clusters = treated_clusters, never_clusters = never_clusters,
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      if (n_treated_units < 2) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "too_few_treated_units",
          treated_clusters = treated_clusters, never_clusters = never_clusters,
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      if (n_never_units < 2) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "too_few_never_units",
          treated_clusters = treated_clusters, never_clusters = never_clusters,
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      if (n_treated_obs == 0) {
        return(tibble::tibble(
          sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
          fail = "no_treated_obs",
          treated_clusters = treated_clusters, never_clusters = never_clusters,
          n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs
        ))
      }
      
      keep2 <- c("unit_id", "time_id", "outcome_sim", "g_placebo", cluster_var)
      if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_sim)) {
        keep2 <- c(keep2, cfg$weights_var)
      }
      keep2 <- unique(keep2)
      keep2 <- keep2[keep2 %in% names(df_sim)]
      df_sim <- df_sim %>% dplyr::select(dplyr::all_of(keep2))
      
      est_raw <- suppressMessages(run_estimator_and_extract_p(df_sim, cfg, cluster_var = cluster_var))
      
      tibble::tibble(
        sim = s,
        p   = as.numeric(est_raw$p),
        est = as.numeric(est_raw$est),
        se  = as.numeric(est_raw$se),
        fail = est_raw$fail %||% NA_character_,
        treated_clusters = treated_clusters,
        never_clusters = never_clusters,
        n_treated_units = n_treated_units,
        n_never_units = n_never_units,
        n_treated_obs = n_treated_obs
      )
    }, error = function(e) {
      tibble::tibble(
        sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
        fail = paste0("one_draw_error: ", conditionMessage(e)),
        treated_clusters = NA_integer_, never_clusters = NA_integer_,
        n_treated_units = NA_integer_, n_never_units = NA_integer_, n_treated_obs = NA_integer_
      )
    })
  }
  
  res_list <- vector("list", length(cfg$effect_grid))
  
  for (k in seq_along(cfg$effect_grid)) {
    eff <- cfg$effect_grid[k]
    
    if (isTRUE(cfg$use_parallel)) {
      draws <- progressr::with_progress({
        p <- progressr::progressor(steps = cfg$n_sims)
        furrr::future_map_dfr(
          1:cfg$n_sims,
          ~ { p(); one_draw(eff, .x) },
          .options = furrr::furrr_options(seed = TRUE)
        )
      })
    } else {
      pb <- utils::txtProgressBar(min = 0, max = cfg$n_sims, style = 3)
      draws <- purrr::map_dfr(
        1:cfg$n_sims,
        \(s) { utils::setTxtProgressBar(pb, s); one_draw(eff, s) }
      )
      close(pb)
    }
    
    power <- mean(draws$p <= cfg$alpha, na.rm = TRUE)
    
    res_list[[k]] <- tibble::tibble(
      option = option,
      panel_choice = cfg$panel_choice,
      estimand = cfg$estimand,
      target_h = dplyr::if_else(cfg$estimand == "event_time", cfg$target_h, NA_integer_),
      effect_size = eff,
      power = power,
      mean_est = mean(draws$est, na.rm = TRUE),
      mean_se  = mean(draws$se,  na.rm = TRUE),
      n_sims = cfg$n_sims,
      n_units = n_units,
      n_clusters = n_clusters,
      n_switchers = n_switchers %||% NA_integer_,
      start_date = min_date,
      end_date   = max_date
    )
  }
  
  dplyr::bind_rows(res_list)
}

simulate_power_grid_states_switchers <- function(panel_df,
                                                 treat_schedule_std,
                                                 cfg,
                                                 cluster_var,
                                                 n_states_grid,
                                                 n_switchers_grid,
                                                 option = c("A1", "A2"),
                                                 seed_base = 1000L) {
  option <- match.arg(option)
  
  baseline_full <- make_baseline_once(panel_df, treat_schedule_std, option = option, cfg = cfg, cluster_var = cluster_var)
  
  unit_state_map <- if ("state_abb" %in% names(panel_df)) {
    panel_df %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))
  } else {
    NULL
  }
  
  grid <- tidyr::expand_grid(
    n_states = as.integer(n_states_grid),
    n_switchers = as.integer(n_switchers_grid)
  ) %>%
    filter(n_states >= (n_switchers + 1L))
  
  purrr::pmap_dfr(grid, function(n_states, n_switchers) {
    scenario_seed <- as.integer(seed_base + 10000L * n_states + n_switchers)
    
    baseline_s <- subset_baseline_to_n_clusters(
      baseline_full,
      cluster_var = cluster_var,
      n_clusters = n_states,
      seed = scenario_seed
    )
    
    simulate_power_from_baseline(
      baseline = baseline_s,
      treat_schedule_std = treat_schedule_std,
      option = option,
      cfg = cfg,
      cluster_var = cluster_var,
      n_switchers = n_switchers,
      unit_state_map = unit_state_map,
      scenario_seed = scenario_seed
    ) %>%
      mutate(n_states = n_states, n_switchers = n_switchers)
  })
}
run_power_simulation <- function(cfg) {
  # Parallel plan (works locally and on Della; respects SLURM_CPUS_PER_TASK if set)
  if (cfg$use_parallel) {
    # multisession is safer than multicore on some HPC setups; multicore is faster on Linux.
    plan(multisession, workers = cfg$workers)
    message(glue("Parallel ON: workers = {cfg$workers}"))
  } else {
    plan(sequential)
    message("Parallel OFF")
  }
  
  panel_df <- load_panel(cfg)
  message(glue("Loaded panel: {cfg$panel_choice}"))
  message(glue("Outcome used: {attr(panel_df, 'outcome_var')}"))
  message(glue("Units: {n_distinct(panel_df$unit_id)} | Months: {n_distinct(panel_df$time_id)}"))
  
  # cluster var
  cluster_var <- case_when(
    cfg$cluster_level == "unit" ~ "unit_id",
    cfg$cluster_level == "state" ~ if ("state_abb" %in% names(panel_df)) "state_abb" else "unit_id",
    TRUE ~ "unit_id"
  )
  
  # treat schedule
  treat_schedule <- make_treat_schedule(panel_df, cfg)
  treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
  
  ts_sum <- treat_schedule_std %>%
    summarise(
      n_units = n(),
      n_treated = sum(ever_treated & g_id > 0),
      share_treated = mean(ever_treated & g_id > 0),
      min_g = min(if_else(g_id > 0, g_id, NA_integer_), na.rm = TRUE),
      max_g = max(if_else(g_id > 0, g_id, NA_integer_), na.rm = TRUE)
    )
  print(ts_sum)
  
  if (isTRUE(cfg$run_state_switcher_grid)) {
    power_A1_grid <- simulate_power_grid_states_switchers(
      panel_df, treat_schedule_std, cfg, cluster_var,
      n_states_grid = cfg$n_states_grid,
      n_switchers_grid = cfg$n_switchers_grid,
      option = "A1",
      seed_base = 123
    )
    power_A2_grid <- simulate_power_grid_states_switchers(
      panel_df, treat_schedule_std, cfg, cluster_var,
      n_states_grid = cfg$n_states_grid,
      n_switchers_grid = cfg$n_switchers_grid,
      option = "A2",
      seed_base = 456
    )
    
    power_grid_all <- bind_rows(power_A1_grid, power_A2_grid) %>%
      arrange(option, n_states, n_switchers, effect_size)
    
    write_csv(power_grid_all, file.path(cfg$data_dir, "power_grid_states_switchers.csv"))
    
    mde_surface <- power_grid_all %>%
      group_by(option, estimand, target_h, n_states, n_switchers) %>%
      summarise(mde_80 = compute_mde(cur_data_all(), power_target = cfg$power_target), .groups = "drop")
    
    write_csv(mde_surface, file.path(cfg$data_dir, "mde_surface_states_switchers.csv"))
    
    message("\nSaved outputs:")
    message(glue("  - {file.path(cfg$data_dir, 'power_grid_states_switchers.csv')}"))
    message(glue("  - {file.path(cfg$data_dir, 'mde_surface_states_switchers.csv')}"))
  } else {
    power_A1 <- simulate_power(panel_df, treat_schedule_std, option = "A1", cfg = cfg, cluster_var = cluster_var)
    power_A2 <- simulate_power(panel_df, treat_schedule_std, option = "A2", cfg = cfg, cluster_var = cluster_var)
    write_csv(power_A1, "power_A1.csv")
    power_results <- bind_rows(power_A1, power_A2) %>% arrange(option, effect_size)
    
    mde_tbl <- power_results %>%
      group_by(option, estimand, target_h) %>%
      summarise(mde_80 = compute_mde(pick(everything()), power_target = cfg$power_target), .groups = "drop")
    print(mde_tbl)
    
    calib <- power_results %>%
      filter(effect_size == 0) %>%
      select(option, power) %>%
      mutate(expected_alpha = cfg$alpha)
    print(calib)
    
    write_csv(power_results, file.path(cfg$data_dir, "power_results.csv"))
    
    p <- power_results %>%
      ggplot(aes(x = effect_size, y = power, color = option)) +
      geom_line(linewidth = 1) +
      geom_point() +
      geom_hline(yintercept = cfg$power_target, linetype = "dashed") +
      scale_y_continuous(limits = c(0, 1)) +
      labs(
        title = "Simulated power curve (staggered adoption, CS estimator)",
        subtitle = glue("Panel: {cfg$panel_choice} | Estimand: {cfg$estimand}{ifelse(cfg$estimand=='event_time', glue(' (h={cfg$target_h})'), '')} | cluster: {cluster_var} | alpha={cfg$alpha} | sims={cfg$n_sims} | boot={cfg$did_bstrap} ({cfg$did_biters})"),
        x = "Imposed effect size (outcome units)",
        y = "Power (Pr[p <= alpha])",
        color = "Baseline option"
      ) +
      theme_minimal()
    
    ggsave(file.path(cfg$data_dir, "power_curve.png"), p, width = 8, height = 5, dpi = 300)
    
    best_mde <- mde_tbl %>% arrange(option) %>% slice(1)
    
    grant_paragraph <- glue(
      "We will assess statistical power using simulation-based methods that impose known treatment effects on untreated outcome data and re-estimate our staggered-adoption difference-in-differences model across many simulated samples. ",
      "Consistent with simulation-based power analyses in observational research designs, we introduce effects into pre-treatment (untreated) data to preserve realistic serial correlation and variance structure and compute power as the fraction of simulations rejecting the null at alpha={cfg$alpha}. ",
      "Using monthly panel data ({n_distinct(panel_df$unit_id)} units; {as.character(min(panel_df$month_date))} to {as.character(max(panel_df$month_date))}), we mimic the empirical adoption pattern by preserving the number of treated units and the distribution of treatment timing (shifted into an untreated window) and estimate effects using the Callaway–Sant’Anna estimator with inference clustered at the {cluster_var} level. ",
      "Under our preferred specification, the minimum detectable effect for 80% power is approximately {round(best_mde$mde_80, 3)} outcome units."
    )
    
    writeLines(as.character(grant_paragraph), file.path(cfg$data_dir, "grant_ready_paragraph.txt"))
    cat("\n--- Grant-ready paragraph ---\n")
    cat(grant_paragraph)
    cat("\n-----------------------------\n")
    
    message("\nSaved outputs:")
    message(glue("  - {file.path(cfg$data_dir, 'power_results.csv')}"))
    message(glue("  - {file.path(cfg$data_dir, 'power_curve.png')}"))
    message(glue("  - {file.path(cfg$data_dir, 'grant_ready_paragraph.txt')}"))
  }
}

if (sys.nframe() == 0L) {
  run_power_simulation(cfg)
}

################################################################################
# END
################################################################################
