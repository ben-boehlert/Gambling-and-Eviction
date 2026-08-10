#!/usr/bin/env Rscript
################################################################################
# pretrends_all_county.R
#
# Pre-trends event study on the ALL-COUNTY panel (Sim D), using:
#   1. Sun-Abraham TWFE event study (fixest::sunab)
#   2. did2s event study (Gardner) — the new recommended headline estimator
#
# Mirrors pretrends_border_county.R but on all ~1,350 ETS counties (states with
# <5 counties dropped to match the multi-estimator calibration sample).
#
# Outputs:
#   output/border_diagnostic/pretrends_all_county_sunab.{csv,png}
#   output/border_diagnostic/pretrends_all_county_did2s.{csv,png}
#   output/border_diagnostic/pretrends_all_county_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(fixest)
  library(ggplot2)
})

set.seed(20260521L)

HAS_DID2S <- requireNamespace("did2s", quietly = TRUE)
if (HAS_DID2S) library(did2s)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")
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

# Drop states with <MIN_COUNTIES counties (same as calibration script).
counties_per_state <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  filter(!(state_abb %in% drop_states)) %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(
    y = log1p(pmax(filings_count, 0)),
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                NA_integer_),
    g_sunab = if_else(is.na(g), 10000L, as.integer(g)),
    first_treat = if_else(is.na(g), NA_integer_, g),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb)
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  arrange(unit_id, t)

cat("All-county pretrends panel:\n")
cat("  Obs:    ", nrow(panel), "\n")
cat("  Units:  ", n_distinct(panel$unit_id), "counties\n")
cat("  States: ", n_distinct(panel$state_abb), "\n")
cat("  Months: ", n_distinct(panel$t), "\n\n")

# ----------------------------- Sun-Abraham event study ------------------------

cat("Running Sun-Abraham event study...\n")
sa_fit <- fixest::feols(
  y ~ sunab(cohort = g_sunab, period = t, ref.p = -1) | unit_id + t,
  data = panel,
  cluster = ~state_abb
)

sa_tab <- as_tibble(fixest::coeftable(sa_fit), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`,
         t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
  mutate(
    event_time = suppressWarnings(as.integer(sub("^t::", "", term))),
    panel_label = "all_county_sunab"
  ) %>%
  filter(!is.na(event_time))

write_csv(sa_tab %>% select(panel_label, event_time, estimate, se,
                            t_stat, p_value),
          file.path(out_dir, "pretrends_all_county_sunab.csv"))

pre_terms_sa <- sa_tab %>% filter(event_time < -1) %>% pull(term)
n_pre_sa <- length(pre_terms_sa)
cat("  SunAb pre-period coefs:", n_pre_sa, "\n")
cat("  Range of event times:",
    min(sa_tab$event_time), "to", max(sa_tab$event_time), "\n")

# Wald F on pre-period coefs.
wald_pre_sa <- if (n_pre_sa >= 1) {
  pat <- paste0("^(", paste(gsub("([.+*?^$()|\\[\\]\\\\])", "\\\\\\1",
                                  pre_terms_sa), collapse = "|"), ")$")
  tryCatch(fixest::wald(sa_fit, keep = pat, print = FALSE),
           error = function(e) NULL)
} else NULL

get_wald_field <- function(w, field) {
  if (is.null(w)) return(NA_real_)
  if (is.list(w) && field %in% names(w)) return(as.numeric(w[[field]]))
  if (is.numeric(w) && field %in% names(w)) return(as.numeric(w[field]))
  NA_real_
}

# ----------------------------- did2s event study ------------------------------

did2s_tab <- NULL
if (HAS_DID2S) {
  cat("Running did2s event study...\n")
  panel_d2s <- panel %>%
    mutate(
      rel_year = if_else(is.na(first_treat),
                         NA_integer_, as.integer(t - first_treat))
    )
  # Restrict to a reasonable event-time window for did2s — the package
  # accepts only event-times with sufficient mass to identify.
  rel_counts <- panel_d2s %>%
    filter(!is.na(rel_year)) %>%
    count(rel_year, name = "n_obs")
  keep_rel <- rel_counts %>% filter(n_obs >= 30) %>% pull(rel_year)
  cat("  Event-times retained:", min(keep_rel), "to", max(keep_rel), "\n")

  panel_d2s2 <- panel_d2s %>%
    filter(is.na(rel_year) | rel_year %in% keep_rel)

  did2s_fit <- tryCatch({
    did2s::event_study(
      data = panel_d2s2,
      yname = "y",
      idname = "unit_id",
      gname = "first_treat",
      tname = "t",
      estimator = "did2s",
      cluster_var = "state_abb"
    )
  }, error = function(e) {
    cat("  did2s::event_study failed:", conditionMessage(e), "\n")
    NULL
  })

  if (!is.null(did2s_fit)) {
    did2s_tab <- as_tibble(did2s_fit) %>%
      rename_with(~ tolower(.x)) %>%
      mutate(panel_label = "all_county_did2s") %>%
      select(panel_label, event_time = any_of(c("rel_year", "term", "event_time")),
             estimate, std.error, dplyr::everything())
    write_csv(did2s_tab,
              file.path(out_dir, "pretrends_all_county_did2s.csv"))
  }
}

# ----------------------------- summary ----------------------------------------

# Near-treatment pre-period summary (event_time in [-12, -2]).
near_pre_sa <- sa_tab %>%
  filter(event_time >= -12, event_time <= -2) %>%
  mutate(sig = abs(estimate) > 1.96 * se)
near_pre_summary_sa <- tibble(
  estimator = "sun_abraham",
  n_pre_coefs_total = n_pre_sa,
  n_pre_coefs_near = nrow(near_pre_sa),
  n_pre_sig_near = sum(near_pre_sa$sig),
  max_abs_pre_near = max(abs(near_pre_sa$estimate), na.rm = TRUE),
  mean_abs_pre_near = mean(abs(near_pre_sa$estimate), na.rm = TRUE),
  wald_stat = get_wald_field(wald_pre_sa, "stat"),
  wald_p    = get_wald_field(wald_pre_sa, "p")
)

cat("\n=== ALL-COUNTY SunAb PRETRENDS ===\n")
print(near_pre_summary_sa)

cat("\nNear-treatment SunAb pre-period coefficients (event_time -12 to -2):\n")
print(near_pre_sa %>%
        select(event_time, estimate, se, p_value, sig) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

write_csv(near_pre_summary_sa,
          file.path(out_dir, "pretrends_all_county_summary.csv"))

# ----------------------------- plot -------------------------------------------

es_plot <- sa_tab %>%
  filter(!is.na(event_time), event_time >= -36, event_time <= 36) %>%
  mutate(ci_low  = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se)

p <- ggplot(es_plot, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.7) +
  scale_x_continuous(breaks = seq(-36, 36, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA)
  )

ggsave(file.path(out_dir, "pretrends_all_county_sunab.png"), p,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
