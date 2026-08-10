#!/usr/bin/env Rscript
################################################################################
# long_diff_variants.R
#
# Two variants of the long-difference DiD headline:
#
#   (a) POST-COVID-ONLY long-difference: 2022 vs 2024 means, both post-COVID.
#       Treats the entire pandemic + recovery as a black box; identifies the
#       effect off how treated counties' filings changed from 2022 to 2024
#       relative to never-treated counties' same change. Captures dose-response
#       at long horizons (treated states have had 3-6 years of gambling by
#       2024; in 2022 they had 1-4 years).
#
#   (b) MAIN LONG-DIFFERENCE WITH PARTISANSHIP CONTROL: 2018-2019 vs 2024,
#       same as the headline spec, but adds state-level Trump 2020 vote share
#       as a covariate. Addresses concern that gambling adoption correlates
#       with state partisanship and that partisanship-correlated factors
#       (housing policy, eviction-court structure, moratorium intensity) may
#       drive the result.
#
# All specs drop NH (data quality) and ME, restrict to states with ≥5 ETS
# counties, cluster at state.
#
# Outputs:
#   output/border_diagnostic/long_diff_variants/{
#     post_covid_long_diff.csv,
#     partisan_controlled.csv,
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
                       "long_diff_variants")
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

# State-level Trump 2020 vote share (% of two-party vote). Public, well-known
# numbers. Source: MIT Election Lab / state secretaries of state, 2020
# presidential general election results, rounded to nearest 0.1%.
trump_2020 <- tibble::tribble(
  ~state_abb, ~trump_2020_share,
  "AL", 62.0,  "AK", 53.1,  "AZ", 49.1,  "AR", 62.4,  "CA", 34.3,
  "CO", 41.9,  "CT", 39.2,  "DE", 39.8,  "DC", 5.4,   "FL", 51.2,
  "GA", 49.2,  "HI", 34.3,  "ID", 63.8,  "IL", 40.5,  "IN", 57.0,
  "IA", 53.1,  "KS", 56.2,  "KY", 62.1,  "LA", 58.5,  "ME", 44.0,
  "MD", 32.2,  "MA", 32.1,  "MI", 47.8,  "MN", 45.3,  "MS", 57.6,
  "MO", 56.8,  "MT", 56.9,  "NE", 58.2,  "NV", 47.7,  "NH", 45.4,
  "NJ", 41.4,  "NM", 43.5,  "NY", 37.7,  "NC", 49.9,  "ND", 65.1,
  "OH", 53.3,  "OK", 65.4,  "OR", 40.4,  "PA", 48.8,  "RI", 38.6,
  "SC", 55.1,  "SD", 61.8,  "TN", 60.7,  "TX", 52.1,  "UT", 58.1,
  "VT", 30.7,  "VA", 44.0,  "WA", 38.8,  "WV", 68.6,  "WI", 48.8,
  "WY", 69.9
)

DROP_STATES <- c("ME", "NH")

# Period definitions for both specs.
PRE_START_MAIN  <- as.Date("2018-01-01")
PRE_END_MAIN    <- as.Date("2019-12-31")
PRE_START_POST  <- as.Date("2022-04-01")    # just after COVID drop ends
PRE_END_POST    <- as.Date("2022-12-31")
LATE_START      <- as.Date("2024-01-01")
LATE_END        <- as.Date("2024-12-31")

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
  mutate(y = log1p(pmax(filings_count, 0)),
         filings_per_1k = if_else(renter_occupied_housing_units > 0,
                                  1000 * filings_count /
                                    renter_occupied_housing_units,
                                  NA_real_),
         y_rate = log1p(pmax(filings_per_1k, 0)),
         ever_treated = !is.na(treat_start))

# County-level means for the relevant windows.
build_county_means <- function(pre_start, pre_end, label_pre,
                                late_start, late_end, label_late) {
  panel %>%
    mutate(
      period = case_when(
        month_date >= pre_start & month_date <= pre_end   ~ "pre",
        month_date >= late_start & month_date <= late_end ~ "late",
        TRUE                                              ~ NA_character_
      )
    ) %>%
    filter(!is.na(period)) %>%
    group_by(fips, state_abb, ever_treated, treat_start, trump_2020_share,
             period) %>%
    summarise(
      n_months = n(),
      y_mean = mean(y, na.rm = TRUE),
      pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
      poverty_rate = mean(poverty_rate, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    pivot_wider(names_from = period,
                values_from = c(n_months, y_mean, pop_renter, poverty_rate)) %>%
    filter(n_months_pre >= 3L, n_months_late >= 6L) %>%
    mutate(dy = y_mean_late - y_mean_pre,
           label = paste(label_pre, "vs", label_late))
}

# ----------------------------- (a) post-COVID long diff -----------------------

cat("=== (a) POST-COVID LONG DIFFERENCE: 2022 vs 2024 ===\n\n")

cm_post <- build_county_means(
  PRE_START_POST, PRE_END_POST, "2022-Q2..Q4",
  LATE_START, LATE_END, "2024")

cat("Counties with coverage in both 2022 and 2024:", nrow(cm_post), "\n")
cat("Treated:", sum(cm_post$ever_treated),
    "; never-treated:", sum(!cm_post$ever_treated), "\n\n")

extract_treat_row <- function(fit, spec_label) {
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  att <- as.numeric(ct[rn, "Estimate"])
  se  <- as.numeric(ct[rn, "Std. Error"])
  tibble(spec = spec_label, att = att, se = se,
         ci_low = att - 1.96 * se, ci_high = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100,
         n_obs = fit$nobs)
}

m_post1 <- feols(dy ~ ever_treated, data = cm_post, cluster = ~state_abb)
m_post2 <- feols(dy ~ ever_treated + log(pop_renter_pre) + poverty_rate_pre,
                 data = cm_post, cluster = ~state_abb)
m_post3 <- feols(dy ~ ever_treated + log(pop_renter_pre) + poverty_rate_pre +
                   y_mean_pre, data = cm_post, cluster = ~state_abb)
m_post4 <- feols(dy ~ ever_treated + log(pop_renter_pre) + poverty_rate_pre +
                   y_mean_pre + trump_2020_share, data = cm_post,
                 cluster = ~state_abb)

post_results <- bind_rows(
  extract_treat_row(m_post1, "(a) post-COVID, no controls"),
  extract_treat_row(m_post2, "(a) post-COVID, + pop + pov"),
  extract_treat_row(m_post3, "(a) post-COVID, + baseline"),
  extract_treat_row(m_post4, "(a) post-COVID, + baseline + partisan")
)
write_csv(post_results, file.path(out_dir, "post_covid_long_diff.csv"))
print(post_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- (b) partisanship control -----------------------

cat("\n=== (b) MAIN LONG DIFF (2018-2019 vs 2024) + PARTISANSHIP CONTROL ===\n\n")

cm_main <- build_county_means(
  PRE_START_MAIN, PRE_END_MAIN, "2018-2019",
  LATE_START, LATE_END, "2024")

cat("Counties with coverage in both 2018-2019 and 2024:", nrow(cm_main), "\n")
cat("Treated:", sum(cm_main$ever_treated),
    "; never-treated:", sum(!cm_main$ever_treated), "\n\n")

m_main1 <- feols(dy ~ ever_treated, data = cm_main, cluster = ~state_abb)
m_main2 <- feols(dy ~ ever_treated + log(pop_renter_pre) + poverty_rate_pre +
                   y_mean_pre, data = cm_main, cluster = ~state_abb)
m_main3 <- feols(dy ~ ever_treated + log(pop_renter_pre) + poverty_rate_pre +
                   y_mean_pre + trump_2020_share, data = cm_main,
                 cluster = ~state_abb)
m_main4 <- feols(dy ~ ever_treated * trump_2020_share + log(pop_renter_pre) +
                   poverty_rate_pre + y_mean_pre, data = cm_main,
                 cluster = ~state_abb)

main_results <- bind_rows(
  extract_treat_row(m_main1, "(b) main, no controls"),
  extract_treat_row(m_main2, "(b) main, + baseline + pop + pov"),
  extract_treat_row(m_main3, "(b) main, + baseline + partisan"),
  extract_treat_row(m_main4, "(b) main, + ever_treated × partisan")
)
write_csv(main_results, file.path(out_dir, "partisan_controlled.csv"))
print(main_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

cat("\n--- Interaction model details: ever_treated × trump_2020_share ---\n")
print(fixest::coeftable(m_main4))

# ----------------------------- combined summary -------------------------------

all_results <- bind_rows(post_results, main_results)
write_csv(all_results, file.path(out_dir, "summary.csv"))

cat("\n=== COMBINED SUMMARY ===\n")
print(all_results %>%
        select(spec, pct_effect, ci_low, ci_high) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- forest plot ------------------------------------

plot_df <- all_results %>%
  mutate(spec = factor(spec, levels = rev(spec)))

p <- ggplot(plot_df, aes(x = spec, y = att)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                width = 0.3, color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 2) +
  coord_flip() +
  labs(x = NULL,
       y = "Effect on log(filings + 1), 95% CI") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "summary_forest.png"), p,
       width = 9, height = 4, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
