#!/usr/bin/env Rscript
################################################################################
# long_diff_forest_clean.R
#
# Cleaner version of the long-difference exposure-gradient plot.
# - Subtracts the never-treated 2018/19 -> 2024 change from each treated state
#   (so each dot is a real DiD, not a level change).
# - Sorts states by ATT (not by cohort timing).
# - Drops the meaningless OLS trend line.
# - Color-codes states whose 95% CI excludes zero.
# - Plain-English axis in percent change, not log points.
#
# Outputs:
#   output/border_diagnostic/long_difference/long_diff_state_forest.csv
#   output/border_diagnostic/long_difference/long_diff_state_forest.png
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(ggplot2)
})

set.seed(20260522L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_difference")

county <- read_csv(file.path(out_dir, "long_diff_county.csv"),
                   show_col_types = FALSE)

# Drop NH (data quality) and ME, matching the headline spec.
county <- county %>% filter(!state_abb %in% c("NH", "ME"))

# Never-treated benchmark: pooled mean and county-level SE.
nt <- county %>% filter(!ever_treated)
mean_nt <- mean(nt$dy, na.rm = TRUE)
se_nt   <- sd(nt$dy, na.rm = TRUE) / sqrt(sum(!is.na(nt$dy)))

# Per-state ATT relative to the never-treated benchmark.
state_att <- county %>%
  filter(ever_treated) %>%
  group_by(state_abb) %>%
  summarise(
    n_counties = n(),
    mean_dy_s  = mean(dy, na.rm = TRUE),
    se_dy_s    = sd(dy, na.rm = TRUE) / sqrt(sum(!is.na(dy))),
    .groups = "drop"
  ) %>%
  mutate(
    att     = mean_dy_s - mean_nt,
    se      = sqrt(se_dy_s^2 + se_nt^2),
    ci_low  = att - 1.96 * se,
    ci_high = att + 1.96 * se,
    # Convert log-points to percent change, including CI endpoints.
    pct      = (exp(att) - 1) * 100,
    pct_low  = (exp(ci_low) - 1) * 100,
    pct_high = (exp(ci_high) - 1) * 100,
    sig      = ci_low > 0 | ci_high < 0
  ) %>%
  arrange(att)

write_csv(state_att, file.path(out_dir, "long_diff_state_forest.csv"))

# Order state factor by ATT for the forest layout.
state_att <- state_att %>%
  mutate(state_abb = factor(state_abb, levels = state_abb))

x_range <- range(c(state_att$pct_low, state_att$pct_high), na.rm = TRUE)
x_pad   <- 0.05 * diff(x_range)
x_lims  <- c(x_range[1] - x_pad, x_range[2] + x_pad)

p <- ggplot(state_att,
            aes(x = pct, y = state_abb, color = sig)) +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "grey60", linewidth = 0.4) +
  geom_errorbarh(aes(xmin = pct_low, xmax = pct_high),
                 height = 0, linewidth = 0.6) +
  geom_point(size = 3.2) +
  scale_color_manual(values = c(`TRUE` = "#b91c1c", `FALSE` = "grey35"),
                     guide = "none") +
  scale_x_continuous(limits = x_lims,
                     breaks = scales::pretty_breaks(n = 6),
                     labels = function(z) paste0(round(z), "%")) +
  labs(x = "Change in eviction filings vs. states that never legalized",
       y = NULL) +
  theme_minimal(base_size = 12, base_family = "serif") +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
    axis.text.y        = element_text(size = rel(1.05)),
    axis.ticks.y       = element_blank(),
    axis.ticks.x       = element_line(color = "grey40", linewidth = 0.3),
    axis.line.x        = element_line(color = "grey40", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    plot.margin        = margin(t = 8, r = 12, b = 5, l = 5, unit = "pt")
  )

ggsave(file.path(out_dir, "long_diff_state_forest.png"), p,
       width = 6.5, height = 4.5, dpi = 300, bg = "transparent")

cat("Never-treated benchmark dy: ", round(mean_nt, 4),
    " (SE ", round(se_nt, 4), ")\n", sep = "")
cat("Wrote: long_diff_state_forest.{csv,png}\n")
print(state_att %>% select(state_abb, n_counties, att, ci_low, ci_high,
                           pct, sig))
