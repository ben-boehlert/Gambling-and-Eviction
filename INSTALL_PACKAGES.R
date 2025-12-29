################################################################################
# PACKAGE INSTALLATION SCRIPT
# Run this once to install all required packages
################################################################################

cat("\n")
cat("================================================================================\n")
cat("INSTALLING PACKAGES FOR POWER ANALYSIS\n")
cat("================================================================================\n\n")

# Standard CRAN packages
cran_packages <- c(
  "tidyverse",    # Data manipulation and visualization
  "fixest",       # Fast fixed effects regression with clustering
  "lubridate",    # Date/time handling
  "boot",         # Bootstrap methods
  "patchwork",    # Combine plots
  "scales"        # Plot scaling
)

cat("Installing standard CRAN packages...\n")
for (pkg in cran_packages) {
  if (!pkg %in% installed.packages()[,"Package"]) {
    cat(sprintf("  Installing %s...\n", pkg))
    install.packages(pkg, dependencies = TRUE, quiet = FALSE)
  } else {
    cat(sprintf("  ✓ %s already installed\n", pkg))
  }
}

cat("\n")

# Special installation for fwildclusterboot (from r-universe)
cat("Installing fwildclusterboot from r-universe...\n")
if (!"fwildclusterboot" %in% installed.packages()[,"Package"]) {
  tryCatch({
    install.packages(
      "fwildclusterboot",
      repos = c("https://s3alfisc.r-universe.dev", "https://cloud.r-project.org"),
      dependencies = TRUE
    )
    cat("  ✓ fwildclusterboot installed successfully\n")
  }, error = function(e) {
    cat("  ⚠ fwildclusterboot installation failed (optional for wild bootstrap)\n")
    cat("    You can still run the analysis without wild bootstrap\n")
  })
} else {
  cat("  ✓ fwildclusterboot already installed\n")
}

cat("\n")
cat("================================================================================\n")
cat("TESTING PACKAGE INSTALLATION\n")
cat("================================================================================\n\n")

# Test loading each package
all_packages <- c(cran_packages, "fwildclusterboot")
success_count <- 0

for (pkg in all_packages) {
  result <- tryCatch({
    suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    cat(sprintf("✓ %s loads correctly\n", pkg))
    success_count <- success_count + 1
    TRUE
  }, error = function(e) {
    cat(sprintf("✗ %s failed to load: %s\n", pkg, e$message))
    FALSE
  })
}

cat("\n")
cat("================================================================================\n")
cat("INSTALLATION SUMMARY\n")
cat("================================================================================\n\n")

cat(sprintf("Successfully loaded: %d / %d packages\n", success_count, length(all_packages)))

if (success_count == length(all_packages)) {
  cat("\n✓ ALL PACKAGES INSTALLED AND WORKING!\n")
  cat("\nYou can now run the full analysis:\n")
  cat("  source('RUN_ALL_ANALYSES.R')\n\n")
} else if (success_count >= length(cran_packages)) {
  cat("\n⚠ Core packages installed. Wild bootstrap optional.\n")
  cat("\nYou can run the analysis (without wild bootstrap):\n")
  cat("  source('eviction_gambling_power_analysis.R')\n")
  cat("  source('power_simulation_main.R')  # Set use_wild_bootstrap = FALSE\n\n")
} else {
  cat("\n✗ Some required packages failed to install.\n")
  cat("\nTry running the minimal version instead:\n")
  cat("  source('RUN_MINIMAL.R')\n\n")
  cat("Or install packages manually:\n")
  failed <- all_packages[!sapply(all_packages, function(p) {
    p %in% installed.packages()[,"Package"]
  })]
  for (pkg in failed) {
    cat(sprintf("  install.packages('%s')\n", pkg))
  }
  cat("\n")
}

cat("Session info:\n")
cat("--------------------------------------------------------------------------------\n")
print(sessionInfo())
cat("\n")
