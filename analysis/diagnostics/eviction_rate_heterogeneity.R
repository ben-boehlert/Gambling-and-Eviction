#!/usr/bin/env Rscript
################################################################################
# eviction_rate_heterogeneity.R
#
# Tests substantive heterogeneity by pre-treatment eviction rate, on a scale
# (levels of filings per 1k renters) where the denominator effect is absent.
#
# Why this matters: the earlier finding that per-state log-ATT correlates
# strongly with pre-treatment filings per 1k renters (-0.76, p=0.005) is
# mechanical on the log scale — a given absolute increase in filings becomes
# a smaller percent change when the baseline is high. To assess substantive
# heterogeneity (i.e., do higher-eviction-rate counties experience LARGER
# absolute eviction increases?), we need an outcome scale where the
# denominator effect is absent.
#
# Three outcome scales:
#   1. dy_log = log1p(filings_count_late) - log1p(filings_count_pre)
#      (the current headline; denominator-effect-prone)
#   2. dy_rate_level = filings_per_1k_late - filings_per_1k_pre
#      (levels, denominator-effect-free)
#   3. dy_rate_log = log1p(filings_per_1k_late) - log1p(filings_per_1k_pre)
#      (still log-scale but normalized by renter pop)
#
# For each scale: run the interaction ever_treated × pre_filings_per_1k_renters
# and compare. Substantive heterogeneity is detected if the interaction's
# direction differs across scales.
#
# Outputs:
#   output/border_diagnostic/eviction_rate_heterogeneity/{
#     by_scale.csv,
#     rate_levels_interactions.csv,
#     summary.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "eviction_rate_heterogeneity")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

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

trump_2020 <- tibble::tribble(
  ~state_abb, ~trump_2020_share,
  "AL",62.0,"AK",53.1,"AZ",49.1,"AR",62.4,"CA",34.3,"CO",41.9,"CT",39.2,
  "DE",39.8,"FL",51.2,"GA",49.2,"HI",34.3,"ID",63.8,"IL",40.5,"IN",57.0,
  "IA",53.1,"KS",56.2,"KY",62.1,"LA",58.5,"MD",32.2,"MA",32.1,"MI",47.8,
  "MN",45.3,"MS",57.6,"MO",56.8,"MT",56.9,"NE",58.2,"NV",47.7,"NJ",41.4,
  "NM",43.5,"NY",37.7,"NC",49.9,"ND",65.1,"OH",53.3,"OK",65.4,"OR",40.4,
  "PA",48.8,"RI",38.6,"SC",55.1,"SD",61.8,"TN",60.7,"TX",52.1,"UT",58.1,
  "VT",30.7,"VA",44.0,"WA",38.8,"WV",68.6,"WI",48.8,"WY",69.9
)

DROP_STATES <- c("ME", "NH")
PRE_START  <- as.Date("2018-01-01")
PRE_END    <- as.Date("2019-12-31")
LATE_START <- as.Date("2024-01-01")
LATE_END   <- as.Date("2024-12-31")

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count),
         renter_occupied_housing_units =
           as.numeric(renter_occupied_housing_units),
         poverty_rate = as.numeric(poverty_rate)) %>%
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
  filter(n_counties >= 5L) %>% pull(state_abb)

panel <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  left_join(state_treat_one, by = "state_abb") %>%
  left_join(trump_2020, by = "state_abb") %>%
  mutate(filings_per_1k = if_else(renter_occupied_housing_units > 0,
                                   1000 * filings_count /
                                     renter_occupied_housing_units,
                                   NA_real_),
         ever_treated = !is.na(treat_start))

# County-level period means.
county_means <- panel %>%
  mutate(
    period = case_when(
      month_date >= PRE_START & month_date <= PRE_END   ~ "pre",
      month_date >= LATE_START & month_date <= LATE_END ~ "late",
      TRUE                                              ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(fips, state_abb, ever_treated, trump_2020_share, period) %>%
  summarise(
    n_months = n(),
    y_log = mean(log1p(pmax(filings_count, 0)), na.rm = TRUE),
    y_rate = mean(filings_per_1k, na.rm = TRUE),
    y_rate_log = mean(log1p(pmax(filings_per_1k, 0)), na.rm = TRUE),
    pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
    poverty_rate = mean(poverty_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period,
              values_from = c(n_months, y_log, y_rate, y_rate_log,
                              pop_renter, poverty_rate)) %>%
  filter(n_months_pre >= 6L, n_months_late >= 6L) %>%
  mutate(
    dy_log = y_log_late - y_log_pre,
    dy_rate_level = y_rate_late - y_rate_pre,
    dy_rate_log = y_rate_log_late - y_rate_log_pre,
    log_pop_pre = log(pop_renter_pre),
    pre_filings_rate = y_rate_pre,
    pre_filings_rate_c = pre_filings_rate -
      mean(pre_filings_rate, na.rm = TRUE),
    pov_pre_c = poverty_rate_pre - mean(poverty_rate_pre, na.rm = TRUE),
    log_pop_pre_c = log_pop_pre - mean(log_pop_pre, na.rm = TRUE),
    trump_share_c = trump_2020_share - mean(trump_2020_share, na.rm = TRUE),
    # Median splits for subgroup analysis
    high_evict = pre_filings_rate > median(pre_filings_rate, na.rm = TRUE)
  ) %>%
  filter(is.finite(dy_log), is.finite(dy_rate_level), is.finite(dy_rate_log))

cat("Long-difference panel:\n")
cat("  Counties:", nrow(county_means), "\n")
cat("  Treated:", sum(county_means$ever_treated),
    "  Never-treated:", sum(!county_means$ever_treated), "\n\n")
cat("Pre-treatment filings per 1k renters distribution:\n")
print(summary(county_means$pre_filings_rate))
cat("\n")

# ----------------------------- helper ----------------------------------------

extract_terms <- function(fit, main_name, int_name, spec_label) {
  ct <- fixest::coeftable(fit)
  rn <- rownames(ct)
  m  <- intersect(c(main_name, "ever_treated"), rn)[1]
  i  <- intersect(int_name, rn)[1]
  tibble(
    spec = spec_label,
    main_att = if (!is.na(m)) as.numeric(ct[m, "Estimate"]) else NA_real_,
    main_se  = if (!is.na(m)) as.numeric(ct[m, "Std. Error"]) else NA_real_,
    interaction = if (!is.na(i)) as.numeric(ct[i, "Estimate"]) else NA_real_,
    interaction_se = if (!is.na(i)) as.numeric(ct[i, "Std. Error"])
                     else NA_real_,
    interaction_p = if (!is.na(i)) as.numeric(ct[i, "Pr(>|t|)"]) else NA_real_,
    n_obs = fit$nobs
  )
}

# ----------------------------- baseline ATTs across scales -------------------

cat("=== BASELINE ATTs ACROSS THREE OUTCOME SCALES ===\n")

m_log <- feols(
  dy_log ~ ever_treated + y_log_pre + log_pop_pre + poverty_rate_pre +
            trump_share_c,
  data = county_means, cluster = ~state_abb
)
m_lvl <- feols(
  dy_rate_level ~ ever_treated + y_rate_pre + log_pop_pre + poverty_rate_pre +
                   trump_share_c,
  data = county_means, cluster = ~state_abb
)
m_rlg <- feols(
  dy_rate_log ~ ever_treated + y_rate_log_pre + log_pop_pre + poverty_rate_pre +
                 trump_share_c,
  data = county_means, cluster = ~state_abb
)

by_scale <- bind_rows(
  extract_terms(m_log, "ever_treatedTRUE", "ever_treatedTRUE:pre_filings_rate_c",
                 "log1p(filings) — current headline (DENOMINATOR-PRONE)"),
  extract_terms(m_lvl, "ever_treatedTRUE", "ever_treatedTRUE:pre_filings_rate_c",
                 "filings_per_1k LEVELS (denominator-effect-free)"),
  extract_terms(m_rlg, "ever_treatedTRUE", "ever_treatedTRUE:pre_filings_rate_c",
                 "log1p(filings_per_1k) — rate in logs")
)
write_csv(by_scale, file.path(out_dir, "by_scale.csv"))

cat("\nMain effect at sample-mean characteristics (no interaction yet):\n")
print(by_scale %>%
        select(spec, main_att, main_se, n_obs) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- interactions WITH pre-eviction-rate -----------

cat("\n=== INTERACTIONS WITH PRE-TREATMENT EVICTION RATE ===\n")

m_log_x <- feols(
  dy_log ~ ever_treated * pre_filings_rate_c + y_log_pre + log_pop_pre +
            poverty_rate_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
m_lvl_x <- feols(
  dy_rate_level ~ ever_treated * pre_filings_rate_c + log_pop_pre +
                   poverty_rate_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)
m_rlg_x <- feols(
  dy_rate_log ~ ever_treated * pre_filings_rate_c + y_rate_log_pre +
                 log_pop_pre + poverty_rate_pre + trump_share_c,
  data = county_means, cluster = ~state_abb
)

interactions <- bind_rows(
  extract_terms(m_log_x, "ever_treatedTRUE",
                 "ever_treatedTRUE:pre_filings_rate_c",
                 "log1p(filings) × pre-rate"),
  extract_terms(m_lvl_x, "ever_treatedTRUE",
                 "ever_treatedTRUE:pre_filings_rate_c",
                 "filings_per_1k LEVELS × pre-rate"),
  extract_terms(m_rlg_x, "ever_treatedTRUE",
                 "ever_treatedTRUE:pre_filings_rate_c",
                 "log1p(filings_per_1k) × pre-rate")
)
write_csv(interactions, file.path(out_dir, "rate_levels_interactions.csv"))

cat("\nInteraction with pre-treatment filings per 1k renters (centered):\n")
print(interactions %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- subgroup ATTs by eviction rate ----------------

cat("\n=== SUBGROUP ATTs: HIGH vs LOW pre-treatment eviction rate ===\n")

run_sub <- function(panel_in, formula_str, label) {
  fmla <- as.formula(formula_str)
  fit <- feols(fmla, data = panel_in, cluster = ~state_abb)
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  att <- as.numeric(ct[rn, "Estimate"])
  se  <- as.numeric(ct[rn, "Std. Error"])
  tibble(spec = label, att = att, se = se,
         ci_low = att - 1.96 * se, ci_high = att + 1.96 * se,
         n_obs = fit$nobs)
}

# Subset by high/low evict.
sub_results <- bind_rows(
  # LOG scale
  run_sub(county_means %>% filter(!high_evict),
          "dy_log ~ ever_treated + y_log_pre + log_pop_pre + poverty_rate_pre + trump_share_c",
          "log1p(filings) — LOW eviction rate"),
  run_sub(county_means %>% filter(high_evict),
          "dy_log ~ ever_treated + y_log_pre + log_pop_pre + poverty_rate_pre + trump_share_c",
          "log1p(filings) — HIGH eviction rate"),
  # LEVELS scale (denominator-effect-free)
  run_sub(county_means %>% filter(!high_evict),
          "dy_rate_level ~ ever_treated + y_rate_pre + log_pop_pre + poverty_rate_pre + trump_share_c",
          "LEVELS (filings/1k) — LOW eviction rate"),
  run_sub(county_means %>% filter(high_evict),
          "dy_rate_level ~ ever_treated + y_rate_pre + log_pop_pre + poverty_rate_pre + trump_share_c",
          "LEVELS (filings/1k) — HIGH eviction rate")
)
write_csv(sub_results, file.path(out_dir, "subgroup_by_evict_rate.csv"))
print(sub_results %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- summary plot ----------------------------------

plot_df <- interactions %>%
  mutate(label = sub("^[^×]+ × ", "", spec),
         scale = sub(" ×.*", "", spec),
         ci_low = interaction - 1.96 * interaction_se,
         ci_high = interaction + 1.96 * interaction_se)

p <- ggplot(plot_df, aes(x = scale, y = interaction)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = 0.3,
                color = "grey20") +
  geom_point(size = 2.5, color = "grey20") +
  coord_flip() +
  labs(x = NULL,
       y = "Interaction coefficient: ever_treated × (pre-treatment filings per 1k renters)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(out_dir, "interaction_across_scales.png"), p,
       width = 8, height = 3.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
