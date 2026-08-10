#!/usr/bin/env Rscript
################################################################################
# long_difference_creative.R
#
# Three creative simple comparisons that bypass the COVID-dynamics problem
# entirely by collapsing time into pre/post averages:
#
#   1. LONG-DIFFERENCE DiD
#      For each county, compute mean log1p(filings) in 2018-2019 (pre-COVID,
#      pre-treatment for all states) and in 2024 (late, long-run post-treatment
#      for early adopters). Estimate the difference-in-difference on county
#      means. Treats all COVID-era dynamics as nuisance.
#
#   2. EXPOSURE-TIME GRADIENT
#      Plot (2024 mean − 2018-2019 mean) against months-since-legalization for
#      each treated state. If gambling has cumulative effects, long-exposure
#      states should show larger differences. Within-treated-states identifying
#      variation only.
#
#   3. LATE-PANEL CROSS-SECTION (the user's idea, literal)
#      Use only 2024 data. Run a simple cross-section: late_mean ~ ever_treated
#      + baseline (2018-2019 mean) + demographic controls. Compares treated
#      county levels vs never-treated, conditional on pre-treatment baseline.
#
# All three drop NH (data quality) and ME.
#
# Outputs:
#   output/border_diagnostic/long_difference/{
#     long_diff_county.csv,
#     long_diff_state.csv,
#     exposure_gradient.{csv,png},
#     late_cross_section.csv,
#     summary.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_difference")
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

DROP_STATES <- c("ME", "NH")

# Period definitions.
PRE_START  <- as.Date("2018-01-01")
PRE_END    <- as.Date("2019-12-31")
LATE_START <- as.Date("2024-01-01")
LATE_END   <- as.Date("2024-12-31")

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

# Restrict to states with ≥5 ETS counties (same convention as before).
counties_per_state <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
ok_states <- counties_per_state %>%
  filter(n_counties >= 5L) %>% pull(state_abb)

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         filings_per_1k = if_else(renter_occupied_housing_units > 0,
                                  1000 * filings_count /
                                    renter_occupied_housing_units,
                                  NA_real_),
         y_rate = log1p(pmax(filings_per_1k, 0)),
         ever_treated = !is.na(treat_start))

# County-level means for the pre and late windows.
county_means <- panel %>%
  mutate(
    period = case_when(
      month_date >= PRE_START & month_date <= PRE_END   ~ "pre",
      month_date >= LATE_START & month_date <= LATE_END ~ "late",
      TRUE                                              ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(fips, state_abb, ever_treated, treat_start, period) %>%
  summarise(
    n_months = n(),
    y_mean = mean(y, na.rm = TRUE),
    y_rate_mean = mean(y_rate, na.rm = TRUE),
    pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
    poverty_rate = mean(poverty_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period, values_from = c(n_months, y_mean,
                                                    y_rate_mean,
                                                    pop_renter, poverty_rate)) %>%
  filter(n_months_pre >= 6L, n_months_late >= 6L) %>%   # require coverage in both windows
  mutate(
    dy        = y_mean_late - y_mean_pre,
    dy_rate   = y_rate_mean_late - y_rate_mean_pre,
    pop_pre   = pop_renter_pre,
    pov_pre   = poverty_rate_pre,
    months_since_treat = as.integer((LATE_END - treat_start) / 30)
  )

write_csv(county_means, file.path(out_dir, "long_diff_county.csv"))

cat("County-level long-difference panel:\n")
cat("  Counties with coverage in both windows:", nrow(county_means), "\n")
cat("  Treated:", sum(county_means$ever_treated),
    "; never-treated:", sum(!county_means$ever_treated), "\n\n")

# ----------------------------- 1. LONG-DIFFERENCE DiD -------------------------

cat("=== 1. LONG-DIFFERENCE DiD (county-level mean differences) ===\n")

# Simple specification: dy ~ ever_treated + state-level controls + state cluster.
m1 <- feols(dy ~ ever_treated, data = county_means,
            cluster = ~state_abb)
m2 <- feols(dy ~ ever_treated + log(pop_pre) + pov_pre, data = county_means,
            cluster = ~state_abb)
m3 <- feols(dy ~ ever_treated + log(pop_pre) + pov_pre + y_mean_pre,
            data = county_means, cluster = ~state_abb)
m4 <- feols(dy_rate ~ ever_treated, data = county_means, cluster = ~state_abb)
m5 <- feols(dy_rate ~ ever_treated + log(pop_pre) + pov_pre,
            data = county_means, cluster = ~state_abb)

extract_treat_row <- function(fit, spec_label) {
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  att <- as.numeric(ct[rn, "Estimate"])
  se  <- as.numeric(ct[rn, "Std. Error"])
  tibble(spec = spec_label, att = att, se = se,
         ci_low = att - 1.96 * se,
         ci_high = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100,
         n_obs = fit$nobs)
}

ld_results <- bind_rows(
  extract_treat_row(m1, "log1p(filings), no controls"),
  extract_treat_row(m2, "log1p(filings), + pop + pov"),
  extract_treat_row(m3, "log1p(filings), + baseline level"),
  extract_treat_row(m4, "log1p(rate), no controls"),
  extract_treat_row(m5, "log1p(rate), + pop + pov")
)
write_csv(ld_results, file.path(out_dir, "long_diff_results.csv"))

cat("\n")
print(ld_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- 2. EXPOSURE-TIME GRADIENT ----------------------

cat("\n=== 2. EXPOSURE-TIME GRADIENT (treated states only) ===\n")

state_exposure <- county_means %>%
  filter(ever_treated) %>%
  group_by(state_abb, treat_start, months_since_treat) %>%
  summarise(
    n_counties = n(),
    mean_dy = mean(dy, na.rm = TRUE),
    se_dy = sd(dy, na.rm = TRUE) / sqrt(n()),
    mean_dy_rate = mean(dy_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(months_since_treat)
write_csv(state_exposure, file.path(out_dir, "exposure_gradient.csv"))

print(state_exposure %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# Regression: long-difference ON months since legalization.
m_exp <- feols(dy ~ months_since_treat, data = county_means %>%
                 filter(ever_treated), cluster = ~state_abb)
ct_exp <- fixest::coeftable(m_exp)
exp_slope <- as.numeric(ct_exp["months_since_treat", "Estimate"])
exp_se    <- as.numeric(ct_exp["months_since_treat", "Std. Error"])
cat(sprintf("\nExposure-time slope: %.5f per month, SE = %.5f\n",
            exp_slope, exp_se))
cat(sprintf("  → implied effect per year of exposure: %.2f%% (CI [%.2f%%, %.2f%%])\n",
            (exp(12 * exp_slope) - 1) * 100,
            (exp(12 * (exp_slope - 1.96 * exp_se)) - 1) * 100,
            (exp(12 * (exp_slope + 1.96 * exp_se)) - 1) * 100))

# Exposure-gradient plot.
p_exp <- ggplot(state_exposure,
                aes(x = months_since_treat, y = mean_dy)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = mean_dy - 1.96 * se_dy,
                    ymax = mean_dy + 1.96 * se_dy),
                width = 2, color = "grey30") +
  geom_point(color = "grey20", size = 2.5) +
  geom_text(aes(label = state_abb), nudge_y = 0.03, size = 3,
            family = "serif") +
  geom_smooth(method = "lm", se = TRUE,
              color = "grey20", fill = "grey85", linewidth = 0.5) +
  labs(x = "Months between gambling legalization and end of 2024",
       y = "Mean county-level long-difference (2024 minus 2018-2019)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "exposure_gradient.png"), p_exp,
       width = 7, height = 5, dpi = 300, bg = "transparent")

# ----------------------------- 3. LATE-PANEL CROSS-SECTION --------------------

cat("\n=== 3. LATE-PANEL CROSS-SECTION (2024 only) ===\n")

m_xs1 <- feols(y_mean_late ~ ever_treated, data = county_means,
               cluster = ~state_abb)
m_xs2 <- feols(y_mean_late ~ ever_treated + y_mean_pre,
               data = county_means, cluster = ~state_abb)
m_xs3 <- feols(y_mean_late ~ ever_treated + y_mean_pre + log(pop_pre) + pov_pre,
               data = county_means, cluster = ~state_abb)

xs_results <- bind_rows(
  extract_treat_row(m_xs1, "no controls"),
  extract_treat_row(m_xs2, "+ baseline (pre-period mean)"),
  extract_treat_row(m_xs3, "+ baseline + pop + poverty")
)

write_csv(xs_results, file.path(out_dir, "late_cross_section.csv"))

cat("\n")
print(xs_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- summary ----------------------------------------

cat("\n")
cat("=== SUMMARY ===\n")
cat("\nLong-difference DiD (% effect on log1p(filings)):\n")
ld_results %>%
  filter(grepl("filings", spec)) %>%
  select(spec, pct_effect, ci_low, ci_high) %>%
  mutate(across(where(is.numeric), ~ signif(.x, 3))) %>%
  print()

cat("\nLate-panel cross-section (% effect on log1p(filings) in 2024):\n")
xs_results %>%
  select(spec, pct_effect, ci_low, ci_high) %>%
  mutate(across(where(is.numeric), ~ signif(.x, 3))) %>%
  print()

cat("\nWrote outputs to:", out_dir, "\n")
