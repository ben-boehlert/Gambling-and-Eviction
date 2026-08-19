#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Never-treated eviction trends BEFORE vs AFTER COVID — the descriptive
# companion to covid_global_pt_diagnostic.R (which tests level shifts across
# the splice). Two questions, both about did2s/BJS's GLOBAL parallel-trends
# requirement (Y(0) = alpha_i + lambda_t fit on ALL untreated cells):
#
#   1. Do never-treated states' TRENDS differ before vs after COVID?
#      (If yes, one additive model spanning the splice is misspecified —
#      the spliced-window failure mode.)
#   2. WITHIN each segment alone, how much do state effects drift?
#      (The post-COVID-only segment is what the post-COVID did2s design
#      relies on; within-segment drift is its residual global-PT risk.
#      Implemented as the same half-split shift test the parent diagnostic
#      uses on the pre period, applied to each segment symmetrically.)
#
# Never-treated only, so treatment cannot confound anything. Real outcomes;
# allowed under the blindness protocol (untreated data). Window conventions
# follow the parent diagnostic (drop 2020-03..2022-03).
#
# NOTE on inference: regressors vary at the state level and clustering is by
# state, so joint Wald statistics are degenerate here (the parent script's
# astronomical F values). This script reports MAGNITUDES (slopes, shift SDs)
# and treats them descriptively.
#
# Usage:  Rscript analysis/diagnostics/nevertreated_trends_pre_post_covid.R
# Output: output/covid_global_pt/nevertreated_{trajectories.png,slopes.csv,
#         segment_drift.csv}
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(fixest); library(glue)
})
theme_set(theme_minimal())

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/covid_global_pt"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

MIN_DATE   <- as.Date("2016-01-01")
MAX_DATE   <- as.Date("2024-12-31")
DROP_START <- as.Date("2020-03-01")
DROP_END   <- as.Date("2022-03-31")

ym_index <- function(d) {
  (as.integer(format(d, "%Y")) - 2000L) * 12L + as.integer(format(d, "%m"))
}

panel0 <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                   show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb),
            month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE)

# Balance to common coverage on the SPLICED sample, matching the parent
# diagnostic and the pretrends pipeline (ME included post-repair).
spliced <- panel0 %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))
coverage  <- spliced %>% count(state_abb, name = "n")
keep      <- coverage %>% filter(n >= max(n)) %>% pull(state_abb)
spliced   <- spliced %>% filter(state_abb %in% keep)
n_st      <- n_distinct(spliced$state_abb)
common_mo <- spliced %>% count(month_date, name = "k") %>%
  filter(k == n_st) %>% pull(month_date)
spliced   <- spliced %>% filter(month_date %in% common_mo)

treat <- load_eviction_treatment_schedule(
  treat_file = "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date", states = spliced$state_abb)

nt <- spliced %>%
  left_join(treat, by = "state_abb") %>%
  filter(is.na(treat_start)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         segment = if_else(month_date > DROP_END, "post", "pre"))

cat(glue("Never-treated states: {n_distinct(nt$state_abb)} ",
         "({paste(sort(unique(nt$state_abb)), collapse=', ')}); ",
         "pre months: {n_distinct(nt$t[nt$segment=='pre'])}, ",
         "post months: {n_distinct(nt$t[nt$segment=='post'])}"), "\n\n")

# ── 1. Per-state linear slopes, pre vs post (log points / month) ─────────────
slopes <- nt %>%
  group_by(state_abb, segment) %>%
  group_modify(~ {
    f <- lm(y ~ t, data = .x)
    tibble(slope = coef(f)[["t"]], se = summary(f)$coefficients["t", 2],
           n_months = n_distinct(.x$t))
  }) %>%
  ungroup() %>%
  pivot_wider(names_from = segment, values_from = c(slope, se, n_months)) %>%
  mutate(slope_diff = slope_post - slope_pre,
         ann_pct_pre  = 100 * (exp(12 * slope_pre) - 1),
         ann_pct_post = 100 * (exp(12 * slope_post) - 1))

cat("=== Per-state linear trends (never-treated), annualized % change ===\n")
print(slopes %>%
        transmute(state_abb, ann_pct_pre = round(ann_pct_pre, 1),
                  ann_pct_post = round(ann_pct_post, 1),
                  slope_diff_monthly = round(slope_diff, 4)) %>%
        arrange(desc(abs(slope_diff_monthly))) %>% as.data.frame(),
      row.names = FALSE)
cat(glue("\n  SD of slopes across states: pre {round(sd(slopes$slope_pre), 4)}, ",
         "post {round(sd(slopes$slope_post), 4)} log pts/month ",
         "(annualized: pre {round(sd(slopes$ann_pct_pre), 1)}pp, ",
         "post {round(sd(slopes$ann_pct_post), 1)}pp)"), "\n")
cat(glue("  Mean slope: pre {round(mean(slopes$slope_pre), 4)}, ",
         "post {round(mean(slopes$slope_post), 4)} log pts/month"), "\n\n")

# ── 2. Within-segment drift: half-split state-shift SD per segment ───────────
seg_drift <- map_dfr(c("pre", "post"), function(sg) {
  d <- nt %>% filter(segment == sg)
  mid <- median(unique(d$t))
  d <- d %>% mutate(late_half = t > mid, state_abb = factor(state_abb))
  m <- feols(y ~ i(state_abb, late_half) | state_abb + t, data = d,
             cluster = ~state_abb)
  sh <- broom::tidy(m) %>% filter(str_detect(term, "state_abb")) %>%
    pull(estimate)
  sh <- c(sh, 0)                      # the collinearity-dropped reference state
  tibble(segment = sg, n_months = n_distinct(d$t),
         shift_sd = sd(sh - mean(sh)),
         shift_range = max(sh) - min(sh))
})
cat("=== Within-segment half-split drift of state effects (never-treated) ===\n")
print(seg_drift %>% mutate(across(where(is.numeric), ~round(.x, 3))) %>%
        as.data.frame(), row.names = FALSE)
cat("  (Across-COVID shift SD from the parent diagnostic: 0.467 log points.)\n\n")

write_csv(slopes, file.path(OUT_DIR, "nevertreated_slopes.csv"))
write_csv(seg_drift, file.path(OUT_DIR, "nevertreated_segment_drift.csv"))

# ── 3. Trajectory figure: log filings indexed to each state's pre-COVID mean ──
traj <- nt %>%
  group_by(state_abb) %>%
  mutate(y_idx = y - mean(y[segment == "pre"])) %>%
  ungroup()
p <- ggplot(traj, aes(month_date, y_idx, group = state_abb)) +
  geom_line(alpha = 0.55, linewidth = 0.4) +
  geom_smooth(aes(group = segment), method = "loess", se = FALSE,
              linewidth = 1.0, color = "black") +
  annotate("rect", xmin = DROP_START, xmax = DROP_END,
           ymin = -Inf, ymax = Inf, alpha = 0.12) +
  geom_hline(yintercept = 0, linetype = "dotted") +
  facet_wrap(~state_abb) +
  labs(x = NULL, y = "Log filings, deviation from own pre-COVID mean")
ggsave(file.path(OUT_DIR, "nevertreated_trajectories.png"), p,
       width = 10, height = 7, dpi = 150)

cat(glue("Wrote {OUT_DIR}/nevertreated_*\n"))
