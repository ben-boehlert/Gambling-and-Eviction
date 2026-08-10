#!/usr/bin/env Rscript
################################################################################
# cs_calibration_multi_estimator_county.R
#
# PURPOSE: Port of cs_calibration_multi_estimator.R to the ALL-COUNTY panel
#          (Sim D from the 4-way decomposition). Tests whether the singleton
#          cohort problem that crippled CS-DiD / Sun-Abraham on the state panel
#          improves when each cohort has ~40 counties instead of 1 state.
#
# Comparison target (from CLAUDE.md, state-panel result):
#
#   Estimator       Rejection (null)   SE/SD   Noise vs TWFE
#   TWFE            1%                 1.14    1x
#   Sun-Abraham     21%                0.58    4x
#   CS Analytic     14%                0.67    5.1x
#   didimputation   failed             —       —
#   did2s           failed             —       —
#
# Prediction: Each cohort grows from 1 state to ~40 counties, so within-cohort
# variance should shrink. CS-DiD's over-rejection should drop substantially.
# Whether it reaches nominal 5% is the empirical question.
#
# CRITICAL design choice: All estimators cluster at STATE level, not county.
# Treatment is state-level; AAIW (2023, QJE) and Cameron-Miller (2015) say
# cluster at the treatment assignment level.
#
# USAGE:
#   N_SIMS=50 N_WORKERS=8 Rscript analysis/diagnostics/cs_calibration_multi_estimator_county.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
  library(tibble)
})

set.seed(20260521L)

HAS_DIDIMP <- requireNamespace("didimputation", quietly = TRUE)
HAS_DID2S  <- requireNamespace("did2s", quietly = TRUE)
if (HAS_DIDIMP) library(didimputation)
if (HAS_DID2S)  library(did2s)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x
}

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

# ----------------------------- config -----------------------------------------

N_SIMS    <- parse_int(getenv1("N_SIMS",    "50"), 50L)
N_WORKERS <- parse_int(getenv1("N_WORKERS", "8"),  8L)
SEED      <- 20260521L
ALPHA     <- 0.05

P_COUNTY_RAW <- "data/raw/monthly_county_data_download.csv"
P_STATE_TR   <- "data/raw/state_month_panel_with_treatment.csv"
OUT_DIR      <- "output/border_diagnostic/cs_calibration_multi_county"

DROP_START   <- as.Date("2020-03-01")
DROP_END     <- as.Date("2022-03-31")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== MULTI-ESTIMATOR CALIBRATION TEST — COUNTY PANEL ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}, SEED={SEED}"), "\n")
cat(glue("Estimators: TWFE, SunAb, CS-analytic"), "\n")
if (HAS_DIDIMP) cat("  + didimputation\n")
if (HAS_DID2S)  cat("  + did2s\n")
cat("\n")

# ----------------------------- helpers ----------------------------------------

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

# ----------------------------- build panel ------------------------------------

cat("Building all-county panel (matching Sim D)...\n")

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

# Identify states with too few counties — CS-DiD's per-cohort regressions
# require enough units to be stable. Drop states with < MIN_COUNTIES counties.
MIN_COUNTIES <- 5L
counties_per_state <- panel_full %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)
if (length(drop_states) > 0) {
  cat("Dropping states with <", MIN_COUNTIES, "counties: ",
      paste(drop_states, collapse = ", "), "\n", sep = "")
}

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

n_units    <- n_distinct(panel$id)
n_states   <- n_distinct(panel$state_abb)
n_switch_s <- n_distinct(panel$state_abb[panel$g > 0L])
n_never_s  <- n_states - n_switch_s
n_months   <- n_distinct(panel$t)
n_cohorts  <- n_distinct(panel$g[panel$g > 0L])

cat(glue("Panel: {n_units} counties, {n_states} states ",
         "({n_switch_s} treated, {n_never_s} never-treated), ",
         "{n_cohorts} cohorts, {n_months} months, {nrow(panel)} obs"), "\n")

mean_units_per_cohort <- panel %>%
  filter(g > 0L) %>%
  group_by(g) %>%
  summarise(n_county_in_cohort = n_distinct(id), .groups = "drop") %>%
  summarise(mean_n = mean(n_county_in_cohort),
            median_n = median(n_county_in_cohort),
            min_n = min(n_county_in_cohort),
            max_n = max(n_county_in_cohort))
cat(glue("Counties per treated cohort: mean={round(mean_units_per_cohort$mean_n,1)}, ",
         "median={mean_units_per_cohort$median_n}, ",
         "range=[{mean_units_per_cohort$min_n}, {mean_units_per_cohort$max_n}]"), "\n\n")

# ----------------------------- sanity check on real data ----------------------

cat("Sanity: real data estimates on county panel...\n")
dat_real <- as.data.frame(panel)

twfe_real <- feols(y ~ post_treat | id + t, data = dat_real,
                   cluster = ~state_abb, warn = FALSE, notes = FALSE)
cat(glue("  TWFE:  ATT={round(coef(twfe_real)[1], 4)}, SE={round(se(twfe_real)[1], 4)}"), "\n")

tryCatch({
  sunab_real <- feols(y ~ sunab(first_treat, t) | id + t, data = dat_real,
                      cluster = ~state_abb, warn = FALSE, notes = FALSE)
  sunab_agg <- summary(sunab_real, agg = "att")
  cat(glue("  SunAb: ATT={round(coef(sunab_agg)[1], 4)}, SE={round(se(sunab_agg)[1], 4)}"), "\n")
}, error = function(e) cat("  SunAb: ERROR -", conditionMessage(e), "\n"))

# CS-DiD: cluster at state via clustervars argument; idname is county.
tryCatch({
  cs_real <- did::att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g",
    data = dat_real, est_method = "reg",
    control_group = "notyettreated",
    clustervars = "state_abb",
    bstrap = FALSE, cband = FALSE,
    allow_unbalanced_panel = TRUE, print_details = FALSE,
    faster_mode = FALSE
  )
  cs_agg_real <- did::aggte(cs_real, type = "simple", na.rm = TRUE)
  cat(glue("  CS:    ATT={round(cs_agg_real$overall.att, 4)}, ",
           "SE={round(cs_agg_real$overall.se, 4)}"), "\n")
}, error = function(e) cat("  CS: ERROR -", conditionMessage(e), "\n"))

cat("\n")

# ----------------------------- FE fit + residual pool -------------------------

cat("Fitting county FE + month FE on untreated observations...\n")
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
cat(glue("Residual pool: {nrow(base_fe)} obs across {length(resid_pool_by_t)} months"), "\n\n")

# ----------------------------- simulation core --------------------------------

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

compute_t_p <- function(att, se, df) {
  if (is.finite(att) && is.finite(se) && se > 0) {
    2 * stats::pt(-abs(att / se), df = df)
  } else {
    NA_real_
  }
}

one_sim <- function(seed) {
  set.seed(seed)
  e_draw <- draw_errors(panel$t, resid_pool_by_t, global_pool)
  y_sim  <- panel$yhat + e_draw

  dat <- as.data.frame(data.frame(
    id          = panel$id,
    t           = panel$t,
    g           = panel$g,
    y           = y_sim,
    post_treat  = as.integer(panel$post_treat),
    first_treat = panel$first_treat,
    rel_time    = panel$rel_time,
    state_abb   = panel$state_abb
  ))

  out <- list(seed = seed)

  # --- TWFE ---
  out$twfe_ok <- FALSE
  tryCatch({
    suppressWarnings({
      fit <- feols(y ~ post_treat | id + t, data = dat, cluster = ~state_abb,
                   warn = FALSE, notes = FALSE)
      out$twfe_att <- as.numeric(coef(fit)[1])
      out$twfe_se  <- as.numeric(se(fit)[1])
      out$twfe_p   <- as.numeric(pvalue(fit)[1])
      out$twfe_ok  <- is.finite(out$twfe_att) && is.finite(out$twfe_se)
    })
  }, error = function(e) {
    out$twfe_err <<- conditionMessage(e)
  })

  # --- Sun-Abraham ---
  out$sunab_ok <- FALSE
  tryCatch({
    suppressMessages(suppressWarnings({
      fit_sa <- feols(y ~ sunab(first_treat, t) | id + t, data = dat,
                      cluster = ~state_abb, warn = FALSE, notes = FALSE)
      agg_sa <- summary(fit_sa, agg = "att")
      out$sunab_att <- as.numeric(coef(agg_sa)[1])
      out$sunab_se  <- as.numeric(se(agg_sa)[1])
      out$sunab_p   <- as.numeric(pvalue(agg_sa)[1])
      out$sunab_ok  <- is.finite(out$sunab_att) && is.finite(out$sunab_se)
    }))
  }, error = function(e) {
    out$sunab_err <<- conditionMessage(e)
  })

  # --- CS Analytic, state-clustered ---
  out$cs_ok <- FALSE
  tryCatch({
    suppressMessages(suppressWarnings({
      cs_fit <- did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        data = dat, est_method = "reg",
        control_group = "notyettreated",
        clustervars = "state_abb",
        bstrap = FALSE, cband = FALSE,
        allow_unbalanced_panel = TRUE, print_details = FALSE,
        faster_mode = FALSE
      )
      agg <- did::aggte(cs_fit, type = "simple", na.rm = TRUE)
      out$cs_att <- agg$overall.att
      out$cs_se  <- agg$overall.se
      out$cs_p   <- compute_t_p(out$cs_att, out$cs_se, df = n_switch_s - 1)
      out$cs_ok  <- is.finite(out$cs_att) && is.finite(out$cs_se)
    }))
  }, error = function(e) {
    out$cs_err <<- conditionMessage(e)
  })

  # --- didimputation ---
  if (HAS_DIDIMP) {
    out$didimp_ok <- FALSE
    tryCatch({
      suppressMessages(suppressWarnings({
        didimp_fit <- did_imputation(
          data = dat, yname = "y", gname = "first_treat",
          tname = "t", idname = "id", cluster_var = "state_abb"
        )
        out$didimp_att <- didimp_fit$estimate[1]
        out$didimp_se  <- didimp_fit$std.error[1]
        out$didimp_p   <- compute_t_p(out$didimp_att, out$didimp_se,
                                       df = n_switch_s - 1)
        out$didimp_ok  <- is.finite(out$didimp_att) && is.finite(out$didimp_se)
      }))
    }, error = function(e) {
      out$didimp_err <<- conditionMessage(e)
    })
  }

  # --- did2s ---
  if (HAS_DID2S) {
    out$did2s_ok <- FALSE
    tryCatch({
      suppressMessages(suppressWarnings({
        d2s_fit <- did2s(
          data = dat, yname = "y", first_stage = ~ 0 | id + t,
          second_stage = ~ post_treat, treatment = "post_treat",
          cluster_var = "state_abb"
        )
        out$did2s_att <- as.numeric(coef(d2s_fit)[1])
        d2s_vcov <- tryCatch(stats::vcov(d2s_fit), error = function(e) NULL)
        out$did2s_se  <- if (!is.null(d2s_vcov)) sqrt(diag(d2s_vcov))[1] else NA_real_
        out$did2s_p   <- compute_t_p(out$did2s_att, out$did2s_se,
                                      df = n_switch_s - 1)
        out$did2s_ok  <- is.finite(out$did2s_att) && is.finite(out$did2s_se)
      }))
    }, error = function(e) {
      out$did2s_err <<- conditionMessage(e)
    })
  }

  out
}

# ----------------------------- run simulations --------------------------------

cat(glue("Running {N_SIMS} simulations under the null with {N_WORKERS} workers..."), "\n")
seeds <- sample.int(1e8, N_SIMS)

use_parallel <- (N_WORKERS > 1L)
if (use_parallel) {
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({ library(fixest); library(did) })
    NULL
  })
  if (HAS_DIDIMP) parallel::clusterEvalQ(cl, { library(didimputation); NULL })
  if (HAS_DID2S)  parallel::clusterEvalQ(cl, { library(did2s); NULL })
  parallel::clusterExport(
    cl,
    varlist = c("panel", "resid_pool_by_t", "global_pool",
                "n_switch_s", "draw_errors", "compute_t_p", "one_sim",
                "HAS_DIDIMP", "HAS_DID2S"),
    envir = environment()
  )
}

t0 <- Sys.time()
batch_size <- 5L
n_batches <- ceiling(N_SIMS / batch_size)
results <- vector("list", N_SIMS)

for (b in seq_len(n_batches)) {
  lo <- (b - 1) * batch_size + 1L
  hi <- min(b * batch_size, N_SIMS)
  bs <- seeds[lo:hi]
  batch_results <- if (use_parallel) {
    parallel::parLapply(cl, bs, one_sim)
  } else {
    lapply(bs, one_sim)
  }
  results[lo:hi] <- batch_results

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  rate <- elapsed / hi
  eta <- rate * (N_SIMS - hi)
  cat(glue("  [{hi}/{N_SIMS}] elapsed={round(elapsed)}s, ETA~{round(eta)}s"), "\n")
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(glue("\nDone in {round(elapsed_total)}s ({round(elapsed_total/60, 1)} min)"), "\n\n")

# ----------------------------- summarize --------------------------------------

df <- bind_rows(lapply(results, function(r) {
  row <- tibble(seed = r$seed)
  for (m in c("twfe", "sunab", "cs", "didimp", "did2s")) {
    row[[paste0(m, "_ok")]]  <- isTRUE(r[[paste0(m, "_ok")]])
    row[[paste0(m, "_att")]] <- r[[paste0(m, "_att")]] %||% NA_real_
    row[[paste0(m, "_se")]]  <- r[[paste0(m, "_se")]] %||% NA_real_
    row[[paste0(m, "_p")]]   <- r[[paste0(m, "_p")]] %||% NA_real_
  }
  row
}))

write_csv(df, file.path(OUT_DIR, "sim_results.csv"))

summarize_method <- function(ok, att, se, p, name) {
  valid <- ok & is.finite(att) & is.finite(se) & se > 0 & is.finite(p)
  n_valid <- sum(valid); n_fail <- sum(!ok)
  if (n_valid == 0) {
    return(tibble(method = name, n_valid = 0, n_fail = n_fail,
                  rejection = NA, mean_att = NA, sd_att = NA,
                  mean_se = NA, se_over_sd = NA))
  }
  att_v <- att[valid]; se_v <- se[valid]; p_v <- p[valid]
  tibble(
    method = name, n_valid = n_valid, n_fail = n_fail,
    rejection = mean(p_v < ALPHA),
    mean_att = mean(att_v),
    sd_att = sd(att_v),
    mean_se = mean(se_v),
    se_over_sd = mean(se_v) / sd(att_v)
  )
}

methods <- list(
  list("twfe",   "TWFE (fixest)"),
  list("sunab",  "Sun-Abraham (fixest)"),
  list("cs",     "CS Analytic (did)"),
  list("didimp", "didimputation (BJS)"),
  list("did2s",  "did2s (Gardner)")
)

summary_rows <- bind_rows(lapply(methods, function(m) {
  col <- m[[1]]; name <- m[[2]]
  ok_col <- paste0(col, "_ok"); att_col <- paste0(col, "_att")
  se_col <- paste0(col, "_se"); p_col <- paste0(col, "_p")
  if (!(ok_col %in% names(df))) return(NULL)
  if (all(is.na(df[[ok_col]]))) return(NULL)
  summarize_method(df[[ok_col]], df[[att_col]], df[[se_col]], df[[p_col]], name)
}))

# Add noise ratio vs TWFE.
twfe_sd <- summary_rows$sd_att[summary_rows$method == "TWFE (fixest)"]
if (length(twfe_sd) == 1 && is.finite(twfe_sd) && twfe_sd > 0) {
  summary_rows$noise_ratio_vs_twfe <- summary_rows$sd_att / twfe_sd
} else {
  summary_rows$noise_ratio_vs_twfe <- NA_real_
}

write_csv(summary_rows, file.path(OUT_DIR, "calibration_summary.csv"))

cat("============================================================\n")
cat("  MULTI-ESTIMATOR CALIBRATION — COUNTY PANEL RESULTS\n")
cat("============================================================\n\n")
print(summary_rows %>% mutate(across(where(is.numeric), ~ signif(.x, 3))))

cat("\n\nComparison to state-panel result (CLAUDE.md baseline):\n")
cat("                    State-panel  |  County-panel\n")
cat("                    Rej%   SE/SD |  Rej%   SE/SD  Noise×\n")
for (i in seq_len(nrow(summary_rows))) {
  r <- summary_rows[i, ]
  state_panel_lookup <- list(
    `TWFE (fixest)`        = list(rej = 0.01, se_over_sd = 1.14),
    `Sun-Abraham (fixest)` = list(rej = 0.21, se_over_sd = 0.58),
    `CS Analytic (did)`    = list(rej = 0.14, se_over_sd = 0.67),
    `didimputation (BJS)`  = list(rej = NA,   se_over_sd = NA),
    `did2s (Gardner)`      = list(rej = NA,   se_over_sd = NA)
  )
  sp <- state_panel_lookup[[r$method]]
  cat(sprintf("  %-22s %4s   %4s  |  %4s   %4s    %4s\n",
              r$method,
              if (is.null(sp) || is.na(sp$rej)) "  —" else sprintf("%.1f%%", sp$rej * 100),
              if (is.null(sp) || is.na(sp$se_over_sd)) "  —" else sprintf("%.2f", sp$se_over_sd),
              if (is.na(r$rejection)) "  —" else sprintf("%.1f%%", r$rejection * 100),
              if (is.na(r$se_over_sd)) "  —" else sprintf("%.2f", r$se_over_sd),
              if (is.na(r$noise_ratio_vs_twfe)) "  —" else sprintf("%.1fx", r$noise_ratio_vs_twfe)))
}

cat(glue("\nResults saved to: {OUT_DIR}/"), "\n")
