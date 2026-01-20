#!/usr/bin/env Rscript
################################################################################
# plot_csdid_pretrends.R
#
# Comprehensive plotting functions for CS-DiD pre-trends analysis
#
# Functions:
# 1. plot_event_study() - Standard event study plot with pre-trends highlighted
# 2. plot_pretrends_test() - Visual test of pre-trends with confidence bands
# 3. plot_group_dynamics() - Separate event studies by treatment group
# 4. plot_calendar_time() - Calendar-time effects
# 5. plot_support_heatmap() - Visualize which (g,t) cells are identifiable
# 6. create_pretrends_report() - Generate full diagnostic report
################################################################################

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(patchwork)
})

#' Standard Event Study Plot with Pre-trends Emphasis
#'
#' @param att_gt_result Result from att_gt_safe() or did::att_gt()
#' @param pretreatment_periods Number of pre-treatment periods to show (default: all)
#' @param posttreatment_periods Number of post-treatment periods to show (default: all)
#' @param ref_period Reference period (default: -1)
#' @param show_pretrend_window Highlight pre-trend window (default: TRUE)
#' @param alpha Significance level for confidence intervals (default: 0.05)
#' @param title Plot title
#'
#' @return ggplot object
plot_event_study <- function(att_gt_result,
                              pretreatment_periods = NULL,
                              posttreatment_periods = NULL,
                              ref_period = -1,
                              show_pretrend_window = TRUE,
                              alpha = 0.05,
                              title = "Event Study: Treatment Effects Over Time") {

  # Aggregate to dynamic (event time)
  if (!inherits(att_gt_result, "AGGTEobj")) {
    agg_dyn <- did::aggte(att_gt_result, type = "dynamic", na.rm = TRUE)
  } else {
    agg_dyn <- att_gt_result
  }

  # Extract event study data
  event_time <- agg_dyn$egt
  att <- agg_dyn$att.egt
  se <- agg_dyn$se.egt

  # Compute confidence intervals
  crit_val <- qnorm(1 - alpha/2)
  ci_lower <- att - crit_val * se
  ci_upper <- att + crit_val * se

  # Create data frame
  plot_data <- data.frame(
    event_time = event_time,
    att = att,
    se = se,
    ci_lower = ci_lower,
    ci_upper = ci_upper,
    is_pretrend = event_time < 0,
    is_post = event_time >= 0
  )

  # Filter periods if requested
  if (!is.null(pretreatment_periods)) {
    plot_data <- plot_data %>%
      filter(event_time >= -pretreatment_periods)
  }
  if (!is.null(posttreatment_periods)) {
    plot_data <- plot_data %>%
      filter(event_time <= posttreatment_periods)
  }

  # Create base plot
  p <- ggplot(plot_data, aes(x = event_time, y = att)) +
    # Zero line
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    # Vertical line at treatment
    geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.5) +
    # Confidence interval
    geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper),
                alpha = 0.2, fill = "steelblue") +
    # Point estimates
    geom_line(color = "steelblue", linewidth = 1) +
    geom_point(aes(shape = is_post), color = "steelblue", size = 2.5) +
    scale_shape_manual(values = c("TRUE" = 19, "FALSE" = 1),
                       labels = c("Post-treatment", "Pre-treatment"),
                       name = "") +
    labs(
      title = title,
      x = "Event Time (periods relative to treatment)",
      y = "Average Treatment Effect on Treated (ATT)",
      caption = paste0(100*(1-alpha), "% confidence intervals shown")
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      axis.title = element_text(size = 11),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )

  # Highlight pre-trend window
  if (show_pretrend_window && any(plot_data$is_pretrend)) {
    pretrend_window <- plot_data %>%
      filter(is_pretrend) %>%
      summarise(xmin = min(event_time) - 0.5,
                xmax = max(event_time) + 0.5)

    p <- p +
      annotate("rect",
               xmin = pretrend_window$xmin,
               xmax = pretrend_window$xmax,
               ymin = -Inf, ymax = Inf,
               alpha = 0.1, fill = "orange") +
      annotate("text",
               x = mean(c(pretrend_window$xmin, pretrend_window$xmax)),
               y = Inf,
               label = "Pre-treatment\n(test parallel trends)",
               vjust = 1.5, hjust = 0.5,
               size = 3, color = "orange4", fontface = "italic")
  }

  return(p)
}


#' Pre-trends Test Plot with Joint Hypothesis Test
#'
#' @param att_gt_result Result from att_gt_safe() or did::att_gt()
#' @param pretreatment_periods Pre-treatment periods to test (default: all)
#' @param alpha Significance level (default: 0.05)
#' @param title Plot title
#'
#' @return List with ggplot object and test results
plot_pretrends_test <- function(att_gt_result,
                                 pretreatment_periods = NULL,
                                 alpha = 0.05,
                                 title = "Pre-trends Test") {

  # Aggregate to dynamic
  agg_dyn <- did::aggte(att_gt_result, type = "dynamic", na.rm = TRUE)

  # Extract pre-treatment effects
  event_time <- agg_dyn$egt
  is_pre <- event_time < 0

  if (!is.null(pretreatment_periods)) {
    is_pre <- is_pre & (event_time >= -pretreatment_periods)
  }

  pre_att <- agg_dyn$att.egt[is_pre]
  pre_se <- agg_dyn$se.egt[is_pre]
  pre_event_time <- event_time[is_pre]

  # Compute individual t-statistics
  t_stats <- pre_att / pre_se
  p_values <- 2 * (1 - pnorm(abs(t_stats)))

  # Joint F-test (Wald test)
  # H0: all pre-treatment effects = 0
  if (length(pre_att) > 1) {
    # Remove any NA/Inf values that could cause issues
    valid_idx <- is.finite(pre_att) & is.finite(pre_se) & pre_se > 0
    if (sum(valid_idx) > 0) {
      joint_chisq <- sum((pre_att[valid_idx] / pre_se[valid_idx])^2)
      joint_df <- sum(valid_idx)
      joint_p <- 1 - pchisq(joint_chisq, df = joint_df)
    } else {
      joint_chisq <- NA_real_
      joint_df <- 0
      joint_p <- NA_real_
    }
  } else if (length(pre_att) == 1 && is.finite(t_stats[1])) {
    joint_p <- p_values[1]
    joint_chisq <- t_stats[1]^2
    joint_df <- 1
  } else {
    joint_chisq <- NA_real_
    joint_df <- 0
    joint_p <- NA_real_
  }

  # Create data frame
  plot_data <- data.frame(
    event_time = pre_event_time,
    att = pre_att,
    se = pre_se,
    ci_lower = pre_att - qnorm(1 - alpha/2) * pre_se,
    ci_upper = pre_att + qnorm(1 - alpha/2) * pre_se,
    p_value = p_values,
    significant = p_values < alpha
  )

  # Create plot
  p <- ggplot(plot_data, aes(x = event_time, y = att)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
    geom_pointrange(aes(ymin = ci_lower, ymax = ci_upper, color = significant),
                    size = 0.8, fatten = 3) +
    scale_color_manual(values = c("FALSE" = "steelblue", "TRUE" = "red"),
                       labels = c("Non-significant", "Significant"),
                       name = paste0("Significant at ", 100*alpha, "%")) +
    labs(
      title = title,
      subtitle = sprintf("Joint test: χ²(%.0f) = %.2f, p = %.4f",
                        joint_df, joint_chisq, joint_p),
      x = "Event Time (pre-treatment periods only)",
      y = "ATT (should be ≈ 0 under parallel trends)",
      caption = paste0(100*(1-alpha), "% confidence intervals shown")
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11,
                                   color = ifelse(joint_p < alpha, "red", "darkgreen"),
                                   face = "bold"),
      axis.title = element_text(size = 11),
      legend.position = "bottom"
    )

  # Add interpretation annotation
  interpretation <- if (!is.na(joint_p) && joint_p >= alpha) {
    "✓ Fail to reject H0: Pre-trends are not significantly different from zero\n(Parallel trends assumption supported)"
  } else if (!is.na(joint_p)) {
    "✗ Reject H0: Pre-trends are significantly different from zero\n(Parallel trends assumption violated)"
  } else {
    "Note: Joint test could not be computed (insufficient data)"
  }

  p <- p +
    annotate("text",
             x = mean(range(plot_data$event_time)),
             y = min(plot_data$ci_lower) - 0.1 * diff(range(c(plot_data$ci_lower, plot_data$ci_upper))),
             label = interpretation,
             hjust = 0.5, vjust = 1,
             size = 3.5,
             color = ifelse(!is.na(joint_p) && joint_p < alpha, "red", "darkgreen"),
             fontface = "italic")

  # Test results
  test_results <- list(
    joint_chisq = joint_chisq,
    joint_df = joint_df,
    joint_p = joint_p,
    individual_tests = plot_data[, c("event_time", "att", "se", "p_value", "significant")],
    passes_pretrends = if (!is.na(joint_p)) joint_p >= alpha else NA
  )

  return(list(plot = p, test_results = test_results))
}


#' Group-Specific Event Study Plots
#'
#' @param att_gt_result Result from att_gt_safe() or did::att_gt()
#' @param max_groups Maximum number of groups to plot (default: 6)
#' @param alpha Significance level (default: 0.05)
#' @param ncol Number of columns in facet (default: 2)
#'
#' @return ggplot object
plot_group_dynamics <- function(att_gt_result,
                                max_groups = 6,
                                alpha = 0.05,
                                ncol = 2) {

  # Get group-specific aggregation
  agg_group <- did::aggte(att_gt_result, type = "group", na.rm = TRUE)

  # Extract group-time ATTs
  gt_data <- data.frame(
    group = att_gt_result$group,
    time = att_gt_result$t,
    att = att_gt_result$att,
    se = att_gt_result$se
  ) %>%
    filter(!is.na(att)) %>%
    group_by(group) %>%
    mutate(
      event_time = time - group,
      ci_lower = att - qnorm(1 - alpha/2) * se,
      ci_upper = att + qnorm(1 - alpha/2) * se
    ) %>%
    ungroup()

  # Select top groups by number of observations
  top_groups <- gt_data %>%
    count(group, sort = TRUE) %>%
    head(max_groups) %>%
    pull(group)

  plot_data <- gt_data %>%
    filter(group %in% top_groups) %>%
    mutate(group = factor(group, levels = top_groups))

  # Create faceted plot
  p <- ggplot(plot_data, aes(x = event_time, y = att)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_vline(xintercept = -0.5, linetype = "solid", color = "gray30", linewidth = 0.3) +
    geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "steelblue") +
    geom_line(color = "steelblue", linewidth = 0.8) +
    geom_point(color = "steelblue", size = 1.5) +
    facet_wrap(~ group, scales = "free_y", ncol = ncol,
               labeller = labeller(group = function(x) paste("Group", x))) +
    labs(
      title = "Group-Specific Event Studies",
      subtitle = paste("Showing", length(top_groups), "groups with most observations"),
      x = "Event Time",
      y = "ATT",
      caption = paste0(100*(1-alpha), "% confidence intervals shown")
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      strip.text = element_text(face = "bold", size = 10),
      axis.title = element_text(size = 10),
      panel.grid.minor = element_blank()
    )

  return(p)
}


#' Calendar Time Effects Plot
#'
#' @param att_gt_result Result from att_gt_safe() or did::att_gt()
#' @param alpha Significance level (default: 0.05)
#'
#' @return ggplot object
plot_calendar_time <- function(att_gt_result, alpha = 0.05) {

  # Aggregate by calendar time
  agg_calendar <- did::aggte(att_gt_result, type = "calendar", na.rm = TRUE)

  # Extract data
  plot_data <- data.frame(
    time = agg_calendar$egt,
    att = agg_calendar$att.egt,
    se = agg_calendar$se.egt
  ) %>%
    mutate(
      ci_lower = att - qnorm(1 - alpha/2) * se,
      ci_upper = att + qnorm(1 - alpha/2) * se
    )

  # Create plot
  p <- ggplot(plot_data, aes(x = time, y = att)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "darkgreen") +
    geom_line(color = "darkgreen", linewidth = 1) +
    geom_point(color = "darkgreen", size = 2.5) +
    labs(
      title = "Calendar Time Effects",
      subtitle = "Average treatment effect by calendar period",
      x = "Calendar Time Period",
      y = "ATT",
      caption = paste0(100*(1-alpha), "% confidence intervals shown")
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      axis.title = element_text(size = 11),
      panel.grid.minor = element_blank()
    )

  return(p)
}


#' Support Heatmap: Visualize Identifiable (g,t) Cells
#'
#' @param att_gt_result Result from att_gt_safe() with support_diagnostics
#' @param max_groups Max groups to show (default: 20)
#' @param max_periods Max time periods to show (default: 50)
#'
#' @return ggplot object
plot_support_heatmap <- function(att_gt_result,
                                  max_groups = 20,
                                  max_periods = 50) {

  # Check if support diagnostics are available
  if (is.null(att_gt_result$support_diagnostics)) {
    stop("att_gt_result must include support_diagnostics. Use att_gt_safe() instead of did::att_gt().")
  }

  support_data <- att_gt_result$support_diagnostics

  # Select subset if too large
  unique_groups <- sort(unique(support_data$g))
  unique_times <- sort(unique(support_data$t))

  if (length(unique_groups) > max_groups) {
    unique_groups <- unique_groups[1:max_groups]
    support_data <- support_data %>% filter(g %in% unique_groups)
  }

  if (length(unique_times) > max_periods) {
    # Select periods around treatment
    mid <- length(unique_times) %/% 2
    keep_idx <- seq(max(1, mid - max_periods/2),
                   min(length(unique_times), mid + max_periods/2))
    unique_times <- unique_times[keep_idx]
    support_data <- support_data %>% filter(t %in% unique_times)
  }

  # Create plot
  p <- ggplot(support_data, aes(x = t, y = factor(g), fill = identifiable)) +
    geom_tile(color = "white", linewidth = 0.5) +
    scale_fill_manual(
      values = c("TRUE" = "steelblue", "FALSE" = "gray90"),
      labels = c("TRUE" = "Identifiable", "FALSE" = "Not identifiable"),
      name = "Cell Status"
    ) +
    labs(
      title = "Support Heatmap: Identifiable (g,t) Cells",
      subtitle = sprintf("%d of %d cells identifiable (%.1f%%)",
                        sum(support_data$identifiable),
                        nrow(support_data),
                        100 * mean(support_data$identifiable)),
      x = "Time Period",
      y = "Treatment Group"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      axis.text.y = element_text(size = 8),
      legend.position = "bottom"
    )

  return(p)
}


#' Create Comprehensive Pre-trends Report
#'
#' @param att_gt_result Result from att_gt_safe()
#' @param output_file Path to save PDF report (optional)
#' @param alpha Significance level (default: 0.05)
#'
#' @return List of plots
create_pretrends_report <- function(att_gt_result,
                                    output_file = NULL,
                                    alpha = 0.05) {

  cat("Generating pre-trends diagnostic report...\n\n")

  # 1. Main event study
  cat("1. Creating main event study plot...\n")
  p1 <- plot_event_study(att_gt_result, alpha = alpha)

  # 2. Pre-trends test
  cat("2. Running pre-trends test...\n")
  pretrends <- plot_pretrends_test(att_gt_result, alpha = alpha)
  p2 <- pretrends$plot

  # Print test results
  cat("\nPre-trends Joint Test Results:\n")
  cat(sprintf("  χ²(%.0f) = %.2f, p-value = %.4f\n",
              pretrends$test_results$joint_df,
              pretrends$test_results$joint_chisq,
              pretrends$test_results$joint_p))

  if (pretrends$test_results$passes_pretrends) {
    cat("  ✓ Parallel trends assumption SUPPORTED\n\n")
  } else {
    cat("  ✗ Parallel trends assumption VIOLATED\n\n")
  }

  # 3. Group dynamics
  cat("3. Creating group-specific event studies...\n")
  p3 <- plot_group_dynamics(att_gt_result, alpha = alpha)

  # 4. Calendar time
  cat("4. Creating calendar time plot...\n")
  p4 <- plot_calendar_time(att_gt_result, alpha = alpha)

  # 5. Support heatmap (if available)
  p5 <- NULL
  if (!is.null(att_gt_result$support_diagnostics)) {
    cat("5. Creating support heatmap...\n")
    p5 <- plot_support_heatmap(att_gt_result)
  }

  # Combine plots
  cat("\nCombining plots...\n")

  if (!is.null(p5)) {
    combined <- (p1 + p2) / (p3 + p4) / p5 +
      plot_annotation(
        title = "CS-DiD Pre-trends Diagnostic Report",
        theme = theme(plot.title = element_text(size = 16, face = "bold"))
      )
  } else {
    combined <- (p1 + p2) / (p3 + p4) +
      plot_annotation(
        title = "CS-DiD Pre-trends Diagnostic Report",
        theme = theme(plot.title = element_text(size = 16, face = "bold"))
      )
  }

  # Save if requested
  if (!is.null(output_file)) {
    cat(sprintf("\nSaving report to: %s\n", output_file))

    # Ensure output directory exists
    output_dir <- dirname(output_file)
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }

    ggsave(output_file, combined,
           width = 14, height = ifelse(!is.null(p5), 18, 12),
           dpi = 300)
    cat("✓ Report saved successfully\n")
  }

  cat("\n✓ Pre-trends report complete\n\n")

  # Return results
  invisible(list(
    event_study = p1,
    pretrends_test = p2,
    group_dynamics = p3,
    calendar_time = p4,
    support_heatmap = p5,
    combined = combined,
    test_results = pretrends$test_results
  ))
}


# If run as script, print usage
if (!interactive() && !exists("plot_csdid_pretrends_sourced")) {
  cat("\n")
  cat("========================================================================\n")
  cat("plot_csdid_pretrends.R - CS-DiD Pre-trends Visualization\n")
  cat("========================================================================\n\n")
  cat("Usage:\n")
  cat("  source('patches/plot_csdid_pretrends.R')\n\n")
  cat("  # Run CS-DiD estimation\n")
  cat("  result <- att_gt_safe(...)\n\n")
  cat("  # Create comprehensive report\n")
  cat("  report <- create_pretrends_report(\n")
  cat("    result,\n")
  cat("    output_file = 'output/figures/pretrends_report.pdf'\n")
  cat("  )\n\n")
  cat("  # Or create individual plots\n")
  cat("  p1 <- plot_event_study(result)\n")
  cat("  p2 <- plot_pretrends_test(result)\n")
  cat("  p3 <- plot_group_dynamics(result)\n")
  cat("  p4 <- plot_calendar_time(result)\n")
  cat("  p5 <- plot_support_heatmap(result)\n\n")
}

plot_csdid_pretrends_sourced <- TRUE
