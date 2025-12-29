################################################################################
# SENSITIVITY ANALYSIS AND VISUALIZATION
# Varying panel length and number of states
################################################################################

library(tidyverse)
library(fixest)
library(patchwork)
library(scales)

# Load results
load("power_simulation_results.RData")
load("eviction_gambling_power_workspace.RData")

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("SENSITIVITY ANALYSIS\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

################################################################################
# SENSITIVITY 1: Panel Length
# Test +6, +12, +24 months
################################################################################

cat("Running panel length sensitivity...\n")

# Source the simulation functions
source("power_simulation_main.R", local = TRUE)

panel_length_sensitivity <- function(data, months_to_add = c(6, 12, 24)) {
  results_list <- list()

  # Baseline: 6 pre, 6 post
  cat("\nBaseline (6 pre, 6 post):\n")
  results_base <- run_power_simulation(
    data, scheme = "A", effect_sizes = c(0, 1, 2, 3, 4, 5),
    n_sims = 200, m_pre = 6, r_post = 6
  )
  results_base$scenario <- "6_pre_6_post"
  results_list[[1]] <- results_base

  # Extended panels
  for (add_months in months_to_add) {
    new_post <- 6 + add_months
    cat(sprintf("\nExtended (6 pre, %d post):\n", new_post))

    results_ext <- run_power_simulation(
      data, scheme = "A", effect_sizes = c(0, 1, 2, 3, 4, 5),
      n_sims = 200, m_pre = 6, r_post = new_post
    )
    results_ext$scenario <- sprintf("6_pre_%d_post", new_post)
    results_list[[length(results_list) + 1]] <- results_ext
  }

  bind_rows(results_list)
}

sensitivity_panel_length <- panel_length_sensitivity(analysis_panel)
write_csv(sensitivity_panel_length, "sensitivity_panel_length.csv")

################################################################################
# SENSITIVITY 2: Number of States (Clusters)
################################################################################

cat("\n\nRunning number of states sensitivity...\n")

states_sensitivity <- function(data, state_fractions = c(0.5, 0.75, 1.0)) {
  results_list <- list()
  all_states <- unique(data$state)
  n_all_states <- length(all_states)

  for (frac in state_fractions) {
    n_states <- round(n_all_states * frac)
    states_subset <- sample(all_states, n_states)

    cat(sprintf("\nUsing %d states (%.0f%% of total):\n", n_states, frac * 100))

    data_subset <- data %>% filter(state %in% states_subset)

    results <- run_power_simulation(
      data_subset, scheme = "A", effect_sizes = c(0, 1, 2, 3, 4, 5),
      n_sims = 200, m_pre = 6, r_post = 6
    )
    results$n_states <- n_states
    results$state_fraction <- frac
    results_list[[length(results_list) + 1]] <- results
  }

  bind_rows(results_list)
}

sensitivity_n_states <- states_sensitivity(analysis_panel)
write_csv(sensitivity_n_states, "sensitivity_n_states.csv")

################################################################################
# SENSITIVITY 3: Block Length (for moving-block bootstrap)
################################################################################

cat("\n\nRunning block length sensitivity...\n")

block_length_sensitivity <- function(data, block_lengths = c(1, 3, 6, 12)) {
  results_list <- list()

  for (block_len in block_lengths) {
    cat(sprintf("\nBlock length = %d:\n", block_len))

    results <- run_power_simulation(
      data, scheme = "A", effect_sizes = c(0, 1, 2, 3, 4, 5),
      n_sims = 200, m_pre = 6, r_post = 6,
      block_length = block_len
    )
    results$block_length <- block_len
    results_list[[length(results_list) + 1]] <- results
  }

  bind_rows(results_list)
}

sensitivity_block_length <- block_length_sensitivity(analysis_panel)
write_csv(sensitivity_block_length, "sensitivity_block_length.csv")

################################################################################
# VISUALIZATION
################################################################################

cat("\n\nCreating visualizations...\n")

# Define theme
theme_power <- theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "gray30"),
    axis.title = element_text(size = 11),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

################################################################################
# PLOT 1: Power Curves (Scheme A vs B)
################################################################################

plot_power_curves <- ggplot() +
  geom_line(
    data = results_scheme_a %>% filter(effect_size > 0),
    aes(x = effect_size, y = power, color = "Scheme A: Random"),
    size = 1.2
  ) +
  geom_point(
    data = results_scheme_a %>% filter(effect_size > 0),
    aes(x = effect_size, y = power, color = "Scheme A: Random"),
    size = 3
  ) +
  geom_line(
    data = results_scheme_b %>% filter(effect_size > 0),
    aes(x = effect_size, y = power, color = "Scheme B: Staggered"),
    size = 1.2
  ) +
  geom_point(
    data = results_scheme_b %>% filter(effect_size > 0),
    aes(x = effect_size, y = power, color = "Scheme B: Staggered"),
    size = 3
  ) +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = mde_scheme_a, linetype = "dotted", color = "#00BFC4", alpha = 0.7) +
  geom_vline(xintercept = mde_scheme_b, linetype = "dotted", color = "#F8766D", alpha = 0.7) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_color_manual(values = c("#00BFC4", "#F8766D")) +
  labs(
    title = "Power Curves: Sports Gambling → Eviction Filings",
    subtitle = "Following Black et al. (2021) simulation methodology\n6 pre-periods, 6 post-periods, α=0.05",
    x = "Effect Size (filings per 1,000 renter households)",
    y = "Statistical Power",
    color = "Assignment Scheme",
    caption = sprintf("MDE at 80%% power: Scheme A = %.2f, Scheme B = %.2f", mde_scheme_a, mde_scheme_b)
  ) +
  theme_power

ggsave("plot_power_curves.png", plot_power_curves, width = 10, height = 6, dpi = 300)

################################################################################
# PLOT 2: Sign Error and Magnitude Error Rates
################################################################################

plot_errors <- results_scheme_a %>%
  filter(effect_size > 0) %>%
  select(effect_size, sign_error_rate, severe_mag_error_rate) %>%
  pivot_longer(cols = c(sign_error_rate, severe_mag_error_rate),
               names_to = "error_type", values_to = "rate") %>%
  mutate(
    error_type = factor(
      error_type,
      levels = c("sign_error_rate", "severe_mag_error_rate"),
      labels = c("Sign Error (wrong direction)", "Severe Magnitude Error (>2× truth)")
    )
  ) %>%
  ggplot(aes(x = effect_size, y = rate, color = error_type)) +
  geom_line(size = 1.2) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  scale_y_continuous(labels = percent_format()) +
  scale_color_manual(values = c("#E41A1C", "#FF7F00")) +
  labs(
    title = "Error Rates Among Statistically Significant Results",
    subtitle = "Following Gelman & Carlin (2014) believability criteria\nScheme A: Random assignment",
    x = "True Effect Size (filings per 1,000 renter households)",
    y = "Error Rate",
    color = "Error Type"
  ) +
  theme_power +
  theme(legend.position = "bottom")

ggsave("plot_error_rates.png", plot_errors, width = 10, height = 6, dpi = 300)

################################################################################
# PLOT 3: Panel Length Sensitivity
################################################################################

plot_panel_length <- sensitivity_panel_length %>%
  filter(effect_size > 0) %>%
  mutate(
    scenario_label = str_replace_all(scenario, "_", " ") %>% str_to_title()
  ) %>%
  ggplot(aes(x = effect_size, y = power, color = scenario_label, group = scenario_label)) +
  geom_line(size = 1.1) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray50") +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_color_brewer(palette = "Set2") +
  labs(
    title = "Power vs. Panel Length",
    subtitle = "How power changes with additional post-treatment months",
    x = "Effect Size (filings per 1,000 renter households)",
    y = "Statistical Power",
    color = "Panel Design"
  ) +
  theme_power

ggsave("plot_panel_length_sensitivity.png", plot_panel_length, width = 10, height = 6, dpi = 300)

################################################################################
# PLOT 4: Number of States Sensitivity
################################################################################

plot_n_states <- sensitivity_n_states %>%
  filter(effect_size > 0) %>%
  mutate(
    states_label = sprintf("%d states", n_states)
  ) %>%
  ggplot(aes(x = effect_size, y = power, color = states_label, group = n_states)) +
  geom_line(size = 1.1) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray50") +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_color_viridis_d(option = "plasma") +
  labs(
    title = "Power vs. Number of States (Clusters)",
    subtitle = "Impact of sample size on statistical power",
    x = "Effect Size (filings per 1,000 renter households)",
    y = "Statistical Power",
    color = "Sample Size"
  ) +
  theme_power

ggsave("plot_n_states_sensitivity.png", plot_n_states, width = 10, height = 6, dpi = 300)

################################################################################
# TABLE 1: Main Results Summary
################################################################################

table_main <- bind_rows(
  results_scheme_a %>% mutate(scheme = "A: Random"),
  results_scheme_b %>% mutate(scheme = "B: Staggered")
) %>%
  select(
    Scheme = scheme,
    `Effect Size` = effect_size,
    Power = power,
    `Sign Error %` = sign_error_rate,
    `Mag Error %` = severe_mag_error_rate,
    `Mean Estimate` = mean_coef,
    N = n_valid
  ) %>%
  mutate(
    Power = sprintf("%.1f%%", Power * 100),
    `Sign Error %` = sprintf("%.1f%%", `Sign Error %` * 100),
    `Mag Error %` = sprintf("%.1f%%", `Mag Error %` * 100),
    `Mean Estimate` = sprintf("%.3f", `Mean Estimate`)
  )

write_csv(table_main, "table_main_results.csv")

################################################################################
# TABLE 2: MDE Summary by Design
################################################################################

# Calculate MDE for each scenario
mde_panel_length <- sensitivity_panel_length %>%
  group_by(scenario) %>%
  summarise(
    mde = calculate_mde_from_results(cur_data()),
    .groups = "drop"
  )

mde_n_states <- sensitivity_n_states %>%
  group_by(n_states) %>%
  summarise(
    mde = calculate_mde_from_results(cur_data()),
    .groups = "drop"
  )

table_mde_summary <- tibble(
  Design = c(
    "Baseline (6 pre, 6 post)",
    sprintf("Extended (%s)", mde_panel_length$scenario[-1]),
    sprintf("%d states", mde_n_states$n_states)
  ),
  `MDE (80% power, 5% alpha)` = c(
    mde_scheme_a,
    mde_panel_length$mde[-1],
    mde_n_states$mde
  )
) %>%
  mutate(
    `MDE (80% power, 5% alpha)` = sprintf("%.3f", `MDE (80% power, 5% alpha)`)
  )

write_csv(table_mde_summary, "table_mde_summary.csv")

################################################################################
# COMBINED PLOT: 4-panel sensitivity
################################################################################

combined_plot <- (plot_power_curves + plot_errors) /
  (plot_panel_length + plot_n_states) +
  plot_annotation(
    title = "Simulated Power Analysis: Sports Gambling → Eviction Filings",
    subtitle = "Following Black et al. (2021) and Burlig et al. (2020) methodology",
    theme = theme(plot.title = element_text(size = 16, face = "bold"))
  )

ggsave("plot_combined_sensitivity.png", combined_plot, width = 16, height = 12, dpi = 300)

cat("\n=== VISUALIZATION COMPLETE ===\n")
cat("Plots saved:\n")
cat("  - plot_power_curves.png\n")
cat("  - plot_error_rates.png\n")
cat("  - plot_panel_length_sensitivity.png\n")
cat("  - plot_n_states_sensitivity.png\n")
cat("  - plot_combined_sensitivity.png\n\n")
cat("Tables saved:\n")
cat("  - table_main_results.csv\n")
cat("  - table_mde_summary.csv\n\n")

################################################################################
# FINAL SUMMARY REPORT
################################################################################

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("FINAL SUMMARY REPORT\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

cat("METHODOLOGY SUMMARY:\n")
cat("Following Black, Hollingsworth, Nunes & Simon (2021) and Burlig, Preonas & Woerman (2020)\n\n")

cat("SIMULATION STEPS:\n")
cat("1. Used ONLY untreated/pre-period eviction data from real panels\n")
cat("2. Random pseudo-treatment assignment (500 iterations per effect size)\n")
cat("3. Calibrated error process from untreated months, preserving autocorrelation\n")
cat("4. Estimated Y ~ D | state + month with cluster-robust SE\n")
cat("5. Recorded: power, MDE, sign errors, magnitude errors\n")
cat("6. Sensitivity: panel length (+6/+12/+24 months), # states, block length\n\n")

cat("KEY FINDINGS:\n")
cat(sprintf("• MDE (Scheme A, Random):     %.3f filings per 1,000 renters\n", mde_scheme_a))
cat(sprintf("• MDE (Scheme B, Staggered):  %.3f filings per 1,000 renters\n", mde_scheme_b))
cat(sprintf("• Analysis based on %d states, %d state-months\n",
            n_distinct(analysis_panel$state), nrow(analysis_panel)))
cat(sprintf("• Baseline design: 6 pre-periods, 6 post-periods\n"))
cat(sprintf("• Cluster-robust inference at state level\n\n"))

cat("INTERPRETATION:\n")
cat("Power curves show detectable effect sizes anchored to gambling→bankruptcy magnitudes.\n")
cat("Error rates quantify risk of sign errors and severe overestimation (Gelman & Carlin 2014).\n")
cat("Sensitivity analyses demonstrate trade-offs between panel length and cluster count.\n\n")

cat("=== ANALYSIS COMPLETE ===\n\n")
