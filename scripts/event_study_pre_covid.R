#!/usr/bin/env Rscript
################################################################################
# event_study_pre_covid.R
#
# Event study for states treated BEFORE September 2021 (pre-COVID period)
# Excludes post-COVID adopters from the analysis
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(fixest)

cat("\n")
cat("================================================================================\n")
cat("EVENT STUDY: PRE-COVID PERIOD (Treatment before Sept 2021)\n")
cat("================================================================================\n\n")

# Define COVID cutoff
covid_cutoff <- as.Date("2021-09-01")

# Load data
cat("Loading data...\n")
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

# Prepare data
cat("Preparing data...\n")
panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0),
    # Classify treatment period
    treat_period = case_when(
      is.na(first_treat_date) ~ "Never",
      first_treat_date < covid_cutoff ~ "Pre-COVID",
      first_treat_date >= covid_cutoff ~ "Post-COVID"
    )
  ) %>%
  filter(!is.na(log_evictions))

# Keep only pre-COVID adopters and never-treated
panel_data_precovid <- panel_data %>%
  filter(treat_period %in% c("Pre-COVID", "Never"))

cat(sprintf("  Total observations: %d\n", nrow(panel_data_precovid)))
cat(sprintf("  States: %d\n", n_distinct(panel_data_precovid$state_abb)))
cat(sprintf("  Pre-COVID treated states: %d\n",
           sum(panel_data_precovid$treat_period == "Pre-COVID" & !duplicated(panel_data_precovid$state_abb))))
cat(sprintf("  Never-treated states: %d\n\n",
           sum(panel_data_precovid$treat_period == "Never" & !duplicated(panel_data_precovid$state_abb))))

# Create event time bins
cat("Creating event time bins...\n")
panel_data_precovid <- panel_data_precovid %>%
  mutate(
    event_bin = case_when(
      is.na(event_time) ~ "Never treated",
      event_time < -12 ~ "Exclude",
      event_time >= -12 & event_time <= 24 ~ as.character(event_time),
      event_time > 24 ~ "Exclude"
    )
  ) %>%
  filter(event_bin != "Exclude") %>%
  mutate(event_bin = factor(event_bin, levels = c("Never treated", as.character(-12:24))))

# Remove reference period for regression
panel_reg <- panel_data_precovid %>%
  filter(event_bin != "-1") %>%
  mutate(
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m"))
  )

cat(sprintf("  Regression sample: %d observations\n\n", nrow(panel_reg)))

# Run regression
cat("Running event study regression...\n")
es_model <- feols(log_evictions ~ event_bin | state_id + year_month,
                  data = panel_reg,
                  cluster = ~state_id)

cat("  Model estimated\n\n")

# Extract coefficients
coef_names <- names(coef(es_model))
event_coefs <- coef(es_model)[grepl("event_bin", coef_names)]
event_ses <- se(es_model)[grepl("event_bin", coef_names)]

# Create results dataframe
results <- data.frame(
  event_time = as.numeric(gsub("event_bin", "", names(event_coefs))),
  coef = as.numeric(event_coefs),
  se = as.numeric(event_ses),
  ci_lower = as.numeric(event_coefs) - 1.96 * as.numeric(event_ses),
  ci_upper = as.numeric(event_coefs) + 1.96 * as.numeric(event_ses),
  significant = abs(as.numeric(event_coefs) / as.numeric(event_ses)) > 1.96
)

# Add reference period
results <- rbind(results, data.frame(
  event_time = -1,
  coef = 0,
  se = 0,
  ci_lower = 0,
  ci_upper = 0,
  significant = FALSE
)) %>% arrange(event_time)

# Pre-trends test
cat("Testing pre-trends...\n")
pre_results <- results %>% filter(event_time >= -12 & event_time < 0 & event_time != -1)
chi_sq <- sum((pre_results$coef / pre_results$se)^2)
p_val <- 1 - pchisq(chi_sq, nrow(pre_results))

cat(sprintf("  Pre-treatment periods: %d\n", nrow(pre_results)))
cat(sprintf("  Joint test: χ²(%d) = %.2f, p = %.4f\n", nrow(pre_results), chi_sq, p_val))
if (p_val >= 0.05) {
  cat("  ✓ Parallel trends supported\n\n")
} else {
  cat("  ✗ Parallel trends violated\n\n")
}

# Create plot
cat("Creating plot...\n")
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
    title = "Event Study: Pre-COVID Adopters (Treatment before Sept 2021)",
    subtitle = "Two-way fixed effects regression with state and time fixed effects",
    x = "Months relative to gambling legalization",
    y = "Effect on log(eviction filings + 1)",
    caption = "95% confidence intervals. Standard errors clustered at state level. Reference period: t = -1."
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    axis.title = element_text(size = 11),
    legend.position = "bottom"
  )

# Save outputs
dir.create("output/csdid_pretrends/pre_covid", showWarnings = FALSE, recursive = TRUE)
ggsave("output/csdid_pretrends/pre_covid/event_study_pre_covid.pdf", p, width = 12, height = 7)
ggsave("output/csdid_pretrends/pre_covid/event_study_pre_covid.png", p, width = 12, height = 7, dpi = 300)
write.csv(results, "output/csdid_pretrends/pre_covid/event_study_results.csv", row.names = FALSE)

cat("  Saved outputs\n\n")

cat("================================================================================\n")
cat("COMPLETE!\n")
cat("================================================================================\n\n")

cat("Output files:\n")
cat("  • output/csdid_pretrends/pre_covid/event_study_pre_covid.pdf\n")
cat("  • output/csdid_pretrends/pre_covid/event_study_results.csv\n\n")
