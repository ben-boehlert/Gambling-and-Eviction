#!/usr/bin/env Rscript
################################################################################
# generate_support_plots.R
#
# Generate plots from existing support diagnostics (no CS-DiD estimation needed)
################################################################################

library(dplyr)
library(ggplot2)

cat("Generating plots from existing support diagnostics...\n\n")

# Load support diagnostics
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

cat(sprintf("Loaded %d (g,t) cells\n", nrow(support)))
cat(sprintf("  Identifiable: %d (%.1f%%)\n",
            sum(support$identifiable),
            100 * mean(support$identifiable)))
cat(sprintf("  Non-identifiable: %d (%.1f%%)\n\n",
            sum(!support$identifiable),
            100 * mean(!support$identifiable)))

# Create output directory
dir.create("output/csdid_plots", showWarnings = FALSE, recursive = TRUE)

# ========================================================================
# Plot 1: Support Heatmap
# ========================================================================

cat("Creating support heatmap...\n")

# Select reasonable subset for visualization
groups <- sort(unique(support$g))
times <- sort(unique(support$t))

# Take first 15 groups and middle 60 time periods for visibility
g_subset <- groups[1:min(15, length(groups))]
t_mid <- length(times) %/% 2
t_subset <- times[max(1, t_mid - 30):min(length(times), t_mid + 30)]

support_viz <- support %>%
  filter(g %in% g_subset, t %in% t_subset)

p1 <- ggplot(support_viz, aes(x = t, y = factor(g), fill = identifiable)) +
  geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_manual(
    values = c("TRUE" = "steelblue", "FALSE" = "gray90"),
    labels = c("TRUE" = "Identifiable", "FALSE" = "Not identifiable"),
    name = "Cell Status"
  ) +
  labs(
    title = "CS-DiD Support Heatmap: Which (g,t) Cells Are Identifiable?",
    subtitle = sprintf("Showing %d groups × %d time periods (subset of full data)",
                      length(g_subset), length(t_subset)),
    x = "Time Period",
    y = "Treatment Group"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

ggsave("output/csdid_plots/support_heatmap.pdf", p1, width = 12, height = 8)
ggsave("output/csdid_plots/support_heatmap.png", p1, width = 12, height = 8, dpi = 300)
cat("  ✓ Saved: output/csdid_plots/support_heatmap.pdf\n")
cat("  ✓ Saved: output/csdid_plots/support_heatmap.png\n\n")

# ========================================================================
# Plot 2: Identifiability by Event Time
# ========================================================================

cat("Creating identifiability by event time plot...\n")

support_by_event <- support %>%
  mutate(event_time = t - g) %>%
  group_by(event_time) %>%
  summarise(
    n_total = n(),
    n_identifiable = sum(identifiable),
    pct_identifiable = 100 * mean(identifiable),
    .groups = "drop"
  ) %>%
  arrange(event_time)

p2 <- ggplot(support_by_event, aes(x = event_time, y = pct_identifiable)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 2) +
  geom_hline(yintercept = 50, linetype = "dashed", color = "red", alpha = 0.5) +
  geom_vline(xintercept = 0, linetype = "solid", color = "gray30", linewidth = 0.5) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 25)) +
  labs(
    title = "Cell Identifiability by Event Time",
    subtitle = "Percentage of (g,t) cells that are identifiable at each event time",
    x = "Event Time (periods relative to treatment)",
    y = "% Identifiable Cells",
    caption = "Cells are non-identifiable when treated units not observed in that period"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

ggsave("output/csdid_plots/identifiability_by_event_time.pdf", p2, width = 10, height = 6)
ggsave("output/csdid_plots/identifiability_by_event_time.png", p2, width = 10, height = 6, dpi = 300)
cat("  ✓ Saved: output/csdid_plots/identifiability_by_event_time.pdf\n")
cat("  ✓ Saved: output/csdid_plots/identifiability_by_event_time.png\n\n")

# ========================================================================
# Plot 3: Identifiability by Treatment Group
# ========================================================================

cat("Creating identifiability by group plot...\n")

support_by_group <- support %>%
  group_by(g) %>%
  summarise(
    n_total = n(),
    n_identifiable = sum(identifiable),
    pct_identifiable = 100 * mean(identifiable),
    .groups = "drop"
  ) %>%
  arrange(g)

p3 <- ggplot(support_by_group, aes(x = factor(g), y = pct_identifiable)) +
  geom_col(fill = "steelblue", alpha = 0.8) +
  geom_hline(yintercept = 50, linetype = "dashed", color = "red", alpha = 0.5) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 25)) +
  labs(
    title = "Cell Identifiability by Treatment Group",
    subtitle = "Percentage of time periods where each group is identifiable",
    x = "Treatment Group (first treatment time)",
    y = "% Identifiable Cells",
    caption = sprintf("Based on %d treatment groups", nrow(support_by_group))
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid.minor = element_blank()
  )

ggsave("output/csdid_plots/identifiability_by_group.pdf", p3, width = 10, height = 6)
ggsave("output/csdid_plots/identifiability_by_group.png", p3, width = 10, height = 6, dpi = 300)
cat("  ✓ Saved: output/csdid_plots/identifiability_by_group.pdf\n")
cat("  ✓ Saved: output/csdid_plots/identifiability_by_group.png\n\n")

# ========================================================================
# Plot 4: Cell Counts Distribution
# ========================================================================

cat("Creating cell counts distribution plot...\n")

support_long <- support %>%
  select(g, t, identifiable, n_treat_pre, n_treat_post, n_control_pre, n_control_post) %>%
  tidyr::pivot_longer(
    cols = c(n_treat_pre, n_treat_post, n_control_pre, n_control_post),
    names_to = "cell_type",
    values_to = "n_obs"
  ) %>%
  mutate(
    cell_type = factor(cell_type,
                      levels = c("n_treat_pre", "n_treat_post", "n_control_pre", "n_control_post"),
                      labels = c("Treated × Pre", "Treated × Post", "Control × Pre", "Control × Post"))
  )

p4 <- ggplot(support_long, aes(x = n_obs, fill = cell_type)) +
  geom_histogram(bins = 30, alpha = 0.7, position = "identity") +
  facet_wrap(~ cell_type, scales = "free_y") +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Distribution of Cell Observation Counts",
    subtitle = "How many observations in each cell type across all (g,t) comparisons?",
    x = "Number of Observations",
    y = "Frequency (number of cells)",
    caption = "Zero counts indicate non-identifiable cells"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    legend.position = "none",
    panel.grid.minor = element_blank()
  )

ggsave("output/csdid_plots/cell_counts_distribution.pdf", p4, width = 12, height = 8)
ggsave("output/csdid_plots/cell_counts_distribution.png", p4, width = 12, height = 8, dpi = 300)
cat("  ✓ Saved: output/csdid_plots/cell_counts_distribution.pdf\n")
cat("  ✓ Saved: output/csdid_plots/cell_counts_distribution.png\n\n")

# ========================================================================
# Summary Statistics Table
# ========================================================================

cat("Creating summary statistics table...\n")

summary_stats <- data.frame(
  Metric = c(
    "Total (g,t) cells",
    "Identifiable cells",
    "Non-identifiable cells",
    "Treatment groups",
    "Time periods",
    "Min event time",
    "Max event time"
  ),
  Value = c(
    nrow(support),
    sum(support$identifiable),
    sum(!support$identifiable),
    length(unique(support$g)),
    length(unique(support$t)),
    min(support$t - support$g),
    max(support$t - support$g)
  ),
  Percentage = c(
    100,
    100 * mean(support$identifiable),
    100 * mean(!support$identifiable),
    NA, NA, NA, NA
  )
)

write.csv(summary_stats, "output/csdid_plots/summary_statistics.csv", row.names = FALSE)
cat("  ✓ Saved: output/csdid_plots/summary_statistics.csv\n\n")

# Reason breakdown
reason_summary <- support %>%
  filter(!identifiable) %>%
  count(reason) %>%
  arrange(desc(n)) %>%
  mutate(percentage = 100 * n / sum(n))

write.csv(reason_summary, "output/csdid_plots/non_identifiable_reasons.csv", row.names = FALSE)
cat("  ✓ Saved: output/csdid_plots/non_identifiable_reasons.csv\n\n")

# ========================================================================
# Summary
# ========================================================================

cat("========================================================================\n")
cat("PLOTS GENERATED SUCCESSFULLY\n")
cat("========================================================================\n\n")

cat("Output directory: output/csdid_plots/\n\n")

cat("Files created:\n")
cat("  PDF plots (publication quality):\n")
cat("    - support_heatmap.pdf\n")
cat("    - identifiability_by_event_time.pdf\n")
cat("    - identifiability_by_group.pdf\n")
cat("    - cell_counts_distribution.pdf\n\n")

cat("  PNG plots (for presentations/slides):\n")
cat("    - support_heatmap.png\n")
cat("    - identifiability_by_event_time.png\n")
cat("    - identifiability_by_group.png\n")
cat("    - cell_counts_distribution.png\n\n")

cat("  Tables:\n")
cat("    - summary_statistics.csv\n")
cat("    - non_identifiable_reasons.csv\n\n")

cat("View plots:\n")
cat("  open output/csdid_plots/support_heatmap.pdf\n")
cat("  open output/csdid_plots/identifiability_by_event_time.pdf\n\n")

cat("========================================================================\n")
