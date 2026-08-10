#!/usr/bin/env Rscript
################################################################################
# moratorium_filter_covid.R
#
# CREATIVE IDEA: use the CDC eviction moratorium (Sept 4, 2020 – Aug 26, 2021)
# as a "filter" that turns off the gambling-treatment indicator during periods
# when evictions were administratively suppressed.
#
# Rationale: a treatment-effect estimator with state-level treatment and
# county-month outcome implicitly assumes filings could respond to treatment
# in each month. During the moratorium, filings were legally suppressed: a
# state could legalize gambling, but courts couldn't process evictions. So the
# moratorium months should NOT count as part of the "treatment is active"
# window.
#
# This is the opposite of dropping COVID: instead of throwing away 24 months
# of data because something complicated happened, we MODEL what happened.
#
# The active-treatment indicator becomes:
#   active_treat = post_treat × (1 - moratorium)
#
# Where moratorium = 1 if the federal CDC moratorium applied at (state, time).
# Federal dates: 2020-09-04 to 2021-08-26.
#
# This lets us:
#   1. Keep the COVID months in the panel (instead of dropping them)
#   2. Recover identification for COVID-era cohorts (MT, CO, TN), whose
#      treatment dates fall inside the standard COVID drop
#   3. Treat the moratorium period as a known zero-effect window (not just
#      missing data)
#
# Two robustness specs:
#   (a) Use only the federal CDC moratorium window (conservative — many states
#       extended their own moratoriums beyond Aug 2021)
#   (b) Use a wider "any active moratorium" window: Mar 2020 to Mar 2022,
#       which approximates the full federal+state moratorium overlap.
#
# Outputs:
#   output/border_diagnostic/moratorium_filter/{
#     specs_comparison.csv,
#     active_treat_eventstudy.csv,
#     summary.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble)
  library(fixest); library(did2s); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "moratorium_filter")
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

# Federal CDC moratorium dates.
CDC_MORATORIUM_START <- as.Date("2020-09-01")
CDC_MORATORIUM_END   <- as.Date("2021-08-31")

# Wider "any active moratorium" window (approximate federal+state coverage).
WIDE_MORATORIUM_START <- as.Date("2020-03-01")
WIDE_MORATORIUM_END   <- as.Date("2022-03-31")

MIN_COUNTIES <- 5L

# ----------------------------- build panel ------------------------------------

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

# CRITICALLY: keep COVID months. The moratorium filter handles them.
panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states),
         state_abb != "NH") %>%   # drop NH for data-quality reasons
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         first_treat = if_else(is.na(g), 0L, as.integer(g)),
         post_treat = as.integer(!is.na(g) & t >= g),
         cdc_moratorium = as.integer(month_date >= CDC_MORATORIUM_START &
                                     month_date <= CDC_MORATORIUM_END),
         wide_moratorium = as.integer(month_date >= WIDE_MORATORIUM_START &
                                      month_date <= WIDE_MORATORIUM_END),
         # The creative active-treatment indicators.
         active_treat_cdc = post_treat * (1L - cdc_moratorium),
         active_treat_wide = post_treat * (1L - wide_moratorium),
         unit_id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t))

n_treated_states <- n_distinct(panel$state_abb[!is.na(panel$g)])
n_never_treated <- n_distinct(panel$state_abb[is.na(panel$g)])
cat("Panel (NH dropped, COVID months retained):\n")
cat("  Obs:", nrow(panel), "\n")
cat("  Counties:", n_distinct(panel$unit_id), "\n")
cat("  States:", n_distinct(panel$state_abb),
    "(", n_treated_states, "treated +", n_never_treated, "never-treated)\n")
cat("  Months:", n_distinct(panel$t),
    "(includes COVID window)\n\n")

# ----------------------------- treatment-indicator audit ----------------------

ind_audit <- panel %>%
  filter(post_treat == 1L) %>%
  summarise(
    total_post_treat_obs       = sum(post_treat),
    cdc_moratorium_post_treat  = sum(cdc_moratorium * post_treat),
    wide_moratorium_post_treat = sum(wide_moratorium * post_treat),
    active_treat_cdc           = sum(active_treat_cdc),
    active_treat_wide          = sum(active_treat_wide),
    pct_treated_under_cdc      = 100 * sum(cdc_moratorium * post_treat) /
                                  sum(post_treat),
    pct_treated_under_wide     = 100 * sum(wide_moratorium * post_treat) /
                                  sum(post_treat)
  )
cat("Treatment-window audit:\n")
print(ind_audit)
cat("\n")

# ----------------------------- run specs --------------------------------------

run_did2s_spec <- function(panel_in, treatment_col, label) {
  cat(sprintf("  %s ... ", label))
  fmla <- as.formula(paste0("~ ", treatment_col))
  fit <- tryCatch({
    did2s::did2s(
      data = panel_in, yname = "y",
      first_stage = ~ 0 | unit_id + t,
      second_stage = fmla,
      treatment = treatment_col,
      cluster_var = "state_abb"
    )
  }, error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)
  ct <- fixest::coeftable(fit)
  if (!(treatment_col %in% rownames(ct))) {
    cat("no treatment row\n"); return(NULL)
  }
  att <- as.numeric(ct[treatment_col, "Estimate"])
  se  <- as.numeric(ct[treatment_col, "Std. Error"])
  cat(sprintf("ATT=%.4f, SE=%.4f, 95%% CI=[%.4f, %.4f], %% effect=%.1f%%\n",
              att, se, att - 1.96 * se, att + 1.96 * se,
              (exp(att) - 1) * 100))
  tibble(spec = label,
         n_obs = nrow(panel_in),
         n_treated_states = n_distinct(
           panel_in$state_abb[!is.na(panel_in$g)]),
         treatment_col = treatment_col,
         att = att, se = se,
         ci_low_95 = att - 1.96 * se,
         ci_high_95 = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100)
}

run_twfe_spec <- function(panel_in, treatment_col, label) {
  cat(sprintf("  %s ... ", label))
  fmla <- as.formula(paste0("y ~ ", treatment_col, " | unit_id + t"))
  fit <- tryCatch({
    fixest::feols(fmla, data = panel_in, cluster = ~state_abb,
                  warn = FALSE, notes = FALSE)
  }, error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)
  ct <- fixest::coeftable(fit)
  att <- as.numeric(ct[treatment_col, "Estimate"])
  se  <- as.numeric(ct[treatment_col, "Std. Error"])
  cat(sprintf("ATT=%.4f, SE=%.4f, 95%% CI=[%.4f, %.4f], %% effect=%.1f%%\n",
              att, se, att - 1.96 * se, att + 1.96 * se,
              (exp(att) - 1) * 100))
  tibble(spec = label,
         n_obs = nrow(panel_in),
         n_treated_states = n_distinct(
           panel_in$state_abb[!is.na(panel_in$g)]),
         treatment_col = treatment_col,
         att = att, se = se,
         ci_low_95 = att - 1.96 * se,
         ci_high_95 = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100)
}

# Spec battery — held constant: NH dropped throughout, state clustering.
cat("=== TWFE ===\n")
twfe_results <- bind_rows(
  run_twfe_spec(panel %>%
                  filter(!(month_date >= WIDE_MORATORIUM_START &
                           month_date <= WIDE_MORATORIUM_END)),
                "post_treat",
                "TWFE: drop COVID, naive post_treat (baseline)"),
  run_twfe_spec(panel, "post_treat",
                "TWFE: keep COVID, naive post_treat (no adjustment)"),
  run_twfe_spec(panel, "active_treat_cdc",
                "TWFE: keep COVID, CDC moratorium filter"),
  run_twfe_spec(panel, "active_treat_wide",
                "TWFE: keep COVID, wide moratorium filter")
)

cat("\n=== did2s ===\n")
did2s_results <- bind_rows(
  run_did2s_spec(panel %>%
                   filter(!(month_date >= WIDE_MORATORIUM_START &
                            month_date <= WIDE_MORATORIUM_END)),
                 "post_treat",
                 "did2s: drop COVID, naive post_treat (baseline)"),
  run_did2s_spec(panel, "post_treat",
                 "did2s: keep COVID, naive post_treat"),
  run_did2s_spec(panel, "active_treat_cdc",
                 "did2s: keep COVID, CDC moratorium filter"),
  run_did2s_spec(panel, "active_treat_wide",
                 "did2s: keep COVID, wide moratorium filter")
)

results <- bind_rows(twfe_results, did2s_results)
write_csv(results, file.path(out_dir, "specs_comparison.csv"))

cat("\n=== SUMMARY: all specs ===\n")
print(results %>%
        select(spec, n_treated_states, att, se, ci_low_95, ci_high_95,
               pct_effect) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- forest plot ------------------------------------

plot_df <- results %>%
  mutate(spec_short = sub("^[^:]+:\\s*", "", spec),
         estimator = sub(":.*", "", spec),
         spec_short = factor(spec_short,
                             levels = c("drop COVID, naive post_treat (baseline)",
                                        "drop COVID, naive post_treat",
                                        "keep COVID, naive post_treat (no adjustment)",
                                        "keep COVID, naive post_treat",
                                        "keep COVID, CDC moratorium filter",
                                        "keep COVID, wide moratorium filter")))

p <- ggplot(plot_df, aes(x = spec_short, y = att, color = estimator,
                          shape = estimator)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = ci_low_95, ymax = ci_high_95),
                position = position_dodge(width = 0.4),
                width = 0.2, linewidth = 0.5) +
  geom_point(position = position_dodge(width = 0.4), size = 2.5) +
  coord_flip() +
  scale_color_grey(start = 0.15, end = 0.55, name = NULL) +
  scale_shape_manual(values = c(TWFE = 16, did2s = 17), name = NULL) +
  labs(x = NULL,
       y = "Average treatment effect on log(filings + 1), 95% CI") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "specs_comparison.png"), p,
       width = 9, height = 4.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
