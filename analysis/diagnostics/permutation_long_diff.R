#!/usr/bin/env Rscript
################################################################################
# permutation_long_diff.R
#
# Card-Krueger / Bertrand-Duflo-Mullainathan-style randomization inference
# on the long-difference DiD headline.
#
# Procedure:
#   1. Build the county-level long-difference panel (2018-2019 mean vs 2024
#      mean of log1p(filings_count), 23 states, NH excluded for data-quality)
#   2. Note the real ATT under the actual treatment assignment (13 states
#      legalize, 10 never-treated)
#   3. For each of B = 1000 permutations:
#        - Randomly select 13 of the 23 states to be "pretend treated"
#        - Re-run the long-difference DiD with the permuted indicator
#        - Record the placebo ATT
#   4. Compute exact p-values from the permutation distribution:
#        p_one_sided  = P(perm_ATT >= real_ATT)
#        p_two_sided  = P(|perm_ATT| >= |real_ATT|)
#
# Run for three specifications:
#   - Long-difference, no controls (+10.6% headline, CI ~ [-2%, +22%])
#   - Long-difference, + baseline + pop + poverty (+13.8%, CI [+2.3%, +23.6%])
#   - Long-difference, + baseline + pop + poverty + partisanship (+15.3%,
#     CI [+3.0%, +25.5%]) — the recommended headline
#
# Outputs:
#   output/border_diagnostic/permutation_inference/{
#     permutation_atts.csv,
#     p_values.csv,
#     histogram.png
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2)
})

set.seed(20260521L)

B <- as.integer(Sys.getenv("B_PERM", "1000"))

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "permutation_inference")
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
  "AL", 62.0,  "AK", 53.1,  "AZ", 49.1,  "AR", 62.4,  "CA", 34.3,
  "CO", 41.9,  "CT", 39.2,  "DE", 39.8,  "DC", 5.4,   "FL", 51.2,
  "GA", 49.2,  "HI", 34.3,  "ID", 63.8,  "IL", 40.5,  "IN", 57.0,
  "IA", 53.1,  "KS", 56.2,  "KY", 62.1,  "LA", 58.5,  "ME", 44.0,
  "MD", 32.2,  "MA", 32.1,  "MI", 47.8,  "MN", 45.3,  "MS", 57.6,
  "MO", 56.8,  "MT", 56.9,  "NE", 58.2,  "NV", 47.7,  "NH", 45.4,
  "NJ", 41.4,  "NM", 43.5,  "NY", 37.7,  "NC", 49.9,  "ND", 65.1,
  "OH", 53.3,  "OK", 65.4,  "OR", 40.4,  "PA", 48.8,  "RI", 38.6,
  "SC", 55.1,  "SD", 61.8,  "TN", 60.7,  "TX", 52.1,  "UT", 58.1,
  "VT", 30.7,  "VA", 44.0,  "WA", 38.8,  "WV", 68.6,  "WI", 48.8,
  "WY", 69.9
)

DROP_STATES <- c("ME", "NH")
PRE_START  <- as.Date("2018-01-01")
PRE_END    <- as.Date("2019-12-31")
LATE_START <- as.Date("2024-01-01")
LATE_END   <- as.Date("2024-12-31")

# ----------------------------- build county-level long-difference panel -------

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
  mutate(y = log1p(pmax(filings_count, 0)),
         ever_treated_real = !is.na(treat_start))

county_means <- panel %>%
  mutate(
    period = case_when(
      month_date >= PRE_START & month_date <= PRE_END   ~ "pre",
      month_date >= LATE_START & month_date <= LATE_END ~ "late",
      TRUE                                              ~ NA_character_
    )
  ) %>%
  filter(!is.na(period)) %>%
  group_by(fips, state_abb, ever_treated_real, trump_2020_share, period) %>%
  summarise(
    n_months = n(),
    y_mean = mean(y, na.rm = TRUE),
    pop_renter = mean(renter_occupied_housing_units, na.rm = TRUE),
    poverty_rate = mean(poverty_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period,
              values_from = c(n_months, y_mean, pop_renter, poverty_rate)) %>%
  filter(n_months_pre >= 6L, n_months_late >= 6L) %>%
  mutate(dy = y_mean_late - y_mean_pre)

state_list <- sort(unique(county_means$state_abb))
n_states <- length(state_list)
real_treated_states <- county_means %>%
  filter(ever_treated_real) %>%
  distinct(state_abb) %>%
  pull(state_abb)
n_real_treated <- length(real_treated_states)

cat("Permutation inference setup:\n")
cat("  Counties:", nrow(county_means), "\n")
cat("  States in pool:", n_states, "\n")
cat("  Actually-treated states:", n_real_treated, "\n")
cat("  States:", paste(state_list, collapse = ", "), "\n")
cat("  Permutations:", B, "\n\n")

# ----------------------------- specifications ---------------------------------

spec_formulas <- list(
  no_controls = dy ~ ever_treated,
  with_baseline = dy ~ ever_treated + y_mean_pre + log(pop_renter_pre) +
                       poverty_rate_pre,
  with_baseline_partisan = dy ~ ever_treated + y_mean_pre + log(pop_renter_pre) +
                              poverty_rate_pre + trump_2020_share
)

extract_att <- function(fit) {
  ct <- fixest::coeftable(fit)
  rn <- intersect(c("ever_treatedTRUE", "ever_treated"), rownames(ct))[1]
  if (is.na(rn)) return(NA_real_)
  as.numeric(ct[rn, "Estimate"])
}

# ----------------------------- real ATTs --------------------------------------

cm <- county_means %>% mutate(ever_treated = ever_treated_real)

real_atts <- sapply(spec_formulas, function(fmla) {
  fit <- feols(fmla, data = cm, cluster = ~state_abb)
  extract_att(fit)
})

cat("Real ATTs:\n")
print(round(real_atts, 4))
cat("As % effect:\n")
print(round(100 * (exp(real_atts) - 1), 2))

# ----------------------------- permutation run --------------------------------

cat(sprintf("\nRunning %d permutations...\n", B))

perm_atts <- matrix(NA_real_, nrow = B, ncol = length(spec_formulas))
colnames(perm_atts) <- names(spec_formulas)

t0 <- Sys.time()
for (b in seq_len(B)) {
  pretend_treated <- sample(state_list, size = n_real_treated)
  cm_b <- county_means %>%
    mutate(ever_treated = state_abb %in% pretend_treated)

  for (k in seq_along(spec_formulas)) {
    fit_b <- tryCatch(
      feols(spec_formulas[[k]], data = cm_b, cluster = ~state_abb,
            warn = FALSE, notes = FALSE),
      error = function(e) NULL
    )
    if (!is.null(fit_b)) perm_atts[b, k] <- extract_att(fit_b)
  }

  if (b %% 100 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta <- (B - b) * elapsed / b
    cat(sprintf("  [%d/%d] elapsed=%.0fs, ETA=%.0fs\n",
                b, B, elapsed, eta))
  }
}

elapsed_tot <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nDone in %.0fs\n\n", elapsed_tot))

# ----------------------------- p-values ---------------------------------------

p_values <- bind_rows(lapply(seq_along(spec_formulas), function(k) {
  perm_v <- perm_atts[, k]
  perm_v <- perm_v[is.finite(perm_v)]
  real <- real_atts[k]
  tibble(
    spec = names(spec_formulas)[k],
    real_att = real,
    pct_effect = 100 * (exp(real) - 1),
    n_perm_valid = length(perm_v),
    perm_mean = mean(perm_v),
    perm_median = median(perm_v),
    perm_sd = sd(perm_v),
    perm_q025 = unname(quantile(perm_v, 0.025)),
    perm_q975 = unname(quantile(perm_v, 0.975)),
    real_percentile = mean(perm_v < real),
    p_one_sided  = mean(perm_v >= real),
    p_two_sided  = mean(abs(perm_v) >= abs(real))
  )
}))

write_csv(p_values, file.path(out_dir, "p_values.csv"))

cat("=== PERMUTATION INFERENCE RESULTS ===\n")
print(p_values %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# ----------------------------- save permutation distribution ------------------

perm_df <- as_tibble(perm_atts, .name_repair = "minimal") %>%
  mutate(perm = seq_len(B)) %>%
  pivot_longer(-perm, names_to = "spec", values_to = "perm_att") %>%
  filter(is.finite(perm_att))
write_csv(perm_df, file.path(out_dir, "permutation_atts.csv"))

# ----------------------------- histogram --------------------------------------

real_df <- tibble(spec = names(real_atts), real_att = unname(real_atts))

p <- perm_df %>%
  ggplot(aes(x = perm_att)) +
  geom_histogram(bins = 40, fill = "grey80", color = "grey30",
                 linewidth = 0.2) +
  geom_vline(xintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(data = real_df, aes(xintercept = real_att),
             linetype = "dashed", color = "grey15", linewidth = 0.6) +
  geom_text(data = real_df,
            aes(x = real_att, y = Inf,
                label = sprintf("Real ATT = %.3f", real_att)),
            vjust = 1.5, hjust = -0.05, size = 3, family = "serif") +
  facet_wrap(~ spec, ncol = 1, scales = "free_y") +
  labs(x = "Permuted long-difference ATT",
       y = "Count") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain", size = rel(0.95)))

ggsave(file.path(out_dir, "histogram.png"), p,
       width = 7, height = 7, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
