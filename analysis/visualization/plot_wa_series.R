#!/usr/bin/env Rscript
# WA (Tacoma / Pierce County, never-treated control) monthly filings, with the
# median of the other never-launched control states for context. Control
# states only, so nothing here touches treated outcomes.
# Run from the project root: Rscript --vanilla analysis/visualization/plot_wa_series.R
suppressMessages({ library(tidyverse); library(patchwork) })
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_size = 12))

p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb, month_date = as.Date(month_date), filings_count) %>%
  filter(!is.na(filings_count))
sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  mutate(ab = c(state.abb, "DC")[match(state, c(state.name, "District of Columbia"))])
launched <- sched$ab[!is.na(sched$online_start_date)]
ctrl <- setdiff(unique(p$state_abb), c(launched, PRE_PASPA_SPORTS_BETTING, "HI", "MS"))

wa <- p %>% filter(state_abb == "WA")
shade <- annotate("rect", xmin = as.Date("2020-03-01"), xmax = as.Date("2022-05-31"),
                  ymin = -Inf, ymax = Inf, alpha = 0.12)

g1 <- ggplot(wa, aes(month_date, filings_count)) + shade +
  geom_line(linewidth = 0.7) + geom_point(size = 0.8) +
  scale_y_continuous(labels = scales::comma, limits = c(0, NA)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(x = NULL, y = "WA monthly filings (Pierce County)", tag = "(a)")

idx <- p %>% filter(state_abb %in% ctrl, month_date >= as.Date("2022-06-01")) %>%
  group_by(state_abb) %>%
  mutate(base = mean(filings_count[month_date <= as.Date("2022-11-01")])) %>%
  ungroup() %>% filter(is.finite(base), base > 0) %>%
  mutate(index = 100 * filings_count / base)
others <- idx %>% filter(state_abb != "WA") %>% group_by(month_date) %>%
  summarise(index = median(index), .groups = "drop") %>% mutate(series = "Median of other never-launched controls")
g2 <- bind_rows(idx %>% filter(state_abb == "WA") %>% transmute(month_date, index, series = "WA"), others) %>%
  ggplot(aes(month_date, index, linetype = series)) +
  geom_hline(yintercept = 100, colour = "grey70") + geom_line(linewidth = 0.7) +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  labs(x = NULL, y = "Index (Jun-Nov 2022 = 100)", linetype = NULL, tag = "(b)") +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("figures/wa_series.png", g1 / g2, width = 8, height = 8, dpi = 200, bg = "white")
ggsave("figures/wa_series.pdf", g1 / g2, width = 8, height = 8)
cat("controls used for the median:", paste(sort(setdiff(unique(idx$state_abb), "WA")), collapse = " "), "\n")
