#!/usr/bin/env Rscript
################################################################################
# preflight_support_check.R
#
# Preflight diagnostics for Callaway-Sant'Anna DiD estimation
# Run this BEFORE calling did::att_gt() to check support and identify
# which (g,t) cells will be skipped and why
#
# Returns: A detailed report with:
#  - Panel balance diagnostics
#  - Treatment group and event-time structure
#  - Support table for all ATT(g,t) comparisons
#  - List of non-identifiable cells with reasons
################################################################################

#' Preflight Support Check for CS-DiD
#'
#' @param data Data frame containing the panel data
#' @param idname Name of unit identifier column
#' @param tname Name of time period column
#' @param gname Name of group/cohort column (0 = never-treated)
#' @param yname Name of outcome variable column
#' @param control_group Type of control group ("nevertreated" or "notyettreated")
#' @param anticipation Number of anticipation periods (default 0)
#' @param verbose Print detailed diagnostics to console (default TRUE)
#'
#' @return A list with components:
#'   - panel_balance: Summary of panel structure
#'   - support_table: Full support diagnostics for all (g,t) cells
#'   - non_identifiable: Subset of cells that cannot be estimated
#'   - summary: Overall summary statistics
#'
#' @examples
#' check <- preflight_support_check(
#'   data = mydata,
#'   idname = "id",
#'   tname = "year",
#'   gname = "first_treat",
#'   yname = "outcome",
#'   control_group = "nevertreated"
#' )
preflight_support_check <- function(data,
                                     idname,
                                     tname,
                                     gname,
                                     yname,
                                     control_group = "nevertreated",
                                     anticipation = 0,
                                     verbose = TRUE) {

  # Input validation
  stopifnot(is.data.frame(data))
  required_cols <- c(idname, tname, gname, yname)
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  # Extract variables
  id <- data[[idname]]
  t <- data[[tname]]
  g <- data[[gname]]
  y <- data[[yname]]

  # Remove rows with missing values
  complete_rows <- complete.cases(id, t, g, y)
  if (sum(!complete_rows) > 0) {
    if (verbose) {
      cat(sprintf("Removing %d rows with missing values\n", sum(!complete_rows)))
    }
    data <- data[complete_rows, ]
    id <- id[complete_rows]
    t <- t[complete_rows]
    g <- g[complete_rows]
    y <- y[complete_rows]
  }

  # Panel structure
  n_units <- length(unique(id))
  n_periods <- length(unique(t))
  n_obs <- nrow(data)
  expected_obs_balanced <- n_units * n_periods

  # Treatment structure
  treated_units <- unique(id[g > 0])
  control_units <- if (control_group == "nevertreated") {
    unique(id[g == 0])
  } else {
    unique(id)  # All units can serve as controls in notyettreated design
  }

  n_treated <- length(treated_units)
  n_control <- length(control_units)
  treatment_groups <- sort(unique(g[g > 0]))
  n_groups <- length(treatment_groups)

  # Panel balance by unit
  obs_per_unit <- table(id)
  min_obs_per_unit <- min(obs_per_unit)
  max_obs_per_unit <- max(obs_per_unit)
  mean_obs_per_unit <- mean(obs_per_unit)

  # Panel balance by time
  obs_per_time <- table(t)
  min_obs_per_time <- min(obs_per_time)
  max_obs_per_time <- max(obs_per_time)

  panel_balance <- list(
    n_units = n_units,
    n_periods = n_periods,
    n_obs = n_obs,
    expected_obs_balanced = expected_obs_balanced,
    balance_pct = 100 * n_obs / expected_obs_balanced,
    is_balanced = (n_obs == expected_obs_balanced),
    n_treated = n_treated,
    n_control = n_control,
    n_treatment_groups = n_groups,
    treatment_groups = treatment_groups,
    obs_per_unit_range = c(min = min_obs_per_unit, max = max_obs_per_unit, mean = mean_obs_per_unit),
    obs_per_time_range = c(min = min_obs_per_time, max = max_obs_per_time)
  )

  # Compute support for each ATT(g,t) comparison
  # CS-DiD estimates ATT(g,t) for all t >= g
  support_list <- list()

  for (g_val in treatment_groups) {
    # Get all time periods >= g_val
    time_periods <- sort(unique(t[t >= g_val]))

    for (t_val in time_periods) {
      # Pre-treatment period: one period before treatment
      pre_t <- g_val - 1

      # Identify treated and control units for this comparison
      if (control_group == "nevertreated") {
        comp_treated_units <- unique(id[g == g_val])
        comp_control_units <- unique(id[g == 0])
      } else {
        # notyettreated: controls are units not yet treated at time t
        comp_treated_units <- unique(id[g == g_val])
        comp_control_units <- unique(id[g == 0 | g > t_val])
      }

      # Count observations in each cell
      n_treat_pre <- sum(id %in% comp_treated_units & t == pre_t & !is.na(y))
      n_treat_post <- sum(id %in% comp_treated_units & t == t_val & !is.na(y))
      n_control_pre <- sum(id %in% comp_control_units & t == pre_t & !is.na(y))
      n_control_post <- sum(id %in% comp_control_units & t == t_val & !is.na(y))

      n_total <- n_treat_pre + n_treat_post + n_control_pre + n_control_post

      # Check if identifiable
      # Need at least one observation in each of the four cells
      identifiable <- (n_treat_pre > 0) & (n_treat_post > 0) & (n_control_pre > 0) & (n_control_post > 0)

      # Determine reason for non-identifiability
      reason <- if (!identifiable) {
        parts <- c()
        if (n_treat_pre == 0) parts <- c(parts, "n_treat_pre=0")
        if (n_treat_post == 0) parts <- c(parts, "n_treat_post=0")
        if (n_control_pre == 0) parts <- c(parts, "n_control_pre=0")
        if (n_control_post == 0) parts <- c(parts, "n_control_post=0")
        paste(parts, collapse = ", ")
      } else {
        NA_character_
      }

      support_list[[length(support_list) + 1]] <- data.frame(
        g = g_val,
        t = t_val,
        event_time = t_val - g_val,
        n_treat_pre = n_treat_pre,
        n_treat_post = n_treat_post,
        n_control_pre = n_control_pre,
        n_control_post = n_control_post,
        n_total = n_total,
        identifiable = identifiable,
        reason = reason,
        stringsAsFactors = FALSE
      )
    }
  }

  # Combine support list into table
  if (length(support_list) > 0) {
    support_table <- do.call(rbind, support_list)

    # Non-identifiable cells
    non_identifiable <- support_table[!support_table$identifiable, ]
    n_non_identifiable <- nrow(non_identifiable)
    n_total_comparisons <- nrow(support_table)
    pct_non_identifiable <- 100 * n_non_identifiable / n_total_comparisons
  } else {
    support_table <- data.frame()
    non_identifiable <- data.frame()
    n_non_identifiable <- 0
    n_total_comparisons <- 0
    pct_non_identifiable <- 0
  }

  # Summary
  summary_stats <- list(
    n_total_comparisons = n_total_comparisons,
    n_identifiable = n_total_comparisons - n_non_identifiable,
    n_non_identifiable = n_non_identifiable,
    pct_identifiable = 100 * (n_total_comparisons - n_non_identifiable) / n_total_comparisons,
    pct_non_identifiable = pct_non_identifiable
  )

  # Print diagnostics
  if (verbose) {
    cat("\n")
    cat("=================================================================\n")
    cat("Preflight Support Check for Callaway-Sant'Anna DiD\n")
    cat("=================================================================\n\n")

    cat("PANEL STRUCTURE:\n")
    cat(sprintf("  Units: %d\n", panel_balance$n_units))
    cat(sprintf("  Periods: %d\n", panel_balance$n_periods))
    cat(sprintf("  Observations: %d (%.1f%% of balanced panel)\n",
                panel_balance$n_obs, panel_balance$balance_pct))
    cat(sprintf("  Balanced: %s\n", ifelse(panel_balance$is_balanced, "YES", "NO")))
    cat(sprintf("  Obs per unit: min=%d, max=%d, mean=%.1f\n",
                panel_balance$obs_per_unit_range["min"],
                panel_balance$obs_per_unit_range["max"],
                panel_balance$obs_per_unit_range["mean"]))
    cat("\n")

    cat("TREATMENT STRUCTURE:\n")
    cat(sprintf("  Treated units: %d\n", panel_balance$n_treated))
    cat(sprintf("  Control units: %d (%s)\n", panel_balance$n_control, control_group))
    cat(sprintf("  Treatment groups: %d\n", panel_balance$n_treatment_groups))
    cat(sprintf("  Group values: %s\n", paste(panel_balance$treatment_groups, collapse = ", ")))
    cat("\n")

    cat("ATT(g,t) SUPPORT:\n")
    cat(sprintf("  Total comparisons: %d\n", summary_stats$n_total_comparisons))
    cat(sprintf("  Identifiable: %d (%.1f%%)\n",
                summary_stats$n_identifiable, summary_stats$pct_identifiable))
    cat(sprintf("  Non-identifiable: %d (%.1f%%)\n",
                summary_stats$n_non_identifiable, summary_stats$pct_non_identifiable))
    cat("\n")

    if (n_non_identifiable > 0) {
      cat("WARNING: Non-identifiable cells detected!\n\n")

      # Summarize reasons
      reason_counts <- table(non_identifiable$reason)
      cat("Reasons for non-identifiability:\n")
      for (r in names(reason_counts)) {
        cat(sprintf("  %s: %d cells\n", r, reason_counts[r]))
      }
      cat("\n")

      # Show first few non-identifiable cells
      cat("First 10 non-identifiable (g,t) cells:\n")
      print(head(non_identifiable[, c("g", "t", "event_time", "n_treat_pre", "n_treat_post",
                                       "n_control_pre", "n_control_post", "reason")], 10))
      cat("\n")

      cat("RECOMMENDATION:\n")
      cat("  These cells will need to be handled explicitly:\n")
      cat("  - Set ATT(g,t) = NA for non-identifiable cells\n")
      cat("  - Exclude from aggregation or reweight appropriately\n")
      cat("  - Report in paper appendix with reasons\n")
      cat("\n")
    } else {
      cat("✓ All (g,t) cells are identifiable\n\n")
    }

    cat("=================================================================\n\n")
  }

  # Return results
  invisible(list(
    panel_balance = panel_balance,
    support_table = support_table,
    non_identifiable = non_identifiable,
    summary = summary_stats
  ))
}


#' Save Preflight Check Results to File
#'
#' @param check_result Output from preflight_support_check()
#' @param output_dir Directory to save results
#' @param prefix Prefix for output files
save_preflight_check <- function(check_result, output_dir, prefix = "csdid_preflight") {
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # Save support table
  support_file <- file.path(output_dir, paste0(prefix, "_support_table.csv"))
  write.csv(check_result$support_table, support_file, row.names = FALSE)
  cat(sprintf("Support table saved to: %s\n", support_file))

  # Save non-identifiable cells
  if (nrow(check_result$non_identifiable) > 0) {
    non_id_file <- file.path(output_dir, paste0(prefix, "_non_identifiable.csv"))
    write.csv(check_result$non_identifiable, non_id_file, row.names = FALSE)
    cat(sprintf("Non-identifiable cells saved to: %s\n", non_id_file))
  }

  # Save summary report
  report_file <- file.path(output_dir, paste0(prefix, "_summary.txt"))
  sink(report_file)
  cat("Callaway-Sant'Anna DiD Preflight Check Summary\n")
  cat(paste0("Generated: ", Sys.time(), "\n\n"))

  cat("Panel Balance:\n")
  print(check_result$panel_balance)
  cat("\n")

  cat("Support Summary:\n")
  print(check_result$summary)
  cat("\n")

  if (nrow(check_result$non_identifiable) > 0) {
    cat("Non-Identifiable Cells:\n")
    print(table(check_result$non_identifiable$reason))
  }

  sink()
  cat(sprintf("Summary report saved to: %s\n", report_file))

  invisible(NULL)
}


# If run as a script, perform check on the gambling-eviction data
if (!interactive() && !exists("preflight_check_sourced")) {
  cat("Running preflight check as standalone script...\n\n")

  suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
  })

  # Load and prepare data (same as debug script)
  source_local <- function() {
    # (Include same data loading code as in debug_csdid_instrumented.R)
    # For brevity, load prepared data directly if available
    if (file.exists("output/csdid_debug/panel_cs.rds")) {
      panel_cs <- readRDS("output/csdid_debug/panel_cs.rds")
    } else {
      stop("Please run debug_csdid_instrumented.R first to prepare data")
    }

    panel_cs
  }

  # Check if we can load data
  if (file.exists("data/raw/combined_monthly_panel.csv")) {
    # Load data (reuse functions from instrumented script)
    # For this example, assume data is already prepared
    cat("Data loading code would go here...\n")
    cat("Use: check <- preflight_support_check(data, ...)\n")
  } else {
    cat("Data not found. This script is meant to be sourced and used with your data.\n")
  }
}

# Mark as sourced
preflight_check_sourced <- TRUE
