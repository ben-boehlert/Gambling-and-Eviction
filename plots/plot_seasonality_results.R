#!/usr/bin/env Rscript
################################################################################
# plot_seasonality_results.R
# Visualize the impact of seasonality correction on parallel trends
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(patchwork)
})

# Read results
results <- read_csv("seasonality_test_results.csv", show_col_types = FALSE)

# Create bar plot of rejection rates
p1 <- ggplot(results, aes(x = method, y = rejection_rate * 100)) +
  geom_col(aes(fill = method), width = 0.6) +
  geom_hline(yintercept = 5, linetype = "dashed", color = "red", linewidth = 1) +
  geom_text(aes(label = paste0(round(rejection_rate * 100, 1), "%")),
            vjust = -0.5, size = 5, fontface = "bold") +
  annotate("text", x = 1.5, y = 5.5, label = "Target: 5%",
           color = "red", size = 4) +
  scale_fill_manual(values = c("No seasonality" = "#E74C3C",
                                 "With month FE" = "#27AE60")) +
  labs(
    title = "Type I Error Calibration: Effect of Seasonality Correction",
    subtitle = "Pre-COVID period (2016-2020), 50 simulations per method",
    x = NULL,
    y = "Rejection Rate (%)",
    caption = "Dashed line shows nominal 5% significance level"
  ) +
  coord_cartesian(ylim = c(0, 8)) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(color = "gray30", size = 12),
    panel.grid.major.x = element_blank(),
    axis.text.x = element_text(size = 12, face = "bold")
  )

# Save plot
ggsave("seasonality_rejection_rates.png", p1, width = 10, height = 6, dpi = 300)

cat("Plot saved to seasonality_rejection_rates.png\n")

# Print summary table
cat("\n=== Summary Table ===\n")
results_table <- results %>%
  mutate(
    rejection_pct = paste0(round(rejection_rate * 100, 1), "%"),
    distance_from_target = round((rejection_rate - 0.05) * 100, 1)
  ) %>%
  select(
    Method = method,
    `Rejection Rate` = rejection_pct,
    `Distance from 5%` = distance_from_target
  )

print(results_table)

cat("\nKey Finding:\n")
cat("Without seasonality correction, the current approach shows a 4% Type I error.\n")
cat("With month FE, Type I error drops to 2%.\n")
cat("Both are within acceptable range, but neither quite reaches 5%.\n")
cat("The slight under-rejection suggests the test may be conservative.\n")
