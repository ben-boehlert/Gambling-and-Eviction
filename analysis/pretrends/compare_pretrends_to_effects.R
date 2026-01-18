#!/usr/bin/env Rscript
################################################################################
# compare_pretrends_to_effects.R
#
# Comprehensive Comparison of Pre-trend Violations to Treatment Effects
# Using HonestDiD Sensitivity Analysis
#
# Following Rambachan & Roth (2023): "A More Credible Approach to Parallel Trends"
# and Roth (2022): "Pretest with caution: Event-Study Estimates after Testing
#                    for Parallel Trends"
#
# Key Question: Are treatment effects robust to pre-trend violations of
#               realistic magnitude?
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(tibble)
  library(tidyr)
})

################################################################################
# CONFIGURATION
################################################################################

# Paths
BASE_DIR <- "/Users/bb1806/Documents/GitHub/Gambling-and-Eviction"
EVAL_DIR <- file.path(BASE_DIR, "output/pretrends_evaluation")
SPEC_NAME <- "baseline"
SPEC_DIR <- file.path(EVAL_DIR, SPEC_NAME)
OUTPUT_DIR <- EVAL_DIR
FIG_DIR <- file.path(OUTPUT_DIR, "figures")

# Create output directories
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

# Logging
LOG_FILE <- file.path(OUTPUT_DIR, "comparison_log.txt")
if (file.exists(LOG_FILE)) file.remove(LOG_FILE)

log_msg <- function(msg, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  formatted <- glue("[{timestamp}] [{level}] {msg}")
  cat(formatted, "\n")
  cat(formatted, "\n", file = LOG_FILE, append = TRUE)
}

log_msg(paste(rep("=", 80), collapse=""))
log_msg("COMPARING PRE-TREND VIOLATIONS TO TREATMENT EFFECTS")
log_msg(paste(rep("=", 80), collapse=""))
log_msg(glue("Specification: {SPEC_NAME}"))
log_msg(glue("Input directory: {SPEC_DIR}"))
log_msg(glue("Output directory: {OUTPUT_DIR}"))

################################################################################
# SECTION 1: LOAD DATA
################################################################################

log_msg("\n--- Loading Data ---")

# Load event study coefficients
coefs_file <- file.path(SPEC_DIR, "event_study_coefs.csv")
if (!file.exists(coefs_file)) {
  stop(glue("Event study coefficients not found: {coefs_file}"))
}
coefs <- readr::read_csv(coefs_file, show_col_types = FALSE)
log_msg(glue("Loaded {nrow(coefs)} event study coefficients"))

# Load HonestDiD sensitivity results
honestdid_file <- file.path(SPEC_DIR, "honestdid_sensitivity.csv")
if (!file.exists(honestdid_file)) {
  stop(glue("HonestDiD results not found: {honestdid_file}"))
}
honestdid <- readr::read_csv(honestdid_file, show_col_types = FALSE)
log_msg(glue("Loaded HonestDiD results for M={paste(honestdid$M, collapse=', ')}"))

# Load power analysis (MDE)
power_file <- file.path(SPEC_DIR, "power_mde.csv")
mde_80 <- NA
if (file.exists(power_file)) {
  power <- readr::read_csv(power_file, show_col_types = FALSE)
  mde_row <- power %>% filter(target_power == 0.8)
  if (nrow(mde_row) > 0) {
    mde_80 <- mde_row$mde_slope[1]
    log_msg(glue("MDE (80% power): {round(mde_80, 4)}"))
  }
} else {
  log_msg("Power analysis file not found", level = "WARN")
}

# Load equivalence test
equiv_file <- file.path(SPEC_DIR, "equivalence_test.csv")
delta_star <- NA
if (file.exists(equiv_file)) {
  equiv <- readr::read_csv(equiv_file, show_col_types = FALSE)
  if ("delta_star_max" %in% names(equiv)) {
    delta_star <- equiv$delta_star_max[1]
    log_msg(glue("δ* (equivalence test): {round(delta_star, 4)}"))
  }
} else {
  log_msg("Equivalence test file not found", level = "WARN")
}

# Load pre-trends F-test
ftest_file <- file.path(SPEC_DIR, "pretrends_ftest.csv")
ftest_pval <- NA
if (file.exists(ftest_file)) {
  ftest <- readr::read_csv(ftest_file, show_col_types = FALSE)
  if ("p_value" %in% names(ftest)) {
    ftest_pval <- ftest$p_value[1]
    log_msg(glue("Pre-trends F-test p-value: {round(ftest_pval, 4)}"))
  }
}

################################################################################
# SECTION 2: SEPARATE PRE AND POST PERIODS
################################################################################

log_msg("\n--- Separating Pre and Post Periods ---")

# Separate pre-treatment (e < 0) and post-treatment (e >= 0)
pre_coefs <- coefs %>% filter(e < 0) %>% arrange(e)
post_coefs <- coefs %>% filter(e >= 0) %>% arrange(e)

log_msg(glue("Pre-treatment periods: {nrow(pre_coefs)} (e = {min(pre_coefs$e)} to {max(pre_coefs$e)})"))
log_msg(glue("Post-treatment periods: {nrow(post_coefs)} (e = {min(post_coefs$e)} to {max(post_coefs$e)})"))

################################################################################
# SECTION 3: CHARACTERIZE PRE-TREND VIOLATIONS
################################################################################

log_msg("\n--- Characterizing Pre-trend Violations ---")

# 3.1 Magnitude statistics
pre_max <- max(abs(pre_coefs$estimate))
pre_max_e <- pre_coefs$e[which.max(abs(pre_coefs$estimate))]
pre_mean_abs <- mean(abs(pre_coefs$estimate))
pre_rms <- sqrt(mean(pre_coefs$estimate^2))
pre_sd <- sd(pre_coefs$estimate)

log_msg(glue("Max absolute pre-trend: {round(pre_max, 4)} at e={pre_max_e}"))
log_msg(glue("Mean absolute pre-trend: {round(pre_mean_abs, 4)}"))
log_msg(glue("RMS of pre-trends: {round(pre_rms, 4)}"))
log_msg(glue("SD of pre-trends: {round(pre_sd, 4)}"))

# 3.2 Pattern analysis: Linear trend
pre_lm <- lm(estimate ~ e, data = pre_coefs)
pre_slope <- coef(pre_lm)[2]
pre_slope_se <- summary(pre_lm)$coefficients[2, 2]
pre_slope_t <- pre_slope / pre_slope_se
pre_slope_pval <- summary(pre_lm)$coefficients[2, 4]
pre_r2 <- summary(pre_lm)$r.squared

log_msg(glue("Linear trend slope: {round(pre_slope, 6)} (SE={round(pre_slope_se, 6)})"))
log_msg(glue("Linear trend t-stat: {round(pre_slope_t, 3)}, p-value: {round(pre_slope_pval, 4)}"))
log_msg(glue("Linear trend R²: {round(pre_r2, 4)}"))

# 3.3 Pattern analysis: Quadratic trend
pre_lm_quad <- lm(estimate ~ e + I(e^2), data = pre_coefs)
quad_coef <- coef(pre_lm_quad)[3]
quad_pval <- summary(pre_lm_quad)$coefficients[3, 4]
quad_r2 <- summary(pre_lm_quad)$r.squared

log_msg(glue("Quadratic coefficient: {round(quad_coef, 6)}, p-value: {round(quad_pval, 4)}"))
log_msg(glue("Quadratic model R²: {round(quad_r2, 4)}"))

# 3.4 Monotonicity test
pre_diffs <- diff(pre_coefs$estimate)
n_pos <- sum(pre_diffs > 0)
n_neg <- sum(pre_diffs < 0)
monotonic <- (n_pos == 0) | (n_neg == 0)

log_msg(glue("Monotonicity: {n_pos} increases, {n_neg} decreases, monotonic={monotonic}"))

# 3.5 Autocorrelation
if (requireNamespace("lmtest", quietly = TRUE)) {
  dw_test <- lmtest::dwtest(pre_lm)
  log_msg(glue("Durbin-Watson statistic: {round(dw_test$statistic, 4)}, p-value: {round(dw_test$p.value, 4)}"))
} else {
  log_msg("lmtest package not available for Durbin-Watson test", level = "WARN")
}

# 3.6 Statistical significance of pre-trends
pre_sig <- sum(pre_coefs$p_value < 0.05)
log_msg(glue("Significant pre-trends (p<0.05): {pre_sig} out of {nrow(pre_coefs)}"))

################################################################################
# SECTION 4: CHARACTERIZE TREATMENT EFFECTS
################################################################################

log_msg("\n--- Characterizing Treatment Effects ---")

# 4.1 Magnitude statistics
post_mean <- mean(post_coefs$estimate)
post_median <- median(post_coefs$estimate)
post_max <- max(abs(post_coefs$estimate))
post_max_e <- post_coefs$e[which.max(abs(post_coefs$estimate))]
post_rms <- sqrt(mean(post_coefs$estimate^2))

log_msg(glue("Mean treatment effect: {round(post_mean, 4)}"))
log_msg(glue("Median treatment effect: {round(post_median, 4)}"))
log_msg(glue("Max absolute treatment effect: {round(post_max, 4)} at e={post_max_e}"))
log_msg(glue("RMS of treatment effects: {round(post_rms, 4)}"))

# 4.2 Statistical significance
post_sig <- sum(post_coefs$p_value < 0.05)
post_avg_pval <- mean(post_coefs$p_value)

log_msg(glue("Significant post-treatment effects (p<0.05): {post_sig} out of {nrow(post_coefs)}"))
log_msg(glue("Average p-value of treatment effects: {round(post_avg_pval, 4)}"))

# 4.3 Dynamic pattern
early <- post_coefs %>% filter(e >= 0, e <= 6)
mid <- post_coefs %>% filter(e > 6, e <= 12)
late <- post_coefs %>% filter(e > 12)

log_msg(glue("\nDynamic pattern:"))
log_msg(glue("  Early (e=0-6): mean={round(mean(early$estimate), 4)}, {sum(early$p_value<0.05)}/{nrow(early)} sig"))
log_msg(glue("  Mid (e=7-12): mean={round(mean(mid$estimate), 4)}, {sum(mid$p_value<0.05)}/{nrow(mid)} sig"))
log_msg(glue("  Late (e=13+): mean={round(mean(late$estimate), 4)}, {sum(late$p_value<0.05)}/{nrow(late)} sig"))

################################################################################
# SECTION 5: DIRECT COMPARISON
################################################################################

log_msg("\n--- Direct Comparison: Pre-trends vs Effects ---")

# 5.1 Magnitude ratios
ratio_mean <- mean(abs(post_coefs$estimate)) / pre_max
ratio_max <- post_max / pre_max
ratio_rms <- post_rms / pre_rms

log_msg(glue("Ratio (mean effect / max pretrend): {round(ratio_mean, 2)}"))
log_msg(glue("Ratio (max effect / max pretrend): {round(ratio_max, 2)}"))
log_msg(glue("Ratio (RMS effect / RMS pretrend): {round(ratio_rms, 2)}"))

interpretation <- if (ratio_mean > 3) {
  "STRONG - Effects >> pre-trends"
} else if (ratio_mean > 2) {
  "MODERATE - Effects notably larger than pre-trends"
} else if (ratio_mean > 1) {
  "WEAK - Effects only slightly larger than pre-trends"
} else {
  "CONCERNING - Effects not larger than pre-trends"
}
log_msg(glue("Interpretation: {interpretation}"))

# 5.2 Signal-to-noise ratio
snr <- post_mean / pre_sd
log_msg(glue("\nSignal-to-noise ratio: {round(snr, 2)}"))
log_msg(glue("Interpretation: Mean effect is {round(snr, 2)} SDs of pre-trend noise"))

# 5.3 Comparison to MDE
if (!is.na(mde_80)) {
  effect_to_mde <- post_mean / mde_80
  log_msg(glue("\nEffect-to-MDE ratio: {round(effect_to_mde, 2)}"))
  if (effect_to_mde > 1) {
    log_msg("  → Effect larger than MDE: adequately powered")
  } else {
    log_msg("  → Effect smaller than MDE: may be underpowered")
  }
}

################################################################################
# SECTION 6: HONESTDID SENSITIVITY ANALYSIS
################################################################################

log_msg("\n--- HonestDiD Sensitivity Analysis ---")

# Process HonestDiD results
honestdid_analysis <- honestdid %>%
  mutate(
    width = ub - lb,
    excludes_zero = (lb > 0) | (ub < 0),
    significant = ifelse(excludes_zero, "YES", "NO")
  ) %>%
  arrange(M)

# Find breakdown point
breakdown_M <- honestdid_analysis %>%
  filter(!excludes_zero) %>%
  slice(1) %>%
  pull(M)

if (length(breakdown_M) == 0) {
  breakdown_M <- NA
  log_msg("Results robust to ALL tested M values (up to M=2)")
} else {
  log_msg(glue("Breakdown M value: {breakdown_M}"))
  log_msg(glue("  → Results lose significance at M={breakdown_M}"))
}

# Log results for each M
log_msg("\nResults by M value:")
for (i in 1:nrow(honestdid_analysis)) {
  row <- honestdid_analysis[i,]
  log_msg(glue("  M={row$M}: [{round(row$lb, 3)}, {round(row$ub, 3)}], width={round(row$width, 3)}, sig={row$significant}"))
}

# Compute width relative to M=0
width_M0 <- honestdid_analysis %>% filter(M == 0) %>% pull(width)
honestdid_analysis <- honestdid_analysis %>%
  mutate(width_rel_M0 = width / width_M0)

# Analyze precision degradation
log_msg("\nPrecision degradation:")
for (i in 1:nrow(honestdid_analysis)) {
  row <- honestdid_analysis[i,]
  pct_increase <- (row$width_rel_M0 - 1) * 100
  log_msg(glue("  M={row$M}: width is {round(pct_increase, 1)}% larger than M=0"))
}

################################################################################
# SECTION 7: PATTERN INVESTIGATION
################################################################################

log_msg("\n--- Pattern Investigation ---")

# 7.1 Compare pre vs post slopes
post_lm <- lm(estimate ~ e, data = post_coefs)
post_slope <- coef(post_lm)[2]
post_slope_se <- summary(post_lm)$coefficients[2, 2]

log_msg(glue("Pre-trend slope: {round(pre_slope, 6)}"))
log_msg(glue("Post-treatment slope: {round(post_slope, 6)}"))
slope_ratio <- abs(post_slope / pre_slope)
log_msg(glue("Slope ratio (post/pre): {round(slope_ratio, 2)}"))

if (abs(slope_ratio - 1) < 0.5) {
  log_msg("  → CONCERNING: Slopes are similar (potential extrapolation)")
} else {
  log_msg("  → REASSURING: Slopes are different (distinct treatment effect)")
}

# 7.2 Extrapolation test
# Predict post-period values using pre-trend linear fit
post_predicted <- predict(pre_lm, newdata = post_coefs)
post_actual <- post_coefs$estimate
extrapolation_error <- post_actual - post_predicted
extrapolation_corr <- cor(post_actual, post_predicted)

log_msg(glue("\nExtrapolation test:"))
log_msg(glue("  Correlation (actual vs extrapolated): {round(extrapolation_corr, 3)}"))
log_msg(glue("  Mean extrapolation error: {round(mean(extrapolation_error), 4)}"))
log_msg(glue("  RMS extrapolation error: {round(sqrt(mean(extrapolation_error^2)), 4)}"))

if (abs(extrapolation_corr) > 0.7) {
  log_msg("  → CONCERNING: High correlation suggests extrapolation")
} else {
  log_msg("  → REASSURING: Low correlation suggests true effect")
}

# 7.3 Placebo test: Do early pre-trends predict late pre-trends?
if (nrow(pre_coefs) > 4) {
  n_early <- floor(nrow(pre_coefs) / 2)
  early_pre <- pre_coefs[1:n_early,]
  late_pre <- pre_coefs[(n_early+1):nrow(pre_coefs),]

  placebo_lm <- lm(estimate ~ e, data = early_pre)
  late_predicted <- predict(placebo_lm, newdata = late_pre)
  placebo_corr <- cor(late_pre$estimate, late_predicted)

  log_msg(glue("\nPlacebo test (early pre-trends predicting late pre-trends):"))
  log_msg(glue("  Correlation: {round(placebo_corr, 3)}"))

  if (abs(placebo_corr) > 0.7) {
    log_msg("  → CONCERNING: Pre-trends are highly predictable (spurious trend)")
  } else {
    log_msg("  → REASSURING: Pre-trends not highly predictable (noise)")
  }
}

################################################################################
# SECTION 8: CREATE OUTPUT TABLES
################################################################################

log_msg("\n--- Creating Output Tables ---")

# 8.1 Main comparison table
comparison_table <- tibble(
  specification = SPEC_NAME,
  n_pre_periods = nrow(pre_coefs),
  n_post_periods = nrow(post_coefs),
  max_pretrend = pre_max,
  max_pretrend_at_e = pre_max_e,
  mean_pretrend = pre_mean_abs,
  rms_pretrend = pre_rms,
  sd_pretrend = pre_sd,
  pretrend_slope = pre_slope,
  pretrend_slope_pval = pre_slope_pval,
  pretrend_r2 = pre_r2,
  pretrend_ftest_pval = ftest_pval,
  n_sig_pretrends = pre_sig,
  max_treatment_effect = post_max,
  max_treatment_at_e = post_max_e,
  mean_treatment_effect = post_mean,
  median_treatment_effect = post_median,
  rms_treatment_effect = post_rms,
  n_sig_treatment_effects = post_sig,
  ratio_mean = ratio_mean,
  ratio_max = ratio_max,
  ratio_rms = ratio_rms,
  signal_to_noise = snr,
  mde_80pct = mde_80,
  effect_to_mde_ratio = if (!is.na(mde_80)) post_mean / mde_80 else NA,
  delta_star = delta_star
)

# Add HonestDiD results
for (i in 1:nrow(honestdid_analysis)) {
  M_val <- honestdid_analysis$M[i]
  M_str <- gsub("\\.", "", as.character(M_val))  # 0.5 -> 05
  comparison_table[[glue("honestdid_M{M_str}_lb")]] <- honestdid_analysis$lb[i]
  comparison_table[[glue("honestdid_M{M_str}_ub")]] <- honestdid_analysis$ub[i]
  comparison_table[[glue("honestdid_M{M_str}_sig")]] <- honestdid_analysis$excludes_zero[i]
}

comparison_table$breakdown_M <- breakdown_M

# Assessment
comparison_table$assessment <- if (ratio_mean > 3 && (is.na(breakdown_M) || breakdown_M >= 1)) {
  "ROBUST"
} else if (ratio_mean > 2 && (is.na(breakdown_M) || breakdown_M >= 0.5)) {
  "MODERATE"
} else {
  "WEAK"
}

comparison_table$assessment_rationale <- glue(
  "Effect-to-pretrend ratio = {round(ratio_mean, 2)}; ",
  "HonestDiD breakdown M = {ifelse(is.na(breakdown_M), 'none (robust to M=2)', as.character(breakdown_M))}"
)

# Save comparison table
comparison_file <- file.path(OUTPUT_DIR, "comparison_table.csv")
readr::write_csv(comparison_table, comparison_file)
log_msg(glue("Saved: {comparison_file}"))

# 8.2 Detailed HonestDiD table
honestdid_detailed <- honestdid_analysis %>%
  mutate(
    interpretation = case_when(
      M == 0 ~ "Exact parallel trends (baseline)",
      M == 0.5 ~ "Violations ≤ 0.5 × max pre-trend",
      M == 1 ~ "Violations ≤ max pre-trend (key robustness check)",
      M == 1.5 ~ "Violations ≤ 1.5 × max pre-trend",
      M == 2 ~ "Violations ≤ 2 × max pre-trend (conservative)",
      TRUE ~ as.character(M)
    )
  )

honestdid_file <- file.path(OUTPUT_DIR, "honestdid_detailed.csv")
readr::write_csv(honestdid_detailed, honestdid_file)
log_msg(glue("Saved: {honestdid_file}"))

# 8.3 Pre-trend pattern analysis
pretrend_pattern <- pre_coefs %>%
  mutate(
    linear_fit = predict(pre_lm),
    residual = estimate - linear_fit,
    abs_residual = abs(residual)
  ) %>%
  select(event_time = e, estimate, se, pval = p_value,
         significant = p_value, linear_fit, residual, abs_residual) %>%
  mutate(significant = significant < 0.05)

pattern_file <- file.path(OUTPUT_DIR, "pretrend_pattern_analysis.csv")
readr::write_csv(pretrend_pattern, pattern_file)
log_msg(glue("Saved: {pattern_file}"))

################################################################################
# SECTION 9: SUMMARY
################################################################################

log_msg(paste("\n", paste(rep("=", 80), collapse=""), sep=""))
log_msg("SUMMARY")
log_msg(paste(rep("=", 80), collapse=""))

log_msg("\n1. PRE-TREND VIOLATIONS:")
log_msg(glue("   - Max: {round(pre_max, 4)} at e={pre_max_e}"))
log_msg(glue("   - RMS: {round(pre_rms, 4)}"))
log_msg(glue("   - Linear slope: {round(pre_slope, 6)} (p={round(pre_slope_pval, 4)})"))

log_msg("\n2. TREATMENT EFFECTS:")
log_msg(glue("   - Mean: {round(post_mean, 4)}"))
log_msg(glue("   - Max: {round(post_max, 4)} at e={post_max_e}"))
log_msg(glue("   - Significant periods: {post_sig}/{nrow(post_coefs)}"))

log_msg("\n3. COMPARISON:")
log_msg(glue("   - Effect/Pretrend ratio: {round(ratio_mean, 2)}x"))
log_msg(glue("   - Signal-to-noise: {round(snr, 2)}"))
log_msg(glue("   - Assessment: {comparison_table$assessment}"))

log_msg("\n4. HONESTDID ROBUSTNESS:")
if (is.na(breakdown_M)) {
  log_msg("   - Results ROBUST to all M values tested (up to M=2)")
} else {
  log_msg(glue("   - Results robust up to M={breakdown_M}"))
}
log_msg(glue("   - M=1 significant: {honestdid_analysis$significant[honestdid_analysis$M==1]}"))

log_msg("\n5. OVERALL CONCLUSION:")
if (comparison_table$assessment == "ROBUST") {
  log_msg("   ✓ Treatment effects are ROBUST to realistic pre-trend violations")
  log_msg("     Evidence: Large effect-to-pretrend ratios AND HonestDiD robustness")
} else if (comparison_table$assessment == "MODERATE") {
  log_msg("   ~ Treatment effects show MODERATE robustness")
  log_msg("     Caution: Some sensitivity to violations, interpret carefully")
} else {
  log_msg("   ✗ Treatment effects show WEAK robustness")
  log_msg("     Warning: Significant sensitivity to pre-trend violations")
}

log_msg(paste("\n", paste(rep("=", 80), collapse=""), sep=""))
log_msg(glue("Analysis complete. Output files created in: {OUTPUT_DIR}"))
log_msg(paste(rep("=", 80), collapse=""))

cat("\n✓ Comparison analysis complete!\n")
cat(glue("  Output directory: {OUTPUT_DIR}\n"))
cat(glue("  Assessment: {comparison_table$assessment}\n\n"))
