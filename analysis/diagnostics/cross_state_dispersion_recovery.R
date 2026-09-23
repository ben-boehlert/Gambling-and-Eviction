# When does DIFFERENTIAL post-COVID recovery end?
#
# A flat combined series is not what DiD needs: a recovery common to all states
# is absorbed by time effects. What hurts is states recovering at different
# speeds. Two outcome-only measures, by month, across a fixed set of states
# (no treatment information is used anywhere):
#   (1) growth dispersion -- cross-state SD of the 6-month change in log filings
#       (6 = the headline LP-DiD base-period width). Needs no reference year, so
#       it is the primary measure; benchmark = its own 2017-2019 range.
#   (2) level dispersion  -- cross-state SD of log filings relative to each
#       state's own 2023 mean. Mechanically smallest in 2023, so read its path
#       INTO 2023, not its 2023 level.
# Each is reported as SD and as a robust SD (1.4826 * MAD).
#
# Run from project root:
#   Rscript analysis/diagnostics/cross_state_dispersion_recovery.R

library(tidyverse)
library(lubridate)

theme_set(theme_minimal(base_size = 12))

growth_lag   <- 6
win_start    <- as.Date("2017-01-01")
win_end      <- as.Date("2024-12-01")
bench_years  <- 2017:2019
max_missing  <- 3

panel <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types = FALSE) |>
  mutate(month_date = as.Date(month_date)) |>
  filter(month_date >= win_start, month_date <= win_end, filings_count > 0)

# Fixed state set: constant basket, near-complete over 2019-2024 outside the
# spring-2020 shutdown, and all 12 months of the 2023 reference year.
core_months <- seq(as.Date("2019-01-01"), win_end, by = "month")
core_months <- core_months[!(core_months >= as.Date("2020-03-01") &
                             core_months <= as.Date("2020-08-01"))]
state_set <- panel |>
  group_by(state_abb) |>
  summarise(core_missing = length(core_months) - sum(month_date %in% core_months),
            months_2023 = sum(year(month_date) == 2023),
            basket_constant = n_distinct(n_counties[month_date %in% core_months]) == 1,
            .groups = "drop") |>
  mutate(kept = core_missing <= max_missing & months_2023 == 12 & basket_constant)
keep <- state_set |> filter(kept) |> pull(state_abb)

dev <- panel |>
  filter(state_abb %in% keep) |>
  select(state_abb, month_date, filings_count) |>
  complete(state_abb, month_date = seq(win_start, win_end, by = "month")) |>
  group_by(state_abb) |>
  arrange(month_date, .by_group = TRUE) |>
  mutate(log_f = log(filings_count),
         level_dev = log_f - log(mean(filings_count[year(month_date) == 2023])),
         growth = log_f - lag(log_f, growth_lag)) |>
  ungroup()

robust_sd <- function(x) 1.4826 * mad(x, na.rm = TRUE)

dispersion <- dev |>
  group_by(month_date) |>
  summarise(n_level = sum(!is.na(level_dev)), n_growth = sum(!is.na(growth)),
            level_sd = sd(level_dev, na.rm = TRUE), level_rsd = robust_sd(level_dev),
            growth_sd = sd(growth, na.rm = TRUE), growth_rsd = robust_sd(growth),
            .groups = "drop")

bench <- dispersion |>
  filter(year(month_date) %in% bench_years, !is.na(growth_sd)) |>
  summarise(across(c(growth_sd, growth_rsd),
                   list(mean = mean, p90 = \(x) quantile(x, 0.9), max = max)))

# First month from which the measure stays at or below its pre-COVID 90th
# percentile for 6 consecutive months.
settle_month <- function(x, dates, cap, run = 6, from = as.Date("2020-09-01")) {
  ok <- !is.na(x) & x <= cap & dates >= from
  r <- stats::filter(as.numeric(ok), rep(1, run), sides = 1)
  i <- which(r == run)[1]
  if (is.na(i)) as.Date(NA) else dates[i - run + 1]
}
settle <- tibble(
  measure = c("growth_sd", "growth_rsd"),
  pre_covid_p90 = c(bench$growth_sd_p90, bench$growth_rsd_p90),
  settles = c(settle_month(dispersion$growth_sd, dispersion$month_date, bench$growth_sd_p90),
              settle_month(dispersion$growth_rsd, dispersion$month_date, bench$growth_rsd_p90)))

out_dir <- "output/cross_state_dispersion"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write_csv(dispersion, file.path(out_dir, "dispersion_by_month.csv"))
write_csv(state_set, file.path(out_dir, "state_set.csv"))
write_csv(settle, file.path(out_dir, "settle_months.csv"))

plot_df <- dispersion |>
  select(month_date, level_sd, level_rsd, growth_sd, growth_rsd) |>
  pivot_longer(-month_date) |>
  mutate(measure = if_else(str_starts(name, "growth"),
                           sprintf("(a) %d-month change in log filings", growth_lag),
                           "(b) log filings relative to own 2023 mean"),
         stat = if_else(str_ends(name, "rsd"), "Robust SD (MAD)", "SD"))

bench_lines <- tibble(
  measure = sprintf("(a) %d-month change in log filings", growth_lag),
  stat = c("SD", "Robust SD (MAD)"),
  y = c(bench$growth_sd_p90, bench$growth_rsd_p90))

p <- ggplot(plot_df, aes(month_date, value, linetype = stat)) +
  annotate("rect", xmin = as.Date("2020-03-01"), xmax = as.Date("2021-07-01"),
           ymin = -Inf, ymax = Inf, alpha = 0.12) +
  geom_vline(xintercept = as.Date("2022-03-01"), colour = "grey40", linewidth = 0.3) +
  geom_hline(data = bench_lines, aes(yintercept = y, linetype = stat),
             colour = "grey50", linewidth = 0.3) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~measure, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  labs(x = NULL, y = "Cross-state dispersion", linetype = NULL,
       caption = sprintf(paste0("%d states: %s\nShaded = COVID drop window; vertical line = 2022-03; ",
                                "horizontal lines in (a) = 2017-2019 90th percentile."),
                         length(keep), paste(sort(keep), collapse = " "))) +
  theme(legend.position = "bottom",
        plot.caption = element_text(hjust = 0, size = 8),
        axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("figures/cross_state_dispersion_recovery.png", p, width = 9, height = 7.5, dpi = 200)
ggsave("figures/cross_state_dispersion_recovery.pdf", p, width = 9, height = 7.5)

cat(length(keep), "states:", paste(sort(keep), collapse = " "), "\n\nPre-COVID benchmark (2017-2019):\n")
print(bench)
cat("\nSettle months (<= pre-COVID p90 for 6 straight months):\n")
print(settle)
cat("\nHalf-year means:\n")
print(dispersion |>
        filter(month_date >= as.Date("2019-01-01")) |>
        mutate(half = sprintf("%d-H%d", year(month_date), if_else(month(month_date) <= 6, 1, 2))) |>
        group_by(half) |>
        summarise(across(c(growth_sd, growth_rsd, level_sd, level_rsd), \(x) round(mean(x, na.rm = TRUE), 3)),
                  n_states = round(mean(n_growth), 1)), n = Inf)
