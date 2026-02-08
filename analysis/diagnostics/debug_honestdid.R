#!/usr/bin/env Rscript
################################################################################
# debug_honestdid.R
#
# Debug why HonestDiD is failing
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
})

# Check if HonestDiD is installed
has_honestdid <- requireNamespace("HonestDiD", quietly = TRUE)

if (!has_honestdid) {
  cat("HonestDiD package not installed. Install with:\n")
  cat("  remotes::install_github('asheshrambachan/HonestDiD')\n")
  quit(status = 1)
}

library(HonestDiD)

cat("HonestDiD package loaded successfully\n\n")

# Load one of the event study results
baseline_coefs <- readr::read_csv(
  "output/pretrends_evaluation/baseline/event_study_coefs.csv",
  show_col_types = FALSE
)

cat("Loaded event study coefficients:\n")
print(baseline_coefs)
cat("\n")

# Extract pre and post
pre_coefs <- baseline_coefs %>% filter(e < 0)
post_coefs <- baseline_coefs %>% filter(e >= 0)

numPrePeriods <- nrow(pre_coefs)
numPostPeriods <- nrow(post_coefs)

cat(glue::glue("Pre-periods: {numPrePeriods}, Post-periods: {numPostPeriods}\n\n"))

# Create betahat vector
beta <- baseline_coefs$estimate
names(beta) <- baseline_coefs$e

cat("Beta vector:\n")
print(beta)
cat("\n")

# For debugging, create a simple diagonal variance matrix
# (This is not accurate but helps test if the issue is with sigma)
sigma_simple <- diag(baseline_coefs$se^2)
rownames(sigma_simple) <- baseline_coefs$e
colnames(sigma_simple) <- baseline_coefs$e

cat("Sigma dimensions:", dim(sigma_simple), "\n")
cat("Sigma diagonal (first 5):", diag(sigma_simple)[1:5], "\n\n")

# Test HonestDiD with simple case
cat("Testing HonestDiD with M = 0 (exact parallel trends)...\n")
tryCatch({
  result <- HonestDiD::createSensitivityResults(
    betahat = beta,
    sigma = sigma_simple,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    Mvec = 0,  # FIXED: was Mbarvec
    method = "C-LF",
    alpha = 0.05
  )
  cat("SUCCESS! HonestDiD worked with M = 0\n")
  print(str(result))
}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n")
  cat("\nFull traceback:\n")
  print(e)
})

cat("\n\nTesting with M = 1...\n")
tryCatch({
  result <- HonestDiD::createSensitivityResults(
    betahat = beta,
    sigma = sigma_simple,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    Mvec = 1,  # FIXED: was Mbarvec
    method = "C-LF",
    alpha = 0.05
  )
  cat("SUCCESS! HonestDiD worked with M = 1\n")
  print(names(result))
}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n")
})

# Try different method
cat("\n\nTesting with method = 'FLCI'...\n")
tryCatch({
  result <- HonestDiD::createSensitivityResults(
    betahat = beta,
    sigma = sigma_simple,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    Mvec = 0,  # FIXED: was Mbarvec
    method = "FLCI",
    alpha = 0.05
  )
  cat("SUCCESS! HonestDiD worked with FLCI method\n")
  print(names(result))
}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n")
})

# Check package version
cat("\n\nPackage info:\n")
cat("HonestDiD version:", as.character(packageVersion("HonestDiD")), "\n")
