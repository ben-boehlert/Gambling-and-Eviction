################################################################################
# test-loader.R
#
# Sample selection, g column, COVID filter, and quarterly aggregation.
################################################################################

library(lubridate)

cfg <- read_power_config("config/power_validation.yml")

test_that("S1 caps months at the universal cutoff and g is all zero", {
  panel <- load_blinded_panel(level = "state", sample = "S1",
                              treat_def = "online_start_date", covid = "keep",
                              config = cfg)
  expect_lte(max(panel$month_date), as.Date("2018-05-31"))
  expect_true(all(panel$g == 0))
})

test_that("covid='drop' removes the config COVID window", {
  panel <- load_blinded_panel(level = "state", sample = "S3",
                              treat_def = "online_start_date", covid = "drop",
                              config = cfg)
  win <- cfg$covid_drop
  in_window <- panel$month_date >= win[1] & panel$month_date <= win[2]
  expect_equal(sum(in_window), 0L)

  # And 'keep' retains at least some of those months (sanity contrast).
  panel_keep <- load_blinded_panel(level = "state", sample = "S3",
                                   treat_def = "online_start_date",
                                   covid = "keep", config = cfg)
  expect_gt(sum(panel_keep$month_date >= win[1] & panel_keep$month_date <= win[2]),
            0L)
})

test_that("quarterly aggregation sums monthly counts for a spot-checked state", {
  m <- load_blinded_panel(level = "state", sample = "S3",
                          treat_def = "online_start_date", covid = "keep",
                          config = cfg, quarterly = FALSE)
  q <- load_blinded_panel(level = "state", sample = "S3",
                          treat_def = "online_start_date", covid = "keep",
                          config = cfg, quarterly = TRUE)

  st <- m$state_abb[1]
  m_st <- m %>% dplyr::filter(state_abb == st) %>%
    dplyr::mutate(qd = floor_date(month_date, "quarter")) %>%
    dplyr::group_by(qd) %>%
    dplyr::summarise(fc = sum(filings_count), .groups = "drop")
  q_st <- q %>% dplyr::filter(state_abb == st) %>%
    dplyr::select(month_date, filings_count) %>%
    dplyr::arrange(month_date)

  joined <- dplyr::inner_join(m_st, q_st, by = c("qd" = "month_date"))
  expect_equal(joined$fc, joined$filings_count)
  # Quarterly totals must equal the overall monthly total for the state.
  expect_equal(sum(q_st$filings_count),
               sum(m$filings_count[m$state_abb == st]))
})

test_that("required columns are present with expected types", {
  panel <- load_blinded_panel(level = "state", sample = "S2",
                              treat_def = "online_start_date", config = cfg)
  expect_true(all(c("unit_id", "state_abb", "month_date", "t",
                    "filings_count", "renters",
                    "y_log1p", "y_lograte", "y_asinh", "g") %in% names(panel)))
  expect_s3_class(panel$month_date, "Date")
  expect_type(panel$t, "integer")
  expect_equal(min(panel$t), 1L)
})

# ---------------------------------------------------------------------------
# time_agg axis (2026-08-19): month / quarter / year aggregation, plus the
# complete_periods_only rule. Motivation: covid filtering happens BEFORE
# aggregation, so covid="drop" leaves PARTIAL periods (2020Q1 = Jan+Feb only;
# annual 2020 = 2 months) whose summed counts are mechanically depressed —
# a level artifact that would masquerade as a COVID break.
# ---------------------------------------------------------------------------

test_that("time_agg='quarter' reproduces the legacy quarterly=TRUE panel", {
  q_legacy <- load_blinded_panel(level = "state", sample = "S3",
                                 treat_def = "online_start_date",
                                 covid = "keep", config = cfg, quarterly = TRUE)
  q_new <- load_blinded_panel(level = "state", sample = "S3",
                              treat_def = "online_start_date",
                              covid = "keep", config = cfg, time_agg = "quarter")
  expect_equal(as.data.frame(q_new), as.data.frame(q_legacy))
})

test_that("time_agg='year' sums 12 months per unit-year and preserves totals", {
  m <- load_blinded_panel(level = "state", sample = "S3",
                          treat_def = "online_start_date", covid = "keep",
                          config = cfg, time_agg = "month")
  y <- load_blinded_panel(level = "state", sample = "S3",
                          treat_def = "online_start_date", covid = "keep",
                          config = cfg, time_agg = "year")
  st <- m$state_abb[1]
  m_st <- m %>% dplyr::filter(state_abb == st) %>%
    dplyr::mutate(yd = floor_date(month_date, "year")) %>%
    dplyr::group_by(yd) %>%
    dplyr::summarise(fc = sum(filings_count), .groups = "drop")
  y_st <- y %>% dplyr::filter(state_abb == st) %>%
    dplyr::select(month_date, filings_count) %>% dplyr::arrange(month_date)
  joined <- dplyr::inner_join(m_st, y_st, by = c("yd" = "month_date"))
  expect_equal(joined$fc, joined$filings_count)
  expect_equal(sum(y_st$filings_count),
               sum(m$filings_count[m$state_abb == st]))
  # Every retained date is a January 1st, and t is contiguous from 1.
  expect_true(all(month(y$month_date) == 1L))
  expect_identical(sort(unique(y$t)), seq_len(dplyr::n_distinct(y$month_date)))
})

test_that("complete_periods_only drops COVID-truncated partial periods", {
  win <- cfg$covid_drop           # 2020-03-01 .. 2021-07-31
  q_all <- load_blinded_panel(level = "state", sample = "S3",
                              treat_def = "online_start_date", covid = "drop",
                              config = cfg, time_agg = "quarter")
  q_cmp <- load_blinded_panel(level = "state", sample = "S3",
                              treat_def = "online_start_date", covid = "drop",
                              config = cfg, time_agg = "quarter",
                              complete_periods_only = TRUE)
  # 2020Q1 keeps Jan+Feb and 2021Q3 keeps Aug+Sep under a bare drop ...
  expect_true(as.Date("2020-01-01") %in% q_all$month_date)
  expect_true(as.Date("2021-07-01") %in% q_all$month_date)
  # ... and both vanish once incomplete periods are removed.
  expect_false(as.Date("2020-01-01") %in% q_cmp$month_date)
  expect_false(as.Date("2021-07-01") %in% q_cmp$month_date)
  # Nothing else is touched: every retained unit-period keeps its exact count.
  # The rule applies PER unit-period, so a state whose coverage begins
  # mid-quarter loses only its own partial quarter while that same quarter
  # survives for fully-covered states — hence the join on (unit_id, period).
  b <- q_cmp %>% dplyr::arrange(unit_id, month_date)
  a <- q_all %>% dplyr::semi_join(b, by = c("unit_id", "month_date")) %>%
    dplyr::arrange(unit_id, month_date)
  expect_equal(nrow(a), nrow(b))
  expect_equal(a$filings_count, b$filings_count)
  # And the rule removed strictly more than the two calendar-wide quarters.
  expect_gt(nrow(q_all) - nrow(q_cmp), 0L)

  y_cmp <- load_blinded_panel(level = "state", sample = "S3",
                              treat_def = "online_start_date", covid = "drop",
                              config = cfg, time_agg = "year",
                              complete_periods_only = TRUE)
  # 2020 (Jan-Feb) and 2021 (Aug-Dec) are both partial under the COVID drop.
  expect_false(as.Date("2020-01-01") %in% y_cmp$month_date)
  expect_false(as.Date("2021-01-01") %in% y_cmp$month_date)
  expect_true(as.Date("2019-01-01") %in% y_cmp$month_date)
  expect_identical(attr(y_cmp, "time_agg"), "year")
  expect_true(attr(y_cmp, "n_periods_dropped_incomplete") > 0L)
})
