#!/usr/bin/env Rscript
################################################################################
# sunab_pre_covid_yearly.R
#
# Sun-Abraham with YEARLY cohorts (not monthly) for pre-COVID period
# This aggregates sparse monthly cohorts to improve identification
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(fixest)

cat("\n")
cat("================================================================================\n")
cat("SUN-ABRAHAM: PRE-COVID with YEARLY COHORTS\n")
cat("================================================================================\n\n")

covid_cutoff <- as.Date("2021-09-01")

# Load data
cat("Loading data...\n")
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

# Prepare data with YEARLY cohorts
panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0),
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m")),
    treat_period = case_when(
      is.na(first_treat_date) ~ "Never",
      first_treat_date < covid_cutoff ~ "Pre-COVID",
      first_treat_date >= covid_cutoff ~ "Post-COVID"
    ),
    # Create YEARLY cohort variable (0 if never treated)
    cohort = ifelse(is.na(first_treat_date), 0,
                   as.integer(format(first_treat_date, "%Y")))
  ) %>%
  filter(!is.na(log_evictions))

# Keep only pre-COVID adopters and never-treated
panel_data_precovid <- panel_data %>%
  filter(treat_period %in% c("Pre-COVID", "Never")) %>%
  mutate(cohort = ifelse(treat_period == "Never", 0, cohort)) %>%
  filter(cohort == 0 | (event_time >= -12 & event_time <= 24))

cat(sprintf("  Total observations: %d\n", nrow(panel_data_precovid)))
cat(sprintf("  States: %d\n", n_distinct(panel_data_precovid$state_abb)))
cat(sprintf("  Pre-COVID yearly cohorts: %d\n", n_distinct(panel_data_precovid$cohort[panel_data_precovid$cohort > 0])))
cat(sprintf("  Never-treated states: %d\n\n",
           sum(panel_data_precovid$cohort == 0 & !duplicated(panel_data_precovid$state_abb))))

# Show cohort composition
cat("Yearly cohort composition:\n")
cohort_info <- panel_data_precovid %>%
  filter(cohort > 0) %>%
  group_by(cohort) %>%
  summarise(
    n_states = n_distinct(state_abb),
    states = paste(unique(state_abb), collapse = ", ")
  )
print(cohort_info)
cat("\n")

# Estimate Sun-Abraham model
cat("Estimating Sun-Abraham model with yearly cohorts...\n")
sa_model <- feols(log_evictions ~ sunab(cohort, event_time) | state_id + year_month,
                  data = panel_data_precovid,
                  cluster = ~state_id)

cat("Model estimated!\n\n")

# Extract coefficients
sa_coefs <- coef(sa_model)
sa_se <- se(sa_model)

# Extract event time
extract_event_time <- function(name) {
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

# Check for problematic SEs
cat("Standard error diagnostics:\n")
cat(sprintf("  Min SE: %.4f\n", min(results$se[results$event_time != -1])))
cat(sprintf("  Max SE: %.4f\n", max(results$se[results$event_time != -1])))
cat(sprintf("  Median SE: %.4f\n", median(results$se[results$event_time != -1])))
cat(sprintf("  Number with SE > 100: %d\n\n", sum(results$se > 100)))

# Pre-trends test
cat("Pre-trends test (Sun-Abraham estimator):\n")
cat("========================================================================\n")

pre_results <- results %>% filter(event_time >= -12 & event_time < 0 & event_time != -1)

if (nrow(pre_results) > 0) {
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

# Treatment effects summary
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

# Create plot
cat("Creating Sun-Abraham event study plot...\n")

p <- ggplot(results, aes(x = event_time, y = coef)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.5) +
  geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(aes(shape = event_time < 0), color = "steelblue", size = 2.5) +
  scale_shape_manual(values = c("TRUE" = 1, "FALSE" = 19),
                     labels = c("Pre-treatment", "Post-treatment"),
                     name = "") +
  labs(
    title = "Sun-Abraham Event Study: Pre-COVID Adopters (Yearly Cohorts)",
    subtitle = "Interaction-weighted estimator with cohorts aggregated by year",
    x = "Months relative to gambling legalization",
    y = "Effect on log(eviction filings + 1)",
    caption = "95% confidence intervals. Standard errors clustered at state level.\nReference period: t = -1. Cohorts: 2018, 2019, 2020, 2021."
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11),
    axis.title = element_text(size = 11),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

dir.create("output/csdid_pretrends/pre_covid", showWarnings = FALSE, recursive = TRUE)
ggsave("output/csdid_pretrends/pre_covid/sunab_pre_covid_yearly.pdf", p,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/pre_covid/sunab_pre_covid_yearly.png", p,
       width = 12, height = 7, dpi = 300)

cat("  Saved plot\n\n")

# Save results
write.csv(results, "output/csdid_pretrends/pre_covid/sunab_results_yearly.csv", row.names = FALSE)

cat("Files saved:\n")
cat("  • output/csdid_pretrends/pre_covid/sunab_pre_covid_yearly.pdf\n")
cat("  • output/csdid_pretrends/pre_covid/sunab_pre_covid_yearly.png\n")
cat("  • output/csdid_pretrends/pre_covid/sunab_results_yearly.csv\n\n")

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n\n")

cat("Sun-Abraham estimator for pre-COVID adopters (yearly cohorts):\n")
cat(sprintf("  %d treatment cohorts (by year)\n", n_distinct(panel_data_precovid$cohort[panel_data_precovid$cohort > 0])))
cat("  Aggregates monthly cohorts to improve identification\n")
cat("  Accounts for staggered treatment timing\n\n")

if (exists("p_val") && !is.na(p_val)) {
  if (p_val >= 0.05) {
    cat(sprintf("✓ Pre-trends test: PASSED (p = %.4f)\n", p_val))
  } else {
    cat(sprintf("✗ Pre-trends test: FAILED (p = %.4f)\n", p_val))
  }
}

if (exists("n_sig")) {
  cat(sprintf("⚠ Post-treatment: %d/%d periods significant\n", n_sig, nrow(post_results)))
}

cat("\n================================================================================\n\n")
