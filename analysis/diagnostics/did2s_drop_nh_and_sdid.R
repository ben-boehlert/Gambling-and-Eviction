#!/usr/bin/env Rscript
################################################################################
# did2s_drop_nh_and_sdid.R
#
# Two follow-ups to the per-state heterogeneity decomposition:
#
#   1. did2s aggregate WITHOUT NH (which has 10-county coverage and a max
#      pre-period coefficient of 1.55 log-points — clearly a data-quality
#      issue). Compare aggregate ATT to the full-sample did2s estimate.
#
#   2. Synthetic Difference-in-Differences (Arkhangelsky, Athey, Hirshberg,
#      Imbens, Wager 2021 AER), which constructs unit weights AND time weights
#      to explicitly match pre-period outcomes between treated and synthetic
#      control. This is the right tool when parallel trends are imperfect.
#
#      We run SDID on:
#      (a) full all-county panel (all 14 treated cohorts)
#      (b) pre-COVID-treated cohorts only (cleanest natural experiment)
#      (c) pre-COVID cohorts excluding NH
#
# Outputs:
#   output/border_diagnostic/did2s_sdid/
#     did2s_drop_nh.csv
#     sdid_results.csv
#     sdid_plot.png
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(tibble)
  library(fixest); library(did2s); library(synthdid); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic", "did2s_sdid")
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

# ----------------------------- build base panel -------------------------------

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
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states)) %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         first_treat = if_else(is.na(g), 0L, g),
         post_treat = as.integer(!is.na(g) & t >= g),
         id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(id), !is.na(t))

# ========================== PART 1: did2s drop-NH =============================

cat("=== PART 1: did2s aggregate dropping NH ===\n")

run_did2s_agg <- function(panel_in, label) {
  cat(sprintf("  %s (n=%d, n_treated_states=%d): ",
              label, nrow(panel_in),
              n_distinct(panel_in$state_abb[!is.na(panel_in$g)])))
  fit <- tryCatch({
    did2s::did2s(
      data = panel_in, yname = "y",
      first_stage = ~ 0 | id + t,
      second_stage = ~ post_treat,
      treatment = "post_treat",
      cluster_var = "state_abb"
    )
  }, error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)
  ct <- fixest::coeftable(fit)
  if (!("post_treat" %in% rownames(ct))) {
    cat("no post_treat row\n"); return(NULL)
  }
  att <- as.numeric(ct["post_treat", "Estimate"])
  se  <- as.numeric(ct["post_treat", "Std. Error"])
  cat(sprintf("ATT=%.4f, SE=%.4f, 95%% CI=[%.4f, %.4f], %% effect=%.1f%%\n",
              att, se, att - 1.96 * se, att + 1.96 * se,
              (exp(att) - 1) * 100))
  tibble(spec = label,
         n_obs = nrow(panel_in),
         n_treated_states = n_distinct(panel_in$state_abb[!is.na(panel_in$g)]),
         att = att, se = se,
         ci_low_95 = att - 1.96 * se,
         ci_high_95 = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100)
}

drop_nh_results <- bind_rows(
  run_did2s_agg(panel, "all_cohorts_with_NH"),
  run_did2s_agg(panel %>% filter(state_abb != "NH"), "all_cohorts_drop_NH"),
  run_did2s_agg(panel %>%
                  filter(is.na(g) |
                         (g < ym_index(COVID_START) & state_abb != "NH")),
                "pre_covid_drop_NH")
)
write_csv(drop_nh_results, file.path(out_dir, "did2s_drop_nh.csv"))

cat("\n")

# ========================== PART 2: Synthetic DiD =============================
# SDID requires a BALANCED panel. We:
#   - Drop counties that aren't observed in every month
#   - Use the "single treatment date per state" structure
# For staggered treatment we estimate SDID per cohort and aggregate.

cat("=== PART 2: Synthetic Difference-in-Differences ===\n")

# Helper: balance panel to counties present in all months.
balance_panel <- function(panel_in) {
  n_months <- n_distinct(panel_in$t)
  county_months <- panel_in %>% count(id, name = "n_obs")
  full_counties <- county_months %>% filter(n_obs == n_months) %>% pull(id)
  panel_in %>% filter(id %in% full_counties)
}

# Helper: run SDID for a SINGLE treatment date. SDID requires a binary
# treatment that turns on at a single time period.
run_sdid_one_cohort <- function(panel_in, treated_state, cohort_g, label) {
  # Restrict to this cohort + never-treated.
  sub <- panel_in %>%
    filter(state_abb == treated_state | is.na(g))
  sub <- balance_panel(sub)
  if (n_distinct(sub$id) < 10) {
    cat("  ", label, ": too few balanced units\n"); return(NULL)
  }

  # Build the (unit, time, y, treated) panel that synthdid wants.
  sub <- sub %>%
    mutate(treated = as.integer(state_abb == treated_state & t >= cohort_g))

  # panel.matrices() needs unit, time, outcome, treatment columns.
  d <- sub %>%
    select(id, t, y, treated) %>%
    arrange(id, t)

  pm <- tryCatch(
    synthdid::panel.matrices(as.data.frame(d),
                              unit = "id", time = "t",
                              outcome = "y", treatment = "treated"),
    error = function(e) { cat("  ", label,
                              ": panel.matrices failed:",
                              conditionMessage(e), "\n"); NULL })
  if (is.null(pm)) return(NULL)

  fit <- tryCatch(
    synthdid::synthdid_estimate(pm$Y, pm$N0, pm$T0),
    error = function(e) { cat("  ", label,
                              ": synthdid_estimate failed:",
                              conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)

  # Jackknife SE (cluster-style, by state — but with only one treated state
  # per cohort we jackknife over control counties).
  se <- tryCatch(sqrt(synthdid::vcov(fit, method = "jackknife")),
                  error = function(e) NA_real_)
  att <- as.numeric(fit)

  tibble(
    cohort_label = label,
    state_abb = treated_state,
    n_treated_units = pm$N0 + nrow(pm$Y) - pm$N0,   # = nrow(Y)
    n_control_units = pm$N0,
    n_pre_periods = pm$T0,
    n_post_periods = ncol(pm$Y) - pm$T0,
    att = att,
    se = se,
    ci_low_95 = att - 1.96 * se,
    ci_high_95 = att + 1.96 * se,
    pct_effect = (exp(att) - 1) * 100
  )
}

treated_states_df <- panel %>%
  filter(!is.na(g)) %>%
  distinct(state_abb, g, treat_start) %>%
  arrange(g)

cat("\nPer-cohort SDID:\n")
sdid_per_cohort <- list()
for (i in seq_len(nrow(treated_states_df))) {
  s <- treated_states_df$state_abb[i]
  d <- treated_states_df$treat_start[i]
  g <- treated_states_df$g[i]
  label <- sprintf("%s (%s)", s, format(d, "%Y-%m"))
  cat(sprintf("  %s ... ", label))
  res <- run_sdid_one_cohort(panel, s, g, label)
  if (!is.null(res)) {
    sdid_per_cohort[[label]] <- res
    cat(sprintf("ATT=%.4f (%.1f%%), SE=%.4f\n",
                res$att, res$pct_effect, res$se))
  }
}

sdid_df <- bind_rows(sdid_per_cohort)
write_csv(sdid_df, file.path(out_dir, "sdid_per_cohort.csv"))

cat("\n=== SDID per-cohort summary ===\n")
print(sdid_df %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# Aggregate SDID across cohorts using inverse-variance weights.
if (nrow(sdid_df) > 0) {
  sdid_agg_all <- sdid_df %>%
    filter(is.finite(se), se > 0) %>%
    mutate(w = 1 / se^2) %>%
    summarise(
      spec = "sdid_inv_var_weighted_all",
      n_cohorts = n(),
      att = sum(att * w) / sum(w),
      se = sqrt(1 / sum(w))
    ) %>%
    mutate(ci_low_95 = att - 1.96 * se,
           ci_high_95 = att + 1.96 * se,
           pct_effect = (exp(att) - 1) * 100)

  sdid_agg_no_nh <- sdid_df %>%
    filter(is.finite(se), se > 0, state_abb != "NH") %>%
    mutate(w = 1 / se^2) %>%
    summarise(
      spec = "sdid_inv_var_weighted_no_NH",
      n_cohorts = n(),
      att = sum(att * w) / sum(w),
      se = sqrt(1 / sum(w))
    ) %>%
    mutate(ci_low_95 = att - 1.96 * se,
           ci_high_95 = att + 1.96 * se,
           pct_effect = (exp(att) - 1) * 100)

  sdid_agg <- bind_rows(sdid_agg_all, sdid_agg_no_nh)
  write_csv(sdid_agg, file.path(out_dir, "sdid_aggregate.csv"))

  cat("\n=== Inverse-variance-weighted SDID aggregate ===\n")
  print(sdid_agg %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))
}

# Per-cohort plot.
if (nrow(sdid_df) > 0) {
  plot_df <- sdid_df %>%
    arrange(att) %>%
    mutate(cohort_label = factor(cohort_label, levels = cohort_label))

  p <- ggplot(plot_df, aes(x = cohort_label, y = att)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
    geom_errorbar(aes(ymin = ci_low_95, ymax = ci_high_95),
                  width = 0.3, color = "grey20", linewidth = 0.5) +
    geom_point(color = "grey20", size = 2.2) +
    coord_flip() +
    labs(x = NULL,
         y = "Synthetic DiD effect on log(filings + 1), 95% CI") +
    theme_minimal(base_size = 11, base_family = "serif") +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
          panel.background = element_rect(fill = "transparent", color = NA),
          plot.background = element_rect(fill = "transparent", color = NA))

  ggsave(file.path(out_dir, "sdid_per_cohort.png"), p,
         width = 7.5, height = 5, dpi = 300, bg = "transparent")
}

cat("\nWrote outputs to:", out_dir, "\n")
