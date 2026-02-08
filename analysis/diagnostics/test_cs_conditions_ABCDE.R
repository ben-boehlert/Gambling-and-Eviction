#!/usr/bin/env Rscript
################################################################################
# test_cs_conditions_ABCDE.R
#
# Systematic A/B testing of CS DiD null size failure
# Tests conditions A-E to adjudicate between competing explanations
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

# Read command line args
args <- commandArgs(trailingOnly = TRUE)
CONDITION <- if (length(args) > 0) args[1] else "A"
N_SIMS <- if (length(args) > 1) as.integer(args[2]) else 500

cat("================================================================================\n")
cat("CS DiD NULL SIZE TEST - CONDITION", CONDITION, "\n")
cat("N_SIMS:", N_SIMS, "\n")
cat("================================================================================\n\n")

# Load data (using minimal test data if main data not available)
DATA_FILE <- Sys.getenv("DATA_FILE", "")
if (DATA_FILE == "" || !file.exists(DATA_FILE)) {
  cat("Main data file not found, creating synthetic panel...\n")

  # Create synthetic panel matching structure
  set.seed(12345)
  n_states <- 38
  n_months <- 120

  # Create balanced treatment groups to avoid singleton issues
  # Group 0 = never treated (10 states)
  # Group 60 = treated at t=60 (14 states)
  # Group 80 = treated at t=80 (14 states)
  treatment_timing <- c(
    rep(0, 10),   # Never treated
    rep(60, 14),  # Early treated
    rep(80, 14)   # Late treated
  )
  treatment_timing <- sample(treatment_timing)  # Randomize assignment

  panel <- expand.grid(
    id = 1:n_states,
    t = 1:n_months
  )

  panel$g <- treatment_timing[panel$id]
  panel$post_treat <- (panel$g > 0) & (panel$t >= panel$g)
  panel$untreated_obs <- !panel$post_treat

  # Generate y with FE structure
  set.seed(12345)
  alpha_i <- rnorm(n_states, mean = 5, sd = 0.5)
  lambda_t <- rnorm(n_months, mean = 0, sd = 0.3)

  panel$y <- alpha_i[panel$id] + lambda_t[panel$t] + rnorm(nrow(panel), sd = 0.4)

  # Set global n_states
  n_states <- length(unique(panel$id))

} else {
  # Load actual data
  panel <- read_csv(DATA_FILE, show_col_types = FALSE)
  n_states <- length(unique(panel$id))
}

cat("Panel structure:\n")
cat("  n_states:", n_states, "\n")
cat("  n_obs:", nrow(panel), "\n")
cat("  n_months:", length(unique(panel$t)), "\n\n")

# Configuration based on CONDITION
CONFIG <- list(
  bstrap = TRUE,
  biters = 199,
  cband = FALSE,
  fe_mode = "untreated_only"  # or "all_data"
)

if (CONDITION == "A") {
  cat("CONDITION A: Baseline (current code)\n")
  cat("  - bstrap=TRUE, cband=FALSE\n")
  cat("  - FE fit on untreated only\n\n")

} else if (CONDITION == "B") {
  cat("CONDITION B: No bootstrap (analytic SE)\n")
  cat("  - bstrap=FALSE, cband=FALSE\n")
  cat("  - FE fit on untreated only\n")
  cat("  - WARNING: Analytic SEs may not be cluster-robust!\n\n")
  CONFIG$bstrap <- FALSE

} else if (CONDITION == "C") {
  cat("CONDITION C: Simultaneous confidence bands\n")
  cat("  - bstrap=TRUE, cband=TRUE\n")
  cat("  - FE fit on untreated only\n\n")
  CONFIG$cband <- TRUE

} else if (CONDITION == "D1") {
  cat("CONDITION D1: FE on untreated only (current)\n")
  cat("  - bstrap=TRUE, cband=FALSE\n")
  cat("  - FE fit on untreated only\n\n")
  CONFIG$fe_mode <- "untreated_only"

} else if (CONDITION == "D2") {
  cat("CONDITION D2: FE on all data\n")
  cat("  - bstrap=TRUE, cband=FALSE\n")
  cat("  - FE fit on ALL data (including treated)\n")
  cat("  - WARNING: May contaminate null with treatment effects!\n\n")
  CONFIG$fe_mode <- "all_data"

} else {
  stop("Unknown CONDITION: ", CONDITION)
}

# Prepare data based on FE mode
if (CONFIG$fe_mode == "untreated_only") {
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
  base_fe$ehat <- as.numeric(residuals(fe_fit))

} else if (CONFIG$fe_mode == "all_data") {
  # Fit FE on all data
  fe_fit <- fixest::feols(y ~ 1 | id + t,
                          data = panel %>% filter(is.finite(y)),
                          notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))

  # Extract residuals for ALL observations
  panel$ehat <- as.numeric(residuals(fe_fit))

  # Create residual pool from untreated observations only
  base_fe <- panel %>% filter(untreated_obs, is.finite(ehat))
}

# Residual pool (always from untreated observations)
resid_pool <- base_fe$ehat
global_pool <- base_fe$ehat

cat("Residual pool size:", length(resid_pool), "\n\n")

# Output file
OUT_FILE <- glue("cs_power_out/diag_null_condition_{CONDITION}.csv")
dir.create("cs_power_out", showWarnings = FALSE, recursive = TRUE)
if (file.exists(OUT_FILE)) file.remove(OUT_FILE)

# One simulation with full diagnostics
one_sim <- function(seed, effect_log) {
  set.seed(seed)

  # Draw errors
  e_draw <- sample(resid_pool, size = nrow(panel), replace = TRUE)

  # Generate y_sim
  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat, effect_log, 0.0)

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    g  = panel$g,
    y  = y_sim
  )

  out <- tryCatch({
    suppressWarnings({
      est <- did::att_gt(
        yname = "y",
        tname = "t",
        idname = "id",
        gname = "g",
        xformla = ~ 1,
        data = dat,
        panel = TRUE,
        control_group = "nevertreated",
        allow_unbalanced_panel = TRUE,
        est_method = "reg",  # Use regression (IPW with xformla=~1 fails with "y missing" error)
        faster_mode = FALSE,
        bstrap = CONFIG$bstrap,
        biters = CONFIG$biters,
        cband = CONFIG$cband,
        clustervars = "id"
      )

      # Extract ATT(g,t) vector for diagnostics
      attgt_vec <- if (!is.null(est$att)) est$att else if (!is.null(est$attgt)) est$attgt else NULL
      n_attgt_total <- if (is.null(attgt_vec)) 0 else length(attgt_vec)
      n_attgt_non_na <- if (is.null(attgt_vec)) 0 else sum(!is.na(attgt_vec))
      miss_share_attgt <- if (n_attgt_total == 0) NA_real_ else mean(is.na(attgt_vec))

      # Get critical value if present
      crit_val <- if (!is.null(est$c)) est$c else if (!is.null(est$cval)) est$cval else NA_real_

      # Aggregate to scalar
      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)

      # Check for overall.pval
      overall_pval_exists <- !is.null(agg$overall.pval)

      # Compute p-value
      z <- att / se
      p <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_

      # Also compute normal p-value for comparison
      p_norm <- if (is.finite(z)) 2 * pnorm(-abs(z)) else NA_real_

      list(
        ok = TRUE,
        seed = seed,
        att = att,
        se = se,
        z = z,
        p = p,
        p_norm = p_norm,
        n_states = n_states,
        n_attgt_total = n_attgt_total,
        n_attgt_non_na = n_attgt_non_na,
        miss_share_attgt = miss_share_attgt,
        crit_val = crit_val,
        overall_pval_exists = overall_pval_exists,
        effect_log = effect_log
      )
    })
  }, error = function(e) {
    list(
      ok = FALSE,
      seed = seed,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p = NA_real_,
      p_norm = NA_real_,
      n_states = n_states,
      n_attgt_total = NA_integer_,
      n_attgt_non_na = NA_integer_,
      miss_share_attgt = NA_real_,
      crit_val = NA_real_,
      overall_pval_exists = FALSE,
      effect_log = effect_log,
      error = conditionMessage(e)
    )
  })

  out
}

# Run simulations
cat("Running", N_SIMS, "null simulations...\n")
set.seed(20240101)
seeds <- sample.int(1e6, N_SIMS)

results <- list()
pb <- txtProgressBar(min = 0, max = N_SIMS, style = 3)
for (i in seq_len(N_SIMS)) {
  results[[i]] <- one_sim(seeds[i], effect_log = 0.0)
  setTxtProgressBar(pb, i)
}
close(pb)

# Convert to data frame
df <- bind_rows(results)

# Write diagnostics
write_csv(df, OUT_FILE)
cat("\nWrote diagnostics to:", OUT_FILE, "\n\n")

# Compute summary statistics
df_ok <- df %>% filter(ok == TRUE, is.finite(att), is.finite(se), se > 0)

if (nrow(df_ok) == 0) {
  cat("ERROR: No successful simulations!\n")
  quit(status = 1)
}

cat("================================================================================\n")
cat("SUMMARY STATISTICS - CONDITION", CONDITION, "\n")
cat("================================================================================\n\n")

cat("Success rate:", nrow(df_ok), "/", nrow(df), "=",
    sprintf("%.1f%%", 100 * nrow(df_ok) / nrow(df)), "\n\n")

# Key metrics
reject_rate <- mean(df_ok$p < 0.05, na.rm = TRUE)
mean_se <- mean(df_ok$se, na.rm = TRUE)
sd_att <- sd(df_ok$att, na.rm = TRUE)
ratio <- mean_se / sd_att
sd_z <- sd(df_ok$z, na.rm = TRUE)

# P-value quantiles
p_quants <- quantile(df_ok$p, c(0.01, 0.05, 0.10, 0.50, 0.90), na.rm = TRUE)

# ATT(g,t) diagnostics
mean_miss_share <- mean(df_ok$miss_share_attgt, na.rm = TRUE)
mean_n_attgt_non_na <- mean(df_ok$n_attgt_non_na, na.rm = TRUE)

cat("REJECTION RATE:\n")
cat("  reject_rate (p < 0.05):", sprintf("%.4f", reject_rate),
    sprintf("(%.2f%%)", 100*reject_rate), "\n")
cat("  Expected: ~0.05 (5%)\n\n")

cat("SE CALIBRATION:\n")
cat("  mean(SE):", sprintf("%.4f", mean_se), "\n")
cat("  sd(ATT):", sprintf("%.4f", sd_att), "\n")
cat("  mean(SE) / sd(ATT):", sprintf("%.3f", ratio), "\n")
cat("  Expected: ~1.0\n\n")

cat("Z-STATISTIC:\n")
cat("  sd(Z):", sprintf("%.4f", sd_z), "\n")
cat("  Expected: ~1.0\n\n")

cat("P-VALUE QUANTILES (should be uniform [0,1] under null):\n")
cat("  p01:", sprintf("%.3f", p_quants[1]), "(expected: 0.01)\n")
cat("  p05:", sprintf("%.3f", p_quants[2]), "(expected: 0.05)\n")
cat("  p10:", sprintf("%.3f", p_quants[3]), "(expected: 0.10)\n")
cat("  p50:", sprintf("%.3f", p_quants[4]), "(expected: 0.50)\n")
cat("  p90:", sprintf("%.3f", p_quants[5]), "(expected: 0.90)\n\n")

cat("ATT(g,t) CELL DIAGNOSTICS:\n")
cat("  mean miss_share_attgt:", sprintf("%.3f", mean_miss_share), "\n")
cat("  mean n_attgt_non_na:", sprintf("%.1f", mean_n_attgt_non_na), "\n\n")

# Check for unit mismatch (Condition E)
cat("UNIT MISMATCH CHECK:\n")
cat("  ATT range: [", sprintf("%.4f", min(df_ok$att)), ",",
    sprintf("%.4f", max(df_ok$att)), "]\n")
cat("  SE range: [", sprintf("%.4f", min(df_ok$se)), ",",
    sprintf("%.4f", max(df_ok$se)), "]\n")
cat("  Z range: [", sprintf("%.4f", min(df_ok$z)), ",",
    sprintf("%.4f", max(df_ok$z)), "]\n")
cat("  → ATT and SE appear to be on same scale (log points)\n\n")

# Check if overall.pval exists
cat("OVERALL.PVAL CHECK:\n")
cat("  overall.pval exists:", any(df_ok$overall_pval_exists), "\n")
cat("  → If FALSE, simulation uses fallback t-test\n\n")

# Save summary
summary_data <- data.frame(
  condition = CONDITION,
  n_sims = N_SIMS,
  success_rate = nrow(df_ok) / nrow(df),
  reject_rate = reject_rate,
  mean_se = mean_se,
  sd_att = sd_att,
  ratio = ratio,
  sd_z = sd_z,
  p01 = p_quants[1],
  p05 = p_quants[2],
  p10 = p_quants[3],
  p50 = p_quants[4],
  p90 = p_quants[5],
  mean_miss_share = mean_miss_share,
  mean_n_attgt_non_na = mean_n_attgt_non_na
)

summary_file <- "cs_power_out/summary_all_conditions.csv"
if (!file.exists(summary_file)) {
  write_csv(summary_data, summary_file)
} else {
  write_csv(summary_data, summary_file, append = TRUE)
}

cat("================================================================================\n")
cat("DONE - Condition", CONDITION, "\n")
cat("================================================================================\n")
