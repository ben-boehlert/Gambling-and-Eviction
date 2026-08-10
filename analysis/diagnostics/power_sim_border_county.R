#!/usr/bin/env Rscript
################################################################################
# power_sim_border_county.R
#
# TWFE power simulation on the BORDER-COUNTY subsample.
#
# Design (mirrors analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R):
#   - Outcome: log1p(filings_count) at the county level
#   - FE: county (unit_id = fips) + month (t)
#   - Cluster: state (treatment assignment unit)
#   - DGP: FE fit on untreated obs only; residuals resampled within month;
#          constant post-treatment effect on log scale
#   - COVID drop: 2020-03-01 to 2022-03-31 (same as state-panel default)
#   - Exclude ME (data quality)
#   - Effect grid: 0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20
#   - n_sims = 200
#
# Outputs:
#   output/border_diagnostic/power_border_twfe.csv
#   output/border_diagnostic/border_panel_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
source(file.path(repo_root, "analysis", "diagnostics", "power_sim_shared.R"))

p_border <- file.path(repo_root, "data", "processed", "county_month_border_panel.csv")
out_dir  <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ----------------------------- panel build ------------------------------------

border_raw <- read_csv(p_border, show_col_types = FALSE) %>%
  mutate(
    month_date  = as.Date(month_date),
    treat_start = as.Date(treat_start)
  ) %>%
  filter(!is.na(month_date))

# Apply standard exclusions: drop ME, drop COVID window.
COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

panel <- border_raw %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t  = ym_index(month_date),
    g  = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = as.integer((g > 0L) & (t >= g)),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("\n=== BORDER-COUNTY TWFE POWER SIM ===\n")
cat("Panel rows:", nrow(panel), "\n")
cat("Border counties:", n_distinct(panel$unit_id), "\n")
cat("States:", n_distinct(panel$state_abb), "\n")
cat("Months:", n_distinct(panel$t), "\n")
cat("Treated counties (post-treat obs > 0):",
    panel %>% filter(post_treat == 1L) %>% pull(unit_id) %>% n_distinct(), "\n")
cat("Treated states:",
    panel %>% filter(post_treat == 1L) %>% pull(state_abb) %>% n_distinct(), "\n\n")

# Panel summary for downstream comparison.
panel_summary <- tibble(
  panel_label = "border_county_twfe",
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
write_csv(panel_summary, file.path(out_dir, "border_panel_summary.csv"))

# ----------------------------- power grid -------------------------------------

EFFECT_PCTS <- c(0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
N_SIMS <- 200L

t0 <- Sys.time()
power_tbl <- run_power_grid(panel, EFFECT_PCTS, n_sims = N_SIMS,
                            seed = 20260521L, alpha = 0.05) %>%
  mutate(panel_label = "border_county_twfe", .before = 1)
t1 <- Sys.time()

cat("\nElapsed:", round(as.numeric(difftime(t1, t0, units = "secs")), 1),
    "seconds\n")

write_csv(power_tbl, file.path(out_dir, "power_border_twfe.csv"))
cat("\nWrote:", file.path(out_dir, "power_border_twfe.csv"), "\n\n")
print(power_tbl)
