#!/usr/bin/env Rscript
################################################################################
# drop_nh_eventstudy.R
#
# What the headline did2s spec looks like WITHOUT New Hampshire.
# Produces aggregate event studies for:
#   1. did2s, all 13 non-NH cohorts (full sample)
#   2. did2s, pre-COVID-treated non-NH cohorts only (5 states: WV, PA, NY, AR, IN)
# Plus TWFE-pooled with i() event-time dummies on both samples for visual
# comparison.
#
# Outputs:
#   output/border_diagnostic/drop_nh_eventstudy/{
#     event_studies.csv,
#     event_studies.png,
#     summary_table.csv
#   }
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(tibble)
  library(fixest); library(did2s); library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "drop_nh_eventstudy")
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

COVID_START   <- as.Date("2020-03-01")
COVID_END     <- as.Date("2022-03-31")
MIN_COUNTIES  <- 5L
PRE_COVID_END <- ym_index(COVID_START)
DROP_STATE    <- c("NH")

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

panel_full <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states)) %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         first_treat = if_else(is.na(g), 0L, as.integer(g)),
         post_treat = as.integer(!is.na(g) & t >= g),
         unit_id = as.integer(fips),
         state_abb = as.character(state_abb)) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t))

# Drop NH for the relevant specs.
panel_no_nh <- panel_full %>% filter(!state_abb %in% DROP_STATE)
panel_no_nh_precovid <- panel_no_nh %>%
  filter(is.na(g) | g < PRE_COVID_END)

cat("Sample sizes:\n")
cat("  Full (with NH):", nrow(panel_full),
    "obs across", n_distinct(panel_full$unit_id), "counties,",
    n_distinct(panel_full$state_abb[!is.na(panel_full$g)]), "treated states\n")
cat("  Drop NH:", nrow(panel_no_nh),
    "obs,", n_distinct(panel_no_nh$state_abb[!is.na(panel_no_nh$g)]),
    "treated states\n")
cat("  Drop NH + pre-COVID:", nrow(panel_no_nh_precovid),
    "obs,",
    n_distinct(panel_no_nh_precovid$state_abb[!is.na(panel_no_nh_precovid$g)]),
    "treated states\n\n")

# ----------------------------- TWFE i() event study ---------------------------

PRE_W  <- -12L:-2L
POST_W <- 0L:12L

run_twfe_es <- function(panel_in, label) {
  cat(sprintf("  TWFE i() event study: %s ... ", label))
  d <- panel_in %>%
    mutate(rel_time = if_else(is.na(g), NA_integer_, as.integer(t - g)),
           rel_time_bin = case_when(
             is.na(rel_time)               ~ NA_integer_,
             rel_time < min(PRE_W)         ~ min(PRE_W) - 1L,
             rel_time > max(POST_W)        ~ max(POST_W) + 1L,
             TRUE                          ~ rel_time
           ))
  fit <- tryCatch(
    fixest::feols(y ~ i(rel_time_bin, ref = -1) | unit_id + t, data = d,
                  cluster = ~state_abb, warn = FALSE, notes = FALSE),
    error = function(e) { cat("failed\n"); NULL })
  if (is.null(fit)) return(NULL)
  ct <- as_tibble(fixest::coeftable(fit), rownames = "term") %>%
    rename(estimate = Estimate, se = `Std. Error`,
           t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
    mutate(event_time = suppressWarnings(
      as.integer(sub("^rel_time_bin::", "", term))),
      spec = label,
      estimator = "TWFE_i") %>%
    filter(!is.na(event_time))
  cat("ok\n")
  ct
}

# ----------------------------- did2s event study ------------------------------

run_did2s_es <- function(panel_in, label) {
  cat(sprintf("  did2s event study: %s ... ", label))
  fit <- tryCatch(
    did2s::event_study(
      data = panel_in, yname = "y",
      idname = "unit_id", gname = "first_treat", tname = "t",
      estimator = "did2s"
    ),
    error = function(e) { cat("failed:", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)
  df <- as_tibble(fit) %>%
    rename_with(~ tolower(.x)) %>%
    rename(event_time = any_of(c("term", "rel_year", "event_time")),
           estimate = any_of(c("estimate", "att")),
           se = any_of(c("std.error", "se"))) %>%
    mutate(event_time = as.numeric(event_time),
           spec = label, estimator = "did2s")
  cat(sprintf("ok (%d event-times)\n", nrow(df)))
  df
}

# ----------------------------- run all ----------------------------------------

cat("=== TWFE event studies ===\n")
twfe_full   <- run_twfe_es(panel_full,            "full (with NH)")
twfe_no_nh  <- run_twfe_es(panel_no_nh,           "drop NH, all cohorts")
twfe_no_nh_pc <- run_twfe_es(panel_no_nh_precovid, "drop NH, pre-COVID only")

cat("\n=== did2s event studies ===\n")
did2s_full   <- run_did2s_es(panel_full,            "full (with NH)")
did2s_no_nh  <- run_did2s_es(panel_no_nh,           "drop NH, all cohorts")
did2s_no_nh_pc <- run_did2s_es(panel_no_nh_precovid, "drop NH, pre-COVID only")

safe_select <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  df %>% select(spec, estimator, event_time, estimate, se)
}
all_es <- bind_rows(
  safe_select(twfe_full),
  safe_select(twfe_no_nh),
  safe_select(twfe_no_nh_pc),
  safe_select(did2s_full),
  safe_select(did2s_no_nh),
  safe_select(did2s_no_nh_pc)
)
write_csv(all_es, file.path(out_dir, "event_studies.csv"))

# ----------------------------- summary ----------------------------------------

pre_summary <- all_es %>%
  filter(event_time >= -12, event_time <= -2) %>%
  group_by(spec, estimator) %>%
  summarise(
    n_pre_coefs = n(),
    n_sig = sum(abs(estimate) > 1.96 * se, na.rm = TRUE),
    mean_abs_pre = mean(abs(estimate), na.rm = TRUE),
    max_abs_pre  = max(abs(estimate), na.rm = TRUE),
    mean_pre = mean(estimate, na.rm = TRUE),
    .groups = "drop"
  )

post_summary <- all_es %>%
  filter(event_time >= 0, event_time <= 12) %>%
  group_by(spec, estimator) %>%
  summarise(
    n_post_coefs = n(),
    n_sig_pos = sum(estimate > 1.96 * se, na.rm = TRUE),
    n_sig_neg = sum(estimate < -1.96 * se, na.rm = TRUE),
    mean_post = mean(estimate, na.rm = TRUE),
    max_post = max(estimate, na.rm = TRUE),
    .groups = "drop"
  )

summary_tbl <- pre_summary %>%
  left_join(post_summary, by = c("spec", "estimator"))
write_csv(summary_tbl, file.path(out_dir, "summary_table.csv"))

cat("\n=== PRE-PERIOD SUMMARY (event_time -12 to -2) ===\n")
print(summary_tbl %>%
        select(spec, estimator, n_sig, mean_abs_pre, max_abs_pre, mean_pre,
               mean_post) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))))

# ----------------------------- plot -------------------------------------------

plot_df <- all_es %>%
  filter(event_time >= -12, event_time <= 12) %>%
  mutate(ci_low = estimate - 1.96 * se,
         ci_high = estimate + 1.96 * se,
         spec = factor(spec,
                       levels = c("full (with NH)",
                                  "drop NH, all cohorts",
                                  "drop NH, pre-COVID only")))

p <- ggplot(plot_df, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.5) +
  geom_point(color = "grey20", size = 1.5) +
  facet_grid(estimator ~ spec, scales = "free_y") +
  scale_x_continuous(breaks = seq(-12, 12, 3)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 10, base_family = "serif") +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA),
        strip.text = element_text(face = "plain", size = rel(0.9)))

ggsave(file.path(out_dir, "event_studies.png"), p,
       width = 10, height = 6, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
