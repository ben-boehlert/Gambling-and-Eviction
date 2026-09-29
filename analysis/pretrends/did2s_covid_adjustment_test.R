#!/usr/bin/env Rscript
################################################################################
# did2s_covid_adjustment_test.R
#
# Empirical test: does did2s give the same answer if we keep COVID and adjust
# for it via state-specific COVID-period interactions, vs. dropping COVID?
#
# Specs:
#   1. Drop full COVID (current default, 2020-03 to 2022-03)
#   2. Keep COVID, no adjustment
#   3. Keep COVID, state x COVID-period dummy in first stage
#   4. Keep COVID, state x moratorium-period dummy (CDC fed moratorium 2020-09 to 2021-08)
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(did2s)
})

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "data/output/did2s_covid_adjustment"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

build_panel <- function(min_date = "2018-01-01", max_date = "2024-12-31",
                         drop_covid = FALSE) {
  raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types=FALSE) |>
    transmute(state_abb = as.character(state_abb),
              month_date = as.Date(month_date),
              filings_count = as.numeric(filings_count)) |>
    filter(month_date >= as.Date(min_date), month_date <= as.Date(max_date),
           state_abb != "ME") |>
    anti_join(bad_obs, by = c("state_abb","month_date"))

  if (drop_covid) {
    raw <- raw |> filter(!(month_date >= as.Date("2020-03-01") &
                           month_date <= as.Date("2022-03-31")))
  }

  cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
  keep <- cov |> filter(n == max(n)) |> pull(state_abb)
  raw <- raw |> filter(state_abb %in% keep) |> drop_pre_paspa_states("did2s_covid_adjustment_test")
  n_pre <- n_distinct(raw$state_abb)
  common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
  raw <- raw |> filter(month_date %in% common)

  treat <- load_eviction_treatment_schedule(
    treat_file="data/raw/sports_gambling_legalization_dates.csv",
    treat_date_col="online_start_date", states=raw$state_abb)

  panel <- raw |> left_join(treat, by="state_abb") |>
    mutate(y = log1p(pmax(filings_count, 0)),
           t = ym_index(month_date),
           g_raw = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
           g_raw = as.integer(g_raw),
           id = as.integer(as.factor(state_abb)),
           # COVID period flags
           covid_period = (month_date >= as.Date("2020-03-01") &
                           month_date <= as.Date("2022-03-31")),
           moratorium_period = (month_date >= as.Date("2020-09-01") &
                                month_date <= as.Date("2021-08-31")))

  t_values <- sort(unique(panel$t))
  snap_g <- function(g) {
    if (g == 0L) return(0L)
    c <- t_values[t_values >= g]
    if (!length(c)) return(0L)
    as.integer(min(c))
  }
  state_g <- panel |> distinct(state_abb, g_raw) |>
    mutate(g = vapply(g_raw, snap_g, integer(1)))
  panel <- panel |> select(-g_raw) |> left_join(state_g, by="state_abb") |>
    mutate(post_treat = as.integer(g > 0 & t >= g),
           treated = as.integer(g > 0))

  panel
}

run_did2s <- function(panel, first_stage_formula, label) {
  n_states <- n_distinct(panel$state_abb)
  n_treated <- n_distinct(panel$state_abb[panel$g > 0])
  cat(glue("\n[{label}] {n_states} states ({n_treated} treated), {n_distinct(panel$t)} months, {nrow(panel)} obs"), "\n")

  fit <- tryCatch({
    suppressMessages(suppressWarnings({
      did2s(data = as.data.frame(panel), yname = "y",
            first_stage = first_stage_formula,
            second_stage = ~ post_treat,
            treatment = "post_treat",
            cluster_var = "id")
    }))
  }, error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })

  if (is.null(fit)) return(tibble(spec=label, att=NA, se=NA, p=NA,
                                    n_states=n_states, n_treated=n_treated))

  att <- as.numeric(coef(fit)[1])
  se  <- sqrt(diag(stats::vcov(fit)))[1]
  p   <- 2 * stats::pt(-abs(att/se), df = n_states - 1L)
  cat(glue("  ATT = {sprintf('%+.4f', att)}, SE = {sprintf('%.4f', se)}, p = {sprintf('%.3f', p)}"), "\n")
  cat(glue("  95% CI: [{sprintf('%+.3f', att - 1.96*se)}, {sprintf('%+.3f', att + 1.96*se)}]"), "\n")
  tibble(spec=label, att=att, se=se, p=p,
         ci_lo = att - 1.96*se, ci_hi = att + 1.96*se,
         n_states=n_states, n_treated=n_treated, n_obs=nrow(panel))
}

cat("=== COVID ADJUSTMENT TEST: did2s ===\n")

panel_drop_covid <- build_panel(drop_covid = TRUE)
panel_keep_covid <- build_panel(drop_covid = FALSE)

results <- bind_rows(
  run_did2s(panel_drop_covid, ~ 0 | id + t,
            "(1) Drop COVID"),
  run_did2s(panel_keep_covid, ~ 0 | id + t,
            "(2) Keep COVID, no adjustment"),
  run_did2s(panel_keep_covid, ~ 0 | id + t + id^covid_period,
            "(3) Keep COVID + state x covid_period FE"),
  run_did2s(panel_keep_covid, ~ 0 | id + t + id^moratorium_period,
            "(4) Keep COVID + state x moratorium FE")
)

write_csv(results, file.path(OUT_DIR, "covid_adjustment_results.csv"))

cat("\n=== SUMMARY ===\n")
print(as.data.frame(results), digits = 3)
