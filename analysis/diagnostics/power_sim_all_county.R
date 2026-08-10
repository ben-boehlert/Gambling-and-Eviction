#!/usr/bin/env Rscript
################################################################################
# power_sim_all_county.R  —  Sim D in the 4-way decomposition
#
# Full county-month panel (all ~1,384 ETS counties), county FE + month FE,
# state clustering. Isolates the PURE DISAGGREGATION effect: same outcome
# universe as the state baseline (Sim A), but at the county level.
#
# Same DGP, same seeds, same effect grid, same exclusions as power_sim_border_county.R.
#
# Outputs:
#   output/border_diagnostic/power_all_county_twfe.csv
#   output/border_diagnostic/all_county_panel_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
source(file.path(repo_root, "analysis", "diagnostics", "power_sim_shared.R"))

p_county_raw <- file.path(repo_root, "data", "raw",
                          "monthly_county_data_download.csv")
p_state_tr   <- file.path(repo_root, "data", "raw",
                          "state_month_panel_with_treatment.csv")
out_dir      <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# State-FIPS crosswalk (mirror of power_simulation_cs.R lines 199–252).
state_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb,
   1, "AL",  2, "AK",  4, "AZ",  5, "AR",  6, "CA",  8, "CO",  9, "CT",
  10, "DE", 11, "DC", 12, "FL", 13, "GA", 15, "HI", 16, "ID",
  17, "IL", 18, "IN", 19, "IA", 20, "KS", 21, "KY", 22, "LA",
  23, "ME", 24, "MD", 25, "MA", 26, "MI", 27, "MN", 28, "MS",
  29, "MO", 30, "MT", 31, "NE", 32, "NV", 33, "NH", 34, "NJ",
  35, "NM", 36, "NY", 37, "NC", 38, "ND", 39, "OH", 40, "OK",
  41, "OR", 42, "PA", 44, "RI", 45, "SC", 46, "SD", 47, "TN",
  48, "TX", 49, "UT", 50, "VT", 51, "VA", 53, "WA", 54, "WV",
  55, "WI", 56, "WY"
)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

# Load full ETS county panel.
county_raw <- read_csv(p_county_raw, show_col_types = FALSE) %>%
  mutate(
    fips        = as.integer(fips),
    state_fips  = as.integer(floor(fips / 1000)),
    month_date  = as.Date(date),
    filings_count = as.numeric(filings_count)
  ) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date))

# State treatment timing (one per state).
state_treat_one <- read_csv(p_state_tr, show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = as.integer((g > 0L) & (t >= g)),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("\n=== ALL-COUNTY TWFE POWER SIM (Sim D) ===\n")
cat("Panel rows:", nrow(panel), "\n")
cat("Counties:", n_distinct(panel$unit_id), "\n")
cat("States:", n_distinct(panel$state_abb), "\n")
cat("Months:", n_distinct(panel$t), "\n")
cat("Treated states:",
    panel %>% filter(post_treat == 1L) %>% pull(state_abb) %>% n_distinct(),
    "\n\n")

panel_summary <- tibble(
  panel_label = "all_county_twfe",
  n_units = n_distinct(panel$unit_id),
  n_states = n_distinct(panel$state_abb),
  n_months = n_distinct(panel$t),
  n_obs = nrow(panel),
  n_treated_units = panel %>% filter(post_treat == 1L) %>%
    pull(unit_id) %>% n_distinct(),
  n_treated_states = panel %>% filter(post_treat == 1L) %>%
    pull(state_abb) %>% n_distinct(),
  share_post_treat = mean(panel$post_treat == 1L)
)
write_csv(panel_summary, file.path(out_dir, "all_county_panel_summary.csv"))

EFFECT_PCTS <- c(0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
N_SIMS <- 200L

t0 <- Sys.time()
power_tbl <- run_power_grid(panel, EFFECT_PCTS, n_sims = N_SIMS,
                            seed = 20260521L, alpha = 0.05) %>%
  mutate(panel_label = "all_county_twfe", .before = 1)
t1 <- Sys.time()

cat("\nElapsed:", round(as.numeric(difftime(t1, t0, units = "secs")), 1),
    "seconds\n")

write_csv(power_tbl, file.path(out_dir, "power_all_county_twfe.csv"))
print(power_tbl)
