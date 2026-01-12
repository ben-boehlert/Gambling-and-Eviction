#!/usr/bin/env Rscript
# Diagnostic to check if effects are being added correctly

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# Read the output files from a completed run
cat("=== CHECKING POWER SIMULATION OUTPUT ===\n\n")

# Check if output directory exists
if (!dir.exists("cs_power_out")) {
  stop("cs_power_out directory not found. Run the simulation first.")
}

# Read power results
if (file.exists("cs_power_out/power_by_effect.csv")) {
  pwr <- read_csv("cs_power_out/power_by_effect.csv", show_col_types = FALSE)
  cat("Power results:\n")
  print(pwr)
  cat("\n")
} else {
  cat("power_by_effect.csv not found\n\n")
}

# Read sample draws if available
if (file.exists("cs_power_out/draws_sample.csv")) {
  draws <- read_csv("cs_power_out/draws_sample.csv", show_col_types = FALSE)
  cat("Sample draws (first 20 rows):\n")
  print(head(draws, 20))
  cat("\n")

  # Analyze by effect
  cat("ATT estimates by effect size:\n")
  draws_summary <- draws %>%
    group_by(effect_pct) %>%
    summarise(
      n = n(),
      mean_att = mean(att, na.rm = TRUE),
      sd_att = sd(att, na.rm = TRUE),
      mean_se = mean(se, na.rm = TRUE),
      mean_p = mean(p, na.rm = TRUE),
      .groups = "drop"
    )
  print(draws_summary)
  cat("\n")

  # Expected effect sizes
  cat("Expected vs Observed ATT:\n")
  expected <- data.frame(
    effect_pct = c(0, 0.05, 0.10, 0.15, 0.20),
    effect_log = log(1 + c(0, 0.05, 0.10, 0.15, 0.20))
  )
  comparison <- left_join(expected, draws_summary, by = "effect_pct")
  print(comparison)
  cat("\n")

} else {
  cat("draws_sample.csv not found\n\n")
}

# Read diagnostics
if (file.exists("cs_power_out/diagnostics_sanity.csv")) {
  diag <- read_csv("cs_power_out/diagnostics_sanity.csv", show_col_types = FALSE)
  cat("Diagnostics:\n")
  print(diag)
  cat("\n")
}

# Check run log for key information
if (file.exists("cs_power_out/run.log")) {
  cat("Key info from run.log:\n")
  log_lines <- readLines("cs_power_out/run.log")

  # Panel info
  panel_line <- grep("Panel:", log_lines, value = TRUE)
  if (length(panel_line) > 0) cat(panel_line[1], "\n")

  # Untreated obs
  untreated_line <- grep("Untreated observations", log_lines, value = TRUE)
  if (length(untreated_line) > 0) cat(untreated_line[1], "\n")

  # AR1 info
  ar1_lines <- grep("AR\\(1\\)", log_lines, value = TRUE)
  if (length(ar1_lines) > 0) cat(ar1_lines[1], "\n")

  cat("\n")
}

cat("=== DIAGNOSTIC COMPLETE ===\n")
