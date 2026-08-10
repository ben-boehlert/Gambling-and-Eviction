#!/usr/bin/env Rscript
################################################################################
# border_panel_descriptives.R
#
# Coverage summary for the border-county panel:
#   - per-treated-state count of adjacent ETS-covered control states
#   - per-state count of border counties
#   - usable-pair counts (treated state ↔ ever-treated other state with
#     different date, or treated state ↔ never-treated state)
#
# Outputs:
#   output/border_diagnostic/coverage_summary.csv
#   output/border_diagnostic/by_treated_state.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")

p_pairs <- file.path(repo_root, "data", "processed", "border_county_pairs.csv")
p_panel <- file.path(repo_root, "data", "processed", "county_month_border_panel.csv")

out_dir <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pairs <- read_csv(p_pairs, show_col_types = FALSE)
panel <- read_csv(p_panel, show_col_types = FALSE)

# ---- per-state border-county counts ------------------------------------------
by_state <- panel %>%
  distinct(state_abb, fips, ever_treated) %>%
  group_by(state_abb, ever_treated) %>%
  summarise(n_border_counties = n(), .groups = "drop") %>%
  pivot_wider(names_from = ever_treated, values_from = n_border_counties,
              names_prefix = "ever_treated_", values_fill = 0L)

# ---- by treated state: adjacent control coverage -----------------------------
treated_state_summary <- pairs %>%
  filter(ever_treated_a, !ever_treated_b) %>%   # treated-side -> control-side
  group_by(state_abb_a) %>%
  summarise(
    n_adj_control_states = n_distinct(state_abb_b),
    adj_control_states   = paste(sort(unique(state_abb_b)), collapse = ","),
    n_border_pairs       = n(),
    n_treated_counties_in_pairs = n_distinct(fips_a),
    .groups = "drop"
  ) %>%
  rename(treated_state = state_abb_a)

# Also: treated states that have NO ever-treated-vs-never-treated neighbor.
all_treated_states <- panel %>%
  filter(ever_treated) %>%
  distinct(state_abb) %>%
  pull(state_abb)

treated_state_summary <- tibble(treated_state = sort(all_treated_states)) %>%
  left_join(treated_state_summary, by = "treated_state") %>%
  mutate(
    n_adj_control_states = tidyr::replace_na(n_adj_control_states, 0L),
    n_border_pairs       = tidyr::replace_na(n_border_pairs, 0L),
    n_treated_counties_in_pairs =
      tidyr::replace_na(n_treated_counties_in_pairs, 0L),
    adj_control_states = ifelse(is.na(adj_control_states), "", adj_control_states)
  )

# ---- overall coverage summary -------------------------------------------------
coverage <- tibble(
  metric = c(
    "border_counties_total",
    "border_counties_in_treated_states",
    "border_counties_in_never_treated_states",
    "states_represented_in_border_panel",
    "treated_states_in_border_panel",
    "never_treated_states_in_border_panel",
    "cross_state_pairs_both_in_ets",
    "pairs_treated_xor_never",
    "pairs_both_treated_different_dates",
    "treated_states_with_at_least_one_never_treated_neighbor"
  ),
  value = c(
    n_distinct(panel$fips),
    panel %>% filter(ever_treated) %>% distinct(fips) %>% nrow(),
    panel %>% filter(!ever_treated) %>% distinct(fips) %>% nrow(),
    n_distinct(panel$state_abb),
    panel %>% filter(ever_treated) %>% distinct(state_abb) %>% nrow(),
    panel %>% filter(!ever_treated) %>% distinct(state_abb) %>% nrow(),
    nrow(pairs),
    sum(pairs$treated_xor),
    sum(pairs$treated_both & !pairs$same_date),
    sum(treated_state_summary$n_adj_control_states > 0)
  )
)

write_csv(coverage, file.path(out_dir, "coverage_summary.csv"))
write_csv(treated_state_summary, file.path(out_dir, "by_treated_state.csv"))
write_csv(by_state, file.path(out_dir, "by_state.csv"))

cat("Coverage summary:\n")
print(coverage)
cat("\nBy treated state:\n")
print(treated_state_summary)
cat("\nWrote to:", out_dir, "\n")
