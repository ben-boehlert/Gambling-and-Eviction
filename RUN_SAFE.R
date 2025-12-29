################################################################################
# ONE-COMMAND RUNNER - CRASH-PROOF VERSION
#
# Just run: source("RUN_SAFE.R")
################################################################################

cat("\n")
cat("================================================================================\n")
cat("         CRASH-PROOF POWER ANALYSIS FOR EVICTION-GAMBLING STUDY\n")
cat("================================================================================\n\n")

cat("This script will:\n")
cat("  1. Test your R environment\n")
cat("  2. Run power analysis using base R (no tidyverse)\n")
cat("  3. Save results to CSV files\n\n")

cat("Press Ctrl+C to cancel, or wait 3 seconds to continue...\n")
Sys.sleep(3)

cat("\n--- STEP 1: ENVIRONMENT TEST ---\n\n")

# Quick environment check
tryCatch({
  source("diagnose_crash.R")
  cat("\n✓ Environment test passed\n\n")
}, error = function(e) {
  cat("\n✗ Environment test failed. Running alternative version...\n\n")
})

Sys.sleep(2)

cat("--- STEP 2: POWER ANALYSIS ---\n\n")

# Run the base R version (most stable)
tryCatch({
  source("power_analysis_NO_TIDYVERSE.R")
  cat("\n✓ Power analysis completed successfully\n\n")
}, error = function(e) {
  cat("\n✗ Power analysis failed with error:\n")
  cat(e$message, "\n\n")
  cat("Please run diagnose_crash.R to identify the problem.\n\n")
  stop("Analysis failed")
})

cat("================================================================================\n")
cat("                            ALL DONE!\n")
cat("================================================================================\n\n")
cat("Check these files for results:\n")
cat("  • power_results_base_r.csv      - Power analysis results\n")
cat("  • analysis_panel_base_r.csv     - Prepared data panel\n")
cat("  • power_analysis_base_r.RData   - Full workspace\n\n")

cat("To view results in R:\n")
cat("  results <- read.csv('power_results_base_r.csv')\n")
cat("  print(results)\n\n")
