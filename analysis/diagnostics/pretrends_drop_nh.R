#!/usr/bin/env Rscript
################################################################################
# pretrends_drop_nh.R
#
# Re-runs the all-county SunAb pretrends without NH (an outlier cohort: only 10
# ETS counties, max pre-period coefficient 1.6 log-points, mean abs(pre) 0.28
# — 4× the next-worst cohort). Tests whether the aggregate pre-trend pattern
# cleans up substantially once NH is removed.
#
# Outputs:
#   output/border_diagnostic/pretrends_all_county_drop_nh.{csv,png}
#   output/border_diagnostic/pretrends_all_county_drop_nh_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L
             + as.integer(format(date, "%m")))
}

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

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")
MIN_COUNTIES <- 5L

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date))

state_treat_one <- read_csv(file.path(repo_root, "data", "raw",
                                       "state_month_panel_with_treatment.csv"),
                            show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

counties_per_state <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
drop_states_min <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

# NH-specific drop (outlier with only 10 ETS counties).
DROP_OUTLIER <- c("NH")
drop_states <- unique(c(drop_states_min, DROP_OUTLIER))
cat("Dropping outlier cohort: NH (10 ETS counties, pre-period max 1.6)\n")
cat("All dropped states:", paste(drop_states, collapse = ", "), "\n\n")

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states)) %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         g_sunab = if_else(is.na(g), 10000L, as.integer(g)),
         unit_id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("Panel after drop:\n")
cat("  Obs:", nrow(panel), "\n")
cat("  Counties:", n_distinct(panel$unit_id), "\n")
cat("  States:", n_distinct(panel$state_abb), "\n\n")

# SunAb event study.
sa_fit <- fixest::feols(
  y ~ sunab(cohort = g_sunab, period = t, ref.p = -1) | unit_id + t,
  data = panel, cluster = ~state_abb
)

sa_tab <- as_tibble(fixest::coeftable(sa_fit), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`,
         t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
  mutate(event_time = suppressWarnings(as.integer(sub("^t::", "", term))),
         panel_label = "all_county_drop_nh") %>%
  filter(!is.na(event_time))

write_csv(sa_tab %>% select(panel_label, event_time, estimate, se,
                            t_stat, p_value),
          file.path(out_dir, "pretrends_all_county_drop_nh.csv"))

# Near-treatment summary.
near_pre <- sa_tab %>%
  filter(event_time >= -12, event_time <= -2) %>%
  mutate(sig = abs(estimate) > 1.96 * se)
summary_tbl <- tibble(
  spec = "all_county_drop_nh",
  n_pre_coefs_near = nrow(near_pre),
  n_pre_sig_near = sum(near_pre$sig),
  max_abs_pre_near = max(abs(near_pre$estimate)),
  mean_abs_pre_near = mean(abs(near_pre$estimate)),
  mean_pre = mean(near_pre$estimate)
)
write_csv(summary_tbl, file.path(out_dir, "pretrends_all_county_drop_nh_summary.csv"))

cat("=== DROP-NH RESULTS ===\n")
print(summary_tbl %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

cat("\nNear-treatment pre-period coefficients (drop-NH):\n")
print(near_pre %>% select(event_time, estimate, se, p_value, sig) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# Plot.
plot_df <- sa_tab %>%
  filter(event_time >= -24, event_time <= 24) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p <- ggplot(plot_df, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.7) +
  scale_x_continuous(breaks = seq(-24, 24, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "pretrends_all_county_drop_nh.png"), p,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
