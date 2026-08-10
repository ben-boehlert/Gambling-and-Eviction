#!/usr/bin/env Rscript
################################################################################
# border_power_comparison_4way.R
#
# Side-by-side comparison of all four power sims, isolating the contributions
# of sample selection vs. disaggregation:
#
#   Sim A:  all counties, aggregated to state         (power_state_twfe.csv)
#   Sim B:  border counties only, aggregated to state (power_border_state_agg_twfe.csv)
#   Sim C:  border counties, county-level             (power_border_twfe.csv)
#   Sim D:  all counties, county-level                (power_all_county_twfe.csv)
#
# Reading the table:
#   B vs A:  pure sample-selection effect (restricts to border counties)
#   C vs B:  pure disaggregation effect on the border sample
#   D vs A:  pure disaggregation effect on the full sample
#   C vs A:  combined sample-selection + disaggregation (what we showed first)
#
# Outputs:
#   output/border_diagnostic/power_comparison_4way.csv
#   output/border_diagnostic/power_comparison_4way.png
#   output/border_diagnostic/mechanism_decomposition.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
})

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")

read_one <- function(fname) {
  p <- file.path(out_dir, fname)
  if (!file.exists(p)) {
    warning("Missing: ", fname); return(NULL)
  }
  read_csv(p, show_col_types = FALSE)
}

A <- read_one("power_state_twfe.csv")
B <- read_one("power_border_state_agg_twfe.csv")
C <- read_one("power_border_twfe.csv")
D <- read_one("power_all_county_twfe.csv")

all4 <- bind_rows(A, B, C, D)
write_csv(all4, file.path(out_dir, "power_comparison_4way_long.csv"))

# Wide table: one row per effect, one col per panel × stat.
wide <- all4 %>%
  select(panel_label, effect_pct, rejection_rate, sd_att, mean_se,
         se_over_sdatt) %>%
  pivot_wider(names_from = panel_label,
              values_from = c(rejection_rate, sd_att, mean_se, se_over_sdatt))
write_csv(wide, file.path(out_dir, "power_comparison_4way.csv"))

# Mechanism decomposition: focus on Type I and on MDE.
mech <- all4 %>%
  group_by(panel_label) %>%
  arrange(effect_pct) %>%
  summarise(
    type1            = rejection_rate[abs(effect_pct) < 1e-12][1],
    sd_att_null      = sd_att[abs(effect_pct) < 1e-12][1],
    mean_se_null     = mean_se[abs(effect_pct) < 1e-12][1],
    se_over_sd_null  = se_over_sdatt[abs(effect_pct) < 1e-12][1],
    rej_at_002       = rejection_rate[abs(effect_pct - 0.02) < 1e-6][1],
    rej_at_005       = rejection_rate[abs(effect_pct - 0.05) < 1e-6][1],
    rej_at_010       = rejection_rate[abs(effect_pct - 0.10) < 1e-6][1],
    mde_80 = {
      ge <- which(rejection_rate >= 0.80)
      if (length(ge) == 0) NA_real_ else effect_pct[min(ge)]
    },
    .groups = "drop"
  )
write_csv(mech, file.path(out_dir, "mechanism_decomposition.csv"))

cat("\n=== ALL FOUR POWER SIMULATIONS ===\n")
print(mech)

# Effect-size ratios (relative to state baseline A).
baseline_sd <- mech %>% filter(panel_label == "state_twfe_baseline") %>%
  pull(sd_att_null)
if (length(baseline_sd) == 1 && is.finite(baseline_sd)) {
  ratios <- mech %>%
    mutate(sd_ratio_vs_state = sd_att_null / baseline_sd)
  cat("\n=== SD shrinkage relative to state baseline (Sim A) ===\n")
  print(ratios %>% select(panel_label, sd_att_null, sd_ratio_vs_state, mde_80))
  write_csv(ratios, file.path(out_dir, "sd_shrinkage_vs_baseline.csv"))
}

# ----------------------------- plot -------------------------------------------
label_map <- c(
  state_twfe_baseline   = "A: all counties → state",
  border_state_agg_twfe = "B: border counties → state",
  border_county_twfe    = "C: border counties (county)",
  all_county_twfe       = "D: all counties (county)"
)

plot_df <- all4 %>%
  mutate(panel_label_nice = factor(label_map[panel_label],
                                   levels = unname(label_map)))

p <- ggplot(plot_df, aes(x = effect_pct, y = rejection_rate,
                          color = panel_label_nice,
                          shape = panel_label_nice,
                          linetype = panel_label_nice)) +
  geom_hline(yintercept = 0.80, linetype = "dotted", color = "grey50") +
  geom_hline(yintercept = 0.05, linetype = "dotted", color = "grey70") +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.4) +
  scale_x_continuous(breaks = unique(plot_df$effect_pct),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
  scale_color_grey(start = 0.15, end = 0.7, name = NULL) +
  scale_shape_manual(values = c(16, 15, 17, 18), name = NULL) +
  scale_linetype_manual(values = c("solid", "longdash", "dashed", "dotted"),
                        name = NULL) +
  labs(x = "True treatment effect (log-points)",
       y = "Rejection rate (n=200 sims, alpha=0.05)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(
    legend.position = "bottom",
    legend.text = element_text(size = rel(0.85)),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA)
  ) +
  guides(color = guide_legend(nrow = 2),
         shape = guide_legend(nrow = 2),
         linetype = guide_legend(nrow = 2))

ggsave(file.path(out_dir, "power_comparison_4way.png"), p,
       width = 7.0, height = 4.5, dpi = 300, bg = "transparent")

cat("\nWrote outputs to:", out_dir, "\n")
