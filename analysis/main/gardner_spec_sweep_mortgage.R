#!/usr/bin/env Rscript
################################################################################
# gardner_spec_sweep_mortgage.R
#
# Run Gardner (did2s) across a grid of specifications on the mortgage
# delinquency panel. Axes:
#   - Treatment definition: online_start_date, retail_start_date, first_start_date
#   - COVID window: default drop, no drop, CARES-only drop, long drop, short drop
#   - Outcome: delinq_pct (percentage points), log_delinq_pct
#   - Sample: full 51-state, drop ME
#
# Output: one row per spec with ATT, SE, t, p, CI, N, and sample characteristics.
################################################################################

Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(did2s)
  library(fixest)
  library(glue)
})

state_name_to_abb <- function(s){s <- trimws(as.character(s)); m <- setNames(state.abb, state.name); m <- c(m, "District of Columbia"="DC"); unname(m[s])}
ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m")))

OUT_DIR <- "output/gardner_spec_sweep_mortgage"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# --- load raw data once ---

mort_wide <- read_csv("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv",
                      show_col_types = FALSE) %>% filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", colnames(mort_wide), value = TRUE)

mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(all_of(month_cols), names_to = "month_str", values_to = "delinq_pct") %>%
  mutate(state_abb = state_name_to_abb(Name),
         month_date = as.Date(paste0(month_str, "-01")),
         delinq_pct = as.numeric(delinq_pct)) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, delinq_pct)

treat_raw <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                      show_col_types = FALSE)

# --- build_panel: apply per-spec filters and return ready-to-fit panel ---

build_panel <- function(treat_col, drop_start, drop_end, outcome,
                        min_date = as.Date("2016-01-01"),
                        max_date = as.Date("2024-12-31"),
                        exclude_states = character(0)) {
  treat_sched <- treat_raw %>%
    transmute(state_abb = state_name_to_abb(state),
              treat_start = as.Date(.data[[treat_col]])) %>%
    filter(!is.na(state_abb)) %>%
    group_by(state_abb) %>%
    summarise(treat_start = if (all(is.na(treat_start))) as.Date(NA)
                            else min(treat_start, na.rm = TRUE),
              .groups = "drop")

  p <- mort_long %>%
    filter(month_date >= min_date, month_date <= max_date,
           !(state_abb %in% exclude_states))

  if (!is.na(drop_start) && !is.na(drop_end)) {
    p <- p %>% filter(!(month_date >= drop_start & month_date <= drop_end))
  }

  cov <- p %>% count(state_abb, name = "n_months")
  keep <- cov %>% filter(n_months >= max(n_months)) %>% pull(state_abb)
  p <- p %>% filter(state_abb %in% keep)
  n_pre <- n_distinct(p$state_abb)
  common <- p %>% count(month_date, name = "n") %>%
    filter(n == n_pre) %>% pull(month_date)
  p <- p %>% filter(month_date %in% common)

  p <- p %>%
    left_join(treat_sched, by = "state_abb") %>%
    mutate(y_raw = delinq_pct,
           y     = if (outcome == "log_delinq_pct") log(pmax(delinq_pct, 0.001))
                   else delinq_pct,
           t     = ym_index(month_date),
           g     = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
           id    = as.integer(as.factor(state_abb)),
           post_treat = as.integer(g > 0L & t >= g),
           first_treat = ifelse(g == 0L, NA_integer_, g))
  p
}

# --- fit_did2s: run Gardner, extract ATT / SE / CI ---

fit_did2s <- function(panel_df) {
  dat <- as.data.frame(panel_df)
  res <- tryCatch({
    fit <- did2s(data = dat, yname = "y",
                 first_stage = ~ 0 | id + t,
                 second_stage = ~ post_treat,
                 treatment = "post_treat",
                 cluster_var = "id")
    att <- as.numeric(coef(fit)[1])
    vc  <- tryCatch(stats::vcov(fit), error = function(e) NULL)
    se  <- if (!is.null(vc)) sqrt(diag(vc))[1] else NA_real_
    n_states <- n_distinct(dat$id)
    df_c <- n_states - 1
    tstat <- att / se
    pval <- 2 * pt(-abs(tstat), df = df_c)
    list(att = att, se = se, t = tstat, p = pval,
         ci_lo = att - qt(0.975, df = df_c) * se,
         ci_hi = att + qt(0.975, df = df_c) * se,
         n_obs = nrow(dat), n_states = n_states,
         n_treated = n_distinct(dat$state_abb[dat$g > 0L]),
         n_cohorts = n_distinct(dat$g[dat$g > 0L]),
         n_months  = n_distinct(dat$t),
         mean_y_pre = mean(dat$y_raw[dat$post_treat == 0L], na.rm = TRUE))
  }, error = function(e) {
    list(att = NA, se = NA, t = NA, p = NA, ci_lo = NA, ci_hi = NA,
         n_obs = NA, n_states = NA, n_treated = NA, n_cohorts = NA,
         n_months = NA, mean_y_pre = NA, err = conditionMessage(e))
  })
  res
}

# --- spec grid ---

specs <- tribble(
  ~label,                ~treat_col,           ~drop_start,                ~drop_end,                  ~outcome,         ~exclude,
  "1. Main (online, default COVID drop)",      "online_start_date", as.Date("2020-03-01"), as.Date("2021-07-31"), "delinq_pct",     character(0),
  "2. Retail-start treatment",                  "retail_start_date",as.Date("2020-03-01"), as.Date("2021-07-31"), "delinq_pct",     character(0),
  "3. First-start (online or retail, earliest)","first_start_date", as.Date("2020-03-01"), as.Date("2021-07-31"), "delinq_pct",     character(0),
  "4. No COVID drop",                           "online_start_date",as.Date(NA),            as.Date(NA),            "delinq_pct",     character(0),
  "5. Short drop (lockdown only, 2020-03 to 2020-12)", "online_start_date",as.Date("2020-03-01"), as.Date("2020-12-31"), "delinq_pct", character(0),
  "6. Long drop (through CARES forbearance end, 2020-03 to 2021-09)","online_start_date",as.Date("2020-03-01"), as.Date("2021-09-30"), "delinq_pct", character(0),
  "7. Very long drop (2020-03 to 2022-03)",     "online_start_date",as.Date("2020-03-01"), as.Date("2022-03-31"), "delinq_pct",     character(0),
  "8. Log outcome",                             "online_start_date",as.Date("2020-03-01"), as.Date("2021-07-31"), "log_delinq_pct", character(0),
  "9. Drop ME",                                 "online_start_date",as.Date("2020-03-01"), as.Date("2021-07-31"), "delinq_pct",     c("ME")
)

# --- run ---

cat("=== Gardner (did2s) Spec Sweep — Mortgage Delinquency ===\n\n")
results <- vector("list", nrow(specs))
for (i in seq_len(nrow(specs))) {
  s <- specs[i, ]
  cat(glue("[{i}/{nrow(specs)}] {s$label}"), "\n")
  p <- build_panel(treat_col = s$treat_col,
                   drop_start = s$drop_start,
                   drop_end = s$drop_end,
                   outcome = s$outcome,
                   exclude_states = s$exclude[[1]])
  r <- fit_did2s(p)
  cat(glue("   N_states={r$n_states}, N_treated={r$n_treated}, N_cohorts={r$n_cohorts}, N_months={r$n_months}, N_obs={r$n_obs}"), "\n")
  if (!is.na(r$att)) {
    cat(glue("   ATT={round(r$att, 4)}, SE={round(r$se, 4)}, t={round(r$t, 2)}, p={round(r$p, 3)}, CI=[{round(r$ci_lo, 4)}, {round(r$ci_hi, 4)}]"), "\n")
    if (s$outcome == "delinq_pct") {
      pct_of_mean <- 100 * r$att / r$mean_y_pre
      cat(glue("   Relative to pre-mean ({round(r$mean_y_pre, 3)} pp): {round(pct_of_mean, 1)}%"), "\n")
    }
  } else {
    cat(glue("   ERROR: {r$err}"), "\n")
  }
  cat("\n")
  results[[i]] <- tibble(spec = s$label,
                         treatment = s$treat_col,
                         covid_drop = ifelse(is.na(s$drop_start), "none",
                                             paste(s$drop_start, s$drop_end, sep = " to ")),
                         outcome = s$outcome,
                         exclude = ifelse(length(s$exclude[[1]]) == 0, "",
                                          paste(s$exclude[[1]], collapse = ",")),
                         att = r$att, se = r$se, t_stat = r$t, p_value = r$p,
                         ci_lo = r$ci_lo, ci_hi = r$ci_hi,
                         mean_y_pre = r$mean_y_pre,
                         pct_of_mean = if (s$outcome == "delinq_pct") 100 * r$att / r$mean_y_pre else NA_real_,
                         n_states = r$n_states, n_treated = r$n_treated,
                         n_cohorts = r$n_cohorts, n_months = r$n_months,
                         n_obs = r$n_obs)
}

out <- bind_rows(results)
write_csv(out, file.path(OUT_DIR, "gardner_spec_sweep.csv"))

# --- summary table ---

cat("\n\n=== SUMMARY TABLE ===\n")
tbl <- out %>%
  mutate(att_fmt = sprintf("%+.4f", att),
         se_fmt  = sprintf("(%.4f)", se),
         ci_fmt  = sprintf("[%+.3f, %+.3f]", ci_lo, ci_hi),
         pct_fmt = ifelse(is.na(pct_of_mean), "", sprintf("%+.1f%%", pct_of_mean)),
         sig = ifelse(is.na(p_value), "",
                      ifelse(p_value < 0.01, "***",
                             ifelse(p_value < 0.05, "**",
                                    ifelse(p_value < 0.10, "*", ""))))) %>%
  select(spec, att_fmt, se_fmt, pct_fmt, ci_fmt, sig, n_states, n_treated, n_obs)
print(tbl, n = Inf, width = Inf)

cat(glue("\nResults saved to {OUT_DIR}/gardner_spec_sweep.csv"), "\n")
