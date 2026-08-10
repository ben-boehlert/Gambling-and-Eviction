#!/usr/bin/env Rscript
################################################################################
# pretrends_border_county.R
#
# Sun-Abraham TWFE event study on the border-county subsample. Used as the
# parallel-trends diagnostic for the border-discontinuity design proposal.
#
# Mirrors the SunAb block from analysis/pretrends/pretrends_statepanel_template.R
# but at the county level on the border subsample.
#
# Outputs:
#   output/border_diagnostic/pretrends_border_eventstudy.csv
#   output/border_diagnostic/pretrends_border_eventstudy.png
#   output/border_diagnostic/pretrends_border_summary.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
  library(ggplot2)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

p_border <- file.path(repo_root, "data", "processed",
                      "county_month_border_panel.csv")

# ----------------------------- panel build ------------------------------------
COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

panel <- read_csv(p_border, show_col_types = FALSE) %>%
  mutate(
    month_date  = as.Date(month_date),
    treat_start = as.Date(treat_start)
  ) %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start),
                as.integer(ym_index(treat_start)),
                NA_integer_),
    unit_id = as.integer(fips),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t)) %>%
  mutate(
    # NA for never-treated → sunab() needs a sentinel; use a far-future int.
    g_sunab = if_else(is.na(g), 10000L, as.integer(g)),
    event_time = if_else(is.na(g), NA_integer_, as.integer(t - g))
  ) %>%
  arrange(unit_id, t)

# Drop event-time observations that are too sparsely represented.
event_counts <- panel %>%
  filter(!is.na(event_time)) %>%
  count(event_time, name = "n_obs")

keep_event <- event_counts %>%
  filter(n_obs >= 30) %>%   # need enough mass to identify
  pull(event_time)

panel_es <- panel %>%
  filter(is.na(event_time) | event_time %in% keep_event)

cat("Border-county event-study panel: ", nrow(panel_es), " obs, ",
    n_distinct(panel_es$unit_id), " counties, ",
    n_distinct(panel_es$state_abb), " states\n", sep = "")
cat("Event-times retained: ", min(keep_event), "..", max(keep_event), "\n",
    sep = "")

# ----------------------------- Sun-Abraham fit --------------------------------
# Reference period: -1 (period just before treatment).
# Never-treated as the always-control reference.
es <- fixest::feols(
  y ~ sunab(cohort = g_sunab, period = t, ref.p = -1) | unit_id + t,
  data = panel_es,
  cluster = ~state_abb
)

# sunab() already returns event-time-aggregated coefficients; just extract.
ct <- as_tibble(fixest::coeftable(es), rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`,
         t_stat = `t value`, p_value = `Pr(>|t|)`) %>%
  mutate(
    event_time  = suppressWarnings(as.integer(sub("^t::", "", term))),
    panel_label = "border_county_sunab"
  ) %>%
  filter(!is.na(event_time))

es_tab <- ct %>%
  select(panel_label, event_time, estimate, se, t_stat, p_value, term)

write_csv(es_tab %>% select(-term),
          file.path(out_dir, "pretrends_border_eventstudy.csv"))

# Pre-trends joint test: Wald F on pre-period coefficients (event_time < -1).
pre_terms <- es_tab %>% filter(event_time < -1) %>% pull(term)

wald_pre <- if (length(pre_terms) >= 1) {
  pre_pattern <- paste0("^(", paste(gsub("([.+*?^$()|\\[\\]\\\\])", "\\\\\\1",
                                          pre_terms), collapse = "|"), ")$")
  tryCatch(
    fixest::wald(es, keep = pre_pattern, print = FALSE),
    error = function(e) NULL
  )
} else NULL

# fixest::wald() returns a named list/vector — pull stat/p safely.
get_wald_field <- function(w, field) {
  if (is.null(w)) return(NA_real_)
  if (is.list(w) && field %in% names(w)) return(as.numeric(w[[field]]))
  if (is.numeric(w) && field %in% names(w)) return(as.numeric(w[field]))
  NA_real_
}

pre_summary <- tibble(
  panel_label   = "border_county_sunab",
  n_obs         = nrow(panel_es),
  n_counties    = n_distinct(panel_es$unit_id),
  n_states      = n_distinct(panel_es$state_abb),
  n_pre_coefs   = length(pre_terms),
  wald_stat     = get_wald_field(wald_pre, "stat"),
  wald_p        = get_wald_field(wald_pre, "p")
)
write_csv(pre_summary, file.path(out_dir, "pretrends_border_summary.csv"))

cat("\n=== PRETRENDS (border county Sun-Abraham) ===\n")
print(pre_summary)

# ----------------------------- plot -------------------------------------------
# Only event times in keep_event for the plot.
es_plot <- es_tab %>%
  filter(!is.na(event_time)) %>%
  filter(event_time >= -24, event_time <= 24) %>%
  mutate(
    ci_low  = estimate - 1.96 * se,
    ci_high = estimate + 1.96 * se
  )

p <- ggplot(es_plot, aes(x = event_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey50") +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "grey80", alpha = 0.4) +
  geom_line(color = "grey20", linewidth = 0.6) +
  geom_point(color = "grey20", size = 1.8) +
  scale_x_continuous(breaks = seq(-24, 24, 6)) +
  labs(x = "Months relative to gambling legalization",
       y = "Effect on log(filings + 1)") +
  theme_minimal(base_size = 11, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA)
  )

ggsave(file.path(out_dir, "pretrends_border_eventstudy.png"), p,
       width = 6.5, height = 4.0, dpi = 300, bg = "transparent")

cat("\nWrote:\n",
    "  ", file.path(out_dir, "pretrends_border_eventstudy.csv"), "\n",
    "  ", file.path(out_dir, "pretrends_border_eventstudy.png"), "\n",
    "  ", file.path(out_dir, "pretrends_border_summary.csv"), "\n")
