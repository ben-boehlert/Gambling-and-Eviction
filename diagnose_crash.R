################################################################################
# DIAGNOSTIC SCRIPT - Find which package causes crash
# Run this to identify the problem
################################################################################

cat("=== R CRASH DIAGNOSTIC ===\n\n")
cat("R version:", R.version.string, "\n")
cat("Platform:", R.version$platform, "\n\n")

cat("Testing packages one at a time...\n")
cat("(Press Ctrl+C if R hangs)\n\n")

# Test 1: Base R
cat("[1/7] Testing base R... ")
x <- 1:10
cat("OK\n")

# Test 2: tidyverse (most likely culprit)
cat("[2/7] Testing tidyverse... ")
Sys.sleep(0.5)  # Brief pause
result <- tryCatch({
  suppressPackageStartupMessages(library(tidyverse))
  "OK"
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")
if (grepl("FAILED", result)) {
  cat("\n*** PROBLEM FOUND: tidyverse is causing the crash ***\n")
  cat("Solution: Install individual packages instead\n")
  cat("Run: install.packages(c('dplyr', 'ggplot2', 'readr', 'tidyr', 'stringr'))\n\n")
  quit(save = "no")
}

# Test 3: fixest
cat("[3/7] Testing fixest... ")
Sys.sleep(0.5)
result <- tryCatch({
  suppressPackageStartupMessages(library(fixest))
  "OK"
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")

# Test 4: lubridate
cat("[4/7] Testing lubridate... ")
Sys.sleep(0.5)
result <- tryCatch({
  suppressPackageStartupMessages(library(lubridate))
  "OK"
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")

# Test 5: Reading CSV
cat("[5/7] Testing CSV reading... ")
result <- tryCatch({
  if (file.exists("sports_gambling_legalization_dates.csv")) {
    df <- read.csv("sports_gambling_legalization_dates.csv", nrows = 5)
    paste("OK - read", nrow(df), "rows")
  } else {
    "SKIPPED - file not found"
  }
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")

# Test 6: Memory allocation
cat("[6/7] Testing memory allocation... ")
result <- tryCatch({
  big_matrix <- matrix(rnorm(10000), nrow = 100)
  "OK"
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")

# Test 7: String operations
cat("[7/7] Testing string operations... ")
result <- tryCatch({
  header <- paste(rep("=", 80), collapse = "")
  test_str <- sprintf("Test %d", 123)
  "OK"
}, error = function(e) {
  paste("FAILED:", e$message)
})
cat(result, "\n")

cat("\n=== DIAGNOSTIC COMPLETE ===\n")
cat("If you see this message, R is working.\n")
cat("If R crashed before this, the last test shown is the problem.\n\n")

cat("Session info:\n")
print(sessionInfo())
