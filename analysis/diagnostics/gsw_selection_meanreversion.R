#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# gsw_selection_meanreversion.R  (2026-09-18)
#
# Ghanem, Sant'Anna & Wuthrich (GSW) framing of the moratorium-rebound threat to
# parallel trends: PT fails only if BOTH
#   (a) SELECTION   -- launch timing is related to a state's COVID displacement
#   (b) NON-MARTINGALE -- that displacement still predicts subsequent changes
#       in untreated outcomes (mean reversion)
# hold jointly. Measures each, at every candidate long-difference base month b,
# using UNTREATED state-months only (anticipation = 6 months) plus timing.
# Blindness-safe: no treatment effect is ever estimated or printed.
#
# Usage: Rscript analysis/diagnostics/gsw_selection_meanreversion.R
# Output: output/gsw_selection_meanreversion/
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
  library(sandwich)
  library(lmtest)
  library(patchwork)
})

theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/gsw_selection_meanreversion"
FIG_DIR <- file.path(OUT_DIR, "figures")
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

PANEL_FILE <- "data/raw/state_month_panel_with_treatment.csv"
TREAT_FILE <- "data/raw/sports_gambling_legalization_dates.csv"

ANTICIPATION_MONTHS <- 6L
NORM_YEARS   <- 2017:2019
NORM_MIN_YRS <- 2L
BASE_MIN     <- 4L   # of 6 baseline months
OUT_MIN      <- 7L   # of 13 outcome months
THIN_N       <- 8L   # states; never silently drop below this

B_SEQ <- seq(as.Date("2021-08-01"), as.Date("2023-06-01"), by = "month")

ym_index <- function(d) as.integer(lubridate::year(d)) * 12L + as.integer(lubridate::month(d))

# ── Load panel; drop NV (always-treated pre-PASPA, never a legitimate control) ──
panel_raw <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  mutate(state_abb = as.character(state_abb), month_date = as.Date(month_date))

nv_dropped <- panel_raw %>% filter(state_abb %in% PRE_PASPA_SPORTS_BETTING)
panel <- panel_raw %>% filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING)

stopifnot(!("NV" %in% unique(panel$state_abb)))
cat(glue("Dropped {nrow(nv_dropped)} NV state-months (pre-PASPA always-treated; ",
         "never a legitimate control). {n_distinct(panel$state_abb)} states remain."), "\n")

# ── y = log(filings_count); drop zero/NA months rather than log1p ──────────────
n_zero_na <- sum(is.na(panel$filings_count) | panel$filings_count <= 0)
cat(glue("Dropping {n_zero_na} of {nrow(panel)} state-months with zero/NA filings_count ",
         "before taking logs (no log1p)."), "\n")

panel_y <- panel %>%
  filter(!is.na(filings_count), filings_count > 0) %>%
  transmute(state_abb, month_date,
            my = ym_index(month_date),
            cal_month = month(month_date),
            yr = year(month_date),
            y = log(filings_count))

# ── norm_{s,m}: mean y in calendar month m, 2017-2019, >= 2 of 3 years ─────────
norm_tbl <- panel_y %>%
  filter(yr %in% NORM_YEARS) %>%
  group_by(state_abb, cal_month) %>%
  summarise(n_years = n(), norm = mean(y), .groups = "drop") %>%
  filter(n_years >= NORM_MIN_YRS)

norm_coverage <- norm_tbl %>%
  group_by(state_abb) %>%
  summarise(n_calmonths_with_norm = n(), .groups = "drop") %>%
  right_join(tibble(state_abb = sort(unique(panel_y$state_abb))), by = "state_abb") %>%
  mutate(n_calmonths_with_norm = replace_na(n_calmonths_with_norm, 0L)) %>%
  arrange(n_calmonths_with_norm)

full_dropouts <- norm_coverage %>% filter(n_calmonths_with_norm == 0) %>% pull(state_abb)
partial_states <- norm_coverage %>%
  filter(n_calmonths_with_norm > 0, n_calmonths_with_norm < 12) %>% pull(state_abb)

cat(glue("States with NO usable 2017-2019 norm (drop out entirely): ",
         "{paste(full_dropouts, collapse = ', ')}"), "\n")
if (length(partial_states) > 0) {
  cat(glue("States with PARTIAL calendar-month norm coverage (< 12 of 12 months): ",
           "{paste(partial_states, collapse = ', ')}"), "\n")
}

# ── Launch timing (online), from the canonical schedule; never re-derived ─────
launch_tbl <- load_eviction_treatment_schedule(
  treat_file = TREAT_FILE,
  treat_date_col = "online_start_date",
  states = sort(unique(panel_y$state_abb))
) %>%
  transmute(state_abb, launch_my = ifelse(is.na(treat_start), NA_integer_, ym_index(treat_start)))

# ── Deseasonalized, untreated-flagged deviations ───────────────────────────────
dev_input <- panel_y %>%
  left_join(norm_tbl %>% select(state_abb, cal_month, norm), by = c("state_abb", "cal_month")) %>%
  left_join(launch_tbl, by = "state_abb") %>%
  mutate(
    raw_dev   = y - norm,
    untreated = is.na(launch_my) | (launch_my - my >= ANTICIPATION_MONTHS),
    eff_dev   = ifelse(untreated, raw_dev, NA_real_)
  )

# ── Per-base-month computation ────────────────────────────────────────────────
compute_one_b <- function(b) {
  my_b <- ym_index(b)
  base_range <- (my_b - 5L):my_b
  out_range  <- (my_b + 12L):(my_b + 24L)

  base_summary <- dev_input %>%
    filter(my %in% base_range) %>%
    group_by(state_abb, launch_my) %>%
    summarise(n_base = sum(!is.na(eff_dev)),
              dev = if (sum(!is.na(eff_dev)) >= BASE_MIN) mean(eff_dev, na.rm = TRUE) else NA_real_,
              .groups = "drop") %>%
    filter(!is.na(dev))

  out_summary <- dev_input %>%
    filter(my %in% out_range) %>%
    group_by(state_abb) %>%
    summarise(n_out = sum(!is.na(eff_dev)),
              out_mean = if (sum(!is.na(eff_dev)) >= OUT_MIN) mean(eff_dev, na.rm = TRUE) else NA_real_,
              .groups = "drop") %>%
    filter(!is.na(out_mean))

  # Contributing-cells audit: every (state, my) that fed dev or the outcome mean
  # must be untreated as of that b. Checked directly against dev_input's own
  # `untreated` flag on the exact rows the two summaries were built from.
  contrib <- dev_input %>%
    filter((my %in% base_range | my %in% out_range),
           state_abb %in% c(base_summary$state_abb, out_summary$state_abb),
           !is.na(eff_dev))
  stopifnot(all(contrib$untreated))
  stopifnot(all(is.na(contrib$launch_my) | (contrib$launch_my - contrib$my >= ANTICIPATION_MONTHS)))

  sel_sample <- base_summary %>%
    mutate(group = ifelse(is.na(launch_my), "never_launcher", "later_launcher"))

  n_dev_sample <- nrow(sel_sample)
  n_later <- sum(sel_sample$group == "later_launcher")
  n_never <- sum(sel_sample$group == "never_launcher")
  sd_dev  <- sd(sel_sample$dev)

  # (a)(i) Welch t-test: later-launchers vs never-launchers, on dev
  # t.test(x, y) is always ordered mean(x) - mean(y), so pass later first, never
  # second -- avoids relying on factor/formula level ordering to get the sign right.
  diff_later_never <- NA_real_; diff_se <- NA_real_
  diff_ci_lo <- NA_real_; diff_ci_hi <- NA_real_; diff_p <- NA_real_
  later_vals <- sel_sample$dev[sel_sample$group == "later_launcher"]
  never_vals <- sel_sample$dev[sel_sample$group == "never_launcher"]
  if (n_later >= 2 && n_never >= 2) {
    tt <- t.test(later_vals, never_vals)
    diff_later_never <- unname(tt$estimate[1] - tt$estimate[2])
    diff_se <- unname(diff_later_never / tt$statistic)
    diff_ci_lo <- tt$conf.int[1]; diff_ci_hi <- tt$conf.int[2]
    diff_p <- tt$p.value
  }

  # (a)(ii) Spearman correlation of launch month with dev, among later-launchers
  later <- sel_sample %>% filter(group == "later_launcher")
  n_spearman <- nrow(later)
  spearman_rho <- NA_real_; spearman_p <- NA_real_
  if (n_spearman >= 3) {
    sp <- suppressWarnings(cor.test(later$launch_my, later$dev, method = "spearman"))
    spearman_rho <- unname(sp$estimate); spearman_p <- sp$p.value
  }

  # (b) Mean-reversion regression: d_{s,b} ~ dev_{s,b}, HC3 SEs
  reg_tbl <- base_summary %>%
    inner_join(out_summary, by = "state_abb") %>%
    mutate(d = out_mean - dev)

  n_reg <- nrow(reg_tbl)
  slope <- NA_real_; slope_se <- NA_real_
  slope_ci_lo <- NA_real_; slope_ci_hi <- NA_real_; r2 <- NA_real_
  if (n_reg >= 3 && sd(reg_tbl$dev) > 0) {
    fit <- lm(d ~ dev, data = reg_tbl)
    vc <- vcovHC(fit, type = "HC3")
    ct <- coeftest(fit, vcov. = vc)
    ci <- tryCatch(coefci(fit, vcov. = vc, level = 0.95), error = function(e) matrix(NA, 2, 2))
    slope <- unname(ct["dev", "Estimate"])
    slope_se <- unname(ct["dev", "Std. Error"])
    slope_ci_lo <- unname(ci["dev", 1]); slope_ci_hi <- unname(ci["dev", 2])
    r2 <- summary(fit)$r.squared
  }

  thin <- (n_reg < THIN_N) || ((n_later + n_never) < THIN_N)

  list(
    row = tibble(
      b = b, n_dev_sample = n_dev_sample, n_later = n_later, n_never = n_never,
      sd_dev = sd_dev,
      diff_later_never = diff_later_never, diff_se = diff_se,
      diff_ci_lo = diff_ci_lo, diff_ci_hi = diff_ci_hi, diff_p = diff_p,
      n_spearman = n_spearman, spearman_rho = spearman_rho, spearman_p = spearman_p,
      n_reg = n_reg, slope = slope, slope_se = slope_se,
      slope_ci_lo = slope_ci_lo, slope_ci_hi = slope_ci_hi, r2 = r2,
      thin = thin
    ),
    state_rows = reg_tbl %>%
      mutate(b = b, group = ifelse(is.na(launch_my), "never_launcher", "later_launcher")) %>%
      select(state_abb, b, dev, d, group)
  )
}

results <- map(B_SEQ, compute_one_b)
by_base_month <- map_dfr(results, "row")
state_dev_by_base_month <- map_dfr(results, "state_rows")

stopifnot(!("NV" %in% unique(state_dev_by_base_month$state_abb)))

if (any(by_base_month$thin)) {
  thin_b <- format(by_base_month$b[by_base_month$thin], "%Y-%m")
  cat(glue("THIN (n < {THIN_N}) at base months: {paste(thin_b, collapse = ', ')} -- kept, flagged."), "\n")
}

# ── Console table ──────────────────────────────────────────────────────────────
cat("\n=== by_base_month (rounded) ===\n")
print(
  by_base_month %>%
    mutate(b = format(b, "%Y-%m")) %>%
    mutate(across(where(is.numeric), ~round(.x, 3))) %>%
    as.data.frame(),
  row.names = FALSE
)

# ── Write outputs ──────────────────────────────────────────────────────────────
write_csv(by_base_month, file.path(OUT_DIR, "by_base_month.csv"))
write_csv(state_dev_by_base_month, file.path(OUT_DIR, "state_dev_by_base_month.csv"))

# ── Figures ─────────────────────────────────────────────────────────────────────
p_slope <- ggplot(by_base_month, aes(b, slope)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_ribbon(aes(ymin = slope_ci_lo, ymax = slope_ci_hi), alpha = 0.15) +
  geom_line() + geom_point(aes(shape = thin), size = 2) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.18))) +
  scale_x_date(date_labels = "%Y-%m") +
  labs(x = NULL, y = "Mean-reversion slope: d(s,b) on dev(s,b)", tag = "Panel A") +
  theme(plot.margin = margin(t = 18, r = 12, b = 5, l = 5))

p_selection <- ggplot(by_base_month, aes(b, diff_later_never)) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  geom_ribbon(aes(ymin = diff_ci_lo, ymax = diff_ci_hi), alpha = 0.15) +
  geom_line() + geom_point(aes(shape = thin), size = 2) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.18))) +
  scale_x_date(date_labels = "%Y-%m") +
  labs(x = "Base month b", y = "Later-launcher minus never-launcher mean dev(s,b)", tag = "Panel B") +
  theme(plot.margin = margin(t = 18, r = 12, b = 5, l = 5))

fig <- p_slope / p_selection

ggsave(file.path(FIG_DIR, "gsw_selection_meanreversion.png"), fig, width = 8, height = 8.5, dpi = 150)
ggsave(file.path(FIG_DIR, "gsw_selection_meanreversion.pdf"), fig, width = 8, height = 8.5)

cat(glue("\nWrote {OUT_DIR}/by_base_month.csv, {OUT_DIR}/state_dev_by_base_month.csv, ",
         "{FIG_DIR}/gsw_selection_meanreversion.{{png,pdf}}"), "\n")
