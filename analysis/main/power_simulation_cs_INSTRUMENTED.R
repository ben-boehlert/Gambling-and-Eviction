#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_INSTRUMENTED.R
#
# INSTRUMENTED version of one_sim() to diagnose why size ~= 0%
# Run with: DIAG=TRUE Rscript power_simulation_cs_INSTRUMENTED.R
################################################################################

# Source the original simulation
source("power_simulation_cs_statepanel_staggered_parallel_merged.R",
       echo = FALSE, verbose = FALSE)

# ============================================================================
# INSTRUMENTED VERSION OF one_sim
# ============================================================================

one_sim_instrumented <- function(seed, effect_log) {
  set.seed(seed)

  e_draw <- if (ERR_MODE == "iid_month") {
    draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  } else {
    draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool, sd_row, rho_used, sigma_u)
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

      # ========== INSTRUMENTATION START ==========

      # Extract ATT(g,t) vector
      attgt_vec <- NULL
      if (!is.null(est$att)) attgt_vec <- est$att
      if (!is.null(est$attgt)) attgt_vec <- est$attgt

      miss_share <- if (is.null(attgt_vec)) NA_real_ else mean(is.na(attgt_vec))
      n_attgt_non_na <- if (is.null(attgt_vec)) NA_integer_ else sum(!is.na(attgt_vec))
      n_attgt_total <- if (is.null(attgt_vec)) NA_integer_ else length(attgt_vec)

      # Check for critical value
      crit_val <- if (!is.null(est$c)) as.numeric(est$c) else NA_real_

      # Check current miss_share validation
      if (!is.finite(miss_share) || miss_share >= 0.25) {
        stop(glue("Too many missing ATT(g,t) cells: miss_share={round(miss_share,3)}"))
      }

      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)

      # Check if overall.pval exists
      overall_pval_exists <- "overall.pval" %in% names(agg)
      overall_pval_value <- if (overall_pval_exists && !is.null(agg$overall.pval)) {
        as.numeric(agg$overall.pval)
      } else {
        NA_real_
      }

      # Compute z and p
      z <- att / se
      p_t <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_
      p_norm <- if (is.finite(z)) 2 * pnorm(-abs(z)) else NA_real_

      # What p is actually used
      p_actual <- NA_real_
      if (isTRUE(did_bstrap) && !is.null(agg$overall.pval) && is.finite(agg$overall.pval)) {
        p_actual <- as.numeric(agg$overall.pval)
      } else {
        p_actual <- p_t
      }

      # ========== INSTRUMENTATION END ==========

      list(
        ok = TRUE,
        seed = seed,
        effect_log = effect_log,
        att = att,
        se = se,
        z = z,
        p_t = p_t,
        p_norm = p_norm,
        p_actual = p_actual,
        overall_pval_exists = overall_pval_exists,
        overall_pval_value = overall_pval_value,
        miss_share = miss_share,
        n_attgt_non_na = n_attgt_non_na,
        n_attgt_total = n_attgt_total,
        crit_val = crit_val,
        n_clusters = n_states
      )
    })
  }, error = function(e) {
    list(
      ok = FALSE,
      seed = seed,
      effect_log = effect_log,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p_t = NA_real_,
      p_norm = NA_real_,
      p_actual = NA_real_,
      overall_pval_exists = FALSE,
      overall_pval_value = NA_real_,
      miss_share = NA_real_,
      n_attgt_non_na = NA_integer_,
      n_attgt_total = NA_integer_,
      crit_val = NA_real_,
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
# RUN INSTRUMENTED SIMULATION (effect=0 only)
# ============================================================================

N_DIAG <- 500  # Run 500 null simulations
DIAG_SEED <- 999000

cat("=" %R% 80, "\n")
cat("INSTRUMENTED CS SIMULATION (effect = 0)\n")
cat("=" %R% 80, "\n\n")

cat("Configuration:\n")
cat("  n_states:", n_states, "\n")
cat("  did_bstrap:", did_bstrap, "\n")
cat("  did_biters:", did_biters, "\n")
cat("  did_control_group:", did_control_group, "\n")
cat("  did_method:", did_method, "\n")
cat("  ERR_MODE:", ERR_MODE, "\n")
cat("  N_DIAG:", N_DIAG, "\n\n")

cat("Running", N_DIAG, "null simulations...\n\n")

diag_results <- vector("list", N_DIAG)
diag_seeds <- DIAG_SEED + seq_len(N_DIAG) * 17

for (i in seq_len(N_DIAG)) {
  diag_results[[i]] <- one_sim_instrumented(diag_seeds[i], effect_log = 0.0)

  if (i %% 100 == 0) cat("  ... completed", i, "/", N_DIAG, "\n")
}

diag_df <- bind_rows(diag_results)

# Save full results
diag_path <- file.path(OUT_DIR, "diag_instrumented_null.csv")
write_csv(diag_df, diag_path)
cat("\nFull results saved to:", diag_path, "\n\n")

# ============================================================================
# DIAGNOSTIC SUMMARY
# ============================================================================

succ <- diag_df %>% filter(ok)
n_success <- nrow(succ)
n_fail <- N_DIAG - n_success

cat("=" %R% 80, "\n")
cat("DIAGNOSTIC SUMMARY\n")
cat("=" %R% 80, "\n\n")

cat("Success rate:", n_success, "/", N_DIAG,
    "(", round(100*n_success/N_DIAG, 1), "%)\n")
cat("Failure rate:", round(100*n_fail/N_DIAG, 1), "%\n\n")

if (n_success > 0) {

  # ========== KEY STATISTICS ==========

  cat("KEY STATISTICS (effect=0):\n")
  cat("-" %R% 80, "\n")

  type1_t <- mean(succ$p_t < 0.05, na.rm = TRUE)
  type1_norm <- mean(succ$p_norm < 0.05, na.rm = TRUE)
  type1_actual <- mean(succ$p_actual < 0.05, na.rm = TRUE)

  mean_att <- mean(succ$att, na.rm = TRUE)
  sd_att <- sd(succ$att, na.rm = TRUE)
  mean_se <- mean(succ$se, na.rm = TRUE)
  sd_se <- sd(succ$se, na.rm = TRUE)
  se_inflation <- mean_se / sd_att
  sd_z <- sd(succ$z, na.rm = TRUE)

  cat("Type I Error Rates:\n")
  cat("  Using p_t (t-dist):    ", sprintf("%.2f%%", 100*type1_t), "\n")
  cat("  Using p_norm (normal): ", sprintf("%.2f%%", 100*type1_norm), "\n")
  cat("  Using p_actual (sim):  ", sprintf("%.2f%%", 100*type1_actual), "\n")
  cat("  Expected:               5.00%\n\n")

  cat("ATT Statistics:\n")
  cat("  mean(ATT): ", format(mean_att, digits = 5), "\n")
  cat("  sd(ATT):   ", format(sd_att, digits = 5), "\n\n")

  cat("SE Statistics:\n")
  cat("  mean(SE):  ", format(mean_se, digits = 5), "\n")
  cat("  sd(SE):    ", format(sd_se, digits = 5), "\n\n")

  cat("SE Inflation:\n")
  cat("  mean(SE) / sd(ATT): ", format(se_inflation, digits = 3), "x\n")
  cat("  (Expect ~1.0 if well-calibrated)\n\n")

  cat("Z-Statistic:\n")
  cat("  sd(Z): ", format(sd_z, digits = 4), "\n")
  cat("  (Expect ~1.0 under null)\n\n")

  # ========== ATT(g,t) CELL DIAGNOSTICS ==========

  cat("ATT(g,t) Cell Diagnostics:\n")
  cat("-" %R% 80, "\n")

  cat("  mean(miss_share):     ", format(mean(succ$miss_share, na.rm = TRUE), digits = 3), "\n")
  cat("  median(miss_share):   ", format(median(succ$miss_share, na.rm = TRUE), digits = 3), "\n")
  cat("  mean(n_attgt_non_na): ", format(mean(succ$n_attgt_non_na, na.rm = TRUE), digits = 1), "\n")
  cat("  mean(n_attgt_total):  ", format(mean(succ$n_attgt_total, na.rm = TRUE), digits = 1), "\n\n")

  # ========== CRITICAL VALUE ==========

  cat("Critical Value:\n")
  cat("-" %R% 80, "\n")

  if (any(!is.na(succ$crit_val))) {
    cat("  median(crit_val): ", format(median(succ$crit_val, na.rm = TRUE), digits = 4), "\n")
    cat("  (1.96 for normal pointwise, >2.5 suggests uniform)\n\n")
  } else {
    cat("  crit_val: NA (not available)\n\n")
  }

  cat("overall.pval exists? ", ifelse(any(succ$overall_pval_exists), "YES", "NO"), "\n\n")

  # ========== Z AND P QUANTILES ==========

  cat("Z-Statistic Quantiles:\n")
  cat("-" %R% 80, "\n")
  print(quantile(succ$z, c(0.05, 0.25, 0.5, 0.75, 0.95), na.rm = TRUE))
  cat("\n")

  cat("|Z| Exceedances:\n")
  z_abs <- abs(succ$z)
  cat("  |Z| > 1.96: ", sum(z_abs > 1.96, na.rm = TRUE), "/", sum(!is.na(z_abs)),
      " = ", sprintf("%.2f%%", 100*mean(z_abs > 1.96, na.rm = TRUE)), "\n")
  cat("  |Z| > 2.03: ", sum(z_abs > 2.03, na.rm = TRUE), "/", sum(!is.na(z_abs)),
      " = ", sprintf("%.2f%%", 100*mean(z_abs > 2.03, na.rm = TRUE)), "\n")
  cat("  (Expected: ~5%)\n\n")

  cat("P-Value Quantiles (should be Uniform[0,1] under null):\n")
  cat("-" %R% 80, "\n")
  print(quantile(succ$p_actual, c(0.05, 0.25, 0.5, 0.75, 0.95), na.rm = TRUE))
  cat("\n\n")

  # ========== DIAGNOSIS ==========

  cat("=" %R% 80, "\n")
  cat("DIAGNOSIS\n")
  cat("=" %R% 80, "\n\n")

  if (sd_z < 0.6) {
    cat("✗ PROBLEM DETECTED: sd(Z) =", format(sd_z, digits = 3), "<< 1.0\n")
    cat("  → SEs are INFLATED relative to sampling variation\n\n")
  }

  if (se_inflation > 1.5) {
    cat("✗ PROBLEM DETECTED: SE inflation =", format(se_inflation, digits = 2), "x\n")
    cat("  → mean(SE) >> sd(ATT)\n\n")
  }

  if (type1_actual < 0.01) {
    cat("✗ PROBLEM DETECTED: Type I error =", sprintf("%.2f%%", 100*type1_actual), "<< 5%\n")
    cat("  → Test is severely under-rejecting\n\n")
  }

  if (mean(succ$miss_share, na.rm = TRUE) > 0.2) {
    cat("⚠  WARNING: mean(miss_share) =", format(mean(succ$miss_share, na.rm = TRUE), digits = 2), "\n")
    cat("  → Many ATT(g,t) cells are missing\n\n")
  }

  cat("\nSUMMARY TABLE:\n")
  summary_tbl <- tibble(
    metric = c("Type I Error (%)", "mean(SE) / sd(ATT)", "sd(Z)", "mean(miss_share)"),
    value = c(
      100*type1_actual,
      se_inflation,
      sd_z,
      mean(succ$miss_share, na.rm = TRUE)
    ),
    expected = c(5.0, 1.0, 1.0, NA),
    status = c(
      ifelse(abs(type1_actual - 0.05) < 0.02, "✓", "✗"),
      ifelse(abs(se_inflation - 1.0) < 0.2, "✓", "✗"),
      ifelse(abs(sd_z - 1.0) < 0.1, "✓", "✗"),
      ifelse(mean(succ$miss_share, na.rm = TRUE) < 0.1, "✓", "⚠")
    )
  )
  print(summary_tbl, n = Inf)
  cat("\n")

} else {
  cat("✗ ALL SIMULATIONS FAILED\n\n")
}

cat("=" %R% 80, "\n")
cat("END DIAGNOSTIC\n")
cat("=" %R% 80, "\n")
