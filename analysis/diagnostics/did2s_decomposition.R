#!/usr/bin/env Rscript
################################################################################
# did2s_decomposition.R
#
# Uses did2s (Gardner 2022) — the calibrated heterogeneity-robust estimator
# from the multi-estimator test — to decompose the all-county null three ways:
#
#   1. Per-state ATT: one did2s run per treated state vs all never-treated.
#      Reveals which states drive the aggregate result.
#
#   2. Per-state event-study pre-period: the cohort-by-cohort pretrend pattern,
#      computed with did2s (calibrated SEs) instead of sunab (over-tight SEs).
#
#   3. Pre/post-COVID era split: aggregate did2s on (a) pre-COVID-treated
#      cohorts only, (b) full sample. Compare ATTs and pretrend patterns.
#
# All specs: log1p(filings_count), county + month FE, state clustering, COVID
# drop 2020-03 to 2022-03, ME excluded, states with <5 counties dropped.
#
# Outputs:
#   output/border_diagnostic/did2s_decomp/
#     by_state_att.csv         — one row per treated state with ATT, SE, CI
#     by_state_eventstudy.csv  — event-time coefs per cohort
#     by_state_eventstudy.png  — facet plot
#     era_split_att.csv        — pre-COVID, full sample, comparison
#     era_split_eventstudy.{csv,png}
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(fixest)
  library(did2s); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic", "did2s_decomp")
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
         first_treat = if_else(is.na(g), 0L, g),  # did2s convention
         post_treat = as.integer(!is.na(g) & t >= g),
         id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(id), !is.na(t))

treated_states <- panel %>%
  filter(!is.na(g)) %>%
  distinct(state_abb, g, treat_start) %>%
  arrange(g)

cat("Treated states in panel:\n")
print(treated_states)
cat("\n")

# ----------------------------- per-state ATT ----------------------------------

cat("=== PER-STATE ATT (did2s) ===\n")
per_state_results <- list()
for (i in seq_len(nrow(treated_states))) {
  s <- treated_states$state_abb[i]
  d <- treated_states$treat_start[i]
  label <- sprintf("%s (%s)", s, format(d, "%Y-%m"))
  cat(sprintf("  fitting %s ... ", label))

  sub <- panel %>% filter(state_abb == s | is.na(g))

  fit <- tryCatch({
    did2s::did2s(
      data = sub,
      yname = "y",
      first_stage = ~ 0 | id + t,
      second_stage = ~ post_treat,
      treatment = "post_treat",
      cluster_var = "state_abb"
    )
  }, error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })

  if (is.null(fit)) next

  ct <- tryCatch(fixest::coeftable(fit), error = function(e) NULL)
  if (is.null(ct)) { cat("no coeftable\n"); next }

  if (!("post_treat" %in% rownames(ct))) {
    cat("no post_treat row in coeftable\n"); next
  }
  att <- as.numeric(ct["post_treat", "Estimate"])
  se  <- as.numeric(ct["post_treat", "Std. Error"])

  per_state_results[[label]] <- tibble(
    state_abb = s,
    treat_start = d,
    cohort_label = label,
    n_obs = nrow(sub),
    n_treated_counties = n_distinct(sub$id[sub$state_abb == s]),
    n_control_counties = n_distinct(sub$id[is.na(sub$g)]),
    att = att,
    se = se,
    ci_low_95 = att - 1.96 * se,
    ci_high_95 = att + 1.96 * se,
    pct_effect = (exp(att) - 1) * 100
  )
  cat(sprintf("ATT=%.4f (%.1f%%), SE=%.4f\n", att, (exp(att) - 1) * 100, se))
}

by_state_df <- bind_rows(per_state_results) %>%
  arrange(treat_start)
write_csv(by_state_df, file.path(out_dir, "by_state_att.csv"))

cat("\n=== PER-STATE ATT SUMMARY ===\n")
print(by_state_df %>%
        select(cohort_label, att, se, ci_low_95, ci_high_95, pct_effect,
               n_treated_counties) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- per-state event study --------------------------

cat("\n=== PER-STATE EVENT STUDY (did2s) ===\n")
per_state_es <- list()
for (i in seq_len(nrow(treated_states))) {
  s <- treated_states$state_abb[i]
  d <- treated_states$treat_start[i]
  label <- sprintf("%s (%s)", s, format(d, "%Y-%m"))
  cat(sprintf("  fitting event study %s ... ", label))

  sub <- panel %>% filter(state_abb == s | is.na(g))

  es_fit <- tryCatch({
    did2s::event_study(
      data = sub,
      yname = "y",
      idname = "id",
      gname = "first_treat",
      tname = "t",
      estimator = "did2s"
    )
  }, error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })

  if (is.null(es_fit)) next

  es_df <- as_tibble(es_fit) %>%
    rename_with(~ tolower(.x)) %>%
    rename(event_time = any_of(c("term", "rel_year", "event_time")),
           estimate = any_of(c("estimate", "att")),
           se = any_of(c("std.error", "se"))) %>%
    mutate(cohort_label = label,
           state_abb = s,
           event_time = as.numeric(event_time))

  per_state_es[[label]] <- es_df
  cat(sprintf("ok (%d event-times)\n", nrow(es_df)))
}

by_state_es <- bind_rows(per_state_es)
write_csv(by_state_es, file.path(out_dir, "by_state_eventstudy.csv"))

# Plot per-state event studies.
es_plot_df <- by_state_es %>%
  filter(event_time >= -12, event_time <= 12) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p_es <- ggplot(es_plot_df, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.5) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 1.2) +
  facet_wrap(~ cohort_label, ncol = 4, scales = "free_y") +
  scale_x_continuous(breaks = seq(-12, 12, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 9, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain"))

ggsave(file.path(out_dir, "by_state_eventstudy.png"), p_es,
       width = 10, height = 7, dpi = 300, bg = "transparent")

# Per-state pre-period summary.
state_pre_summary <- by_state_es %>%
  filter(event_time >= -12, event_time <= -2) %>%
  group_by(cohort_label, state_abb) %>%
  summarise(n_pre_coefs = n(),
            n_sig = sum(abs(estimate) > 1.96 * se, na.rm = TRUE),
            mean_abs_pre = mean(abs(estimate), na.rm = TRUE),
            max_abs_pre = max(abs(estimate), na.rm = TRUE),
            mean_pre = mean(estimate, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(desc(mean_abs_pre))
write_csv(state_pre_summary,
          file.path(out_dir, "by_state_pre_summary.csv"))

cat("\n=== PER-STATE PRE-PERIOD SUMMARY (did2s, event_time -12 to -2) ===\n")
print(state_pre_summary %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- era split --------------------------------------

covid_start_yidx <- ym_index(COVID_START)
pre_covid_states <- treated_states %>%
  filter(g < covid_start_yidx) %>% pull(state_abb)

cat("\n=== ERA-SPLIT ATT (did2s) ===\n")
cat("Pre-COVID-treated states:", paste(pre_covid_states, collapse = ", "), "\n")
cat("(Post-COVID-treated cohorts have treatment dates inside COVID drop —",
    "non-identifiable with current spec)\n\n")

run_aggregate <- function(panel_in, label) {
  cat(sprintf("  %s (n_obs=%d, n_treated_states=%d) ... ",
              label, nrow(panel_in),
              n_distinct(panel_in$state_abb[!is.na(panel_in$g)])))

  fit <- tryCatch({
    did2s::did2s(
      data = panel_in,
      yname = "y",
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
  cat(sprintf("ATT=%.4f, SE=%.4f\n", att, se))

  tibble(spec = label,
         n_obs = nrow(panel_in),
         n_treated_states = n_distinct(panel_in$state_abb[!is.na(panel_in$g)]),
         att = att, se = se,
         ci_low_95 = att - 1.96 * se,
         ci_high_95 = att + 1.96 * se,
         pct_effect = (exp(att) - 1) * 100)
}

era_pre  <- run_aggregate(panel %>% filter(is.na(g) | state_abb %in% pre_covid_states),
                          "pre_covid_cohorts_only")
era_all  <- run_aggregate(panel, "all_cohorts")

era_df <- bind_rows(era_pre, era_all)
write_csv(era_df, file.path(out_dir, "era_split_att.csv"))

cat("\n=== ERA-SPLIT ATT COMPARISON ===\n")
print(era_df %>% mutate(across(where(is.numeric), ~ signif(.x, 4))))

# Era-split event study.
cat("\nFitting era-split event studies...\n")
run_es <- function(panel_in, label) {
  fit <- tryCatch({
    did2s::event_study(
      data = panel_in,
      yname = "y", idname = "id", gname = "first_treat", tname = "t",
      estimator = "did2s"
    )
  }, error = function(e) { cat("  failed:", label, conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)
  as_tibble(fit) %>%
    rename_with(~ tolower(.x)) %>%
    rename(event_time = any_of(c("term", "rel_year", "event_time")),
           estimate = any_of(c("estimate", "att")),
           se = any_of(c("std.error", "se"))) %>%
    mutate(spec = label, event_time = as.numeric(event_time))
}

es_pre <- run_es(panel %>% filter(is.na(g) | state_abb %in% pre_covid_states),
                 "pre_covid_cohorts_only")
es_all <- run_es(panel, "all_cohorts")
era_es <- bind_rows(es_pre, es_all)
write_csv(era_es, file.path(out_dir, "era_split_eventstudy.csv"))

# Era-split event study plot.
era_es_plot <- era_es %>%
  filter(event_time >= -12, event_time <= 12) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p_era <- ggplot(era_es_plot, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.5) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.5) +
  facet_wrap(~ spec, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(-12, 12, 3)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain"))

ggsave(file.path(out_dir, "era_split_eventstudy.png"), p_era,
       width = 7.5, height = 5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
