#!/usr/bin/env Rscript
################################################################################
# power_sim_state_baseline.R
#
# TWFE power simulation on the STATE-MONTH panel, using SAME seeds, effect grid,
# n_sims, exclusions, and DGP as power_sim_border_county.R — so the two are
# apples-to-apples comparable.
#
# Outputs:
#   output/border_diagnostic/power_state_twfe.csv
#   output/border_diagnostic/state_panel_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
source(file.path(repo_root, "analysis", "diagnostics", "power_sim_shared.R"))

p_state <- file.path(repo_root, "data", "raw",
                     "state_month_panel_with_treatment.csv")
out_dir <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ----------------------------- panel build ------------------------------------

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

state_raw <- read_csv(p_state, show_col_types = FALSE) %>%
  mutate(
    month_date  = as.Date(month_date),
    treat_start = as.Date(treat_start)
  )

# One treat_start per state.
state_treat_one <- state_raw %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(treat_start, na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

panel <- state_raw %>%
  select(-treat_start, -treated) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(as.factor(state_abb)),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = as.integer((g > 0L) & (t >= g)),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("\n=== STATE-PANEL TWFE POWER SIM (baseline) ===\n")
cat("Panel rows:", nrow(panel), "\n")
cat("States:", n_distinct(panel$state_abb), "\n")
cat("Months:", n_distinct(panel$t), "\n")
cat("Treated states (post-treat obs > 0):",
    panel %>% filter(post_treat == 1L) %>% pull(state_abb) %>% n_distinct(), "\n\n")

panel_summary <- tibble(
  panel_label = "state_twfe_baseline",
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
write_csv(panel_summary, file.path(out_dir, "state_panel_summary.csv"))

# ----------------------------- power grid -------------------------------------

EFFECT_PCTS <- c(0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
N_SIMS <- 200L

t0 <- Sys.time()
power_tbl <- run_power_grid(panel, EFFECT_PCTS, n_sims = N_SIMS,
                            seed = 20260521L, alpha = 0.05) %>%
  mutate(panel_label = "state_twfe_baseline", .before = 1)
t1 <- Sys.time()

cat("\nElapsed:", round(as.numeric(difftime(t1, t0, units = "secs")), 1),
    "seconds\n")

write_csv(power_tbl, file.path(out_dir, "power_state_twfe.csv"))
cat("\nWrote:", file.path(out_dir, "power_state_twfe.csv"), "\n\n")
print(power_tbl)
