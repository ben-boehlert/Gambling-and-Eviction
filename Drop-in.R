################################################################################
# POWER GRID BY (# STATES) x (# SWITCHERS), Black-style baseline preserved
#
# Drop-in block for power_simulation_cs.R
#
# What this adds:
#   - Ability to run your existing CS/Black simulation on a grid of:
#       * n_states     = number of distinct state clusters in the baseline
#       * n_switchers  = number of placebo-treated states ("switchers") in the draw
#   - Still builds the baseline exactly your way:
#       * never-treated units: all months
#       * treated units: only pre-treatment months
#   - Still uses did::att_gt + aggte via your run_estimator_and_extract_p()
#
# What you should do:
#   1) Replace your existing draw_placebo_schedule() with the one below
#   2) Paste the rest of this block below simulate_power() (or anywhere after
#      build_untreated_sample/residualize_outcome/impose_effect/run_estimator...)
#   3) In the RUN section, call simulate_power_grid_states_switchers(...)
################################################################################
library(dplyr)
# --- REPLACE your current draw_placebo_schedule() with this version -----------
draw_placebo_schedule <- function(treat_schedule_std,
                                  cfg,
                                  baseline_df,
                                  n_switchers = NULL,
                                  unit_state_map = NULL) {
  
  # STATE-level branch (counties/sites/states panels that carry state_abb)
  if ("state_abb" %in% names(baseline_df)) {
    
    # Mapping from unit_id -> state_abb (use global map if provided)
    if (is.null(unit_state_map)) {
      unit_state_map <- baseline_df %>% distinct(unit_id, state_abb)
    } else {
      unit_state_map <- unit_state_map %>%
        distinct(unit_id, state_abb) %>%
        filter(!is.na(state_abb))
    }
    
    # Units & their observed time ranges (so placebo g is feasible per unit)
    unit_time_range <- baseline_df %>%
      group_by(unit_id, state_abb) %>%
      summarise(
        min_time_id = min(time_id),
        max_time_id = max(time_id),
        .groups = "drop"
      )
    
    baseline_states <- sort(unique(unit_time_range$state_abb))
    if (length(baseline_states) < 2) stop("Need at least 2 baseline states for placebo assignment.")
    
    # Build the REAL adoption-date pool at the STATE level using the *full* schedule + map
    # (important: don't let your baseline subsetting shrink the date pool)
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
    
    # Shift into baseline window
    shift_months <- max(cfg$post_len + 1L, 1L)
    min_t <- min(baseline_df$time_id, na.rm = TRUE)
    max_t <- max(baseline_df$time_id, na.rm = TRUE)
    
    placebo_dates <- treatment_dates - shift_months
    placebo_dates <- placebo_dates[
      placebo_dates >= (min_t + cfg$pre_len) &
        placebo_dates <= (max_t - cfg$post_len)
    ]
    
    if (length(placebo_dates) == 0) stop("No valid placebo dates after shifting into baseline window.")
    
    # Decide how many switcher states to treat in this draw
    if (is.null(n_switchers)) {
      treated_share <- mean(state_ts_full$ever_treated, na.rm = TRUE)
      n_to_treat <- round(length(baseline_states) * treated_share)
    } else {
      n_to_treat <- as.integer(n_switchers)
    }
    
    # Leave at least one never-treated control state
    n_to_treat <- max(1L, min(n_to_treat, length(baseline_states) - 1L))
    
    treated_states_sample <- sample(baseline_states, size = n_to_treat, replace = FALSE)
    placebo_dates_sample  <- sample(placebo_dates,  size = n_to_treat, replace = TRUE) # cohorts allowed
    
    placebo_state <- tibble(
      state_abb = c(treated_states_sample, setdiff(baseline_states, treated_states_sample)),
      g_placebo = c(placebo_dates_sample, rep(0L, length(baseline_states) - n_to_treat))
    )
    
    # Push state g_placebo down to units; drop infeasible g for short series units
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
  
  # UNIT-level branch (only used if state_abb doesn't exist)
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

# --- NEW: build baseline once (Black-style) and keep only needed columns -------
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

# --- NEW: subset baseline to N clusters (states) -------------------------------
subset_baseline_to_n_clusters <- function(baseline, cluster_var, n_clusters, seed = NULL) {
  if (!(cluster_var %in% names(baseline))) stop(glue::glue("cluster_var='{cluster_var}' not in baseline."))
  
  clusters <- sort(unique(baseline[[cluster_var]]))
  if (n_clusters > length(clusters)) {
    stop(glue::glue("Requested {n_clusters} clusters but baseline only has {length(clusters)}."))
  }
  
  if (!is.null(seed)) set.seed(seed)
  chosen <- sample(clusters, size = n_clusters, replace = FALSE)
  
  baseline %>% filter(.data[[cluster_var]] %in% chosen)
}

# --- NEW: simulate_power but FROM a provided baseline + scenario controls -------
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
  
  # Metadata for this scenario
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
      
      # Cluster-aware feasibility checks (critical when clustering at state)
      treated_clusters <- if (cluster_var %in% names(df_sim)) {
        dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo > 0L])
      } else NA_integer_
      
      never_clusters <- if (cluster_var %in% names(df_sim)) {
        dplyr::n_distinct(df_sim[[cluster_var]][df_sim$g_placebo == 0L])
      } else NA_integer_
      
      n_treated_units <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo > 0L])
      n_never_units   <- dplyr::n_distinct(df_sim$unit_id[df_sim$g_placebo == 0L])
      n_treated_obs   <- sum(df_sim$g_placebo > 0L, na.rm = TRUE)
      
      # Keep your unit-level checks, but add cluster checks so "1 treated state" fails early
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
      if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_sim)) keep2 <- c(keep2, cfg$weights_var)
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

# --- NEW: run grid over n_states x n_switchers, preserving Black baseline -------
simulate_power_grid_states_switchers <- function(panel_df,
                                                 treat_schedule_std,
                                                 cfg,
                                                 cluster_var,
                                                 n_states_grid,
                                                 n_switchers_grid,
                                                 option = c("A1", "A2"),
                                                 seed_base = 1000L) {
  
  option <- match.arg(option)
  
  # Baseline ONCE per option (Black-style)
  baseline_full <- make_baseline_once(panel_df, treat_schedule_std, option = option, cfg = cfg, cluster_var = cluster_var)
  
  # Global unit->state map so your placebo date pool doesn't shrink when you subset states
  unit_state_map <- if ("state_abb" %in% names(panel_df)) {
    panel_df %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))
  } else {
    NULL
  }
  
  grid <- tidyr::expand_grid(
    n_states = as.integer(n_states_grid),
    n_switchers = as.integer(n_switchers_grid)
  ) %>%
    # leave at least 1 control state (never-treated in placebo schedule)
    filter(n_states >= (n_switchers + 1L))
  
  purrr::pmap_dfr(grid, function(n_states, n_switchers) {
    
    # scenario-specific seed (stable across reruns)
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

################################################################################
# Example RUN usage (replace your old RUN block if you want grid outputs)
################################################################################
n_states_grid    <- c(10, 15, 20, 25, 30, 32)
n_switchers_grid <- c(3, 5, 8, 10, 12, 15)
#
power_A1_grid <- simulate_power_grid_states_switchers(
  panel_df, treat_schedule_std, cfg, cluster_var,
  n_states_grid = n_states_grid,
  n_switchers_grid = n_switchers_grid,
  option = "A1",
  seed_base = 123
)
write.csv(power_A1_grid, "power_A1_grid_states_switchers.csv")
power_A2_grid <- simulate_power_grid_states_switchers(
  panel_df, treat_schedule_std, cfg, cluster_var,
  n_states_grid = n_states_grid,
  n_switchers_grid = n_switchers_grid,
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
################################################################################
