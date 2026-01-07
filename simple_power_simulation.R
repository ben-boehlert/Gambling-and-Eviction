#!/usr/bin/env Rscript
################################################################################
# simple_power_simulation.R
#
# A straightforward power simulation for staggered DiD using Callaway-Sant'Anna
# Every step is documented and easy to understand
#
# What this does:
#   1. Load your real eviction data
#   2. Add fake treatment effects of different sizes
#   3. Run DiD estimation (Callaway-Sant'Anna)
#   4. Check how often we correctly detect the effect
#   5. Report the Minimum Detectable Effect (MDE) for your grant
#
# Runtime: ~30 minutes for 100 simulations
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(did)        # Callaway-Sant'Anna DiD
  library(fixest)     # For fixed effects
  library(glue)
})

set.seed(20250105)  # For reproducibility

################################################################################
# STEP 1: CONFIGURATION
################################################################################

cat("=== Simple Power Simulation for Grant Application ===\n\n")

# Allow external config to override defaults
if (!exists("config")) {
  config <- list(
    # Which period to analyze?
    period = "precovid",  # "precovid" or "postcovid"

    # How many simulations per effect size?
    n_sims = 100,  # Increase to 500 for final version

    # What effect sizes to test? (filings per 1,000 renters)
    effect_sizes = c(0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0),

    # Statistical significance level
    alpha = 0.05,

    # Target power (probability of detecting a real effect)
    target_power = 0.80,

    # Bootstrap settings for inference
    n_bootstrap = 50,  # CS default; increase to 199 for final version

    # Control group specification (Roth et al. 2023 recommendation)
    # "nevertreated" = more robust to pre-trends violations (recommended)
    # "notyettreated" = more efficient but assumes parallel trends hold
    control_group = "nevertreated",

    # Output file
    output_file = "simple_power_results.csv"
  )
}

cat(glue("Period: {config$period}\n"))
cat(glue("Simulations per effect size: {config$n_sims}\n"))
cat(glue("Effect sizes tested: {paste(config$effect_sizes, collapse=', ')}\n"))
cat(glue("Significance level: {config$alpha}\n"))
cat(glue("Target power: {config$target_power}\n"))
cat(glue("Control group: {config$control_group}\n\n"))

################################################################################
# STEP 2: LOAD AND PREPARE DATA
################################################################################

cat("=== Loading Data ===\n")

# Initialize cfg for power_simulation_cs.R if not already defined
if (!exists("cfg")) {
  cfg <- list(
    data_dir = ".",
    panel_choice = "states_from_counties",
    outcome_preference = c(
      "filings_per_1k_renters",
      "filings_count_per_1k_renters",
      "filings_count"
    ),
    weights_var = "renter_occupied_housing_units",
    treat_date_col = "online_start_date"
  )
}

# Load the panel data
source("power_simulation_cs.R")
panel <- load_panel(cfg)

# Filter by period
if (config$period == "precovid") {
  panel <- panel %>%
    filter(month_date >= as.Date("2016-01-01"),
           month_date < as.Date("2020-03-01"))
  cat("Using Pre-COVID period: 2016-01 to 2020-02\n")
} else if (config$period == "postcovid") {
  panel <- panel %>%
    filter(month_date >= as.Date("2021-01-01")) %>%
    # Exclude COVID-disruption states
    filter(!(state_abb %in% c("CO", "DC", "IL", "TN", "MI", "VA")))
  cat("Using Post-COVID period: 2021-01 to 2025-09\n")
  cat("Excluding COVID-disruption states: CO, DC, IL, TN, MI, VA\n")
} else {
  stop("config$period must be 'precovid' or 'postcovid'")
}

# Get treatment schedule
treat_schedule <- make_treat_schedule(panel, cfg)

# Merge treatment info
panel <- panel %>%
  left_join(
    treat_schedule %>% select(unit_id, g, ever_treated),
    by = "unit_id"
  )

cat(glue("\nPanel dimensions:\n"))
cat(glue("  Total observations: {nrow(panel)}\n"))
cat(glue("  States: {n_distinct(panel$state_abb)}\n"))
cat(glue("  Months: {n_distinct(panel$month_date)}\n"))
cat(glue("  Treated states: {sum(panel$ever_treated, na.rm=TRUE) / n_distinct(panel$month_date)}\n"))
cat(glue("  Control states: {sum(!panel$ever_treated, na.rm=TRUE) / n_distinct(panel$month_date)}\n\n"))

# Create numeric IDs for DiD package
panel <- panel %>%
  mutate(
    state_id = as.integer(factor(state_abb)),
    time_id = as.integer(factor(month_date))
  )

################################################################################
# STEP 3: RESIDUALIZE OUTCOMES
################################################################################
# Why? We want to add treatment effects to the "noise" part of the outcome,
# not to the part explained by state and time fixed effects.
################################################################################

cat("=== Residualizing Outcomes ===\n")
cat("Removing unit and time fixed effects from baseline outcome...\n")

# Use only untreated observations to estimate FE
# (This is standard practice to avoid contamination)
baseline_untreated <- panel %>%
  filter(!ever_treated | (ever_treated & month_date < g))

# Fit fixed effects model
fe_model <- feols(outcome ~ 1 | state_id + time_id, data = baseline_untreated)

# Get residuals
baseline_untreated <- baseline_untreated %>%
  mutate(
    outcome_resid = resid(fe_model),
    outcome_mean = mean(baseline_untreated$outcome, na.rm = TRUE)
  )

# Keep only what we need
baseline <- baseline_untreated %>%
  select(state_id, time_id, state_abb, month_date, outcome_resid, outcome_mean)

cat(glue("Residualized {nrow(baseline)} observations\n"))
cat(glue("Mean outcome: {round(mean(baseline$outcome_mean), 2)}\n"))
cat(glue("SD of residuals: {round(sd(baseline$outcome_resid, na.rm=TRUE), 2)}\n\n"))

################################################################################
# STEP 4: DEFINE SIMULATION FUNCTION
################################################################################

simulate_one_power <- function(effect_size, baseline, config, sim_id) {
  # Purpose: Test if we can detect a given effect size
  #
  # Steps:
  #   1. Randomly assign "placebo" treatment to some states
  #   2. Add fake treatment effect to treated units after treatment
  #   3. Run Callaway-Sant'Anna DiD
  #   4. Check if we reject null hypothesis

  # Step 1: Randomly assign placebo treatment
  states <- unique(baseline$state_abb)
  # Ensure we have at least 3 never-treated states for control group
  n_treated <- max(3, min(length(states) - 3, round(0.3 * length(states))))

  treated_states <- sample(states, n_treated)

  # Assign random treatment time periods (not dates, to match time_id)
  available_times <- baseline %>%
    distinct(month_date, time_id) %>%
    arrange(time_id)

  # Need at least 12 months before and after
  min_time <- min(available_times$time_id) + 12
  max_time <- max(available_times$time_id) - 12
  eligible_times <- available_times %>%
    filter(time_id >= min_time, time_id <= max_time)

  if (nrow(eligible_times) == 0) {
    return(list(
      sim_id = sim_id,
      effect_size = effect_size,
      p_value = NA,
      reject = NA,
      att_estimate = NA,
      att_se = NA,
      error = "Not enough time periods"
    ))
  }

  # Assign DIFFERENT treatment times to each treated state (staggered adoption)
  # Sample treatment times for each treated state
  treat_times <- eligible_times %>%
    slice_sample(n = min(length(treated_states), nrow(eligible_times)), replace = TRUE)

  # Create treatment assignment lookup
  treat_lookup <- tibble(
    state_abb = treated_states,
    g_numeric = treat_times$time_id[seq_along(treated_states)],
    placebo_g = treat_times$month_date[seq_along(treated_states)]
  )

  sim_data <- baseline %>%
    left_join(treat_lookup, by = "state_abb") %>%
    mutate(
      placebo_treated = !is.na(g_numeric),
      g_numeric = if_else(is.na(g_numeric), 0L, as.integer(g_numeric)),
      placebo_g = if_else(is.na(placebo_g), as.Date(NA), placebo_g)
    )

  # Step 2: Add treatment effect
  # Effect = effect_size * I(treated & post-treatment)
  sim_data <- sim_data %>%
    mutate(
      post_treatment = placebo_treated & month_date >= placebo_g,
      # Reconstruct outcome: mean + residual + treatment effect
      outcome_sim = outcome_mean + outcome_resid + if_else(post_treatment, effect_size, 0)
    )

  # Step 3: Run Callaway-Sant'Anna DiD
  # g_numeric already created above (matches time_id for treated, 0 for never-treated)

  # Debugging: check g_numeric values
  if (sim_id == 1 && effect_size == 0) {
    cat(sprintf("\n  DEBUG sim 1: g_numeric values: %s\n", paste(sort(unique(sim_data$g_numeric)), collapse=", ")))
    cat(sprintf("  DEBUG sim 1: time_id range: %d to %d\n", min(sim_data$time_id), max(sim_data$time_id)))
    cat(sprintf("  DEBUG sim 1: n_treated=%d, never_treated=%d\n",
                sum(sim_data$g_numeric > 0), sum(sim_data$g_numeric == 0)))
  }

  # Run att_gt
  tryCatch({
    cs_result <- att_gt(
      yname = "outcome_sim",
      tname = "time_id",
      idname = "state_id",
      gname = "g_numeric",
      data = as.data.frame(sim_data),
      control_group = config$control_group,  # Use configured control group
      bstrap = TRUE,
      biters = config$n_bootstrap,
      clustervars = "state_id",
      print_details = FALSE
    )

    # Aggregate to overall ATT
    cs_agg <- aggte(cs_result, type = "simple")

    # Extract p-value
    p_value <- cs_agg$overall.pval

    # Reject null?
    reject <- (p_value < config$alpha)

    return(list(
      sim_id = sim_id,
      effect_size = effect_size,
      p_value = p_value,
      reject = reject,
      att_estimate = cs_agg$overall.att,
      att_se = cs_agg$overall.se
    ))

  }, error = function(e) {
    # Print full error for first simulation
    if (sim_id == 1) {
      cat(sprintf("\n  FULL ERROR: %s\n", e$message))
    }
    return(list(
      sim_id = sim_id,
      effect_size = effect_size,
      p_value = NA,
      reject = NA,
      att_estimate = NA,
      att_se = NA,
      error = e$message
    ))
  })
}

################################################################################
# STEP 5: RUN SIMULATIONS
################################################################################

cat("=== Running Simulations ===\n")
cat("This will take approximately 30 minutes...\n\n")

results_list <- list()
counter <- 1

for (effect in config$effect_sizes) {
  cat(glue("Effect size: {effect} filings per 1,000 renters\n"))

  effect_results <- list()

  for (sim in 1:config$n_sims) {
    if (sim %% 10 == 0) {
      cat(glue("  Simulation {sim}/{config$n_sims}\n"))
    }

    result <- simulate_one_power(
      effect_size = effect,
      baseline = baseline,
      config = config,
      sim_id = sim
    )

    # Check if result is valid (not an error)
    if (!is.null(result) && length(result$p_value) > 0 && !is.na(result$p_value)) {
      effect_results[[sim]] <- result
    } else if (sim == 1) {
      # Debug first failure
      cat("  WARNING: First simulation failed. Result structure:\n")
      print(str(result))
    }
  }

  results_list[[counter]] <- bind_rows(effect_results)
  counter <- counter + 1

  cat("\n")
}

# Combine all results
# Filter out empty results and convert to data frame
all_results <- results_list %>%
  keep(~nrow(.) > 0) %>%  # Remove empty data frames
  bind_rows()

# Check if we have results
if (nrow(all_results) == 0) {
  cat("\n⚠️  ERROR: No valid simulation results.\n")
  cat("All simulations failed. Check warnings above.\n")
  quit(status = 1)
}

cat(glue("\nCollected {nrow(all_results)} simulation results\n"))
cat(glue("Columns: {paste(names(all_results), collapse=', ')}\n\n"))

################################################################################
# STEP 6: CALCULATE POWER
################################################################################

cat("=== Calculating Power ===\n\n")

power_summary <- all_results %>%
  filter(!is.na(reject)) %>%
  group_by(effect_size) %>%
  summarise(
    n_sims = n(),
    n_reject = sum(reject, na.rm = TRUE),
    power = mean(reject, na.rm = TRUE),
    mean_att = mean(att_estimate, na.rm = TRUE),
    mean_se = mean(att_se, na.rm = TRUE),
    .groups = "drop"
  )

print(power_summary)

# Calculate MDE (effect size with 80% power)
# Use linear interpolation
if (any(power_summary$power >= config$target_power)) {
  # Find the two points that bracket 80% power
  below_target <- power_summary %>% filter(power < config$target_power)
  above_target <- power_summary %>% filter(power >= config$target_power)

  if (nrow(below_target) > 0 && nrow(above_target) > 0) {
    # Interpolate
    x1 <- max(below_target$effect_size)
    y1 <- max(below_target$power)
    x2 <- min(above_target$effect_size)
    y2 <- min(above_target$power)

    mde <- x1 + (config$target_power - y1) * (x2 - x1) / (y2 - y1)
  } else {
    # Already above target at smallest effect
    mde <- min(power_summary$effect_size[power_summary$power >= config$target_power])
  }
} else {
  mde <- NA
  cat("\n⚠️  Warning: Did not achieve 80% power at any tested effect size.\n")
  cat("    Consider testing larger effect sizes.\n")
}

cat("\n=== RESULTS FOR GRANT APPLICATION ===\n\n")

if (!is.na(mde)) {
  cat(glue("Minimum Detectable Effect (MDE) at {100*config$target_power}% power:\n"))
  cat(glue("  {round(mde, 2)} filings per 1,000 renters\n\n"))

  cat("What this means:\n")
  cat(glue("  With your sample size and design, you have {100*config$target_power}% power to detect\n"))
  cat(glue("  an effect of {round(mde, 2)} or larger.\n\n"))

  # Context
  baseline_mean <- mean(baseline$outcome_mean)
  pct_change <- 100 * mde / baseline_mean
  cat(glue("  This represents a {round(pct_change, 1)}% change from baseline rate\n"))
  cat(glue("  of {round(baseline_mean, 2)} filings per 1,000 renters.\n\n"))
}

# Type I error (power at effect = 0)
type1_error <- power_summary %>%
  filter(effect_size == 0) %>%
  pull(power)

if (length(type1_error) > 0) {
  cat(glue("Type I error rate: {round(100*type1_error, 1)}%\n"))
  cat(glue("  (Target: 5%, acceptable range: 3-10%)\n"))

  if (type1_error > 0.10) {
    cat("  ⚠️  Type I error elevated - identification may be weak\n")
  } else if (type1_error < 0.03) {
    cat("  ⚠️  Type I error low - test may be conservative\n")
  } else {
    cat("  ✓ Type I error well-calibrated\n")
  }
}

################################################################################
# STEP 7: SAVE RESULTS
################################################################################

cat(glue("\n=== Saving Results ===\n"))

# Save detailed results
write_csv(all_results, config$output_file)
cat(glue("Detailed results: {config$output_file}\n"))

# Save summary
summary_file <- str_replace(config$output_file, "\\.csv$", "_summary.csv")
write_csv(power_summary, summary_file)
cat(glue("Power summary: {summary_file}\n"))

# Create plot
library(ggplot2)

p <- ggplot(power_summary, aes(x = effect_size, y = power)) +
  geom_line(linewidth = 1.2, color = "#2C3E50") +
  geom_point(size = 3, color = "#E74C3C") +
  geom_hline(yintercept = config$target_power,
             linetype = "dashed", color = "#27AE60", linewidth = 1) +
  annotate("text", x = max(config$effect_sizes), y = config$target_power + 0.05,
           label = glue("{100*config$target_power}% power"),
           hjust = 1, color = "#27AE60") +
  labs(
    title = glue("Power Analysis: {str_to_title(config$period)} Period"),
    subtitle = glue("MDE at {100*config$target_power}% power: {round(mde, 2)} filings per 1,000 renters"),
    x = "Effect Size (filings per 1,000 renters)",
    y = "Statistical Power",
    caption = glue("Based on {config$n_sims} simulations per effect size")
  ) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 12, color = "#7F8C8D"),
    panel.grid.minor = element_blank()
  )

plot_file <- str_replace(config$output_file, "\\.csv$", "_plot.png")
ggsave(plot_file, p, width = 10, height = 6, dpi = 300)
cat(glue("Power curve: {plot_file}\n"))

cat("\nDone!\n")
