#!/usr/bin/env Rscript
################################################################################
# long_diff_heterogeneity.R
#
# Tests whether the long-difference DiD treatment effect varies by state/county
# characteristics. Unlike the cross-state ATT correlation analysis (which
# suffers a denominator effect on log-scale ATTs), this uses the same long-
# difference outcome scale throughout — so interaction coefficients reflect
# substantive heterogeneity, not denominator artifacts.
#
# Model: dy_c = α + β * ever_treated_c + γ * X_c + δ * ever_treated_c * X_c
#               + baseline_controls + ε_c
#
# Interaction δ tests whether the long-difference treatment effect differs
# by X. Continuous X is centered at its sample mean so the main effect β
# corresponds to the average value of X.
#
# Characteristics tested:
#   - Pre-treatment poverty rate (county-level)
#   - Pre-treatment filings per 1k renters (county-level)
#   - Pre-treatment log renter population (county-level)
#   - State-level cumulative gambling handle per renter
#   - State partisanship (Trump 2020 vote share)
#   - High-poverty indicator (above-median split)
#   - Urban indicator (above-median renter population)
#
# All specs include baseline controls (pre-period y_mean, log pop, poverty
# rate, partisanship) and cluster at state.
#
# Outputs:
#   output/border_diagnostic/long_diff_heterogeneity/{
#     interaction_results.csv,
#     summary.csv,
#     visualization.png
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_diff_heterogeneity")
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
PRE_START  <- as.Date("2018-01-01")
PRE_END    <- as.Date("2019-12-31")
LATE_START <- as.Date("2024-01-01")
LATE_END   <- as.Date("2024-12-31")

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

# State-level gambling intensity (per-renter cumulative handle).
gambling <- read_csv(file.path(repo_root, "data", "raw",
                                "lsr_sports_betting_handle_revenue_by_state_month.csv"),
                     show_col_types = FALSE) %>%
  mutate(state_abb = state.abb[match(State, state.name)],
         month_date = as.Date(month_date),
         Handle = as.numeric(Handle)) %>%
  filter(!is.na(state_abb), month_date <= LATE_END) %>%
  group_by(state_abb) %>%
  summarise(cum_handle = sum(Handle, na.rm = TRUE), .groups = "drop")

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  left_join(trump_2020, by = "state_abb") %>%
  left_join(gambling, by = "state_abb") %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         ever_treated = !is.na(treat_start))

# County-level long-difference (mean(2018-2019) vs mean(2024)).
county_means <- panel %>%
  mutate(
    period = case_when(
      month_date >= PRE_START & month_date <= PRE_END   ~ "pre",
      month_date >= LATE_START & month_date <= LATE_END ~ "late",
      TRUE                                              ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(fips, state_abb, ever_treated, trump_2020_share, cum_handle, period) %>%
  summarise(
    n_months = n(),
    y_mean = mean(y, na.rm = TRUE),
    pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
    poverty_rate = mean(poverty_rate, na.rm = TRUE),
    filings_per_1k = mean(if_else(renter_occupied_housing_units > 0,
                                    1000 * filings_count /
                                      renter_occupied_housing_units,
                                    NA_real_), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period,
              values_from = c(n_months, y_mean, pop_renter, poverty_rate,
                              filings_per_1k)) %>%
  filter(n_months_pre >= 6L, n_months_late >= 6L) %>%
  mutate(
    dy = y_mean_late - y_mean_pre,
    log_pop_pre = log(pop_renter_pre),
    # Center continuous chars at sample mean so main effect = ATT at mean(X).
    pov_pre_c       = poverty_rate_pre - mean(poverty_rate_pre, na.rm = TRUE),
    filings_pre_c   = filings_per_1k_pre - mean(filings_per_1k_pre,
                                                 na.rm = TRUE),
    log_pop_pre_c   = log_pop_pre - mean(log_pop_pre, na.rm = TRUE),
    trump_share_c   = trump_2020_share - mean(trump_2020_share, na.rm = TRUE),
    # State-level: cumulative handle per renter.
    handle_per_renter = cum_handle / pop_renter_pre,
    handle_per_renter_c =
      handle_per_renter - mean(handle_per_renter, na.rm = TRUE),
    high_poverty = poverty_rate_pre > median(poverty_rate_pre, na.rm = TRUE),
    high_pop = log_pop_pre > median(log_pop_pre, na.rm = TRUE)
  )

cat("Long-difference panel (NH dropped, coverage in both 2018-2019 and 2024):\n")
cat("  Counties:", nrow(county_means), "\n")
cat("  States:", n_distinct(county_means$state_abb), "\n")
cat("  Treated counties:", sum(county_means$ever_treated), "\n")
cat("  Never-treated counties:", sum(!county_means$ever_treated), "\n\n")

# ----------------------------- helper ---------------------------------------

extract_terms <- function(fit, base_main, base_int, spec_label, x_label) {
  ct <- fixest::coeftable(fit)
  rn <- rownames(ct)
  main_row <- intersect(c(base_main, "ever_treated"), rn)[1]
  int_row  <- intersect(c(base_int), rn)[1]

  out <- tibble(spec = spec_label,
                interactor = x_label,
                main_att = NA_real_,
                main_se = NA_real_,
                interaction = NA_real_,
                interaction_se = NA_real_,
                interaction_p = NA_real_,
                n_obs = fit$nobs)
  if (!is.na(main_row)) {
    out$main_att <- as.numeric(ct[main_row, "Estimate"])
    out$main_se  <- as.numeric(ct[main_row, "Std. Error"])
  }
  if (!is.na(int_row)) {
    out$interaction <- as.numeric(ct[int_row, "Estimate"])
    out$interaction_se <- as.numeric(ct[int_row, "Std. Error"])
    out$interaction_p  <- as.numeric(ct[int_row, "Pr(>|t|)"])
  }
  out
}

# ----------------------------- run interactions -------------------------------

cat("=== HETEROGENEITY VIA INTERACTIONS ===\n")
cat("Main effect (ever_treatedTRUE) is the ATT at the SAMPLE MEAN of the\n")
cat("centered interactor. Interaction coef shows shift per 1 unit of X.\n\n")

# All continuous interactors are centered, so the main "ever_treatedTRUE"
# coefficient equals the ATT at the average value of the interactor.

m_pov <- feols(
  dy ~ ever_treated * pov_pre_c + y_mean_pre + log_pop_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
r_pov <- extract_terms(m_pov, "ever_treatedTRUE",
                        "ever_treatedTRUE:pov_pre_c",
                        "ever_treated × poverty rate (county, centered)",
                        "poverty_rate")

m_fil <- feols(
  dy ~ ever_treated * filings_pre_c + y_mean_pre + log_pop_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
r_fil <- extract_terms(m_fil, "ever_treatedTRUE",
                        "ever_treatedTRUE:filings_pre_c",
                        "ever_treated × pre-filings per 1k renters (county, centered)",
                        "pre_filings_per_1k")

m_pop <- feols(
  dy ~ ever_treated * log_pop_pre_c + y_mean_pre + poverty_rate_pre +
         trump_share_c,
  data = county_means, cluster = ~state_abb
)
r_pop <- extract_terms(m_pop, "ever_treatedTRUE",
                        "ever_treatedTRUE:log_pop_pre_c",
                        "ever_treated × log(renter pop) (county, centered)",
                        "log_renter_pop")

m_trump <- feols(
  dy ~ ever_treated * trump_share_c + y_mean_pre + log_pop_pre +
         poverty_rate_pre,
  data = county_means, cluster = ~state_abb
)
r_trump <- extract_terms(m_trump, "ever_treatedTRUE",
                          "ever_treatedTRUE:trump_share_c",
                          "ever_treated × Trump 2020 share (state, centered)",
                          "trump_share")

m_handle <- feols(
  dy ~ ever_treated * handle_per_renter_c + y_mean_pre + log_pop_pre +
         poverty_rate_pre + trump_share_c,
  data = county_means %>% filter(ever_treated | is.finite(handle_per_renter_c)),
  cluster = ~state_abb
)
r_handle <- extract_terms(m_handle, "ever_treatedTRUE",
                           "ever_treatedTRUE:handle_per_renter_c",
                           "ever_treated × handle per renter (state, centered)",
                           "handle_per_renter")

# Binary splits for visualization
m_high_pov <- feols(
  dy ~ ever_treated * high_poverty + y_mean_pre + log_pop_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
r_high_pov <- extract_terms(m_high_pov, "ever_treatedTRUE",
                             "ever_treatedTRUE:high_povertyTRUE",
                             "ever_treated × high-poverty (above-median)",
                             "high_poverty")

m_high_pop <- feols(
  dy ~ ever_treated * high_pop + y_mean_pre + poverty_rate_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
r_high_pop <- extract_terms(m_high_pop, "ever_treatedTRUE",
                             "ever_treatedTRUE:high_popTRUE",
                             "ever_treated × high-pop (above-median renter pop)",
                             "high_pop")

results <- bind_rows(r_pov, r_fil, r_pop, r_trump, r_handle,
                     r_high_pov, r_high_pop) %>%
  mutate(main_pct = (exp(main_att) - 1) * 100,
         interaction_pct = (exp(interaction) - 1) * 100)

write_csv(results, file.path(out_dir, "interaction_results.csv"))
print(results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- subgroup ATTs ---------------------------------

cat("\n=== SUBGROUP ATTs (high-poverty vs low-poverty counties) ===\n")
sub_low <- feols(
  dy ~ ever_treated + y_mean_pre + log_pop_pre + trump_share_c,
  data = county_means %>% filter(!high_poverty), cluster = ~state_abb
)
sub_high <- feols(
  dy ~ ever_treated + y_mean_pre + log_pop_pre + trump_share_c,
  data = county_means %>% filter(high_poverty), cluster = ~state_abb
)

sub_results <- bind_rows(
  extract_terms(sub_low, "ever_treatedTRUE", NA,
                 "Low-poverty counties (below median)", "low_pov_subset"),
  extract_terms(sub_high, "ever_treatedTRUE", NA,
                 "High-poverty counties (above median)", "high_pov_subset")
) %>%
  mutate(main_pct = (exp(main_att) - 1) * 100,
         ci_low_95 = main_att - 1.96 * main_se,
         ci_high_95 = main_att + 1.96 * main_se)

write_csv(sub_results, file.path(out_dir, "subgroup_high_pov.csv"))
print(sub_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

cat("\n=== SUBGROUP ATTs (high-pop vs low-pop counties) ===\n")
sub_low_pop <- feols(
  dy ~ ever_treated + y_mean_pre + poverty_rate_pre + trump_share_c,
  data = county_means %>% filter(!high_pop), cluster = ~state_abb
)
sub_high_pop <- feols(
  dy ~ ever_treated + y_mean_pre + poverty_rate_pre + trump_share_c,
  data = county_means %>% filter(high_pop), cluster = ~state_abb
)

sub_pop_results <- bind_rows(
  extract_terms(sub_low_pop, "ever_treatedTRUE", NA,
                 "Low-population counties (below median renter pop)",
                 "low_pop_subset"),
  extract_terms(sub_high_pop, "ever_treatedTRUE", NA,
                 "High-population counties (above median renter pop)",
                 "high_pop_subset")
) %>%
  mutate(main_pct = (exp(main_att) - 1) * 100,
         ci_low_95 = main_att - 1.96 * main_se,
         ci_high_95 = main_att + 1.96 * main_se)

write_csv(sub_pop_results, file.path(out_dir, "subgroup_high_pop.csv"))
print(sub_pop_results %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- forest plot -----------------------------------

forest_df <- bind_rows(
  results %>% mutate(plot_type = "interaction",
                     estimate = interaction,
                     se = interaction_se,
                     label = sub("ever_treated × ", "", spec)),
  sub_results %>% mutate(plot_type = "subgroup",
                          estimate = main_att,
                          se = main_se,
                          label = spec),
  sub_pop_results %>% mutate(plot_type = "subgroup",
                              estimate = main_att,
                              se = main_se,
                              label = spec)
) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p <- forest_df %>%
  mutate(label = factor(label, levels = rev(label))) %>%
  ggplot(aes(x = label, y = estimate, color = plot_type)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                width = 0.3, linewidth = 0.5) +
  geom_point(size = 2.2) +
  coord_flip() +
  scale_color_grey(start = 0.15, end = 0.55, name = NULL) +
  labs(x = NULL,
       y = "Coefficient (interaction or subgroup ATT), 95% CI") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "visualization.png"), p,
       width = 10, height = 6, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
