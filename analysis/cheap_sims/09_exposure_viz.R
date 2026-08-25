#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/09_exposure_viz.R
#
# Exhibit: share of each state's online-era betting handle that occurred after
# evictions returned to pre-pandemic baseline (Sep 2021). 100%-stacked bar per
# state, grouped by legalization era; post-recovery share carries the emphasis
# hue, pre-recovery the neutral. Reads the CSV written by the exposure
# classification (see county_covidclean/exposure_post_recovery_by_state.csv).
#
# Run from repo root:  Rscript analysis/cheap_sims/09_exposure_viz.R
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
theme_set(theme_minimal(base_family = "serif"))

tab <- read_csv("output/cheap_power_sim/county_covidclean/exposure_post_recovery_by_state.csv",
                show_col_types = FALSE) %>%
  filter(!is.na(pct_post_recovery)) %>%      # WV/FL/MO: no LSR handle (footnote)
  mutate(
    class = factor(class,
                   levels = c("pre-COVID", "during COVID", "post-recovery"),
                   labels = c("Legalized pre-COVID\n(Aug 2018 - Feb 2020)",
                              "Legalized during COVID\n(Mar 2020 - Sep 2021)",
                              "Legalized after evictions\nrecovered (Oct 2021 - )")),
    lab = sprintf("%s  (%s)", state_abb, format(g, "%b %Y")),
    lab = fct_reorder(lab, desc(as.numeric(g))),
    handle_lab = ifelse(total_handle_bn >= 10,
                        sprintf("$%.0fB", total_handle_bn),
                        sprintf("$%.1fB", total_handle_bn)),
    # topmost plotted row's figure self-describes the column (lab levels run
    # bottom-to-top, so the top row is the last factor level)
    handle_lab = ifelse(as.integer(lab) == nlevels(lab),
                        paste0(handle_lab, " handle"), handle_lab)
  )

long <- tab %>%
  transmute(lab, class, pct_post_recovery, handle_lab,
            `After recovery`  = pct_post_recovery,
            `Before recovery` = 100 - pct_post_recovery) %>%
  pivot_longer(c(`After recovery`, `Before recovery`),
               names_to = "period", values_to = "pct") %>%
  mutate(period = factor(period, levels = c("Before recovery", "After recovery")))

col_post <- "#2563EB"   # emphasis: exposure in the clean regime
col_pre  <- "#C9CDD4"   # neutral: exposure before evictions renormalized

p <- ggplot(long, aes(x = pct, y = lab, fill = period)) +
  geom_col(width = 0.72, color = "white", linewidth = 0.6) +
  # direct % labels centered in the blue segment, pre/during groups only
  # (the post-recovery group is a wall of 100s; the pattern speaks)
  geom_text(data = tab %>% filter(pct_post_recovery < 99.95),
            aes(x = pct_post_recovery / 2, y = lab,
                label = sprintf("%.0f%%", pct_post_recovery)),
            inherit.aes = FALSE, size = 3.0,
            family = "serif", color = "white") +
  # total handle as a text column at the right margin
  geom_text(data = tab, aes(x = 128, y = lab, label = handle_lab),
            inherit.aes = FALSE, hjust = 1, size = 2.9,
            family = "serif", color = "grey40") +
  facet_grid(class ~ ., scales = "free_y", space = "free_y") +
  scale_fill_manual(values = c(`Before recovery` = col_pre,
                               `After recovery` = col_post),
                    breaks = c("After recovery", "Before recovery"),
                    labels = c("Handle wagered after evictions recovered (Sep 2021)",
                               "Handle wagered before recovery")) +
  scale_x_continuous(limits = c(0, 129), breaks = seq(0, 100, 25),
                     labels = function(x) paste0(x, "%"), expand = c(0, 0)) +
  labs(x = "Share of state's cumulative online-era betting handle", y = NULL,
       fill = NULL) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text.y = element_text(face = "bold", size = 9, angle = 0, hjust = 0),
    axis.text.y = element_text(size = 8.6, color = "grey15"),
    axis.text.x = element_text(size = 8, color = "grey35"),
    axis.title.x = element_text(size = 9, color = "grey25",
                                margin = margin(t = 6)),
    legend.text = element_text(size = 8.6),
    plot.margin = margin(8, 10, 6, 6)
  )

out <- "output/cheap_power_sim/county_covidclean"
ggsave(file.path(out, "exposure_post_recovery.pdf"), p,
       width = 7.5, height = 7.2, bg = "white")
ggsave(file.path(out, "exposure_post_recovery.png"), p,
       width = 7.5, height = 7.2, dpi = 300, bg = "white")
cat("written:", file.path(out, "exposure_post_recovery.{pdf,png}"), "\n")
