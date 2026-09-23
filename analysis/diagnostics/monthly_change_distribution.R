################################################################################
# analysis/diagnostics/monthly_change_distribution.R
#
# How unusual is a large month-over-month jump in eviction filings?
#
# Motivation: the 2026-09-17 plausibility band censors a state-month at +/-50%
# of its expected level. That is only defensible if month-over-month moves that
# large are genuinely rare. This measures the empirical distribution.
#
# Measured on the PRE-CENSOR panel (4,304 rows) and the raw county download, so
# the distribution is not conditioned on the rule it is being used to judge.
#
# Restrictions, all of which matter:
#   * CONSECUTIVE months only (a change across a gap is not a monthly change)
#   * COVID era dropped entirely: keep < 2020-01 and > 2021-12, per Ben
#   * MINIMUM LEVEL on BOTH months, so 1 -> 2 is not a 100% increase
#   * CONSTANT COMPOSITION: same county count in both months, so a basket
#     change is not read as an eviction change
#
# Run from the project root:
#   Rscript analysis/diagnostics/monthly_change_distribution.R
# Outputs: figures/monthly_change_distribution.png
#          output/inclusion_rule/monthly_change_quantiles.csv
################################################################################
suppressPackageStartupMessages({
  library(tidyverse); library(lubridate); library(glue)
})
theme_set(theme_minimal())

MIN_LEVEL <- as.numeric(Sys.getenv("MIN_LEVEL", "100"))
PRE  <- as.Date("2020-01-01")
POST <- as.Date("2021-12-31")
mi <- function(d) year(d) * 12L + (month(d) - 1L)

pct_changes <- function(df, id, level_min, comp = NULL) {
  df %>%
    filter(month_date < PRE | month_date > POST) %>%
    arrange(.data[[id]], month_date) %>%
    group_by(.data[[id]]) %>%
    mutate(prev = lag(filings_count), gap = mi(month_date) - lag(mi(month_date)),
           prev_comp = if (is.null(comp)) NA_real_ else lag(.data[[comp]]),
           this_comp = if (is.null(comp)) NA_real_ else .data[[comp]]) %>%
    ungroup() %>%
    filter(gap == 1L,
           # both months in the SAME era (never straddle the COVID hole)
           (month_date < PRE) == ((month_date %m-% months(1)) < PRE),
           filings_count >= level_min, prev >= level_min,
           is.null(comp) | is.na(prev_comp) | prev_comp == this_comp) %>%
    mutate(pct = 100 * (filings_count - prev) / prev)
}

state <- read_csv("data/raw/deprecated/state_month_panel_with_treatment_pre_value_censor_2026-09-17.csv",
                  show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  pct_changes("state_abb", MIN_LEVEL, comp = "n_counties") %>%
  mutate(level = "State-month (analysis panel)")

county <- read_csv("data/raw/monthly_county_data_download.csv", show_col_types = FALSE,
                   col_types = cols(fips = col_character())) %>%
  filter(!is.na(filings_count)) %>%
  mutate(month_date = floor_date(as.Date(date), "month")) %>%
  select(fips, month_date, filings_count) %>%
  pct_changes("fips", MIN_LEVEL) %>%
  mutate(level = "County-month (LSC download)")

both <- bind_rows(state %>% select(level, pct), county %>% select(level, pct))

qs <- both %>% group_by(level) %>%
  summarise(n = n(),
            p1 = quantile(pct, .01), p5 = quantile(pct, .05),
            p25 = quantile(pct, .25), median = median(pct),
            p75 = quantile(pct, .75), p95 = quantile(pct, .95),
            p99 = quantile(pct, .99),
            sd = sd(pct),
            share_gt_25 = mean(abs(pct) > 25), share_gt_50 = mean(abs(pct) > 50),
            share_up_50 = mean(pct > 50), share_dn_50 = mean(pct < -50),
            .groups = "drop")
dir.create("output/inclusion_rule", showWarnings = FALSE, recursive = TRUE)
write_csv(qs, "output/inclusion_rule/monthly_change_quantiles.csv")
cat(glue("\nMinimum level: {MIN_LEVEL} filings in BOTH months; COVID era (2020-01..2021-12) dropped\n\n"))
print(as.data.frame(qs %>% mutate(across(where(is.numeric), ~round(.x, 3)))), row.names = FALSE)

cat("\n-- sensitivity to the minimum level (state-month) --\n")
raw_state <- read_csv("data/raw/deprecated/state_month_panel_with_treatment_pre_value_censor_2026-09-17.csv",
                      show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
map_dfr(c(25, 50, 100, 250, 500), function(m) {
  d <- pct_changes(raw_state, "state_abb", m, comp = "n_counties")
  tibble(min_level = m, n = nrow(d), sd = round(sd(d$pct), 1),
         p95 = round(quantile(d$pct, .95), 1), p99 = round(quantile(d$pct, .99), 1),
         share_up_50 = round(mean(d$pct > 50), 4))
}) %>% as.data.frame() %>% print(row.names = FALSE)

p <- ggplot(both, aes(x = pct)) +
  geom_histogram(binwidth = 2.5, boundary = 0, fill = "grey35", colour = NA) +
  geom_vline(xintercept = c(-50, 50), linetype = "dashed", colour = "firebrick") +
  geom_vline(xintercept = 0, linewidth = 0.3, colour = "grey60") +
  facet_wrap(~level, scales = "free_y", ncol = 1) +
  coord_cartesian(xlim = c(-100, 150)) +
  labs(x = "Month-over-month change in filings (%)", y = "State-months / county-months",
       subtitle = glue("Consecutive months only, constant county composition, ",
                       ">= {MIN_LEVEL} filings in both months. ",
                       "COVID era (2020-01..2021-12) excluded. ",
                       "Dashed lines at +/-50%."))
dir.create("figures", showWarnings = FALSE)
ggsave("figures/monthly_change_distribution.png", p, width = 9, height = 6.5, dpi = 150)
cat("\nFigure: figures/monthly_change_distribution.png\n")
