################################################################################
# analysis/diagnostics/county_vs_state_dispersion_decomposition.R
#
# WHY does the county LP-DiD arm have a tighter sampling distribution than the
# state arm on the clean-anchor design (SD ratio 0.76, ledger row
# lpdid_shift12_clean_county_ewatt_pmd6), when treatment varies at the state
# level and the county arm has FEWER clusters?
#
# Descriptive, blind-safe decomposition on the REAL UNTREATED panel: no
# treatment schedule, no estimates -- just the cross-STATE dispersion of the
# clean-anchor long difference
#     dy(t,h) = log1p(y_{t+h}) - mean_{s = t-6..t-1} log1p(y_s),  h = 12..24,
# COVID months dropped, ex NV/ID/HI/MS, states present in both feeds, under
# four state-level summaries:
#   A  state panel: log1p(fixed-basket sum), states equal          (state arm)
#   B  mean over counties of county dy, states equal
#   C  mean over counties of county dy, states weighted by LSC county count
#      (what unweighted county ewatt implicitly does)
#   D  log1p(sum over ALL download counties), states equal
# Result 2026-09-16: A 0.158 | B 0.189 (1.20x) | C 0.144 (0.92x) | D 0.258.
# Within-state averaging HURTS (B > A: log1p of small county counts is noisy
# and 13 counties do not average it away); the entire county advantage is the
# implicit county-count reweighting (C < A) -- a data-vendor footprint, not an
# estimand. This motivated lpdid_unit_weights = renters (run_estimators.R).
#
# Output (aggregates only): output/county_vs_state_dispersion/
#   dispersion_by_summary.csv, dispersion_by_state.csv
# Run from the project root:
#   Rscript analysis/diagnostics/county_vs_state_dispersion_decomposition.R
################################################################################
suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
xw <- tibble(state_fips = c(1,2,4,5,6,8,9,10,11,12,13,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,47,48,49,50,51,53,54,55,56),
  state_abb = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"))
cty <- read_csv("data/raw/monthly_county_data_download.csv", show_col_types = FALSE) %>%
  mutate(state_fips = as.integer(fips) %/% 1000L, month_date = floor_date(as.Date(date), "month")) %>%
  left_join(xw, by = "state_fips") %>% filter(!is.na(state_abb), state_abb != "ME") %>%
  transmute(unit_id = as.character(fips), state_abb, month_date, y = as.numeric(filings_count))
st  <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(unit_id = state_abb, state_abb, month_date = as.Date(month_date), y = as.numeric(filings_count), n_counties, basket_share)
excl <- c("NV","ID","HI","MS")
common <- intersect(unique(cty$state_abb), unique(st$state_abb)) %>% setdiff(excl)
cat("common states:", length(common), "\n")
cty <- filter(cty, state_abb %in% common); st <- filter(st, state_abb %in% common)
# county-sum series (ALL counties in download, not the fixed basket)
cty_sum <- cty %>% group_by(state_abb, month_date) %>% summarise(y = sum(y), unit_id = first(state_abb), .groups = "drop")

gap <- seq(as.Date("2020-03-01"), as.Date("2021-07-01"), by = "month")
mi <- function(d) year(d)*12L + month(d)
long_diff <- function(panel, pmd = 6L, hs = 12:24) {
  panel <- panel %>% mutate(m = mi(month_date), ly = log1p(y)) %>%
    filter(month_date >= as.Date("2016-01-01"), month_date <= as.Date("2024-12-01"), !month_date %in% gap)
  Y <- panel %>% select(unit_id, state_abb, m, ly)
  # baseline at anchor t: mean of ly over m in t-6..t-1, all 6 present and none in the gap (gap rows are absent -> NA)
  units <- distinct(Y, unit_id, state_abb)
  grid <- expand_grid(units, t = (min(Y$m)+pmd):(max(Y$m)-min(hs)))
  base <- map_dfr(1:pmd, ~ Y %>% mutate(t = m + .x) %>% select(unit_id, t, ly)) %>%
    group_by(unit_id, t) %>% summarise(n = n(), b = mean(ly), .groups = "drop") %>% filter(n == pmd)
  out <- map_dfr(hs, function(h) {
    Y %>% mutate(t = m - h) %>% select(unit_id, t, ly_far = ly) %>%
      inner_join(base, by = c("unit_id","t")) %>% mutate(h = h, dy = ly_far - b)
  }) %>% inner_join(units, by = "unit_id")
  out
}
ld_state  <- long_diff(st)      # A: state panel (fixed basket, log of sum)
ld_csum   <- long_diff(cty_sum) # D: log of sum over ALL download counties
ld_cty    <- long_diff(cty)     # county units
# state summaries from county units
sum_cty <- ld_cty %>% group_by(state_abb, t, h) %>%
  summarise(n_c = n(), dy_mean = mean(dy), dy_sd_within = sd(dy), .groups = "drop")
# cross-state dispersion per (t,h), then average
disp <- function(d, val, wcol = NULL) {
  d <- d %>% mutate(.v = {{val}}, .w = if (is.null(wcol)) 1 else .data[[wcol]])
  d %>% group_by(t, h) %>% filter(n() >= 10) %>%
    summarise(sd = sqrt(sum(.w*(.v - weighted.mean(.v, .w))^2)/sum(.w)), n = n(), .groups = "drop") %>%
    summarise(mean_sd = mean(sd), n_cells = n(), mean_states = mean(n))
}
A <- disp(ld_state, dy)
D <- disp(ld_csum, dy)
B <- disp(sum_cty, dy_mean)
C <- disp(sum_cty, dy_mean, "n_c")
res <- bind_rows(A = A, D = D, B = B, C = C, .id = "summary") %>%
  mutate(label = c("A  state panel: log1p(fixed-basket sum), states equal",
                   "D  log1p(sum over ALL download counties), states equal",
                   "B  mean over counties of county dy, states equal",
                   "C  mean over counties of county dy, states weighted by n_counties (ewatt-county)")[match(summary, c("A","D","B","C"))],
         ratio_to_A = mean_sd / A$mean_sd)
print(res %>% select(label, mean_sd, ratio_to_A, n_cells, mean_states), width = 200)
readr::write_csv(res %>% select(summary, label, mean_sd, ratio_to_A, n_cells, mean_states), "output/county_vs_state_dispersion/dispersion_by_summary.csv")
# within-state county noise vs between-state
w <- sum_cty %>% summarise(mean_within_sd = mean(dy_sd_within, na.rm = TRUE), med_n_c = median(n_c))
print(w)
# per-state: how noisy is each state's long-difference under A vs B
ps <- ld_state %>% group_by(state_abb) %>% summarise(sd_A = sd(dy)) %>%
  inner_join(sum_cty %>% group_by(state_abb) %>% summarise(sd_B = sd(dy_mean), n_c = as.integer(median(n_c))), by = "state_abb") %>%
  inner_join(st %>% distinct(state_abb, n_counties, basket_share) %>% group_by(state_abb) %>% slice(1), by = "state_abb") %>%
  arrange(desc(sd_A))
print(ps, n = 40)
readr::write_csv(ps, "output/county_vs_state_dispersion/dispersion_by_state.csv")
