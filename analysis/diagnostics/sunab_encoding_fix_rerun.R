#!/usr/bin/env Rscript
################################################################################
# sunab_encoding_fix_rerun.R
#
# PURPOSE: The Sun-Abraham arm of cs_calibration_multi_estimator_county.R coded
#          never-treated counties as first_treat = NA. fixest::sunab() does NOT
#          special-case NA cohorts — feols drops every NA row, so the SA
#          regression ran with zero never-treated controls (the note was
#          suppressed by notes = FALSE). Verified on a synthetic known-truth
#          panel: NA encoding drops all never-treated obs and badly biases the
#          ATT; cohort = 0 / Inf / 10000 all agree with the truth.
#
# This script re-runs ONLY the Sun-Abraham arm of the saved 50-sim county
# calibration (output/border_diagnostic/cs_calibration_multi_county/), using
# the exact seeds stored in sim_results.csv, under both encodings:
#   - sunab_na:    first_treat NA for never-treated  (reproduces the bug)
#   - sunab_fixed: cohort g = 0 for never-treated    (correct; matches the
#                  pretrends template and R/power/run_estimators.R .re_sunab)
# TWFE is recomputed per seed as an end-to-end replication check against the
# stored twfe_att values.
#
# Panel construction below is copied VERBATIM from
# analysis/diagnostics/cs_calibration_multi_estimator_county.R so the residual
# pool and row order (hence the per-seed error draws) match the original run.
#
# USAGE:
#   N_WORKERS=6 Rscript analysis/diagnostics/sunab_encoding_fix_rerun.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(tibble)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x
}
getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

# Default 3: 6 PSOCK workers each fitting saturated sunab design matrices on
# the 91k-row county panel OOM'd (worker killed -> "error reading from
# connection" in parLapply) on the 2026-08-28 first launch.
N_WORKERS <- suppressWarnings(as.integer(getenv1("N_WORKERS", "3")))
ALPHA     <- 0.05

P_COUNTY_RAW <- "data/raw/monthly_county_data_download.csv"
P_STATE_TR   <- "data/raw/state_month_panel_with_treatment.csv"
IN_DIR       <- "output/border_diagnostic/cs_calibration_multi_county"
OUT_DIR      <- "output/border_diagnostic/cs_calibration_multi_county_sunab_fix"

DROP_START   <- as.Date("2020-03-01")
DROP_END     <- as.Date("2022-03-31")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

orig <- read_csv(file.path(IN_DIR, "sim_results.csv"), show_col_types = FALSE)
seeds <- orig$seed
cat(glue("Re-running SA arm for {length(seeds)} stored seeds"), "\n\n")

# ----- panel build: verbatim from cs_calibration_multi_estimator_county.R -----

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

county_raw <- read_csv(P_COUNTY_RAW, show_col_types = FALSE) %>%
  mutate(
    fips        = as.integer(fips),
    state_fips  = as.integer(floor(fips / 1000)),
    month_date  = as.Date(date),
    filings_count = as.numeric(filings_count)
  ) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date))

state_treat_one <- read_csv(P_STATE_TR, show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

panel_full <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

MIN_COUNTIES <- 5L
counties_per_state <- panel_full %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

panel <- panel_full %>%
  filter(!(state_abb %in% drop_states)) %>%
  mutate(
    y = log1p(pmax(filings_count, 0)),
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    g = as.integer(g),
    id = as.integer(fips),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = (g > 0L) & (t >= g),
    first_treat = if_else(g == 0L, NA_integer_, g),
    rel_time = if_else(g == 0L, NA_integer_, as.integer(t - g))
  ) %>%
  filter(is.finite(y), !is.na(id), !is.na(t))

n_states   <- n_distinct(panel$state_abb)
n_switch_s <- n_distinct(panel$state_abb[panel$g > 0L])
n_never_c  <- n_distinct(panel$id[panel$g == 0L])
cat(glue("Panel: {n_distinct(panel$id)} counties, {n_states} states ",
         "({n_switch_s} treated), {nrow(panel)} obs; ",
         "{n_never_c} never-treated counties ",
         "({sum(panel$g == 0L)} obs = what the NA encoding silently drops)"),
    "\n\n")

base_fe <- panel %>% filter(untreated_obs, is.finite(y))
fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)

panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
if (any(!is.finite(panel$yhat))) {
  n_bad <- sum(!is.finite(panel$yhat))
  cat(glue("  Dropping {n_bad} non-finite yhat rows"), "\n")
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}

base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]

# ----- real-data check: both encodings side by side ---------------------------

dat_real <- as.data.frame(panel)
fit_na <- feols(y ~ sunab(first_treat, t) | id + t, data = dat_real,
                cluster = ~state_abb, warn = FALSE, notes = FALSE)
fit_fx <- feols(y ~ sunab(g, t) | id + t, data = dat_real,
                cluster = ~state_abb, warn = FALSE, notes = FALSE)
agg_na <- summary(fit_na, agg = "att")
agg_fx <- summary(fit_fx, agg = "att")
cat("Real data, SA under both encodings:\n")
cat(glue("  NA encoding (buggy):  nobs={fit_na$nobs} ",
         "ATT={round(coef(agg_na)[1], 4)} SE={round(se(agg_na)[1], 4)}"), "\n")
cat(glue("  g=0 encoding (fixed): nobs={fit_fx$nobs} ",
         "ATT={round(coef(agg_fx)[1], 4)} SE={round(se(agg_fx)[1], 4)}"), "\n\n")

# ----- per-seed re-run --------------------------------------------------------

draw_errors <- function(t_vec, pool_by_t, fallback) {
  e <- numeric(length(t_vec))
  for (tv in unique(t_vec)) {
    idx <- which(t_vec == tv)
    pool <- pool_by_t[[as.character(tv)]]
    if (is.null(pool) || length(pool) < 3) pool <- fallback
    e[idx] <- sample(pool, length(idx), replace = TRUE)
  }
  e
}

one_sim_sa <- function(seed) {
  set.seed(seed)
  e_draw <- draw_errors(panel$t, resid_pool_by_t, global_pool)
  y_sim  <- panel$yhat + e_draw

  dat <- data.frame(
    id          = panel$id,
    t           = panel$t,
    g           = panel$g,
    y           = y_sim,
    post_treat  = as.integer(panel$post_treat),
    first_treat = panel$first_treat,
    state_abb   = panel$state_abb
  )

  out <- list(seed = seed)

  fit <- feols(y ~ post_treat | id + t, data = dat, cluster = ~state_abb,
               warn = FALSE, notes = FALSE)
  out$twfe_att <- as.numeric(coef(fit)[1])

  run_sa <- function(fml) {
    tryCatch(suppressMessages(suppressWarnings({
      fit_sa <- feols(fml, data = dat, cluster = ~state_abb,
                      warn = FALSE, notes = FALSE)
      agg <- summary(fit_sa, agg = "att")
      list(att = as.numeric(coef(agg)[1]), se = as.numeric(se(agg)[1]),
           p = as.numeric(pvalue(agg)[1]), nobs = fit_sa$nobs)
    })), error = function(e) list(att = NA_real_, se = NA_real_,
                                  p = NA_real_, nobs = NA_integer_))
  }
  sa_na <- run_sa(y ~ sunab(first_treat, t) | id + t)
  sa_fx <- run_sa(y ~ sunab(g, t) | id + t)

  out$sunab_na_att <- sa_na$att; out$sunab_na_se <- sa_na$se
  out$sunab_na_p   <- sa_na$p;   out$sunab_na_nobs <- sa_na$nobs
  out$sunab_fx_att <- sa_fx$att; out$sunab_fx_se <- sa_fx$se
  out$sunab_fx_p   <- sa_fx$p;   out$sunab_fx_nobs <- sa_fx$nobs
  out
}

use_parallel <- (N_WORKERS > 1L)
if (use_parallel) {
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages(library(fixest)); NULL
  })
  parallel::clusterExport(
    cl, varlist = c("panel", "resid_pool_by_t", "global_pool",
                    "draw_errors", "one_sim_sa"),
    envir = environment()
  )
}

# Batched with incremental saves: each batch appends to PARTIAL_CSV, and seeds
# already present there are skipped, so a crashed or OOM-killed run resumes
# from where it stopped instead of losing everything.
PARTIAL_CSV <- file.path(OUT_DIR, "sim_results_sunab_fix_partial.csv")
done_seeds <- if (file.exists(PARTIAL_CSV)) {
  read_csv(PARTIAL_CSV, show_col_types = FALSE)$seed
} else integer(0)
todo <- setdiff(seeds, done_seeds)
if (length(done_seeds) > 0) {
  cat(glue("Resuming: {length(done_seeds)} seeds already done, ",
           "{length(todo)} to go"), "\n")
}

t0 <- Sys.time()
batch_size <- max(N_WORKERS, 1L)
n_batches <- ceiling(length(todo) / batch_size)
for (b in seq_len(n_batches)) {
  lo <- (b - 1L) * batch_size + 1L
  hi <- min(b * batch_size, length(todo))
  bs <- todo[lo:hi]
  batch_res <- if (use_parallel) {
    parallel::parLapply(cl, bs, one_sim_sa)
  } else {
    lapply(bs, one_sim_sa)
  }
  batch_df <- bind_rows(lapply(batch_res, as_tibble))
  if (file.exists(PARTIAL_CSV)) {
    write_csv(batch_df, PARTIAL_CSV, append = TRUE)
  } else {
    write_csv(batch_df, PARTIAL_CSV)
  }
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(glue("  [{length(done_seeds) + hi}/{length(seeds)}] ",
           "elapsed={round(elapsed)}s"), "\n")
}
cat(glue("Done in {round(as.numeric(difftime(Sys.time(), t0, units = 'secs')))}s"),
    "\n\n")

df <- read_csv(PARTIAL_CSV, show_col_types = FALSE)
df <- df[match(seeds, df$seed), , drop = FALSE]
df <- df %>%
  left_join(orig %>% select(seed, orig_twfe_att = twfe_att,
                            orig_sunab_att = sunab_att,
                            orig_sunab_p = sunab_p),
            by = "seed")

write_csv(df, file.path(OUT_DIR, "sim_results_sunab_fix.csv"))

# Replication checks against the stored run
twfe_match  <- max(abs(df$twfe_att - df$orig_twfe_att), na.rm = TRUE)
sunab_match <- max(abs(df$sunab_na_att - df$orig_sunab_att), na.rm = TRUE)
cat("Replication checks vs stored sim_results.csv:\n")
cat(glue("  max |twfe_att - stored|          = {signif(twfe_match, 3)}"), "\n")
cat(glue("  max |sunab_NA_att - stored SA|   = {signif(sunab_match, 3)}"), "\n\n")

summ <- function(att, se, p, label) {
  valid <- is.finite(att) & is.finite(se) & se > 0 & is.finite(p)
  tibble(
    arm = label, n_valid = sum(valid),
    rejection = mean(p[valid] < ALPHA),
    mean_att = mean(att[valid]), sd_att = sd(att[valid]),
    mean_se = mean(se[valid]), se_over_sd = mean(se[valid]) / sd(att[valid])
  )
}
out_summary <- bind_rows(
  summ(df$orig_twfe_att, orig$twfe_se, orig$twfe_p, "TWFE (stored)"),
  summ(df$sunab_na_att, df$sunab_na_se, df$sunab_na_p, "SA, NA encoding (bug)"),
  summ(df$sunab_fx_att, df$sunab_fx_se, df$sunab_fx_p, "SA, g=0 encoding (fixed)")
)
out_summary$noise_ratio_vs_twfe <-
  out_summary$sd_att / out_summary$sd_att[out_summary$arm == "TWFE (stored)"]

write_csv(out_summary, file.path(OUT_DIR, "calibration_summary_sunab_fix.csv"))
cat("=== SA calibration, bug vs fix (50 sims, stored seeds) ===\n")
print(as.data.frame(out_summary %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
cat(glue("\nResults saved to: {OUT_DIR}/"), "\n")
