#!/usr/bin/env Rscript
################################################################################
# hollenbeck_style.R
#
# Hollenbeck, Larsen & Proserpio (2025) "Sports Betting's Impact on Vulnerable
# Households" methodology, ported from individual-level UC Consumer Credit
# Panel to our county-level eviction data.
#
# Their setup:
#   - Individual-level data (~7M consumers), state-level treatment, state clustering
#   - CS-DiD (Callaway-Sant'Anna) with multiplier BOOTSTRAP inference (not analytic)
#   - Event study by event_time (dynamic effects, not just simple ATT)
#   - Heterogeneity by subprime status (credit score)
#
# Our port:
#   - County-level data, state-level treatment, state clustering
#   - CS-DiD with bootstrap (bstrap = TRUE, biters = 999, default cluster at state)
#   - Event study with did::aggte(type = "dynamic")
#   - Heterogeneity by county poverty rate (proxy for "vulnerable households")
#
# Outputs:
#   output/border_diagnostic/hollenbeck_style/{
#     overall_att.csv,
#     dynamic_event_study.csv,
#     dynamic_event_study.png,
#     heterogeneity_by_poverty.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(did)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "hollenbeck_style")
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

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")
MIN_COUNTIES <- 5L

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count),
         poverty_rate = as.numeric(poverty_rate)) %>%
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
         g = if_else(!is.na(treat_start),
                     as.integer(ym_index(treat_start)), 0L),
         g = as.integer(g),
         id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(id), !is.na(t)) %>%
  arrange(id, t)

cat("Hollenbeck-style CS-DiD panel:\n")
cat("  Counties:", n_distinct(panel$id), "\n")
cat("  States:", n_distinct(panel$state_abb),
    "(", n_distinct(panel$state_abb[panel$g > 0]), "treated,",
    n_distinct(panel$state_abb[panel$g == 0]), "never-treated)\n")
cat("  Months:", n_distinct(panel$t), "\n")
cat("  Obs:", nrow(panel), "\n\n")

dat <- as.data.frame(panel)

# ----------------------------- CS-DiD with bootstrap --------------------------

cat("Fitting CS-DiD with multiplier bootstrap (biters = 999)...\n")
cs_fit <- did::att_gt(
  yname = "y", tname = "t", idname = "id", gname = "g",
  data = dat, est_method = "reg",
  control_group = "notyettreated",
  clustervars = "state_abb",
  bstrap = TRUE, biters = 999, cband = TRUE,
  allow_unbalanced_panel = TRUE, print_details = FALSE,
  faster_mode = FALSE
)

# Overall ATT (simple aggregation).
cs_simple <- did::aggte(cs_fit, type = "simple", na.rm = TRUE,
                        bstrap = TRUE, biters = 999, cband = TRUE)

cat("\nOverall ATT (bootstrap inference):\n")
cat(sprintf("  ATT = %.5f, SE = %.5f, 95%% CI = [%.4f, %.4f]\n",
            cs_simple$overall.att,
            cs_simple$overall.se,
            cs_simple$overall.att - 1.96 * cs_simple$overall.se,
            cs_simple$overall.att + 1.96 * cs_simple$overall.se))

write_csv(tibble(
  spec = "cs_did_county_bootstrap",
  att = cs_simple$overall.att,
  se = cs_simple$overall.se,
  ci_low_95 = cs_simple$overall.att - 1.96 * cs_simple$overall.se,
  ci_high_95 = cs_simple$overall.att + 1.96 * cs_simple$overall.se,
  biters = 999,
  inference = "multiplier_bootstrap"
), file.path(out_dir, "overall_att.csv"))

# ----------------------------- dynamic event study ----------------------------

cat("\nFitting dynamic event-study aggregation...\n")
cs_dynamic <- did::aggte(cs_fit, type = "dynamic", na.rm = TRUE,
                         bstrap = TRUE, biters = 999, cband = TRUE,
                         min_e = -12, max_e = 12)

dyn_tab <- tibble(
  event_time = cs_dynamic$egt,
  estimate   = cs_dynamic$att.egt,
  se         = cs_dynamic$se.egt,
  ci_low_95  = cs_dynamic$att.egt - 1.96 * cs_dynamic$se.egt,
  ci_high_95 = cs_dynamic$att.egt + 1.96 * cs_dynamic$se.egt
)

write_csv(dyn_tab, file.path(out_dir, "dynamic_event_study.csv"))

cat("\nDynamic event study (event_time -12 to +12, bootstrap CIs):\n")
print(dyn_tab %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

# Pre-trends joint test from CS.
cat(sprintf("\nCS-DiD joint pre-trends test (Wald): stat = %.3f, p = %.4f\n",
            cs_fit$Wpval, cs_fit$Wpval))

# Plot.
p <- ggplot(dyn_tab, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low_95, ymax = ci_high_95),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.8) +
  scale_x_continuous(breaks = seq(-12, 12, 3)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "dynamic_event_study.png"), p,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")

# ----------------------------- heterogeneity by poverty -----------------------

cat("\nHeterogeneity by county poverty rate...\n")

# Median-split by county-mean poverty rate.
pov_by_county <- dat %>%
  group_by(id) %>%
  summarise(pov = mean(poverty_rate, na.rm = TRUE), .groups = "drop")
pov_median <- median(pov_by_county$pov, na.rm = TRUE)

dat <- dat %>%
  left_join(pov_by_county, by = "id") %>%
  mutate(high_poverty = pov >= pov_median)

run_cs_subset <- function(subset_label, subset_data) {
  cat(sprintf("  Fitting CS-DiD on %s (n=%d obs, %d counties)...\n",
              subset_label, nrow(subset_data),
              n_distinct(subset_data$id)))

  fit <- tryCatch({
    did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g",
      data = subset_data, est_method = "reg",
      control_group = "notyettreated",
      clustervars = "state_abb",
      bstrap = TRUE, biters = 999, cband = TRUE,
      allow_unbalanced_panel = TRUE, print_details = FALSE,
      faster_mode = FALSE
    )
  }, error = function(e) {
    cat("    failed:", conditionMessage(e), "\n"); return(NULL)
  })
  if (is.null(fit)) return(NULL)

  agg <- did::aggte(fit, type = "simple", na.rm = TRUE,
                    bstrap = TRUE, biters = 999)
  tibble(
    subset = subset_label,
    n_obs = nrow(subset_data),
    n_counties = n_distinct(subset_data$id),
    att = agg$overall.att,
    se = agg$overall.se,
    ci_low_95 = agg$overall.att - 1.96 * agg$overall.se,
    ci_high_95 = agg$overall.att + 1.96 * agg$overall.se
  )
}

het_rows <- list(
  run_cs_subset("high_poverty",  dat %>% filter(high_poverty)),
  run_cs_subset("low_poverty",   dat %>% filter(!high_poverty))
)
het_df <- bind_rows(het_rows)
write_csv(het_df, file.path(out_dir, "heterogeneity_by_poverty.csv"))

cat("\n=== HETEROGENEITY BY POVERTY RATE ===\n")
print(het_df %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

cat("\nMedian county-mean poverty rate:", round(pov_median, 2), "%\n")
cat("\nWrote outputs to:", out_dir, "\n")
