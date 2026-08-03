################################################################################
# test-blindness.R
#
# The loader never returns treated/anticipation rows (independently re-derived),
# and the forbidden-path guards behave. State level tested in full; county level
# on a lighter check for speed.
################################################################################

library(lubridate)

cfg <- read_power_config("config/power_validation.yml")
sched <- .load_gambling_schedule(cfg$schedule, "online_start_date")

# Independent re-derivation of the cutoff violation (does NOT call assert_blinded).
independent_violation_rows <- function(panel, sched, anticipation, universal_cutoff,
                                       sample_id) {
  chk <- panel %>%
    dplyr::left_join(dplyr::distinct(sched, state_abb, g_first), by = "state_abb") %>%
    dplyr::mutate(cutoff = g_first %m-% months(anticipation))
  bad_treat <- chk %>%
    dplyr::filter(!is.na(g_first) & month_date >= cutoff)
  if (identical(sample_id, "S1")) {
    bad_uc <- chk %>% dplyr::filter(month_date > universal_cutoff)
    bad_treat <- dplyr::bind_rows(bad_treat, bad_uc)
  }
  bad_treat
}

test_that("state loader returns no treated/anticipation rows (all samples)", {
  for (s in c("S1", "S2", "S3")) {
    panel <- load_blinded_panel(level = "state", treat_def = "online_start_date",
                                anticipation = 6L, sample = s, covid = "drop",
                                config = cfg)
    bad <- independent_violation_rows(panel, sched, 6L,
                                      cfg$universal_cutoff, s)
    expect_equal(nrow(bad), 0L,
                 info = paste("state sample", s, "had", nrow(bad), "bad rows"))
    expect_true(all(panel$g == 0))
    expect_gt(nrow(panel), 0L)
  }
})

test_that("county loader returns no treated/anticipation rows (S2 subsample)", {
  panel <- load_blinded_panel(level = "county", treat_def = "online_start_date",
                              anticipation = 6L, sample = "S2", covid = "drop",
                              config = cfg)
  # Re-derive independently at the state-month level (dedup for speed).
  sm <- dplyr::distinct(panel, state_abb, month_date)
  bad <- independent_violation_rows(sm, sched, 6L, cfg$universal_cutoff, "S2")
  expect_equal(nrow(bad), 0L)
  expect_true(all(panel$g == 0))
})

test_that("forbidden-path guard blocks output/, figures/, and result docs", {
  expect_error(assert_no_forbidden_paths("output/x.csv"), "forbidden|prohibited")
  expect_error(assert_no_forbidden_paths("figures/a.png"), "forbidden|prohibited")
  expect_error(assert_no_forbidden_paths("CLAUDE.md"), "result-bearing")
  expect_error(assert_no_forbidden_paths("docs/START_HERE.md"), "result-bearing")
  # Framework's own output root must NOT be blocked.
  expect_true(assert_no_forbidden_paths("output_blinded_power/results.csv"))
  # A normal data file is fine.
  expect_true(assert_no_forbidden_paths("data/raw/some.csv"))
})

test_that("blinded_output_path rejects escapes and allows in-root writes", {
  expect_error(blinded_output_path("../output/x.csv", create = FALSE), "escapes")
  p <- blinded_output_path("sub", "results.csv", create = FALSE)
  expect_true(grepl("output_blinded_power/sub/results.csv$", p))
})
