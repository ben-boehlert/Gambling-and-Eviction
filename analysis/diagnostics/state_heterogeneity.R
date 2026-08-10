#!/usr/bin/env Rscript
################################################################################
# state_heterogeneity.R
#
# Decomposes per-state did2s ATTs by state characteristics to identify what
# correlates with effect size. Tests:
#
#   - Poverty rate (high-poverty states should show larger effects, per
#     Hollenbeck's vulnerable-household finding)
#   - Cumulative gambling handle (dose-response: more gambling → bigger
#     eviction effect)
#   - Pre-treatment eviction filings (high-eviction states may have tighter
#     housing markets → bigger marginal effect)
#   - Renter population share (proxy for housing-market vulnerability)
#   - Trump 2020 vote share (partisanship-correlated housing policy)
#   - Number of months between treatment and 2024 (exposure-time gradient)
#
# Outputs:
#   output/border_diagnostic/state_heterogeneity/{
#     state_characteristics.csv,
#     att_vs_each.png,
#     correlation_table.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(ggplot2); library(patchwork)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "state_heterogeneity")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ----------------------------- read per-state ATTs ----------------------------

per_state <- read_csv(file.path(repo_root, "output", "border_diagnostic",
                                 "did2s_decomp", "by_state_att.csv"),
                      show_col_types = FALSE) %>%
  filter(state_abb != "NH")   # exclude data-quality artifact

cat("Per-state ATTs (NH excluded):\n")
print(per_state %>%
        select(state_abb, treat_start, att, pct_effect, n_treated_counties) %>%
        arrange(desc(pct_effect)))

# ----------------------------- state characteristics --------------------------

# 1. County-level data → state aggregates (pre-treatment characteristics).
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

# Pre-treatment characteristics from the ETS county-month data.
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
  filter(!is.na(state_abb))

state_char <- county_raw %>%
  # Pre-treatment baseline window: 2018-2019 (before any treatment, before COVID).
  filter(month_date >= as.Date("2018-01-01"),
         month_date <= as.Date("2019-12-31")) %>%
  group_by(state_abb) %>%
  summarise(
    pre_mean_poverty_rate = mean(poverty_rate, na.rm = TRUE),
    pre_mean_filings_per_county_month = mean(filings_count, na.rm = TRUE),
    pre_total_renters = mean(renter_occupied_housing_units, na.rm = TRUE),
    pre_filings_per_1k_renters =
      1000 * sum(filings_count, na.rm = TRUE) /
      sum(renter_occupied_housing_units, na.rm = TRUE) /
      n_distinct(month_date),
    .groups = "drop"
  )

# 2. Gambling handle (cumulative + average post-treatment).
gambling <- read_csv(file.path(repo_root, "data", "raw",
                                "lsr_sports_betting_handle_revenue_by_state_month.csv"),
                     show_col_types = FALSE) %>%
  mutate(
    state_abb = state.abb[match(State, state.name)],
    month_date = as.Date(month_date),
    Handle = as.numeric(Handle),
    Revenue = as.numeric(Revenue)
  ) %>%
  filter(!is.na(state_abb))

# Per-state gambling cumulative + monthly mean (through 2024).
state_gambling <- gambling %>%
  filter(month_date <= as.Date("2024-12-31")) %>%
  group_by(state_abb) %>%
  summarise(
    n_months_gambling = n(),
    cumulative_handle = sum(Handle, na.rm = TRUE),
    mean_monthly_handle = mean(Handle, na.rm = TRUE),
    .groups = "drop"
  )

# 3. Months since treatment (through end of 2024).
months_since <- per_state %>%
  mutate(months_since_treat =
           as.integer((as.Date("2024-12-31") - treat_start) / 30)) %>%
  select(state_abb, months_since_treat)

# ----------------------------- assemble -------------------------------------

state_combined <- per_state %>%
  left_join(state_char, by = "state_abb") %>%
  left_join(state_gambling, by = "state_abb") %>%
  left_join(trump_2020, by = "state_abb") %>%
  left_join(months_since, by = "state_abb") %>%
  # Cumulative handle per renter (normalized by state size)
  mutate(handle_per_renter = cumulative_handle / pre_total_renters)

write_csv(state_combined, file.path(out_dir, "state_characteristics.csv"))

cat("\nCombined state-level dataset:\n")
print(state_combined %>%
        select(state_abb, pct_effect,
               pre_mean_poverty_rate,
               pre_filings_per_1k_renters,
               cumulative_handle,
               handle_per_renter,
               trump_2020_share,
               months_since_treat) %>%
        arrange(desc(pct_effect)) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- correlations -----------------------------------

cor_vars <- c("pre_mean_poverty_rate",
              "pre_filings_per_1k_renters",
              "pre_mean_filings_per_county_month",
              "cumulative_handle",
              "mean_monthly_handle",
              "handle_per_renter",
              "trump_2020_share",
              "months_since_treat",
              "pre_total_renters")

cor_table <- bind_rows(lapply(cor_vars, function(v) {
  if (!v %in% names(state_combined)) return(NULL)
  x <- state_combined[[v]]
  y <- state_combined$pct_effect
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 4) return(tibble(variable = v, n = sum(ok), cor = NA,
                                  p_value = NA, slope = NA, slope_se = NA))
  cv <- cor.test(x[ok], y[ok])
  # Also fit a regression for slope (effect per 1-unit increase in characteristic).
  fit <- lm(y[ok] ~ x[ok])
  s <- summary(fit)
  tibble(
    variable = v,
    n = sum(ok),
    cor = cv$estimate,
    p_value = cv$p.value,
    slope = coef(fit)[2],
    slope_se = s$coefficients[2, "Std. Error"]
  )
})) %>% arrange(p_value)

write_csv(cor_table, file.path(out_dir, "correlation_table.csv"))

cat("\n=== CORRELATIONS WITH PER-STATE % EFFECT ===\n")
print(cor_table %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- visualizations ---------------------------------

scatter_plot <- function(x_var, x_lab) {
  d <- state_combined %>%
    filter(is.finite(.data[[x_var]]), is.finite(pct_effect))
  ggplot(d, aes(x = .data[[x_var]], y = pct_effect)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
    geom_smooth(method = "lm", se = TRUE,
                color = "grey40", fill = "grey85", linewidth = 0.5) +
    geom_point(color = "grey20", size = 2) +
    geom_text(aes(label = state_abb), nudge_y = 2.5, size = 3,
              family = "serif") +
    labs(x = x_lab, y = "% effect (did2s per-state)") +
    theme_minimal(base_size = 10, base_family = "serif") +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
          panel.background = element_rect(fill = "transparent", color = NA),
          plot.background = element_rect(fill = "transparent", color = NA))
}

p1 <- scatter_plot("pre_mean_poverty_rate", "Pre-treatment poverty rate (%)")
p2 <- scatter_plot("pre_filings_per_1k_renters",
                    "Pre-treatment filings per 1k renters (state-month)")
p3 <- scatter_plot("handle_per_renter",
                    "Cumulative gambling handle / renter ($)")
p4 <- scatter_plot("trump_2020_share", "Trump 2020 vote share (%)")
p5 <- scatter_plot("months_since_treat",
                    "Months between treatment and 2024")
p6 <- scatter_plot("mean_monthly_handle",
                    "Mean monthly gambling handle ($)")

combined <- (p1 | p2 | p3) / (p4 | p5 | p6)

ggsave(file.path(out_dir, "att_vs_each.png"), combined,
       width = 12, height = 7, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
