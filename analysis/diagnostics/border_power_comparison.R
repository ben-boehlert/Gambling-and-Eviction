#!/usr/bin/env Rscript
################################################################################
# border_power_comparison.R
#
# Side-by-side comparison of border-county TWFE vs state-panel TWFE power.
#
# Inputs:
#   output/border_diagnostic/power_border_twfe.csv
#   output/border_diagnostic/power_state_twfe.csv
#
# Outputs:
#   output/border_diagnostic/power_comparison.csv
#   output/border_diagnostic/power_comparison.png
#   output/border_diagnostic/calibration_check.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
})

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")

pb <- read_csv(file.path(out_dir, "power_border_twfe.csv"),
               show_col_types = FALSE)
ps <- read_csv(file.path(out_dir, "power_state_twfe.csv"),
               show_col_types = FALSE)

# ----------------------------- side-by-side -----------------------------------
both <- bind_rows(pb, ps)

wide <- both %>%
  select(panel_label, effect_pct, rejection_rate, sd_att, mean_se,
         se_over_sdatt) %>%
  pivot_wider(names_from = panel_label,
              values_from = c(rejection_rate, sd_att, mean_se, se_over_sdatt))

write_csv(wide, file.path(out_dir, "power_comparison.csv"))

# ----------------------------- calibration check ------------------------------
# Type I at effect_pct = 0; SE/SD ratio.
calib <- both %>%
  filter(abs(effect_pct) < 1e-12) %>%
  select(panel_label, n_sims, n_ok, type1 = rejection_rate,
         mean_att, sd_att, mean_se, se_over_sdatt) %>%
  mutate(
    type1_low_ci  = pmax(0, type1 - 1.96 * sqrt(type1 * (1 - type1) / n_ok)),
    type1_high_ci = pmin(1, type1 + 1.96 * sqrt(type1 * (1 - type1) / n_ok)),
    calibration_verdict = case_when(
      type1 < 0.025 ~ "under-rejects (SEs too large)",
      type1 > 0.075 ~ "over-rejects (SEs too small)",
      TRUE          ~ "well-calibrated"
    )
  )
write_csv(calib, file.path(out_dir, "calibration_check.csv"))

cat("\n=== CALIBRATION ===\n")
print(calib)

# ----------------------------- MDE at 80% power -------------------------------
mde_table <- both %>%
  group_by(panel_label) %>%
  arrange(effect_pct) %>%
  summarise(
    mde_80 = {
      ge <- which(rejection_rate >= 0.80)
      if (length(ge) == 0) NA_real_ else effect_pct[min(ge)]
    },
    rej_at_005 = rejection_rate[abs(effect_pct - 0.05) < 1e-6][1],
    rej_at_010 = rejection_rate[abs(effect_pct - 0.10) < 1e-6][1],
    rej_at_020 = rejection_rate[abs(effect_pct - 0.20) < 1e-6][1],
    .groups = "drop"
  )
write_csv(mde_table, file.path(out_dir, "mde_summary.csv"))

cat("\n=== MDE (lowest effect with rejection >= 0.80 in tested grid) ===\n")
print(mde_table)

# ----------------------------- plot -------------------------------------------
p <- both %>%
  mutate(panel_label = recode(panel_label,
                              state_twfe_baseline = "State panel (baseline)",
                              border_county_twfe  = "Border-county panel")) %>%
  ggplot(aes(x = effect_pct, y = rejection_rate,
             color = panel_label, shape = panel_label, linetype = panel_label)) +
  geom_hline(yintercept = 0.80, linetype = "dotted", color = "grey50") +
  geom_hline(yintercept = 0.05, linetype = "dotted", color = "grey70") +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.5) +
  scale_x_continuous(breaks = unique(both$effect_pct),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
  scale_color_grey(start = 0.2, end = 0.55, name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  scale_linetype_manual(values = c("solid", "dashed"), name = NULL) +
  labs(x = "True treatment effect (log-points)",
       y = "Rejection rate (n=200 sims, alpha=0.05)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background = element_rect(fill = "transparent", color = NA),
    plot.background  = element_rect(fill = "transparent", color = NA)
  )

ggsave(file.path(out_dir, "power_comparison.png"), p,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")
cat("\nWrote:\n",
    "  ", file.path(out_dir, "power_comparison.csv"), "\n",
    "  ", file.path(out_dir, "calibration_check.csv"), "\n",
    "  ", file.path(out_dir, "mde_summary.csv"), "\n",
    "  ", file.path(out_dir, "power_comparison.png"), "\n")
