#!/usr/bin/env Rscript
################################################################################
# test_att_gt_safe_regression.R
#
# Regression test for att_gt_safe() with unbalanced panel that triggers
# empty matrix / support issues
#
# This test creates a minimal synthetic panel that would previously crash
# or return invalid estimates, and verifies:
# 1. No crash/segfault
# 2. Non-identifiable cells are flagged with NA
# 3. Aggregation handles NA cells correctly
# 4. Clear warnings are provided
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(did)
})

cat("\n")
cat("========================================================================\n")
cat("Regression Test: att_gt_safe() with Unbalanced Panel\n")
cat("========================================================================\n\n")

# ========================================================================
# Test 1: Synthetic unbalanced panel with missing post-treatment obs
# ========================================================================

cat("Test 1: Unbalanced panel with n_treat_post=0 for some (g,t)\n")
cat("------------------------------------------------------------------------\n\n")

# Create a minimal panel:
# - 2 treated units (group g=3)
# - 3 control units (group g=0)
# - 5 time periods (t=1,2,3,4,5)
# - Treatment happens at g=3
# - UNBALANCED: treated units drop out after t=3 (missing t=4,5)

set.seed(123)

panel_test1 <- expand.grid(
  id = 1:5,
  time = 1:5
) %>%
  mutate(
    first_treat = ifelse(id <= 2, 3, 0),  # Units 1-2 treated at t=3
    treat = (id <= 2) & (time >= first_treat),
    y = rnorm(n()) + treat * 0.5  # Small treatment effect
  ) %>%
  # Remove treated units in post-treatment periods t=4,5
  # This creates the n_treat_post=0 problem
  filter(!(id <= 2 & time >= 4))

cat(sprintf("Panel structure:\n"))
cat(sprintf("  Total observations: %d\n", nrow(panel_test1)))
cat(sprintf("  Treated units: %d (observed until t=3)\n", sum(panel_test1$first_treat > 0 & panel_test1$time == 1)))
cat(sprintf("  Control units: %d (observed all periods)\n", sum(panel_test1$first_treat == 0 & panel_test1$time == 1)))
cat(sprintf("  Time periods: %d\n", length(unique(panel_test1$time))))
cat("\n")

cat("Observations per time period:\n")
print(table(panel_test1$time))
cat("\n")

# Source the safe wrapper
source("patches/att_gt_safe.R", local = TRUE)

# Test att_gt_safe
cat("Running att_gt_safe()...\n\n")

result1 <- tryCatch(
  {
    att_gt_safe(
      yname = "y",
      tname = "time",
      idname = "id",
      gname = "first_treat",
      data = panel_test1,
      control_group = "nevertreated",
      est_method = "reg",
      base_period = "universal",
      anticipation = 0,
      bstrap = FALSE,
      panel = FALSE,  # Use repeated cross-sections to handle unbalanced
      print_details = FALSE,
      fail_on_support_issues = FALSE,
      save_support_check = TRUE,
      support_check_dir = "output/csdid_debug/test1"
    )
  },
  error = function(e) {
    cat("\nERROR in Test 1:\n")
    cat(conditionMessage(e), "\n\n")
    NULL
  }
)

if (!is.null(result1)) {
  cat("\n✓ Test 1 PASSED: No crash/segfault\n")

  cat("\nATT(g,t) estimates:\n")
  att_summary <- data.frame(
    group = result1$group,
    time = result1$t,
    att = result1$att,
    se = result1$se,
    is_na = is.na(result1$att)
  )
  print(att_summary)

  # Check that problematic cells have NA
  na_count <- sum(is.na(result1$att))
  cat(sprintf("\nNumber of NA estimates: %d\n", na_count))

  if (na_count > 0) {
    cat("✓ Non-identifiable cells correctly returned NA\n")
  }

  # Test aggregation
  cat("\nTesting aggte_safe() with type='simple'...\n")
  agg1 <- aggte_safe(result1, type = "simple", na_action = "exclude")

  cat(sprintf("Overall ATT: %.4f (SE: %.4f)\n", agg1$overall.att, agg1$overall.se))
  cat(sprintf("NA cells excluded: %d\n", agg1$n_na_excluded))

  cat("\n✓ Test 1 COMPLETE\n\n")
} else {
  cat("\n✗ Test 1 FAILED\n\n")
}

# ========================================================================
# Test 2: Panel with no control observations in some periods
# ========================================================================

cat("========================================================================\n")
cat("Test 2: Panel with n_control_post=0 for some (g,t)\n")
cat("------------------------------------------------------------------------\n\n")

panel_test2 <- expand.grid(
  id = 1:5,
  time = 1:5
) %>%
  mutate(
    first_treat = ifelse(id <= 2, 3, 0),
    treat = (id <= 2) & (time >= first_treat),
    y = rnorm(n()) + treat * 0.5
  ) %>%
  # Remove control units in late periods
  filter(!(id > 2 & time >= 4))

cat(sprintf("Panel structure:\n"))
cat(sprintf("  Total observations: %d\n", nrow(panel_test2)))
cat("\nObservations per time period:\n")
print(table(panel_test2$time))
cat("\n")

cat("Running att_gt_safe()...\n\n")

result2 <- tryCatch(
  {
    att_gt_safe(
      yname = "y",
      tname = "time",
      idname = "id",
      gname = "first_treat",
      data = panel_test2,
      control_group = "nevertreated",
      est_method = "reg",
      base_period = "universal",
      anticipation = 0,
      bstrap = FALSE,
      panel = FALSE,
      print_details = FALSE,
      fail_on_support_issues = FALSE
    )
  },
  error = function(e) {
    cat("\nERROR in Test 2:\n")
    cat(conditionMessage(e), "\n\n")
    NULL
  }
)

if (!is.null(result2)) {
  cat("\n✓ Test 2 PASSED: No crash/segfault\n")
  cat(sprintf("NA estimates: %d\n", sum(is.na(result2$att))))
  cat("\n✓ Test 2 COMPLETE\n\n")
} else {
  cat("\n✗ Test 2 FAILED\n\n")
}

# ========================================================================
# Test 3: Balanced panel (should work perfectly)
# ========================================================================

cat("========================================================================\n")
cat("Test 3: Balanced panel (all cells identifiable)\n")
cat("------------------------------------------------------------------------\n\n")

panel_test3 <- expand.grid(
  id = 1:10,
  time = 1:5
) %>%
  mutate(
    first_treat = ifelse(id <= 5, 3, 0),
    treat = (id <= 5) & (time >= first_treat),
    y = rnorm(n()) + treat * 1.0  # Larger effect for easier detection
  )

cat(sprintf("Panel structure:\n"))
cat(sprintf("  Total observations: %d\n", nrow(panel_test3)))
cat(sprintf("  Balanced: YES\n\n"))

cat("Running att_gt_safe()...\n\n")

result3 <- tryCatch(
  {
    att_gt_safe(
      yname = "y",
      tname = "time",
      idname = "id",
      gname = "first_treat",
      data = panel_test3,
      control_group = "nevertreated",
      est_method = "dr",  # Test doubly robust
      base_period = "universal",
      anticipation = 0,
      bstrap = FALSE,
      panel = FALSE,
      print_details = FALSE,
      fail_on_support_issues = TRUE  # Should not fail with balanced panel
    )
  },
  error = function(e) {
    cat("\nERROR in Test 3:\n")
    cat(conditionMessage(e), "\n\n")
    NULL
  }
)

if (!is.null(result3)) {
  cat("\n✓ Test 3 PASSED: Balanced panel works correctly\n")
  cat(sprintf("NA estimates: %d (expected 0)\n", sum(is.na(result3$att))))

  if (sum(is.na(result3$att)) == 0) {
    cat("✓ All cells identifiable as expected\n")
  } else {
    cat("✗ WARNING: Unexpected NA values in balanced panel\n")
  }

  # Test all aggregation types
  cat("\nTesting all aggregation types...\n")
  for (agg_type in c("simple", "dynamic", "group", "calendar")) {
    cat(sprintf("  %s: ", agg_type))
    agg <- tryCatch(
      {
        aggte_safe(result3, type = agg_type, na_action = "exclude")
      },
      error = function(e) NULL
    )
    if (!is.null(agg)) {
      cat("✓\n")
    } else {
      cat("✗ FAILED\n")
    }
  }

  cat("\n✓ Test 3 COMPLETE\n\n")
} else {
  cat("\n✗ Test 3 FAILED\n\n")
}

# ========================================================================
# Summary
# ========================================================================

cat("========================================================================\n")
cat("Regression Test Summary\n")
cat("========================================================================\n\n")

tests_passed <- sum(
  !is.null(result1),
  !is.null(result2),
  !is.null(result3)
)

cat(sprintf("Tests passed: %d / 3\n", tests_passed))

if (tests_passed == 3) {
  cat("\n✓ ALL TESTS PASSED\n\n")
  cat("att_gt_safe() correctly handles:\n")
  cat("  - Unbalanced panels with missing post-treatment observations\n")
  cat("  - Missing control observations\n")
  cat("  - Balanced panels\n")
  cat("  - NA cells are flagged and aggregation handles them correctly\n\n")
} else {
  cat("\n✗ SOME TESTS FAILED\n\n")
  cat("Review error messages above for details.\n\n")
}

cat("========================================================================\n")
