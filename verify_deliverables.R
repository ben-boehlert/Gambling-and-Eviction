#!/usr/bin/env Rscript
################################################################################
# verify_deliverables.R
#
# Verification script to check all CS-DiD deliverables are in place
# Run this before paper submission to ensure everything is ready
################################################################################

cat("\n")
cat("================================================================================\n")
cat("CS-DiD DELIVERABLES VERIFICATION\n")
cat("================================================================================\n\n")

# Initialize counters
n_pass <- 0
n_fail <- 0
n_warn <- 0

check_file <- function(path, description, required = TRUE) {
  if (file.exists(path)) {
    size <- file.info(path)$size
    size_kb <- round(size / 1024, 1)
    cat(sprintf("✓ %s\n", description))
    cat(sprintf("  Path: %s\n", path))
    cat(sprintf("  Size: %.1f KB\n\n", size_kb))
    n_pass <<- n_pass + 1
    return(TRUE)
  } else {
    if (required) {
      cat(sprintf("✗ MISSING: %s\n", description))
      cat(sprintf("  Expected: %s\n\n", path))
      n_fail <<- n_fail + 1
    } else {
      cat(sprintf("⚠ OPTIONAL: %s not found\n", description))
      cat(sprintf("  Path: %s\n\n", path))
      n_warn <<- n_warn + 1
    }
    return(FALSE)
  }
}

check_loadable <- function(path, description) {
  if (!file.exists(path)) {
    cat(sprintf("✗ CANNOT CHECK: %s (file not found)\n", description))
    cat(sprintf("  Path: %s\n\n", path))
    n_fail <<- n_fail + 1
    return(FALSE)
  }

  tryCatch({
    source(path)
    cat(sprintf("✓ %s loads without errors\n", description))
    cat(sprintf("  Path: %s\n\n", path))
    n_pass <<- n_pass + 1
    return(TRUE)
  }, error = function(e) {
    cat(sprintf("✗ ERROR loading %s\n", description))
    cat(sprintf("  Path: %s\n", path))
    cat(sprintf("  Error: %s\n\n", e$message))
    n_fail <<- n_fail + 1
    return(FALSE)
  })
}

# ========================================================================
# 1. Core Patch Files
# ========================================================================

cat("1. CORE PATCH FILES\n")
cat("-------------------\n")

check_loadable("patches/preflight_support_check.R", "Preflight support check")
check_loadable("patches/att_gt_safe.R", "Safe CS-DiD wrapper")
check_loadable("patches/reg_did_rc_safe.R", "Patched DRDID function")
check_loadable("patches/plot_csdid_pretrends.R", "Pre-trends plotting functions")

# ========================================================================
# 2. Documentation Files
# ========================================================================

cat("2. DOCUMENTATION FILES\n")
cat("----------------------\n")

check_file("patches/CSDID_FIX_IMPLEMENTATION.md", "Technical documentation")
check_file("patches/README_PRETRENDS.md", "Plotting guide")
check_file("patches/FIND_YOUR_OUTPUTS.md", "Output location guide")
check_file("OUTPUT_SUMMARY.md", "Complete guide with examples")
check_file("QUICK_START.md", "Quick start guide")
check_file("FINAL_DELIVERABLES_SUMMARY.md", "Final deliverables summary")
check_file("PAPER_CHECKLIST.md", "Paper submission checklist")
check_file("CSDID_STATE_COUNT.txt", "State count documentation", required = FALSE)

# ========================================================================
# 3. Support Diagnostics (Critical for Paper)
# ========================================================================

cat("3. SUPPORT DIAGNOSTICS\n")
cat("----------------------\n")

if (check_file("output/csdid_debug/support_diagnostics_full.csv",
               "Full support diagnostics table (875 rows)")) {

  # Load and verify
  support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

  cat("  Verifying contents...\n")

  # Check row count
  if (nrow(support) == 875) {
    cat(sprintf("  ✓ Row count: %d (expected 875)\n", nrow(support)))
    n_pass <- n_pass + 1
  } else {
    cat(sprintf("  ✗ Row count: %d (expected 875)\n", nrow(support)))
    n_fail <- n_fail + 1
  }

  # Check columns
  required_cols <- c("g", "t", "n_treat_pre", "n_treat_post",
                     "n_control_pre", "n_control_post", "identifiable", "reason")
  missing_cols <- setdiff(required_cols, names(support))

  if (length(missing_cols) == 0) {
    cat("  ✓ All required columns present\n")
    n_pass <- n_pass + 1
  } else {
    cat(sprintf("  ✗ Missing columns: %s\n", paste(missing_cols, collapse = ", ")))
    n_fail <- n_fail + 1
  }

  # Report statistics
  n_identifiable <- sum(support$identifiable)
  n_nonidentifiable <- sum(!support$identifiable)
  pct_identifiable <- 100 * mean(support$identifiable)

  cat(sprintf("  Total cells: %d\n", nrow(support)))
  cat(sprintf("  Identifiable: %d (%.1f%%)\n", n_identifiable, pct_identifiable))
  cat(sprintf("  Non-identifiable: %d (%.1f%%)\n\n",
              n_nonidentifiable, 100 - pct_identifiable))

  # Check expected values
  if (n_identifiable == 338 && n_nonidentifiable == 537) {
    cat("  ✓ Cell counts match expected values (338/537)\n\n")
    n_pass <- n_pass + 1
  } else {
    cat("  ⚠ Cell counts differ from expected (338/537)\n")
    cat("    This may be OK if you reran analysis with different parameters\n\n")
    n_warn <- n_warn + 1
  }
}

check_file("output/csdid_plots/summary_statistics.csv", "Summary statistics table")
check_file("output/csdid_plots/non_identifiable_reasons.csv", "Non-identifiable reasons")

# ========================================================================
# 4. Publication-Quality Plots
# ========================================================================

cat("4. PUBLICATION-QUALITY PLOTS\n")
cat("----------------------------\n")

check_file("output/csdid_plots/support_heatmap.pdf", "Support heatmap (PDF)")
check_file("output/csdid_plots/support_heatmap.png", "Support heatmap (PNG)")
check_file("output/csdid_plots/identifiability_by_event_time.pdf",
           "Identifiability by event time (PDF)")
check_file("output/csdid_plots/identifiability_by_event_time.png",
           "Identifiability by event time (PNG)")
check_file("output/csdid_plots/identifiability_by_group.pdf",
           "Identifiability by group (PDF)")
check_file("output/csdid_plots/identifiability_by_group.png",
           "Identifiability by group (PNG)")
check_file("output/csdid_plots/cell_counts_distribution.pdf",
           "Cell counts distribution (PDF)")
check_file("output/csdid_plots/cell_counts_distribution.png",
           "Cell counts distribution (PNG)")

# ========================================================================
# 5. Test Suite
# ========================================================================

cat("5. TEST SUITE\n")
cat("-------------\n")

check_file("patches/test_att_gt_safe_regression.R", "Regression tests")
check_file("patches/EXAMPLE_FULL_WORKFLOW.R", "Example workflow")

# ========================================================================
# 6. Plotting Script
# ========================================================================

cat("6. PLOTTING SCRIPT\n")
cat("------------------\n")

check_file("scripts/generate_support_plots.R", "Support plots generation script")

# ========================================================================
# 7. Optional: Analysis Results (if you've run full analysis)
# ========================================================================

cat("7. ANALYSIS RESULTS (OPTIONAL)\n")
cat("------------------------------\n")

check_file("output/my_csdid/cs_result.rds", "CS-DiD results object", required = FALSE)
check_file("output/my_csdid/agg_simple.rds", "Simple aggregate", required = FALSE)
check_file("output/my_csdid/agg_dynamic.rds", "Dynamic aggregate", required = FALSE)
check_file("output/my_csdid/figures/event_study.pdf", "Event study plot", required = FALSE)
check_file("output/my_csdid/figures/pretrends_test.pdf", "Pre-trends test plot", required = FALSE)

# ========================================================================
# Summary
# ========================================================================

cat("\n")
cat("================================================================================\n")
cat("VERIFICATION SUMMARY\n")
cat("================================================================================\n\n")

cat(sprintf("✓ Passed:  %d\n", n_pass))
cat(sprintf("✗ Failed:  %d\n", n_fail))
cat(sprintf("⚠ Warnings: %d\n\n", n_warn))

if (n_fail == 0) {
  cat("🎉 ALL REQUIRED DELIVERABLES PRESENT\n\n")
  cat("You are ready to use these materials in your paper!\n\n")
  cat("Next steps:\n")
  cat("1. Review PAPER_CHECKLIST.md for paper components\n")
  cat("2. Include support diagnostics in Appendix Table A1\n")
  cat("3. Include plots in appendix figures\n")
  cat("4. Add methods section language (see FINAL_DELIVERABLES_SUMMARY.md)\n\n")
} else {
  cat("⚠ SOME REQUIRED FILES ARE MISSING\n\n")
  cat("Please check the items marked with ✗ above.\n")
  cat("Refer to FINAL_DELIVERABLES_SUMMARY.md for complete file list.\n\n")
}

cat("================================================================================\n\n")

# Return exit code
if (n_fail > 0) {
  quit(status = 1)
} else {
  quit(status = 0)
}
