# ==============================================================================
# fig4_calibration_scoreboard.R
# Scoreboard of null-DGP calibration for five staggered-DiD estimators, on the
# balanced state panel and the all-county panel. Two dot-plot sub-panels:
# (A) Type I error (rejection under the null) vs. nominal 0.05
# (B) SE / SD calibration ratio vs. 1.0
# Inputs:
#   data/output/cs_calibration_multi/calibration_summary.csv       (state)
#   output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv (county)
# Outputs:
#   figures/estimator_diagnostics/fig4_calibration_scoreboard.png
#   figures/estimator_diagnostics/fig4_calibration_scoreboard.pdf
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(patchwork)
  library(scales)
  library(here)
})

theme_set(theme_minimal(base_size = 12))

# ------------------------------------------------------------------------
# Paper-to-Code Naming Map
# ------------------------------------------------------------------------
# Concept                          | Code Name        | Description
# Estimator                        | method            | Display: TWFE, Sun-Abraham,
#                                   |                   | CS analytic, BJS (didimputation),
#                                   |                   | did2s (Gardner)
# Panel level                      | panel             | "State panel" (n=20 null sims) or
#                                   |                   | "County panel" (n=50 null sims)
# Type I error (rejection)         | rejection         | From calibration_summary.csv
# SE/SD calibration ratio          | se_over_sd        | mean_se / sd_att
# Convergence status               | status            | "ok" / "failed" / "missing"
# ------------------------------------------------------------------------

# ---- Paths (project-root relative) -----------------------------------------
STATE_SUMMARY_PATH  <- here("data/output/cs_calibration_multi/calibration_summary.csv")
COUNTY_SUMMARY_PATH <- here(
  "output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv"
)
OUT_DIR <- here("figures/estimator_diagnostics")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

stopifnot(file.exists(STATE_SUMMARY_PATH), file.exists(COUNTY_SUMMARY_PATH))

# ---- Method display map -----------------------------------------------------
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

COL_STATE  <- "#0072B2"  # Okabe-Ito blue
COL_COUNTY <- "#D55E00"  # Okabe-Ito vermillion

# ---- Load and harmonize summaries -------------------------------------------
state_summary <- read_csv(STATE_SUMMARY_PATH, show_col_types = FALSE) |>
  mutate(panel = "State panel")

county_summary <- read_csv(COUNTY_SUMMARY_PATH, show_col_types = FALSE) |>
  mutate(panel = "County panel")

summary_all <- bind_rows(state_summary, county_summary) |>
  mutate(
    method = unname(METHOD_LOOKUP[method]),
    panel  = factor(panel, levels = c("State panel", "County panel"))
  )
stopifnot(!any(is.na(summary_all$method)))

# ---- Ensure every (method, panel) combination is represented; flag gaps -----
all_combos <- expand_grid(
  method = METHOD_ORDER,
  panel  = factor(c("State panel", "County panel"), levels = c("State panel", "County panel"))
)

scoreboard <- all_combos |>
  left_join(summary_all, by = c("method", "panel")) |>
  mutate(
    status = case_when(
      is.na(n_valid)  ~ "missing",
      n_valid == 0L   ~ "failed",
      TRUE            ~ "ok"
    ),
    method = factor(method, levels = rev(METHOD_ORDER))  # TWFE plots at top
  )

n_gaps <- sum(scoreboard$status != "ok")
if (n_gaps > 0L) {
  message(sprintf(
    "fig4: %d method x panel cell(s) missing/failed and will be flagged.", n_gaps
  ))
}

pts_ok  <- filter(scoreboard, status == "ok")
pts_bad <- filter(scoreboard, status != "ok")

# ---- Binomial 95% Monte Carlo noise band around nominal alpha = 0.05 --------
binom_band <- function(n, p0 = 0.05, level = 0.95) {
  z  <- qnorm(1 - (1 - level) / 2)
  se <- sqrt(p0 * (1 - p0) / n)
  c(lo = max(0, p0 - z * se), hi = min(1, p0 + z * se))
}

n_state  <- unique(pts_ok$n_valid[pts_ok$panel == "State panel"])
n_county <- unique(pts_ok$n_valid[pts_ok$panel == "County panel"])
stopifnot(length(n_state) == 1L, length(n_county) == 1L)

band_state  <- binom_band(n_state)
band_county <- binom_band(n_county)

# ------------------------------------------------------------------------
# Sub-panel A: Type I error (rejection under the null)
# ------------------------------------------------------------------------
rejection_label_max <- max(pts_ok$rejection, na.rm = TRUE)

pA <- ggplot(pts_ok, aes(x = rejection, y = method, color = panel, shape = panel)) +
  annotate(
    "rect", xmin = band_state["lo"], xmax = band_state["hi"], ymin = -Inf, ymax = Inf,
    fill = COL_STATE, alpha = 0.08
  ) +
  annotate(
    "rect", xmin = band_county["lo"], xmax = band_county["hi"], ymin = -Inf, ymax = Inf,
    fill = COL_COUNTY, alpha = 0.10
  ) +
  geom_vline(xintercept = 0.05, linetype = "dashed", color = "grey30") +
  geom_point(size = 3, position = position_dodge(width = 0.45)) +
  geom_text(
    aes(label = percent(rejection, accuracy = 1)),
    position = position_dodge(width = 0.45), hjust = -0.35, size = 3.1,
    show.legend = FALSE
  )

if (nrow(pts_bad) > 0L) {
  pA <- pA +
    geom_point(
      data = pts_bad, aes(x = 0, y = method), inherit.aes = FALSE,
      shape = 4, size = 3, color = "grey40"
    ) +
    geom_text(
      data = pts_bad, aes(x = 0, y = method, label = "not run"),
      inherit.aes = FALSE, hjust = -0.15, size = 3.1, color = "grey40"
    )
}

pA <- pA +
  scale_color_manual(values = c("State panel" = COL_STATE, "County panel" = COL_COUNTY)) +
  scale_shape_manual(values = c("State panel" = 16, "County panel" = 17)) +
  scale_x_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, rejection_label_max * 1.4),
    expand = expansion(mult = c(0.02, 0.05))
  ) +
  labs(
    x = "Rejection rate under the null (Type I error)",
    y = NULL, color = "Panel", shape = "Panel",
    subtitle = "A. Type I error\n(nominal alpha = 0.05, dashed line; shaded = 95% MC noise band)"
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

# ------------------------------------------------------------------------
# Sub-panel B: SE / SD calibration ratio
# ------------------------------------------------------------------------
pB <- ggplot(pts_ok, aes(x = se_over_sd, y = method, color = panel, shape = panel)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "grey30") +
  geom_point(size = 3, position = position_dodge(width = 0.45)) +
  geom_text(
    aes(label = sprintf("%.2f", se_over_sd)),
    position = position_dodge(width = 0.45), hjust = -0.35, size = 3.1,
    show.legend = FALSE
  )

if (nrow(pts_bad) > 0L) {
  pB <- pB +
    geom_point(
      data = pts_bad, aes(x = 0, y = method), inherit.aes = FALSE,
      shape = 4, size = 3, color = "grey40"
    ) +
    geom_text(
      data = pts_bad, aes(x = 0, y = method, label = "not run"),
      inherit.aes = FALSE, hjust = -0.15, size = 3.1, color = "grey40"
    )
}

pB <- pB +
  annotate(
    "text", x = 0.55, y = Inf, vjust = 1.6, hjust = 0.5, size = 3.1,
    fontface = "italic", color = "grey35",
    label = "SEs too small ->\nover-rejects"
  ) +
  annotate(
    "text", x = 2.1, y = Inf, vjust = 1.6, hjust = 0.5, size = 3.1,
    fontface = "italic", color = "grey35",
    label = "SEs too big ->\nover-covers"
  ) +
  scale_color_manual(values = c("State panel" = COL_STATE, "County panel" = COL_COUNTY)) +
  scale_shape_manual(values = c("State panel" = 16, "County panel" = 17)) +
  scale_x_continuous(limits = c(0, 2.65), expand = expansion(mult = c(0.02, 0.05))) +
  labs(
    x = "SE / SD (mean claimed SE / SD of null ATT draws)",
    y = NULL, color = "Panel", shape = "Panel",
    subtitle = "B. Calibration ratio\n(dashed line at 1.0)"
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

# ------------------------------------------------------------------------
# Combine and export
# ------------------------------------------------------------------------
fig4 <- (pA + pB) +
  plot_layout(guides = "collect") &
  theme(legend.position = "top")

fig4 <- fig4 +
  plot_annotation(
    title = "Null-DGP calibration scoreboard: five staggered-DiD estimators",
    subtitle = paste0(
      "State panel = balanced 24-state estimation sample (11 treated, all singleton ",
      "cohorts), n = ", n_state, " null simulations. County panel: n = ", n_county,
      " null simulations. True effect = 0 in both."
    ),
    caption = paste0(
      "Shaded bands (Panel A) are 95% Monte Carlo noise bands around the nominal ",
      "5% rejection rate, computed from a binomial approximation given each ",
      "panel's simulation count."
    )
  )

ggsave(
  file.path(OUT_DIR, "fig4_calibration_scoreboard.png"),
  plot = fig4, width = 11, height = 7, dpi = 300
)
ggsave(
  file.path(OUT_DIR, "fig4_calibration_scoreboard.pdf"),
  plot = fig4, width = 11, height = 7
)

message("fig4: wrote fig4_calibration_scoreboard.{png,pdf} to ", OUT_DIR)

# ---- Print displayed values for verification/handoff ------------------------
print(
  scoreboard |>
    arrange(panel, method) |>
    select(panel, method, status, n_valid, rejection, se_over_sd)
)
