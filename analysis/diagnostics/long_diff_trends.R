#!/usr/bin/env Rscript
################################################################################
# long_diff_trends.R
#
# Two-line chart of the raw underlying trends behind the long-difference
# spec: mean filings per county per year, separately for ever-treated states
# and never-treated states. Indexed so 2019 = 100 to make the
# parallel-trends story visible at a glance.
#
# Sample matches long_diff_event_study_main.R:
#   - log1p(monthly filings), averaged within county-year (≥6 months)
#   - ≥5 ETS counties per state, NH and ME dropped
#   - Counties present in both 2018 and 2019 (so the index baseline is real)
#
# Outputs:
#   output/border_diagnostic/long_difference/long_diff_trends.csv
#   output/border_diagnostic/long_difference/long_diff_trends.png
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(ggplot2)
  library(lubridate)
})

set.seed(20260522L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_difference")

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

DROP_STATES <- c("ME", "NH")

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
  mutate(treat_start  = if_else(is.finite(treat_start), treat_start,
                                 as.Date(NA)),
         ever_treated = !is.na(treat_start))

ok_states <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties") %>%
  filter(n_counties >= 5L) %>% pull(state_abb)

cty_year <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  mutate(y_m = log1p(pmax(filings_count, 0))) %>%
  group_by(fips, state_abb, year) %>%
  summarise(
    n_months = n(),
    y        = mean(y_m, na.rm = TRUE),
    .groups  = "drop"
  ) %>%
  filter(n_months >= 6L) %>%
  left_join(state_treat %>% select(state_abb, ever_treated),
            by = "state_abb")

# Counties with both 2018 and 2019 (so baseline is meaningful).
ok_counties <- cty_year %>%
  filter(year %in% c(2018L, 2019L)) %>%
  count(fips, name = "n_yrs") %>%
  filter(n_yrs == 2L) %>% pull(fips)

panel <- cty_year %>% filter(fips %in% ok_counties)

# Group-year means of county-level mean log1p(filings).
group_year <- panel %>%
  group_by(ever_treated, year) %>%
  summarise(
    n_counties = n_distinct(fips),
    y_mean     = mean(y, na.rm = TRUE),
    y_se       = sd(y, na.rm = TRUE) / sqrt(n_counties),
    .groups    = "drop"
  )

# Each group's 2019 mean -> normalize so 2019 = 0 in log points.
base_19 <- group_year %>% filter(year == 2019L) %>%
  select(ever_treated, y_base = y_mean)

trends <- group_year %>%
  inner_join(base_19, by = "ever_treated") %>%
  mutate(
    diff_log = y_mean - y_base,
    pct      = (exp(diff_log) - 1) * 100,
    pct_low  = (exp(diff_log - 1.96 * y_se) - 1) * 100,
    pct_high = (exp(diff_log + 1.96 * y_se) - 1) * 100,
    group    = if_else(ever_treated, "Legalized gambling",
                       "Never legalized")
  ) %>%
  filter(year <= 2024L)

write_csv(trends, file.path(out_dir, "long_diff_trends.csv"))

# --- Plot --------------------------------------------------------------------
y_pad <- 0.10 * diff(range(c(trends$pct_low, trends$pct_high), na.rm = TRUE))
y_lim <- c(min(trends$pct_low, na.rm = TRUE) - y_pad,
           max(trends$pct_high, na.rm = TRUE) + y_pad)

p <- ggplot(trends, aes(x = year, y = pct,
                        color = group, fill = group, shape = group)) +
  geom_hline(yintercept = 0, color = "grey55", linewidth = 0.4) +
  geom_ribbon(aes(ymin = pct_low, ymax = pct_high),
              alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 3, stroke = 0.6, color = "grey15") +
  scale_color_manual(values = c(`Legalized gambling` = "#b91c1c",
                                `Never legalized`    = "grey40")) +
  scale_fill_manual(values  = c(`Legalized gambling` = "#b91c1c",
                                `Never legalized`    = "grey40")) +
  scale_shape_manual(values = c(`Legalized gambling` = 21,
                                `Never legalized`    = 22)) +
  scale_x_continuous(breaks = seq(2016, 2024, 1)) +
  scale_y_continuous(limits = y_lim,
                     breaks = scales::pretty_breaks(n = 6),
                     labels = function(z) paste0(round(z), "%")) +
  labs(x = NULL,
       y = "Change in eviction filings vs. 2019") +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    legend.position    = c(0.02, 0.04),
    legend.justification = c(0, 0),
    legend.title       = element_blank(),
    legend.background  = element_rect(fill = "white", color = NA),
    legend.text        = element_text(size = rel(0.95)),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    axis.title.y       = element_text(margin = margin(r = 8)),
    axis.text          = element_text(color = "grey20"),
    axis.ticks         = element_line(color = "grey40", linewidth = 0.3),
    axis.line          = element_line(color = "grey40", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    plot.margin        = margin(t = 8, r = 14, b = 5, l = 5, unit = "pt")
  )

ggsave(file.path(out_dir, "long_diff_trends.png"), p,
       width = 8.5, height = 5.0, dpi = 300, bg = "transparent")

cat("Wrote: long_diff_trends.{csv,png}\n")
print(trends %>% select(year, group, n_counties, y_mean, pct,
                         pct_low, pct_high))
