################################################################################
# test-cs-safe-patches.R
#
# The `cs_safe_patches` flag installs patches/reg_did_rc_safe.R over the DRDID
# internal that segfaults on zero-row design matrices (see
# install_cs_safe_patches() in R/power/run_estimators.R).
#
# The flag's entire safety claim is "a flag-OFF run is bit-identical to the
# pre-flag framework, and every partial already on disk keeps its scenario id".
# The golden-id test below pins exactly that; the rest cover the installer's
# contract, including the failure mode that motivated it (an install that
# patches DRDID but not did's imports frame reports success while being inert).
################################################################################

# ---- Golden scenario ids: flag OFF must not move anything -------------------

test_that("flag-OFF scenario ids match the partials already on disk", {
  skip_if_not(file.exists("../../config/power_cheap.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_cheap.yml")
  expect_false(isTRUE(cfg$cs_safe_patches))

  grid <- expand_scenario_grid(cfg)
  # These are the filenames under output_blinded_power/cheap/partials/ as of
  # 2026-08-17. If this test fails, an identity-schema change has orphaned
  # completed multi-hour scenarios -- do not "fix" it by updating the strings.
  golden <- c("S0199769b58", "S7570c31060", "Sd9e469e5a5",
              "Sff2a24764c", "S0508e397a6")
  expect_true(all(golden %in% substr(grid$scenario_id, 1, 11)))
})

test_that("the flag is hashed only for scenarios that actually run CS", {
  skip_if_not(file.exists("../../config/power_cheap.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_cheap.yml")
  base <- expand_scenario_grid(cfg)

  # cheap runs twfe + did2s only, so flipping the guard must be a no-op for
  # every one of its ids: the guard replaces a DRDID internal reachable only
  # through did::att_gt(). Turning the flag on in power_primary.yml must not
  # orphan the completed county twfe/did2s partials.
  cfg_on <- cfg
  cfg_on$cs_safe_patches <- TRUE
  expect_identical(expand_scenario_grid(cfg_on)$scenario_id, base$scenario_id)

  # ...but a CS-bearing scenario must separate, since the guard changes what
  # CS returns on cells that previously aborted the process.
  cfg_cs <- cfg
  cfg_cs$estimators <- c("cs", "twfe")
  ids_off <- expand_scenario_grid(cfg_cs)$scenario_id
  cfg_cs$cs_safe_patches <- TRUE
  ids_on <- expand_scenario_grid(cfg_cs)$scenario_id
  expect_false(any(ids_on %in% ids_off))
})

# ---- cs_faster_mode axis -----------------------------------------------------

test_that("cs_faster_mode defaults to TRUE when a config omits it", {
  skip_if_not(file.exists("../../config/power_cheap.yml"),
              "run from repo root or tests/testthat")
  # Historical behavior must survive a config that never heard of the key.
  cfg <- read_power_config("../../config/power_cheap.yml")
  expect_true(cfg$cs_faster_mode)
  expect_true(all(expand_scenario_grid(cfg)$cs_faster_mode))
})

test_that("cs_faster_mode is hashed only when non-default AND CS is present", {
  skip_if_not(file.exists("../../config/power_primary.yml"),
              "run from repo root or tests/testthat")

  # primary runs cs -> flipping to the non-default FALSE must separate ids,
  # because faster_mode is an att_gt() argument that changes the estimate
  # itself (verified 2026-08-17: same data, materially different ATT).
  cfg <- read_power_config("../../config/power_primary.yml")
  ids_default <- expand_scenario_grid(cfg)$scenario_id
  cfg$cs_faster_mode <- FALSE
  expect_false(any(expand_scenario_grid(cfg)$scenario_id %in% ids_default))

  # cheap runs twfe/did2s only -> the key cannot touch its results, so its
  # completed partials must survive the flip untouched.
  cfg2 <- read_power_config("../../config/power_cheap.yml")
  ids2 <- expand_scenario_grid(cfg2)$scenario_id
  cfg2$cs_faster_mode <- FALSE
  expect_identical(expand_scenario_grid(cfg2)$scenario_id, ids2)
})

test_that("cs_faster_mode reaches the estimator spec", {
  skip_if_not(file.exists("../../config/power_cs_probe.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_cs_probe.yml")
  expect_false(cfg$cs_faster_mode)
  expect_true(all(!expand_scenario_grid(cfg)$cs_faster_mode))

  # .re_spec() uses modifyList(), which DELETES keys whose value is NULL --
  # that would silently pass faster_mode = NULL into att_gt().
  expect_false(.re_spec(list(cs_faster_mode = FALSE))$cs_faster_mode)
  expect_true(.re_spec(list())$cs_faster_mode)
  expect_true(.re_spec(list(cs_faster_mode = NULL))$cs_faster_mode)
})

# ---- Installer contract ------------------------------------------------------

test_that("install_cs_safe_patches() is a no-op when disabled", {
  skip_if_not(exists("install_cs_safe_patches", mode = "function"))
  before <- getOption("power.cs_safe_patches_installed")
  expect_false(install_cs_safe_patches(FALSE))
  # Must not have touched the process-level sentinel.
  expect_identical(getOption("power.cs_safe_patches_installed"), before)
})

test_that("install_cs_safe_patches() installs, is idempotent, and reaches did", {
  skip_if_not_installed("DRDID")
  skip_if_not_installed("did")
  skip_if_not(exists("install_cs_safe_patches", mode = "function"))
  root <- normalizePath("../..", mustWork = FALSE)
  skip_if_not(file.exists(file.path(root, "patches", "reg_did_rc_safe.R")))

  expect_true(install_cs_safe_patches(TRUE, root = root))
  expect_true(install_cs_safe_patches(TRUE, root = root))  # idempotent

  # The regression this guards: patching DRDID alone leaves did's imports
  # frame -- the binding compute.att_gt2() resolves under faster_mode = TRUE --
  # holding the ORIGINAL function, while the installer still reports success.
  patched_body <- body(get("reg_did_rc", envir = asNamespace("DRDID"),
                           mode = "function"))
  imports <- parent.env(asNamespace("did"))
  if (exists("reg_did_rc", envir = imports, inherits = FALSE)) {
    expect_identical(
      body(get("reg_did_rc", envir = imports, mode = "function")),
      patched_body)
  }
})

test_that("install_cs_safe_patches() refuses a signature-mismatched patch", {
  skip_if_not_installed("DRDID")
  skip_if_not(exists("install_cs_safe_patches", mode = "function"))

  # att_gt() binds this function's arguments positionally, so a DRDID upgrade
  # that changed the signature must abort the install rather than mis-bind.
  tmp_root <- file.path(tempdir(), "cs_patch_root")
  dir.create(file.path(tmp_root, "patches"), recursive = TRUE,
             showWarnings = FALSE)
  writeLines("reg_did_rc_safe <- function(y, post) NULL",
             file.path(tmp_root, "patches", "reg_did_rc_safe.R"))

  withr::with_options(list(power.cs_safe_patches_installed = NULL), {
    expect_warning(res <- install_cs_safe_patches(TRUE, root = tmp_root),
                   "signature")
    expect_false(res)
  })
})

test_that("install_cs_safe_patches() warns and fails when the patch is absent", {
  skip_if_not_installed("DRDID")
  skip_if_not(exists("install_cs_safe_patches", mode = "function"))
  empty_root <- file.path(tempdir(), "cs_patch_empty")
  dir.create(empty_root, recursive = TRUE, showWarnings = FALSE)

  withr::with_options(list(power.cs_safe_patches_installed = NULL), {
    expect_warning(res <- install_cs_safe_patches(TRUE, root = empty_root),
                   "not found")
    expect_false(res)
  })
})
