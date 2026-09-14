# =============================================================================
# plot_state_series_check.R  (2026-09-14)
#
# Series check for states whose COVID baseline->outcome drift looked implausibly
# large in straddle_pooled_contamination.R (VA -0.447, CT +0.419, AZ +0.275).
# Eviction filings are normally smooth, so a ~50% swing is either real
# moratorium suppression or a reporting artifact -- this separates them.
#
# Shows: raw filings, the COVID drop window, online launch, the 6-month
# pre-launch baseline, the 12-24 month outcome window, and months that fall
# below 25% of the state's own median (flagged).
#
# Output: figures/state_series_check.{png,pdf}
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
theme_set(theme_minimal(base_size = 11))
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
STATES <- c("VT","CT","VA")
LAUNCH <- c(VT = as.Date("2024-01-01"), CT = as.Date("2021-10-01"), VA = as.Date("2021-01-01"))

d <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>% filter(state_abb %in% STATES) %>%
  group_by(state_abb) %>% mutate(med = median(filings_count),
                                 low = filings_count < 0.25 * med) %>% ungroup() %>%
  mutate(state_abb = factor(state_abb, levels = STATES))

win <- tibble(state_abb = factor(STATES, levels = STATES), L = LAUNCH[STATES]) %>%
  mutate(b_lo = L %m-% months(6), b_hi = L %m-% months(1),
         o_lo = L %m+% months(12), o_hi = L %m+% months(24))

p <- ggplot(d, aes(month_date, filings_count)) +
  geom_rect(data = win, inherit.aes = FALSE,
            aes(xmin = b_lo, xmax = b_hi, ymin = -Inf, ymax = Inf),
            fill = "#2C7FB8", alpha = 0.18) +
  geom_rect(data = win, inherit.aes = FALSE,
            aes(xmin = o_lo, xmax = o_hi, ymin = -Inf, ymax = Inf),
            fill = "#D94801", alpha = 0.15) +
  annotate("rect", xmin = CS, xmax = CE, ymin = -Inf, ymax = Inf,
           fill = "grey35", alpha = 0.20) +
  geom_line(colour = "grey35", linewidth = 0.45) +
  geom_point(aes(colour = low), size = 1.1) +
  geom_vline(data = win, aes(xintercept = L), linetype = "22",
             colour = "grey10", linewidth = 0.45) +
  scale_colour_manual(values = c(`FALSE` = "grey30", `TRUE` = "#B2182B"),
                      labels = c("normal", "< 25% of state median"), name = NULL) +
  scale_y_continuous(labels = scales::comma) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  facet_wrap(~ state_abb, ncol = 1, scales = "free_y") +
  labs(x = NULL, y = "Eviction filings per month") +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", hjust = 0))

ggsave("figures/state_series_check.png", p, width = 9.5, height = 7.4, dpi = 220, bg = "white")
ggsave("figures/state_series_check.pdf", p, width = 9.5, height = 7.4, bg = "white")

cat("grey band = COVID drop | blue = 6-mo pre-launch baseline | orange = 12-24 mo outcome window\n")
cat("dashed line = online launch\n\n")
d %>% group_by(state_abb) %>%
  summarise(median = median(filings_count), min = min(filings_count), max = max(filings_count),
            n_low = sum(low), .groups = "drop") %>% as.data.frame() %>% print(row.names = FALSE)
