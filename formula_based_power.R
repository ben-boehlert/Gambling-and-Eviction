#!/usr/bin/env Rscript
################################################################################
# formula_based_power.R
#
# Simple formula-based power calculation for DiD
# Uses the variation in your actual data to calculate MDE
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
  library(glue)
})

cat("=== Formula-Based Power Calculation ===\n\n")

# Load data
cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
  outcome_preference = c("filings_per_1k_renters", "filings_count_per_1k_renters"),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date"
)

source("power_simulation_cs.R")
panel <- load_panel(cfg)

# Pre-COVID period
panel_pre <- panel %>%
  filter(month_date >= as.Date("2016-01-01"),
         month_date < as.Date("2020-03-01"))

cat("Data loaded:\n")
cat(glue("  {nrow(panel_pre)} observations\n"))
cat(glue("  {n_distinct(panel_pre$state_abb)} states\n"))
cat(glue("  {n_distinct(panel_pre$month_date)} months\n\n"))

# Get treatment info
treat_schedule <- make_treat_schedule(panel_pre, cfg)
panel_pre <- panel_pre %>%
  left_join(treat_schedule %>% select(unit_id, g, ever_treated), by = "unit_id")

# Use ONLY never-treated states to estimate variation
never_treated <- panel_pre %>%
  filter(!ever_treated) %>%
  mutate(
    state_id = as.integer(factor(state_abb)),
    time_id = as.integer(factor(month_date))
  )

cat(glue("Never-treated sample: {n_distinct(never_treated$state_abb)} states, {nrow(never_treated)} obs\n\n"))

# Residualize (remove unit + time FE)
fe_model <- feols(outcome ~ 1 | state_id + time_id, data = never_treated)

never_treated <- never_treated %>%
  mutate(outcome_resid = resid(fe_model))

# Calculate standard deviation of residuals
sd_resid <- sd(never_treated$outcome_resid, na.rm = TRUE)
mean_outcome <- mean(never_treated$outcome, na.rm = TRUE)

cat("=== Variation in Never-Treated Data ===\n")
cat(glue("Mean outcome: {round(mean_outcome, 2)} filings per 1,000 renters\n"))
cat(glue("SD of residuals (after unit+time FE): {round(sd_resid, 2)}\n\n"))

# Power calculation parameters
n_treated_states <- 4  # Pre-COVID: WV, PA, IN, NH
n_control_states <- n_distinct(never_treated$state_abb)
n_months_post <- 12  # Assume 12 months post-treatment
alpha <- 0.05
power <- 0.80

# Critical values
t_crit_twosided <- qt(1 - alpha/2, df = n_treated_states + n_control_states - 2)
z_power <- qnorm(power)

cat("=== Power Calculation ===\n")
cat(glue("Treated states: {n_treated_states}\n"))
cat(glue("Control states: {n_control_states}\n"))
cat(glue("Post-treatment months: {n_months_post}\n"))
cat(glue("Significance level: {alpha} (two-sided)\n"))
cat(glue("Target power: {power}\n\n"))

# Standard error for DiD estimator
# SE_DiD ≈ SD × sqrt(1/n_treat + 1/n_control) × sqrt(1/T_post)
# This is a simplified formula

se_did <- sd_resid * sqrt(1/n_treated_states + 1/n_control_states) / sqrt(n_months_post)

# Minimum Detectable Effect
# MDE = (t_crit + z_power) × SE
mde <- (t_crit_twosided + z_power) * se_did

cat("=== RESULTS ===\n\n")
cat(glue("Standard error of DiD estimator: {round(se_did, 3)}\n"))
cat(glue("Minimum Detectable Effect (MDE): {round(mde, 2)} filings per 1,000 renters\n\n"))

pct_change <- 100 * mde / mean_outcome
cat(glue("This represents a {round(pct_change, 1)}% change from baseline.\n\n"))

# Show power curve
effect_sizes <- seq(0, 5, by = 0.5)
powers <- sapply(effect_sizes, function(delta) {
  # Power = P(reject | true effect = delta)
  # Non-centrality parameter
  ncp <- delta / se_did
  # Power for two-sided test
  power_val <- 1 - pt(t_crit_twosided, df = n_treated_states + n_control_states - 2, ncp = ncp) +
               pt(-t_crit_twosided, df = n_treated_states + n_control_states - 2, ncp = ncp)
  return(power_val)
})

power_table <- tibble(
  effect_size = effect_sizes,
  power = powers
)

cat("=== Power Curve ===\n")
print(power_table %>% mutate(power = round(power, 3)))

# Save results
write_csv(power_table, "formula_power_results.csv")

# Plot
library(ggplot2)

p <- ggplot(power_table, aes(x = effect_size, y = power)) +
  geom_line(linewidth = 1.2, color = "#2C3E50") +
  geom_point(size = 3, color = "#E74C3C") +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "#27AE60", linewidth = 1) +
  geom_vline(xintercept = mde, linetype = "dashed", color = "#E74C3C", linewidth = 1) +
  annotate("text", x = mde, y = 0.05,
           label = glue("MDE = {round(mde, 2)}"), hjust = -0.1, color = "#E74C3C") +
  annotate("text", x = max(effect_sizes), y = 0.80 + 0.05,
           label = "80% power", hjust = 1, color = "#27AE60") +
  labs(
    title = "Power Analysis: Pre-COVID Period",
    subtitle = glue("MDE at 80% power: {round(mde, 2)} filings per 1,000 renters ({round(pct_change, 1)}% change)"),
    x = "Effect Size (filings per 1,000 renters)",
    y = "Statistical Power",
    caption = glue("Based on {n_treated_states} treated, {n_control_states} control states; {n_months_post} months post-treatment")
  ) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(0, 5, by = 0.5)) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 12, color = "#7F8C8D"),
    panel.grid.minor = element_blank()
  )

ggsave("formula_power_curve.png", p, width = 10, height = 6, dpi = 300)

cat("\n=== Files Saved ===\n")
cat("formula_power_results.csv - Power at each effect size\n")
cat("formula_power_curve.png - Power curve plot\n\n")

cat("=== For Your Grant ===\n")
cat(glue('With {n_treated_states} treated states and {n_control_states} control states,\n'))
cat(glue('we have 80% power to detect an effect of {round(mde, 2)} filings per 1,000 renters\n'))
cat(glue('({round(pct_change, 1)}% change from baseline).\n'))

cat("\nDone!\n")
