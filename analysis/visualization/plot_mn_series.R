################################################################################
# plot_mn_series.R
#
# The Minnesota series, because MN turned out to drive the Jan-Jun 2022
# differential trend.
#
# Panel A: MN filings per 1k renters, full panel span, with the COVID-era gap
#          and the diagnostic windows marked.
# Panel B: MN's LSC percent-of-historical-average (the plausibility column) --
#          this is what shows the post-moratorium ramp for what it is.
# Panel C: MN against the other never-legalizer controls and the later-adopter
#          arm, indexed to 2021-08 = 0 in logs.
#
# MN has a 16-month interior gap (2020-04..2021-07) and re-enters at 27% of its
# own historical average, reaching 147% by 2022-06.
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(patchwork)})
theme_set(theme_minimal(base_size = 11))
source("utils/eviction_treatment_schedule.R")

SCH <- "data/raw/sports_gambling_legalization_dates.csv"
OUT <- "output/prewindow_trends_2021h2"

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))
sched <- load_eviction_treatment_schedule(SCH, "online_start_date",
                                          states = EVICTION_STATE_UNIVERSE)
ps <- sort(unique(pan$state_abb))
CT_CONTROL <- suppressWarnings(
  eviction_control_states(ps, SCH, "online_start_date", censor_end = as.Date("2026-06-01")))
CT_TREATED <- sched %>% filter(state_abb %in% ps, !is.na(treat_start),
                               treat_start > as.Date("2022-06-01")) %>%
  pull(state_abb) %>% sort()

mn <- pan %>% filter(state_abb == "MN") %>% arrange(month_date)
win <- tibble(xmin = as.Date(c("2021-07-01", "2022-01-01")),
              xmax = as.Date(c("2022-06-01", "2022-06-01")),
              lab  = c("2021-07..2022-06", "2022-01..2022-06"))
gap <- tibble(xmin = as.Date("2020-04-01"), xmax = as.Date("2021-07-01"))

pA <- ggplot(mn, aes(month_date, filings_per_1k_renters)) +
  geom_rect(data = gap, inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "grey85", alpha = 0.7) +
  annotate("text", x = as.Date("2020-11-01"), y = Inf, vjust = 1.4,
           label = "16-month gap\n(no MN rows)", size = 2.9, colour = "grey30") +
  geom_rect(data = win[1, ], inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "#2166AC", alpha = 0.12) +
  geom_line(linewidth = 0.5) + geom_point(size = 0.7) +
  labs(x = NULL, y = "Filings per 1k renters",
       title = "A. Minnesota, full panel span",
       subtitle = "Grey = interior gap; blue = the 2021-07..2022-06 diagnostic window. 22 counties, basket share 1.00.")

pB <- ggplot(filter(mn, !is.na(lsc_pct_of_hist_avg)),
             aes(month_date, lsc_pct_of_hist_avg)) +
  geom_rect(data = gap, inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "grey85", alpha = 0.7) +
  geom_rect(data = win[1, ], inherit.aes = FALSE,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "#2166AC", alpha = 0.12) +
  geom_hline(yintercept = 100, linetype = 2, linewidth = 0.3, colour = "grey40") +
  geom_line(linewidth = 0.5) + geom_point(size = 0.7) +
  labs(x = NULL, y = "% of historical average",
       title = "B. MN percent-of-historical-average (LSC plausibility column)",
       subtitle = "Re-enters at 27% of normal in 2021-08 and passes 100% by 2022-04 - a post-moratorium ramp, not a level.")

# Panel C: indexed comparison, base 2021-08
base_m <- as.Date("2021-08-01")
cmp <- pan %>%
  filter(month_date >= base_m, month_date <= as.Date("2022-06-01"),
         !is.na(filings_per_1k_renters),
         state_abb %in% c(CT_TREATED, CT_CONTROL)) %>%
  mutate(arm = case_when(state_abb == "MN" ~ "Minnesota",
                         state_abb %in% CT_TREATED ~ "later adopters (mean)",
                         TRUE ~ "other never-legalizers (mean)")) %>%
  group_by(state_abb) %>%
  mutate(idx = log1p(filings_per_1k_renters) -
           log1p(filings_per_1k_renters[month_date == base_m])) %>%
  ungroup() %>%
  group_by(arm, month_date) %>% summarise(idx = mean(idx), .groups = "drop")

pC <- ggplot(cmp, aes(month_date, idx, colour = arm)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_line(linewidth = 0.7) + geom_point(size = 1.4) +
  scale_colour_manual(values = c("Minnesota" = "#B2182B",
                                 "other never-legalizers (mean)" = "#2166AC",
                                 "later adopters (mean)" = "#66A61E")) +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "2 months") +
  labs(x = NULL, y = "Log change since Aug 2021", colour = NULL,
       title = "C. MN against the two arms, indexed to Aug 2021",
       subtitle = "MN is a control state climbing far faster than any other control - which pushes treated-minus-control down.")

p <- pA / pB / pC + plot_layout(heights = c(1, 1, 1.15))
ggsave(file.path(OUT, "mn_series.png"), p, width = 10, height = 11, dpi = 200)
cat("Wrote ", file.path(OUT, "mn_series.png"), "\n\n")

cat("MN log change Aug 2021 -> Jun 2022: ",
    round(with(mn, log1p(filings_per_1k_renters[month_date == as.Date("2022-06-01")]) -
                   log1p(filings_per_1k_renters[month_date == base_m])), 3), "\n")
print(as.data.frame(cmp %>% filter(month_date == as.Date("2022-06-01")) %>%
        mutate(idx = round(idx, 3))))
