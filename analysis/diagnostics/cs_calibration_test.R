#!/usr/bin/env Rscript
################################################################################
# cs_calibration_test.R  (v3 — exactly mirrors pretrends_statepanel_template.R)
#
# PURPOSE: Test whether did::att_gt() + aggte() produces calibrated inference
#          under the null (effect = 0). We need ~5% rejection at alpha = 0.05.
#
# Tests three inference approaches:
#   1. Analytic SEs from aggte(bstrap=FALSE)
#   2. Bootstrap p-values from aggte(bstrap=TRUE, biters=199)
#   3. TWFE baseline (fixest::feols) — known-calibrated reference
#
# Panel build: identical to pretrends_statepanel_template.R with defaults from
# run_pretrends_statepanel.sh — should produce 24 states, 83 months, 1992 obs.
#
# USAGE:
#   N_SIMS=100 N_WORKERS=4 Rscript analysis/diagnostics/cs_calibration_test.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
  library(tibble)
})

# Source shared treatment schedule utility (handles state name → abbreviation)
source("utils/eviction_treatment_schedule.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

# ----------------------------- config -----------------------------------------

N_SIMS     <- parse_int(getenv1("N_SIMS", "100"), 100L)
N_WORKERS  <- parse_int(getenv1("N_WORKERS", "4"), 4L)
SEED       <- 20260409L
ALPHA      <- 0.05
DID_BITERS <- 199L

PANEL_FILE     <- "data/raw/state_month_panel_with_treatment.csv"
TREAT_FILE     <- "data/raw/sports_gambling_legalization_dates.csv"
TREAT_DATE_COL <- "online_start_date"
OUT_DIR        <- "data/output/cs_calibration_test"

# Match pretrends_statepanel_template.R defaults exactly
EXCLUDE_STATES <- c("ME")
MIN_DATE       <- as.Date("2016-01-01")
MAX_DATE       <- as.Date("2024-12-31")
DROP_START     <- as.Date("2020-03-01")
DROP_END       <- as.Date("2022-03-31")  # matches run_pretrends_statepanel.sh

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== CS CALIBRATION TEST (v3) ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}, SEED={SEED}"), "\n")
cat(glue("DID_BITERS={DID_BITERS}, ALPHA={ALPHA}"), "\n")
cat(glue("COVID drop: {DROP_START} to {DROP_END}"), "\n")
cat(glue("Exclude: {paste(EXCLUDE_STATES, collapse=', ')}"), "\n\n")

# ----------------------------- helpers ----------------------------------------

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

# ----------------------------- build panel ------------------------------------
# Mirrors pretrends_statepanel_template.R panel build exactly

cat("Loading panel...\n")
panel0 <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    filings_count = as.numeric(filings_count)
  )

# Date range filter
panel0 <- panel0 %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE)

# Exclude states
panel0 <- panel0 %>%
  filter(!(state_abb %in% EXCLUDE_STATES))

# Drop COVID window
panel0 <- panel0 %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

# Coverage threshold (auto = max_coverage, matching pretrends default)
coverage <- panel0 %>% count(state_abb, name = "n_months") %>% arrange(desc(n_months))
max_cov <- max(coverage$n_months)
keep_states <- coverage %>% filter(n_months >= max_cov) %>% pull(state_abb)
panel0 <- panel0 %>% filter(state_abb %in% keep_states)
cat(glue("Coverage threshold: {max_cov} months, {length(keep_states)} states pass"), "\n")

# Balance to common months (BALANCE_COMMON_MONTHS=TRUE default)
n_states_pre <- n_distinct(panel0$state_abb)
common_months <- panel0 %>%
  count(month_date, name = "n_states") %>%
  filter(n_states == n_states_pre) %>%
  pull(month_date)
panel0 <- panel0 %>% filter(month_date %in% common_months)

# Treatment schedule from file using shared utility
treat_by_state <- load_eviction_treatment_schedule(
  treat_file = TREAT_FILE,
  treat_date_col = TREAT_DATE_COL,
  states = panel0$state_abb
)

panel <- panel0 %>%
  left_join(treat_by_state, by = "state_abb") %>%
  mutate(
    y = log1p(pmax(filings_count, 0)),
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    untreated_obs = (g == 0L) | (t < g),
    post_treat = (g > 0L) & (t >= g)
  )

n_states <- n_distinct(panel$state_abb)
n_switch <- n_distinct(panel$state_abb[panel$g > 0L])
n_never <- n_states - n_switch
n_months <- n_distinct(panel$t)

cat(glue("Panel: {n_states} states ({n_switch} treated, {n_never} never-treated), {n_months} months, {nrow(panel)} obs"), "\n")

# Verify balance
bal <- panel %>% count(state_abb) %>% pull(n)
if (length(unique(bal)) > 1) {
  cat("WARNING: Panel is not balanced! Obs per state:", paste(unique(bal), collapse = ", "), "\n")
  stop("Panel must be balanced for calibration test. Check panel build logic.")
} else {
  cat(glue("Panel is balanced: {unique(bal)} obs per state [OK]"), "\n")
}

# Quick sanity: run CS on real data to confirm it works
cat("\nSanity check: running CS on real data...\n")
dat_real <- as.data.frame(panel[, c("id", "t", "g", "y")])
tryCatch({
  cs_sanity <- did::att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g",
    data = dat_real, est_method = "reg",
    control_group = "notyettreated",
    bstrap = FALSE, cband = FALSE,
    allow_unbalanced_panel = TRUE,
    print_details = FALSE
  )
  agg_sanity <- did::aggte(cs_sanity, type = "simple")
  cat(glue("  Real data ATT: {round(agg_sanity$overall.att, 4)}, SE: {round(agg_sanity$overall.se, 4)}"), "\n")
  cat("  CS works on this panel. Proceeding with simulation.\n\n")
}, error = function(e) {
  cat("  ERROR on real data:", conditionMessage(e), "\n")
  cat("  CS cannot run on this panel. Aborting.\n")
  quit(status = 1)
})

# ----------------------------- FE + residual pool -----------------------------

base_fe <- panel %>% filter(untreated_obs, is.finite(y))

set.seed(SEED)
fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))

if (any(!is.finite(panel$yhat))) {
  n_bad <- sum(!is.finite(panel$yhat))
  cat(glue("Dropping {n_bad} non-finite yhat rows"), "\n")
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}

base_fe$ehat <- as.numeric(residuals(fe_fit))

# Residual pool by month
resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]

cat(glue("Residual pool: {nrow(base_fe)} obs, {length(resid_pool_by_t)} months"), "\n\n")

# ----------------------------- error draw function ----------------------------

draw_errors_iid_month <- function(t_vec, pool_by_t, fallback_pool) {
  e <- numeric(length(t_vec))
  for (t_val in unique(t_vec)) {
    idx <- which(t_vec == t_val)
    pool <- pool_by_t[[as.character(t_val)]]
    if (is.null(pool) || length(pool) < 3) pool <- fallback_pool
    e[idx] <- sample(pool, size = length(idx), replace = TRUE)
  }
  e
}

# ----------------------------- one simulation ---------------------------------

one_sim <- function(seed) {
  set.seed(seed)

  e_draw <- draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  y_sim <- panel$yhat + e_draw  # no treatment effect

  dat <- as.data.frame(data.frame(
    id = panel$id, t = panel$t, g = panel$g,
    y = y_sim, post_treat = as.integer(panel$post_treat)
  ))

  out <- list(seed = seed)

  # --- Method 1: CS analytic SEs ---
  tryCatch({
    suppressMessages(suppressWarnings({
      cs_fit <- did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        data = dat, est_method = "reg",
        control_group = "notyettreated",
        bstrap = FALSE, cband = FALSE,
        allow_unbalanced_panel = TRUE,
        print_details = FALSE
      )
      agg <- did::aggte(cs_fit, type = "simple")
      out$cs_analytic_att <- agg$overall.att
      out$cs_analytic_se  <- agg$overall.se
      if (is.finite(agg$overall.att) && is.finite(agg$overall.se) && agg$overall.se > 0) {
        tstat <- agg$overall.att / agg$overall.se
        out$cs_analytic_p <- 2 * pt(-abs(tstat), df = n_states - 1)
      } else {
        out$cs_analytic_p <- NA_real_
      }
      out$cs_analytic_ok <- TRUE
    }))
  }, error = function(e) {
    out$cs_analytic_ok  <<- FALSE
    out$cs_analytic_att <<- NA_real_
    out$cs_analytic_se  <<- NA_real_
    out$cs_analytic_p   <<- NA_real_
    out$cs_analytic_err <<- conditionMessage(e)
  })

  # --- Method 2: CS bootstrap ---
  tryCatch({
    suppressMessages(suppressWarnings({
      cs_fit_bs <- did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        data = dat, est_method = "reg",
        control_group = "notyettreated",
        bstrap = TRUE, biters = DID_BITERS, cband = FALSE,
        allow_unbalanced_panel = TRUE,
        print_details = FALSE
      )
      agg_bs <- did::aggte(cs_fit_bs, type = "simple")
      out$cs_bootstrap_att <- agg_bs$overall.att
      out$cs_bootstrap_se  <- agg_bs$overall.se
      if (is.finite(agg_bs$overall.att) && is.finite(agg_bs$overall.se) && agg_bs$overall.se > 0) {
        tstat_bs <- agg_bs$overall.att / agg_bs$overall.se
        out$cs_bootstrap_p <- 2 * pt(-abs(tstat_bs), df = n_states - 1)
      } else {
        out$cs_bootstrap_p <- NA_real_
      }
      out$cs_bootstrap_ok <- TRUE
    }))
  }, error = function(e) {
    out$cs_bootstrap_ok  <<- FALSE
    out$cs_bootstrap_att <<- NA_real_
    out$cs_bootstrap_se  <<- NA_real_
    out$cs_bootstrap_p   <<- NA_real_
    out$cs_bootstrap_err <<- conditionMessage(e)
  })

  # --- Method 3: TWFE reference ---
  tryCatch({
    suppressWarnings({
      twfe_fit <- feols(y ~ post_treat | id + t, data = dat,
                        cluster = ~id, warn = FALSE, notes = FALSE)
      out$twfe_att <- as.numeric(coef(twfe_fit)[1])
      out$twfe_se  <- as.numeric(se(twfe_fit)[1])
      out$twfe_p   <- as.numeric(pvalue(twfe_fit)[1])
      out$twfe_ok  <- TRUE
    })
  }, error = function(e) {
    out$twfe_ok  <<- FALSE
    out$twfe_att <<- NA_real_
    out$twfe_se  <<- NA_real_
    out$twfe_p   <<- NA_real_
  })

  out
}

# ----------------------------- run simulations --------------------------------

cat(glue("Running {N_SIMS} simulations under the null (effect = 0)..."), "\n")

seeds <- sample.int(1e8, N_SIMS)

use_parallel <- (N_WORKERS > 1L)
if (use_parallel) {
  cat(glue("Starting PSOCK cluster with {N_WORKERS} workers"), "\n")
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(fixest)
      library(did)
    })
    NULL
  })

  parallel::clusterExport(
    cl,
    varlist = c(
      "panel", "resid_pool_by_t", "global_pool",
      "n_states", "DID_BITERS", "draw_errors_iid_month", "one_sim"
    ),
    envir = environment()
  )
}

t0 <- Sys.time()

batch_size <- 10L
n_batches <- ceiling(N_SIMS / batch_size)
results <- vector("list", N_SIMS)

for (b in seq_len(n_batches)) {
  lo <- (b - 1) * batch_size + 1L
  hi <- min(b * batch_size, N_SIMS)
  batch_seeds <- seeds[lo:hi]

  if (use_parallel) {
    batch_results <- parallel::parLapply(cl, batch_seeds, one_sim)
  } else {
    batch_results <- lapply(batch_seeds, one_sim)
  }
  results[lo:hi] <- batch_results

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  done <- hi
  rate <- elapsed / done
  eta <- rate * (N_SIMS - done)
  cat(glue("  [{done}/{N_SIMS}] elapsed={round(elapsed)}s, ~{round(eta)}s remaining"), "\n")
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(glue("\nDone in {round(elapsed_total)}s ({round(elapsed_total/60, 1)} min)"), "\n\n")

# ----------------------------- summarize results ------------------------------

df_results <- bind_rows(lapply(results, function(r) {
  tibble(
    seed = r$seed,
    cs_analytic_ok  = isTRUE(r$cs_analytic_ok),
    cs_analytic_att = r$cs_analytic_att %||% NA_real_,
    cs_analytic_se  = r$cs_analytic_se %||% NA_real_,
    cs_analytic_p   = r$cs_analytic_p %||% NA_real_,
    cs_analytic_err = if (!is.null(r$cs_analytic_err)) r$cs_analytic_err else NA_character_,
    cs_bootstrap_ok  = isTRUE(r$cs_bootstrap_ok),
    cs_bootstrap_att = r$cs_bootstrap_att %||% NA_real_,
    cs_bootstrap_se  = r$cs_bootstrap_se %||% NA_real_,
    cs_bootstrap_p   = r$cs_bootstrap_p %||% NA_real_,
    cs_bootstrap_err = if (!is.null(r$cs_bootstrap_err)) r$cs_bootstrap_err else NA_character_,
    twfe_ok  = isTRUE(r$twfe_ok),
    twfe_att = r$twfe_att %||% NA_real_,
    twfe_se  = r$twfe_se %||% NA_real_,
    twfe_p   = r$twfe_p %||% NA_real_
  )
}))

write_csv(df_results, file.path(OUT_DIR, "sim_results.csv"))

# Show error messages if any
cs_a_errs <- df_results %>% filter(!cs_analytic_ok, !is.na(cs_analytic_err)) %>%
  count(cs_analytic_err, sort = TRUE)
if (nrow(cs_a_errs) > 0) {
  cat("CS Analytic errors:\n")
  print(cs_a_errs)
  cat("\n")
}
cs_b_errs <- df_results %>% filter(!cs_bootstrap_ok, !is.na(cs_bootstrap_err)) %>%
  count(cs_bootstrap_err, sort = TRUE)
if (nrow(cs_b_errs) > 0) {
  cat("CS Bootstrap errors:\n")
  print(cs_b_errs)
  cat("\n")
}

# Compute diagnostics
summarize_method <- function(ok, att, se, p, method_name) {
  valid <- ok & is.finite(att) & is.finite(se) & se > 0 & is.finite(p)
  n_valid <- sum(valid)
  n_fail  <- sum(!ok)

  if (n_valid == 0) {
    cat(glue("\n=== {method_name} ==="), "\n")
    cat(glue("  ALL FAILED ({n_fail}/{length(ok)} errors)"), "\n")
    return(tibble(
      method = method_name, n_valid = 0, n_fail = n_fail,
      rejection_rate = NA, mean_att = NA, sd_att = NA, mean_se = NA,
      se_over_sd = NA, p05 = NA, p50 = NA, p95 = NA
    ))
  }

  att_v <- att[valid]; se_v <- se[valid]; p_v <- p[valid]
  reject <- mean(p_v < ALPHA)
  sd_att <- sd(att_v)
  mean_se <- mean(se_v)
  se_ratio <- mean_se / sd_att

  cat(glue("\n=== {method_name} ==="), "\n")
  cat(glue("  Valid: {n_valid}/{length(ok)} (failures: {n_fail})"), "\n")
  cat(glue("  Rejection rate at alpha={ALPHA}: {round(reject * 100, 1)}% (target: 5%)"), "\n")
  cat(glue("  Mean ATT: {round(mean(att_v), 4)}  (should be ~0)"), "\n")
  cat(glue("  SD(ATT):  {round(sd_att, 4)}"), "\n")
  cat(glue("  Mean SE:  {round(mean_se, 4)}"), "\n")
  cat(glue("  SE/SD ratio: {round(se_ratio, 2)} (should be ~1.0)"), "\n")
  cat(glue("  P-value quantiles: p05={round(quantile(p_v, 0.05), 3)}, p50={round(quantile(p_v, 0.50), 3)}, p95={round(quantile(p_v, 0.95), 3)}"), "\n")

  tibble(
    method = method_name, n_valid = n_valid, n_fail = n_fail,
    rejection_rate = reject, mean_att = mean(att_v), sd_att = sd_att,
    mean_se = mean_se, se_over_sd = se_ratio,
    p05 = quantile(p_v, 0.05), p50 = quantile(p_v, 0.50),
    p95 = quantile(p_v, 0.95)
  )
}

cat("\n============================================================")
cat("\n  CS CALIBRATION TEST — NULL REJECTION DIAGNOSTICS")
cat("\n============================================================\n")

summary_rows <- bind_rows(
  summarize_method(df_results$cs_analytic_ok, df_results$cs_analytic_att,
                   df_results$cs_analytic_se, df_results$cs_analytic_p, "CS Analytic"),
  summarize_method(df_results$cs_bootstrap_ok, df_results$cs_bootstrap_att,
                   df_results$cs_bootstrap_se, df_results$cs_bootstrap_p, "CS Bootstrap"),
  summarize_method(df_results$twfe_ok, df_results$twfe_att,
                   df_results$twfe_se, df_results$twfe_p, "TWFE (reference)")
)

write_csv(summary_rows, file.path(OUT_DIR, "calibration_summary.csv"))

cat("\n\n=== CALIBRATION VERDICT ===\n")
for (i in seq_len(nrow(summary_rows))) {
  r <- summary_rows[i, ]
  if (is.na(r$rejection_rate)) {
    cat(glue("  {r$method}: FAILED (no valid results)"), "\n")
  } else {
    status <- if (r$rejection_rate >= 0.02 & r$rejection_rate <= 0.10) "PASS" else "FAIL"
    se_status <- if (!is.na(r$se_over_sd) && r$se_over_sd >= 0.8 && r$se_over_sd <= 1.3) "OK" else "INFLATED"
    cat(glue("  {r$method}: rejection={round(r$rejection_rate*100,1)}% [{status}], SE/SD={round(r$se_over_sd,2)} [{se_status}]"), "\n")
  }
}
cat(glue("\nTarget: rejection ~5% (2-10% acceptable with {N_SIMS} sims), SE/SD ~1.0 (0.8-1.3 OK)"), "\n")
cat(glue("Results saved to: {OUT_DIR}/"), "\n")
