#!/usr/bin/env Rscript
################################################################################
# plot_event_study_deseasonalized.R
# Event study plot showing lead-up and post-treatment trends
# With calendar month FE to remove seasonality
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Creating Event Study Plot (De-seasonalized, Pre-COVID) ===\n\n")

# Source the main simulation
source("power_simulation_cs.R")

# Load panel data
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

# Use full panel (not just untreated sample) to see post-treatment
# But restrict to pre-COVID
panel_precovid <- panel_df %>%
  filter(month_date < as.Date("2020-03-01")) %>%
  left_join(treat_schedule_std %>% select(unit_id, g_id), by = "unit_id") %>%
  mutate(
    ever_treated = !is.na(g_id) & g_id > 0,
    month = month(month_date),
    # Event time: months relative to treatment (NA for never-treated)
    event_time = if_else(ever_treated, time_id - g_id, NA_integer_)
  )

cat(glue("Period: {min(panel_precovid$month_date)} to {max(panel_precovid$month_date)}\n"))
cat(glue("Total observations: {nrow(panel_precovid)}\n"))
cat(glue("Treated units: {sum(panel_precovid$ever_treated)}\n"))
cat(glue("Never-treated units: {sum(!panel_precovid$ever_treated)}\n\n"))

# Remove calendar month seasonality
cat("Removing calendar month fixed effects...\n")
m_deseason <- feols(outcome ~ 1 | unit_id + time_id + month, data = panel_precovid)
outcome_mean <- mean(panel_precovid$outcome, na.rm = TRUE)

panel_precovid <- panel_precovid %>%
  mutate(outcome_deseason = resid(m_deseason) + outcome_mean)

# For treated units: calculate mean by event time
treated_trends <- panel_precovid %>%
  filter(ever_treated) %>%
  group_by(event_time) %>%
  summarise(
    mean_outcome = mean(outcome_deseason, na.rm = TRUE),
    se_outcome = sd(outcome_deseason, na.rm = TRUE) / sqrt(n()),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  mutate(group = "Treated states (aligned by treatment date)")

# For never-treated: use all their data, create pseudo event time around median treatment date
median_g <- median(panel_precovid$g_id[panel_precovid$ever_treated], na.rm = TRUE)

never_treated_trends <- panel_precovid %>%
  filter(!ever_treated) %>%
  mutate(pseudo_event_time = time_id - median_g) %>%
  group_by(pseudo_event_time) %>%
  summarise(
    mean_outcome = mean(outcome_deseason, na.rm = TRUE),
    se_outcome = sd(outcome_deseason, na.rm = TRUE) / sqrt(n()),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  rename(event_time = pseudo_event_time) %>%
  mutate(group = "Never-treated states (pseudo event time)")

# Combine
plot_data <- bind_rows(treated_trends, never_treated_trends)

cat("Creating event study plot...\n")

# Event study plot
p <- ggplot(plot_data, aes(x = event_time, y = mean_outcome, color = group, group = group)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray30", linewidth = 1) +
  geom_line(linewidth = 1.3) +
  geom_point(size = 2.5, alpha = 0.7) +
  geom_ribbon(aes(ymin = mean_outcome - 1.96*se_outcome,
                  ymax = mean_outcome + 1.96*se_outcome,
                  fill = group),
              alpha = 0.15, color = NA) +
  annotate("text", x = 0, y = max(plot_data$mean_outcome, na.rm = TRUE),
           label = "Treatment", hjust = -0.1, vjust = 1.5,
           color = "gray30", size = 4, fontface = "bold") +
  scale_color_manual(
    values = c("Treated states (aligned by treatment date)" = "#E74C3C",
               "Never-treated states (pseudo event time)" = "#3498DB")
  ) +
  scale_fill_manual(
    values = c("Treated states (aligned by treatment date)" = "#E74C3C",
               "Never-treated states (pseudo event time)" = "#3498DB")
  ) +
  scale_x_continuous(
    breaks = seq(-36, 24, by = 6),
    limits = c(-36, 24)
  ) +
  labs(
    title = "Event Study: Pre- and Post-Treatment Trends",
    subtitle = "Calendar month seasonality removed | Pre-COVID period (2016-2020) | Aligned by treatment timing",
    x = "Months Relative to Treatment",
    y = "De-seasonalized Eviction Filings per 1,000 Renters",
    color = NULL,
    fill = NULL,
    caption = "Note: Shaded areas show 95% confidence intervals. Never-treated states aligned to median treatment date."
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 11, color = "gray30", margin = margin(b = 15)),
    plot.caption = element_text(hjust = 0, color = "gray40", size = 9),
    legend.position = "bottom",
    legend.text = element_text(size = 11),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(color = "gray90"),
    axis.title = element_text(size = 12)
  )

ggsave("event_study_deseasonalized_precovid.png", p, width = 14, height = 8, dpi = 300)
cat("Saved: event_study_deseasonalized_precovid.png\n\n")

# Test pre-treatment parallel trends
cat("=== Pre-Treatment Parallel Trends Test ===\n")
pre_treatment_data <- panel_precovid %>%
  filter(
    (ever_treated & event_time < 0) |  # Treated: before treatment
    !ever_treated                       # Never-treated: all periods
  ) %>%
  # Create common time variable for never-treated
  mutate(
    event_time_test = if_else(ever_treated, event_time, time_id - median_g)
  )

model_pre <- feols(outcome_deseason ~ event_time_test * ever_treated | unit_id,
                   data = pre_treatment_data)
print(summary(model_pre))

coef_interact <- coef(model_pre)["event_time_test:ever_treatedTRUE"]
se_interact <- se(model_pre)["event_time_test:ever_treatedTRUE"]
t_interact <- coef_interact / se_interact
p_interact <- 2 * pt(-abs(t_interact), df = model_pre$nobs - model_pre$nparams)

cat("\n=== PRE-TREATMENT RESULT ===\n")
cat(glue("Differential trend (pre-treatment): {round(coef_interact, 5)}\n"))
cat(glue("t-statistic: {round(t_interact, 3)}\n"))
cat(glue("p-value: {round(p_interact, 4)}\n\n"))

if (p_interact >= 0.05) {
  cat("✓ PARALLEL TRENDS HOLD in pre-treatment period (p >= 0.05)\n")
} else {
  cat("✗ PARALLEL TRENDS VIOLATED in pre-treatment period (p < 0.05)\n")
}

# Test post-treatment divergence
cat("\n=== Post-Treatment Divergence Test ===\n")
post_treatment_data <- panel_precovid %>%
  filter(ever_treated & event_time >= 0)  # Only treated, post-treatment

if (nrow(post_treatment_data) > 0) {
  model_post <- lm(outcome_deseason ~ event_time, data = post_treatment_data)
  post_slope <- coef(model_post)["event_time"]
  post_se <- summary(model_post)$coefficients["event_time", "Std. Error"]

  cat(glue("Post-treatment slope: {round(post_slope, 5)} per month\n"))
  cat(glue("Standard error: {round(post_se, 5)}\n\n"))

  # Average treatment effect in post-period
  avg_post <- mean(post_treatment_data$outcome_deseason, na.rm = TRUE)
  avg_never <- mean(panel_precovid$outcome_deseason[!panel_precovid$ever_treated], na.rm = TRUE)

  cat(glue("Average outcome (treated, post-treatment): {round(avg_post, 2)}\n"))
  cat(glue("Average outcome (never-treated, all periods): {round(avg_never, 2)}\n"))
  cat(glue("Difference: {round(avg_post - avg_never, 2)}\n"))
} else {
  cat("No post-treatment observations in pre-COVID period.\n")
}

# Summary statistics by event time window
cat("\n=== Summary by Event Time Window ===\n")
summary_by_window <- plot_data %>%
  mutate(
    window = case_when(
      event_time < -24 ~ "More than 2 years before",
      event_time >= -24 & event_time < -12 ~ "1-2 years before",
      event_time >= -12 & event_time < 0 ~ "Up to 1 year before",
      event_time >= 0 & event_time < 12 ~ "Up to 1 year after",
      event_time >= 12 ~ "More than 1 year after"
    )
  ) %>%
  filter(!is.na(window)) %>%
  group_by(group, window) %>%
  summarise(
    mean = round(mean(mean_outcome, na.rm = TRUE), 2),
    n_months = n(),
    .groups = "drop"
  )

print(summary_by_window)

cat("\nInterpretation:\n")
cat("This event study plot shows trends before and after treatment, with:\n")
cat("  - Calendar month seasonality removed (cleaner trends)\n")
cat("  - Treated states aligned by their actual treatment dates\n")
cat("  - Never-treated states shown for comparison (pseudo event time)\n")
cat("  - Pre-COVID period only (avoids structural break)\n")
