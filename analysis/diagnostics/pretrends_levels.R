#!/usr/bin/env Rscript
################################################################################
# pretrends_levels.R
#
# Event study on the LEVEL of filings per 1k renters per month.
#
# Why this matters: we've established the recommended main outcome is the
# rate in levels (not log), so the pretrends test needs to match. Pretrends
# on log-scale don't translate one-to-one to pretrends on level scale.
#
# Three specifications:
#   1. TWFE event study with i(rel_time, ref = -1) on filings_per_1k
#   2. did2s event study on filings_per_1k (pre-COVID-treated only)
#   3. Compare both to the log-scale event studies we already have
#
# Outputs:
#   output/border_diagnostic/pretrends_levels/{
#     event_study_levels.csv,
#     event_study_levels.png,
#     summary.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(did2s); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "pretrends_levels")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L +
             as.integer(format(date, "%m")))
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
DROP_STATES <- c("ME", "NH")

# ----------------------------- build panel -----------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count),
         renter_occupied_housing_units =
           as.numeric(renter_occupied_housing_units)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date), !(state_abb %in% DROP_STATES))

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
ok_states <- counties_per_state %>%
  filter(n_counties >= MIN_COUNTIES) %>% pull(state_abb)

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                NA_integer_),
    first_treat = if_else(is.na(g), 0L, as.integer(g)),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    # LEVEL outcome
    y_rate = if_else(renter_occupied_housing_units > 0,
                      1000 * filings_count / renter_occupied_housing_units,
                      NA_real_),
    # Log outcome (for comparison)
    y_log = log1p(pmax(filings_count, 0))
  ) %>%
  filter(is.finite(y_rate), !is.na(unit_id), !is.na(t)) %>%
  mutate(rel_time = if_else(is.na(g), NA_integer_, as.integer(t - g)))

cat("Panel (NH dropped, COVID dropped):\n")
cat("  Obs:", nrow(panel), "\n")
cat("  Counties:", n_distinct(panel$unit_id), "\n")
cat("  States:", n_distinct(panel$state_abb), "\n")
cat("  Mean filings_per_1k:", round(mean(panel$y_rate, na.rm = TRUE), 3), "\n\n")

# Restrict event-time window: -12 to +12 for the plot
PRE_W  <- -12L:-2L
POST_W <- 0L:12L

panel_es <- panel %>%
  mutate(
    rel_time_bin = case_when(
      is.na(rel_time)               ~ NA_integer_,
      rel_time < min(PRE_W)         ~ min(PRE_W) - 1L,
      rel_time > max(POST_W)        ~ max(POST_W) + 1L,
      TRUE                          ~ rel_time
    )
  )

# ----------------------------- TWFE event study on LEVELS ---------------------

cat("=== TWFE event study on filings_per_1k (LEVELS) ===\n")
fit_lvl <- fixest::feols(
  y_rate ~ i(rel_time_bin, ref = -1) | unit_id + t,
  data = panel_es, cluster = ~state_abb
)

ct_lvl <- as_tibble(fixest::coeftable(fit_lvl), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`,
         t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
  mutate(event_time = suppressWarnings(
    as.integer(sub("^rel_time_bin::", "", term))),
    scale = "filings_per_1k_LEVELS",
    estimator = "TWFE_i") %>%
  filter(!is.na(event_time)) %>%
  filter(event_time %in% c(PRE_W, POST_W))

cat("Near-treatment pre-period coefs (level scale):\n")
print(ct_lvl %>%
        filter(event_time >= -12, event_time <= -2) %>%
        select(event_time, estimate, se, p_value) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- TWFE on LOGS (for comparison) -----------------

cat("\n=== TWFE event study on log1p(filings) (for comparison) ===\n")
fit_log <- fixest::feols(
  y_log ~ i(rel_time_bin, ref = -1) | unit_id + t,
  data = panel_es, cluster = ~state_abb
)

ct_log <- as_tibble(fixest::coeftable(fit_log), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`,
         t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
  mutate(event_time = suppressWarnings(
    as.integer(sub("^rel_time_bin::", "", term))),
    scale = "log1p_filings",
    estimator = "TWFE_i") %>%
  filter(!is.na(event_time)) %>%
  filter(event_time %in% c(PRE_W, POST_W))

cat("Near-treatment pre-period coefs (log scale):\n")
print(ct_log %>%
        filter(event_time >= -12, event_time <= -2) %>%
        select(event_time, estimate, se, p_value) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- did2s event study on LEVELS -------------------

PRE_COVID_END <- ym_index(COVID_START)
panel_precovid <- panel %>%
  filter(is.na(g) | g < PRE_COVID_END)

cat("\n=== did2s event study on filings_per_1k (LEVELS, pre-COVID cohorts only) ===\n")
es_d2s <- tryCatch({
  did2s::event_study(
    data = panel_precovid, yname = "y_rate",
    idname = "unit_id", gname = "first_treat", tname = "t",
    estimator = "did2s"
  )
}, error = function(e) { cat("Failed:", conditionMessage(e), "\n"); NULL })

if (!is.null(es_d2s)) {
  ct_d2s <- as_tibble(es_d2s) %>%
    rename_with(~ tolower(.x)) %>%
    rename(event_time = any_of(c("term", "rel_year", "event_time")),
           estimate = any_of(c("estimate", "att")),
           se = any_of(c("std.error", "se"))) %>%
    mutate(event_time = as.numeric(event_time),
           scale = "filings_per_1k_LEVELS",
           estimator = "did2s") %>%
    filter(!is.na(event_time))
  cat(sprintf("did2s estimator ran (%d event-times)\n", nrow(ct_d2s)))
}

# ----------------------------- summary table ---------------------------------

# Near-treatment pretrends summary.
near_pre_lvl <- ct_lvl %>%
  filter(event_time >= -12, event_time <= -2)
near_pre_log <- ct_log %>%
  filter(event_time >= -12, event_time <= -2)

summary_tbl <- bind_rows(
  tibble(scale = "LEVELS (filings per 1k renters)",
         estimator = "TWFE_i",
         n_pre_coefs = nrow(near_pre_lvl),
         n_sig_pre = sum(abs(near_pre_lvl$estimate) >
                          1.96 * near_pre_lvl$se),
         mean_pre = mean(near_pre_lvl$estimate),
         mean_abs_pre = mean(abs(near_pre_lvl$estimate)),
         max_abs_pre = max(abs(near_pre_lvl$estimate))),
  tibble(scale = "LOGS (log1p filings)",
         estimator = "TWFE_i",
         n_pre_coefs = nrow(near_pre_log),
         n_sig_pre = sum(abs(near_pre_log$estimate) >
                          1.96 * near_pre_log$se),
         mean_pre = mean(near_pre_log$estimate),
         mean_abs_pre = mean(abs(near_pre_log$estimate)),
         max_abs_pre = max(abs(near_pre_log$estimate)))
)
write_csv(summary_tbl, file.path(out_dir, "summary.csv"))

cat("\n=== PRE-PERIOD SUMMARY (event_time -12 to -2) ===\n")
print(summary_tbl %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- save event-study coefficients -----------------

all_es <- bind_rows(
  ct_lvl %>% select(scale, estimator, event_time, estimate, se, p_value),
  ct_log %>% select(scale, estimator, event_time, estimate, se, p_value)
)
if (exists("ct_d2s") && !is.null(ct_d2s)) {
  all_es <- bind_rows(
    all_es,
    ct_d2s %>%
      select(any_of(c("scale", "estimator", "event_time", "estimate", "se"))) %>%
      mutate(p_value = NA_real_)
  )
}
write_csv(all_es, file.path(out_dir, "event_study_levels.csv"))

# ----------------------------- plot ------------------------------------------

# Separate plots for level and log scales (different y-axes).
plot_lvl <- ct_lvl %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

plot_log <- ct_log %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p_lvl <- ggplot(plot_lvl, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 1.7) +
  scale_x_continuous(breaks = seq(-12, 12, 3)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on filings per 1,000 renters (LEVELS)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

p_log <- ggplot(plot_log, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 1.7) +
  scale_x_continuous(breaks = seq(-12, 12, 3)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log1p(filings)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

# Save individual plots; user can compare side-by-side.
ggsave(file.path(out_dir, "event_study_levels.png"), p_lvl,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")
ggsave(file.path(out_dir, "event_study_log_comparison.png"), p_log,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
