#!/usr/bin/env Rscript
################################################################################
# honestdid_levels.R
#
# HonestDiD (Rambachan & Roth 2023) sensitivity bounds on the long-difference
# in the LEVEL scale (filings per 1k renters per month).
#
# Method: fit an event-study on filings_per_1k with i(rel_time, ref = -1),
# extract pre-period (-12 to -2) and post-period (0 to +12) coefficients
# and the full vcov. Use l_vec = average of post-period coefficients to
# bound the average long-difference treatment effect under various
# relative-magnitudes assumptions M.
#
# Reports:
#   - Original (no-restriction) CI on the average post-period effect
#   - CIs at M ∈ {0, 0.25, 0.5, 0.75, 1, 1.5, 2}
#   - Breakdown M: largest M at which the CI still excludes zero
#
# Outputs:
#   output/border_diagnostic/honestdid_levels/{
#     bounds.csv,
#     bounds.png,
#     breakdown.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(fixest)
  library(HonestDiD); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "honestdid_levels")
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
PRE_W  <- -12L:-2L
POST_W <- 0L:18L   # 18 months post-treatment — balances HonestDiD compute with horizon coverage

# ----------------------------- build panel ------------------------------------

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
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    y_rate = if_else(renter_occupied_housing_units > 0,
                      1000 * filings_count / renter_occupied_housing_units,
                      NA_real_)
  ) %>%
  filter(is.finite(y_rate), !is.na(unit_id), !is.na(t)) %>%
  mutate(rel_time = if_else(is.na(g), NA_integer_, as.integer(t - g)),
         rel_time_bin = case_when(
           is.na(rel_time)               ~ NA_integer_,
           rel_time < min(PRE_W)         ~ min(PRE_W) - 1L,
           rel_time > max(POST_W)        ~ max(POST_W) + 1L,
           TRUE                          ~ rel_time
         ))

# ----------------------------- fit event study --------------------------------

cat("Fitting event-study on filings_per_1k (LEVELS)...\n")
es_fit <- fixest::feols(
  y_rate ~ i(rel_time_bin, ref = -1) | unit_id + t,
  data = panel, cluster = ~state_abb
)

ct <- as_tibble(fixest::coeftable(es_fit), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`) %>%
  mutate(event_time = suppressWarnings(
    as.integer(sub("^rel_time_bin::", "", term)))) %>%
  filter(!is.na(event_time),
         event_time %in% c(PRE_W, POST_W)) %>%
  arrange(event_time)

cat("\nEvent-study coefficients (LEVELS):\n")
print(ct %>% select(event_time, estimate, se) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- vcov for HonestDiD -----------------------------

beta_vec <- ct$estimate
names(beta_vec) <- ct$term
full_vcov <- vcov(es_fit)
sub_vcov  <- full_vcov[ct$term, ct$term, drop = FALSE]

n_pre  <- length(PRE_W)
n_post <- length(POST_W)
l_vec  <- rep(1 / n_post, n_post)   # average of post-period coefficients

cat(sprintf("\nN pre-period coefs: %d\nN post-period coefs: %d\n",
            n_pre, n_post))
cat(sprintf("Average post-period (raw): %.4f\n",
            mean(ct$estimate[ct$event_time >= 0])))

# ----------------------------- HonestDiD bounds -------------------------------

Mbar_grid <- c(0, 0.25, 0.5, 0.75, 1, 1.5, 2)

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
write_csv(bounds_df, file.path(out_dir, "bounds.csv"))

cat("\n=== HonestDiD BOUNDS (LEVELS scale) ===\n")
print(bounds_df %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# Breakdown: largest Mbar at which CI still excludes zero.
ci_excludes_zero <- function(lb, ub) (lb > 0) | (ub < 0)

bd <- rm_df %>%
  arrange(Mbar) %>%
  mutate(excludes_zero = ci_excludes_zero(lb, ub))
bd_value <- if (any(bd$excludes_zero)) {
  max(bd$Mbar[bd$excludes_zero])
} else NA_real_

cat(sprintf("\nBreakdown Mbar (largest Mbar at which CI excludes zero): %s\n",
            if (is.na(bd_value))
              "0 (point estimate's CI already includes zero — null is robust)"
            else as.character(bd_value)))

write_csv(tibble(
  breakdown_mbar = bd_value,
  original_lb = as.numeric(orig_ci$lb)[1],
  original_ub = as.numeric(orig_ci$ub)[1],
  original_excludes_zero = ci_excludes_zero(as.numeric(orig_ci$lb)[1],
                                            as.numeric(orig_ci$ub)[1]),
  raw_post_period_mean = mean(ct$estimate[ct$event_time >= 0])
), file.path(out_dir, "breakdown.csv"))

# ----------------------------- plot -------------------------------------------

plot_df <- bounds_df %>%
  mutate(label = case_when(
    method == "original_no_bound" ~ "Original",
    !is.na(Mbar) ~ sprintf("M = %.2f", Mbar)
  ),
  midpoint = (lb + ub) / 2)

p <- ggplot(plot_df, aes(x = label)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = lb, ymax = ub),
                width = 0.2, color = "grey20", linewidth = 0.5) +
  geom_point(aes(y = midpoint), color = "grey20", size = 2) +
  scale_x_discrete(limits = c("Original",
                              sprintf("M = %.2f",
                                      sort(unique(rm_df$Mbar))))) +
  labs(x = "Sensitivity assumption (Rambachan-Roth Mbar)",
       y = "Long-difference ATT in levels (filings per 1k renters, 95% CI)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(out_dir, "bounds.png"), p,
       width = 7.0, height = 4.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
