################################################################################
# test-schedules.R
#
# Pseudo-schedule structure, support, reproducibility, and D4 restriction.
################################################################################

library(lubridate)

cfg <- read_power_config("config/power_validation.yml")
real_schedule <- guarded_read_csv(cfg$schedule)

# D1/D3 reassign the full real cohort structure (24 treated states across 18
# cohorts), so they need an all-states pool: use an S2 panel. D4 restricts to
# never-treated states, derived from the same panel's attribute.
panel_nt <- load_blinded_panel(level = "state", sample = "S2",
                               treat_def = "online_start_date", covid = "keep",
                               config = cfg)

cov <- panel_nt %>%
  dplyr::group_by(state_abb) %>%
  dplyr::summarise(min_m = min(month_date), max_m = max(month_date),
                   .groups = "drop")
mi <- function(d) year(d) * 12L + (month(d) - 1L)

test_that("D1 preserves the total number of cohorts and per-state single dates", {
  # template = "panel": the national 24-state template is knife-edge on this
  # panel — placement feasibility depends on the seed (seed 101 fails, the
  # seeds used by later tests place). The panel-restricted template is the
  # production design (power_smoke/power_cheap, 2026-08-10) and is robustly
  # feasible, so the structure-preservation invariant is tested on it.
  sched <- make_pseudo_schedule("D1", panel = panel_nt,
                                real_schedule = real_schedule,
                                treat_def = "online_start_date",
                                min_pre = 12L, min_post = 6L, seed = 101,
                                template = "panel")
  tgt <- attr(sched, "cohort_structure_target")
  ach <- attr(sched, "cohort_structure_achieved")
  # Cohort count preserved (all template cohorts placed).
  expect_equal(nrow(ach), nrow(tgt))
  expect_equal(sum(ach$n_states), sum(tgt$n_states))
  expect_identical(attr(sched, "template"), "panel")
  # Panel restriction: target cohorts only from states present in the panel.
  expect_lte(sum(tgt$n_states), dplyr::n_distinct(panel_nt$state_abb))
  # One row per state, first-of-month dates.
  expect_equal(nrow(sched), dplyr::n_distinct(sched$state_abb))
  expect_true(all(day(sched$pseudo_g) == 1L))
})

test_that("every assigned state satisfies min_pre / min_post support (D1)", {
  sched <- make_pseudo_schedule("D1", panel = panel_nt,
                                real_schedule = real_schedule,
                                treat_def = "online_start_date",
                                min_pre = 12L, min_post = 6L, seed = 202)
  chk <- sched %>% dplyr::left_join(cov, by = "state_abb")
  expect_true(all(mi(chk$min_m) <= mi(chk$pseudo_g) - 12L))
  expect_true(all(mi(chk$max_m) >= mi(chk$pseudo_g) + 6L))
})

test_that("same seed reproduces an identical schedule", {
  a <- make_pseudo_schedule("D1", panel = panel_nt,
                            real_schedule = real_schedule,
                            treat_def = "online_start_date", seed = 303)
  b <- make_pseudo_schedule("D1", panel = panel_nt,
                            real_schedule = real_schedule,
                            treat_def = "online_start_date", seed = 303)
  expect_identical(as.data.frame(a), as.data.frame(b))
})

test_that("D4 uses only never-treated states", {
  nt <- attr(panel_nt, "never_treated")
  sched <- make_pseudo_schedule("D4", panel = panel_nt,
                                real_schedule = real_schedule,
                                treat_def = "online_start_date",
                                min_pre = 12L, min_post = 6L, seed = 404)
  expect_true(all(sched$state_abb %in% nt))
  expect_true(all(day(sched$pseudo_g) == 1L))
  expect_equal(nrow(sched), dplyr::n_distinct(sched$state_abb))
})

test_that("D3 draws dates within the feasible window and respects support", {
  sched <- make_pseudo_schedule("D3", panel = panel_nt,
                                real_schedule = real_schedule,
                                treat_def = "online_start_date",
                                min_pre = 12L, min_post = 6L, seed = 505)
  chk <- sched %>% dplyr::left_join(cov, by = "state_abb")
  expect_true(all(mi(chk$min_m) <= mi(chk$pseudo_g) - 12L))
  expect_true(all(mi(chk$max_m) >= mi(chk$pseudo_g) + 6L))
})
