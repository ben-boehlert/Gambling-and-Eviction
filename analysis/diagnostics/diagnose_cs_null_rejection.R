#!/usr/bin/env Rscript
################################################################################
# diagnose_cs_null_rejection.R
#
# Forensic diagnostic: log z, p_norm, p_t, p_did under the null
# to identify why rejection rate is ~0%
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

set.seed(20260112)

# Load main simulation script environment (without running full sim)
source("power_simulation_cs_statepanel_staggered_parallel_merged.R", echo = FALSE)

cat("=== CS NULL REJECTION DIAGNOSTIC ===\n\n")
cat("Configuration:\n")
cat("  n_states:", n_states, "\n")
cat("  did_bstrap:", did_bstrap, "\n")
cat("  did_biters:", did_biters, "\n")
cat("  did_control_group:", did_control_group, "\n")
cat("  ALPHA:", ALPHA, "\n\n")

# Run small batch of null simulations
N_DIAG <- 100
cat("Running", N_DIAG, "null simulations (effect = 0)...\n\n")

diag_results <- vector("list", N_DIAG)

for (i in seq_len(N_DIAG)) {
  seed_i <- 999000 + i * 17

  # Run one_sim at effect=0
  res <- one_sim(seed = seed_i, effect_log = 0.0)

  if (isTRUE(res$ok)) {
    att <- res$att
    se <- res$se
    p_did <- res$p

    z <- att / se
    p_norm <- if (is.finite(z)) 2 * pnorm(-abs(z)) else NA_real_
    p_t <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_

    # Implied critical value multiplier (assuming normal)
    # p = 2*pnorm(-abs(z/k)) => k = abs(z) / qnorm(1 - p/2)
    k_implied <- if (is.finite(p_did) && p_did > 0 && p_did < 1) {
      abs(z) / qnorm(1 - p_did/2)
    } else {
      NA_real_
    }

    diag_results[[i]] <- tibble(
      sim = i,
      success = TRUE,
      att = att,
      se = se,
      z = z,
      p_norm = p_norm,
      p_t = p_t,
      p_did = p_did,
      k_implied = k_implied
    )
  } else {
    diag_results[[i]] <- tibble(
      sim = i,
      success = FALSE,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p_norm = NA_real_,
      p_t = NA_real_,
      p_did = NA_real_,
      k_implied = NA_real_
    )
  }

  if (i %% 20 == 0) cat("  ... completed", i, "/", N_DIAG, "\n")
}

diag_df <- bind_rows(diag_results)

# Summary statistics
n_success <- sum(diag_df$success, na.rm = TRUE)
n_fail <- N_DIAG - n_success
fail_rate <- n_fail / N_DIAG

cat("\n=== RESULTS ===\n\n")
cat("Success rate:", n_success, "/", N_DIAG, "(", round(100*(1-fail_rate), 1), "%)\n")
cat("Failure rate:", round(100*fail_rate, 1), "%\n\n")

succ <- diag_df %>% filter(success)

if (nrow(succ) > 0) {
  cat("Type I error rates (conditional on success):\n")
  cat("  Using p_norm : ", round(100 * mean(succ$p_norm < ALPHA, na.rm = TRUE), 2), "%\n")
  cat("  Using p_t    : ", round(100 * mean(succ$p_t < ALPHA, na.rm = TRUE), 2), "%\n")
  cat("  Using p_did  : ", round(100 * mean(succ$p_did < ALPHA, na.rm = TRUE), 2), "%\n\n")

  cat("P-value summary (successful sims):\n")
  print(summary(succ %>% select(p_norm, p_t, p_did)))
  cat("\n")

  cat("Z-statistic summary:\n")
  print(summary(succ$z))
  cat("\n")

  cat("Implied critical value multiplier k (if p_did = 2*pnorm(-|z|/k)):\n")
  print(summary(succ$k_implied))
  cat("\n")

  # Check if p_did matches p_norm or p_t
  cor_norm <- cor(succ$p_norm, succ$p_did, use = "complete.obs")
  cor_t <- cor(succ$p_t, succ$p_did, use = "complete.obs")

  cat("Correlation:\n")
  cat("  cor(p_norm, p_did):", round(cor_norm, 4), "\n")
  cat("  cor(p_t, p_did)   :", round(cor_t, 4), "\n\n")

  # Show first 20 rows
  cat("First 20 successful simulations:\n")
  print(head(succ %>% select(sim, att, se, z, p_norm, p_t, p_did, k_implied), 20), n = 20)
  cat("\n")
}

# Save full results
out_path <- file.path(OUT_DIR, "diagnostic_null_rejection.csv")
write_csv(diag_df, out_path)
cat("Full results saved to:", out_path, "\n")

cat("\n=== END DIAGNOSTIC ===\n")
