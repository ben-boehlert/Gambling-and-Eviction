#!/usr/bin/env Rscript
################################################################################
# long_diff_event_study_main.R
#
# Faithful event-study version of the MAIN long-difference spec
# (long_difference_creative.R headline):
#
#   - Outcome:  mean over months in calendar year y of log1p(monthly filings)
#               (same monthly-log construction as the headline; NOT log of
#                annual totals).
#   - Baseline: each county's own 2018–2019 mean of that outcome.
#   - Sample:   ≥5 ETS counties per state, NH and ME dropped, counties with
#               at least 6 monthly obs in both 2018 and 2019 (so the baseline
#               is well-defined; mirrors the long-diff's coverage gate).
#   - Design:   TWFE event study on the county-year panel, fips + year FE,
#               state-clustered SEs, unweighted (matches headline).
#   - Reference event year: -1.
#
# Outputs:
#   output/border_diagnostic/long_difference/long_diff_event_study_main.csv
#   output/border_diagnostic/long_difference/long_diff_event_study_main.png
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2); library(lubridate); library(broom)
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

DROP_STATES   <- c("ME", "NH")
EVENT_RANGE   <- -3:5

# --- Load monthly county panel ----------------------------------------------
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

ok_states <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties") %>%
  filter(n_counties >= 5L) %>% pull(state_abb)

# --- County-year panel of mean(log1p(monthly filings)) ----------------------
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
  left_join(state_treat, by = "state_abb") %>%
  mutate(
    ever_treated = !is.na(treat_year),
    event_year   = if_else(ever_treated, year - treat_year, NA_integer_)
  )

# Require both 2018 and 2019 to have >=6 months in-county
ok_counties <- cty_year %>%
  filter(year %in% c(2018L, 2019L)) %>%
  group_by(fips) %>% summarise(n_yrs = n(), .groups = "drop") %>%
  filter(n_yrs == 2L) %>% pull(fips)

panel <- cty_year %>% filter(fips %in% ok_counties)

# --- Construct event-bin variable -------------------------------------------
# For never-treated counties, event_bin stays NA -> they identify year FE only.
# For treated counties outside the range, event_bin is NA (lumped reference).
panel_reg <- panel %>%
  mutate(event_bin = case_when(
    !ever_treated                  ~ NA_integer_,
    event_year < min(EVENT_RANGE)  ~ NA_integer_,
    event_year > max(EVENT_RANGE)  ~ NA_integer_,
    TRUE                           ~ as.integer(event_year)
  ))

cat("Sample summary:\n")
cat("  Counties:", n_distinct(panel_reg$fips), "\n")
cat("  Years:   ", paste(sort(unique(panel_reg$year)), collapse = " "), "\n")
cat("  Treated states:    ",
    paste(sort(unique(panel_reg$state_abb[panel_reg$ever_treated])),
          collapse = " "), "\n")
cat("  Never-treated:     ",
    paste(sort(unique(panel_reg$state_abb[!panel_reg$ever_treated])),
          collapse = " "), "\n\n")

m <- feols(
  y ~ i(event_bin, ref = -1) | fips + year,
  data    = panel_reg,
  cluster = ~ state_abb
)

ct <- broom::tidy(m, conf.int = TRUE) %>%
  filter(grepl("event_bin", term)) %>%
  mutate(event_year = as.integer(sub(".*::", "", term))) %>%
  select(event_year, estimate, std.error, conf.low, conf.high)

ref_row <- tibble(event_year = -1L, estimate = 0,
                  std.error = 0, conf.low = 0, conf.high = 0)

es <- bind_rows(ct, ref_row) %>%
  arrange(event_year) %>%
  mutate(
    pct      = (exp(estimate) - 1) * 100,
    pct_low  = (exp(conf.low)  - 1) * 100,
    pct_high = (exp(conf.high) - 1) * 100,
    is_ref   = event_year == -1L,
    sig      = !is_ref & (conf.low > 0 | conf.high < 0)
  )

write_csv(es, file.path(out_dir, "long_diff_event_study_main.csv"))

# --- Plot --------------------------------------------------------------------
y_range <- range(c(es$pct_low, es$pct_high), na.rm = TRUE)
y_pad   <- 0.10 * diff(y_range)
y_lim   <- c(y_range[1] - y_pad, y_range[2] + y_pad)

p <- ggplot(es, aes(x = event_year, y = pct)) +
  # Soft shading: post-treatment region.
  annotate("rect",
           xmin = -0.5, xmax = max(EVENT_RANGE) + 0.5,
           ymin = y_lim[1], ymax = y_lim[2],
           fill = "grey95", alpha = 0.6) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.45) +
  geom_vline(xintercept = -0.5, linetype = "dashed",
             color = "grey50", linewidth = 0.4) +
  geom_errorbar(aes(ymin = pct_low, ymax = pct_high),
                width = 0.18, color = "grey20", linewidth = 0.55) +
  geom_point(aes(fill = sig),
             shape = 21, color = "grey15", size = 3.8, stroke = 0.7) +
  scale_fill_manual(values = c(`TRUE` = "#b91c1c", `FALSE` = "white"),
                    guide = "none") +
  scale_x_continuous(breaks = EVENT_RANGE) +
  scale_y_continuous(limits = y_lim,
                     breaks = scales::pretty_breaks(n = 6),
                     labels = function(z) paste0(round(z), "%")) +
  labs(
    x = "Years since gambling legalization",
    y = "Change in eviction filings vs. never-legalized states"
  ) +
  theme_minimal(base_size = 14, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    axis.title.x       = element_text(margin = margin(t = 8)),
    axis.title.y       = element_text(margin = margin(r = 8)),
    axis.text          = element_text(color = "grey20"),
    axis.ticks         = element_line(color = "grey40", linewidth = 0.3),
    axis.line          = element_line(color = "grey40", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    plot.margin        = margin(t = 8, r = 12, b = 5, l = 5, unit = "pt")
  )

ggsave(file.path(out_dir, "long_diff_event_study_main.png"), p,
       width = 8.5, height = 5.0, dpi = 300, bg = "transparent")

cat("Event study (main long-diff spec) fit:\n")
print(summary(m))
cat("\nWrote: long_diff_event_study_main.{csv,png}\n")
print(es)
