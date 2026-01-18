#!/usr/bin/env Rscript
################################################################################
# debug_fastglm.R
#
# Test fastglm directly to identify the issue
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# Check if fastglm is installed
has_fastglm <- requireNamespace("fastglm", quietly = TRUE)

if (!has_fastglm) {
  cat("fastglm package not installed. Install with:\n")
  cat("  install.packages('fastglm')\n")
  quit(status = 1)
}

library(fastglm)

cat("fastglm package loaded successfully\n")
cat("fastglm version:", as.character(packageVersion("fastglm")), "\n\n")

# Create simple test cases
cat("=== TEST 1: Simple regression (should work) ===\n")
set.seed(42)
n <- 100
X <- cbind(1, rnorm(n), rnorm(n))
y <- rnorm(n)

tryCatch({
  fit <- fastglm(X, y, family = gaussian())
  cat("SUCCESS: Basic fastglm works\n")
  cat("Coefficients:", coef(fit), "\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

# Test with some edge cases
cat("=== TEST 2: Matrix with NAs ===\n")
X_na <- X
X_na[1:5, 2] <- NA
tryCatch({
  fit <- fastglm(X_na, y, family = gaussian())
  cat("SUCCESS: fastglm handles NAs\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 3: Zero variance column ===\n")
X_const <- cbind(X, rep(1, n))
tryCatch({
  fit <- fastglm(X_const, y, family = gaussian())
  cat("SUCCESS: fastglm handles constant column\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 4: Perfectly collinear columns ===\n")
X_collin <- cbind(X, X[, 2])
tryCatch({
  fit <- fastglm(X_collin, y, family = gaussian())
  cat("SUCCESS: fastglm handles collinearity\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 5: Single row ===\n")
tryCatch({
  fit <- fastglm(matrix(c(1, 2, 3), nrow = 1), 5, family = gaussian())
  cat("SUCCESS: fastglm handles single row\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 6: Empty matrix (0 rows) ===\n")
tryCatch({
  fit <- fastglm(matrix(numeric(0), nrow = 0, ncol = 3), numeric(0), family = gaussian())
  cat("SUCCESS: fastglm handles empty data\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 7: Matrix with Inf ===\n")
X_inf <- X
X_inf[1, 2] <- Inf
tryCatch({
  fit <- fastglm(X_inf, y, family = gaussian())
  cat("SUCCESS: fastglm handles Inf\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 8: Very small matrix (2x2) ===\n")
tryCatch({
  fit <- fastglm(matrix(c(1, 1, 0, 1), nrow = 2), c(1, 2), family = gaussian())
  cat("SUCCESS: fastglm handles 2x2\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 9: Matrix with all zeros in one column ===\n")
X_zero <- cbind(1, rep(0, n), rnorm(n))
tryCatch({
  fit <- fastglm(X_zero, y, family = gaussian())
  cat("SUCCESS: fastglm handles zero column\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 10: Sparse-like pattern (mostly zeros) ===\n")
X_sparse <- matrix(0, nrow = 100, ncol = 10)
X_sparse[1:10, 1:5] <- rnorm(50)
tryCatch({
  fit <- fastglm(X_sparse, y, family = gaussian())
  cat("SUCCESS: fastglm handles sparse pattern\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("=== TEST 11: Check colMax_dense directly ===\n")
cat("Testing the specific function that crashes...\n")
# Try to call colMax_dense if accessible
tryCatch({
  # This is an internal function, may not be exported
  result <- fastglm:::colMax_dense(X)
  cat("SUCCESS: colMax_dense works on normal matrix\n")
  cat("Result:", result, "\n\n")
}, error = function(e) {
  cat("Cannot access colMax_dense (may be internal)\n")
  cat("Error:", e$message, "\n\n")
})

# Try a matrix that might cause issues with colMax
cat("=== TEST 12: Matrix with extreme values ===\n")
X_extreme <- matrix(c(1e-300, 1e300, 0, 1), nrow = 2)
y_extreme <- c(1, 2)
tryCatch({
  fit <- fastglm(X_extreme, y_extreme, family = gaussian())
  cat("SUCCESS: fastglm handles extreme values\n\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n\n")
})

cat("\n=== DIAGNOSIS ===\n")
cat("If tests 6, 8, or 9 failed, the issue might be:\n")
cat("  - Empty or very small subgroups in the CS-DiD data\n")
cat("  - Zero variance in covariates for some group-time cells\n")
cat("  - Insufficient observations for estimation\n\n")

cat("Recommendation:\n")
cat("  - Use did package with panel=TRUE (requires balanced panel)\n")
cat("  - Or use alternative packages (fixest::sunab, didimputation)\n")
