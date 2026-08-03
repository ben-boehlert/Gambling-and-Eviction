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
