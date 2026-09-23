# Combined monthly eviction filings, 2020-2023, on a fixed composition.
#
# Composition rule: a state enters only if it has all 48 months 2020-01..2023-12
# in the state-month panel AND its county basket (n_counties) is constant over
# that window. The state panel already holds one fixed county basket per state,
# so the summed series has the same states and counties in every month.
#
# Run from project root:
#   Rscript analysis/visualization/plot_combined_filings_2020_2023.R

library(tidyverse)
library(lubridate)

theme_set(theme_minimal(base_size = 12))

win_start <- as.Date("2020-01-01")
win_end   <- as.Date("2023-12-01")
n_months  <- 48

panel <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types = FALSE) |>
  mutate(month_date = as.Date(month_date)) |>
  filter(month_date >= win_start, month_date <= win_end)

composition <- panel |>
  group_by(state_abb) |>
  summarise(months = n_distinct(month_date),
            any_na = any(is.na(filings_count)),
            basket_constant = n_distinct(n_counties) == 1,
            n_counties = first(n_counties),
            basket_share = first(basket_share),
            panel_source = first(panel_source),
            .groups = "drop") |>
  mutate(kept = months == n_months & !any_na & basket_constant)

keep <- composition |> filter(kept) |> pull(state_abb)

combined <- panel |>
  filter(state_abb %in% keep) |>
  group_by(month_date) |>
  summarise(filings = sum(filings_count), n_states = n_distinct(state_abb),
            .groups = "drop")

stopifnot(nrow(combined) == n_months, all(combined$n_states == length(keep)))

# Looser set: constant basket, at most max_gap missing months; gaps filled by
# linear interpolation within the state's own series (edge gaps take the
# nearest observed month, since there is nothing to interpolate toward).
max_gap <- 3
composition <- composition |>
  mutate(kept_loose = months >= n_months - max_gap & !any_na & basket_constant)
keep_loose <- composition |> filter(kept_loose) |> pull(state_abb)

month_grid <- seq(win_start, win_end, by = "month")
loose_filled <- panel |>
  filter(state_abb %in% keep_loose) |>
  select(state_abb, month_date, filings_count) |>
  complete(state_abb, month_date = month_grid) |>
  group_by(state_abb) |>
  mutate(interpolated = is.na(filings_count),
         filings_count = approx(as.numeric(month_date[!interpolated]),
                                filings_count[!interpolated],
                                xout = as.numeric(month_date), rule = 2)$y) |>
  ungroup()

combined_loose <- loose_filled |>
  group_by(month_date) |>
  summarise(filings = sum(filings_count), n_states = n_distinct(state_abb),
            n_interpolated = sum(interpolated), .groups = "drop")

stopifnot(nrow(combined_loose) == n_months,
          all(combined_loose$n_states == length(keep_loose)))

both <- bind_rows(
  combined |> mutate(series = sprintf("Strict: %d states, all 48 months", length(keep))),
  combined_loose |> mutate(series = sprintf("Loose: %d states, <=%d months interpolated",
                                            length(keep_loose), max_gap)))

dir.create("output/combined_filings_2020_2023", showWarnings = FALSE, recursive = TRUE)
write_csv(composition, "output/combined_filings_2020_2023/composition.csv")
write_csv(combined, "output/combined_filings_2020_2023/combined_monthly_filings.csv")

write_csv(combined_loose, "output/combined_filings_2020_2023/combined_monthly_filings_loose.csv")
write_csv(loose_filled |> filter(interpolated) |> select(state_abb, month_date),
          "output/combined_filings_2020_2023/interpolated_state_months.csv")

p <- ggplot(both, aes(month_date, filings, linetype = series, shape = series)) +
  annotate("rect", xmin = as.Date("2020-03-01"), xmax = as.Date("2021-07-01"),
           ymin = -Inf, ymax = Inf, alpha = 0.12) +
  annotate("text", x = as.Date("2020-11-01"), y = max(both$filings),
           label = "COVID drop window\n(2020-03 to 2021-07)", size = 3.2, vjust = 1) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1) +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  scale_y_continuous(labels = scales::comma, limits = c(0, NA)) +
  labs(x = NULL, y = "Monthly eviction filings (combined)", linetype = NULL, shape = NULL,
       caption = sprintf("Strict: %s\nLoose adds: %s",
                         paste(sort(keep), collapse = " "),
                         paste(sort(setdiff(keep_loose, keep)), collapse = " "))) +
  theme(legend.position = "bottom",
        plot.caption = element_text(hjust = 0, size = 8),
        axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("figures/combined_filings_2020_2023.png", p, width = 9, height = 5.5, dpi = 200)
ggsave("figures/combined_filings_2020_2023.pdf", p, width = 9, height = 5.5)

cat("Kept", length(keep), "states:", paste(sort(keep), collapse = " "), "\n")
cat("Loose adds", length(setdiff(keep_loose, keep)), "states:",
    paste(sort(setdiff(keep_loose, keep)), collapse = " "), "\n")
cat("Interpolated state-months:\n")
print(loose_filled |> filter(interpolated) |> group_by(state_abb) |>
        summarise(months = paste(format(month_date, "%Y-%m"), collapse = " ")), n = Inf)
print(combined_loose |> mutate(year = year(month_date)) |> group_by(year) |>
        summarise(mean_monthly = round(mean(filings)), min = round(min(filings)),
                  max = round(max(filings))))
cat("Dropped:\n")
print(composition |> filter(!kept) |> select(state_abb, months, any_na, basket_constant),
      n = Inf)
print(combined |> mutate(year = year(month_date)) |> group_by(year) |>
        summarise(mean_monthly = round(mean(filings)), min = min(filings), max = max(filings)))
