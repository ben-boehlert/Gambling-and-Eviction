# =============================================================================
# idaho_ada_canyon_decomposition.R   (2026-09-21)
#
# QUESTION. The statewide Idaho A12 series grows ~10%/yr over 2021-2026. The
# 2026-09-17 verification attributed 58% of that growth to Ada County (Boise)
# and called it a ramp, not a step. A competing-policy story has since been
# raised: a documented Ada County program, with markers at 2022-12, 2023-04,
# 2023-06/07 and 2023-11 (expiry). If that story is right, the statewide drift
# should be OVERWHELMINGLY Ada (and Canyon), and Ada's growth should become
# especially pronounced after the 2023-11 marker -- while the other 42 counties
# stay comparatively flat.
#
# This script tests that, outcome-only. NO treatment information is used: Idaho
# has no row in sports_gambling_legalization_dates.csv (never-legalizer) and is
# control-pool only. Blind-safe.
#
# DATA. data/raw/idaho/id_county_month_a12.csv -- 44 counties x 66 months,
# 2021-01..2026-06. Verified against the LIVE panel vintage (boundary 11,
# data/raw/state_month_panel_with_treatment.csv, 4,429 rows): Idaho's 66 panel
# rows equal the county sums bit-for-bit, so this decomposition is of exactly
# the series the estimators see. The script re-asserts that at run time.
#
# THE EVENT DATES ARE USER-SUPPLIED and are NOT documented anywhere in this
# repo. They are drawn on the figures and used to cut the segment table, but
# nothing downstream depends on them. Fill in `label` below once the program
# and its dates are sourced; until then they are markers, not findings.
#
# SEASONALITY. Levels are seasonal, so every growth statistic here is either a
# 12-month log change (YoY, which differences out month-of-year) or a
# log-linear trend with month-of-year fixed effects. The figures carry a
# 12-month centred rolling mean over the raw monthly points.
#
# Run from project root:
#   Rscript analysis/diagnostics/idaho_ada_canyon_decomposition.R
#
# Outputs: output/idaho_ada_canyon/*.csv
#          figures/idaho_ada_canyon_{levels,indexed}.{png,pdf}
# =============================================================================

library(tidyverse)
library(lubridate)

theme_set(theme_minimal(base_size = 11))

CTY_FILE  <- "data/raw/idaho/id_county_month_a12.csv"
PANEL     <- "data/raw/state_month_panel_with_treatment.csv"
OUT_DIR   <- "output/idaho_ada_canyon"
FIG_DIR   <- "figures"
BIG       <- c("Ada", "Canyon")

# User-supplied policy markers (see header -- provenance not in repo).
events <- tibble(
  date  = as.Date(c("2022-12-01", "2023-04-01", "2023-07-01", "2023-11-01")),
  label = c("2022-12", "2023-04", "2023-06/07", "2023-11")
)
band <- tibble(xmin = as.Date("2023-06-01"), xmax = as.Date("2023-07-31"))

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- load + assert we are on the live panel vintage ------------------------
cty <- read_csv(CTY_FILE, show_col_types = FALSE) |>
  mutate(month_date = as.Date(month_date))

id_panel <- read_csv(PANEL, show_col_types = FALSE) |>
  mutate(month_date = as.Date(month_date)) |>
  filter(state_abb == "ID") |>
  select(month_date, panel_filings = filings_count, panel_source, n_counties)

recon <- cty |>
  group_by(month_date) |>
  summarise(cty_sum = sum(filings_count), .groups = "drop") |>
  full_join(id_panel, by = "month_date")

stopifnot(nrow(recon) == nrow(id_panel),
          !any(is.na(recon$panel_filings)),
          !any(is.na(recon$cty_sum)),
          all(recon$cty_sum == recon$panel_filings))

cat(sprintf(
  "Panel check PASSED: %d ID months, %s..%s, source '%s', n_counties %s;\n  county sums == panel filings on every month.\n\n",
  nrow(recon), format(min(recon$month_date)), format(max(recon$month_date)),
  unique(id_panel$panel_source), paste(unique(id_panel$n_counties), collapse = "/")))

# ---- three groups ----------------------------------------------------------
grp_levels <- c("Ada", "Canyon", "Other 42 counties")

grp <- cty |>
  mutate(group = case_when(county == "Ada" ~ "Ada",
                           county == "Canyon" ~ "Canyon",
                           TRUE ~ "Other 42 counties")) |>
  group_by(group, month_date) |>
  summarise(filings = sum(filings_count), n_cty = n(), .groups = "drop") |>
  mutate(group = factor(group, levels = grp_levels)) |>
  arrange(group, month_date)

stopifnot(all(grp$n_cty[grp$group == "Other 42 counties"] == 42L))

state_tot <- grp |> group_by(month_date) |>
  summarise(filings = sum(filings), .groups = "drop") |> mutate(group = "Idaho (all 44)")

# 12-month centred rolling mean for the figures
roll12 <- function(x) {
  n <- length(x); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    lo <- i - 6L; hi <- i + 5L
    if (lo >= 1L && hi <= n) out[i] <- mean(x[lo:hi])
  }
  out
}
grp <- grp |> group_by(group) |> mutate(roll = roll12(filings)) |> ungroup()

# =============================================================================
# 1. Shares and growth decomposition, full calendar years only (2021-2025)
# =============================================================================
ann <- grp |>
  filter(year(month_date) %in% 2021:2025) |>
  group_by(group, yr = year(month_date)) |>
  summarise(filings = sum(filings), .groups = "drop")

ann_wide <- ann |> pivot_wider(names_from = yr, values_from = filings, names_prefix = "y")

state_ann <- ann |> group_by(yr) |> summarise(state = sum(filings), .groups = "drop")

growth_decomp <- ann_wide |>
  mutate(share_2021 = y2021 / sum(y2021),
         share_2025 = y2025 / sum(y2025),
         change_21_25 = y2025 - y2021,
         pct_change = 100 * (y2025 / y2021 - 1),
         share_of_state_growth = change_21_25 / sum(change_21_25))

write_csv(growth_decomp, file.path(OUT_DIR, "growth_decomposition_2021_2025.csv"))

cat("=== 1. Annual totals and who owns the growth (2021 -> 2025) ===\n")
print(growth_decomp |>
        mutate(across(c(share_2021, share_2025, share_of_state_growth), ~ round(100 * .x, 1)),
               pct_change = round(pct_change, 1)) |>
        as.data.frame())
cat(sprintf("\nStatewide: %.0f (2021) -> %.0f (2025), +%.1f%%\n",
            state_ann$state[state_ann$yr == 2021], state_ann$state[state_ann$yr == 2025],
            100 * (state_ann$state[state_ann$yr == 2025] / state_ann$state[state_ann$yr == 2021] - 1)))

cat("\nAnnual totals by group:\n")
print(ann |> pivot_wider(names_from = yr, values_from = filings) |> as.data.frame())

# =============================================================================
# 2. Trend: log-linear with month-of-year FE, by group and for two aggregates
# =============================================================================
trend_of <- function(df, from = NULL) {
  d <- df
  if (!is.null(from)) d <- d |> filter(month_date >= as.Date(from))
  d <- d |> mutate(t = as.numeric(month_date - min(month_date)) / 365.25,
                   moy = factor(month(month_date)),
                   ly  = log(filings))
  if (any(!is.finite(d$ly))) return(tibble(pct_per_yr = NA_real_, se = NA_real_, n = nrow(d)))
  fit <- lm(ly ~ t + moy, data = d)
  tibble(pct_per_yr = 100 * coef(fit)[["t"]],
         se = 100 * summary(fit)$coefficients["t", "Std. Error"],
         n = nrow(d))
}

agg <- bind_rows(
  grp |> select(group, month_date, filings) |> mutate(group = as.character(group)),
  state_tot |> select(group, month_date, filings),
  grp |> filter(group %in% BIG) |> group_by(month_date) |>
    summarise(filings = sum(filings), .groups = "drop") |> mutate(group = "Ada + Canyon")
) |> distinct(group, month_date, .keep_all = TRUE)

# NB "Other 42 counties" IS Idaho ex Ada+Canyon -- one series, not two.
series_levels <- c("Ada", "Canyon", "Ada + Canyon", "Other 42 counties", "Idaho (all 44)")

trends <- agg |>
  group_by(group) |>
  group_modify(~ bind_cols(
    trend_of(.x)               |> rename(full_pct = pct_per_yr, full_se = se, full_n = n),
    trend_of(.x, "2022-06-01") |> rename(post_pct = pct_per_yr, post_se = se, post_n = n))) |>
  ungroup() |>
  mutate(group = factor(group, levels = series_levels)) |>
  arrange(group)

# month-over-month log-change volatility (the statistic ID was once excluded on)
vol <- agg |> group_by(group) |> arrange(month_date, .by_group = TRUE) |>
  summarise(sd_mom_dlog = sd(diff(log(filings)), na.rm = TRUE),
            sd_yoy_dlog = sd(log(filings) - lag(log(filings), 12), na.rm = TRUE), .groups = "drop")

trend_tab <- left_join(trends, vol, by = "group")
write_csv(trend_tab, file.path(OUT_DIR, "trend_and_volatility_by_group.csv"))

cat("\n=== 2. Log-linear trend (month-of-year FE), %/yr ===\n")
print(trend_tab |> mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame())

# =============================================================================
# 3. Segments cut at the user-supplied markers; YoY log growth by segment
# =============================================================================
cuts <- c(as.Date("2021-01-01"), events$date, as.Date("2026-07-01"))
seg_labs <- c("2021-01..2022-11", "2022-12..2023-03", "2023-04..2023-06",
              "2023-07..2023-10", "2023-11..2026-06")

seg <- agg |>
  group_by(group) |> arrange(month_date, .by_group = TRUE) |>
  mutate(yoy = log(filings) - lag(log(filings), 12)) |>
  ungroup() |>
  mutate(seg = cut(month_date, breaks = cuts, labels = seg_labs, right = FALSE)) |>
  filter(!is.na(seg))

seg_tab <- seg |>
  group_by(group, seg) |>
  summarise(mean_filings = mean(filings),
            mean_yoy_pct = 100 * (exp(mean(yoy, na.rm = TRUE)) - 1),
            n_yoy = sum(!is.na(yoy)), .groups = "drop") |>
  mutate(group = factor(group, levels = series_levels)) |>
  arrange(group, seg)

write_csv(seg_tab, file.path(OUT_DIR, "segment_means_by_marker.csv"))

cat("\n=== 3. Segment means between the user-supplied markers ===\n")
print(seg_tab |>
        mutate(mean_filings = round(mean_filings, 1), mean_yoy_pct = round(mean_yoy_pct, 1)) |>
        pivot_wider(id_cols = group, names_from = seg,
                    values_from = mean_yoy_pct) |> as.data.frame())
cat("(cells are mean YoY log growth, %, within the segment)\n")

# =============================================================================
# 4. The expiry test: growth before vs after 2023-11
# =============================================================================
expiry <- as.Date("2023-11-01")
ba <- agg |>
  group_by(group) |> arrange(month_date, .by_group = TRUE) |>
  mutate(yoy = log(filings) - lag(log(filings), 12)) |>
  filter(!is.na(yoy)) |>
  mutate(period = if_else(month_date < expiry, "pre_2023_11", "post_2023_11")) |>
  group_by(group, period) |>
  summarise(mean_yoy_pct = 100 * (exp(mean(yoy)) - 1), n = n(), .groups = "drop") |>
  pivot_wider(names_from = period, values_from = c(mean_yoy_pct, n)) |>
  mutate(accel_pp = mean_yoy_pct_post_2023_11 - mean_yoy_pct_pre_2023_11,
         group = factor(group, levels = series_levels)) |>
  arrange(group)

write_csv(ba, file.path(OUT_DIR, "expiry_test_2023_11.csv"))

cat("\n=== 4. Expiry test: mean YoY growth before vs after 2023-11 ===\n")
print(ba |> mutate(across(where(is.numeric), ~ round(.x, 1))) |> as.data.frame())

# =============================================================================
# 4b. Is "the other 42 are flat" masking offsetting county moves?
#     Per-county trend for every county averaging >= 2 filings/month.
# =============================================================================
cty_trend <- cty |>
  group_by(county) |>
  filter(mean(filings_count) >= 2, all(filings_count > 0)) |>
  group_modify(~ trend_of(.x |> rename(filings = filings_count))) |>
  ungroup() |>
  left_join(cty |> group_by(county) |> summarise(mean_mo = mean(filings_count), .groups = "drop"),
            by = "county") |>
  arrange(desc(pct_per_yr))

write_csv(cty_trend, file.path(OUT_DIR, "per_county_trend.csv"))

cat("\n=== 4b. Per-county trend, counties averaging >= 2 filings/mo and never zero ===\n")
print(cty_trend |> mutate(across(where(is.numeric), ~ round(.x, 2))) |> as.data.frame())
cat(sprintf("\n%d of 44 counties qualify (they are %.1f%% of all filings).\n",
            nrow(cty_trend),
            100 * sum(cty$filings_count[cty$county %in% cty_trend$county]) / sum(cty$filings_count)))

# =============================================================================
# 5. Figures
# =============================================================================
vline_layers <- list(
  geom_rect(data = band, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            inherit.aes = FALSE, fill = "grey70", alpha = 0.25),
  geom_vline(data = events, aes(xintercept = date), inherit.aes = FALSE,
             linetype = "dashed", colour = "grey35", linewidth = 0.35)
)

p1 <- ggplot(grp, aes(month_date, filings)) +
  vline_layers +
  geom_line(colour = "grey55", linewidth = 0.35) +
  geom_point(size = 0.5, colour = "grey45") +
  geom_line(aes(y = roll), colour = "#1f4e79", linewidth = 0.9, na.rm = TRUE) +
  facet_wrap(~ group, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "6 months", date_labels = "%Y-%m") +
  labs(x = NULL, y = "Monthly eviction (A12) filings",
       title = "Idaho monthly filings: Ada, Canyon, and the other 42 counties",
       subtitle = "Blue = 12-month centred rolling mean. Dashed lines / band = user-supplied policy markers (provenance not yet in repo).",
       caption = "Source: Idaho Judicial Branch A12, data/raw/idaho/id_county_month_a12.csv (= live panel Idaho, boundary 11). Free y-axes.") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        plot.caption = element_text(size = 7, colour = "grey40"),
        plot.subtitle = element_text(size = 8, colour = "grey30"))

base_mean <- grp |> filter(year(month_date) == 2021) |>
  group_by(group) |> summarise(base = mean(filings), .groups = "drop")

idx <- grp |> left_join(base_mean, by = "group") |>
  mutate(index = 100 * roll / base)

p2 <- ggplot(idx |> filter(!is.na(index)), aes(month_date, index, colour = group)) +
  vline_layers +
  geom_hline(yintercept = 100, colour = "grey80", linewidth = 0.3) +
  geom_line(linewidth = 0.9) +
  scale_x_date(date_breaks = "6 months", date_labels = "%Y-%m") +
  scale_colour_manual(values = c("Ada" = "#c0392b", "Canyon" = "#e67e22",
                                 "Other 42 counties" = "#1f4e79"), name = NULL) +
  labs(x = NULL, y = "12-month rolling mean, 2021 mean = 100",
       title = "Same three groups, indexed to their own 2021 level",
       subtitle = "Comparable drift. If the statewide trend is an Ada story, the blue line stays near 100.",
       caption = "Source: Idaho Judicial Branch A12. Rolling mean is centred, so it starts 2021-07 and ends 2026-01.") +
  theme(legend.position = "top",
        axis.text.x = element_text(angle = 45, hjust = 1),
        plot.caption = element_text(size = 7, colour = "grey40"),
        plot.subtitle = element_text(size = 8, colour = "grey30"))

ggsave(file.path(FIG_DIR, "idaho_ada_canyon_levels.png"), p1, width = 9, height = 9, dpi = 200)
ggsave(file.path(FIG_DIR, "idaho_ada_canyon_levels.pdf"), p1, width = 9, height = 9)
ggsave(file.path(FIG_DIR, "idaho_ada_canyon_indexed.png"), p2, width = 9, height = 5.2, dpi = 200)
ggsave(file.path(FIG_DIR, "idaho_ada_canyon_indexed.pdf"), p2, width = 9, height = 5.2)

write_csv(grp |> select(group, month_date, filings, roll),
          file.path(OUT_DIR, "group_month_series.csv"))

cat("\nWrote: figures/idaho_ada_canyon_{levels,indexed}.{png,pdf} and", OUT_DIR, "/*.csv\n")
