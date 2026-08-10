#!/usr/bin/env Rscript
# Estimate months to reach each quintile of peak gambling Handle by state
# Excludes COVID period (2020-03 to 2021-06) when defining peaks
# Usage: Rscript analysis/exploratory/quintile_timing_analysis.R

library(tidyverse)

df <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
               show_col_types = FALSE) %>%
  filter(!is.na(Handle), Handle > 0) %>%
  arrange(State, month_date)

cat(sprintf("Loaded %d rows for %d states\n", nrow(df), n_distinct(df$State)))

# Define COVID period
covid_start <- as.Date("2020-03-01")
covid_end   <- as.Date("2021-06-01")

df <- df %>%
  mutate(is_covid = month_date >= covid_start & month_date <= covid_end)

# ── 1. Show peak dates and flag any COVID peaks ────────────────────────────
peak_info_all <- df %>%
  group_by(State) %>%
  slice_max(Handle, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(State, peak_date_all = month_date, peak_handle_all = Handle) %>%
  mutate(peak_in_covid = peak_date_all >= covid_start & peak_date_all <= covid_end)

cat("\n=== Peak Dates (all data) ===\n")
cat(sprintf("  States with peak during COVID (2020-03 to 2021-06): %d\n",
            sum(peak_info_all$peak_in_covid)))
if (any(peak_info_all$peak_in_covid)) {
  cat("  These states:\n")
  peak_info_all %>% filter(peak_in_covid) %>%
    mutate(label = sprintf("    %s: peak %s ($%.0fM)",
                           State, peak_date_all, peak_handle_all / 1e6)) %>%
    pull(label) %>% cat(sep = "\n")
  cat("\n")
}

cat("\n  Peak date distribution (all data):\n")
peak_info_all %>%
  mutate(year = year(peak_date_all)) %>%
  count(year) %>%
  mutate(label = sprintf("    %d: %d states", year, n)) %>%
  pull(label) %>% cat(sep = "\n")
cat("\n")

# ── 2. Compute peaks excluding COVID months ────────────────────────────────
df_nocovid <- df %>% filter(!is_covid)

state_info <- df_nocovid %>%
  group_by(State) %>%
  summarise(
    peak_handle = max(Handle),
    peak_date   = month_date[which.max(Handle)],
    .groups = "drop"
  )

# First data point uses ALL data (including COVID) for the starting month
first_dates <- df %>%
  group_by(State) %>%
  summarise(first_date = min(month_date), n_months = n(), .groups = "drop")

state_info <- state_info %>%
  inner_join(first_dates, by = "State")

cat("=== Peak Dates (excl. COVID) ===\n")
state_info %>%
  mutate(year = year(peak_date)) %>%
  count(year) %>%
  mutate(label = sprintf("    %d: %d states", year, n)) %>%
  pull(label) %>% cat(sep = "\n")
cat("\n")

# Show per-state peak comparison
cat("=== Per-State Peak Comparison ===\n\n")
comparison <- peak_info_all %>%
  inner_join(state_info %>% select(State, peak_handle_nocovid = peak_handle,
                                     peak_date_nocovid = peak_date),
             by = "State") %>%
  mutate(
    pct_change = round((peak_handle_nocovid / peak_handle_all - 1) * 100, 1),
    same_peak  = peak_date_all == peak_date_nocovid
  ) %>%
  arrange(desc(peak_handle_all))

print(comparison %>%
        select(State, peak_date_all, peak_date_nocovid, same_peak, pct_change),
      n = Inf, width = Inf)

cat(sprintf("\n  States where peak changes after excluding COVID: %d / %d\n",
            sum(!comparison$same_peak), nrow(comparison)))

# ── 3. Quintile timing using COVID-excluded peaks ──────────────────────────
# But we search ALL months (including COVID) for first time reaching threshold
quintiles <- c(0.2, 0.4, 0.6, 0.8, 1.0)

results <- map_dfr(quintiles, function(q) {
  df %>%
    inner_join(state_info, by = "State") %>%
    filter(Handle >= q * peak_handle) %>%
    group_by(State) %>%
    summarise(
      first_reach_date = min(month_date),
      first_date       = first(first_date),
      peak_handle      = first(peak_handle),
      .groups = "drop"
    ) %>%
    mutate(
      quintile = paste0(q * 100, "%"),
      months_to_reach = as.numeric(difftime(first_reach_date, first_date, units = "days")) / 30.44
    )
})

# Summary table
summary_table <- results %>%
  group_by(quintile) %>%
  summarise(
    n_states      = n(),
    mean_months   = round(mean(months_to_reach), 1),
    median_months = round(median(months_to_reach), 1),
    sd_months     = round(sd(months_to_reach), 1),
    min_months    = round(min(months_to_reach), 1),
    max_months    = round(max(months_to_reach), 1),
    .groups = "drop"
  )

cat("\n=== Months to Reach Each Quintile of Peak Handle (excl. COVID peaks) ===\n\n")
print(summary_table, n = Inf, width = Inf)

cat("\n=== Per-State Detail ===\n\n")
detail <- results %>%
  select(State, quintile, months_to_reach, peak_handle) %>%
  pivot_wider(names_from = quintile, values_from = months_to_reach,
              names_prefix = "q") %>%
  inner_join(state_info %>% select(State, peak_date), by = "State") %>%
  arrange(desc(peak_handle))

print(detail, n = Inf, width = Inf)
