#!/usr/bin/env Rscript
################################################################################
# pretrends_cohort_decomp.R
#
# Decomposes the all-county SunAb pretrends pattern by cohort and by COVID-era
# splits, to test whether the near-treatment pre-period violations are:
#   (a) uniform across cohorts, or
#   (b) driven by a subset of cohorts (e.g. those treated during/after COVID),
#       or
#   (c) driven by cohorts with unusual pre-period economic conditions.
#
# Analyses:
#   1. Per-cohort SunAb (extract cohort × event_time, no aggregation)
#   2. Aggregate SunAb restricted to pre-COVID-treated cohorts (g < 2020-03)
#   3. Aggregate SunAb restricted to post-COVID-treated cohorts (g > 2022-03)
#   4. Aggregate SunAb on full sample (for comparison)
#
# Outputs:
#   output/border_diagnostic/pretrends_cohort_decomp/{by_cohort,
#                                                     by_era,
#                                                     comparison_plot}.{csv,png}
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(tibble)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "pretrends_cohort_decomp")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

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

COVID_START  <- as.Date("2020-03-01")
COVID_END    <- as.Date("2022-03-31")
MIN_COUNTIES <- 5L

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(
    fips        = as.integer(fips),
    state_fips  = as.integer(floor(fips / 1000)),
    month_date  = as.Date(date),
    filings_count = as.numeric(filings_count)
  ) %>%
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
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states)) %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(
    y = log1p(pmax(filings_count, 0)),
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                NA_integer_),
    g_sunab = if_else(is.na(g), 10000L, as.integer(g)),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb)
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t))

# Map cohort code (g) back to (state_abb, treat_date).
cohort_map <- panel %>%
  filter(!is.na(g)) %>%
  distinct(state_abb, g, treat_start) %>%
  arrange(g)
cat("Cohorts in panel (after MIN_COUNTIES filter and COVID drop):\n")
print(cohort_map)

# ----------------------------- per-cohort event study -------------------------

# For each treated state cohort, run a focused SunAb where that state is the
# only treated unit (others enter as never-treated controls). This is closest
# to running CS-DiD's ATT(g,t) cells but using a fixest-based SE.
extract_pre_coefs <- function(es, label) {
  ct <- as_tibble(fixest::coeftable(es), rownames = "term") %>%
    rename(estimate = Estimate, se = `Std. Error`,
           t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
    mutate(event_time = suppressWarnings(as.integer(sub("^t::", "", term))),
           cohort_label = label) %>%
    filter(!is.na(event_time))
  ct
}

per_cohort_results <- list()
for (i in seq_len(nrow(cohort_map))) {
  s <- cohort_map$state_abb[i]
  d <- cohort_map$treat_start[i]
  label <- sprintf("%s (%s)", s, format(d, "%Y-%m"))
  cat(sprintf("  fitting %s ... ", label))

  # Restrict to this state's cohort + never-treated states.
  sub_panel <- panel %>%
    filter(state_abb == s | is.na(treat_start))

  if (n_distinct(sub_panel$unit_id) < 5) {
    cat("skipped (too few units)\n"); next
  }

  fit <- tryCatch({
    sub <- sub_panel %>%
      mutate(g_sunab_local = if_else(is.na(treat_start), 10000L,
                                      as.integer(g)))
    fixest::feols(
      y ~ sunab(cohort = g_sunab_local, period = t, ref.p = -1)
      | unit_id + t,
      data = sub,
      cluster = ~state_abb,
      warn = FALSE, notes = FALSE
    )
  }, error = function(e) NULL)

  if (is.null(fit)) { cat("failed\n"); next }

  ct <- extract_pre_coefs(fit, label)
  per_cohort_results[[label]] <- ct
  cat(sprintf("ok (%d coefs)\n", nrow(ct)))
}

cohort_df <- bind_rows(per_cohort_results)
write_csv(cohort_df, file.path(out_dir, "by_cohort.csv"))

# Per-cohort pre-period summary (event_time -12 to -2).
cohort_summary <- cohort_df %>%
  filter(event_time >= -12, event_time <= -2) %>%
  group_by(cohort_label) %>%
  summarise(
    n_pre_coefs = n(),
    n_sig = sum(abs(estimate) > 1.96 * se),
    mean_abs_pre = mean(abs(estimate), na.rm = TRUE),
    max_abs_pre  = max(abs(estimate), na.rm = TRUE),
    mean_pre = mean(estimate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_abs_pre))
write_csv(cohort_summary, file.path(out_dir, "cohort_pre_summary.csv"))

cat("\n=== PER-COHORT PRE-PERIOD SUMMARY (-12 to -2) ===\n")
print(cohort_summary %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- COVID-era split --------------------------------

# Pre-COVID-treated cohorts: g (treat date in ym_index) < ym_index(2020-03)
# Post-COVID-treated cohorts: g >= ym_index(2022-04)
covid_start_yidx <- ym_index(COVID_START)
covid_end_yidx   <- ym_index(COVID_END)

pre_covid_states <- cohort_map %>%
  filter(g < covid_start_yidx) %>% pull(state_abb)
post_covid_states <- cohort_map %>%
  filter(g > covid_end_yidx) %>% pull(state_abb)
covid_era_states <- cohort_map %>%
  filter(g >= covid_start_yidx & g <= covid_end_yidx) %>% pull(state_abb)

cat("\nCohort era split:\n")
cat("  Pre-COVID-treated states:", paste(pre_covid_states, collapse = ", "), "\n")
cat("  Treated during COVID drop window:",
    paste(covid_era_states, collapse = ", "), "\n")
cat("  Post-COVID-treated states:",
    paste(post_covid_states, collapse = ", "), "\n")

# Run SunAb restricted to each era group.
run_sa <- function(panel_in, label) {
  cat("  fitting", label, "... ")
  fit <- tryCatch({
    panel_in <- panel_in %>%
      mutate(g_sunab_local = if_else(is.na(treat_start), 10000L,
                                      as.integer(g)))
    fixest::feols(
      y ~ sunab(cohort = g_sunab_local, period = t, ref.p = -1)
      | unit_id + t,
      data = panel_in,
      cluster = ~state_abb,
      warn = FALSE, notes = FALSE
    )
  }, error = function(e) {
    cat("ERROR:", conditionMessage(e), "\n"); return(NULL)
  })
  if (is.null(fit)) return(NULL)
  ct <- extract_pre_coefs(fit, label)
  cat("ok\n")
  ct
}

panel_pre <- panel %>%
  filter(is.na(treat_start) | (state_abb %in% pre_covid_states))
panel_post <- panel %>%
  filter(is.na(treat_start) | (state_abb %in% post_covid_states))
panel_all <- panel

era_pre   <- run_sa(panel_pre,  "pre_covid_cohorts")
era_post  <- run_sa(panel_post, "post_covid_cohorts")
era_all   <- run_sa(panel_all,  "all_cohorts")

era_df <- bind_rows(era_pre, era_post, era_all)
write_csv(era_df, file.path(out_dir, "by_era.csv"))

era_summary <- era_df %>%
  filter(event_time >= -12, event_time <= -2) %>%
  group_by(cohort_label) %>%
  summarise(
    n_pre_coefs = n(),
    n_sig = sum(abs(estimate) > 1.96 * se),
    mean_abs_pre = mean(abs(estimate), na.rm = TRUE),
    max_abs_pre  = max(abs(estimate), na.rm = TRUE),
    mean_pre = mean(estimate, na.rm = TRUE),
    .groups = "drop"
  )
write_csv(era_summary, file.path(out_dir, "era_pre_summary.csv"))

cat("\n=== ERA-SPLIT PRE-PERIOD SUMMARY (-12 to -2) ===\n")
print(era_summary %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- plots ------------------------------------------

# Per-cohort event study (near-treatment window only).
cohort_plot_df <- cohort_df %>%
  filter(event_time >= -18, event_time <= 18) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p_cohort <- ggplot(cohort_plot_df, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.5) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 1.2) +
  facet_wrap(~ cohort_label, ncol = 4, scales = "free_y") +
  scale_x_continuous(breaks = seq(-18, 18, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 9, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    strip.text         = element_text(face = "plain")
  )

ggsave(file.path(out_dir, "by_cohort.png"), p_cohort,
       width = 10, height = 7, dpi = 300, bg = "transparent")

# Era-split overlay plot.
era_plot_df <- era_df %>%
  filter(event_time >= -24, event_time <= 24) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se,
         label_clean = case_when(
           cohort_label == "pre_covid_cohorts"  ~ "Pre-COVID cohorts (NJ/PA/WV 2018, NY/IN/NH/AR 2019)",
           cohort_label == "post_covid_cohorts" ~ "Post-COVID cohorts (ND/VA/WI/NC 2021+)",
           cohort_label == "all_cohorts"        ~ "All cohorts"
         ),
         label_clean = factor(label_clean,
                              levels = c("All cohorts",
                                         "Pre-COVID cohorts (NJ/PA/WV 2018, NY/IN/NH/AR 2019)",
                                         "Post-COVID cohorts (ND/VA/WI/NC 2021+)")))

p_era <- ggplot(era_plot_df, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.5) +
  facet_wrap(~ label_clean, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(-24, 24, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    strip.text         = element_text(face = "plain", size = rel(0.95))
  )

ggsave(file.path(out_dir, "by_era.png"), p_era,
       width = 7.5, height = 7, dpi = 300, bg = "transparent")

cat("\nWrote:", out_dir, "\n")
