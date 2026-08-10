#!/usr/bin/env Rscript
################################################################################
# long_diff_event_study.R
#
# Traditional event-study chart built from long differences. For each event
# year e in {-3, -2, -1 (ref), 0, +1, +2, +3, +4, +5}, the ATT is:
#   ATT_e = ( mean log1p(filings) at event year e for treated
#             - mean log1p(filings) in baseline year ) minus the same
#           difference for never-treated counties (same calendar year).
#
# - 2019 = reference (pre-treatment for everyone, last clean pre-COVID year).
# - Drops NH and ME (data quality / sample convention).
# - Drops 2020-2021 (COVID); event years that fall in those calendar years
#   are excluded for treated cohorts.
# - Standard errors clustered at state level.
#
# Outputs:
#   output/border_diagnostic/long_difference/long_diff_event_study.csv
#   output/border_diagnostic/long_difference/long_diff_event_study.png
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2); library(lubridate)
})

set.seed(20260522L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_difference")

# --- Load county panel (reuse long_difference_creative.R conventions) --------
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

DROP_STATES   <- c("ME", "NH")
BASELINE_YEAR <- 2019L
COVID_YEARS   <- integer(0)   # keep COVID years; year FE absorbs aggregate shock
EVENT_RANGE   <- -3:5

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         year       = year(month_date),
         filings_count = as.numeric(filings_count)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date),
         !(state_abb %in% DROP_STATES))

state_treat <- read_csv(file.path(repo_root, "data", "raw",
                                   "state_month_panel_with_treatment.csv"),
                        show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)),
         treat_year  = year(treat_start))

# Same coverage convention: states with >=5 ETS counties.
ok_states <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties") %>%
  filter(n_counties >= 5L) %>% pull(state_abb)

# --- County-year panel of log1p(filings) -------------------------------------
cty_year <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  group_by(fips, state_abb, year) %>%
  summarise(
    n_months = n(),
    annual_filings = sum(filings_count, na.rm = TRUE),
    renter_units   = mean(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(n_months >= 6L) %>%      # require half-year coverage
  mutate(y = log1p(pmax(annual_filings, 0))) %>%
  left_join(state_treat, by = "state_abb") %>%
  mutate(
    ever_treated = !is.na(treat_year),
    event_year   = if_else(ever_treated, year - treat_year, NA_integer_)
  )

# Baseline level per county (mean of pre-treatment baseline year).
baseline <- cty_year %>%
  filter(year == BASELINE_YEAR) %>%
  select(fips, y_base = y, renter_units_base = renter_units)

panel <- cty_year %>%
  inner_join(baseline, by = "fips") %>%
  mutate(dy = y - y_base) %>%
  filter(!(year %in% COVID_YEARS))   # COVID_YEARS is empty by default

# Need a balanced set of counties with baseline; further require they have
# observations across event range (or calendar years for never-treated).
# Soft requirement -- the regression handles imbalance with FE/clustering.

# --- Build event-time DiD on long differences --------------------------------
#
# Specification: dy_{c,t} = sum_e beta_e * 1{event_year_c=e}
#                         + year_FE + epsilon_{c,t}
# - Estimated on treated + never-treated counties.
# - Never-treated counties contribute dy in each calendar year and pin down
#   year FEs (the implicit counterfactual).
# - Event year = -1 is the omitted reference; event year buckets outside
#   EVENT_RANGE are also reference (lumped, ignored).
# - SEs clustered at state level.

panel_reg <- panel %>%
  mutate(
    event_bin = case_when(
      !ever_treated                              ~ NA_integer_,
      event_year < min(EVENT_RANGE)              ~ NA_integer_,
      event_year > max(EVENT_RANGE)              ~ NA_integer_,
      TRUE                                       ~ as.integer(event_year)
    )
  ) %>%
  filter(year != BASELINE_YEAR)   # dy is mechanically 0 in baseline year

# Need ever_treated counties to have at least one event bin observation in
# range; never-treated supply the calendar-year counterfactual.
m <- feols(
  dy ~ i(event_bin, ref = -1) | fips + year,
  data    = panel_reg,
  weights = ~ renter_units_base,
  cluster = ~ state_abb
)

ct <- broom::tidy(m, conf.int = TRUE) %>%
  filter(grepl("event_bin", term)) %>%
  mutate(event_year = as.integer(sub(".*::", "", term))) %>%
  select(event_year, estimate, std.error, conf.low, conf.high)

# Add the reference event year as zero with zero SE for plotting.
ref_row <- tibble(event_year = -1L, estimate = 0,
                  std.error = 0, conf.low = 0, conf.high = 0)

es <- bind_rows(ct, ref_row) %>%
  arrange(event_year) %>%
  mutate(
    pct      = (exp(estimate) - 1) * 100,
    pct_low  = (exp(conf.low)  - 1) * 100,
    pct_high = (exp(conf.high) - 1) * 100,
    is_ref   = event_year == -1L
  )

write_csv(es, file.path(out_dir, "long_diff_event_study.csv"))

# --- Plot --------------------------------------------------------------------
y_pad <- 0.08 * diff(range(c(es$pct_low, es$pct_high), na.rm = TRUE))
y_lim <- c(min(es$pct_low) - y_pad, max(es$pct_high) + y_pad)

p <- ggplot(es, aes(x = event_year, y = pct)) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.4) +
  geom_vline(xintercept = -0.5, linetype = "dashed",
             color = "grey60", linewidth = 0.4) +
  geom_errorbar(aes(ymin = pct_low, ymax = pct_high),
                width = 0.18, color = "grey25", linewidth = 0.5) +
  geom_point(aes(color = is_ref), size = 3) +
  scale_color_manual(values = c(`TRUE` = "grey45", `FALSE` = "#b91c1c"),
                     guide = "none") +
  scale_x_continuous(breaks = EVENT_RANGE) +
  scale_y_continuous(limits = y_lim,
                     labels = function(z) paste0(round(z), "%")) +
  labs(x = "Years since gambling legalization",
       y = "Change in eviction filings vs. 2019, relative to never-legalized states") +
  theme_minimal(base_size = 12, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    axis.ticks         = element_line(color = "grey40", linewidth = 0.3),
    axis.line          = element_line(color = "grey40", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    plot.margin        = margin(t = 8, r = 12, b = 5, l = 5, unit = "pt")
  )

ggsave(file.path(out_dir, "long_diff_event_study.png"), p,
       width = 6.5, height = 4.2, dpi = 300, bg = "transparent")

cat("Event study fit:\n")
print(summary(m))
cat("\nWrote: long_diff_event_study.{csv,png}\n")
print(es)
