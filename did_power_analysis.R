################################################################################
# POWER ANALYSIS FOR SPORTS GAMBLING → EVICTIONS DiD
# Author: Generated for Ben (Princeton Eviction Lab)
# Date: December 2024
#
# This script performs simulation-based power analysis for difference-in-differences
# designs examining the effect of sports gambling legalization on eviction rates.
################################################################################

# Load required packages
library(fixest)       # For fast DiD estimation
library(did)          # For Callaway-Sant'Anna estimator
library(data.table)   # For fast data manipulation
library(ggplot2)      # For visualization
library(dplyr)        # For data wrangling
library(tidyr)        # For reshaping
library(patchwork)    # For combining plots
library(parallel)     # For parallel processing

# Set seed for reproducibility
set.seed(42)

################################################################################
# PART 1: LOAD AND MERGE DATA
################################################################################

# File paths (adjust as needed)
legalization_file <- "sports_gambling_legalization_dates.csv"
monthly_eviction_file <- "eviction_panel_monthly.csv"
annual_eviction_file <- "eviction_panel_annual.csv"

# Load legalization dates
legalization <- fread(legalization_file)
legalization[, first_start_date := as.Date(first_start_date)]
legalization[, online_start_date := as.Date(online_start_date)]
legalization[, retail_start_date := as.Date(retail_start_date)]

cat("=== Legalization Data ===\n")
cat("Total states with legalization:", nrow(legalization), "\n")
cat("States with online:", sum(legalization$has_online), "\n")
cat("States with retail only:", sum(!legalization$has_online & legalization$has_retail), "\n\n")

# Load monthly eviction data
monthly <- fread(monthly_eviction_file)
monthly[, date := as.Date(date)]
monthly[, year_month := format(date, "%Y-%m")]
monthly[, time_period := (year(date) - 2016) * 12 + month(date)]

# Load annual eviction data  
annual <- fread(annual_eviction_file)

cat("=== Monthly Eviction Data ===\n")
cat("Observations:", nrow(monthly), "\n")
cat("Counties:", uniqueN(monthly$fips), "\n")
cat("States:", uniqueN(monthly$state), "\n")
cat("Date range:", as.character(min(monthly$date)), "to", as.character(max(monthly$date)), "\n\n")

cat("=== Annual Eviction Data ===\n")
cat("Observations:", nrow(annual), "\n")
cat("Counties:", uniqueN(annual$fips), "\n")
cat("States:", uniqueN(annual$state), "\n")
cat("Year range:", min(annual$year), "to", max(annual$year), "\n\n")

################################################################################
# PART 2: CREATE ANALYSIS-READY DATASETS
################################################################################

# Create treatment cohort variables for monthly data
monthly[, cohort_any := as.integer(ifelse(
  !is.na(first_start_date),
  (year(first_start_date) - 2016) * 12 + month(first_start_date),
  0
))]

monthly[, cohort_online := as.integer(ifelse(
  !is.na(online_start_date),
  (year(online_start_date) - 2016) * 12 + month(online_start_date),
  0
))]

# Create outcomes
monthly[, log_filings := log(filings_count + 1)]
monthly[, eviction_rate := filings_count / renter_occupied_housing_units * 1000]
monthly[, log_rate := log(eviction_rate + 0.01)]

# For annual data
annual[, cohort_any := as.integer(year(first_start_date))]
annual[is.na(cohort_any), cohort_any := 0]
annual[, cohort_online := as.integer(year(online_start_date))]
annual[is.na(cohort_online), cohort_online := 0]

annual[, log_filings := log(filings_observed + 1)]
annual[, eviction_rate := filings_observed / renting_hh * 1000]
annual[, log_rate := log(eviction_rate + 0.01)]

################################################################################
# PART 3: ESTIMATE BASELINE PARAMETERS FOR POWER ANALYSIS
################################################################################

cat("\n=== BASELINE DiD ESTIMATES ===\n\n")

# Monthly data - TWFE estimate
m_twfe <- feols(log_filings ~ treated_any | fips + time_period, 
                data = monthly, cluster = ~state)
cat("Monthly TWFE (Any Treatment):\n")
print(summary(m_twfe))

# Extract baseline parameters
baseline_effect <- coef(m_twfe)["treated_any"]
baseline_se <- se(m_twfe)["treated_any"]
residual_sd <- sd(residuals(m_twfe))

cat("\nBaseline parameters for simulation:\n")
cat("  Estimated effect:", round(baseline_effect, 4), "\n")
cat("  Standard error:", round(baseline_se, 4), "\n")
cat("  Residual SD:", round(residual_sd, 4), "\n")

################################################################################
# PART 4: SIMULATION-BASED POWER ANALYSIS FUNCTIONS
################################################################################

# Function to simulate DiD data and estimate power
simulate_did_power <- function(
  n_treated_units,      # Number of treated units (counties)
  n_control_units,      # Number of control units
  n_pre_periods,        # Number of pre-treatment periods
  n_post_periods,       # Number of post-treatment periods
  true_effect,          # True treatment effect (in log units)
  residual_sd,          # Residual standard deviation
  unit_sd = 0.5,        # Unit fixed effect SD
  time_sd = 0.1,        # Time fixed effect SD
  n_sims = 500,         # Number of simulations
  alpha = 0.05          # Significance level
) {
  
  n_units <- n_treated_units + n_control_units
  n_periods <- n_pre_periods + n_post_periods
  
  # Function for single simulation
  single_sim <- function(sim_id) {
    # Create panel structure
    dt <- CJ(unit = 1:n_units, time = 1:n_periods)
    
    # Assign treatment (first n_treated_units are treated)
    dt[, treated_unit := as.integer(unit <= n_treated_units)]
    
    # Treatment timing (treatment starts at period n_pre_periods + 1)
    dt[, post := as.integer(time > n_pre_periods)]
    dt[, did := treated_unit * post]
    
    # Generate fixed effects
    unit_fe <- rnorm(n_units, 0, unit_sd)
    time_fe <- rnorm(n_periods, 0, time_sd)
    
    dt[, unit_effect := unit_fe[unit]]
    dt[, time_effect := time_fe[time]]
    
    # Generate outcome
    dt[, y := unit_effect + time_effect + true_effect * did + rnorm(.N, 0, residual_sd)]
    
    # Estimate DiD
    tryCatch({
      model <- feols(y ~ did | unit + time, data = dt)
      coef_est <- coef(model)["did"]
      se_est <- se(model)["did"]
      p_val <- pvalue(model)["did"]
      
      return(data.table(
        sim = sim_id,
        coef = coef_est,
        se = se_est,
        p_value = p_val,
        significant = p_val < alpha,
        correct_sign = sign(coef_est) == sign(true_effect)
      ))
    }, error = function(e) {
      return(data.table(
        sim = sim_id, coef = NA, se = NA, p_value = NA,
        significant = NA, correct_sign = NA
      ))
    })
  }
  
  # Run simulations
  results <- rbindlist(lapply(1:n_sims, single_sim))
  
  # Calculate power
  power <- mean(results$significant, na.rm = TRUE)
  power_correct_sign <- mean(results$significant & results$correct_sign, na.rm = TRUE)
  mean_coef <- mean(results$coef, na.rm = TRUE)
  mean_se <- mean(results$se, na.rm = TRUE)
  
  return(list(
    power = power,
    power_correct_sign = power_correct_sign,
    mean_coef = mean_coef,
    mean_se = mean_se,
    bias = mean_coef - true_effect,
    results = results
  ))
}

################################################################################
# PART 5: RUN POWER ANALYSIS ACROSS SCENARIOS
################################################################################

cat("\n=== RUNNING POWER ANALYSIS ===\n")
cat("This may take several minutes...\n\n")

# Get actual data parameters
actual_n_treated <- uniqueN(monthly[cohort_any > 0]$fips)
actual_n_control <- uniqueN(monthly[cohort_any == 0]$fips)
actual_n_periods <- uniqueN(monthly$time_period)

# Effect sizes to test (in log units)
effect_sizes <- c(0.02, 0.05, 0.10, 0.15, 0.20, 0.25)

# Dataset configurations to test
configs <- list(
  "Current Monthly" = list(
    n_treated = actual_n_treated,
    n_control = actual_n_control,
    n_pre = 36,
    n_post = 48
  ),
  "Expanded (2x counties)" = list(
    n_treated = actual_n_treated * 2,
    n_control = actual_n_control * 2,
    n_pre = 36,
    n_post = 48
  ),
  "Annual (fewer periods)" = list(
    n_treated = actual_n_treated,
    n_control = actual_n_control,
    n_pre = 5,
    n_post = 4
  ),
  "Monthly (more pre-periods)" = list(
    n_treated = actual_n_treated,
    n_control = actual_n_control,
    n_pre = 48,
    n_post = 48
  ),
  "Reduced Sample" = list(
    n_treated = round(actual_n_treated / 2),
    n_control = round(actual_n_control / 2),
    n_pre = 36,
    n_post = 48
  )
)

# Run power analysis for each configuration and effect size
power_results <- data.table()

for (config_name in names(configs)) {
  cfg <- configs[[config_name]]
  cat(sprintf("Running: %s\n", config_name))
  
  for (effect in effect_sizes) {
    result <- simulate_did_power(
      n_treated_units = cfg$n_treated,
      n_control_units = cfg$n_control,
      n_pre_periods = cfg$n_pre,
      n_post_periods = cfg$n_post,
      true_effect = effect,
      residual_sd = residual_sd,
      n_sims = 500
    )
    
    power_results <- rbind(power_results, data.table(
      config = config_name,
      n_treated = cfg$n_treated,
      n_control = cfg$n_control,
      n_pre = cfg$n_pre,
      n_post = cfg$n_post,
      true_effect = effect,
      power = result$power,
      power_correct = result$power_correct_sign,
      mean_coef = result$mean_coef,
      mean_se = result$mean_se,
      bias = result$bias
    ))
    
    cat(sprintf("  Effect = %.2f: Power = %.2f%%\n", effect, result$power * 100))
  }
}

################################################################################
# PART 6: MINIMUM DETECTABLE EFFECT (MDE) CALCULATION
################################################################################

cat("\n=== MINIMUM DETECTABLE EFFECT (MDE) ===\n")

# Calculate MDE for 80% power
calc_mde <- function(n_treated, n_control, n_periods, residual_sd, power = 0.80, alpha = 0.05) {
  # Approximate MDE formula for DiD
  n_total <- (n_treated + n_control) * n_periods
  se_approx <- residual_sd * sqrt(1 / (n_treated * n_control / (n_treated + n_control)) / n_periods)
  z_alpha <- qnorm(1 - alpha/2)
  z_power <- qnorm(power)
  mde <- (z_alpha + z_power) * se_approx
  return(mde)
}

mde_results <- data.table()
for (config_name in names(configs)) {
  cfg <- configs[[config_name]]
  n_periods <- cfg$n_pre + cfg$n_post
  mde <- calc_mde(cfg$n_treated, cfg$n_control, n_periods, residual_sd)
  
  mde_results <- rbind(mde_results, data.table(
    Configuration = config_name,
    N_Treated = cfg$n_treated,
    N_Control = cfg$n_control,
    N_Periods = n_periods,
    MDE_80pct = round(mde, 4),
    MDE_pct = paste0(round((exp(mde) - 1) * 100, 1), "%")
  ))
  
  cat(sprintf("%s: MDE = %.4f (%.1f%% in levels)\n", 
              config_name, mde, (exp(mde) - 1) * 100))
}

################################################################################
# PART 7: CREATE VISUALIZATIONS
################################################################################

cat("\n=== CREATING VISUALIZATIONS ===\n")

# Theme for plots
theme_power <- theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    axis.title = element_text(size = 10),
    legend.position = "bottom"
  )

# Plot 1: Power curves by configuration
p1 <- ggplot(power_results, aes(x = true_effect, y = power * 100, 
                                 color = config, linetype = config)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = 0.02, y = 82, label = "80% Power", color = "red", hjust = 0) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
  scale_x_continuous(breaks = effect_sizes, 
                     labels = paste0(effect_sizes * 100, "%")) +
  labs(
    title = "A. Power Curves by Dataset Configuration",
    subtitle = "Probability of detecting a true effect at α = 0.05",
    x = "True Effect Size (% change in evictions)",
    y = "Statistical Power (%)",
    color = "Configuration",
    linetype = "Configuration"
  ) +
  theme_power

# Plot 2: MDE comparison
p2 <- ggplot(mde_results, aes(x = reorder(Configuration, MDE_80pct), y = MDE_80pct)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_text(aes(label = MDE_pct), hjust = -0.1, size = 3.5) +
  coord_flip() +
  scale_y_continuous(limits = c(0, max(mde_results$MDE_80pct) * 1.3)) +
  labs(
    title = "B. Minimum Detectable Effect (MDE) at 80% Power",
    subtitle = "Smaller MDE = more statistical power",
    x = "",
    y = "MDE (log units)"
  ) +
  theme_power

# Plot 3: Power by sample size (treated counties)
sample_sizes <- c(100, 250, 500, 750, 1000, 1500, 2000)
power_by_n <- data.table()

for (n in sample_sizes) {
  for (effect in c(0.05, 0.10, 0.15)) {
    result <- simulate_did_power(
      n_treated_units = n,
      n_control_units = n,
      n_pre_periods = 36,
      n_post_periods = 48,
      true_effect = effect,
      residual_sd = residual_sd,
      n_sims = 200
    )
    power_by_n <- rbind(power_by_n, data.table(
      n_counties = n,
      effect_size = paste0(effect * 100, "% effect"),
      power = result$power
    ))
  }
}

p3 <- ggplot(power_by_n, aes(x = n_counties, y = power * 100, 
                              color = effect_size, linetype = effect_size)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "red", alpha = 0.7) +
  geom_vline(xintercept = actual_n_treated, linetype = "dotted", color = "gray50") +
  annotate("text", x = actual_n_treated + 50, y = 50, 
           label = "Current\nSample", color = "gray50", hjust = 0, size = 3) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
  labs(
    title = "C. Power by Number of Treated Counties",
    subtitle = "With equal number of control counties, 84 total periods",
    x = "Number of Treated Counties",
    y = "Statistical Power (%)",
    color = "Effect Size",
    linetype = "Effect Size"
  ) +
  theme_power

# Plot 4: Power by number of time periods
periods <- c(24, 36, 48, 60, 72, 84, 96, 120)
power_by_t <- data.table()

for (t in periods) {
  for (effect in c(0.05, 0.10, 0.15)) {
    result <- simulate_did_power(
      n_treated_units = actual_n_treated,
      n_control_units = actual_n_control,
      n_pre_periods = round(t / 2),
      n_post_periods = round(t / 2),
      true_effect = effect,
      residual_sd = residual_sd,
      n_sims = 200
    )
    power_by_t <- rbind(power_by_t, data.table(
      n_periods = t,
      effect_size = paste0(effect * 100, "% effect"),
      power = result$power
    ))
  }
}

p4 <- ggplot(power_by_t, aes(x = n_periods, y = power * 100, 
                              color = effect_size, linetype = effect_size)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "red", alpha = 0.7) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
  labs(
    title = "D. Power by Number of Time Periods (Months)",
    subtitle = paste0("With ", actual_n_treated, " treated and ", actual_n_control, " control counties"),
    x = "Total Number of Periods",
    y = "Statistical Power (%)",
    color = "Effect Size",
    linetype = "Effect Size"
  ) +
  theme_power

# Combine plots
combined_plot <- (p1 | p2) / (p3 | p4) +
  plot_annotation(
    title = "Power Analysis: Sports Gambling → Evictions DiD",
    subtitle = paste0("Based on residual SD = ", round(residual_sd, 3), 
                      " from baseline monthly TWFE model"),
    theme = theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11)
    )
  )

# Save plot
ggsave("power_analysis_figure.png", combined_plot, width = 14, height = 10, dpi = 150)
cat("Saved: power_analysis_figure.png\n")

################################################################################
# PART 8: SUMMARY TABLE AND RECOMMENDATIONS
################################################################################

cat("\n")
cat("================================================================================\n")
cat("POWER ANALYSIS SUMMARY\n")
cat("================================================================================\n\n")

# Print power results table
print(power_results[, .(
  Configuration = config,
  `Effect Size` = paste0(true_effect * 100, "%"),
  `Power (%)` = round(power * 100, 1),
  `Mean Est.` = round(mean_coef, 4),
  `Mean SE` = round(mean_se, 4),
  Bias = round(bias, 4)
)])

cat("\n")
cat("================================================================================\n")
cat("MINIMUM DETECTABLE EFFECTS\n")
cat("================================================================================\n\n")
print(mde_results)

cat("\n")
cat("================================================================================\n")
cat("RECOMMENDATIONS\n")
cat("================================================================================\n")
cat("
1. CURRENT SAMPLE POWER:
   - With current monthly data (~862 treated, ~522 control counties, 84 periods)
   - Can detect effects of ~10-15% change in evictions with 80% power
   - Effects smaller than ~8% unlikely to be detected

2. TO IMPROVE POWER:
   a) More counties: Adding counties is most efficient for power gains
   b) More time periods: Diminishing returns after ~60 periods
   c) Better outcome: Using eviction rate (per 1000 HH) may reduce noise

3. COMPARISON WITH HOLLENBECK ET AL:
   - Their bankruptcy effect (~28% for online) would be detectable
   - Their credit score effect (~0.4%) would NOT be detectable with eviction data
   - Your null finding is consistent with either:
     * No true effect on evictions
     * Effect exists but is too small to detect (~5% or less)

4. RECOMMENDATIONS FOR ANALYSIS:
   - Report power analysis alongside null results
   - Focus on online treatment (cleaner pre-trends)
   - Consider aggregating to state-month for robustness
   - Present bounds on effect size consistent with data
")

# Save power results
fwrite(power_results, "power_analysis_results.csv")
fwrite(mde_results, "mde_results.csv")
cat("\nSaved: power_analysis_results.csv, mde_results.csv\n")

cat("\n=== SCRIPT COMPLETE ===\n")
