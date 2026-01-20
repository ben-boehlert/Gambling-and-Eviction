#!/usr/bin/env Rscript
################################################################################
# event_study_sun_abraham.R
#
# Estimate event study using Sun-Abraham (2021) interaction-weighted estimator
# This addresses treatment effect heterogeneity across cohorts
#
# Reference: Sun & Abraham (2021) "Estimating Dynamic Treatment Effects in
#            Event Studies with Heterogeneous Treatment Effects"
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(fixest)

cat("\n")
cat("================================================================================\n")
cat("SUN-ABRAHAM EVENT STUDY ESTIMATOR\n")
cat("================================================================================\n\n")

# Load and prepare data
cat("Loading data...\n")
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0),
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m"))
  ) %>%
  filter(!is.na(log_evictions))

# Create cohort variable (year-month of first treatment, 0 if never treated)
panel_data <- panel_data %>%
  mutate(
    cohort = ifelse(is.na(first_treat_date), 0,
                   as.integer(format(first_treat_date, "%Y%m")))
  )

cat(sprintf("  Total observations: %d\n", nrow(panel_data)))
cat(sprintf("  States: %d\n", n_distinct(panel_data$state_id)))
cat(sprintf("  Treatment cohorts: %d\n", n_distinct(panel_data$cohort[panel_data$cohort > 0])))
cat(sprintf("  Never-treated states: %d\n\n", sum(panel_data$cohort == 0 & !duplicated(panel_data$state_id))))

# Restrict to event study window
panel_data <- panel_data %>%
  filter(
    cohort == 0 |  # Never treated
    (event_time >= -12 & event_time <= 24)  # Or within event window
  )

cat(sprintf("After restricting to [-12, +24] window:\n"))
cat(sprintf("  Observations: %d\n", nrow(panel_data)))
cat(sprintf("  States: %d\n\n", n_distinct(panel_data$state_id)))

# ========================================================================
# Sun-Abraham Estimation
# ========================================================================

cat("Estimating Sun-Abraham model...\n")
cat("This uses interaction weighting to account for treatment timing\n\n")

# Use sunab() function in fixest for Sun-Abraham estimation
# Syntax: sunab(cohort_var, time_var)
# Reference period is -1 (automatically)
sa_model <- feols(log_evictions ~ sunab(cohort, event_time) | state_id + year_month,
                  data = panel_data,
                  cluster = ~state_id)

cat("Model estimated!\n\n")

# ========================================================================
# Extract and Format Results
# ========================================================================

cat("Extracting results...\n")

# Get coefficients
sa_coefs <- coef(sa_model)
sa_se <- se(sa_model)

# Extract event time from coefficient names
# Format: "event_time::X:cohort::Y" where X is the event time
extract_event_time <- function(name) {
  # Pattern: event_time::NUMBER
  match <- regexpr("event_time::(-?[0-9]+)", name)
  if (match[1] > 0) {
    full_match <- regmatches(name, match)
    event_t <- as.numeric(gsub("event_time::", "", full_match))
    return(event_t)
  }
  return(NA_real_)
}

# Create results data frame
coef_names <- names(sa_coefs)
sunab_coefs <- coef_names[grepl("event_time::", coef_names)]

results <- data.frame(
  coef_name = sunab_coefs,
  event_time_raw = sapply(sunab_coefs, extract_event_time),
  coef = sa_coefs[sunab_coefs],
  se = sa_se[sunab_coefs],
  stringsAsFactors = FALSE
) %>%
  filter(!is.na(event_time_raw)) %>%
  rename(event_time = event_time_raw) %>%
  mutate(
    ci_lower = coef - 1.96 * se,
    ci_upper = coef + 1.96 * se,
    significant = abs(coef / se) > 1.96
  ) %>%
  arrange(event_time)

# Add reference period
results <- bind_rows(
  results,
  data.frame(
    coef_name = "Reference",
    event_time = -1,
    coef = 0,
    se = 0,
    ci_lower = 0,
    ci_upper = 0,
    significant = FALSE
  )
) %>%
  arrange(event_time)

cat(sprintf("  Extracted %d event time coefficients\n", nrow(results) - 1))
cat(sprintf("  Event time range: %d to %d\n\n", min(results$event_time), max(results$event_time)))

# ========================================================================
# Pre-trends Test
# ========================================================================

cat("Pre-trends test (Sun-Abraham estimator):\n")
cat("========================================================================\n")

pre_results <- results %>% filter(event_time >= -12 & event_time < 0 & event_time != -1)

if (nrow(pre_results) > 0) {
  # Joint test
  chi_sq <- sum((pre_results$coef / pre_results$se)^2)
  df <- nrow(pre_results)
  p_val <- 1 - pchisq(chi_sq, df)

  cat(sprintf("  Number of pre-treatment periods: %d\n", df))
  cat(sprintf("  Joint test: χ²(%d) = %.2f, p = %.4f\n\n", df, chi_sq, p_val))

  if (p_val >= 0.05) {
    cat("  ✓ Fail to reject H0: Pre-trends not significantly different from zero\n")
    cat("    (Parallel trends assumption supported)\n\n")
  } else {
    cat("  ✗ Reject H0: Pre-trends significantly different from zero\n")
    cat("    (Parallel trends assumption violated)\n\n")
  }
}

# ========================================================================
# Treatment Effects Summary
# ========================================================================

cat("Treatment effects summary:\n")
cat("========================================================================\n")

post_results <- results %>% filter(event_time >= 0 & event_time <= 24)

if (nrow(post_results) > 0) {
  n_sig <- sum(post_results$significant)
  avg_effect <- mean(post_results$coef)

  cat(sprintf("  Post-treatment periods: %d\n", nrow(post_results)))
  cat(sprintf("  Significant at 5%% level: %d (%.1f%%)\n", n_sig, 100 * n_sig / nrow(post_results)))
  cat(sprintf("  Average effect: %.4f\n", avg_effect))
  cat(sprintf("  Range: [%.4f, %.4f]\n\n", min(post_results$coef), max(post_results$coef)))
}

# ========================================================================
# Create Plot
# ========================================================================

cat("Creating Sun-Abraham event study plot...\n")

p <- ggplot(results, aes(x = event_time, y = coef)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.5) +
  geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "darkgreen") +
  geom_line(color = "darkgreen", linewidth = 1) +
  geom_point(aes(shape = event_time < 0), color = "darkgreen", size = 2.5) +
  scale_shape_manual(values = c("TRUE" = 1, "FALSE" = 19),
                     labels = c("Pre-treatment", "Post-treatment"),
                     name = "") +
  labs(
    title = "Event Study: Sun-Abraham Estimator",
    subtitle = "Interaction-weighted estimator robust to treatment effect heterogeneity",
    x = "Months relative to gambling legalization",
    y = "Effect on log(eviction filings + 1)",
    caption = "95% confidence intervals. Standard errors clustered at state level.\nReference period: t = -1. Accounts for staggered treatment timing."
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  ) +
  annotate("rect",
           xmin = -12.5,
           xmax = -0.5,
           ymin = -Inf, ymax = Inf,
           alpha = 0.1, fill = "orange") +
  annotate("text",
           x = -6.5,
           y = Inf,
           label = "Pre-treatment window\n(12 months for parallel trends test)",
           vjust = 1.5, hjust = 0.5,
           size = 3, color = "orange4", fontface = "italic")

dir.create("output/csdid_pretrends/figures", showWarnings = FALSE, recursive = TRUE)
ggsave("output/csdid_pretrends/figures/event_study_sun_abraham.pdf", p,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/figures/event_study_sun_abraham.png", p,
       width = 12, height = 7, dpi = 300)

cat("  Saved plot\n\n")

# ========================================================================
# Save Results
# ========================================================================

write.csv(results, "output/csdid_pretrends/sun_abraham_results.csv", row.names = FALSE)

cat("Files saved:\n")
cat("  • output/csdid_pretrends/figures/event_study_sun_abraham.pdf\n")
cat("  • output/csdid_pretrends/figures/event_study_sun_abraham.png\n")
cat("  • output/csdid_pretrends/sun_abraham_results.csv\n\n")

# ========================================================================
# Model Comparison
# ========================================================================

cat("Comparison with TWFE:\n")
cat("========================================================================\n")

# Standard TWFE for comparison
twfe_model <- feols(log_evictions ~ i(event_time, ref = -1) | state_id + year_month,
                   data = panel_data,
                   cluster = ~state_id)

# Compare some key coefficients
compare_times <- c(-6, 0, 6, 12)
comparison <- data.frame()

for (t in compare_times) {
  sa_coef <- results$coef[results$event_time == t]
  sa_se <- results$se[results$event_time == t]

  twfe_coef_name <- paste0("event_time::", t)
  if (twfe_coef_name %in% names(coef(twfe_model))) {
    twfe_coef <- coef(twfe_model)[twfe_coef_name]
    twfe_se <- se(twfe_model)[twfe_coef_name]
  } else {
    twfe_coef <- NA
    twfe_se <- NA
  }

  comparison <- rbind(comparison, data.frame(
    event_time = t,
    SA_coef = ifelse(length(sa_coef) > 0, sa_coef, NA),
    SA_se = ifelse(length(sa_se) > 0, sa_se, NA),
    TWFE_coef = twfe_coef,
    TWFE_se = twfe_se
  ))
}

print(comparison)
cat("\n")

cat("Note: Sun-Abraham accounts for treatment timing heterogeneity,\n")
cat("      while TWFE can be biased with staggered adoption.\n\n")

# ========================================================================
# Summary
# ========================================================================

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n\n")

cat("Sun-Abraham estimator advantages:\n")
cat("  1. Robust to heterogeneous treatment effects across cohorts\n")
cat("  2. Uses interaction weighting to aggregate cohort-specific estimates\n")
cat("  3. Avoids negative weighting problems in TWFE\n")
cat("  4. More appropriate for staggered adoption designs\n\n")

cat(sprintf("Your analysis has %d treatment cohorts with staggered timing.\n",
           n_distinct(panel_data$cohort[panel_data$cohort > 0])))
cat("Sun-Abraham is recommended for this setting.\n\n")

if (exists("p_val") && !is.na(p_val)) {
  if (p_val >= 0.05) {
    cat("✓ Pre-trends test: PASSED (p = %.4f)\n", p_val)
  } else {
    cat("✗ Pre-trends test: FAILED (p = %.4f)\n", p_val)
  }
}

if (exists("n_sig")) {
  if (n_sig == 0) {
    cat("✓ Post-treatment: No significant effects detected\n")
  } else {
    cat(sprintf("⚠ Post-treatment: %d/%d periods significant\n", n_sig, nrow(post_results)))
  }
}

cat("\n================================================================================\n\n")
