################################################################################
# test-inclusion-rule.R — the switcher inclusion rule (R/power/inclusion_rule.R)
################################################################################
library(lubridate)
.ir_root <- if (exists("power_repo_root", mode = "function")) power_repo_root() else "."
if (!exists("switcher_inclusion_ok", mode = "function")) {
  source(file.path(.ir_root, "R/power/inclusion_rule.R"))
}
mi <- function(d) year(d) * 12L + (month(d) - 1L)

test_that("splice_excluded_months brackets the dropped window symmetrically", {
  ex <- splice_excluded_months(c("2020-03-01", "2021-07-31"), 3L)
  expect_equal(as.character(ex), c("2019-12-01", "2020-01-01", "2020-02-01",
                                   "2021-08-01", "2021-09-01", "2021-10-01"))
  expect_length(splice_excluded_months(c("2020-03-01", "2021-07-31"), 0L), 0L)
  expect_length(splice_excluded_months(c("2020-03-01", "2021-07-31"), NA), 0L)
})

test_that("switcher_usable_horizons counts observed, non-excluded outcome months", {
  L <- mi(as.Date("2018-06-01"))
  obs <- (L - 10L):(L + 30L)                          # complete series
  u <- switcher_usable_horizons(obs, L, pmd = 6L)
  expect_true(u$baseline_ok); expect_equal(u$n_usable, 13L)
  # punch out two outcome months and exclude one more
  obs2 <- setdiff(obs, c(L + 15L, L + 16L))
  u2 <- switcher_usable_horizons(obs2, L, pmd = 6L, excluded = L + 12L)
  expect_equal(u2$n_usable, 10L)
  expect_false((L + 12L) %in% u2$usable)
  # missing baseline month -> baseline_ok FALSE, horizons still counted
  u3 <- switcher_usable_horizons(setdiff(obs, L - 3L), L, pmd = 6L)
  expect_false(u3$baseline_ok); expect_equal(u3$n_usable, 13L)
})

test_that("switcher_inclusion_ok applies the baseline AND the K floor", {
  L <- 100L; obs <- (L - 10L):(L + 30L)
  expect_true(switcher_inclusion_ok(obs, L, min_horizons = 7L))
  expect_true(switcher_inclusion_ok(obs, L, min_horizons = 13L))
  expect_false(switcher_inclusion_ok(obs, L, min_horizons = 14L))
  # series ends at L+17: 6 usable -> fails K=7, passes K=6 and NA (>=1)
  obs_short <- (L - 10L):(L + 17L)
  expect_false(switcher_inclusion_ok(obs_short, L, min_horizons = 7L))
  expect_true(switcher_inclusion_ok(obs_short, L, min_horizons = 6L))
  expect_true(switcher_inclusion_ok(obs_short, L, min_horizons = NA))
  # no baseline -> never
  expect_false(switcher_inclusion_ok((L - 2L):(L + 30L), L, min_horizons = 1L))
  # exclusions can push a switcher under the floor
  ex <- (L + 12L):(L + 18L)                             # 7 excluded of 13
  expect_false(switcher_inclusion_ok(obs, L, min_horizons = 7L, excluded = ex))
  expect_true(switcher_inclusion_ok(obs, L, min_horizons = 6L, excluded = ex))
})

# ---- 2026-09-17: the baseline is held to the same splice standard ----------
test_that("baseline_clean rejects a baseline containing an excluded month", {
  # launch at index 100, pmd 6 -> baseline 94..99; outcome 112..124
  obs <- 80:130
  excl <- c(98L, 99L)                      # two splice-adjacent baseline months
  expect_false(switcher_usable_horizons(obs, 100L, 6L, excluded = excl)$baseline_ok)
  expect_true(switcher_usable_horizons(obs, 100L, 6L, excluded = excl,
                                       baseline_clean = FALSE)$baseline_ok)
  expect_false(switcher_inclusion_ok(obs, 100L, 6L, 7L, excluded = excl))
  expect_true(switcher_inclusion_ok(obs, 100L, 6L, 7L, excluded = excl,
                                    baseline_clean = FALSE))
})

test_that("baseline_clean is inert when no excluded month falls in the baseline", {
  obs <- 80:130
  excl <- c(115L, 116L)                    # excluded OUTCOME months only
  a <- switcher_usable_horizons(obs, 100L, 6L, excluded = excl)
  b <- switcher_usable_horizons(obs, 100L, 6L, excluded = excl,
                                baseline_clean = FALSE)
  expect_identical(a, b)
  expect_true(a$baseline_ok)
  expect_equal(a$n_usable, 11L)            # 13 window months minus the 2 excluded
})

test_that("AR is the switcher the rule change removes", {
  # AR launches 2022-03; 2021-09 and 2021-10 are splice-adjacent under
  # covid_drop 2020-03..2021-07 with buffer 3.
  mi <- function(d) lubridate::year(d) * 12L + (lubridate::month(d) - 1L)
  excl <- mi(splice_excluded_months(as.Date(c("2020-03-01", "2021-07-31")), 3L))
  L <- mi(as.Date("2022-03-01"))
  obs <- c(mi(seq(as.Date("2016-01-01"), as.Date("2020-02-01"), by = "month")),
           mi(seq(as.Date("2021-08-01"), as.Date("2026-06-01"), by = "month")))
  expect_false(switcher_inclusion_ok(obs, L, 6L, 7L, excluded = excl))
  expect_true(switcher_inclusion_ok(obs, L, 6L, 7L, excluded = excl,
                                    baseline_clean = FALSE))
})
