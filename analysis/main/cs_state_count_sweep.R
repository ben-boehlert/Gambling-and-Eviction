#!/usr/bin/env Rscript
################################################################################
# cs_state_count_sweep.R
#
# Sweep over different pre-treatment data thresholds to vary the number of
# states in a CS-DiD power simulation. Goals:
#   1. Find the minimum number of states for ~5% Type I error (effect=0)
#   2. Compute the 80% MDE at that state count
#
# Inclusion rule (transparent, reviewer-friendly):
#   Include a state if it has >= X months of pre-treatment data.
#   - Treated states: months of data before their treatment date
#   - Never-treated states: total months of data
#
# Hard exclusions: ME, ID (documented data quality issues)
#
# Supports both treatment definitions from Hollenbeck et al.:
#   - first_start_date ("General Access")
#   - online_start_date ("Online Access")
#
# Usage: Rscript analysis/main/cs_state_count_sweep.R
#        (run from project root)
#
# Outputs saved to: output/cs_state_sweep/
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(did)
  library(glue)
  library(future)
  library(furrr)
  library(progressr)
})

################################################################################
# 0) CONFIG & SOURCE
################################################################################

# Source power_simulation_cs.R in library mode (functions only, no execution)
POWER_SIM_LIBRARY_MODE <- TRUE
source("power_simulation_cs.R")

set.seed(20260212)
handlers(global = TRUE)
handlers("txtprogressbar")
options(progressr.enable = TRUE)

# Override cfg for state-level panel
cfg$panel_choice  <- "states_from_counties"
cfg$cluster_level <- "state"
cfg$estimand      <- "overall_att"
cfg$did_bstrap    <- TRUE
cfg$did_biters    <- 50L

# Sweep configuration
sweep_cfg <- list(
  treat_definitions   = c("first_start_date", "online_start_date"),
  pre_treat_thresholds = c(6L, 12L, 18L, 24L, 30L, 36L, 48L, 60L, 72L, 84L, 96L),
  n_sims              = 50L,
  alpha               = 0.05,
  power_target        = 0.80,
  hard_exclude        = c("ME", "ID"),
  # Finer effect grid for MDE determination at optimal threshold
  mde_effect_grid     = c(0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5),
  out_dir             = "output/cs_state_sweep"
)

dir.create(sweep_cfg$out_dir, recursive = TRUE, showWarnings = FALSE)

message(glue("Output directory: {sweep_cfg$out_dir}"))
message(glue("Treatment definitions: {paste(sweep_cfg$treat_definitions, collapse=', ')}"))
message(glue("Pre-treatment thresholds: {paste(sweep_cfg$pre_treat_thresholds, collapse=', ')} months"))
message(glue("Hard exclusions: {paste(sweep_cfg$hard_exclude, collapse=', ')}"))
message(glue("Sims per threshold: {sweep_cfg$n_sims}"))

################################################################################
# 1) COMPUTE PRE-TREATMENT MONTHS PER STATE
################################################################################

compute_pretreat_months <- function(panel_df, treat_schedule_std) {
  # Get state_abb for each unit
  unit_state <- panel_df %>%
    distinct(unit_id, state_abb)

  # Get treatment info per unit
  treat_info <- treat_schedule_std %>%
    left_join(unit_state, by = "unit_id")

  # For each state: count months of data, and months before treatment

  state_months <- panel_df %>%
    group_by(state_abb) %>%
    summarise(
      total_months = n(),
      min_time_id  = min(time_id),
      max_time_id  = max(time_id),
      .groups = "drop"
    )

  state_treat <- treat_info %>%
    select(state_abb, g_id, ever_treated) %>%
    distinct()

  state_months %>%
    left_join(state_treat, by = "state_abb") %>%
    mutate(
      # Pre-treatment months:
      #   treated: months of data strictly before g_id
      #   never-treated: all months of data
      pre_treat_months = if_else(
        ever_treated & g_id > 0L,
        pmax(0L, as.integer(g_id - min_time_id)),
        total_months
      )
    )
}

################################################################################
# 2) APPLY THRESHOLD AND FILTER STATES
################################################################################

filter_states_by_threshold <- function(panel_df, treat_schedule_std,
                                       threshold, hard_exclude) {
  pretreat <- compute_pretreat_months(panel_df, treat_schedule_std)

  # Apply hard exclusions and threshold
  surviving <- pretreat %>%
    filter(!state_abb %in% hard_exclude) %>%
    filter(pre_treat_months >= threshold)

  n_treated   <- sum(surviving$ever_treated & surviving$g_id > 0L)
  n_untreated <- sum(!surviving$ever_treated | surviving$g_id == 0L)
  n_total     <- nrow(surviving)

  # Feasibility check: CS estimator needs at least 2 treated + 2 never-treated
  if (n_treated < 2 || n_untreated < 2) {
    return(list(
      feasible = FALSE,
      n_states = n_total,
      n_treated = n_treated,
      n_untreated = n_untreated,
      states = surviving$state_abb
    ))
  }

  # Filter panel and treatment schedule to surviving states
  surviving_units <- panel_df %>%
    filter(state_abb %in% surviving$state_abb) %>%
    pull(unit_id) %>%
    unique()

  panel_sub <- panel_df %>%
    filter(unit_id %in% surviving_units)

  treat_sub <- treat_schedule_std %>%
    filter(unit_id %in% surviving_units)

  list(
    feasible        = TRUE,
    panel_df        = panel_sub,
    treat_schedule  = treat_sub,
    n_states        = n_total,
    n_treated       = n_treated,
    n_untreated     = n_untreated,
    states          = sort(surviving$state_abb),
    pretreat_detail = surviving
  )
}

################################################################################
# 3) SWEEP LOOP (TYPE I ERROR)
################################################################################

run_sweep <- function(cfg_base, sweep_cfg) {
  all_results <- list()

  for (treat_def in sweep_cfg$treat_definitions) {
    message(glue("\n{strrep('=', 60)}"))
    message(glue("Sweeping treatment definition: {treat_def}"))
    message(glue("{strrep('=', 60)}\n"))

    # Set treatment definition
    cfg_td <- cfg_base
    cfg_td$treat_date_col <- treat_def
    cfg_td$n_sims         <- sweep_cfg$n_sims
    cfg_td$alpha          <- sweep_cfg$alpha
    cfg_td$effect_grid    <- c(0)  # Type I error only

    # Load panel once per treatment definition
    panel_df <- load_panel(cfg_td)
    treat_schedule <- make_treat_schedule(panel_df, cfg_td)
    treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

    # Compute and save pre-treatment months
    pretreat_all <- compute_pretreat_months(panel_df, treat_schedule_std) %>%
      filter(!state_abb %in% sweep_cfg$hard_exclude) %>%
      arrange(desc(pre_treat_months))

    write_csv(
      pretreat_all,
      file.path(sweep_cfg$out_dir, glue("state_pretreat_months_{treat_def}.csv"))
    )

    message(glue("\nPre-treatment months per state ({treat_def}):"))
    print(pretreat_all %>% select(state_abb, ever_treated, total_months, pre_treat_months))

    # Determine cluster_var
    cluster_var <- if ("state_abb" %in% names(panel_df)) "state_abb" else "unit_id"

    sweep_results <- list()

    for (i in seq_along(sweep_cfg$pre_treat_thresholds)) {
      threshold <- sweep_cfg$pre_treat_thresholds[i]

      message(glue("\n--- {treat_def}: threshold = {threshold} months ({i}/{length(sweep_cfg$pre_treat_thresholds)}) ---"))

      # Filter states
      filtered <- filter_states_by_threshold(
        panel_df, treat_schedule_std,
        threshold = threshold,
        hard_exclude = sweep_cfg$hard_exclude
      )

      if (!filtered$feasible) {
        message(glue("  SKIPPED: only {filtered$n_treated} treated + {filtered$n_untreated} never-treated (need >=2 each)"))
        sweep_results[[i]] <- tibble(
          treat_definition       = treat_def,
          pre_treat_threshold    = threshold,
          n_states               = filtered$n_states,
          n_treated              = filtered$n_treated,
          n_never_treated        = filtered$n_untreated,
          rejection_rate_effect0 = NA_real_,
          mean_se                = NA_real_,
          states_included        = paste(filtered$states, collapse = ";"),
          status                 = "infeasible"
        )
        next
      }

      message(glue("  States: {filtered$n_states} ({filtered$n_treated} treated + {filtered$n_untreated} never-treated)"))
      message(glue("  Included: {paste(filtered$states, collapse=', ')}"))

      # Run CS simulation with effect=0
      sim_result <- tryCatch({
        simulate_power(
          filtered$panel_df,
          filtered$treat_schedule,
          option      = "A1",
          cfg         = cfg_td,
          cluster_var = cluster_var
        )
      }, error = function(e) {
        message(glue("  ERROR: {conditionMessage(e)}"))
        NULL
      })

      if (is.null(sim_result)) {
        sweep_results[[i]] <- tibble(
          treat_definition       = treat_def,
          pre_treat_threshold    = threshold,
          n_states               = filtered$n_states,
          n_treated              = filtered$n_treated,
          n_never_treated        = filtered$n_untreated,
          rejection_rate_effect0 = NA_real_,
          mean_se                = NA_real_,
          states_included        = paste(filtered$states, collapse = ";"),
          status                 = "sim_error"
        )
        next
      }

      rej_rate <- sim_result %>% filter(effect_size == 0) %>% pull(power)
      mean_se  <- sim_result %>% filter(effect_size == 0) %>% pull(mean_se)

      message(glue("  Rejection rate at effect=0: {round(rej_rate, 3)} (mean SE: {round(mean_se, 4)})"))

      sweep_results[[i]] <- tibble(
        treat_definition       = treat_def,
        pre_treat_threshold    = threshold,
        n_states               = filtered$n_states,
        n_treated              = filtered$n_treated,
        n_never_treated        = filtered$n_untreated,
        rejection_rate_effect0 = rej_rate,
        mean_se                = mean_se,
        states_included        = paste(filtered$states, collapse = ";"),
        status                 = "ok"
      )

      # Checkpoint
      partial <- bind_rows(sweep_results)
      write_csv(partial, file.path(sweep_cfg$out_dir, glue("sweep_partial_{treat_def}.csv")))
    }

    sweep_df <- bind_rows(sweep_results)
    write_csv(sweep_df, file.path(sweep_cfg$out_dir, glue("sweep_results_{treat_def}.csv")))
    all_results[[treat_def]] <- sweep_df
  }

  bind_rows(all_results)
}

################################################################################
# 4) FIND OPTIMAL THRESHOLD & COMPUTE MDE
################################################################################

find_optimal_and_compute_mde <- function(sweep_results_all, cfg_base, sweep_cfg) {
  mde_results <- list()

  for (treat_def in sweep_cfg$treat_definitions) {
    sweep_df <- sweep_results_all %>%
      filter(treat_definition == treat_def, status == "ok")

    if (nrow(sweep_df) == 0) {
      message(glue("\nNo successful sweeps for {treat_def}, skipping MDE."))
      next
    }

    # Find smallest threshold (= most states) where rejection rate is within
    # acceptable range of 5% (between 2% and 10%)
    target <- sweep_cfg$alpha
    candidates <- sweep_df %>%
      filter(rejection_rate_effect0 >= 0.02, rejection_rate_effect0 <= 0.10) %>%
      arrange(pre_treat_threshold)

    if (nrow(candidates) == 0) {
      message(glue("\nNo threshold achieves 2-10% rejection for {treat_def}."))
      message("  Using threshold closest to 5% rejection rate.")
      optimal_row <- sweep_df %>%
        arrange(abs(rejection_rate_effect0 - target)) %>%
        slice(1)
    } else {
      # Take the smallest threshold (most states) within the acceptable range
      optimal_row <- candidates %>% slice(1)
    }

    opt_threshold <- optimal_row$pre_treat_threshold
    message(glue("\n=== Optimal threshold for {treat_def}: {opt_threshold} months ==="))
    message(glue("  States: {optimal_row$n_states} ({optimal_row$n_treated}T + {optimal_row$n_never_treated}C)"))
    message(glue("  Rejection rate: {round(optimal_row$rejection_rate_effect0, 3)}"))

    # Re-run with full effect grid for MDE
    cfg_mde <- cfg_base
    cfg_mde$treat_date_col <- treat_def
    cfg_mde$n_sims         <- sweep_cfg$n_sims
    cfg_mde$alpha          <- sweep_cfg$alpha
    cfg_mde$effect_grid    <- sweep_cfg$mde_effect_grid

    panel_df <- load_panel(cfg_mde)
    treat_schedule <- make_treat_schedule(panel_df, cfg_mde)
    treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

    filtered <- filter_states_by_threshold(
      panel_df, treat_schedule_std,
      threshold    = opt_threshold,
      hard_exclude = sweep_cfg$hard_exclude
    )

    if (!filtered$feasible) {
      message(glue("  Cannot rebuild panel at threshold={opt_threshold}. Skipping."))
      next
    }

    cluster_var <- if ("state_abb" %in% names(filtered$panel_df)) "state_abb" else "unit_id"

    message(glue("\nRunning full power curve for MDE ({length(sweep_cfg$mde_effect_grid)} effect sizes x {sweep_cfg$n_sims} sims)..."))

    power_result <- tryCatch({
      simulate_power(
        filtered$panel_df,
        filtered$treat_schedule,
        option      = "A1",
        cfg         = cfg_mde,
        cluster_var = cluster_var
      )
    }, error = function(e) {
      message(glue("  MDE simulation failed: {conditionMessage(e)}"))
      NULL
    })

    if (is.null(power_result)) next

    mde_80 <- compute_mde(power_result, power_target = sweep_cfg$power_target)

    message(glue("\n  MDE at 80% power: {round(mde_80, 3)} outcome units"))

    mde_row <- tibble(
      treat_definition       = treat_def,
      optimal_threshold      = opt_threshold,
      n_states               = optimal_row$n_states,
      n_treated              = optimal_row$n_treated,
      n_never_treated        = optimal_row$n_never_treated,
      rejection_rate_effect0 = optimal_row$rejection_rate_effect0,
      mde_80                 = mde_80,
      states_included        = optimal_row$states_included
    )

    mde_results[[treat_def]] <- mde_row

    write_csv(power_result, file.path(sweep_cfg$out_dir, glue("power_curve_data_{treat_def}.csv")))
    write_csv(mde_row, file.path(sweep_cfg$out_dir, glue("mde_results_{treat_def}.csv")))
  }

  if (length(mde_results) > 0) bind_rows(mde_results) else tibble()
}

################################################################################
# 5) VISUALIZATION
################################################################################

plot_sweep_results <- function(sweep_results_all, sweep_cfg) {
  ok_results <- sweep_results_all %>% filter(status == "ok")
  if (nrow(ok_results) == 0) {
    message("No successful sweep results to plot.")
    return(invisible(NULL))
  }

  # Combined plot: both treatment definitions
  p_all <- ok_results %>%
    ggplot(aes(x = pre_treat_threshold, y = rejection_rate_effect0,
               color = treat_definition)) +
    geom_line(linewidth = 1) +
    geom_point(size = 3) +
    geom_hline(yintercept = 0.05, linetype = "dashed", color = "red") +
    geom_hline(yintercept = 0.10, linetype = "dotted", color = "orange", alpha = 0.6) +
    scale_y_continuous(
      limits = c(0, max(0.20, max(ok_results$rejection_rate_effect0, na.rm = TRUE) * 1.1)),
      labels = scales::percent_format(accuracy = 1)
    ) +
    labs(
      title    = "CS-DiD Type I Error by Pre-Treatment Data Threshold",
      subtitle = glue("n_sims={sweep_cfg$n_sims} | alpha={sweep_cfg$alpha} | Hard exclude: {paste(sweep_cfg$hard_exclude, collapse=', ')}"),
      x        = "Minimum Pre-Treatment Months Required",
      y        = "Rejection Rate at Effect = 0",
      color    = "Treatment Definition"
    ) +
    theme_minimal(base_size = 13) +
    theme(legend.position = "bottom")

  ggsave(file.path(sweep_cfg$out_dir, "sweep_curve_all.png"), p_all,
         width = 10, height = 6, dpi = 300)

  # Individual plots per treatment definition
  for (treat_def in sweep_cfg$treat_definitions) {
    df_td <- ok_results %>% filter(treat_definition == treat_def)
    if (nrow(df_td) == 0) next

    p <- df_td %>%
      ggplot(aes(x = pre_treat_threshold, y = rejection_rate_effect0)) +
      geom_line(linewidth = 1, color = "steelblue") +
      geom_point(size = 3, color = "steelblue") +
      geom_hline(yintercept = 0.05, linetype = "dashed", color = "red") +
      geom_text(
        aes(label = glue("{n_states}st\n({n_treated}T/{n_never_treated}C)")),
        vjust = -0.8, size = 2.8, color = "gray30"
      ) +
      scale_y_continuous(
        limits = c(0, max(0.20, max(df_td$rejection_rate_effect0, na.rm = TRUE) * 1.2)),
        labels = scales::percent_format(accuracy = 1)
      ) +
      labs(
        title    = glue("CS-DiD Type I Error: {treat_def}"),
        subtitle = glue("n_sims={sweep_cfg$n_sims} | Labels: N states (Treated/Control)"),
        x        = "Minimum Pre-Treatment Months Required",
        y        = "Rejection Rate (effect = 0)"
      ) +
      theme_minimal(base_size = 12)

    ggsave(file.path(sweep_cfg$out_dir, glue("sweep_curve_{treat_def}.png")), p,
           width = 9, height = 6, dpi = 300)
  }
}

plot_power_curves <- function(sweep_cfg) {
  for (treat_def in sweep_cfg$treat_definitions) {
    power_file <- file.path(sweep_cfg$out_dir, glue("power_curve_data_{treat_def}.csv"))
    mde_file   <- file.path(sweep_cfg$out_dir, glue("mde_results_{treat_def}.csv"))

    if (!file.exists(power_file) || !file.exists(mde_file)) next

    power_df <- read_csv(power_file, show_col_types = FALSE)
    mde_df   <- read_csv(mde_file, show_col_types = FALSE)

    mde_val <- mde_df$mde_80[1]

    p <- power_df %>%
      ggplot(aes(x = effect_size, y = power)) +
      geom_line(linewidth = 1, color = "steelblue") +
      geom_point(size = 2, color = "steelblue") +
      geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray40") +
      {if (is.finite(mde_val)) geom_vline(xintercept = mde_val, linetype = "dotted", color = "darkred")} +
      {if (is.finite(mde_val)) annotate("text", x = mde_val, y = 0.1,
               label = glue("MDE = {round(mde_val, 2)}"),
               hjust = -0.1, color = "darkred", size = 4)} +
      scale_y_continuous(limits = c(0, 1)) +
      labs(
        title    = glue("CS-DiD Power Curve ({treat_def})"),
        subtitle = glue("{mde_df$n_states[1]} states ({mde_df$n_treated[1]}T + {mde_df$n_never_treated[1]}C) | threshold={mde_df$optimal_threshold[1]}mo | n_sims={sweep_cfg$n_sims}"),
        x        = "Imposed Effect Size (outcome units)",
        y        = "Power (Pr[p <= alpha])"
      ) +
      theme_minimal(base_size = 12)

    ggsave(file.path(sweep_cfg$out_dir, glue("power_curve_{treat_def}.png")), p,
           width = 8, height = 5, dpi = 300)
  }
}

################################################################################
# 6) EXECUTION
################################################################################

# Set up parallel workers
if (cfg$use_parallel) {
  plan(multisession, workers = cfg$workers)
  message(glue("\nParallel ON: workers = {cfg$workers}"))
} else {
  plan(sequential)
  message("\nParallel OFF")
}

# Run the sweep
message("\n========== STARTING SWEEP ==========\n")
sweep_results <- run_sweep(cfg, sweep_cfg)

# Save combined results
write_csv(sweep_results, file.path(sweep_cfg$out_dir, "sweep_results_all.csv"))

# Print sweep summary
message("\n========== SWEEP SUMMARY ==========")
sweep_results %>%
  filter(status == "ok") %>%
  select(treat_definition, pre_treat_threshold, n_states, n_treated,
         n_never_treated, rejection_rate_effect0) %>%
  print(n = 50)

# Find optimal thresholds and compute MDEs
message("\n========== COMPUTING MDEs ==========\n")
mde_results <- find_optimal_and_compute_mde(sweep_results, cfg, sweep_cfg)

if (nrow(mde_results) > 0) {
  write_csv(mde_results, file.path(sweep_cfg$out_dir, "mde_results_all.csv"))
  message("\n========== MDE RESULTS ==========")
  mde_results %>%
    select(treat_definition, optimal_threshold, n_states, n_treated,
           n_never_treated, rejection_rate_effect0, mde_80) %>%
    print()
}

# Generate plots
message("\n========== GENERATING PLOTS ==========")
plot_sweep_results(sweep_results, sweep_cfg)
plot_power_curves(sweep_cfg)

message(glue("\nAll outputs saved to: {sweep_cfg$out_dir}/"))
message("Done.")

################################################################################
# END
################################################################################
