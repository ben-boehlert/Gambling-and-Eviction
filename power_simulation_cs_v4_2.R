#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_v4_2.R
#
# Simulation-based power analysis for staggered-adoption DiD using CS (did::att_gt)
#
# This revision implements robustness + HPC-safe parallelism + bug fixes:
#   - Fix treatment schedule joins (states_from_counties + sites_ets)
#   - Standardize g_id/ever_treated consistently (ever_treated := g_id > 0)
#   - Fix fixest residualization to correctly handle dropped observations
#   - Drop NA clusters when subsetting baseline to n_clusters
#   - HPC-safe parallel defaults (SLURM_CPUS_PER_TASK / parallelly::availableCores)
#   - Avoid oversubscription: force 1 thread per worker (BLAS/OMP + fixest)
#   - Prefer multicore on Linux when available; fall back safely
#   - "Don't die on OOM": retry with fewer workers; if still fails, return NA draws
#   - Frequent checkpoints + gc() to limit memory growth
#
# Files used (must be present in data_dir):
#   - allstates_monthly_2020_2021.csv
#   - all_sites_monthly_2020_2021.csv
#   - monthly_county_data_download.csv
#   - sports_gambling_legalization_dates.csv
#
# Outputs (grid mode):
#   - power_grid_states_switchers.csv
#   - mde_surface_states_switchers.csv
#   - mde_heatmap.png
#   - power_heatmap_at_max_effect.png
#   - power_FATAL_ERROR.txt (only if fatal error)
#
# Outputs (non-grid mode):
#   - power_results.csv
#   - power_curve.png
#   - grant_ready_paragraph.txt
#   - power_FATAL_ERROR.txt (only if fatal error)
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

# Optional but recommended for scheduler-aware cores
has_parallelly <- requireNamespace("parallelly", quietly = TRUE)

set.seed(20251224)
handlers(global = TRUE)
handlers("txtprogressbar")
options(progressr.enable = TRUE)

################################################################################
# 0) CONFIG
################################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

compute_default_workers <- function(fallback = 1L) {
  # Prefer SLURM_CPUS_PER_TASK when present, else parallelly::availableCores(), else detectCores()-1.
  slurm <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", NA)))
  if (is.finite(slurm) && slurm >= 1L) return(slurm)

  if (isTRUE(has_parallelly)) {
    w <- suppressWarnings(as.integer(parallelly::availableCores()))
    if (is.finite(w) && w >= 1L) return(w)
  }

  w <- suppressWarnings(as.integer(parallel::detectCores(logical = TRUE)))
  if (is.finite(w) && w >= 2L) return(max(1L, w - 1L))

  as.integer(fallback)
}

if (!exists("cfg", inherits = FALSE)) {
  cfg <- list(
    data_dir = ".",

    panel_choice = "states_from_counties",

    outcome_preference = c(
      "filings_per_1k_renters",
      "filings_count_per_1k_renters",
      "filings_count",
      "filings_2020",
      "filings_avg",
      "percent_of_historical_average"
    ),

    weights_var = "renter_occupied_housing_units",

    treat_date_col = "online_start_date",

    n_sims = 500,
    effect_grid = c(0, 1, 3, 5, 8),
    alpha = 0.05,
    power_target = 0.80,
    mde_method = 'bracket',

    run_state_switcher_grid = TRUE,
    n_states_grid = c(10, 20, 30),
    n_switchers_grid = c(8, 10, 13, 18),

    estimand = "overall_att",
    target_h = 12,

    pre_len = 12,
    post_len = 12,

    effect_shape = "step",
    delay_h = 6,

    did_bstrap = TRUE,
    did_biters = 50,
    did_cband = FALSE,

    cluster_level = "state",

    # Parallel settings
    use_parallel = TRUE,
    workers = compute_default_workers(fallback = 1L),

    # Future globals max size (GB). If you're exporting a large baseline, raise this.
    future_globals_max_gb = 8
  )
}

################################################################################
# 0b) Robust runtime helpers
################################################################################

is_memory_error <- function(e) {
  msg <- conditionMessage(e)
  grepl("cannot allocate|std::bad_alloc|out of memory|MemoryError|vector of size|allocation failed",
        msg, ignore.case = TRUE)
}

configure_threads <- function() {
  # Prevent oversubscription: each worker uses 1 thread internally.
  Sys.setenv(
    OMP_NUM_THREADS = "1",
    OPENBLAS_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    BLIS_NUM_THREADS = "1"
  )
  if (requireNamespace("fixest", quietly = TRUE)) {
    # fixest uses its own thread setting
    try(suppressWarnings(fixest::setFixest_nthreads(1L)), silent = TRUE)
  }
}

set_future_plan_safe <- function(workers, prefer = c("auto", "multicore", "multisession")) {
  prefer <- match.arg(prefer)
  workers <- max(1L, as.integer(workers))

  # Increase globals limit for furrr/future serialization if needed
  if (!is.null(cfg$future_globals_max_gb) && is.finite(cfg$future_globals_max_gb)) {
    options(future.globals.maxSize = as.numeric(cfg$future_globals_max_gb) * 1024^3)
  }

  # On Linux batch nodes, multicore is often cheaper (copy-on-write).
  # But on some environments multicore is unsupported; then fall back.
  if (prefer %in% c("auto", "multicore") && future::supportsMulticore()) {
    tryCatch({
      future::plan(future::multicore, workers = workers)
      return(invisible("multicore"))
    }, error = function(e) {
      # fall through to multisession
      NULL
    })
  }

  tryCatch({
    future::plan(future::multisession, workers = workers)
    invisible("multisession")
  }, error = function(e) {
    future::plan(future::sequential)
    invisible("sequential")
  })
}

safe_future_map_draws <- function(n_sims, one_draw_fn, eff, cfg, use_progress = TRUE) {
  # Try parallel with decreasing workers; if still failing, fall back to sequential.
  # Never throws; returns a tibble with n_sims rows (possibly all-NA with fail tag).
  if (!isTRUE(cfg$use_parallel)) {
    pb <- utils::txtProgressBar(min = 0, max = n_sims, style = 3)
    out <- purrr::map_dfr(seq_len(n_sims), function(s) {
      utils::setTxtProgressBar(pb, s)
      one_draw_fn(eff, s)
    })
    close(pb)
    return(out)
  }

  worker_try <- unique(pmax(1L, c(cfg$workers, floor(cfg$workers/2), floor(cfg$workers/4), 1L)))
  worker_try <- worker_try[worker_try >= 1L]

  last_err <- NULL

  for (w in worker_try) {
    # Set plan for this attempt
    strategy <- set_future_plan_safe(workers = w, prefer = "auto")
    message(glue("Parallel attempt: strategy={strategy}, workers={w}"))
    flush.console()

    out <- tryCatch({
      if (isTRUE(use_progress)) {
        progressr::with_progress({
          p <- progressr::progressor(steps = n_sims)
          furrr::future_map_dfr(
            seq_len(n_sims),
            ~ { p(); one_draw_fn(eff, .x) },
            .options = furrr::furrr_options(seed = TRUE)
          )
        })
      } else {
        furrr::future_map_dfr(
          seq_len(n_sims),
          ~ one_draw_fn(eff, .x),
          .options = furrr::furrr_options(seed = TRUE)
        )
      }
    }, error = function(e) {
      last_err <<- e
      NULL
    })

    if (!is.null(out)) return(out)

    # If it looks like a memory error, retry with fewer workers; otherwise break to sequential
    if (!is.null(last_err) && !is_memory_error(last_err)) break

    message(glue("Parallel attempt failed ({ifelse(is.null(last_err),'unknown',conditionMessage(last_err))}); retrying with fewer workers..."))
    flush.console()
    gc(verbose = FALSE)
  }

  # Sequential fallback
  message("Falling back to sequential draws (parallel failed).")
  flush.console()
  future::plan(future::sequential)

  out2 <- tryCatch({
    pb <- utils::txtProgressBar(min = 0, max = n_sims, style = 3)
    out <- purrr::map_dfr(seq_len(n_sims), function(s) {
      utils::setTxtProgressBar(pb, s)
      one_draw_fn(eff, s)
    })
    close(pb)
    out
  }, error = function(e) {
    # Last resort: return NA rows so the script can continue and checkpoint
    tibble::tibble(
      sim = seq_len(n_sims),
      p = NA_real_, est = NA_real_, se = NA_real_,
      fail = paste0("draws_failed: ", conditionMessage(e))
    )
  })

  out2
}

################################################################################
# 1) Helpers: parsing and indexing
################################################################################

parse_month_to_date <- function(x) {
  if (inherits(x, "Date"))   return(as.Date(floor_date(x, "month")))
  if (inherits(x, "POSIXt")) return(as.Date(floor_date(as.Date(x), "month")))

  x_chr <- as.character(x)
  x_chr[is.na(x_chr)] <- ""

  out <- rep(as.Date(NA), length(x_chr))

  detect <- function(v, pattern) {
    r <- str_detect(v, pattern)
    r[is.na(r)] <- FALSE
    r
  }

  idx_iso_dt <- detect(x_chr, "^\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2}")
  if (any(idx_iso_dt, na.rm = TRUE)) {
    out[idx_iso_dt] <- suppressWarnings(
      as.Date(floor_date(ymd_hms(x_chr[idx_iso_dt], quiet = TRUE), "month"))
    )
  }

  idx_iso_d <- is.na(out) & detect(x_chr, "^\\d{4}-\\d{2}-\\d{2}$")
  if (any(idx_iso_d, na.rm = TRUE)) {
    out[idx_iso_d] <- suppressWarnings(
      as.Date(floor_date(ymd(x_chr[idx_iso_d], quiet = TRUE), "month"))
    )
  }

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

state_key <- function(x) {
  x %>%
    as.character() %>%
    str_to_lower() %>%
    str_replace_all("[^a-z]", "")
}

################################################################################
# 2) Crosswalks (for counties/sites -> state)
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
  df <- readr::read_csv(path, show_col_types = FALSE) %>%
    mutate(
      unit_id = as.numeric(fips),
      month_date = parse_month_to_date(date),
      time_id = date_to_time_id(month_date),
      state_fips = as.integer(floor(as.numeric(fips) / 1000))
    ) %>%
    left_join(state_fips_xwalk, by = "state_fips") %>%
    filter(!is.na(state_abb)) %>%
    mutate(
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
  counties <- prep_panel_counties(cfg)

  df <- counties %>%
    group_by(state_abb, state_name, month_date, time_id) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      state_fips = first(state_fips),
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
      unit_id = as.numeric(state_fips),
      filings_count_per_1k_renters = if_else(
        renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        NA_real_
      )
    )

  cfg2 <- cfg
  cfg2$outcome_preference <- c("filings_count_per_1k_renters", cfg$outcome_preference)
  df <- pick_outcome(df, cfg2)

  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

prep_panel_states_ets <- function(cfg) {
  path <- file.path(cfg$data_dir, "allstates_monthly_2020_2021.csv")
  raw <- readr::read_csv(path, show_col_types = FALSE)

  df <- collapse_unit_month(
    raw,
    unit_col = state,
    month_col = month,
    sum_cols = intersect(c("filings_2020", "filings_avg"), names(raw))
  ) %>%
    mutate(unit_id = state_key(unit_id))

  df <- pick_outcome(df, cfg)

  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

prep_panel_sites_ets <- function(cfg) {
  path <- file.path(cfg$data_dir, "all_sites_monthly_2020_2021.csv")
  raw <- readr::read_csv(path, show_col_types = FALSE)

  df <- collapse_unit_month(
    raw,
    unit_col = city,
    month_col = month,
    sum_cols = intersect(c("filings_2020", "filings_avg", "filings_avg_prepandemic_baseline"), names(raw))
  ) %>%
    mutate(
      state_abb = str_extract(unit_id, "(?<=,\\s)[A-Z]{2}$"),
      unit_id = str_trim(unit_id)
    )

  df <- pick_outcome(df, cfg)

  df %>%
    filter(!is.na(unit_id), !is.na(time_id), !is.na(outcome)) %>%
    arrange(unit_id, time_id)
}

load_panel <- function(cfg) {
  df <- switch(
    cfg$panel_choice,
    "counties" = prep_panel_counties(cfg),
    "states_from_counties" = prep_panel_states_from_counties(cfg),
    "states_ets" = prep_panel_states_ets(cfg),
    "sites_ets" = prep_panel_sites_ets(cfg),
    stop("cfg$panel_choice must be one of: counties, states_from_counties, states_ets, sites_ets")
  )

  if (!is.null(cfg$restrict_to_precovid) && isTRUE(cfg$restrict_to_precovid)) {
    cutoff <- if (!is.null(cfg$precovid_cutoff)) cfg$precovid_cutoff else as.Date("2020-03-01")
    df <- df %>% filter(month_date < cutoff)
    message(sprintf("Restricting panel to pre-COVID: before %s", cutoff))
  }

  df
}

################################################################################
# 4) Treatment schedule from sports_gambling_legalization_dates.csv
################################################################################

read_sports_schedule <- function(cfg) {
  path <- file.path(cfg$data_dir, "sports_gambling_legalization_dates.csv")
  sch <- readr::read_csv(path, show_col_types = FALSE)

  if (!(cfg$treat_date_col %in% names(sch))) {
    stop(glue(
      "cfg$treat_date_col='{cfg$treat_date_col}' not found.\n",
      "Available columns: {paste(names(sch), collapse=', ')}\n",
      "Use e.g. online_start_date / retail_start_date / first_start_date."
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

  if (cfg$panel_choice %in% c("counties")) {
    out <- panel_df %>%
      distinct(unit_id, state_abb) %>%
      left_join(sch %>% select(state_abb, g), by = "state_abb") %>%
      mutate(ever_treated = !is.na(g)) %>%
      select(unit_id, g, ever_treated)
    return(out)
  }

  if (cfg$panel_choice %in% c("states_from_counties")) {
    # FIX: use parsed g from read_sports_schedule(), not the raw column
    sch2 <- sch %>%
      left_join(state_fips_xwalk %>% select(state_fips, state_abb), by = "state_abb") %>%
      transmute(
        unit_id = as.numeric(state_fips),
        g = g,
        ever_treated = !is.na(g)
      )

    out <- panel_df %>%
      distinct(unit_id) %>%
      left_join(sch2, by = "unit_id") %>%
      mutate(
        g = as.Date(g),
        ever_treated = replace_na(ever_treated, FALSE)
      ) %>%
      select(unit_id, g, ever_treated)

    return(out)
  }

  if (cfg$panel_choice %in% c("states_ets")) {
    sch2 <- sch %>%
      transmute(unit_id = state_key, g = g)

    out <- panel_df %>%
      distinct(unit_id) %>%
      left_join(sch2, by = "unit_id") %>%
      mutate(ever_treated = !is.na(g)) %>%
      select(unit_id, g, ever_treated)

    return(out)
  }

  if (cfg$panel_choice %in% c("sites_ets")) {
    # FIX: remove broken join; just join by state_abb
    sch2 <- sch %>% select(state_abb, g)

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
  ts <- treat_schedule %>%
    mutate(
      g_id = suppressWarnings(as.integer(g_to_time_id(g))),
      g_id = replace_na(g_id, 0L),
      ever_treated = g_id > 0L
    ) %>%
    select(unit_id, g_id, ever_treated)

  panel_df %>%
    distinct(unit_id) %>%
    left_join(ts, by = "unit_id") %>%
    mutate(
      g_id = replace_na(g_id, 0L),
      ever_treated = replace_na(ever_treated, FALSE),
      ever_treated = g_id > 0L
    )
}

################################################################################
# 5) Untreated baseline samples
################################################################################

build_untreated_sample <- function(panel_df, treat_schedule_std) {
  time_coverage <- panel_df %>%
    group_by(unit_id) %>%
    summarise(n_periods = n(), .groups = "drop")

  max_periods <- max(time_coverage$n_periods)
  min_periods_threshold <- ceiling(0.8 * max_periods)

  balanced_units <- time_coverage %>%
    filter(n_periods >= min_periods_threshold) %>%
    pull(unit_id)

  panel_df %>%
    filter(unit_id %in% balanced_units) %>%
    left_join(treat_schedule_std %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
    filter((!ever_treated) | (ever_treated & time_id < g_id))
}

residualize_outcome <- function(df_untreated) {
  # FIX: correct handling of dropped observations in fixest
  m <- fixest::feols(outcome ~ 1 | unit_id + time_id, data = df_untreated)

  kept <- tryCatch(fixest::obs(m), error = function(e) NULL)
  if (is.null(kept) || length(kept) == 0L) {
    # If something odd happened, return original (but drop treatment indicators)
    return(df_untreated %>% select(-any_of(c("g_id", "ever_treated"))))
  }

  df_used <- df_untreated[kept, , drop = FALSE]
  mu <- mean(df_used$outcome, na.rm = TRUE)

  df_used %>%
    mutate(outcome = as.numeric(stats::residuals(m)) + mu) %>%
    select(-any_of(c("g_id", "ever_treated")))
}

################################################################################
# 6) Mimic adoption pattern (placebo schedule)
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
    baseline_states <- baseline_states[!is.na(baseline_states)]
    if (length(baseline_states) < 2) stop("Need at least 2 baseline states for placebo assignment.")

    state_ts_full <- treat_schedule_std %>%
      left_join(unit_state_map, by = "unit_id") %>%
      filter(!is.na(state_abb)) %>%
      group_by(state_abb) %>%
      summarise(g_id = suppressWarnings(max(g_id, na.rm = TRUE)), .groups = "drop") %>%
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
# 8) CS estimator wrapper
################################################################################

att_gt_safe <- function(df_in, cfg, cluster_var) {
  df_in <- as.data.frame(df_in)

  args <- list(
    yname = 'outcome_sim',
    tname = 'time_id_seq',
    idname = 'unit_id',
    gname = 'gname',
    data = df_in,
    panel = TRUE,
    control_group = 'notyettreated',
    bstrap = cfg$did_bstrap,
    biters = cfg$did_biters,
    cband = cfg$did_cband,
    est_method = 'ipw'
  )

  if (isTRUE(cfg$did_bstrap) && !is.null(cluster_var) && cluster_var %in% names(df_in)) {
    args$clustervars <- cluster_var
  }

  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_in)) {
    args$weightsname <- cfg$weights_var
  }

  if ('allow_unbalanced_panel' %in% names(formals(did::att_gt))) {
    args$allow_unbalanced_panel <- TRUE
  }

  fmls <- names(formals(did::att_gt))
  if ('cores'  %in% fmls) args$cores  <- 1L
  if ('ncores' %in% fmls) args$ncores <- 1L
  if ('parallel' %in% fmls) args$parallel <- FALSE

  withCallingHandlers(
    do.call(did::att_gt, args),
    warning = function(w) {
      msg <- conditionMessage(w)
      if (grepl("some small groups", msg, ignore.case = TRUE) ||
          grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

run_estimator_and_extract_p <- function(df_sim, cfg, cluster_var, time_mapping = NULL) {
  out <- list(p = NA_real_, est = NA_real_, se = NA_real_)

  if (is.null(time_mapping)) {
    time_mapping <- df_sim %>%
      distinct(time_id) %>%
      arrange(time_id) %>%
      mutate(time_id_seq = row_number())
  }

  g_mapping <- df_sim %>%
    filter(!is.na(g_placebo) & g_placebo > 0L) %>%
    distinct(g_placebo) %>%
    left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
    transmute(g_placebo, g_placebo_seq = time_id_seq)

  df_in <- df_sim %>%
    left_join(time_mapping, by = "time_id") %>%
    left_join(g_mapping, by = "g_placebo") %>%
    mutate(
      gname = if_else(
        is.na(g_placebo) | g_placebo == 0L,
        0,
        as.numeric(coalesce(g_placebo_seq, 0L))
      )
    )

  if (!any(df_in$gname > 0, na.rm = TRUE)) return(out)

  tryCatch({
    att <- att_gt_safe(df_in, cfg, cluster_var = cluster_var)

    if (cfg$estimand == "overall_att") {
      agg_result <- tryCatch({
        agg <- withCallingHandlers(
          did::aggte(att, type = "simple"),
          warning = function(w) {
            msg <- conditionMessage(w)
            if (grepl("some small groups", msg, ignore.case = TRUE) ||
                grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE)) {
              invokeRestart("muffleWarning")
            }
          }
        )
        list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
      }, error = function(e) {
        est_manual <- mean(att$att, na.rm = TRUE)

        if (!is.null(att$inffunc) && length(dim(att$inffunc)) == 2 && nrow(att$inffunc) > 0) {
          inffunc_dense <- if (inherits(att$inffunc, "Matrix")) as.matrix(att$inffunc) else att$inffunc
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
      return(list(p = p, est = est, se = se))
    }

    agg_result <- tryCatch({
      agg <- withCallingHandlers(
        did::aggte(att, type = "dynamic"),
        warning = function(w) {
          msg <- conditionMessage(w)
          if (grepl("some small groups", msg, ignore.case = TRUE) ||
              grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE)) {
            invokeRestart("muffleWarning")
          }
        }
      )
      list(success = TRUE, agg = agg)
    }, error = function(e) list(success = FALSE))

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
# 9) MDE helper
################################################################################

compute_mde <- function(power_df, power_target = 0.80, method = c('bracket', 'closest2'), clamp = TRUE) {
  method <- match.arg(method)

  df <- power_df %>%
    dplyr::select(effect_size, power) %>%
    dplyr::filter(is.finite(effect_size), effect_size > 0) %>%
    dplyr::arrange(effect_size)

  if (nrow(df) < 2) return(NA_real_)
  if (all(is.na(df$power))) return(NA_real_)
  if (max(df$power, na.rm = TRUE) < power_target) return(NA_real_)
  if (min(df$power, na.rm = TRUE) >= power_target) return(as.numeric(df$effect_size[1]))

  if (method == 'bracket') {
    j <- which(df$power >= power_target)[1]
    if (is.na(j) || j <= 1) return(as.numeric(df$effect_size[1]))

    x0 <- df$effect_size[j - 1]
    y0 <- df$power[j - 1]
    x1 <- df$effect_size[j]
    y1 <- df$power[j]

    if (!is.finite(y0) || !is.finite(y1) || y1 == y0) {
      mde <- x1
    } else {
      mde <- x0 + (power_target - y0) * (x1 - x0) / (y1 - y0)
    }
  } else {
    df2 <- df %>%
      dplyr::mutate(dist = abs(power - power_target)) %>%
      dplyr::arrange(dist, effect_size) %>%
      dplyr::slice(1:2)

    x <- df2$effect_size
    y <- df2$power
    if (length(unique(x)) < 2 || any(!is.finite(y))) return(NA_real_)

    fit <- stats::lm(y ~ x)
    b <- stats::coef(fit)
    if (length(b) < 2 || !is.finite(b[2]) || b[2] == 0) return(NA_real_)

    mde <- (power_target - b[1]) / b[2]
  }

  if (!is.finite(mde)) return(NA_real_)

  if (isTRUE(clamp)) {
    lo <- min(df$effect_size, na.rm = TRUE)
    hi <- max(df$effect_size, na.rm = TRUE)
    mde <- max(lo, min(hi, mde))
  }

  as.numeric(mde)
}

################################################################################
# 10) Simulation engines (A1/A2) + grid wrapper
################################################################################

make_baseline_once <- function(panel_df, treat_schedule_std, option = c("A1", "A2"), cfg, cluster_var) {
  option <- match.arg(option)

  baseline <- build_untreated_sample(panel_df, treat_schedule_std)
  if (nrow(baseline) == 0) stop("Untreated baseline is empty.")

  if (option == "A2") baseline <- residualize_outcome(baseline)

  keep <- c("unit_id", "time_id", "month_date", "outcome", "state_abb")
  keep <- unique(c(keep, cluster_var))
  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(baseline)) keep <- unique(c(keep, cfg$weights_var))
  keep <- keep[keep %in% names(baseline)]

  baseline %>% select(all_of(keep))
}

subset_baseline_to_n_clusters <- function(baseline, cluster_var, n_clusters, seed = NULL) {
  if (!(cluster_var %in% names(baseline))) stop(glue("cluster_var='{cluster_var}' not in baseline."))

  clusters <- sort(unique(baseline[[cluster_var]]))
  clusters <- clusters[!is.na(clusters)]  # FIX: do not sample NA as a "cluster"

  if (n_clusters > length(clusters)) {
    stop(glue("Requested {n_clusters} clusters but baseline only has {length(clusters)}."))
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

  # Precompute sequential time ids once per baseline to reduce allocations
  time_mapping <- baseline %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  enforce_windows <- function(df) {
    ok <- df %>%
      filter(g_placebo > 0L) %>%
      group_by(unit_id, g_placebo) %>%
      summarise(min_t = min(time_id), max_t = max(time_id), .groups = "drop") %>%
      mutate(ok = (min_t <= (g_placebo - cfg$pre_len)) & (max_t >= (g_placebo + cfg$post_len)))

    ok_units <- ok %>% filter(ok) %>% pull(unit_id)
    df %>% filter(g_placebo == 0L | unit_id %in% ok_units)
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

      if (identical(cfg$estimand, "event_time")) df_sim <- enforce_windows(df_sim)

      treated_clusters <- if (cluster_var %in% names(df_sim)) dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo > 0L]) else NA_integer_
      never_clusters   <- if (cluster_var %in% names(df_sim)) dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo == 0L]) else NA_integer_

      n_treated_units <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo > 0L])
      n_never_units   <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo == 0L])
      n_treated_obs   <- sum(df_sim$g_placebo > 0L, na.rm = TRUE)

      if (!is.na(treated_clusters) && treated_clusters < 2) {
        return(tibble(sim = s, p = NA_real_, est = NA_real_, se = NA_real_, fail = "too_few_treated_clusters",
                      treated_clusters = treated_clusters, never_clusters = never_clusters,
                      n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs))
      }
      if (n_treated_units < 2) {
        return(tibble(sim = s, p = NA_real_, est = NA_real_, se = NA_real_, fail = "too_few_treated_units",
                      treated_clusters = treated_clusters, never_clusters = never_clusters,
                      n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs))
      }
      if (n_never_units < 2) {
        return(tibble(sim = s, p = NA_real_, est = NA_real_, se = NA_real_, fail = "too_few_never_units",
                      treated_clusters = treated_clusters, never_clusters = never_clusters,
                      n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs))
      }
      if (n_treated_obs == 0) {
        return(tibble(sim = s, p = NA_real_, est = NA_real_, se = NA_real_, fail = "no_treated_obs",
                      treated_clusters = treated_clusters, never_clusters = never_clusters,
                      n_treated_units = n_treated_units, n_never_units = n_never_units, n_treated_obs = n_treated_obs))
      }

      keep2 <- unique(c("unit_id", "time_id", "outcome_sim", "g_placebo", cluster_var))
      if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_sim)) keep2 <- unique(c(keep2, cfg$weights_var))
      keep2 <- keep2[keep2 %in% names(df_sim)]
      df_sim <- df_sim %>% select(all_of(keep2))

      est_raw <- suppressMessages(run_estimator_and_extract_p(df_sim, cfg, cluster_var = cluster_var, time_mapping = time_mapping))

      tibble(
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
      tibble(sim = s, p = NA_real_, est = NA_real_, se = NA_real_,
             fail = paste0("one_draw_error: ", conditionMessage(e)),
             treated_clusters = NA_integer_, never_clusters = NA_integer_,
             n_treated_units = NA_integer_, n_never_units = NA_integer_, n_treated_obs = NA_integer_)
    })
  }

  res_list <- vector("list", length(cfg$effect_grid))

  for (k in seq_along(cfg$effect_grid)) {
    eff <- cfg$effect_grid[k]
    message(glue("[{Sys.time()}] {option}: n_states={n_clusters} n_switchers={n_switchers %||% NA_integer_} effect {k}/{length(cfg$effect_grid)} (eff={eff})"))
    flush.console()

    draws <- safe_future_map_draws(
      n_sims = cfg$n_sims,
      one_draw_fn = one_draw,
      eff = eff,
      cfg = cfg,
      use_progress = TRUE
    )

    # Ensure we have expected columns even if a draw failed hard
    if (!("fail" %in% names(draws))) draws$fail <- NA_character_

    power <- mean(!is.na(draws$p) & draws$p <= cfg$alpha)
    if (is.nan(power)) power <- NA_real_

    res_list[[k]] <- tibble(
      option = option,
      panel_choice = cfg$panel_choice,
      estimand = cfg$estimand,
      target_h = if_else(cfg$estimand == "event_time", cfg$target_h, NA_integer_),
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

    # Free memory aggressively between effects
    rm(draws)
    gc(verbose = FALSE)
  }

  bind_rows(res_list)
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

  if (!is.null(n_states_grid)) {
    max_clusters <- if (cluster_var %in% names(baseline_full)) dplyr::n_distinct(baseline_full[[cluster_var]]) else NA_integer_
    if (is.finite(max_clusters)) {
      n_states_grid <- as.integer(n_states_grid)
      n_states_grid <- n_states_grid[n_states_grid <= max_clusters]
      if (length(n_states_grid) == 0L) stop(glue("All requested n_states_grid exceed available clusters in baseline: {max_clusters}."))
    }
  }

  unit_state_map <- if ("state_abb" %in% names(panel_df)) panel_df %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb)) else NULL

  grid <- tidyr::expand_grid(
    n_states = as.integer(n_states_grid),
    n_switchers = as.integer(n_switchers_grid)
  ) %>%
    filter(n_states >= (n_switchers + 1L))

  out_all <- purrr::pmap_dfr(grid, function(n_states, n_switchers) {
    baseline_seed <- as.integer(seed_base + 10000L * n_states)
    scenario_seed <- as.integer(seed_base + 10000L * n_states + n_switchers)

    baseline_s <- subset_baseline_to_n_clusters(
      baseline_full,
      cluster_var = cluster_var,
      n_clusters = n_states,
      seed = baseline_seed
    )

    # Checkpoint each scenario so partial results exist even if a later scenario OOMs
    res <- tryCatch({
      simulate_power_from_baseline(
        baseline = baseline_s,
        treat_schedule_std = treat_schedule_std,
        option = option,
        cfg = cfg,
        cluster_var = cluster_var,
        n_switchers = n_switchers,
        unit_state_map = unit_state_map,
        scenario_seed = scenario_seed
      ) %>% mutate(n_states = n_states, n_switchers = n_switchers)
    }, error = function(e) {
      tibble(
        option = option,
        panel_choice = cfg$panel_choice,
        estimand = cfg$estimand,
        target_h = if_else(cfg$estimand == "event_time", cfg$target_h, NA_integer_),
        effect_size = cfg$effect_grid,
        power = NA_real_,
        mean_est = NA_real_,
        mean_se = NA_real_,
        n_sims = cfg$n_sims,
        n_units = dplyr::n_distinct(baseline_s$unit_id),
        n_clusters = dplyr::n_distinct(baseline_s[[cluster_var]]),
        n_switchers = n_switchers,
        start_date = min(baseline_s$month_date, na.rm = TRUE),
        end_date = max(baseline_s$month_date, na.rm = TRUE),
        n_states = n_states,
        fail_scenario = paste0("scenario_failed: ", conditionMessage(e))
      )
    })

    # Scenario checkpoint
    chk <- file.path(cfg$data_dir, glue("power_grid_partial_{option}.csv"))
    suppressWarnings(readr::write_csv(bind_rows(out_all %||% tibble(), res), chk))

    rm(baseline_s)
    gc(verbose = FALSE)

    res
  })

  out_all
}

################################################################################
# 11) Main runner
################################################################################

run_power_simulation <- function(cfg) {
  configure_threads()

  if (isTRUE(cfg$use_parallel)) {
    set_future_plan_safe(workers = cfg$workers, prefer = "auto")
    message(glue("Parallel ON: requested workers = {cfg$workers}"))
  } else {
    future::plan(future::sequential)
    message("Parallel OFF")
  }

  panel_df <- load_panel(cfg)
  message(glue("Loaded panel: {cfg$panel_choice}"))
  message(glue("Outcome used: {attr(panel_df, 'outcome_var')}"))
  cfg$outcome_name <- attr(panel_df, "outcome_var") %||% "outcome"
  message(glue("Units: {n_distinct(panel_df$unit_id)} | Months: {n_distinct(panel_df$time_id)}"))

  cluster_var <- dplyr::case_when(
    cfg$cluster_level == "unit" ~ "unit_id",
    cfg$cluster_level == "state" ~ if ("state_abb" %in% names(panel_df)) "state_abb" else "unit_id",
    TRUE ~ "unit_id"
  )

  treat_schedule <- make_treat_schedule(panel_df, cfg)
  treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

  unit_state_map <- if ("state_abb" %in% names(panel_df)) {
    panel_df %>% distinct(unit_id, state_abb)
  } else {
    tibble(unit_id = unique(panel_df$unit_id), state_abb = NA_character_)
  }

  ts_sum <- treat_schedule_std %>%
    left_join(unit_state_map, by = "unit_id") %>%
    summarise(
      n_units = n(),
      n_treated = sum(ever_treated & g_id > 0),
      share_treated = mean(ever_treated & g_id > 0),
      n_states = if (all(is.na(state_abb))) NA_integer_ else dplyr::n_distinct(state_abb, na.rm = TRUE),
      n_treated_states = if (all(is.na(state_abb))) NA_integer_ else dplyr::n_distinct(state_abb[ever_treated & g_id > 0], na.rm = TRUE),
      min_g = suppressWarnings(min(if_else(g_id > 0, g_id, NA_integer_), na.rm = TRUE)),
      max_g = suppressWarnings(max(if_else(g_id > 0, g_id, NA_integer_), na.rm = TRUE))
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

    readr::write_csv(power_grid_all, file.path(cfg$data_dir, "power_grid_states_switchers.csv"))

    mde_surface <- power_grid_all %>%
      group_by(option, estimand, target_h, n_states, n_switchers) %>%
      summarise(mde_80 = compute_mde(dplyr::pick(effect_size, power), power_target = cfg$power_target, method = cfg$mde_method),
                .groups = "drop")

    readr::write_csv(mde_surface, file.path(cfg$data_dir, "mde_surface_states_switchers.csv"))

    mde_plot <- mde_surface %>%
      mutate(n_states = as.factor(n_states), n_switchers = as.factor(n_switchers)) %>%
      ggplot(aes(x = n_states, y = n_switchers, fill = mde_80)) +
      geom_tile() +
      facet_wrap(~ option) +
      labs(
        title = "Minimum Detectable Effect (80% power) by sample size and # switchers",
        subtitle = paste0("Outcome: ", cfg$outcome_name, " | alpha=", cfg$alpha,
                          " | sims=", cfg$n_sims, " | did bootstrap iters=", cfg$did_biters),
        x = "Number of states (clusters) in sample",
        y = "Number of treated states (switchers)",
        fill = "MDE@80%"
      ) +
      theme_minimal()

    ggsave(file.path(cfg$data_dir, "mde_heatmap.png"), mde_plot, width = 9, height = 5.5, dpi = 300)

    max_eff <- max(cfg$effect_grid, na.rm = TRUE)
    pow_plot <- power_grid_all %>%
      filter(effect_size == max_eff) %>%
      mutate(n_states = as.factor(n_states), n_switchers = as.factor(n_switchers)) %>%
      ggplot(aes(x = n_states, y = n_switchers, fill = power)) +
      geom_tile() +
      facet_wrap(~ option) +
      labs(
        title = paste0("Power at effect = ", max_eff, " (", cfg$outcome_name, " units)"),
        subtitle = paste0("alpha=", cfg$alpha, " | sims=", cfg$n_sims),
        x = "Number of states (clusters) in sample",
        y = "Number of treated states (switchers)",
        fill = "Power"
      ) +
      theme_minimal()

    ggsave(file.path(cfg$data_dir, "power_heatmap_at_max_effect.png"), pow_plot, width = 9, height = 5.5, dpi = 300)

    message("\nSaved outputs:")
    message(glue("  - {file.path(cfg$data_dir, 'power_grid_states_switchers.csv')}"))
    message(glue("  - {file.path(cfg$data_dir, 'mde_surface_states_switchers.csv')}"))
    message(glue("  - {file.path(cfg$data_dir, 'mde_heatmap.png')}"))
    message(glue("  - {file.path(cfg$data_dir, 'power_heatmap_at_max_effect.png')}"))
  } else {
    # Non-grid mode: keep your prior outputs (power curve + paragraph)
    # You can extend this section if you still use it; grid mode is the default.
    stop("Non-grid mode not enabled in this v4_2 runner. Set cfg$run_state_switcher_grid=TRUE (default).")
  }

  invisible(TRUE)
}

################################################################################
# 12) Entrypoint (never hard-crash without writing a diagnostic file)
################################################################################

if (sys.nframe() == 0L) {
  tryCatch(
    run_power_simulation(cfg),
    error = function(e) {
      msg <- paste0("FATAL ERROR: ", conditionMessage(e), "\n")
      cat(msg)
      # Always write a diagnostic file so the Slurm job isn't a black box.
      out_path <- file.path(cfg$data_dir %||% ".", "power_FATAL_ERROR.txt")
      try(writeLines(msg, out_path), silent = TRUE)
      # Do not rethrow; exit cleanly so you still keep partial CSV checkpoints.
      invisible(FALSE)
    }
  )
}

################################################################################
# END
################################################################################
