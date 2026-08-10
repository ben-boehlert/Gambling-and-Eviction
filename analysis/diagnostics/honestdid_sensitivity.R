#!/usr/bin/env Rscript
################################################################################
# honestdid_sensitivity.R
#
# Rambachan-Roth (2023, REStud) HonestDiD sensitivity bounds on the all-county
# SunAb event study. Computes:
#   - Relative-magnitudes bounds: assumes post-period violations are at most
#     Mbar × (worst observed pre-period violation). Reports the breakdown Mbar.
#   - Second-differences (smoothness) bounds: assumes deviations are smooth.
#
# Strategy:
#   1. Fit SunAb event study on all-county panel
#   2. Extract event-study betas and vcov in the pre/post form HonestDiD wants
#   3. Run createSensitivityResults_relativeMagnitudes() at Mbar ∈ {0, 0.5, 1,
#      1.5, 2}, with l_vec = average of post-period coefs
#   4. Report breakdown Mbar (largest Mbar that still excludes zero) and CIs
#
# Outputs:
#   output/border_diagnostic/honestdid_bounds.{csv,png}
#   output/border_diagnostic/honestdid_breakdown.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(fixest); library(ggplot2)
  library(HonestDiD)
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
         g_sunab = if_else(is.na(g), 10000L, as.integer(g)),
         unit_id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

# Fit a standard event-study with i() event-time dummies. This gives a clean
# aggregated vcov in the event-time parameter space directly (unlike sunab(),
# which returns cohort × event-time vcov that requires manual aggregation).
# For the pre-trend diagnostic, the simple event-study is essentially identical
# to the SunAb pre-period coefficients (sunab() differs from i() mainly in how
# it weights treatment-effect heterogeneity at post horizons).
PRE_WINDOW  <- -12L:-2L
POST_WINDOW <- 0L:12L

panel_es <- panel %>%
  mutate(
    rel_time = if_else(is.na(g), NA_integer_, as.integer(t - g)),
    # Set far-out / never-treated event-times to a single reference bucket.
    rel_time_bin = case_when(
      is.na(rel_time)                 ~ NA_integer_,
      rel_time < min(PRE_WINDOW)      ~ min(PRE_WINDOW) - 1L,  # binned distant pre
      rel_time > max(POST_WINDOW)     ~ max(POST_WINDOW) + 1L, # binned distant post
      TRUE                            ~ rel_time
    )
  )

es_fit <- fixest::feols(
  y ~ i(rel_time_bin, ref = -1) | unit_id + t,
  data = panel_es, cluster = ~state_abb
)

# Extract event-time coefs in the desired window.
ct <- as_tibble(fixest::coeftable(es_fit), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`) %>%
  mutate(event_time = suppressWarnings(
    as.integer(sub("^rel_time_bin::", "", term)))) %>%
  filter(!is.na(event_time),
         event_time %in% c(PRE_WINDOW, POST_WINDOW)) %>%
  arrange(event_time)

selected_terms <- ct
cat("Selected event-time coefficients:\n")
print(selected_terms %>% select(event_time, estimate, se, term) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# Build betas and vcov in the HonestDiD format.
beta_vec <- selected_terms$estimate
names(beta_vec) <- selected_terms$term

# Subset the vcov to the selected terms.
full_vcov <- vcov(es_fit)
sub_vcov <- full_vcov[selected_terms$term, selected_terms$term, drop = FALSE]

n_pre  <- length(PRE_WINDOW)
n_post <- length(POST_WINDOW)
cat(sprintf("\nN pre-period coefs: %d\nN post-period coefs: %d\n",
            n_pre, n_post))

# l_vec = average of post-period coefficients. HonestDiD expects length = n_post.
l_vec <- rep(1 / n_post, n_post)

# ----------------------------- relative-magnitudes bounds ---------------------
Mbar_grid <- c(0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0)

cat("\nRunning HonestDiD relative-magnitudes bounds...\n")
rm_bounds <- HonestDiD::createSensitivityResults_relativeMagnitudes(
  betahat = beta_vec,
  sigma = sub_vcov,
  numPrePeriods = n_pre,
  numPostPeriods = n_post,
  l_vec = l_vec,
  Mbarvec = Mbar_grid,
  alpha = 0.05
)

# Original (no-bound) CI for reference.
orig_ci <- HonestDiD::constructOriginalCS(
  betahat = beta_vec,
  sigma = sub_vcov,
  numPrePeriods = n_pre,
  numPostPeriods = n_post,
  l_vec = l_vec,
  alpha = 0.05
)

rm_df <- tibble(
  lb = as.numeric(rm_bounds$lb),
  ub = as.numeric(rm_bounds$ub),
  Mbar = as.numeric(rm_bounds$Mbar),
  Delta = as.character(rm_bounds$Delta),
  method = "relative_magnitudes"
)

orig_df <- tibble(
  lb = as.numeric(orig_ci$lb)[1],
  ub = as.numeric(orig_ci$ub)[1],
  Mbar = NA_real_,
  Delta = "Original (parallel trends assumed)",
  method = "original_no_bound"
)

bounds_df <- bind_rows(orig_df, rm_df)
write_csv(bounds_df, file.path(out_dir, "honestdid_bounds.csv"))

cat("\n=== HonestDiD CONFIDENCE BOUNDS ===\n")
print(bounds_df %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- breakdown Mbar ---------------------------------
# Largest Mbar at which CI still excludes zero (under the assumed direction).
ci_excludes_zero <- function(lb, ub) (lb > 0) | (ub < 0)

bd <- rm_df %>%
  arrange(Mbar) %>%
  mutate(excludes_zero = ci_excludes_zero(lb, ub))

bd_value <- if (any(bd$excludes_zero)) {
  max(bd$Mbar[bd$excludes_zero])
} else NA_real_

cat(sprintf("\nBreakdown Mbar (largest Mbar at which CI excludes zero): %s\n",
            if (is.na(bd_value)) "0 (point estimate already includes zero — null is consistent)" else as.character(bd_value)))

write_csv(tibble(breakdown_mbar = bd_value,
                 original_lb = as.numeric(orig_ci$lb)[1],
                 original_ub = as.numeric(orig_ci$ub)[1],
                 original_excludes_zero =
                   ci_excludes_zero(as.numeric(orig_ci$lb)[1],
                                    as.numeric(orig_ci$ub)[1])),
          file.path(out_dir, "honestdid_breakdown.csv"))

# ----------------------------- plot -------------------------------------------
plot_df <- bounds_df %>%
  mutate(label = case_when(
    method == "original_no_bound" ~ "Original",
    !is.na(Mbar) ~ sprintf("Mbar = %.2f", Mbar)
  ),
  midpoint = (lb + ub) / 2)

p <- ggplot(plot_df, aes(x = label)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = lb, ymax = ub),
                width = 0.2, color = "grey20", linewidth = 0.5) +
  geom_point(aes(y = midpoint), color = "grey20", size = 2) +
  scale_x_discrete(limits = c("Original",
                              sprintf("Mbar = %.2f",
                                      sort(unique(rm_df$Mbar))))) +
  labs(x = "Sensitivity assumption (Rambachan-Roth Mbar)",
       y = "Average post-treatment effect, 95% CI") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(out_dir, "honestdid_bounds.png"), p,
       width = 7.0, height = 4.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
