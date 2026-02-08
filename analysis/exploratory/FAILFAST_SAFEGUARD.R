# Fail-fast safeguard for CS DiD simulation
# Add this code AFTER the main simulation loop in power_simulation_cs_statepanel_staggered_parallel_merged.R

# INSERT THIS CODE after line ~700 (after simulation loop completes)
# Before computing rejection rates

################################################################################
# FAIL-FAST SAFEGUARD
################################################################################

# Count successful simulations
n_total <- length(results)
n_success <- sum(sapply(results, function(r) isTRUE(r$ok)))
success_rate <- n_success / n_total

cat("\n")
cat("================================================================================\n")
cat("SIMULATION QUALITY CHECK\n")
cat("================================================================================\n\n")

cat("Total simulations:", n_total, "\n")
cat("Successful:", n_success, "\n")
cat("Failed:", n_total - n_success, "\n")
cat("Success rate:", sprintf("%.1f%%", 100 * success_rate), "\n\n")

# CRITICAL: If success rate is too low, stop with diagnostic information
if (success_rate < 0.95) {
  cat("================================================================================\n")
  cat("ERROR: LOW SUCCESS RATE\n")
  cat("================================================================================\n\n")

  cat("SUCCESS RATE:", sprintf("%.1f%%", 100 * success_rate), "< 95%\n\n")

  # Collect error messages
  errors <- sapply(results, function(r) {
    if (!isTRUE(r$ok) && !is.null(r$err)) {
      as.character(r$err)
    } else {
      NA_character_
    }
  })
  errors <- errors[!is.na(errors)]

  if (length(errors) > 0) {
    # Get unique error messages
    unique_errors <- unique(errors)
    error_counts <- sapply(unique_errors, function(e) sum(errors == e))

    cat("UNIQUE ERROR MESSAGES (showing up to 5):\n\n")
    for (i in seq_len(min(5, length(unique_errors)))) {
      cat("Error", i, "(occurred", error_counts[i], "times):\n")
      cat("  ", unique_errors[i], "\n\n")
    }

    # Provide diagnostic hints
    cat("================================================================================\n")
    cat("DIAGNOSTIC HINTS\n")
    cat("================================================================================\n\n")

    # Check for common errors
    if (any(grepl("argument.*y.*missing", errors, ignore.case = TRUE))) {
      cat("✗ DETECTED: fastglm 'y is missing' error\n\n")
      cat("CAUSE:\n")
      cat("  est_method=\"ipw\" or \"dr\" with xformla=~1 fails in did package\n")
      cat("  (fastglm has no formula method)\n\n")
      cat("FIX:\n")
      cat("  Set: DID_EST_METHOD=reg (or export DID_EST_METHOD=reg)\n")
      cat("  This uses regression adjustment instead of IPW\n\n")
      cat("See: FIX_OPTIONS_COMPLETE.md for details\n\n")
    }

    if (any(grepl("Too many missing ATT", errors, ignore.case = TRUE))) {
      cat("✗ DETECTED: Sparse ATT(g,t) cells\n\n")
      cat("CAUSE:\n")
      cat("  Too many missing group-time treatment effects\n")
      cat("  (insufficient overlap or small groups)\n\n")
      cat("FIX:\n")
      cat("  - Check data for small treatment groups\n")
      cat("  - Consider restricting event-time window\n")
      cat("  - Check for balanced treatment timing\n\n")
    }

    if (any(grepl("singular|rank", errors, ignore.case = TRUE))) {
      cat("✗ DETECTED: Singular covariance matrix\n\n")
      cat("CAUSE:\n")
      cat("  Perfect collinearity in fixed effects or covariates\n\n")
      cat("FIX:\n")
      cat("  - Check for singleton groups\n")
      cat("  - Verify treatment variation within groups\n\n")
    }
  }

  cat("================================================================================\n")
  cat("STOPPING SIMULATION DUE TO LOW SUCCESS RATE\n")
  cat("================================================================================\n\n")

  # Write diagnostic file
  diagnostic_file <- file.path(OUT_DIR, "SIMULATION_FAILURE_DIAGNOSTIC.txt")
  sink(diagnostic_file)
  cat("SIMULATION FAILURE DIAGNOSTIC\n")
  cat("Generated:", Sys.time(), "\n\n")
  cat("Success rate:", sprintf("%.1f%%", 100 * success_rate), "\n")
  cat("Total sims:", n_total, "\n")
  cat("Failed sims:", n_total - n_success, "\n\n")
  cat("Unique errors:\n\n")
  for (i in seq_along(unique_errors)) {
    cat(i, ". (", error_counts[i], " occurrences)\n", sep = "")
    cat("   ", unique_errors[i], "\n\n", sep = "")
  }
  sink()

  cat("Diagnostic saved to:", diagnostic_file, "\n")

  stop("Simulation failed: success rate < 95%. Check diagnostic file for details.")
}

# If all simulations failed (0% success)
if (n_success == 0) {
  cat("================================================================================\n")
  cat("CRITICAL ERROR: ALL SIMULATIONS FAILED\n")
  cat("================================================================================\n\n")

  cat("No successful simulations out of", n_total, "attempts\n\n")
  cat("This typically indicates:\n")
  cat("  1. Wrong est_method (use \"reg\" not \"ipw\" with xformla=~1)\n")
  cat("  2. Data file not found or corrupted\n")
  cat("  3. Incompatible package versions\n\n")

  stop("All simulations failed. See error messages above.")
}

cat("✓ Success rate is acceptable (", sprintf("%.1f%%", 100 * success_rate), ")\n", sep = "")
cat("Proceeding with analysis...\n\n")

################################################################################
# END FAIL-FAST SAFEGUARD
################################################################################
