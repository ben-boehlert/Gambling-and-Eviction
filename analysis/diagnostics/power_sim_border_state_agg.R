#!/usr/bin/env Rscript
################################################################################
# power_sim_border_state_agg.R  —  Sim B in the 4-way decomposition
#
# Border counties only, but AGGREGATED TO STATE-MONTH before running TWFE.
# State FE + month FE, state clustering. Isolates the PURE SAMPLE-SELECTION
# effect: same border-county universe as Sim C, but collapsed to state-month
# the same way the state baseline (Sim A) does.
#
# Differences from Sim A (state baseline):
#   - Sim A:   state aggregate built from ALL counties' filings_count
#   - Sim B:   state aggregate built from BORDER counties' filings_count only
#
# Differences from Sim C (border county-level):
#   - Sim C:   county FE + county-level y
#   - Sim B:   state FE + state-level y (sum of border-county filings per state)
#
# Same DGP, seeds, effect grid, exclusions as power_sim_border_county.R.
#
# Outputs:
#   output/border_diagnostic/power_border_state_agg_twfe.csv
#   output/border_diagnostic/border_state_agg_panel_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
source(file.path(repo_root, "analysis", "diagnostics", "power_sim_shared.R"))

p_border <- file.path(repo_root, "data", "processed",
                      "county_month_border_panel.csv")
out_dir  <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

# Read border-county panel and aggregate to state-month.
border_raw <- read_csv(p_border, show_col_types = FALSE) %>%
  mutate(
    month_date  = as.Date(month_date),
    treat_start = as.Date(treat_start),
    filings_count = as.numeric(filings_count)
  ) %>%
  filter(!is.na(month_date), state_abb != "ME")

# State-month aggregation: sum filings_count across border counties in each
# state-month. This mirrors how state_month_panel_with_treatment.csv is
# constructed in the existing pipeline, but using only border counties.
state_agg <- border_raw %>%
  group_by(state_abb, month_date) %>%
  summarise(
    filings_count = sum(filings_count, na.rm = TRUE),
    treat_start   = dplyr::first(treat_start),
    n_counties_used = n(),
    .groups = "drop"
  )

panel <- state_agg %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(as.factor(state_abb)),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = as.integer((g > 0L) & (t >= g)),
    y = log1p(pmax(filings_count, 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("\n=== BORDER-AGGREGATED STATE TWFE POWER SIM (Sim B) ===\n")
cat("Panel rows:", nrow(panel), "\n")
cat("States:", n_distinct(panel$state_abb), "\n")
cat("Months:", n_distinct(panel$t), "\n")
cat("Treated states:",
    panel %>% filter(post_treat == 1L) %>% pull(state_abb) %>% n_distinct(),
    "\n")
cat("Avg border counties per state-month:",
    round(mean(state_agg$n_counties_used), 1), "\n\n")

panel_summary <- tibble(
  panel_label = "border_state_agg_twfe",
  n_units = n_distinct(panel$unit_id),
  n_states = n_distinct(panel$state_abb),
  n_months = n_distinct(panel$t),
  n_obs = nrow(panel),
  n_treated_units = panel %>% filter(post_treat == 1L) %>%
    pull(unit_id) %>% n_distinct(),
  n_treated_states = panel %>% filter(post_treat == 1L) %>%
    pull(state_abb) %>% n_distinct(),
  share_post_treat = mean(panel$post_treat == 1L),
  avg_counties_per_state_month = round(mean(state_agg$n_counties_used), 2)
)
write_csv(panel_summary, file.path(out_dir, "border_state_agg_panel_summary.csv"))

EFFECT_PCTS <- c(0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
N_SIMS <- 200L

t0 <- Sys.time()
power_tbl <- run_power_grid(panel, EFFECT_PCTS, n_sims = N_SIMS,
                            seed = 20260521L, alpha = 0.05) %>%
  mutate(panel_label = "border_state_agg_twfe", .before = 1)
t1 <- Sys.time()

cat("\nElapsed:", round(as.numeric(difftime(t1, t0, units = "secs")), 1),
    "seconds\n")

write_csv(power_tbl, file.path(out_dir, "power_border_state_agg_twfe.csv"))
print(power_tbl)
