# MINIMAL TEST SCRIPT
# Run this first to check if R can load packages and data

cat("Testing R environment...\n\n")

# Test 1: Load packages
cat("Test 1: Loading packages...\n")
tryCatch({
  library(tidyverse)
  cat("  ✓ tidyverse loaded\n")
}, error = function(e) cat("  ✗ tidyverse failed:", e$message, "\n"))

tryCatch({
  library(fixest)
  cat("  ✓ fixest loaded\n")
}, error = function(e) cat("  ✗ fixest failed:", e$message, "\n"))

tryCatch({
  library(lubridate)
  cat("  ✓ lubridate loaded\n")
}, error = function(e) cat("  ✗ lubridate failed\n\n"))

# Test 2: Load data
cat("\nTest 2: Loading CSV files...\n")
tryCatch({
  df <- read_csv("monthly_county_data_download.csv", show_col_types = FALSE)
  cat(sprintf("  ✓ County data: %d rows, %d columns\n", nrow(df), ncol(df)))
}, error = function(e) cat("  ✗ County data failed:", e$message, "\n"))

tryCatch({
  df <- read_csv("all_sites_monthly_2020_2021.csv", show_col_types = FALSE)
  cat(sprintf("  ✓ Sites data: %d rows, %d columns\n", nrow(df), ncol(df)))
}, error = function(e) cat("  ✗ Sites data failed:", e$message, "\n"))

tryCatch({
  df <- read_csv("sports_gambling_legalization_dates.csv", show_col_types = FALSE)
  cat(sprintf("  ✓ Gambling dates: %d rows, %d columns\n", nrow(df), ncol(df)))
}, error = function(e) cat("  ✗ Gambling dates failed:", e$message, "\n"))

# Test 3: Basic operations
cat("\nTest 3: Basic R operations...\n")
x <- 1:10
y <- x^2
cat(sprintf("  ✓ Vector operations work: mean(y) = %.2f\n", mean(y)))

# Test 4: String operations
cat("\nTest 4: String operations...\n")
header <- paste(rep("=", 40), collapse = "")
cat("  ", header, "\n")
cat("  ✓ String paste works\n")

cat("\n=== ALL TESTS COMPLETE ===\n")
cat("If you see this message, your R environment is working.\n")
cat("You can now run: source('eviction_power_analysis_SAFE.R')\n\n")
