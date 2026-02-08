#!/usr/bin/env Rscript
################################################################################
# debug_cs_null_size.R
#
# Forensic diagnostic: prove why null rejection rate is ~0%
# by comparing p_did vs p_norm vs p_t under the null
################################################################################

suppressPackageStartupMessages({
  library(did)
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
})

# Load simulation environment to get panel data
cat("Loading simulation environment...\n")
source("power_simulation_cs_statepanel_staggered_parallel_merged.R",
       echo = FALSE, verbose = FALSE)

cat("\n=== CS NULL SIZE DIAGNOSTIC ===\n\n")
cat("Configuration from main sim:\n")
cat("  n_states:", n_states, "\n")
cat("  did_bstrap:", did_bstrap, "\n")
cat("  did_biters:", did_biters, "\n")
cat("  did_control_group:", did_control_group, "\n")
cat("  ALPHA:", ALPHA, "\n\n")

diag_pvals <- function(att, se, p_did, n_clusters) {
  z <- att / se
  p_norm <- if (is.finite(z)) 2 * pnorm(-abs(z)) else NA_real_
  p_t    <- if (is.finite(z)) 2 * pt(-abs(z), df = n_clusters - 1) else NA_real_

  # implied multiplier if p_did behaves like inflated Normal test
  k_norm <- NA_real_
  if (is.finite(z) && is.finite(p_did) && p_did > 0 && p_did < 1) {
    q <- qnorm(1 - p_did/2)
    if (is.finite(q) && q > 0) k_norm <- abs(z) / q
  }

  tibble(att = att, se = se, z = z,
         p_did = p_did, p_norm = p_norm, p_t = p_t,
         k_norm = k_norm)
}

one_null_rep <- function(seed, df_sim,
                         biters = 199, cband = FALSE,
                         control_group = "nevertreated") {
  set.seed(seed)

  # Count clusters
  n_clusters <- n_distinct(df_sim$id)

  tryCatch({
    suppressWarnings({
      # Run CS estimation
      mp <- att_gt(
        yname = "y",
        tname = "t",
        idname = "id",
        gname = "g",
        xformla = ~ 1,
        data = df_sim,
        panel = TRUE,
        control_group = control_group,
        allow_unbalanced_panel = TRUE,
        est_method = "ipw",
        faster_mode = FALSE,
        bstrap = TRUE,
        biters = biters,
        clustervars = "id",
        cband = cband
      )

      # Aggregate
      agg <- aggte(mp, type = "simple", na.rm = TRUE)

      # Extract estimand
      att   <- as.numeric(agg$overall.att)
      se    <- as.numeric(agg$overall.se)

      # CHECK IF overall.pval EXISTS
      p_did <- if ("overall.pval" %in% names(agg) && !is.null(agg$overall.pval)) {
        as.numeric(agg$overall.pval)
      } else {
        # Fallback: compute manually
        z_manual <- att / se
        if (is.finite(z_manual)) {
          2 * pt(-abs(z_manual), df = n_clusters - 1)
        } else {
          NA_real_
        }
      }

      out <- diag_pvals(att, se, p_did, n_clusters)
      out$success <- TRUE
      out$overall_pval_exists <- "overall.pval" %in% names(agg)
      out
    })
  }, error = function(e) {
    tibble(
      success = FALSE,
      overall_pval_exists = NA,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p_did = NA_real_,
      p_norm = NA_real_,
      p_t = NA_real_,
      k_norm = NA_real_,
      error_msg = conditionMessage(e)
    )
  })
}

run_null_size <- function(B = 100, seed0 = 999000,
                          biters = 199, cband = FALSE,
                          control_group = "nevertreated") {

  cat("\nRunning", B, "null simulations with:\n")
  cat("  biters =", biters, "\n")
  cat("  cband =", cband, "\n")
  cat("  control_group =", control_group, "\n\n")

  results <- vector("list", B)

  for (b in seq_len(B)) {
    seed_b <- seed0 + b * 17

    # Generate null data (effect = 0)
    set.seed(seed_b)

    e_draw <- if (ERR_MODE == "iid_month") {
      draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
    } else {
      draw_errors_ar1(panel$t, idx_by_id, std_pool_by_t, std_global_pool,
                     sd_row, rho_used, sigma_u)
    }

    y_sim <- panel$yhat + e_draw  # NO treatment effect

    df_sim <- data.frame(
      id = panel$id,
      t  = panel$t,
      g  = panel$g,
      y  = y_sim
    )

    # Run one rep
    results[[b]] <- one_null_rep(
      seed = seed_b,
      df_sim = df_sim,
      biters = biters,
      cband = cband,
      control_group = control_group
    )

    if (b %% 20 == 0) cat("  ... completed", b, "/", B, "\n")
  }

  bind_rows(results)
}

# ============================================================================
# RUN DIAGNOSTICS
# ============================================================================

cat("=" x 70, "\n", sep = "")
cat("TEST A: cband=FALSE (pointwise inference)\n")
cat("=" x 70, "\n", sep = "")

outA <- run_null_size(B = 100, biters = 199, cband = FALSE)

summA <- outA %>%
  filter(success) %>%
  summarise(
    n = n(),
    n_success = sum(success, na.rm = TRUE),
    fail_rate = mean(!success),
    overall_pval_exists_ever = any(overall_pval_exists, na.rm = TRUE),
    type1_did  = mean(p_did  < 0.05, na.rm = TRUE),
    type1_norm = mean(p_norm < 0.05, na.rm = TRUE),
    type1_t    = mean(p_t    < 0.05, na.rm = TRUE),
    median_p_did = median(p_did, na.rm = TRUE),
    median_p_norm = median(p_norm, na.rm = TRUE),
    median_p_t = median(p_t, na.rm = TRUE),
    median_k_norm = median(k_norm, na.rm = TRUE),
    mean_att = mean(att, na.rm = TRUE),
    sd_att = sd(att, na.rm = TRUE),
    mean_se = mean(se, na.rm = TRUE),
    se_inflation = mean_se / sd_att
  )

cat("\n")
cat("RESULTS (cband=FALSE):\n")
print(summA)
cat("\n")

# Save detailed results
out_path_A <- file.path(OUT_DIR, "diagnostic_null_size_cbandFALSE.csv")
write_csv(outA, out_path_A)
cat("Detailed results saved to:", out_path_A, "\n\n")

cat("=" x 70, "\n", sep = "")
cat("TEST B: cband=TRUE (uniform confidence bands)\n")
cat("=" x 70, "\n", sep = "")

outB <- run_null_size(B = 100, biters = 199, cband = TRUE)

summB <- outB %>%
  filter(success) %>%
  summarise(
    n = n(),
    n_success = sum(success, na.rm = TRUE),
    fail_rate = mean(!success),
    overall_pval_exists_ever = any(overall_pval_exists, na.rm = TRUE),
    type1_did  = mean(p_did  < 0.05, na.rm = TRUE),
    type1_norm = mean(p_norm < 0.05, na.rm = TRUE),
    type1_t    = mean(p_t    < 0.05, na.rm = TRUE),
    median_p_did = median(p_did, na.rm = TRUE),
    median_p_norm = median(p_norm, na.rm = TRUE),
    median_p_t = median(p_t, na.rm = TRUE),
    median_k_norm = median(k_norm, na.rm = TRUE),
    mean_att = mean(att, na.rm = TRUE),
    sd_att = sd(att, na.rm = TRUE),
    mean_se = mean(se, na.rm = TRUE),
    se_inflation = mean_se / sd_att
  )

cat("\n")
cat("RESULTS (cband=TRUE):\n")
print(summB)
cat("\n")

# Save detailed results
out_path_B <- file.path(OUT_DIR, "diagnostic_null_size_cbandTRUE.csv")
write_csv(outB, out_path_B)
cat("Detailed results saved to:", out_path_B, "\n\n")

# ============================================================================
# SUMMARY COMPARISON
# ============================================================================

cat("=" x 70, "\n", sep = "")
cat("COMPARISON SUMMARY\n")
cat("=" x 70, "\n", sep = "")

comparison <- bind_rows(
  summA %>% mutate(setting = "cband=FALSE"),
  summB %>% mutate(setting = "cband=TRUE")
) %>%
  select(setting, n_success, overall_pval_exists_ever,
         type1_did, type1_norm, type1_t,
         median_k_norm, se_inflation)

print(comparison)
cat("\n")

cat("=" x 70, "\n", sep = "")
cat("KEY FINDINGS\n")
cat("=" x 70, "\n", sep = "")

if (!summA$overall_pval_exists_ever && !summB$overall_pval_exists_ever) {
  cat("\n❌ CRITICAL: overall.pval DOES NOT EXIST in aggte() output!\n")
  cat("   The simulation is using the fallback: p = 2*pt(-abs(z), df=n_states-1)\n\n")
}

cat("SE Inflation Factor:\n")
cat("  cband=FALSE: ", round(summA$se_inflation, 2), "x\n", sep = "")
cat("  cband=TRUE:  ", round(summB$se_inflation, 2), "x\n", sep = "")
cat("\n")

cat("Type I Error Rates:\n")
cat("  cband=FALSE: type1_t =", round(100*summA$type1_t, 2), "%\n")
cat("  cband=TRUE:  type1_t =", round(100*summB$type1_t, 2), "%\n")
cat("\n")

if (summA$median_k_norm > 1.5) {
  cat("⚠️  median_k_norm =", round(summA$median_k_norm, 2),
      ">> 1 suggests simultaneous/sup-t adjustment\n")
}

cat("\n=== END DIAGNOSTIC ===\n")
