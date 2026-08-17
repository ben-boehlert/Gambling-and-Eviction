################################################################################
# test-cs-cv3.R
#
# CV3 cluster-jackknife inference arm for CSDID (Karim, Nielsen, MacKinnon &
# Webb 2026). Three things are verified:
#
#   1. the arm is OFF by default (production runs must be unaffected);
#   2. when enabled it emits a schema-conformant, converged "jack" row;
#   3. our .re_cs_cv3() reproduces didjack::didjack() to numerical tolerance on
#      a fully-identified panel — the case where the authors' package runs.
#
# (3) is the load-bearing test. We do NOT use didjack in production because its
# internal did::aggte() call omits na.rm = TRUE and therefore dies on the first
# replicate on any design with non-identifiable (g,t) cells (ours has 30-43%).
# This test pins our re-implementation to theirs on common ground, so the
# deviation is confined to NA handling and not to the estimator itself.
################################################################################

.re_root <- if (exists("power_repo_root", mode = "function")) power_repo_root() else "."
if (!exists("run_estimator", mode = "function")) {
  source(file.path(.re_root, "R/power/run_estimators.R"))
}

# Fully-identified toy panel: balanced, 2 treated cohorts + never-treated, and
# enough pre/post span that every (g,t) cell is estimable (so aggte works even
# WITHOUT na.rm, which is what didjack requires).
build_cv3_toy <- function(seed = 424242L, n_states = 12L, n_months = 24L,
                          treat = c(S02 = 10L, S03 = 10L, S05 = 16L, S06 = 16L),
                          noise_sd = 0.2) {
  set.seed(seed)
  states <- sprintf("S%02d", seq_len(n_states))
  grid <- expand.grid(state_abb = states, t = seq_len(n_months),
                      stringsAsFactors = FALSE)
  sfe <- stats::setNames(stats::rnorm(n_states), states)
  tfe <- stats::setNames(stats::rnorm(n_months, 0, 0.3),
                         as.character(seq_len(n_months)))
  grid$y <- 2 + sfe[grid$state_abb] + tfe[as.character(grid$t)] +
    stats::rnorm(nrow(grid), 0, noise_sd)
  grid$g <- as.integer(ifelse(grid$state_abb %in% names(treat),
                              treat[grid$state_abb], 0L))
  grid$id <- as.integer(as.factor(grid$state_abb))
  grid[, c("id", "t", "g", "y", "state_abb")]
}

cv3_fit_on <- function(d) {
  did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
              xformla = ~1, data = d, panel = TRUE,
              allow_unbalanced_panel = TRUE, faster_mode = FALSE,
              clustervars = "state_abb", est_method = "reg",
              base_period = "varying", anticipation = 0L,
              control_group = "notyettreated", bstrap = FALSE,
              cband = FALSE, print_details = FALSE)
}

test_that("cs_jack is off by default and on when requested", {
  skip_if_not_installed("did")
  toy <- build_cv3_toy()
  panel_sim <- data.frame(
    unit_id = toy$state_abb, state_abb = toy$state_abb, t = toy$t,
    month_date = as.Date("2016-01-01") + months(toy$t - 1L),
    y_sim = toy$y,
    pseudo_g = as.Date(ifelse(toy$g == 0L, NA,
                              as.character(as.Date("2016-01-01") +
                                             months(toy$g - 1L)))),
    stringsAsFactors = FALSE
  )

  off <- run_estimator(panel_sim, "cs", spec = list(cs_faster_mode = FALSE))
  expect_false("jack" %in% off$inference)

  on <- run_estimator(panel_sim, "cs",
                      spec = list(cs_jack = TRUE, cs_faster_mode = FALSE))
  jr <- on[on$inference == "jack", ]
  expect_equal(nrow(jr), 1L)
  expect_true(jr$converged)
  expect_true(is.finite(jr$se) && jr$se > 0)
  expect_true(is.finite(jr$p) && jr$p >= 0 && jr$p <= 1)
  expect_true(jr$ci_lo < jr$ci_hi)
  expect_identical(names(on), .RE_SCHEMA)
})

test_that(".re_cs_cv3 reproduces didjack::didjack on an identified panel", {
  skip_if_not_installed("did")
  skip_if_not_installed("didjack")

  dat <- build_cv3_toy()
  # att_gt is called INLINE (not via cv3_fit_on) on purpose: didjack captures
  # the `data` argument as an unevaluated symbol and re-evaluates it in
  # parent.frame(). Called through a helper, that symbol is the helper's local
  # arg name and resolution fails ("object 'd' not found"). Binding the frame's
  # variable to the literal name `dat` is what makes the reference call work.
  fit <- suppressMessages(suppressWarnings(
    did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                xformla = ~1, data = dat, panel = TRUE,
                allow_unbalanced_panel = TRUE, faster_mode = FALSE,
                clustervars = "state_abb", est_method = "reg",
                base_period = "varying", anticipation = 0L,
                control_group = "notyettreated", bstrap = FALSE,
                cband = FALSE, print_details = FALSE)))
  ag  <- suppressMessages(suppressWarnings(did::aggte(fit, type = "simple")))

  jk_ref <- NULL
  invisible(utils::capture.output(suppressMessages(suppressWarnings(
    jk_ref <- didjack::didjack(ag)))))

  ours <- .re_cs_cv3(dat, function(d) cv3_fit_on(d),
                     att_full = as.numeric(ag$overall.att), alpha = 0.05)

  expect_true(ours$ok)
  expect_equal(ours$reps, jk_ref$reps)
  expect_equal(ours$df, jk_ref$cv3df)
  expect_equal(ours$se, jk_ref$cv3se, tolerance = 1e-8)
  expect_equal(ours$p, jk_ref$cv3p, tolerance = 1e-8)
  expect_equal(ours$ci_lo, jk_ref$cv3lci, tolerance = 1e-8)
  expect_equal(ours$ci_hi, jk_ref$cv3uci, tolerance = 1e-8)
})

test_that("cv3 reports rather than hides failed replicates", {
  skip_if_not_installed("did")
  dat <- build_cv3_toy()
  # A fit function that fails on one specific delete-one subset.
  n_states <- length(unique(dat$state_abb))
  flaky <- function(d) {
    if (!("S01" %in% d$state_abb)) stop("synthetic replicate failure")
    cv3_fit_on(d)
  }
  ag <- suppressMessages(suppressWarnings(
    did::aggte(cv3_fit_on(dat), type = "simple", na.rm = TRUE)))
  out <- .re_cs_cv3(dat, flaky, as.numeric(ag$overall.att), 0.05)

  expect_true(out$ok)
  expect_equal(out$n_failed, 1L)
  expect_equal(out$reps, n_states - 1L)
  expect_match(out$msg, "cv3 used")
})
