#!/usr/bin/env Rscript
################################################################################
# debug_cs_size_audit.R
#
# FORENSIC AUDIT: Prove why null rejection rate is 0%
# Instruments every null simulation to log att, se, z, pval
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

# Load simulation environment
cat("Loading simulation environment...\n")
source("power_simulation_cs_statepanel_staggered_parallel_merged.R",
       echo = FALSE, verbose = FALSE)

cat("\n=== CS SIZE AUDIT (INSTRUMENTED) ===\n\n")

# ============================================================================
# INSTRUMENTED VERSION OF one_sim
# ============================================================================

one_sim_instrumented <- function(seed, effect_log) {
  set.seed(seed)

  e_draw <- if (ERR_MODE == "iid_month") {
    draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  } else {
    draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool,
                   sd_row, rho_used, sigma_u)
  }

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
        control_group = did_control_group,
        allow_unbalanced_panel = TRUE,
        est_method = did_method,
        faster_mode = did_faster_mode,
        bstrap = did_bstrap,
        biters = did_biters,
        cband = FALSE,
        clustervars = "id"
      )

      att_vec <- est$att
      miss_share <- if (is.null(att_vec)) 0 else mean(is.na(att_vec))
      if (!is.finite(miss_share) || miss_share >= 0.25) {
        stop(glue("Too many missing ATT(g,t) cells: miss_share={round(miss_share,3)}"))
      }

      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)

      # ========== INSTRUMENTATION ==========

      # Check if overall.pval exists
      overall_pval_exists <- "overall.pval" %in% names(agg)

      # Check for cband/simultaneous inference
      crit_val_used <- if ("crit.val.egt" %in% names(agg)) {
        as.numeric(agg$crit.val.egt[1])
      } else if ("c" %in% names(est)) {
        as.numeric(est$c)
      } else {
        NA_real_
      }

      # Compute z-statistic
      z <- att / se

      # Compute various p-values for comparison
      p_norm <- if (is.finite(z)) 2 * pnorm(-abs(z)) else NA_real_
      p_t    <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_

      # What the simulation actually uses
      p_actual <- NA_real_
      if (isTRUE(did_bstrap) && !is.null(agg$overall.pval) && is.finite(agg$overall.pval)) {
        p_actual <- as.numeric(agg$overall.pval)
      } else {
        p_actual <- p_t
      }

      # Extract influence function for diagnostics
      inf_func_exists <- !is.null(agg$inf.function)
      inf_func_length <- if (inf_func_exists) length(agg$inf.function$simple.att) else NA_integer_

      # Check units: y_sim is in log points (log1p or log)
      # att should also be in log points (difference in logs)
      # se should be in same units as att

      list(
        ok = TRUE,
        att = att,
        se = se,
        z = z,
        p_norm = p_norm,
        p_t = p_t,
        p_actual = p_actual,
        overall_pval_exists = overall_pval_exists,
        crit_val_used = crit_val_used,
        inf_func_exists = inf_func_exists,
        inf_func_length = inf_func_length,
        n_clusters = n_states
      )
    })
  }, error = function(e) {
    list(
      ok = FALSE,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p_norm = NA_real_,
      p_t = NA_real_,
      p_actual = NA_real_,
      overall_pval_exists = FALSE,
      crit_val_used = NA_real_,
      inf_func_exists = FALSE,
      inf_func_length = NA_integer_,
      n_clusters = n_states,
      error_msg = conditionMessage(e)
    )
  })

  if (!isTRUE(out$ok) || !is.finite(out$att) || !is.finite(out$se) ||
      out$se <= 0 || !is.finite(out$p_actual)) {
    out$ok <- FALSE
  }

  out
}

# ============================================================================
# RUN NULL SIMULATIONS
# ============================================================================

cat("Configuration:\n")
cat("  OUTCOME:", OUTCOME, "\n")
cat("  n_states:", n_states, "\n")
cat("  did_bstrap:", did_bstrap, "\n")
cat("  did_biters:", did_biters, "\n")
cat("  did_control_group:", did_control_group, "\n")
cat("  ALPHA:", ALPHA, "\n\n")

N_NULL <- 200
cat("Running", N_NULL, "null simulations (effect_log = 0)...\n\n")

null_results <- vector("list", N_NULL)
seeds_null <- SEED + seq_len(N_NULL) * 10007L

for (i in seq_len(N_NULL)) {
  null_results[[i]] <- one_sim_instrumented(seeds_null[i], effect_log = 0.0)

  if (i %% 50 == 0) cat("  ... completed", i, "/", N_NULL, "\n")
}

null_df <- bind_rows(null_results)

# ============================================================================
# DIAGNOSTICS
# ============================================================================

succ <- null_df %>% filter(ok)
n_success <- nrow(succ)
n_fail <- N_NULL - n_success

cat("\n")
cat("=" %R% 70, "\n")
cat("RESULTS\n")
cat("=" %R% 70, "\n\n")

cat("Success rate:", n_success, "/", N_NULL,
    "(", round(100*n_success/N_NULL, 1), "%)\n")
cat("Failure rate:", round(100*n_fail/N_NULL, 1), "%\n\n")

if (n_success > 0) {

  # KEY DIAGNOSTIC: Check if overall.pval exists
  cat("overall.pval exists in aggte() output?",
      ifelse(any(succ$overall_pval_exists, na.rm = TRUE), "YES", "NO"), "\n")

  # Check critical value
  if (any(!is.na(succ$crit_val_used))) {
    cat("Critical value used (from did):",
        round(median(succ$crit_val_used, na.rm = TRUE), 3), "\n")
    cat("  (1.96 for normal, 2.03 for t(37), >2.5 suggests uniform bands)\n")
  }

  cat("\n")

  # ========== A) SCALE CHECK ==========
  cat("A) SCALE AND UNIT CHECK\n")
  cat("-" %R% 70, "\n")

  cat("ATT (in log points):\n")
  cat("  mean:", format(mean(succ$att, na.rm = TRUE), digits = 4), "\n")
  cat("  sd:  ", format(sd(succ$att, na.rm = TRUE), digits = 4), "\n")
  cat("  range: [", format(min(succ$att, na.rm = TRUE), digits = 4), ",",
      format(max(succ$att, na.rm = TRUE), digits = 4), "]\n\n")

  cat("SE (in log points):\n")
  cat("  mean:", format(mean(succ$se, na.rm = TRUE), digits = 4), "\n")
  cat("  sd:  ", format(sd(succ$se, na.rm = TRUE), digits = 4), "\n")
  cat("  range: [", format(min(succ$se, na.rm = TRUE), digits = 4), ",",
      format(max(succ$se, na.rm = TRUE), digits = 4), "]\n\n")

  cat("SE / sd(ATT) ratio (should be ~1 if well-calibrated):",
      format(mean(succ$se) / sd(succ$att), digits = 3), "\n\n")

  # ========== B) CHECK FOR SIMULTANEOUS/MAX TESTS ==========
  cat("B) CHECK FOR SIMULTANEOUS/UNIFORM INFERENCE\n")
  cat("-" %R% 70, "\n")

  cband_setting <- ifelse(did_bstrap, "FALSE (explicit in code)", "N/A")
  cat("cband setting:", cband_setting, "\n")
  cat("Testing single scalar (overall.att)? YES (type='simple')\n")
  cat("Any max(|t|) over event times? NO (not using type='dynamic')\n\n")

  # ========== C) Z-STATISTIC DIAGNOSTICS ==========
  cat("C) Z-STATISTIC DIAGNOSTICS\n")
  cat("-" %R% 70, "\n")

  z_vec <- succ$z[is.finite(succ$z)]

  cat("Z-statistic summary:\n")
  cat("  mean:", format(mean(z_vec), digits = 4), "\n")
  cat("  sd:  ", format(sd(z_vec), digits = 4),
      " (should be ~1.0 under null)\n")
  cat("  quantiles:\n")
  print(quantile(z_vec, c(0.05, 0.25, 0.5, 0.75, 0.95)))
  cat("\n")

  cat("|Z| exceedances:\n")
  cat("  |Z| > 1.96 (normal 5%):", sum(abs(z_vec) > 1.96), "/", length(z_vec),
      " =", round(100*mean(abs(z_vec) > 1.96), 2), "%\n")
  cat("  |Z| > 2.03 (t(37) 5%):", sum(abs(z_vec) > 2.03), "/", length(z_vec),
      " =", round(100*mean(abs(z_vec) > 2.03), 2), "%\n")
  cat("  (Expected: 5% under correct calibration)\n\n")

  # ========== D) TYPE I ERROR RATES ==========
  cat("D) TYPE I ERROR RATES\n")
  cat("-" %R% 70, "\n")

  type1_norm <- mean(succ$p_norm < ALPHA, na.rm = TRUE)
  type1_t    <- mean(succ$p_t < ALPHA, na.rm = TRUE)
  type1_actual <- mean(succ$p_actual < ALPHA, na.rm = TRUE)

  cat("Using p_norm (normal):  ", round(100*type1_norm, 2), "%\n")
  cat("Using p_t (t-dist):     ", round(100*type1_t, 2), "%\n")
  cat("Using p_actual (sim):   ", round(100*type1_actual, 2), "%\n")
  cat("Expected:                5.00%\n\n")

  # ========== E) P-VALUE DISTRIBUTION ==========
  cat("E) P-VALUE DISTRIBUTION UNDER NULL\n")
  cat("-" %R% 70, "\n")

  cat("P-value quantiles (should be Uniform[0,1]):\n")
  print(quantile(succ$p_actual, c(0.05, 0.25, 0.5, 0.75, 0.95), na.rm = TRUE))
  cat("\n")

  # ========== F) BOOTSTRAP SE INVESTIGATION ==========
  cat("F) BOOTSTRAP SE vs EMPIRICAL SD\n")
  cat("-" %R% 70, "\n")

  empirical_sd_att <- sd(succ$att, na.rm = TRUE)
  mean_bootstrap_se <- mean(succ$se, na.rm = TRUE)
  inflation_factor <- mean_bootstrap_se / empirical_sd_att

  cat("Empirical sd(ATT):       ", format(empirical_sd_att, digits = 4), "\n")
  cat("Mean bootstrap SE:       ", format(mean_bootstrap_se, digits = 4), "\n")
  cat("Inflation factor:        ", format(inflation_factor, digits = 3), "x\n")
  cat("  (Expect ~1.0; >1.5 indicates SE inflation)\n\n")

  if (inflation_factor > 1.5) {
    cat("⚠️  SE is inflated by", format(inflation_factor, digits = 2),
        "x relative to empirical SD!\n")
    cat("   This is likely due to the IQR-based bootstrap SE estimator\n")
    cat("   being upward biased with n_clusters =", n_states, "\n\n")
  }

  # ========== SHOW SAMPLE ROWS ==========
  cat("\nFirst 20 null simulations (detailed):\n")
  print(succ %>%
          select(att, se, z, p_norm, p_t, p_actual) %>%
          head(20),
        n = 20)
  cat("\n")

  # Save full results
  out_path <- file.path(OUT_DIR, "audit_null_size_instrumented.csv")
  write_csv(null_df, out_path)
  cat("Full results saved to:", out_path, "\n\n")

  # ========== ROOT CAUSE DIAGNOSIS ==========
  cat("=" %R% 70, "\n")
  cat("ROOT CAUSE DIAGNOSIS\n")
  cat("=" %R% 70, "\n\n")

  if (sd(z_vec) < 0.5) {
    cat("✓ FOUND: sd(Z) =", format(sd(z_vec), digits = 3),
        "<<< 1.0\n")
    cat("  This means SE is MASSIVELY INFLATED relative to the true variability.\n\n")

    cat("EVIDENCE:\n")
    cat("  - Empirical sd(ATT) =", format(empirical_sd_att, digits = 4), "\n")
    cat("  - Bootstrap SE =", format(mean_bootstrap_se, digits = 4), "\n")
    cat("  - Ratio =", format(inflation_factor, digits = 2), "x\n\n")

    cat("MECHANISM:\n")
    cat("  1. did::mboot() uses IQR-based estimator: bSigma = IQR(bootstrap_dist) / 1.349\n")
    cat("  2. Then SE = bSigma / sqrt(n_clusters)\n")
    cat("  3. With n_clusters =", n_states, ", the IQR estimator is upward biased\n")
    cat("  4. This causes SE to be", format(inflation_factor, digits = 2),
        "x too large\n")
    cat("  5. Z-stats are", format(inflation_factor, digits = 2),
        "x too small\n")
    cat("  6. P-values are systematically too large\n")
    cat("  7. Rejection rate collapses to ~0%\n\n")

  } else if (type1_norm > 0.04 && type1_actual < 0.01) {
    cat("✓ FOUND: p_norm gives ~5% but p_actual gives ~0%\n")
    cat("  The t-distribution or critical value is wrong.\n\n")
  } else {
    cat("⚠️  Unable to pinpoint single root cause.\n")
    cat("   Multiple issues may be compounding.\n\n")
  }

} else {
  cat("❌ ALL SIMULATIONS FAILED!\n")
  cat("Check error messages in output CSV.\n\n")
}

cat("=" %R% 70, "\n")
cat("END AUDIT\n")
cat("=" %R% 70, "\n")
