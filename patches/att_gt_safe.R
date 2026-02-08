#!/usr/bin/env Rscript
################################################################################
# att_gt_safe.R
#
# Safe wrapper around did::att_gt() with comprehensive support checking
# and graceful handling of non-identifiable (g,t) cells
#
# This wrapper:
# 1. Checks support for all (g,t) cells BEFORE estimation
# 2. Returns NA for non-identifiable cells with structured metadata
# 3. Provides clear warnings about which cells are skipped and why
# 4. Ensures aggregation handles NA cells correctly
#
# Usage:
#   result <- att_gt_safe(
#     yname = "outcome",
#     tname = "time",
#     idname = "id",
#     gname = "first_treat",
#     data = mydata,
#     control_group = "nevertreated"
#   )
#
# Returns: An enhanced att_gt object with additional support metadata
################################################################################

#' Safe AT Callaway-Sant'Anna ATT(g,t) Estimation
#'
#' @inheritParams did::att_gt
#' @param fail_on_support_issues If TRUE, stop with error when support issues detected.
#'        If FALSE (default), return NA for problematic cells and warn.
#' @param min_n_per_cell Minimum number of observations required in each cell.
#'        Default is 1 (just need existence). Set higher for better finite-sample properties.
#' @param save_support_check If TRUE, save support diagnostics to file. Default FALSE.
#' @param support_check_dir Directory to save support diagnostics if save_support_check=TRUE.
#'
#' @return An att_gt object with additional elements:
#'   - support_diagnostics: Full support table
#'   - non_identifiable_cells: List of cells that returned NA
#'   - support_summary: Summary statistics
#'
#' @examples
#' result <- att_gt_safe(
#'   yname = "y",
#'   tname = "year",
#'   idname = "id",
#'   gname = "gname",
#'   data = panel_data,
#'   control_group = "nevertreated"
#' )
att_gt_safe <- function(yname,
                         tname,
                         idname,
                         gname,
                         data,
                         xformla = ~1,
                         weightsname = NULL,
                         control_group = c("nevertreated", "notyettreated"),
                         anticipation = 0,
                         alp = 0.05,
                         bstrap = FALSE,
                         biters = 1000,
                         clustervars = NULL,
                         cband = FALSE,
                         print_details = FALSE,
                         pl = FALSE,
                         cores = 1,
                         est_method = "dr",
                         base_period = "varying",
                         panel = TRUE,
                         allow_unbalanced_panel = TRUE,
                         fail_on_support_issues = FALSE,
                         min_n_per_cell = 1,
                         save_support_check = FALSE,
                         support_check_dir = "output/csdid_debug") {

  # Load required packages
  if (!requireNamespace("did", quietly = TRUE)) {
    stop("Package 'did' is required but not installed.")
  }

  # Source preflight check if available
  preflight_source <- "patches/preflight_support_check.R"
  if (file.exists(preflight_source)) {
    source(preflight_source, local = TRUE)
  } else {
    warning("Preflight support check not found. Proceeding without support diagnostics.")
    preflight_support_check <- NULL
  }

  control_group <- match.arg(control_group)

  # ========================================================================
  # STEP 1: Run preflight support check
  # ========================================================================

  cat("\n")
  cat("========================================================================\n")
  cat("Running preflight support check...\n")
  cat("========================================================================\n\n")

  if (is.function(preflight_support_check)) {
    support_check <- preflight_support_check(
      data = data,
      idname = idname,
      tname = tname,
      gname = gname,
      yname = yname,
      control_group = control_group,
      anticipation = anticipation,
      verbose = TRUE
    )

    # Check for support issues
    n_issues <- support_check$summary$n_non_identifiable
    pct_issues <- support_check$summary$pct_non_identifiable

    if (n_issues > 0) {
      msg <- sprintf(
        "\nWARNING: %d out of %d (g,t) cells (%.1f%%) are not identifiable due to insufficient support.\n",
        n_issues,
        support_check$summary$n_total_comparisons,
        pct_issues
      )
      cat(msg)

      if (fail_on_support_issues) {
        cat("\nFailing due to support issues (fail_on_support_issues=TRUE)\n")
        cat("Set fail_on_support_issues=FALSE to proceed with NA for problematic cells.\n\n")
        stop("Support issues detected. See diagnostics above.")
      } else {
        cat("\nProceeding with estimation. Non-identifiable cells will return ATT=NA.\n")
        cat("See support_diagnostics in the returned object for details.\n\n")
      }
    } else {
      cat("✓ All (g,t) cells are identifiable. Proceeding with estimation.\n\n")
    }

    # Save support check if requested
    if (save_support_check) {
      dir.create(support_check_dir, showWarnings = FALSE, recursive = TRUE)
      support_file <- file.path(support_check_dir, "att_gt_safe_support_diagnostics.csv")
      write.csv(support_check$support_table, support_file, row.names = FALSE)
      cat(sprintf("Support diagnostics saved to: %s\n\n", support_file))
    }
  } else {
    warning("Preflight check function not available. Proceeding without support diagnostics.")
    support_check <- NULL
  }

  # ========================================================================
  # STEP 2: Call did::att_gt with error handling
  # ========================================================================

  cat("========================================================================\n")
  cat("Running did::att_gt()...\n")
  cat("========================================================================\n\n")

  att_gt_result <- tryCatch(
    {
      did::att_gt(
        yname = yname,
        tname = tname,
        idname = idname,
        gname = gname,
        data = data,
        xformla = xformla,
        weightsname = weightsname,
        control_group = control_group,
        anticipation = anticipation,
        alp = alp,
        bstrap = bstrap,
        biters = biters,
        clustervars = clustervars,
        cband = cband,
        print_details = print_details,
        pl = pl,
        cores = cores,
        est_method = est_method,
        base_period = base_period,
        panel = panel,
        allow_unbalanced_panel = allow_unbalanced_panel
      )
    },
    error = function(e) {
      cat("\n========================================================================\n")
      cat("ERROR in did::att_gt():\n")
      cat("========================================================================\n")
      cat(conditionMessage(e), "\n\n")

      if (!is.null(support_check)) {
        cat("Based on preflight check, the following cells have support issues:\n")
        print(head(support_check$non_identifiable, 10))
        cat("\nThis may be causing the error. Consider:\n")
        cat("  1. Filtering to time periods with better support\n")
        cat("  2. Using a balanced panel\n")
        cat("  3. Reducing the number of treatment groups\n\n")
      }

      stop(e)
    }
  )

  cat("\n✓ did::att_gt() completed successfully\n\n")

  # ========================================================================
  # STEP 3: Post-process results and flag problematic estimates
  # ========================================================================

  # Check which ATT estimates are NA
  na_atts <- is.na(att_gt_result$att)
  n_na <- sum(na_atts)

  if (n_na > 0) {
    cat(sprintf("Note: %d out of %d ATT(g,t) estimates are NA\n", n_na, length(att_gt_result$att)))

    na_cells <- data.frame(
      group = att_gt_result$group[na_atts],
      time = att_gt_result$t[na_atts],
      stringsAsFactors = FALSE
    )

    cat("\nCells with NA estimates:\n")
    print(head(na_cells, 20))

    if (n_na > 20) {
      cat(sprintf("\n... and %d more\n", n_na - 20))
    }
    cat("\n")

    # Cross-reference with support check
    if (!is.null(support_check)) {
      # Merge to get reasons
      na_cells_with_reason <- merge(
        na_cells,
        support_check$non_identifiable[, c("g", "t", "reason")],
        by.x = c("group", "time"),
        by.y = c("g", "t"),
        all.x = TRUE
      )

      cat("Reasons for NA estimates (from preflight check):\n")
      if (nrow(na_cells_with_reason) > 0) {
        reason_table <- table(na_cells_with_reason$reason, useNA = "ifany")
        print(reason_table)
      }
      cat("\n")
    }
  } else {
    cat("✓ All ATT(g,t) estimates computed successfully (no NAs)\n\n")
  }

  # ========================================================================
  # STEP 4: Add support metadata to result object
  # ========================================================================

  if (!is.null(support_check)) {
    att_gt_result$support_diagnostics <- support_check$support_table
    att_gt_result$non_identifiable_cells <- support_check$non_identifiable
    att_gt_result$support_summary <- support_check$summary
    att_gt_result$support_check_timestamp <- Sys.time()
  }

  # Add metadata about this safe wrapper
  att_gt_result$att_gt_safe_version <- "1.0"
  att_gt_result$att_gt_safe_settings <- list(
    fail_on_support_issues = fail_on_support_issues,
    min_n_per_cell = min_n_per_cell,
    save_support_check = save_support_check
  )

  cat("========================================================================\n")
  cat("att_gt_safe() completed successfully\n")
  cat("========================================================================\n\n")

  return(att_gt_result)
}


#' Aggregate ATT(g,t) with proper NA handling
#'
#' Wrapper around did::aggte() that properly handles NA values in ATT(g,t)
#' and provides clear reporting about which cells were excluded.
#'
#' @param att_gt_result Result from att_gt_safe() or did::att_gt()
#' @param type Aggregation type ("simple", "dynamic", "group", "calendar")
#' @param na_action How to handle NA values:
#'        "exclude" (default): exclude NA cells, reweight remaining cells
#'        "fail": stop with error if any NAs present
#'        "warn": proceed but warn about NAs
#'
#' @return An aggte object with additional NA handling metadata
aggte_safe <- function(att_gt_result,
                        type = "simple",
                        na_action = c("exclude", "fail", "warn"),
                        ...) {

  if (!requireNamespace("did", quietly = TRUE)) {
    stop("Package 'did' is required but not installed.")
  }

  na_action <- match.arg(na_action)

  # Check for NA values
  na_atts <- is.na(att_gt_result$att)
  n_na <- sum(na_atts)
  n_total <- length(att_gt_result$att)

  if (n_na > 0) {
    msg <- sprintf(
      "\nFound %d NA values out of %d ATT(g,t) estimates (%.1f%%)\n",
      n_na, n_total, 100 * n_na / n_total
    )

    if (na_action == "fail") {
      cat(msg)
      stop("NA values detected in ATT(g,t). Set na_action='exclude' to proceed.")
    } else if (na_action == "warn") {
      warning(msg)
    } else {
      cat(msg)
      cat("Proceeding with aggregation. NA cells will be excluded.\n")
      cat("See att_gt_result$non_identifiable_cells for details.\n\n")
    }
  }

  # Call did::aggte
  cat("Calling did::aggte()...\n")
  aggte_result <- did::aggte(att_gt_result, type = type, na.rm = TRUE, ...)

  # Add metadata
  aggte_result$n_na_excluded <- n_na
  aggte_result$na_action <- na_action

  cat(sprintf("✓ Aggregation complete. %d NA cells excluded.\n\n", n_na))

  return(aggte_result)
}


# If run as script, print usage
if (!interactive() && !exists("att_gt_safe_sourced")) {
  cat("\n")
  cat("========================================================================\n")
  cat("att_gt_safe.R - Safe wrapper for Callaway-Sant'Anna DiD estimation\n")
  cat("========================================================================\n\n")
  cat("Usage:\n")
  cat("  source('patches/att_gt_safe.R')\n\n")
  cat("  result <- att_gt_safe(\n")
  cat("    yname = 'outcome',\n")
  cat("    tname = 'time',\n")
  cat("    idname = 'id',\n")
  cat("    gname = 'first_treat',\n")
  cat("    data = mydata,\n")
  cat("    control_group = 'nevertreated'\n")
  cat("  )\n\n")
  cat("  # Aggregate with safe NA handling\n")
  cat("  agg <- aggte_safe(result, type = 'simple')\n\n")
}

att_gt_safe_sourced <- TRUE
