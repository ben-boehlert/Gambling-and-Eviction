#!/usr/bin/env Rscript
################################################################################
# long_diff_trend_sensitivity.R
#
# Bilinski-Hatfield-style linear-trend extrapolation sensitivity for the
# long-difference DiD headline. Analog of HonestDiD's relative-magnitudes
# framework, adapted for the long-difference (two-period) DiD structure.
#
# Procedure:
#   1. For each county, compute mean filings_per_1k in three windows:
#        very-pre   = 2016-2017 (~midpoint mid-2017)
#        pre        = 2018-2019 (~midpoint mid-2019)
#        late       = 2024     (~midpoint mid-2024)
#   2. Estimate county pre-trend: (pre_mean - very_pre_mean) / 2 years
#   3. Project linearly forward to mid-2024 (5 years from pre midpoint):
#        cf_late(M) = pre_mean + M * 5 * annual_trend
#      M = 0:  no extrapolation (= standard long-difference)
#      M = 1:  full pre-trend extends through post-period
#      M > 1:  post-period violation exceeds pre-period trend
#   4. Compute trend-corrected long-difference: late_mean - cf_late(M)
#   5. Regress on ever_treated with controls; vary M
#   6. Report breakdown M = largest M at which the CI excludes zero
#
# Outputs:
#   output/border_diagnostic/trend_sensitivity/{
#     bounds_by_M.csv,
#     plot.png,
#     breakdown.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "trend_sensitivity")
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

# Midpoints (in years) for trend projection.
yrs_pre_to_late <- as.numeric(difftime(LATE_START + 182,
                                        PRE_START + 365, units = "days")) / 365
yrs_vpre_to_pre <- as.numeric(difftime(PRE_START + 365,
                                        VERY_PRE_START + 365, units = "days")) / 365

cat("Trend projection setup:\n")
cat("  Years pre → late (midpoint to midpoint):", round(yrs_pre_to_late, 2), "\n")
cat("  Years very_pre → pre:", round(yrs_vpre_to_pre, 2), "\n\n")

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

# Per-county period means.
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
  # Require coverage in ALL THREE windows.
  filter(n_months_very_pre >= 6L,
         n_months_pre      >= 6L,
         n_months_late     >= 6L,
         is.finite(y_rate_very_pre), is.finite(y_rate_pre),
         is.finite(y_rate_late)) %>%
  mutate(
    # Annual pre-trend per county (rate change per year).
    annual_trend = (y_rate_pre - y_rate_very_pre) / yrs_vpre_to_pre,
    log_pop_pre  = log(pop_renter_pre),
    trump_c      = trump_2020_share - mean(trump_2020_share, na.rm = TRUE)
  )

cat("Three-window panel:\n")
cat("  Counties:", nrow(county_means), "\n")
cat("  Treated:", sum(county_means$ever_treated),
    "  Never-treated:", sum(!county_means$ever_treated), "\n")

# Pre-trend descriptives — sanity-check what pre-trend looks like across counties.
cat("\nDistribution of county-level annual pre-trends (2016-17 → 2018-19):\n")
print(summary(county_means$annual_trend))

# Are pre-trends systematically different between treated and never-treated?
ttest <- t.test(annual_trend ~ ever_treated, data = county_means)
cat("\nt-test on pre-trend by treatment status (asymmetric pre-trends are concerning):\n")
print(ttest)

# ----------------------------- sensitivity loop -------------------------------

M_grid <- c(0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0)

results <- bind_rows(lapply(M_grid, function(M) {
  cm_M <- county_means %>%
    mutate(
      cf_late = y_rate_pre + M * yrs_pre_to_late * annual_trend,
      ld_corrected = y_rate_late - cf_late
    )
  # Include y_rate_pre as control to match the headline spec (absorbs
  # regression-to-the-mean in baseline level). At M=0 this should reproduce
  # the headline long-difference exactly.
  fit <- feols(
    ld_corrected ~ ever_treated + y_rate_pre + log_pop_pre + poverty_rate_pre +
                    trump_c,
    data = cm_M, cluster = ~state_abb
  )
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  att <- as.numeric(ct[rn, "Estimate"])
  se  <- as.numeric(ct[rn, "Std. Error"])
  tibble(
    M = M,
    att = att,
    se = se,
    ci_low = att - 1.96 * se,
    ci_high = att + 1.96 * se,
    p_value = as.numeric(ct[rn, "Pr(>|t|)"]),
    n_obs = fit$nobs
  )
}))

write_csv(results, file.path(out_dir, "bounds_by_M.csv"))

cat("\n=== TREND-EXTRAPOLATION SENSITIVITY BOUNDS ===\n")
print(results %>%
        mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- breakdown M ------------------------------------

ci_excludes_zero <- function(lb, ub) (lb > 0) | (ub < 0)
breakdown <- results %>%
  arrange(M) %>%
  mutate(excludes_zero = ci_excludes_zero(ci_low, ci_high))
bd_value <- if (any(breakdown$excludes_zero)) {
  max(breakdown$M[breakdown$excludes_zero])
} else NA_real_

cat(sprintf("\nBreakdown M (largest M at which 95%% CI excludes zero): %s\n",
            if (is.na(bd_value))
              "0 (CI includes zero at M=0)"
            else as.character(bd_value)))

write_csv(tibble(
  breakdown_M = bd_value,
  att_at_M0 = results$att[results$M == 0],
  ci_low_at_M0 = results$ci_low[results$M == 0],
  ci_high_at_M0 = results$ci_high[results$M == 0]
), file.path(out_dir, "breakdown.csv"))

# ----------------------------- plot ------------------------------------------

p <- results %>%
  ggplot(aes(x = factor(M), y = att)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                width = 0.2, color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 2.5) +
  labs(x = "Sensitivity assumption M (fraction of linear pre-trend extending into post-period)",
       y = "Long-difference treatment effect on filings per 1,000 renters (95% CI)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "plot.png"), p,
       width = 7.0, height = 4.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
