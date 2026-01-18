#!/usr/bin/env Rscript
################################################################################
# visualize_pretrend_effect_comparison.R
#
# Comprehensive Visualizations Comparing Pre-trend Violations to Treatment Effects
# with HonestDiD Sensitivity Analysis
#
# Creates 6 detailed figures for investigating robustness
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
  library(glue)
  library(tidyr)
})

################################################################################
# CONFIGURATION
################################################################################

BASE_DIR <- "/Users/bb1806/Documents/GitHub/Gambling-and-Eviction"
EVAL_DIR <- file.path(BASE_DIR, "output/pretrends_evaluation")
SPEC_NAME <- "baseline"
SPEC_DIR <- file.path(EVAL_DIR, SPEC_NAME)
FIG_DIR <- file.path(EVAL_DIR, "figures")

dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

# Plotting theme
theme_set(theme_minimal(base_size = 12))
my_theme <- theme(
  plot.title = element_text(face = "bold", size = 14),
  plot.subtitle = element_text(size = 11, color = "gray30"),
  panel.grid.minor = element_blank(),
  legend.position = "bottom"
)

cat("Loading data...\n")

################################################################################
# LOAD DATA
################################################################################

# Event study coefficients
coefs <- readr::read_csv(file.path(SPEC_DIR, "event_study_coefs.csv"), show_col_types = FALSE)

# HonestDiD results
honestdid <- readr::read_csv(file.path(SPEC_DIR, "honestdid_sensitivity.csv"), show_col_types = FALSE) %>%
  mutate(width = ub - lb, excludes_zero = (lb > 0) | (ub < 0))

# Comparison table (if exists from previous analysis)
comp_file <- file.path(EVAL_DIR, "comparison_table.csv")
if (file.exists(comp_file)) {
  comp <- readr::read_csv(comp_file, show_col_types = FALSE)
} else {
  # Create minimal comparison table
  pre_coefs <- coefs %>% filter(e < 0)
  post_coefs <- coefs %>% filter(e >= 0)
  comp <- tibble(
    max_pretrend = max(abs(pre_coefs$estimate)),
    mean_pretrend = mean(abs(pre_coefs$estimate)),
    max_treatment_effect = max(abs(post_coefs$estimate)),
    mean_treatment_effect = mean(post_coefs$estimate),
    ratio_mean = mean(abs(post_coefs$estimate)) / max(abs(pre_coefs$estimate))
  )
}

# Separate pre and post
pre_coefs <- coefs %>% filter(e < 0)
post_coefs <- coefs %>% filter(e >= 0)

cat(glue("Loaded data: {nrow(coefs)} coefficients, {nrow(honestdid)} M values\n"))

################################################################################
# FIGURE 1: EVENT STUDY WITH HONESTDID BOUNDS
################################################################################

cat("Creating Figure 1: Event Study with HonestDiD Bounds...\n")

# Prepare data for HonestDiD ribbons
# Note: HonestDiD typically gives bounds for aggregated treatment effect
# For visualization, we'll show them as horizontal bands in post-period

fig1_data <- coefs %>%
  mutate(
    period = ifelse(e < 0, "Pre-treatment", "Post-treatment")
  )

# Main event study plot
p1_main <- ggplot(fig1_data, aes(x = e, y = estimate)) +
  # HonestDiD bounds as horizontal ribbons (simplified visualization)
  # M=0 bounds
  geom_rect(
    data = honestdid %>% filter(M == 0),
    aes(xmin = 0, xmax = max(fig1_data$e), ymin = lb, ymax = ub),
    fill = "lightblue", alpha = 0.2, inherit.aes = FALSE
  ) +
  # M=1 bounds
  geom_rect(
    data = honestdid %>% filter(M == 1),
    aes(xmin = 0, xmax = max(fig1_data$e), ymin = lb, ymax = ub),
    fill = "orange", alpha = 0.15, inherit.aes = FALSE
  ) +
  # M=2 bounds
  geom_rect(
    data = honestdid %>% filter(M == 2),
    aes(xmin = 0, xmax = max(fig1_data$e), ymin = lb, ymax = ub),
    fill = "red", alpha = 0.1, inherit.aes = FALSE
  ) +
  # Point estimates and CIs
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", size = 0.8) +
  geom_pointrange(aes(ymin = lo, ymax = hi, color = period), size = 0.5) +
  geom_line(color = "black", alpha = 0.6) +
  scale_color_manual(values = c("Pre-treatment" = "darkred", "Post-treatment" = "darkgreen")) +
  labs(
    title = "Event Study with HonestDiD Robust Bounds",
    subtitle = "Shaded regions show robust confidence sets for M=0 (light blue), M=1 (orange), M=2 (red)",
    x = "Event Time (months relative to treatment)",
    y = "Coefficient Estimate",
    color = "Period"
  ) +
  my_theme

# Zoomed pre-treatment panel
p1_pre <- ggplot(pre_coefs, aes(x = e, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_smooth(method = "lm", se = TRUE, color = "blue", fill = "lightblue", alpha = 0.3) +
  geom_pointrange(aes(ymin = lo, ymax = hi), color = "darkred", size = 0.6) +
  geom_point(data = pre_coefs %>% filter(p_value < 0.05),
             aes(x = e, y = estimate), color = "red", size = 3, shape = 8) +
  labs(
    title = "Pre-treatment Detail",
    subtitle = "Stars indicate p<0.05",
    x = "Event Time",
    y = "Estimate"
  ) +
  my_theme +
  theme(legend.position = "none")

# Combine
fig1 <- p1_main + p1_pre + plot_layout(widths = c(3, 1))

ggsave(
  filename = file.path(FIG_DIR, "fig1_event_study_honestdid.png"),
  plot = fig1,
  width = 14,
  height = 6,
  dpi = 300
)

cat("  Saved: fig1_event_study_honestdid.png\n")

################################################################################
# FIGURE 2: PRE-TREND PATTERN DECOMPOSITION
################################################################################

cat("Creating Figure 2: Pre-trend Pattern Decomposition...\n")

# Fit linear trend
pre_lm <- lm(estimate ~ e, data = pre_coefs)
pre_coefs <- pre_coefs %>%
  mutate(
    linear_fit = predict(pre_lm),
    residual = estimate - linear_fit
  )

# Panel A: Time series with trend
p2a <- ggplot(pre_coefs, aes(x = e)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_line(aes(y = linear_fit), color = "blue", size = 1, alpha = 0.7) +
  geom_ribbon(aes(ymin = linear_fit - 2*se, ymax = linear_fit + 2*se),
              fill = "lightblue", alpha = 0.3) +
  geom_pointrange(aes(y = estimate, ymin = lo, ymax = hi), color = "darkred") +
  geom_line(aes(y = estimate), color = "black", alpha = 0.5) +
  labs(
    title = "Pre-trend Coefficients with Linear Trend",
    subtitle = glue("Slope = {round(coef(pre_lm)[2], 6)}, R² = {round(summary(pre_lm)$r.squared, 3)}"),
    x = "Event Time",
    y = "Estimate"
  ) +
  my_theme

# Panel B: Residuals (deviations from trend)
p2b <- ggplot(pre_coefs, aes(x = e, y = residual)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_col(aes(fill = abs(residual) > 2*sd(residual)), alpha = 0.7) +
  scale_fill_manual(values = c("TRUE" = "red", "FALSE" = "steelblue")) +
  labs(
    title = "Residuals from Linear Trend",
    subtitle = "Red bars indicate large deviations (>2 SD)",
    x = "Event Time",
    y = "Residual"
  ) +
  my_theme +
  theme(legend.position = "none")

# Panel C: ACF plot (if enough data)
if (nrow(pre_coefs) > 3) {
  acf_data <- acf(pre_coefs$estimate, plot = FALSE)
  acf_df <- tibble(
    lag = acf_data$lag[-1],  # Remove lag 0
    acf = acf_data$acf[-1]
  )

  p2c <- ggplot(acf_df, aes(x = lag, y = acf)) +
    geom_hline(yintercept = 0, color = "gray50") +
    geom_hline(yintercept = c(-1.96/sqrt(nrow(pre_coefs)), 1.96/sqrt(nrow(pre_coefs))),
               linetype = "dashed", color = "blue") +
    geom_col(fill = "steelblue", alpha = 0.7) +
    labs(
      title = "Autocorrelation Function",
      subtitle = "Blue lines show 95% significance bounds",
      x = "Lag",
      y = "ACF"
    ) +
    my_theme
} else {
  p2c <- ggplot() + labs(title = "ACF: Insufficient data") + my_theme
}

# Panel D: Q-Q plot
p2d <- ggplot(pre_coefs, aes(sample = residual)) +
  stat_qq(color = "steelblue", size = 2) +
  stat_qq_line(color = "red", linetype = "dashed") +
  labs(
    title = "Q-Q Plot of Residuals",
    subtitle = "Check for normality",
    x = "Theoretical Quantiles",
    y = "Sample Quantiles"
  ) +
  my_theme

# Combine
fig2 <- (p2a + p2b) / (p2c + p2d) +
  plot_annotation(
    title = "Pre-trend Pattern Decomposition and Diagnostics",
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(
  filename = file.path(FIG_DIR, "fig2_pretrend_decomposition.png"),
  plot = fig2,
  width = 12,
  height = 10,
  dpi = 300
)

cat("  Saved: fig2_pretrend_decomposition.png\n")

################################################################################
# FIGURE 3: MAGNITUDE COMPARISON DASHBOARD
################################################################################

cat("Creating Figure 3: Magnitude Comparison Dashboard...\n")

# Panel A: Bar chart of key metrics
metrics_data <- tibble(
  metric = c("Max Pre-trend", "Mean Pre-trend", "Mean Treatment Effect", "Max Treatment Effect"),
  value = c(
    comp$max_pretrend[1],
    comp$mean_pretrend[1],
    comp$mean_treatment_effect[1],
    comp$max_treatment_effect[1]
  ),
  type = c("Pre-trend", "Pre-trend", "Treatment", "Treatment")
)

p3a <- ggplot(metrics_data, aes(x = reorder(metric, value), y = value, fill = type)) +
  geom_col(alpha = 0.8) +
  geom_text(aes(label = round(value, 3)), hjust = -0.2, size = 4) +
  coord_flip() +
  scale_fill_manual(values = c("Pre-trend" = "darkred", "Treatment" = "darkgreen")) +
  labs(
    title = "Magnitude Comparison",
    x = NULL,
    y = "Coefficient Value",
    fill = "Type"
  ) +
  my_theme

# Panel B: Ratio analysis
ratio_data <- tibble(
  ratio_type = c("Mean Effect /\nMax Pre-trend", "Max Effect /\nMax Pre-trend", "RMS Effect /\nRMS Pre-trend"),
  value = c(comp$ratio_mean[1], comp$ratio_max[1], comp$ratio_rms[1]),
  threshold = 2  # Threshold for "robust"
)

p3b <- ggplot(ratio_data, aes(x = ratio_type, y = value)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
  geom_hline(yintercept = 2, linetype = "dashed", color = "orange", size = 1) +
  geom_hline(yintercept = 3, linetype = "dashed", color = "green", size = 1) +
  geom_col(aes(fill = value > 2), alpha = 0.8, width = 0.6) +
  geom_text(aes(label = round(value, 2)), vjust = -0.5, size = 4.5, fontface = "bold") +
  scale_fill_manual(values = c("TRUE" = "darkgreen", "FALSE" = "darkorange")) +
  annotate("text", x = 0.6, y = 1, label = "1:1 (Equal)", hjust = 0, size = 3, color = "gray30") +
  annotate("text", x = 0.6, y = 2, label = "2:1 (Moderate)", hjust = 0, size = 3, color = "orange") +
  annotate("text", x = 0.6, y = 3, label = "3:1 (Strong)", hjust = 0, size = 3, color = "darkgreen") +
  labs(
    title = "Effect-to-Pretrend Ratios",
    subtitle = "Higher ratios indicate more robust effects",
    x = NULL,
    y = "Ratio Value"
  ) +
  my_theme +
  theme(legend.position = "none")

# Panel C: Distribution comparison
dist_data <- bind_rows(
  pre_coefs %>% mutate(period = "Pre-treatment", value = estimate),
  post_coefs %>% mutate(period = "Post-treatment", value = estimate)
)

p3c <- ggplot(dist_data, aes(x = value, fill = period)) +
  geom_density(alpha = 0.5) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  scale_fill_manual(values = c("Pre-treatment" = "darkred", "Post-treatment" = "darkgreen")) +
  labs(
    title = "Distribution of Coefficients",
    x = "Coefficient Value",
    y = "Density",
    fill = "Period"
  ) +
  my_theme

# Combine
fig3 <- (p3a + p3b) / p3c +
  plot_annotation(
    title = "Magnitude Comparison Dashboard",
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(
  filename = file.path(FIG_DIR, "fig3_magnitude_comparison.png"),
  plot = fig3,
  width = 12,
  height = 10,
  dpi = 300
)

cat("  Saved: fig3_magnitude_comparison.png\n")

################################################################################
# FIGURE 4: HONESTDID SENSITIVITY ANALYSIS
################################################################################

cat("Creating Figure 4: HonestDiD Sensitivity Analysis...\n")

# Panel A: Confidence bounds vs M
bounds_long <- honestdid %>%
  select(M, lb, ub) %>%
  pivot_longer(cols = c(lb, ub), names_to = "bound", values_to = "value")

p4a <- ggplot(honestdid, aes(x = M)) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", size = 1) +
  geom_ribbon(aes(ymin = lb, ymax = ub, fill = excludes_zero), alpha = 0.3) +
  geom_line(aes(y = lb), color = "blue", size = 1) +
  geom_line(aes(y = ub), color = "blue", size = 1) +
  geom_point(data = bounds_long, aes(y = value, shape = bound), size = 3) +
  scale_fill_manual(values = c("TRUE" = "darkgreen", "FALSE" = "darkorange"),
                    labels = c("TRUE" = "Excludes zero", "FALSE" = "Includes zero")) +
  scale_shape_manual(values = c("lb" = 25, "ub" = 24)) +
  labs(
    title = "HonestDiD Confidence Bounds vs M",
    subtitle = "Red dashed line at zero; shading shows confidence set",
    x = "M (Bound on Violations)",
    y = "Confidence Bound",
    fill = "Significance",
    shape = "Bound Type"
  ) +
  my_theme

# Panel B: Confidence set width vs M
width_M0 <- honestdid$width[honestdid$M == 0]

p4b <- ggplot(honestdid, aes(x = M, y = width)) +
  geom_line(color = "steelblue", size = 1.5) +
  geom_point(size = 3, color = "darkblue") +
  geom_hline(yintercept = width_M0, linetype = "dashed", color = "gray50") +
  geom_text(aes(label = round(width, 2)), vjust = -1, size = 3.5) +
  labs(
    title = "Confidence Set Width vs M",
    subtitle = glue("Width at M=0: {round(width_M0, 3)}"),
    x = "M (Bound on Violations)",
    y = "Width of Confidence Set"
  ) +
  my_theme

# Panel C: Width relative to M=0
honestdid_rel <- honestdid %>%
  mutate(width_rel = width / width_M0,
         pct_increase = (width_rel - 1) * 100)

p4c <- ggplot(honestdid_rel, aes(x = M, y = pct_increase)) +
  geom_line(color = "darkorange", size = 1.5) +
  geom_point(size = 3, color = "red") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_text(aes(label = paste0("+", round(pct_increase, 0), "%")), vjust = -1, size = 3.5) +
  labs(
    title = "Precision Degradation",
    subtitle = "Percentage increase in confidence set width relative to M=0",
    x = "M (Bound on Violations)",
    y = "% Increase in Width"
  ) +
  my_theme

# Combine
fig4 <- (p4a) / (p4b + p4c) +
  plot_annotation(
    title = "HonestDiD Sensitivity Analysis",
    subtitle = "How do treatment effect estimates change under bounded violations?",
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(
  filename = file.path(FIG_DIR, "fig4_honestdid_sensitivity.png"),
  plot = fig4,
  width = 12,
  height = 12,
  dpi = 300
)

cat("  Saved: fig4_honestdid_sensitivity.png\n")

################################################################################
# FIGURE 5: PATTERN COMPARISON ANALYSIS
################################################################################

cat("Creating Figure 5: Pattern Comparison Analysis...\n")

# Fit trends
pre_lm <- lm(estimate ~ e, data = pre_coefs)
post_lm <- lm(estimate ~ e, data = post_coefs)

# Extrapolate pre-trend into post period
post_coefs <- post_coefs %>%
  mutate(
    extrapolated = predict(pre_lm, newdata = post_coefs),
    deviation = estimate - extrapolated
  )

# Panel A: Pre vs Post trends overlay with extrapolation
p5a <- ggplot() +
  # Pre-treatment
  geom_smooth(data = pre_coefs, aes(x = e, y = estimate),
              method = "lm", se = TRUE, color = "darkred", fill = "pink", alpha = 0.3) +
  geom_pointrange(data = pre_coefs, aes(x = e, y = estimate, ymin = lo, ymax = hi),
                  color = "darkred", size = 0.5) +
  # Extrapolation into post period
  geom_line(data = post_coefs, aes(x = e, y = extrapolated),
            color = "darkred", linetype = "dashed", size = 1, alpha = 0.7) +
  # Post-treatment actual
  geom_smooth(data = post_coefs, aes(x = e, y = estimate),
              method = "lm", se = TRUE, color = "darkgreen", fill = "lightgreen", alpha = 0.3) +
  geom_pointrange(data = post_coefs, aes(x = e, y = estimate, ymin = lo, ymax = hi),
                  color = "darkgreen", size = 0.5) +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  labs(
    title = "Pre-trend Extrapolation vs Actual Treatment Effects",
    subtitle = "Dashed red line shows pre-trend extrapolation; green shows actual",
    x = "Event Time",
    y = "Estimate"
  ) +
  my_theme

# Panel B: Deviations from extrapolation
p5b <- ggplot(post_coefs, aes(x = e, y = deviation)) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  geom_col(aes(fill = deviation > 0), alpha = 0.7) +
  scale_fill_manual(values = c("TRUE" = "darkgreen", "FALSE" = "darkred")) +
  labs(
    title = "Deviation from Pre-trend Extrapolation",
    subtitle = "Positive = actual effect exceeds extrapolation",
    x = "Event Time",
    y = "Deviation"
  ) +
  my_theme +
  theme(legend.position = "none")

# Panel C: Correlation plot
p5c <- ggplot(post_coefs, aes(x = extrapolated, y = estimate)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  geom_point(size = 3, color = "steelblue", alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "darkgreen", fill = "lightgreen") +
  labs(
    title = "Actual vs Extrapolated Effects",
    subtitle = glue("Correlation: {round(cor(post_coefs$estimate, post_coefs$extrapolated), 3)}"),
    x = "Extrapolated (from pre-trend)",
    y = "Actual Treatment Effect"
  ) +
  my_theme

# Combine
fig5 <- p5a / (p5b + p5c) +
  plot_annotation(
    title = "Pattern Comparison: Pre-trends vs Treatment Effects",
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(
  filename = file.path(FIG_DIR, "fig5_pattern_comparison.png"),
  plot = fig5,
  width = 12,
  height = 12,
  dpi = 300
)

cat("  Saved: fig5_pattern_comparison.png\n")

################################################################################
# FIGURE 6: COMPREHENSIVE SUMMARY PLOT
################################################################################

cat("Creating Figure 6: Comprehensive Summary Plot...\n")

# Top: Event study with M=1 bounds highlighted
p6_top <- ggplot(coefs, aes(x = e, y = estimate)) +
  geom_rect(
    data = honestdid %>% filter(M == 1),
    aes(xmin = 0, xmax = max(coefs$e), ymin = lb, ymax = ub),
    fill = "orange", alpha = 0.2, inherit.aes = FALSE
  ) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", size = 0.8) +
  geom_pointrange(aes(ymin = lo, ymax = hi), size = 0.5) +
  geom_line(color = "black", alpha = 0.6) +
  labs(
    title = "Event Study with M=1 Robust Bounds (Key Robustness Check)",
    subtitle = "Orange shading: violations ≤ max observed pre-trend",
    x = "Event Time",
    y = "Estimate"
  ) +
  my_theme

# Middle left: Key metrics bars
p6_ml <- p3a + labs(title = "Key Magnitudes")

# Middle right: Width vs M
p6_mr <- p4b + labs(title = "Precision Degradation")

# Bottom: Summary statistics table as plot
summary_text <- glue(
  "SUMMARY STATISTICS\n\n",
  "Pre-trend Max: {round(comp$max_pretrend[1], 3)}\n",
  "Treatment Effect Mean: {round(comp$mean_treatment_effect[1], 3)}\n",
  "Effect/Pretrend Ratio: {round(comp$ratio_mean[1], 2)}x\n\n",
  "HonestDiD Robustness:\n",
  "  M=1 Significant: {honestdid$excludes_zero[honestdid$M==1]}\n",
  "  M=2 Significant: {honestdid$excludes_zero[honestdid$M==2]}\n\n",
  "ASSESSMENT: {comp$assessment[1]}"
)

p6_bottom <- ggplot() +
  annotate("text", x = 0.5, y = 0.5, label = summary_text,
           hjust = 0.5, vjust = 0.5, size = 4.5, family = "mono") +
  theme_void() +
  theme(plot.background = element_rect(fill = "gray95", color = "black", size = 1))

# Combine
fig6 <- p6_top / (p6_ml + p6_mr) / p6_bottom +
  plot_layout(heights = c(2, 1.5, 1)) +
  plot_annotation(
    title = "Comprehensive Summary: Pre-trend Violations vs Treatment Effects",
    subtitle = glue("Specification: {SPEC_NAME}"),
    theme = theme(plot.title = element_text(face = "bold", size = 16))
  )

ggsave(
  filename = file.path(FIG_DIR, "fig6_comprehensive_summary.png"),
  plot = fig6,
  width = 14,
  height = 14,
  dpi = 300
)

cat("  Saved: fig6_comprehensive_summary.png\n")

################################################################################
# DONE
################################################################################

cat("\n✓ All visualizations created successfully!\n")
cat(glue("  Output directory: {FIG_DIR}\n"))
cat("  Files created:\n")
cat("    - fig1_event_study_honestdid.png\n")
cat("    - fig2_pretrend_decomposition.png\n")
cat("    - fig3_magnitude_comparison.png\n")
cat("    - fig4_honestdid_sensitivity.png\n")
cat("    - fig5_pattern_comparison.png\n")
cat("    - fig6_comprehensive_summary.png\n\n")
