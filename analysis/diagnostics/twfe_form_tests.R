#!/usr/bin/env Rscript
################################################################################
# twfe_form_tests.R
#
# Tests of the TWFE functional-form assumption underlying did2s / BJS imputation
# estimators. The assumption is that untreated potential outcomes are well-
# described by additively separable unit and time fixed effects.
#
# Three tests:
#
#   1. UNIT-SPECIFIC TIME TRENDS: add unit_id × t to the Stage-1 FE model and
#      re-estimate. If the treatment estimate is stable, TWFE is adequate.
#      If it changes meaningfully, unit-specific trends are part of untreated
#      potential outcomes and the basic imputation is biased.
#
#   2. UNIT × MONTH-OF-YEAR FE: control for unit-specific seasonality. If the
#      treatment estimate is stable, there's no important unit-specific
#      seasonal pattern in untreated outcomes.
#
#   3. PLACEBO TEST ON NEVER-TREATED: randomly assign treatment dates to
#      never-treated states; run did2s. If placebo ATTs cluster around 0,
#      the imputation framework is finding signal only where it should.
#
# Specifications: drop NH, drop COVID, pre-COVID-treated cohorts only,
# log1p(filings_count), state clustering, all-county sample.
#
# Outputs:
#   output/border_diagnostic/twfe_form_tests/{
#     trend_robustness.csv,
#     seasonality_robustness.csv,
#     placebo_distribution.{csv,png}
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(fixest)
  library(did2s); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic", "twfe_form_tests")
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

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count)) %>%
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

# Restrict to pre-COVID-treated cohorts (where did2s event study works).
PRE_COVID_END_YIDX <- ym_index(COVID_START)

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         first_treat = if_else(is.na(g), 0L, as.integer(g)),
         post_treat = as.integer(!is.na(g) & t >= g),
         id = as.integer(fips),
         state_abb = as.character(state_abb),
         # Month-of-year for seasonality.
         month_of_year = as.integer(format(month_date, "%m"))) %>%
  filter(is.finite(y), !is.na(id), !is.na(t)) %>%
  # Pre-COVID-treated cohorts only (or never-treated).
  filter(is.na(g) | g < PRE_COVID_END_YIDX)

n_treated <- n_distinct(panel$state_abb[!is.na(panel$g)])
n_never   <- n_distinct(panel$state_abb[is.na(panel$g)])
cat("Panel (pre-COVID-treated cohorts + never-treated, NH dropped):\n")
cat("  Obs:", nrow(panel), "\n")
cat("  Counties:", n_distinct(panel$id), "\n")
cat("  Treated states:", n_treated, "; never-treated:", n_never, "\n\n")

# ----------------------------- baseline did2s ---------------------------------

cat("=== BASELINE did2s ===\n")
fit_baseline <- did2s::did2s(
  data = panel, yname = "y",
  first_stage = ~ 0 | id + t,
  second_stage = ~ post_treat,
  treatment = "post_treat",
  cluster_var = "state_abb"
)
ct_base <- fixest::coeftable(fit_baseline)
att_base <- as.numeric(ct_base["post_treat", "Estimate"])
se_base  <- as.numeric(ct_base["post_treat", "Std. Error"])
cat(sprintf("  ATT = %.4f, SE = %.4f, 95%% CI = [%.4f, %.4f]\n",
            att_base, se_base, att_base - 1.96 * se_base,
            att_base + 1.96 * se_base))

# ----------------------------- Test 1: unit-specific time trends --------------

cat("\n=== TEST 1: Unit-specific linear time trends ===\n")

# Add unit_id:t (linear unit-specific trends) to Stage 1.
# In fixest syntax: `| id + t` becomes `| id + t + id[t]` to add unit trends.
fit_trend <- tryCatch({
  did2s::did2s(
    data = panel, yname = "y",
    first_stage = ~ 0 | id + t + id[t],   # adds unit-specific linear trends
    second_stage = ~ post_treat,
    treatment = "post_treat",
    cluster_var = "state_abb"
  )
}, error = function(e) {
  cat("  Failed with id[t] syntax — trying alternative\n")
  NULL
})

if (is.null(fit_trend)) {
  # Alternative: manually demean by unit-specific linear trend.
  panel_aug <- panel %>%
    group_by(id) %>%
    mutate(t_centered = t - mean(t, na.rm = TRUE)) %>%
    ungroup() %>%
    mutate(id_t = id * t_centered)
  fit_trend <- did2s::did2s(
    data = panel_aug, yname = "y",
    first_stage = ~ id_t | id + t,   # treat unit-trend as a regressor
    second_stage = ~ post_treat,
    treatment = "post_treat",
    cluster_var = "state_abb"
  )
}

ct_trend <- fixest::coeftable(fit_trend)
att_trend <- as.numeric(ct_trend["post_treat", "Estimate"])
se_trend  <- as.numeric(ct_trend["post_treat", "Std. Error"])
cat(sprintf("  With unit trends: ATT = %.4f, SE = %.4f, 95%% CI = [%.4f, %.4f]\n",
            att_trend, se_trend, att_trend - 1.96 * se_trend,
            att_trend + 1.96 * se_trend))
cat(sprintf("  Change from baseline: ATT %.4f → %.4f (%.1f%% shift)\n",
            att_base, att_trend, 100 * (att_trend - att_base) / abs(att_base)))

# ----------------------------- Test 2: unit × month-of-year FE ---------------

cat("\n=== TEST 2: Unit × month-of-year FE (seasonality) ===\n")

panel_seas <- panel %>%
  mutate(id_moy = paste(id, month_of_year, sep = "_"))

fit_seas <- did2s::did2s(
  data = panel_seas, yname = "y",
  first_stage = ~ 0 | id + t + id_moy,    # add unit × month-of-year interaction
  second_stage = ~ post_treat,
  treatment = "post_treat",
  cluster_var = "state_abb"
)
ct_seas <- fixest::coeftable(fit_seas)
att_seas <- as.numeric(ct_seas["post_treat", "Estimate"])
se_seas  <- as.numeric(ct_seas["post_treat", "Std. Error"])
cat(sprintf("  With unit × month-of-year: ATT = %.4f, SE = %.4f, 95%% CI = [%.4f, %.4f]\n",
            att_seas, se_seas, att_seas - 1.96 * se_seas,
            att_seas + 1.96 * se_seas))
cat(sprintf("  Change from baseline: ATT %.4f → %.4f (%.1f%% shift)\n",
            att_base, att_seas, 100 * (att_seas - att_base) / abs(att_base)))

# ----------------------------- summary table ----------------------------------

robust_results <- bind_rows(
  tibble(spec = "Baseline (id + t FE)", att = att_base, se = se_base),
  tibble(spec = "+ unit-specific linear trends", att = att_trend, se = se_trend),
  tibble(spec = "+ unit × month-of-year FE", att = att_seas, se = se_seas)
) %>%
  mutate(ci_low = att - 1.96 * se,
         ci_high = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100,
         shift_from_baseline_pct = 100 * (att - att_base) / abs(att_base))

write_csv(robust_results, file.path(out_dir, "trend_robustness.csv"))
cat("\n--- Robustness summary ---\n")
print(robust_results %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- Test 3: placebo on never-treated ---------------

cat("\n=== TEST 3: Placebo treatment on never-treated states ===\n")

# Get never-treated states and the treatment-date distribution.
nev_states <- panel %>%
  filter(is.na(g)) %>% distinct(state_abb) %>% pull(state_abb)
real_treat_dates <- panel %>%
  filter(!is.na(g)) %>% distinct(state_abb, g) %>% pull(g)

cat(sprintf("  Never-treated states available: %d\n", length(nev_states)))
cat(sprintf("  Real treatment date range: %d to %d\n",
            min(real_treat_dates), max(real_treat_dates)))

N_PLACEBO <- 100L

placebo_results <- vector("list", N_PLACEBO)
for (b in seq_len(N_PLACEBO)) {
  set.seed(20260521L + b)
  # For each placebo, randomly designate some never-treated states as "treated"
  # at a random date drawn from the real distribution.
  n_pretend_treated <- length(real_treat_dates)
  if (n_pretend_treated > length(nev_states)) {
    n_pretend_treated <- length(nev_states)
  }
  pretend_treated <- sample(nev_states, size = n_pretend_treated)
  pretend_dates   <- sample(real_treat_dates, size = n_pretend_treated)
  assignment <- tibble(state_abb = pretend_treated,
                       placebo_g = pretend_dates)

  placebo_panel <- panel %>%
    left_join(assignment, by = "state_abb") %>%
    mutate(
      placebo_treat = as.integer(!is.na(placebo_g) & t >= placebo_g),
      placebo_first_treat = if_else(is.na(placebo_g), 0L,
                                     as.integer(placebo_g))
    ) %>%
    # Exclude the actually-treated states from the placebo run.
    filter(is.na(g))

  fit_pl <- tryCatch({
    did2s::did2s(
      data = placebo_panel, yname = "y",
      first_stage = ~ 0 | id + t,
      second_stage = ~ placebo_treat,
      treatment = "placebo_treat",
      cluster_var = "state_abb"
    )
  }, error = function(e) NULL)
  if (is.null(fit_pl)) {
    placebo_results[[b]] <- tibble(b = b, ok = FALSE)
    next
  }
  ct_pl <- fixest::coeftable(fit_pl)
  placebo_results[[b]] <- tibble(
    b = b, ok = TRUE,
    att = as.numeric(ct_pl["placebo_treat", "Estimate"]),
    se  = as.numeric(ct_pl["placebo_treat", "Std. Error"]),
    p   = as.numeric(ct_pl["placebo_treat", "Pr(>|t|)"])
  )
}
placebo_df <- bind_rows(placebo_results)
write_csv(placebo_df, file.path(out_dir, "placebo_distribution.csv"))

n_valid <- sum(placebo_df$ok)
if (n_valid > 0) {
  pl_v <- placebo_df %>% filter(ok)
  cat(sprintf("  Placebo runs: %d / %d valid\n", n_valid, N_PLACEBO))
  cat(sprintf("  Mean placebo ATT: %.4f (target: 0)\n",
              mean(pl_v$att, na.rm = TRUE)))
  cat(sprintf("  Median placebo ATT: %.4f\n",
              median(pl_v$att, na.rm = TRUE)))
  cat(sprintf("  SD of placebo ATT: %.4f\n",
              sd(pl_v$att, na.rm = TRUE)))
  cat(sprintf("  Real ATT: %.4f\n", att_base))
  cat(sprintf("  Placebo > real ATT: %d of %d (%.1f%%)\n",
              sum(pl_v$att >= att_base, na.rm = TRUE), n_valid,
              100 * mean(pl_v$att >= att_base, na.rm = TRUE)))
  cat(sprintf("  Rejection rate (p < 0.05) under placebo: %.1f%%\n",
              100 * mean(pl_v$p < 0.05, na.rm = TRUE)))
}

# Plot placebo distribution.
if (n_valid > 0) {
  p_plot <- placebo_df %>% filter(ok) %>%
    ggplot(aes(x = att)) +
    geom_histogram(bins = 30, fill = "grey80", color = "grey30",
                   linewidth = 0.3) +
    geom_vline(xintercept = 0, linetype = "dotted", color = "grey50") +
    geom_vline(xintercept = att_base, linetype = "dashed",
               color = "grey20", linewidth = 0.6) +
    annotate("text", x = att_base, y = Inf, vjust = 1.5, hjust = -0.1,
             label = sprintf("Real ATT = %.3f", att_base),
             family = "serif", size = 3.2) +
    labs(x = "Placebo ATT (random treatment assignment on never-treated states)",
         y = "Count") +
    theme_minimal(base_size = 10, base_family = "serif") +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
          panel.background = element_rect(fill = "transparent", color = NA),
          plot.background = element_rect(fill = "transparent", color = NA))

  ggsave(file.path(out_dir, "placebo_distribution.png"), p_plot,
         width = 6.5, height = 4.0, dpi = 300, bg = "transparent")
}

cat("\nWrote outputs to:", out_dir, "\n")
