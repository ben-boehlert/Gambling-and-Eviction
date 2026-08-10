#!/usr/bin/env Rscript
################################################################################
# pretrend_sources.R
#
# Investigates which states are driving the differential pre-trend pattern
# identified in long_diff_trend_sensitivity.R.
#
# Procedure:
#   1. For each state in the panel (treated + never-treated), compute the
#      mean annual county-level pre-trend (2016-17 → 2018-19), with SE.
#   2. Identify outlier states with the largest positive and negative trends.
#   3. Rerun the long-difference and trend sensitivity dropping suspected
#      outlier states (largest positive pre-trend treated states).
#   4. Re-test the differential pre-trend in the reduced sample.
#   5. Report whether the headline survives outlier exclusion.
#
# Outputs:
#   output/border_diagnostic/pretrend_sources/{
#     per_state_pretrend.csv,
#     long_diff_loo.csv,
#     trend_sensitivity_drop_outliers.csv,
#     plot.png
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "pretrend_sources")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

state_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb,
   1,"AL", 2,"AK", 4,"AZ", 5,"AR", 6,"CA", 8,"CO", 9,"CT",
  10,"DE",11,"DC",12,"FL",13,"GA",15,"HI",16,"ID",
  17,"IL",18,"IN",19,"IA",20,"KS",21,"KY",22,"LA",
  23,"ME",24,"MD",25,"MA",26,"MI",27,"MN",28,"MS",
  29,"MO",30,"MT",31,"NE",32,"NV",33,"NH",34,"NJ",
  35,"NM",36,"NY",37,"NC",38,"ND",39,"OH",40,"OK",
  41,"OR",42,"PA",44,"RI",45,"SC",46,"SD",47,"TN",
  48,"TX",49,"UT",50,"VT",51,"VA",53,"WA",54,"WV",
  55,"WI",56,"WY"
)

trump_2020 <- tibble::tribble(
  ~state_abb, ~trump_2020_share,
  "AL",62.0,"AK",53.1,"AZ",49.1,"AR",62.4,"CA",34.3,"CO",41.9,"CT",39.2,
  "DE",39.8,"FL",51.2,"GA",49.2,"HI",34.3,"ID",63.8,"IL",40.5,"IN",57.0,
  "IA",53.1,"KS",56.2,"KY",62.1,"LA",58.5,"MD",32.2,"MA",32.1,"MI",47.8,
  "MN",45.3,"MS",57.6,"MO",56.8,"MT",56.9,"NE",58.2,"NV",47.7,"NJ",41.4,
  "NM",43.5,"NY",37.7,"NC",49.9,"ND",65.1,"OH",53.3,"OK",65.4,"OR",40.4,
  "PA",48.8,"RI",38.6,"SC",55.1,"SD",61.8,"TN",60.7,"TX",52.1,"UT",58.1,
  "VT",30.7,"VA",44.0,"WA",38.8,"WV",68.6,"WI",48.8,"WY",69.9
)

DROP_STATES <- c("ME", "NH")
VERY_PRE_START <- as.Date("2016-01-01")
VERY_PRE_END   <- as.Date("2017-12-31")
PRE_START      <- as.Date("2018-01-01")
PRE_END        <- as.Date("2019-12-31")
LATE_START     <- as.Date("2024-01-01")
LATE_END       <- as.Date("2024-12-31")

yrs_pre_to_late <- 5.5
yrs_vpre_to_pre <- 2

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count),
         renter_occupied_housing_units =
           as.numeric(renter_occupied_housing_units),
         poverty_rate = as.numeric(poverty_rate)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date), !(state_abb %in% DROP_STATES))

state_treat_one <- read_csv(file.path(repo_root, "data", "raw",
                                       "state_month_panel_with_treatment.csv"),
                            show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

counties_per_state <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
ok_states <- counties_per_state %>%
  filter(n_counties >= 5L) %>% pull(state_abb)

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  left_join(trump_2020, by = "state_abb") %>%
  mutate(filings_per_1k = if_else(renter_occupied_housing_units > 0,
                                   1000 * filings_count /
                                     renter_occupied_housing_units,
                                   NA_real_),
         ever_treated = !is.na(treat_start))

county_means <- panel %>%
  mutate(
    period = case_when(
      month_date >= VERY_PRE_START & month_date <= VERY_PRE_END ~ "very_pre",
      month_date >= PRE_START      & month_date <= PRE_END      ~ "pre",
      month_date >= LATE_START     & month_date <= LATE_END     ~ "late",
      TRUE                                                      ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(fips, state_abb, ever_treated, trump_2020_share, period) %>%
  summarise(
    n_months = n(),
    y_rate = mean(filings_per_1k, na.rm = TRUE),
    pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
    poverty_rate = mean(poverty_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period,
              values_from = c(n_months, y_rate, pop_renter, poverty_rate)) %>%
  filter(n_months_very_pre >= 6L, n_months_pre >= 6L,
         n_months_late     >= 6L,
         is.finite(y_rate_very_pre), is.finite(y_rate_pre),
         is.finite(y_rate_late)) %>%
  mutate(
    annual_trend = (y_rate_pre - y_rate_very_pre) / yrs_vpre_to_pre,
    log_pop_pre  = log(pop_renter_pre),
    trump_c      = trump_2020_share - mean(trump_2020_share, na.rm = TRUE)
  )

cat("Restricted three-window panel:\n")
cat("  Counties:", nrow(county_means), "\n\n")

# ----------------------------- per-state pre-trend summary -------------------

per_state <- county_means %>%
  group_by(state_abb, ever_treated) %>%
  summarise(
    n_counties = n(),
    mean_annual_pretrend = mean(annual_trend, na.rm = TRUE),
    sd_annual_pretrend = sd(annual_trend, na.rm = TRUE),
    se_annual_pretrend = sd(annual_trend, na.rm = TRUE) / sqrt(n()),
    mean_pre_rate = mean(y_rate_pre, na.rm = TRUE),
    mean_late_rate = mean(y_rate_late, na.rm = TRUE),
    mean_long_diff = mean(y_rate_late - y_rate_pre, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_annual_pretrend))

write_csv(per_state, file.path(out_dir, "per_state_pretrend.csv"))

cat("=== PER-STATE ANNUAL PRE-TREND (2016-17 → 2018-19) ===\n")
print(per_state %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))),
      n = Inf)

# ----------------------------- per-state plot --------------------------------

per_state_plot <- per_state %>%
  arrange(mean_annual_pretrend) %>%
  mutate(state_abb = factor(state_abb, levels = state_abb))

p_per_state <- ggplot(per_state_plot,
                       aes(x = state_abb, y = mean_annual_pretrend,
                           color = ever_treated, shape = ever_treated)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = mean_annual_pretrend - 1.96 * se_annual_pretrend,
                    ymax = mean_annual_pretrend + 1.96 * se_annual_pretrend),
                width = 0.3, linewidth = 0.4) +
  geom_point(size = 2.5) +
  coord_flip() +
  scale_color_grey(start = 0.15, end = 0.55, name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  labs(x = NULL,
       y = "Mean county-level annual pre-trend\n(2016-17 → 2018-19)") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "plot.png"), p_per_state,
       width = 7.5, height = 5.5, dpi = 300, bg = "transparent")

# ----------------------------- leave-one-out long-difference -----------------

extract_treat_row <- function(fit, label) {
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  if (is.na(rn)) return(NULL)
  att <- as.numeric(ct[rn, "Estimate"])
  se  <- as.numeric(ct[rn, "Std. Error"])
  tibble(spec = label, att = att, se = se,
         ci_low = att - 1.96 * se, ci_high = att + 1.96 * se,
         p_value = as.numeric(ct[rn, "Pr(>|t|)"]),
         n_obs = fit$nobs)
}

cat("\n=== LEAVE-ONE-STATE-OUT LONG-DIFFERENCE (restricted sample) ===\n")

treated_states_in_sample <- per_state %>%
  filter(ever_treated) %>%
  pull(state_abb)

loo_results <- bind_rows(lapply(treated_states_in_sample, function(s) {
  cm_s <- county_means %>% filter(state_abb != s)
  fit <- feols(
    (y_rate_late - y_rate_pre) ~ ever_treated + y_rate_pre + log_pop_pre +
                                    poverty_rate_pre + trump_c,
    data = cm_s, cluster = ~state_abb
  )
  extract_treat_row(fit, sprintf("Drop %s", s))
}))

baseline_fit <- feols(
  (y_rate_late - y_rate_pre) ~ ever_treated + y_rate_pre + log_pop_pre +
                                  poverty_rate_pre + trump_c,
  data = county_means, cluster = ~state_abb
)
loo_results <- bind_rows(
  extract_treat_row(baseline_fit, "ALL TREATED STATES"),
  loo_results
) %>%
  mutate(across(where(is.numeric), ~ signif(.x, 3)))

write_csv(loo_results, file.path(out_dir, "long_diff_loo.csv"))
print(loo_results)

# ----------------------------- drop outliers, rerun sensitivity --------------

# Identify states whose mean pre-trend is statistically distinguishable from
# zero in the positive direction.
positive_outliers <- per_state %>%
  filter(ever_treated,
         mean_annual_pretrend - 1.96 * se_annual_pretrend > 0) %>%
  pull(state_abb)
cat("\nTreated states with statistically significant POSITIVE pre-trends:\n")
print(positive_outliers)

if (length(positive_outliers) > 0) {
  cat("\n=== TREND SENSITIVITY DROPPING POSITIVE-OUTLIER TREATED STATES ===\n")
  cm_dropped <- county_means %>%
    filter(!(state_abb %in% positive_outliers))
  cat("  Counties after drop:", nrow(cm_dropped),
      "  Treated states remaining:",
      n_distinct(cm_dropped$state_abb[cm_dropped$ever_treated]), "\n")

  # Re-test differential pre-trend in the reduced sample.
  ttest2 <- t.test(annual_trend ~ ever_treated, data = cm_dropped)
  cat("\nDifferential pre-trend after dropping outliers:\n")
  cat(sprintf("  Mean never-treated: %.4f\n",
              ttest2$estimate[1]))
  cat(sprintf("  Mean treated:       %.4f\n",
              ttest2$estimate[2]))
  cat(sprintf("  Difference: %.4f, t = %.2f, p = %.4f\n",
              ttest2$estimate[2] - ttest2$estimate[1],
              ttest2$statistic, ttest2$p.value))

  # Run sensitivity loop on the reduced sample.
  M_grid <- c(0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0)
  sens_results <- bind_rows(lapply(M_grid, function(M) {
    cm_M <- cm_dropped %>%
      mutate(cf_late = y_rate_pre + M * yrs_pre_to_late * annual_trend,
             ld_corrected = y_rate_late - cf_late)
    fit <- feols(
      ld_corrected ~ ever_treated + y_rate_pre + log_pop_pre +
                      poverty_rate_pre + trump_c,
      data = cm_M, cluster = ~state_abb
    )
    extract_treat_row(fit, sprintf("M=%.2f", M)) %>%
      mutate(M = M)
  }))
  write_csv(sens_results, file.path(out_dir,
                                     "trend_sensitivity_drop_outliers.csv"))

  cat("\nSensitivity bounds after dropping positive-outlier treated states:\n")
  print(sens_results)

  cat(sprintf(
    "\nDifferential pre-trends in reduced sample: t-test p = %.4f\n",
    ttest2$p.value))
}

cat("\nWrote outputs to:", out_dir, "\n")
