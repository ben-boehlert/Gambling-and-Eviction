################################################################################
# DIAGNOSE DATA ISSUES
# Check why there are no treated units
################################################################################

cat("=== DIAGNOSING DATA ISSUES ===\n\n")

# Load the workspace
load("eviction_gambling_power_workspace.RData")

cat("Objects in workspace:\n")
print(ls())
cat("\n")

# Check analysis_panel
if (exists("analysis_panel")) {
  cat("Analysis Panel Summary:\n")
  cat(sprintf("  Total observations: %d\n", nrow(analysis_panel)))
  cat(sprintf("  Unique states: %d\n", length(unique(analysis_panel$state))))
  cat(sprintf("  Date range: %s to %s\n\n",
              min(analysis_panel$month), max(analysis_panel$month)))

  # Check treatment status
  cat("Treatment Status:\n")
  if ("treated_state" %in% names(analysis_panel)) {
    cat(sprintf("  States marked as treated: %d\n",
                sum(unique(analysis_panel$state) %in%
                    unique(analysis_panel$state[analysis_panel$treated_state]))))
    cat(sprintf("  Observations with treatment=1: %d\n",
                sum(analysis_panel$post_treatment, na.rm = TRUE)))
  } else {
    cat("  WARNING: No 'treated_state' column found!\n")
  }

  # Check for treatment_date column
  if ("treatment_date" %in% names(analysis_panel)) {
    cat(sprintf("  States with treatment dates: %d\n",
                sum(!is.na(unique(analysis_panel[, c("state", "treatment_date")])$treatment_date))))
  } else {
    cat("  WARNING: No 'treatment_date' column found!\n")
  }

  cat("\nFirst 10 rows:\n")
  print(head(analysis_panel, 10))

  cat("\nColumn names:\n")
  print(names(analysis_panel))

} else {
  cat("ERROR: analysis_panel not found in workspace!\n")
}

cat("\n")

# Check gambling_dates if it exists
if (exists("gambling_dates_clean")) {
  cat("Gambling Dates Loaded:\n")
  print(head(gambling_dates_clean, 10))
  cat(sprintf("\nTotal states with gambling dates: %d\n", nrow(gambling_dates_clean)))
} else {
  cat("WARNING: gambling_dates_clean not found!\n")
}

cat("\n=== END DIAGNOSIS ===\n")
