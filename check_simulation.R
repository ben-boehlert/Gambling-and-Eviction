#!/usr/bin/env Rscript
################################################################################
# check_simulation.R
# Diagnostic suite for staggered DiD power simulation
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(glue)
})

set.seed(123)

# Environment variables for configuration
CHECK_N_SIMS <- as.integer(Sys.getenv("CHECK_N_SIMS", "200"))
CHECK_ALPHA <- as.numeric(Sys.getenv("CHECK_ALPHA", "0.05"))
CHECK_EFFECTS <- as.numeric(strsplit(Sys.getenv("CHECK_EFFECTS", "0,0.5,1,2"), ",")[[1]])

cat("=== Power Simulation Diagnostics ===\n")
cat(glue("N_SIMS: {CHECK_N_SIMS}, ALPHA: {CHECK_ALPHA}, EFFECTS: {paste(CHECK_EFFECTS, collapse=', ')}\n\n"))

# Source the simulation script
tryCatch({
  source("power_simulation_cs.R")
}, error = function(e) {
  cat(glue("\033[31mERROR: Failed to source power_simulation_cs.R: {e$message}\033[0m\n"))
  quit(status = 1)
})

# Initialize report
report <- tibble(
  test_name = character(),
  pass = logical(),
  detail = character(),
  metric1_name = character(),
  metric1_value = character(),
  metric2_name = character(),
  metric2_value = character()
)

# Helper functions
passfail <- function(pass, detail, metrics = list()) {
  list(
    pass = isTRUE(pass),  # Force to strict TRUE/FALSE, never NA
    detail = detail,
    metric1_name = if (length(metrics) >= 1) names(metrics)[1] else NA_character_,
    metric1_value = if (length(metrics) >= 1) as.character(metrics[[1]]) else NA_character_,
    metric2_name = if (length(metrics) >= 2) names(metrics)[2] else NA_character_,
    metric2_value = if (length(metrics) >= 2) as.character(metrics[[2]]) else NA_character_
  )
}

add_test <- function(report_df, test_name, fn) {
  cat(glue("Running: {test_name}...\n"))
  result <- tryCatch(
    fn(),
    error = function(e) {
      passfail(FALSE, glue("ERROR: {e$message}"), list(error = as.character(e)))
    }
  )

  bind_rows(
    report_df,
    tibble(
      test_name = test_name,
      pass = result$pass,
      detail = result$detail,
      metric1_name = result$metric1_name %||% NA_character_,
      metric1_value = result$metric1_value %||% NA_character_,
      metric2_name = result$metric2_name %||% NA_character_,
      metric2_value = result$metric2_value %||% NA_character_
    )
  )
}

################################################################################
# Load common objects once
################################################################################
cat("Loading panel and baseline data...\n")
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

cluster_var <- case_when(
  cfg$cluster_level == "unit" ~ "unit_id",
  cfg$cluster_level == "state" ~ if ("state_abb" %in% names(panel_df)) "state_abb" else "unit_id",
  TRUE ~ "unit_id"
)

baseline <- build_untreated_sample(panel_df, treat_schedule_std)

# CRITICAL: Residualize outcomes to remove unit/time fixed effects
# This ensures baseline outcomes don't differ systematically between
# units that were treated in reality vs never-treated units
baseline <- residualize_outcome(baseline)

unit_state_map <- if ("state_abb" %in% names(panel_df)) {
  panel_df %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))
} else {
  NULL
}

cat("\n")

################################################################################
# TEST 1: Panel aggregation identity check
################################################################################
report <- add_test(report, "Panel aggregation identity", function() {
  if (cfg$panel_choice != "states_from_counties") {
    return(passfail(TRUE, "SKIP: not states_from_counties", list(skipped = "yes")))
  }

  county_file <- file.path(cfg$data_dir, "monthly_county_data_download.csv")
  if (!file.exists(county_file)) {
    return(passfail(FALSE, "County file not found", list(file = county_file)))
  }

  county_raw <- read_csv(county_file, show_col_types = FALSE, col_types = cols()) %>%
    mutate(
      fips_num = as.numeric(fips),
      state_fips = as.integer(floor(fips_num / 1000)),  # Extract state FIPS from county FIPS
      month_date = parse_month_to_date(date)
    )

  # Load state FIPS crosswalk to get state_abb
  if (!exists("state_fips_xwalk")) {
    return(passfail(FALSE, "state_fips_xwalk not loaded", list()))
  }

  county_with_state <- county_raw %>%
    left_join(state_fips_xwalk %>% select(state_fips, state_abb), by = "state_fips") %>%
    # Filter out territories (PR=72, VI=78) - same as panel construction
    filter(!is.na(state_abb))

  # Sample 10 random state-month pairs
  all_pairs <- panel_df %>%
    filter(!is.na(state_abb)) %>%
    select(state_abb, month_date) %>%
    distinct()

  n_sample <- min(10, nrow(all_pairs))
  test_pairs <- all_pairs %>% slice_sample(n = n_sample)

  errors <- map_dfr(1:nrow(test_pairs), function(i) {
    st <- test_pairs$state_abb[i]
    dt <- test_pairs$month_date[i]

    # Aggregate from county data
    agg <- county_with_state %>%
      filter(state_abb == st, month_date == dt) %>%
      summarise(
        filings_sum = sum(filings_count, na.rm = TRUE),
        renters_sum = sum(renter_occupied_housing_units, na.rm = TRUE)
      )

    # Get from panel
    panel_val <- panel_df %>%
      filter(state_abb == st, month_date == dt) %>%
      select(filings_count_per_1k_renters, renter_occupied_housing_units)

    if (nrow(panel_val) == 0 || nrow(agg) == 0) return(tibble(rel_error = NA_real_))

    expected_rate <- (agg$filings_sum / agg$renters_sum) * 1000
    actual_rate <- panel_val$filings_count_per_1k_renters[1]

    tibble(rel_error = abs(expected_rate - actual_rate) / (abs(expected_rate) + 1e-10))
  })

  max_error <- max(errors$rel_error, na.rm = TRUE)
  pass <- max_error < 1e-6

  passfail(pass,
           ifelse(pass, "Aggregation correct", glue("Max error: {signif(max_error, 3)}")),
           list(max_rel_error = signif(max_error, 3), n_tested = nrow(test_pairs)))
})

################################################################################
# TEST 2: Treatment schedule join integrity
################################################################################
report <- add_test(report, "Treatment schedule integrity", function() {
  n_units <- n_distinct(panel_df$unit_id)
  n_sched <- nrow(treat_schedule_std)

  if (n_sched != n_units) {
    return(passfail(FALSE, glue("Mismatch: {n_sched} != {n_units}"),
                    list(sched_rows = n_sched, panel_units = n_units)))
  }

  time_range <- panel_df %>%
    summarise(min_t = min(time_id), max_t = max(time_id))

  treated_g <- treat_schedule_std %>%
    filter(g_id > 0) %>%
    mutate(in_range = g_id >= time_range$min_t - 24 & g_id <= time_range$max_t + 24)

  share_in_range <- mean(treated_g$in_range, na.rm = TRUE)
  pass <- share_in_range > 0.95

  n_treated <- sum(treat_schedule_std$g_id > 0)
  share_treated <- n_treated / nrow(treat_schedule_std)

  passfail(pass,
           ifelse(pass, "Schedule OK", glue("Only {signif(share_in_range*100, 3)}% in range")),
           list(n_treated = n_treated, share_treated = signif(share_treated, 3)))
})

################################################################################
# TEST 3: Untreated baseline correctness
################################################################################
report <- add_test(report, "Baseline post-treatment contamination", function() {
  # After residualization, g_id is removed to prevent treatment leakage
  # We need to rejoin with the treatment schedule to check for contamination

  baseline_with_sched <- baseline %>%
    left_join(treat_schedule_std %>% select(unit_id, g_id), by = "unit_id")

  # Check treated units only (g_id > 0)
  # For these units, all time_id should be < g_id (pre-treatment only)
  baseline_treated <- baseline_with_sched %>%
    filter(!is.na(g_id), g_id > 0)

  if (nrow(baseline_treated) == 0) {
    return(passfail(TRUE, "No treated units in baseline", list(baseline_rows = nrow(baseline))))
  }

  n_violations <- sum(baseline_treated$time_id >= baseline_treated$g_id, na.rm = TRUE)
  pass <- n_violations == 0

  passfail(pass,
           ifelse(pass, "No contamination", glue("{n_violations} violations")),
           list(violations = n_violations, baseline_rows = nrow(baseline)))
})

################################################################################
# TEST 4: Placebo assignment validity
################################################################################
report <- add_test(report, "Placebo window constraints", function() {
  placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline,
                                    n_switchers = NULL, unit_state_map = unit_state_map)

  baseline_ranges <- baseline %>%
    group_by(unit_id) %>%
    summarise(min_t = min(time_id), max_t = max(time_id))

  placebo_check <- placebo %>%
    filter(g_placebo > 0) %>%
    left_join(baseline_ranges, by = "unit_id") %>%
    mutate(
      min_allowed = min_t + cfg$pre_len,
      max_allowed = max_t - cfg$post_len,
      violation = g_placebo < min_allowed | g_placebo > max_allowed
    )

  n_violations <- sum(placebo_check$violation, na.rm = TRUE)

  n_treated_clusters <- if (!is.null(unit_state_map)) {
    placebo_check %>%
      left_join(unit_state_map, by = "unit_id") %>%
      pull(state_abb) %>%
      n_distinct()
  } else {
    n_distinct(placebo_check$unit_id)
  }

  # Require at least 2 treated clusters (needed for valid DiD estimation)
  pass <- n_violations == 0 && n_treated_clusters >= 2

  passfail(pass,
           ifelse(pass, "Windows OK", glue("{n_violations} violations")),
           list(violations = n_violations, n_treated_clusters = n_treated_clusters))
})

################################################################################
# TEST 5: Effect imposition algebra
################################################################################
report <- add_test(report, "Effect imposition logic", function() {
  placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline,
                                    n_switchers = NULL, unit_state_map = unit_state_map)

  df_sim <- impose_effect(baseline, placebo, effect_size = 1, cfg)

  check <- df_sim %>%
    mutate(
      delta = outcome_sim - outcome,
      # Never-treated units have NA event_time, should be D=0
      D = if_else(is.na(event_time), 0L, as.integer(event_time >= 0))
    )

  # Check delta == 0 when D == 0
  check_untreated <- check %>% filter(D == 0)
  prop_fail_untreated <- mean(abs(check_untreated$delta) > 1e-10, na.rm = TRUE)

  # Check based on effect_shape
  if (cfg$effect_shape == "step") {
    check_treated <- check %>% filter(D == 1)
    prop_fail_treated <- mean(abs(check_treated$delta - 1) > 1e-10, na.rm = TRUE)
    detail_msg <- glue("step: untreated={signif(prop_fail_untreated, 3)}, treated={signif(prop_fail_treated, 3)}")
  } else if (cfg$effect_shape == "delayed") {
    check_delayed <- check %>% filter(D == 1, event_time < cfg$delay_h)
    prop_fail_delayed <- mean(abs(check_delayed$delta) > 1e-10, na.rm = TRUE)

    check_post <- check %>% filter(D == 1, event_time >= cfg$delay_h)
    prop_fail_post <- mean(abs(check_post$delta - 1) > 1e-10, na.rm = TRUE)

    prop_fail_treated <- max(prop_fail_delayed, prop_fail_post)
    detail_msg <- glue("delayed: untreated={signif(prop_fail_untreated, 3)}, pre-delay={signif(prop_fail_delayed, 3)}")
  } else if (cfg$effect_shape == "ramp") {
    check_ramp <- check %>%
      filter(D == 1) %>%
      arrange(event_time) %>%
      mutate(delta_lag = lag(delta, default = 0))

    prop_fail_mono <- mean(check_ramp$delta < check_ramp$delta_lag - 1e-6, na.rm = TRUE)
    prop_fail_treated <- prop_fail_mono
    detail_msg <- glue("ramp: untreated={signif(prop_fail_untreated, 3)}, non-mono={signif(prop_fail_mono, 3)}")
  } else {
    prop_fail_treated <- NA
    detail_msg <- "unknown effect_shape"
  }

  pass <- prop_fail_untreated < 0.01 && (is.na(prop_fail_treated) || prop_fail_treated < 0.01)

  passfail(pass,
           ifelse(pass, "Algebra OK", detail_msg),
           list(shape = cfg$effect_shape, untreated_fail = signif(prop_fail_untreated, 3)))
})

################################################################################
# TEST 6: did-input remap sanity
################################################################################
report <- add_test(report, "DID input remapping", function() {
  placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline,
                                    n_switchers = NULL, unit_state_map = unit_state_map)
  df_sim <- impose_effect(baseline, placebo, effect_size = 1, cfg)

  # Recreate remapping logic (must match run_estimator_and_extract_p exactly)
  time_mapping <- df_sim %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  # Remap g_placebo values to sequential scale (only for treated units)
  g_mapping <- df_sim %>%
    filter(!is.na(g_placebo) & g_placebo > 0L) %>%
    distinct(g_placebo) %>%
    left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
    transmute(g_placebo, g_placebo_seq = time_id_seq)

  g_vals <- df_sim %>%
    distinct(unit_id, g_placebo) %>%
    left_join(g_mapping, by = "g_placebo") %>%
    mutate(
      # Create gname: 0 for never-treated, sequential time_id for treated
      gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0L, coalesce(g_placebo_seq, 0L))
    )

  T_max <- max(time_mapping$time_id_seq)
  is_contiguous <- all(time_mapping$time_id_seq == 1:T_max)

  valid_gname <- all(g_vals$gname == 0 | (g_vals$gname >= 1 & g_vals$gname <= T_max))

  n_treated <- sum(g_vals$gname > 0)
  n_never <- sum(g_vals$gname == 0)

  pass <- is_contiguous && valid_gname && n_treated >= 2 && n_never >= 2

  passfail(pass,
           ifelse(pass, "Remap OK", glue("contiguous={is_contiguous}, valid={valid_gname}, n_tr={n_treated}, n_nev={n_never}")),
           list(T = T_max, n_treated = n_treated, n_never = n_never))
})

################################################################################
# TEST 7: Size calibration (Type I error)
################################################################################
report <- add_test(report, "Type I error calibration", function() {
  n_sims <- CHECK_N_SIMS
  alpha <- CHECK_ALPHA

  p_values <- map_dbl(1:n_sims, function(i) {
    if (i %% 50 == 0) cat(".")

    tryCatch({
      placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline,
                                        n_switchers = NULL, unit_state_map = unit_state_map)
      df_sim <- impose_effect(baseline, placebo, effect_size = 0, cfg)
      result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
      # Extract p-value from list result
      if (is.list(result)) result$p else NA_real_
    }, error = function(e) NA_real_)
  })

  cat("\n")

  na_rate <- mean(is.na(p_values))
  rejection_rate <- mean(p_values <= alpha, na.rm = TRUE)

  pass <- rejection_rate >= (alpha - 0.02) && rejection_rate <= (alpha + 0.02)

  passfail(pass,
           ifelse(pass, glue("Rejection={signif(rejection_rate, 3)}"),
                  glue("Rejection={signif(rejection_rate, 3)} outside [{alpha-0.02}, {alpha+0.02}]")),
           list(rejection_rate = signif(rejection_rate, 3), na_rate = signif(na_rate, 3)))
})

################################################################################
# TEST 8: Power monotonicity
################################################################################
report <- add_test(report, "Power monotonicity", function() {
  effects <- CHECK_EFFECTS
  n_sims <- CHECK_N_SIMS
  alpha <- CHECK_ALPHA

  powers <- map_dbl(effects, function(eff) {
    cat(glue("  Effect {eff}..."))

    p_values <- map_dbl(1:n_sims, function(i) {
      tryCatch({
        placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline,
                                          n_switchers = NULL, unit_state_map = unit_state_map)
        df_sim <- impose_effect(baseline, placebo, effect_size = eff, cfg)
        result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
        # Extract p-value from list result
        if (is.list(result)) result$p else NA_real_
      }, error = function(e) NA_real_)
    })

    power <- mean(p_values <= alpha, na.rm = TRUE)
    cat(glue(" power={signif(power, 3)}\n"))
    power
  })

  # Check monotonicity: allow 1 violation by <= 0.05
  violations <- which(diff(powers) < -0.05)
  n_violations <- length(violations)

  pass <- n_violations <= 1

  powers_str <- paste(signif(powers, 3), collapse = ", ")

  passfail(pass,
           ifelse(pass, glue("Powers: {powers_str}"), glue("{n_violations} violations: {powers_str}")),
           list(powers = powers_str, n_violations = n_violations))
})

################################################################################
# TEST 9: Grid sanity
################################################################################
report <- add_test(report, "Grid n_states/n_switchers impact", function() {
  if (cfg$cluster_level != "state" || is.null(unit_state_map)) {
    return(passfail(TRUE, "SKIP: not state-level clustering", list(skipped = "yes")))
  }

  available_states <- n_distinct(baseline[[cluster_var]])

  if (available_states < 10) {
    return(passfail(TRUE, glue("SKIP: only {available_states} states"), list(n_states = available_states)))
  }

  # Scenario A: small
  n_states_A <- min(10, available_states)
  n_switchers_A <- min(3, n_states_A - 1)

  # Scenario B: large
  n_states_B <- available_states
  n_switchers_B <- min(12, n_states_B - 1)

  run_scenario <- function(n_states, n_switchers) {
    baseline_subset <- baseline %>%
      group_by(!!sym(cluster_var)) %>%
      filter(cur_group_id() <= n_states) %>%
      ungroup()

    p_values <- map_dbl(1:100, function(i) {
      tryCatch({
        placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline_subset,
                                          n_switchers = n_switchers, unit_state_map = unit_state_map)
        df_sim <- impose_effect(baseline_subset, placebo, effect_size = 1, cfg)
        result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
        # Extract p-value from list result
        if (is.list(result)) result$p else NA_real_
      }, error = function(e) NA_real_)
    })

    mean(p_values <= CHECK_ALPHA, na.rm = TRUE)
  }

  cat(glue("  Scenario A: {n_states_A} states, {n_switchers_A} switchers...\n"))
  power_A <- run_scenario(n_states_A, n_switchers_A)

  cat(glue("  Scenario B: {n_states_B} states, {n_switchers_B} switchers...\n"))
  power_B <- run_scenario(n_states_B, n_switchers_B)

  pass <- power_B >= power_A - 0.05

  passfail(pass,
           ifelse(pass, glue("A={signif(power_A, 3)}, B={signif(power_B, 3)}"),
                  glue("B < A: {signif(power_B, 3)} < {signif(power_A, 3)}")),
           list(power_A = signif(power_A, 3), power_B = signif(power_B, 3)))
})

################################################################################
# TEST 10: NA monitoring (integrated into tests 7-8)
################################################################################
# Already tracked in test 7, just add a summary test
report <- add_test(report, "NA rate monitoring", function() {
  # Re-extract from test 7
  test7 <- report %>% filter(test_name == "Type I error calibration")

  if (nrow(test7) == 0) {
    return(passfail(FALSE, "Test 7 not found", list()))
  }

  na_rate <- as.numeric(test7$metric2_value)
  pass <- na_rate < 0.20

  passfail(pass,
           ifelse(pass, glue("NA rate={signif(na_rate, 3)}"), glue("High NA rate: {signif(na_rate, 3)}")),
           list(na_rate = signif(na_rate, 3), threshold = 0.20))
})

################################################################################
# Print summary and save report
################################################################################
cat("\n=== DIAGNOSTIC SUMMARY ===\n")
for (i in 1:nrow(report)) {
  status <- ifelse(report$pass[i], "\033[32mPASS\033[0m", "\033[31mFAIL\033[0m")
  cat(glue("{i}. {status} - {report$test_name[i]}: {report$detail[i]}\n"))
}

write_csv(report, "check_report.csv")
cat(glue("\nReport saved to check_report.csv\n"))

# Determine exit code
core_tests <- c("Treatment schedule integrity",
                "Baseline post-treatment contamination",
                "Placebo window constraints",
                "DID input remapping",
                "Type I error calibration")

core_failures <- report %>%
  filter(test_name %in% core_tests, !pass) %>%
  nrow()

if (core_failures > 0) {
  cat(glue("\n\033[31mFAILED: {core_failures} core test(s) failed\033[0m\n"))
  quit(status = 1)
} else {
  total_failures <- sum(!report$pass)
  if (total_failures > 0) {
    cat(glue("\n\033[33mWARNING: {total_failures} non-core test(s) failed\033[0m\n"))
  } else {
    cat("\n\033[32mALL TESTS PASSED\033[0m\n")
  }
  quit(status = 0)
}
