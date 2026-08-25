# ==============================================================================
# fig5_null_distributions.R
# Null (effect = 0) ATT draws for five staggered-DiD estimators, on the
# balanced state panel and the all-county panel, with each estimator's
# claimed +/-1.96 x mean(SE) interval overlaid on the empirical spread.
# Also recomputes the Type I error directly from sim_results.csv and
# cross-checks against calibration_summary.csv.
# Inputs:
#   data/output/cs_calibration_multi/calibration_summary.csv
#   data/output/cs_calibration_multi/sim_results.csv
#   output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv
#   output/border_diagnostic/cs_calibration_multi_county/sim_results.csv
# Outputs:
#   figures/estimator_diagnostics/fig5_null_distributions.png
#   figures/estimator_diagnostics/fig5_null_distributions.pdf
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(scales)
  library(here)
})

theme_set(theme_minimal(base_size = 12))

# ------------------------------------------------------------------------
# Paper-to-Code Naming Map
# ------------------------------------------------------------------------
# Concept                          | Code Name          | Description
# Estimator                        | method              | Display: TWFE, Sun-Abraham,
#                                   |                     | CS analytic, BJS (didimputation),
#                                   |                     | did2s (Gardner)
# Panel level                      | panel               | "State panel" (20 sims) /
#                                   |                     | "County panel" (50 sims)
# Null ATT draw                    | att                 | Per-sim point estimate
# Claimed SE                       | se                  | Per-sim reported SE
# Convergence flag                 | ok                  | Per-sim convergence indicator
# Type I error (summary CSV)       | rejection_summary   | From calibration_summary.csv
# Type I error (recomputed)        | rejection_recomp    | mean(p < 0.05) among ok == TRUE
# ------------------------------------------------------------------------

# ---- Paths -------------------------------------------------------------
STATE_SUMMARY_PATH  <- here("data/output/cs_calibration_multi/calibration_summary.csv")
STATE_SIM_PATH       <- here("data/output/cs_calibration_multi/sim_results.csv")
COUNTY_SUMMARY_PATH <- here(
  "output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv"
)
COUNTY_SIM_PATH <- here(
  "output/border_diagnostic/cs_calibration_multi_county/sim_results.csv"
)
OUT_DIR <- here("figures/estimator_diagnostics")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

stopifnot(
  file.exists(STATE_SUMMARY_PATH), file.exists(STATE_SIM_PATH),
  file.exists(COUNTY_SUMMARY_PATH), file.exists(COUNTY_SIM_PATH)
)

METHOD_KEY_LOOKUP <- c(
  twfe   = "TWFE",
  sunab  = "Sun-Abraham",
  cs     = "CS analytic",
  didimp = "BJS (didimputation)",
  did2s  = "did2s (Gardner)"
)
METHOD_LOOKUP <- c(
  "TWFE (fixest)"        = "TWFE",
  "Sun-Abraham (fixest)" = "Sun-Abraham",
  "CS Analytic (did)"    = "CS analytic",
  "didimputation (BJS)"  = "BJS (didimputation)",
  "did2s (Gardner)"      = "did2s (Gardner)"
)
METHOD_ORDER <- c(
  "TWFE", "Sun-Abraham", "CS analytic", "BJS (didimputation)", "did2s (Gardner)"
)

COL_BAND <- "#D55E00"  # Okabe-Ito vermillion: claimed CI band
COL_BOX  <- "grey40"

# ---- Helper: wide sim_results -> long (method, ok, att, se, p) --------------
pivot_sim_long <- function(path, panel_label) {
  raw <- read_csv(path, show_col_types = FALSE)
  long <- raw |>
    pivot_longer(
      cols = -seed,
      names_to = c("method_key", ".value"),
      names_pattern = "^(twfe|sunab|cs|didimp|did2s)_(ok|att|se|p)$"
    ) |>
    mutate(
      method = unname(METHOD_KEY_LOOKUP[method_key]),
      panel  = panel_label
    )
  stopifnot(!any(is.na(long$method)))
  long
}

sim_state  <- pivot_sim_long(STATE_SIM_PATH, "State panel")
sim_county <- pivot_sim_long(COUNTY_SIM_PATH, "County panel")
sim_all    <- bind_rows(sim_state, sim_county)

# ---- Load summaries for cross-check -----------------------------------------
summary_state <- read_csv(STATE_SUMMARY_PATH, show_col_types = FALSE) |>
  mutate(panel = "State panel", method = unname(METHOD_LOOKUP[method]))
summary_county <- read_csv(COUNTY_SUMMARY_PATH, show_col_types = FALSE) |>
  mutate(panel = "County panel", method = unname(METHOD_LOOKUP[method]))
summary_all <- bind_rows(summary_state, summary_county) |>
  select(panel, method, rejection_summary = rejection, n_valid)

# ---- Recompute Type I error directly from sim_results and cross-check -------
sim_ok <- filter(sim_all, ok == TRUE)  # nolint: keep explicit for readability

recomputed <- sim_ok |>
  group_by(panel, method) |>
  summarise(
    n_ok               = n(),
    rejection_recomp   = mean(p < 0.05, na.rm = TRUE),
    mean_att            = mean(att, na.rm = TRUE),
    mean_se             = mean(se, na.rm = TRUE),
    .groups = "drop"
  )

crosscheck <- recomputed |>
  left_join(summary_all, by = c("panel", "method")) |>
  mutate(discrepancy = abs(rejection_recomp - rejection_summary))

discrepant <- filter(crosscheck, discrepancy > 1e-9)
if (nrow(discrepant) > 0L) {
  message(
    "fig5: rejection recomputation DISAGREES with calibration_summary.csv for ",
    nrow(discrepant), " method x panel cell(s). Displaying recomputed values."
  )
} else {
  message("fig5: recomputed rejection rates match calibration_summary.csv exactly.")
}

# ---- Assemble plotting frames -----------------------------------------------
plot_points <- sim_ok |>
  mutate(
    method = factor(method, levels = rev(METHOD_ORDER)),
    panel  = factor(panel, levels = c("State panel", "County panel"))
  )

# Data-driven display range per panel: sized to the empirical ATT draws
# (never to the claimed SE bands), padded 15% on each side. Claimed bands
# that exceed this range are capped visually and flagged with an arrow +
# a "full width" annotation rather than silently stretching the axis.
DISPLAY_PAD <- 0.15
panel_range <- plot_points |>
  group_by(panel) |>
  summarise(pts_lo = min(att, na.rm = TRUE), pts_hi = max(att, na.rm = TRUE), .groups = "drop") |>
  mutate(
    span    = pts_hi - pts_lo,
    disp_lo = pts_lo - DISPLAY_PAD * span,
    disp_hi = pts_hi + DISPLAY_PAD * span
  )

band_data <- recomputed |>
  mutate(
    band_lo = mean_att - 1.96 * mean_se,
    band_hi = mean_att + 1.96 * mean_se,
    method  = factor(method, levels = rev(METHOD_ORDER)),
    panel   = factor(panel, levels = c("State panel", "County panel"))
  ) |>
  left_join(panel_range, by = "panel") |>
  mutate(
    half_width  = (band_hi - band_lo) / 2,
    is_clip_lo  = band_lo < disp_lo,
    is_clip_hi  = band_hi > disp_hi,
    band_lo_vis = pmax(band_lo, disp_lo),
    band_hi_vis = pmin(band_hi, disp_hi)
  )

arrow_lo <- filter(band_data, is_clip_lo)
arrow_hi <- filter(band_data, is_clip_hi)
clip_note <- filter(band_data, is_clip_lo | is_clip_hi) |>
  mutate(note_label = sprintf("full band +/-%.3f", half_width))

if (nrow(clip_note) > 0L) {
  message(
    "fig5: claimed SE band exceeds the data-driven display range for ",
    nrow(clip_note), " method x panel cell(s); capped with arrow + width note."
  )
}

label_data <- crosscheck |>
  mutate(
    label  = sprintf("Type I: %s", percent(rejection_recomp, accuracy = 1)),
    method = factor(method, levels = rev(METHOD_ORDER)),
    panel  = factor(panel, levels = c("State panel", "County panel"))
  )

# ------------------------------------------------------------------------
# Build figure
# Type I labels sit at a fixed right-margin position (x = Inf) so they can
# never collide with the band or the point cloud, regardless of how wide
# the claimed SE band is.
# ------------------------------------------------------------------------
fig5 <- ggplot(plot_points, aes(x = att, y = method)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_boxplot(
    width = 0.5, outlier.shape = NA, fill = "grey90", color = COL_BOX,
    alpha = 0.7, linewidth = 0.4
  ) +
  geom_jitter(
    height = 0.12, width = 0, alpha = 0.45, size = 1.4, color = "grey25"
  ) +
  geom_segment(
    data = band_data,
    aes(x = band_lo_vis, xend = band_hi_vis, y = method, yend = method),
    inherit.aes = FALSE, color = COL_BAND, linewidth = 2.2, alpha = 0.85
  ) +
  geom_point(
    data = band_data, aes(x = mean_att, y = method),
    inherit.aes = FALSE, color = COL_BAND, size = 2, shape = 18
  ) +
  { if (nrow(arrow_lo) > 0L) {
    geom_segment(
      data = arrow_lo,
      aes(x = band_lo_vis + 0.06 * span, xend = band_lo_vis, y = method, yend = method),
      inherit.aes = FALSE, color = COL_BAND, linewidth = 1.3,
      arrow = grid::arrow(length = unit(0.10, "cm"), type = "closed")
    )
  } } +
  { if (nrow(arrow_hi) > 0L) {
    geom_segment(
      data = arrow_hi,
      aes(x = band_hi_vis - 0.06 * span, xend = band_hi_vis, y = method, yend = method),
      inherit.aes = FALSE, color = COL_BAND, linewidth = 1.3,
      arrow = grid::arrow(length = unit(0.10, "cm"), type = "closed")
    )
  } } +
  { if (nrow(clip_note) > 0L) {
    geom_text(
      data = clip_note, aes(x = mean_att, y = method, label = note_label),
      inherit.aes = FALSE, color = COL_BAND, size = 2.6, fontface = "italic",
      nudge_y = -0.32
    )
  } } +
  geom_text(
    data = label_data,
    aes(x = Inf, y = method, label = label),
    inherit.aes = FALSE, hjust = 1.05, size = 3.1, color = "grey20"
  ) +
  facet_wrap(~panel, scales = "free_x", ncol = 2) +
  coord_cartesian(clip = "off") +
  scale_x_continuous(expand = expansion(mult = c(0.05, 0.20))) +
  labs(
    x = "Null ATT draw (log points; true effect = 0, dashed line)",
    y = NULL,
    title = "Null-DGP distribution of ATT estimates vs. claimed confidence bands",
    subtitle = paste0(
      "State panel: n = 20 null simulations. County panel: n = 50 null simulations.\n",
      "Grey = boxplot + jittered draws; vermillion band = claimed mean(ATT) +/- 1.96 x mean(SE).\n",
      "Where the band is much narrower than the point spread, the estimator over-rejects; ",
      "where much wider, it over-covers."
    ),
    caption = "Type I error labels are recomputed directly from sim_results.csv (share of p < 0.05 among converged draws)."
  ) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.subtitle = element_text(size = 9),
    plot.caption = element_text(size = 8, color = "grey40"),
    panel.spacing.x = unit(2.4, "lines"),
    plot.margin = margin(t = 5, r = 30, b = 5, l = 5)
  )

ggsave(
  file.path(OUT_DIR, "fig5_null_distributions.png"),
  plot = fig5, width = 11, height = 7, dpi = 300
)
ggsave(
  file.path(OUT_DIR, "fig5_null_distributions.pdf"),
  plot = fig5, width = 11, height = 7
)

message("fig5: wrote fig5_null_distributions.{png,pdf} to ", OUT_DIR)

# ---- Print cross-check table for verification/handoff -----------------------
print(
  crosscheck |>
    arrange(panel, method) |>
    select(panel, method, n_ok, rejection_summary, rejection_recomp, discrepancy)
)
