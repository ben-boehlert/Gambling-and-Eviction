################################################################################
# analysis/diagnostics/validate_shift_sufficiency.R
#
# Validates a computational shortcut for the blinded power-simulation
# framework (R/power/): that a rep's delta=0 estimate, shifted by that rep's
# imposed truth at delta > 0, reproduces the power curve actually obtained by
# re-running the estimator at every delta. If this holds (to a documented
# tolerance), future power runs only need the delta=0 arm — the entire delta
# grid becomes a post-hoc shift of one estimation pass.
#
# REVISION (coder-critic round 2, 72/100 -> addresses 6 required fixes):
#   1. LOADING DECOMPOSITION. Shifting by raw truth assumes a loading L = 1
#      (att(delta) - att(0) == truth, exactly). This script now ALSO
#      estimates L_hat per (scenario_id, estimator, inference) by OLS-
#      through-the-origin of the OBSERVED shift (att(delta) - att(0)) on
#      truth, pooled across paired reps and delta > 0 grid points, and
#      reports a SECOND shifted-power series using L_hat * truth. Comparing
#      the L=1 residual to the L_hat residual separates "the L=1 assumption
#      is wrong for this estimator/shape" from "genuine stochastic-
#      mechanism/nonlinearity error that no linear loading can fix."
#   2. PAIRED-SAMPLE ACTUAL. power_actual_paired is computed on the EXACT
#      same paired, usable rep set as power_shifted, so the discrepancy
#      columns are never contaminated by denominator mismatches. The
#      full-converged-sample quantity from summarize_oc() is kept alongside
#      as power_actual_full (the framework's real production statistic).
#   3. WILD RULE. "Actual"/"paired-actual" rejection is ALWAYS p <= alpha
#      (summarize_oc's own convention, and what run_estimators.R's stored
#      `p` already encodes for wild rows via fwildclusterboot::pval()) —
#      never CI membership. Only the SHIFTED counterfactual for wild
#      inference uses CI-shift (there is no bootstrap redraw to recompute a
#      shifted p from). A row-level check quantifies how often p0 <= alpha
#      disagrees with "0 outside [ci_lo0, ci_hi0]" at the SAME baseline row
#      — this disagreement rate is the wild arm's intrinsic validation
#      resolution (finite-B bootstrap-redraw noise), not shift error, and
#      self-check 1 is scoped to pure shift ARITHMETIC (not to this
#      known, separately-quantified duality gap) so it doesn't conflate the
#      two.
#   4. NA-TRUTH GUARD. Pairs with NA truth are dropped from BOTH the shifted
#      and the paired-actual numerator AND denominator (matching
#      summarize_oc's na.rm = TRUE convention), with drop counts reported
#      per scenario (data has zero such rows currently — this is a
#      defensive guard, exercised and confirmed at n = 0).
#   5. DECISION-RELEVANT OUTPUTS. The delta=0 size gate is, by construction,
#      EXACT for analytic/boot_t inference and bounded by the wild arm's
#      duality-noise floor for wild inference — stated explicitly (console +
#      discrepancy_summary.csv column). MDE (80% power crossing, via the
#      framework's own compute_mde()) is reported for actual vs.
#      shifted-L1 vs. shifted-L_hat, since MDE — not max|discrepancy| over
#      the delta grid — is the statistic that drives estimator/level
#      selection in the PAP.
#   6. MINOR: rows are de-duplicated on the FULL key (scenario_id,
#      estimator, inference, estimand, event_time, rep, delta) — covers
#      both delta=0 and delta>0 (defends against resume-appended partials);
#      df recovery mirrors run_estimators.R's max(1L, df_cluster) guard;
#      joins on event_time pass na_matches = "na" explicitly; the dead
#      count(..., name_unused = FALSE) hack was removed.
#
# ADVISORY REVISION (round-2 re-review, 83/100 -> passes; 2 additive items,
# no re-review to follow):
#   A1. PER-DELTA LOADING. The pooled L_hat (FIX 1) is a truth^2-weighted
#       through-origin slope, so it is dominated by the largest delta grid
#       points (delta=0.20 carries 16x the weight of delta=0.05). §7b adds
#       loading_by_delta.csv — the same through-origin-slope formula
#       restricted to a single delta — so a production implementation can
#       fit L_hat on the power-relevant range instead of the whole grid.
#   A2. PAIRED mde_actual. §16's MDE comparison previously compared
#       paired-sample mde_shifted_* against a FULL-sample mde_actual — the
#       exact denominator mismatch FIX 2 eliminated everywhere else.
#       mde_actual is now computed from power_actual_paired (paired sample,
#       matching mde_shifted_l1/lhat); the full-sample quantity is kept as
#       mde_actual_full for reference.
#   A3. COVERAGE NOTE. MDE is defined (curve crosses 80% power within the
#       delta grid) for only 3 of 15 estimator x inference cells — the
#       county headline scenario. Every state-panel ramp/delayed/step cell
#       returns "never_crosses_target" because those power curves top out
#       around 0.55-0.74 within delta in [0, 0.20]. Stated explicitly below
#       so the MDE table is not read as covering the at-risk (ramp/delayed)
#       shapes — those are only characterized by the discrepancy_l1/lhat
#       columns in shift_vs_actual_power.csv / discrepancy_summary.csv.
#
# Method: see inline section comments for the exact conventions mirrored
# from R/power/summarize_operating_characteristics.R and
# R/power/run_estimators.R.
#
# Inputs:  output_blinded_power/cheap/partials/*.csv (per-rep result CSVs;
#          five completed/partial "cheap" scenarios as of 2026-08-17).
# Outputs: output/shift_validation/shift_vs_actual_power.csv
#          output/shift_validation/discrepancy_summary.csv
#          output/shift_validation/mde_comparison.csv
#          output/shift_validation/loading_by_delta.csv
#          output/shift_validation/shift_vs_actual.png
#
# Working directory assumed to be the repository root. Does not modify any
# existing file.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(ggplot2)
  library(tibble)
  library(rlang)
})

theme_set(theme_minimal())

if (!file.exists("power_simulation_cs.R")) {
  stop("validate_shift_sufficiency.R must be run from the repository root ",
       "(power_simulation_cs.R not found in the working directory).",
       call. = FALSE)
}

# Reuses summarize_oc()'s rejection rule AND compute_mde()'s MDE-crossing
# convention verbatim (per brief). Also sources R/power/config.R (guarded,
# defines power_paths()/read_power_config() only — no config file is read at
# source time).
source("R/power/summarize_operating_characteristics.R")

################################################################################
# 1. Constants
################################################################################

# Overridable so the same harness can validate any run's partials (the CS probe
# under output_blinded_power/cs_probe/partials, a primary run, etc.) without
# editing this file. Defaults reproduce the original cheap-run analysis.
INPUT_DIR  <- Sys.getenv("SHIFT_INPUT_DIR",
                         "output_blinded_power/deprecated/cheap/partials")
OUTPUT_DIR <- Sys.getenv("SHIFT_OUTPUT_DIR", "output/shift_validation")
# Created HERE, not next to the final writes: loading_by_delta.csv is written
# well before that point, so a fresh OUTPUT_DIR aborted the run partway. Latent
# until SHIFT_OUTPUT_DIR made the directory something other than the one the
# first run had already created.
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Matches run_estimators.R's .re_spec() default alpha and summarize_oc()'s
# sig_alpha default; the headline significance level for the power curves.
ALPHA <- 0.05

# 80% power crossing — the framework's own MDE convention (compute_mde()).
MDE_POWER_TARGET <- 0.80

# Self-check-1 tolerance for "the shift arithmetic reduces to an exact
# identity at zero shift" (floating-point, not MC, discrepancy).
SELF_CHECK1_TOL <- 1e-9

# The exactness benchmark (self-check 2) is whichever scenario injects a
# deterministic, in-span constant effect: no injection noise and a shape the
# estimated model spans, so an estimator linear in the outcome must shift
# EXACTLY. Identified from the data's own mechanism/shape columns rather than a
# hardcoded scenario id, so the harness works on any run's partials (the id is
# a content hash and differs per config).
BENCHMARK_MECHANISM <- "deterministic"
BENCHMARK_SHAPE     <- "step"

# ---------------------------------------------------------------------------
# Inference-type dispatch (recovered from run_estimators.R, not guessed):
#
#   "wild"              : fwildclusterboot CI (E2/twfe). No stored bootstrap
#                          redraw to recompute a shifted p from; shift both
#                          CI bounds by the imposed effect and reject iff 0
#                          is outside the shifted interval. "Actual"
#                          rejection for wild rows is STILL p <= alpha
#                          (§5/FIX 3) — the CI-shift rule is used only for
#                          the shifted counterfactual, never for "actual".
#   "analytic" / "boot_t": both call the SAME .re_tp(att, se, df) helper with
#                          df = df_cluster = n_treated_clusters +
#                          n_control_clusters - 1 (computed once per
#                          run_estimator() call from cl$n_total). Verified
#                          numerically (pre-code audit) to exactly reproduce
#                          the stored p and CI to floating-point precision on
#                          every analytic row in this data (max
#                          |p_recomputed - p_stored| < 6e-16), so df is
#                          recovered ANALYTICALLY, not by inverting p0
#                          against |att0/se0|.
#   "boot" (CS genuine   : p/crit come from an empirical multiplier-bootstrap
#    bootstrap) / "jack"   distribution (did:::mboot) or a delete-one cluster
#    (CS CV3)              jackknife SE with df = reps - 1 (reps = number of
#                          successful jackknife refits) — NEITHER quantity is
#                          reconstructable from the columns stored in the
#                          per-rep CSVs. These arms are EXCLUDED from the
#                          shift check with an explicit warning rather than
#                          silently mis-applying the t/df formula. Not
#                          present in the "cheap" data (only twfe
#                          analytic/wild and did2s analytic occur), so this
#                          branch is currently a no-op safeguard.
# ---------------------------------------------------------------------------
TSTAT_INFERENCE <- c("analytic", "boot_t")
CI_SHIFT_INFERENCE <- c("wild")

################################################################################
# 2. Load, stack, and de-duplicate per-rep result CSVs
################################################################################

result_files <- list.files(INPUT_DIR, pattern = "[.]csv$", full.names = TRUE)
if (length(result_files) == 0L) {
  stop("No result CSVs found in ", INPUT_DIR, call. = FALSE)
}
message(sprintf("Found %d result file(s) in %s.", length(result_files),
                 INPUT_DIR))

# Explicit column types: guards against readr guessing error_msg as logical
# when a file has zero non-NA error messages (would break bind_rows across
# files with mixed types).
.result_col_types <- cols(
  estimator            = col_character(),
  inference             = col_character(),
  estimand              = col_character(),
  event_time            = col_integer(),
  att                    = col_double(),
  se                     = col_double(),
  p                      = col_double(),
  ci_lo                  = col_double(),
  ci_hi                  = col_double(),
  n_treated_clusters     = col_integer(),
  n_control_clusters     = col_integer(),
  converged              = col_logical(),
  error_msg              = col_character(),
  runtime_s              = col_double(),
  truth                  = col_double(),
  scenario_id            = col_character(),
  scenario_index         = col_integer(),
  name                   = col_character(),
  level                  = col_character(),
  sample                 = col_character(),
  covid                  = col_character(),
  treat_def              = col_character(),
  design                 = col_character(),
  mechanism              = col_character(),
  shape                  = col_character(),
  outcome                = col_character(),
  est_anticipation       = col_integer(),
  loader_anticipation     = col_integer(),
  control_group           = col_character(),
  quarterly                = col_logical(),
  template                  = col_character(),
  rep                       = col_integer(),
  delta                     = col_double(),
  seed_rep                  = col_double()
)

results <- purrr::map_dfr(
  result_files,
  \(f) readr::read_csv(f, col_types = .result_col_types, progress = FALSE)
)
results <- results |> mutate(converged = !is.na(converged) & converged)

# FIX 6: de-duplicate on the FULL row key — covers BOTH the delta=0 and
# delta>0 sides (resume-appended partials can duplicate a (rep, delta) pair
# for a given estimator/inference; an undetected duplicate silently
# double-weights that pair in every downstream join and mean()). Keeps the
# first occurrence; reports how many rows were removed (0 in this data as of
# 2026-08-17 — a defensive guard, not a fix to an observed problem).
full_row_key <- c("scenario_id", "estimator", "inference", "estimand",
                   "event_time", "rep", "delta")
n_before_dedup <- nrow(results)
results <- results |> distinct(across(all_of(full_row_key)), .keep_all = TRUE)
n_dupes_removed <- n_before_dedup - nrow(results)
message(sprintf(paste0(
  "Removed %d duplicate row(s) on the full key (scenario_id, estimator, ",
  "inference, estimand, event_time, rep, delta)."), n_dupes_removed))

n_scenarios <- dplyr::n_distinct(results$scenario_id)
message(sprintf("Stacked %d row(s) across %d scenario(s).",
                 nrow(results), n_scenarios))

# Scenario metadata lookup, used throughout for readable labels. "name"
# alone is NOT a unique scenario label in this data — the two count_nb
# "dynamics" scenarios (delayed- and ramp-shape) share name ==
# "state_nb_dynamics" and differ only in `shape`.
scenario_meta <- results |>
  distinct(scenario_id, name, mechanism, shape) |>
  mutate(scenario_label = paste0(name, " (", shape, ")"))
stopifnot(!anyDuplicated(scenario_meta$scenario_id))

################################################################################
# 3. Self-check 3: non-convergence / failure rows dropped, per scenario
################################################################################

dropped_by_scenario <- results |>
  group_by(scenario_id, name) |>
  summarise(
    n_rows      = dplyr::n(),
    n_dropped   = sum(!converged),
    pct_dropped = round(100 * mean(!converged), 2),
    .groups     = "drop"
  ) |>
  arrange(desc(pct_dropped))

message("\nSelf-check 3 — rows dropped for non-convergence/failure, by ",
        "scenario:")
print(dropped_by_scenario, n = Inf)

################################################################################
# 4. Exclude inference types this script cannot validate (defensive; a no-op
#    on the current "cheap" data, which contains only analytic/wild rows)
################################################################################

supported_inference <- c(TSTAT_INFERENCE, CI_SHIFT_INFERENCE)
unsupported <- setdiff(unique(results$inference), supported_inference)
if (length(unsupported) > 0L) {
  n_excluded <- sum(results$inference %in% unsupported)
  message(sprintf(
    paste0("\nWARNING: excluding %d row(s) with inference type(s) [%s] — ",
           "neither the CS genuine-bootstrap p-value nor the CV3 jackknife ",
           "df (= reps - 1) can be reconstructed from the stored per-rep ",
           "columns (see JUDGMENT CALLS comment block at top of script)."),
    n_excluded, paste(unsupported, collapse = ", ")))
}
supported_results <- results |>
  filter(.data$inference %in% supported_inference)

################################################################################
# 5. Actual power (FULL converged sample): summarize_oc()'s rejection rule,
#    reused verbatim. This is the framework's real production statistic —
#    kept as power_actual_full for reference/decision-relevance (§5a below),
#    separately from the paired-sample actual computed in §8 (FIX 2).
################################################################################

oc <- summarize_oc(supported_results, alpha_vec = ALPHA, sig_alpha = ALPHA)
reject_col <- .reject_col(ALPHA)
stopifnot(reject_col %in% names(oc))
oc$power_actual_full <- oc[[reject_col]]

actual_power_full <- oc |>
  select(scenario_id, estimator, inference, estimand, event_time, delta,
         power_actual_full, n_reps_actual_full = n_reps,
         n_converged_actual_full = n_converged)

################################################################################
# 6. Build the delta=0 baseline and the (rep, delta) pairs
################################################################################

join_keys <- c("scenario_id", "estimator", "inference", "estimand",
               "event_time", "rep")

baseline <- supported_results |>
  filter(delta == 0) |>
  select(all_of(join_keys),
         att0 = att, se0 = se, p0 = p, ci_lo0 = ci_lo, ci_hi0 = ci_hi,
         converged0 = converged,
         n_treated_clusters0 = n_treated_clusters,
         n_control_clusters0 = n_control_clusters)
stopifnot(!anyDuplicated(baseline[join_keys]))  # redundant post-dedup check

# FIX 6: na_matches = "na" made explicit (event_time is NA for every row in
# this "simple"-estimand data; explicit rather than relying on the dplyr
# default so the NA-matching behavior on the join key is documented intent).
pairs_raw <- supported_results |>
  select(scenario_id, name, mechanism, shape, estimator, inference, estimand,
         event_time, rep, delta, truth, converged,
         att_own = att, p_own = p) |>
  inner_join(baseline, by = join_keys, na_matches = "na") |>
  filter(converged, converged0)

# DATA QUIRK (contradicts the brief's implicit "converged == usable"
# assumption): fwildclusterboot::boottest() can return a finite p-value
# (pval()) while confint() fails on the SAME call, leaving converged == TRUE
# (which only checks is.finite(p_w) — see .re_twfe in run_estimators.R) but
# ci_lo/ci_hi == NA. Observed on ~1.4% of wild-inference baseline rows.
baseline_usable <- if_else(
  pairs_raw$inference %in% CI_SHIFT_INFERENCE,
  is.finite(pairs_raw$ci_lo0) & is.finite(pairs_raw$ci_hi0),
  is.finite(pairs_raw$att0) & is.finite(pairs_raw$se0) &
    pairs_raw$se0 > 0 & !is.na(pairs_raw$n_treated_clusters0) &
    !is.na(pairs_raw$n_control_clusters0)
)

# FIX 4: NA-truth guard. Dropped from BOTH numerator and denominator of
# every downstream cell (power_shifted_* AND power_actual_paired), matching
# summarize_oc's na.rm = TRUE convention. n = 0 in this data as of
# 2026-08-17 — exercised and confirmed, not merely asserted.
truth_usable <- !is.na(pairs_raw$truth)

# FIX 3 corollary: the paired-ACTUAL rejection (§8) needs only p_own finite,
# which `converged` already guarantees for every supported inference type
# (wild's own converged flag literally IS is.finite(p_w); analytic/boot_t
# converged requires finite att & se, which makes the t-based p deterministic
# and finite) — asserted, not silently trusted.
stopifnot(all(is.finite(pairs_raw$p_own)))

usable <- baseline_usable & truth_usable
n_unusable <- sum(!usable)
if (n_unusable > 0L) {
  drop_summary <- pairs_raw |>
    mutate(baseline_usable = baseline_usable, truth_usable = truth_usable) |>
    filter(!baseline_usable | !truth_usable) |>
    mutate(reason = case_when(
      !baseline_usable & !truth_usable ~ "baseline_unusable_and_truth_na",
      !baseline_usable ~ "baseline_unusable",
      TRUE ~ "truth_na"
    )) |>
    count(scenario_id, name, estimator, inference, reason)
  message(sprintf(paste0(
    "\nNOTE: excluding %d paired row(s) (FIX 2/4) — see reason breakdown ",
    "below. 'baseline_unusable' = delta=0 row converged == TRUE but has a ",
    "non-finite value needed to compute the shift (wild-CI NA quirk above); ",
    "'truth_na' = imposed truth missing for that (rep, delta)."),
    n_unusable))
  print(drop_summary, n = Inf)
}
pairs <- pairs_raw |> filter(usable)
rm(pairs_raw)

stopifnot(
  all(is.finite(pairs$att0)), all(is.finite(pairs$se0)),
  all(pairs$se0 > 0), all(!is.na(pairs$truth)),
  all(!(pairs$inference %in% CI_SHIFT_INFERENCE) |
        (is.finite(pairs$ci_lo0) & is.finite(pairs$ci_hi0)))
)

################################################################################
# 7. FIX 1 — Loading decomposition: estimate L_hat per (scenario_id,
#    estimator, inference) via OLS THROUGH THE ORIGIN of the observed shift
#    (att_own - att0) on truth, pooled across all paired reps and delta > 0
#    grid points. delta == 0 pairs are excluded from the regression — the
#    shift is identically (0, 0) there for ANY loading, so they carry no
#    information about the slope.
################################################################################

loading_tbl <- pairs |>
  filter(delta > 0) |>
  mutate(observed_shift = att_own - att0) |>
  group_by(scenario_id, estimator, inference) |>
  summarise(
    l_hat       = if_else(sum(truth^2) > 0,
                           sum(observed_shift * truth) / sum(truth^2),
                           NA_real_),
    n_obs_l_hat = dplyr::n(),
    .groups     = "drop"
  )

pairs <- pairs |>
  left_join(loading_tbl, by = c("scenario_id", "estimator", "inference"))
stopifnot(!anyNA(pairs$n_obs_l_hat))  # every group had >= 1 delta>0 pair

message("\n=== FIX 1: fitted loading L_hat per (scenario, estimator, ",
        "inference) ===")
print(loading_tbl |>
        left_join(scenario_meta |> select(scenario_id, scenario_label),
                  by = "scenario_id") |>
        select(scenario_label, estimator, inference, l_hat, n_obs_l_hat) |>
        arrange(scenario_label, estimator, inference),
      n = Inf)

################################################################################
# 7b. ADVISORY 1 (round-2 re-review): per-delta loading diagnostic. The
#     pooled L_hat above is a single truth^2-weighted slope across the WHOLE
#     delta grid, so it is dominated by the largest deltas (delta=0.20 has
#     16x the truth^2-weight of delta=0.05 for a linear-in-delta truth
#     schedule). loading_by_delta.csv reports the SAME through-origin-slope
#     formula restricted to a single delta, making that weighting visible
#     and letting a production implementation fit L_hat on the
#     power-relevant range instead of the whole grid.
################################################################################

loading_by_delta <- pairs |>
  filter(delta > 0) |>
  mutate(observed_shift = att_own - att0) |>
  group_by(scenario_id, estimator, inference, delta) |>
  summarise(
    l_hat_delta = if_else(sum(truth^2) > 0,
                           sum(observed_shift * truth) / sum(truth^2),
                           NA_real_),
    n_obs       = dplyr::n(),
    .groups     = "drop"
  ) |>
  left_join(scenario_meta, by = "scenario_id") |>
  select(scenario_id, scenario_label, mechanism, shape, estimator, inference,
         delta, l_hat_delta, n_obs) |>
  arrange(scenario_label, estimator, inference, delta)

readr::write_csv(loading_by_delta,
                  file.path(OUTPUT_DIR, "loading_by_delta.csv"))

# Headline scenario by NAME, not by content hash: ids differ per config, and a
# run without that block (e.g. the state-only CS probe) should degrade to
# reporting every scenario rather than printing an empty table.
.headline_name <- Sys.getenv("SHIFT_HEADLINE_NAME", "headline_county_nb_step")
# scenario_label is paste0(name, " (", shape, ")"), so the block name is its
# prefix — loading_by_delta does not carry a bare `name` column.
.headline_rows <- loading_by_delta |>
  filter(startsWith(scenario_label, .headline_name))
if (nrow(.headline_rows) == 0L) {
  message("\n=== ADVISORY 1: per-delta loading L_hat_delta (no '",
          .headline_name, "' block in this run — showing all scenarios) ===")
  .headline_rows <- loading_by_delta
} else {
  message("\n=== ADVISORY 1: per-delta loading L_hat_delta, headline ('",
          .headline_name, "') ===")
}
print(.headline_rows |>
        select(scenario_label, estimator, inference, delta, l_hat_delta,
               n_obs), n = Inf)

################################################################################
# 8. Shift-and-reject: BOTH the L=1 (raw truth) and L_hat (fitted loading)
#    counterfactuals, plus the paired "own" (actual) rejection (FIX 2/3:
#    ALWAYS p <= alpha, never CI membership — matches summarize_oc exactly).
################################################################################

pairs <- pairs |>
  mutate(
    is_wild     = inference %in% CI_SHIFT_INFERENCE,
    # Mirrors run_estimators.R's z <- qt(1 - alpha/2, df = max(1L, df_cluster)).
    df_analytic = pmax(1L, n_treated_clusters0 + n_control_clusters0 - 1L),
    # FIX 3: "actual" rejection is always p-based, matching summarize_oc.
    reject_own  = p_own <= ALPHA,

    # --- L = 1 (raw truth) shift ---
    shift_l1          = truth,
    att_shifted_l1     = att0 + shift_l1,
    p_shifted_l1       = if_else(
      is_wild, NA_real_,
      2 * stats::pt(-abs(att_shifted_l1 / se0), df = df_analytic)),
    ci_lo_shifted_l1   = ci_lo0 + shift_l1,
    ci_hi_shifted_l1   = ci_hi0 + shift_l1,
    reject_shifted_l1  = if_else(
      is_wild,
      !(ci_lo_shifted_l1 <= 0 & 0 <= ci_hi_shifted_l1),
      !is.na(p_shifted_l1) & p_shifted_l1 <= ALPHA
    ),

    # --- L_hat (fitted loading) shift; truth == 0 forces shift == 0 so a
    #     degenerate/NA l_hat can never contaminate the delta=0 identity ---
    shift_lhat         = if_else(truth == 0, 0, l_hat * truth),
    att_shifted_lhat    = att0 + shift_lhat,
    p_shifted_lhat      = if_else(
      is_wild, NA_real_,
      2 * stats::pt(-abs(att_shifted_lhat / se0), df = df_analytic)),
    ci_lo_shifted_lhat  = ci_lo0 + shift_lhat,
    ci_hi_shifted_lhat  = ci_hi0 + shift_lhat,
    reject_shifted_lhat = if_else(
      is_wild,
      !(ci_lo_shifted_lhat <= 0 & 0 <= ci_hi_shifted_lhat),
      !is.na(p_shifted_lhat) & p_shifted_lhat <= ALPHA
    )
  )

################################################################################
# 9. Self-check 1 (FIX 3 rescope): the shift ARITHMETIC must reduce to an
#    EXACT identity at zero shift (delta == 0) — analytic/boot_t: the
#    recomputed t-stat p-value must reproduce the stored p0/p_own to
#    floating precision; wild: shifting the CI by 0 must reproduce the
#    stored ci_lo0/ci_hi0 exactly (pure algebra, +0.0). This is DELIBERATELY
#    NOT a check that reject_shifted == reject_own for the wild arm — that
#    comparison conflates pure arithmetic with the wild arm's separate,
#    already-disclosed p-vs-CI duality gap (quantified in §10). Stop on
#    arithmetic failure — every downstream comparison is meaningless
#    otherwise.
################################################################################

row_check <- pairs |> filter(delta == 0)
an_idx <- !row_check$is_wild
wi_idx <- row_check$is_wild

p_diff_l1        <- abs(row_check$p_shifted_l1 - row_check$p_own)
p_diff_lhat      <- abs(row_check$p_shifted_lhat - row_check$p_own)
ci_diff_l1       <- pmax(abs(row_check$ci_lo_shifted_l1 - row_check$ci_lo0),
                          abs(row_check$ci_hi_shifted_l1 - row_check$ci_hi0))
ci_diff_lhat     <- pmax(abs(row_check$ci_lo_shifted_lhat - row_check$ci_lo0),
                          abs(row_check$ci_hi_shifted_lhat - row_check$ci_hi0))

.safe_max <- \(x) {
  m <- suppressWarnings(max(x, na.rm = TRUE))
  if (is.finite(m)) m else 0
}
max_p_diff_l1    <- .safe_max(p_diff_l1[an_idx])
max_p_diff_lhat  <- .safe_max(p_diff_lhat[an_idx])
max_ci_diff_l1   <- .safe_max(ci_diff_l1[wi_idx])
max_ci_diff_lhat <- .safe_max(ci_diff_lhat[wi_idx])
worst_diff <- max(max_p_diff_l1, max_p_diff_lhat, max_ci_diff_l1,
                   max_ci_diff_lhat)

if (worst_diff > SELF_CHECK1_TOL) {
  bad_idx <- (an_idx & (p_diff_l1 > SELF_CHECK1_TOL |
                          p_diff_lhat > SELF_CHECK1_TOL)) |
    (wi_idx & (ci_diff_l1 > SELF_CHECK1_TOL | ci_diff_lhat > SELF_CHECK1_TOL))
  print(row_check[bad_idx, ], n = Inf)
  stop(sprintf(paste0(
    "Self-check 1 FAILED: at delta=0 the shift arithmetic does not reduce ",
    "to an exact identity (max |p diff| L1/Lhat = %.3e/%.3e, max |ci diff| ",
    "L1/Lhat = %.3e/%.3e, tolerance = %.1e). This indicates a bug in the ",
    "join keys, df recovery, or shift formula — fix before trusting any ",
    "delta>0 comparison. Offending rows printed above."),
    max_p_diff_l1, max_p_diff_lhat, max_ci_diff_l1, max_ci_diff_lhat,
    SELF_CHECK1_TOL), call. = FALSE)
}
message(sprintf(paste0(
  "\nSelf-check 1 PASSED: at delta=0 the shift arithmetic (both L=1 and ",
  "L_hat) reduces to an exact identity (max |p diff| = %.3e, max |ci diff| ",
  "= %.3e, tolerance = %.1e)."),
  max(max_p_diff_l1, max_p_diff_lhat), max(max_ci_diff_l1, max_ci_diff_lhat),
  SELF_CHECK1_TOL))

################################################################################
# 10. FIX 3 — Wild p-vs-CI duality check: quantify how often the wild arm's
#     stored p-value (used for "actual"/paired-actual rejection) disagrees
#     with the CI-membership rule (used, of necessity, for the SHIFTED
#     counterfactual) at the delta=0 BASELINE row — i.e. with ZERO shift
#     applied. Any disagreement here is pure p-vs-CI representation noise
#     (finite-B = 999 bootstrap-redraw noise between two order-statistic-
#     derived quantities from the SAME draw), not a shift-approximation
#     error, and is NOT gated by self-check 1 (§9) for exactly this reason.
################################################################################

wild_baseline <- pairs |> filter(delta == 0, is_wild)
if (nrow(wild_baseline) > 0L) {
  duality_disagree <- (wild_baseline$p_own <= ALPHA) !=
    (!(wild_baseline$ci_lo0 <= 0 & 0 <= wild_baseline$ci_hi0))
  n_duality_disagree <- sum(duality_disagree)
  message(sprintf(paste0(
    "\nFIX 3: wild p-vs-CI duality check — %d/%d (%.2f%%) baseline wild ",
    "rows have 'p0 <= alpha' disagree with '0 outside [ci_lo0, ci_hi0]'. ",
    "This is the wild arm's intrinsic validation resolution (finite-B ",
    "bootstrap-redraw noise), NOT a shift-approximation error. In ",
    "PRODUCTION shift mode the wild CI is drawn ONCE per rep at delta=0, so ",
    "this same frozen bootstrap-redraw noise is PERFECTLY CORRELATED ",
    "across every delta grid point derived from it — unlike full ",
    "re-estimation, which redraws B fresh wild weights at every delta."),
    n_duality_disagree, nrow(wild_baseline),
    100 * n_duality_disagree / nrow(wild_baseline)))
  duality_by_scenario <- wild_baseline |>
    mutate(disagree = duality_disagree) |>
    group_by(scenario_id, name) |>
    summarise(n = dplyr::n(), n_disagree = sum(disagree),
              pct_disagree = round(100 * mean(disagree), 3), .groups = "drop")
  print(duality_by_scenario, n = Inf)
} else {
  message("\nFIX 3: wild p-vs-CI duality check — no wild baseline rows ",
          "available.")
  n_duality_disagree <- 0L
}

################################################################################
# 11. FIX 5a — Decision-relevant statement: the delta=0 size gate (Type I
#     error at the estimator/level cell used for disqualification).
################################################################################

message(sprintf(paste0(
  "\nDECISION-RELEVANT (FIX 5a): the delta=0 size gate is, BY ",
  "CONSTRUCTION, EXACT in shift mode for analytic/boot_t inference ",
  "(self-check 1 above: max arithmetic error < %.1e) and bounded by the ",
  "wild arm's own p-vs-CI duality-noise floor (%d disagreement(s) out of ",
  "%d baseline wild rows above) for wild inference. Shift mode CANNOT ",
  "materially corrupt estimator disqualification at delta=0; the only ",
  "quantity genuinely at risk from shift mode is the delta > 0 MDE ",
  "crossing (see §13 MDE comparison below)."),
  SELF_CHECK1_TOL, n_duality_disagree,
  if (exists("wild_baseline")) nrow(wild_baseline) else 0L))

################################################################################
# 12. Aggregate to cell level: n_pairs, L_hat, paired-actual, and BOTH
#     shifted-power series
################################################################################

cell_keys <- c("scenario_id", "estimator", "inference", "estimand",
               "event_time", "delta")

shifted_power <- pairs |>
  group_by(across(all_of(cell_keys))) |>
  summarise(
    n_pairs              = dplyr::n(),
    l_hat                = dplyr::first(l_hat),
    n_obs_l_hat          = dplyr::first(n_obs_l_hat),
    power_actual_paired  = mean(reject_own),
    power_shifted_l1     = mean(reject_shifted_l1),
    n_pairs_lhat         = sum(!is.na(reject_shifted_lhat)),
    power_shifted_lhat   = if (all(is.na(reject_shifted_lhat))) NA_real_
                            else mean(reject_shifted_lhat, na.rm = TRUE),
    .groups = "drop"
  )

################################################################################
# 13. Combine paired-actual/shifted with the full-sample reference; compute
#     discrepancies (FIX 1 x FIX 2 jointly: both now share the SAME,
#     apples-to-apples paired denominator) and mc_se
################################################################################

shift_vs_actual_power <- shifted_power |>
  left_join(scenario_meta, by = "scenario_id") |>
  full_join(actual_power_full,
            by = c("scenario_id", "estimator", "inference", "estimand",
                   "event_time", "delta"),
            na_matches = "na") |>
  mutate(
    discrepancy_l1   = power_shifted_l1 - power_actual_paired,
    discrepancy_lhat = power_shifted_lhat - power_actual_paired,
    mc_se = if_else(
      !is.na(n_pairs) & n_pairs > 0L,
      sqrt(pmax(power_actual_paired * (1 - power_actual_paired), 0) /
             n_pairs),
      NA_real_
    ),
    # FIX 5a companion column (see §11 for the console statement).
    delta0_size_gate_invariant_by_construction = TRUE
  ) |>
  arrange(scenario_id, estimator, inference, estimand, delta) |>
  select(scenario_id, name, scenario_label, mechanism, shape, estimator,
         inference, estimand, event_time, delta, n_pairs, l_hat,
         n_obs_l_hat, power_actual_paired, power_shifted_l1, discrepancy_l1,
         power_shifted_lhat, discrepancy_lhat, n_pairs_lhat, mc_se,
         power_actual_full, n_reps_actual_full, n_converged_actual_full,
         delta0_size_gate_invariant_by_construction)

################################################################################
# 14. Self-check 2: deterministic-step benchmark scenario (exactness bound)
################################################################################

benchmark_tbl <- shift_vs_actual_power |>
  filter(mechanism == BENCHMARK_MECHANISM, shape == BENCHMARK_SHAPE)

if (nrow(benchmark_tbl) == 0L) {
  message(sprintf(paste0(
    "\nSelf-check 2: no %s x %s scenario in this run — skipping benchmark ",
    "report (nothing here pins exactness)."),
    BENCHMARK_MECHANISM, BENCHMARK_SHAPE))
} else {
  message(sprintf(
    "\nSelf-check 2 — deterministic-step benchmark scenario ('%s'):",
    unique(benchmark_tbl$name)))
  print(benchmark_tbl |>
          select(estimator, inference, delta, n_pairs, l_hat,
                 power_actual_paired, power_shifted_l1, discrepancy_l1,
                 power_shifted_lhat, discrepancy_lhat, mc_se), n = Inf)

  benchmark_analytic <- benchmark_tbl |> filter(inference != "wild")
  flagged <- benchmark_analytic |>
    filter(!is.na(mc_se), abs(discrepancy_l1) > 2 * mc_se)
  if (nrow(flagged) > 0L) {
    message("WARNING: benchmark analytic-inference discrepancy_l1 exceeds ",
            "2*mc_se on the following cells:")
    print(flagged |>
            select(estimator, inference, delta, discrepancy_l1, mc_se))
  } else {
    message("Benchmark analytic-inference discrepancies are all within ",
            "2*mc_se of zero (exactness confirmed up to MC noise).")
  }

  benchmark_wild <- benchmark_tbl |> filter(inference == "wild")
  max_wild_disc <- suppressWarnings(max(abs(benchmark_wild$discrepancy_l1),
                                         na.rm = TRUE))
  if (is.finite(max_wild_disc)) {
    message(sprintf(paste0(
      "\nFIX 3(a): deterministic-step benchmark wild-arm max ",
      "|discrepancy_l1| = %.4f. Because the DGP is deterministic ",
      "(identical truth every rep) and TWFE is exactly linear (analytic-",
      "arm discrepancy = 0 to floating precision, above), this residual is ",
      "NOT shift-approximation error — it IS the wild arm's p-vs-CI ",
      "duality/bootstrap-redraw noise floor quantified in §10. Report it ",
      "as the wild arm's validation resolution, not as evidence against ",
      "shift sufficiency."), max_wild_disc))
  }
}

################################################################################
# 15. Write outputs (shift_vs_actual_power.csv, discrepancy_summary.csv)
################################################################################

readr::write_csv(shift_vs_actual_power,
                  file.path(OUTPUT_DIR, "shift_vs_actual_power.csv"))

discrepancy_summary <- shift_vs_actual_power |>
  filter(!is.na(discrepancy_l1)) |>
  group_by(scenario_id, name, scenario_label, estimator, inference) |>
  summarise(
    n_delta_cells             = dplyr::n(),
    l_hat                     = dplyr::first(l_hat),
    n_obs_l_hat               = dplyr::first(n_obs_l_hat),
    max_abs_discrepancy_l1    = max(abs(discrepancy_l1)),
    mean_abs_discrepancy_l1   = mean(abs(discrepancy_l1)),
    exceeds_2x_mc_se_l1       = any(abs(discrepancy_l1) > 2 * mc_se,
                                     na.rm = TRUE),
    max_abs_discrepancy_lhat  = {
      v <- abs(discrepancy_lhat)
      if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
    },
    mean_abs_discrepancy_lhat = {
      v <- abs(discrepancy_lhat)
      if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE)
    },
    exceeds_2x_mc_se_lhat     = any(abs(discrepancy_lhat) > 2 * mc_se,
                                     na.rm = TRUE),
    # FIX 5a companion column.
    delta0_size_gate_invariant_by_construction = TRUE,
    .groups = "drop"
  ) |>
  arrange(desc(max_abs_discrepancy_l1))

readr::write_csv(discrepancy_summary,
                  file.path(OUTPUT_DIR, "discrepancy_summary.csv"))

################################################################################
# 16. FIX 5b — MDE comparison: the framework's own decision statistic is the
#     MDE (delta at which the power curve crosses power_target = 0.80 via
#     compute_mde()'s local-linear interpolation), not max|discrepancy| over
#     the delta grid. Reused verbatim from
#     R/power/summarize_operating_characteristics.R.
#
#     ADVISORY 2 (round-2 re-review): mde_actual is now computed from
#     power_actual_paired — the SAME paired/usable sample as
#     mde_shifted_l1/lhat — eliminating the denominator mismatch FIX 2
#     eliminated everywhere else in this script. The full-sample quantity is
#     kept as mde_actual_full for reference against the framework's real
#     production statistic.
################################################################################

oc_actual_paired <- shift_vs_actual_power |>
  filter(!is.na(power_actual_paired)) |>
  transmute(scenario_id, estimator, inference, estimand,
            delta, "{reject_col}" := power_actual_paired)

oc_shift_l1 <- shift_vs_actual_power |>
  filter(!is.na(power_shifted_l1)) |>
  transmute(scenario_id, estimator, inference, estimand,
            delta, "{reject_col}" := power_shifted_l1)

oc_shift_lhat <- shift_vs_actual_power |>
  filter(!is.na(power_shifted_lhat)) |>
  transmute(scenario_id, estimator, inference, estimand,
            delta, "{reject_col}" := power_shifted_lhat)

mde_actual_paired <- compute_mde(oc_actual_paired,
                                  power_target = MDE_POWER_TARGET,
                                  alpha = ALPHA)
mde_actual_full <- compute_mde(oc, power_target = MDE_POWER_TARGET,
                                alpha = ALPHA)
mde_l1   <- compute_mde(oc_shift_l1, power_target = MDE_POWER_TARGET,
                         alpha = ALPHA)
mde_lhat <- compute_mde(oc_shift_lhat, power_target = MDE_POWER_TARGET,
                         alpha = ALPHA)

mde_keys <- c("scenario_id", "estimator", "inference", "estimand")
mde_comparison <- mde_actual_paired |>
  select(all_of(mde_keys), mde_actual = mde,
         mde_actual_reason = mde_reason) |>
  full_join(mde_actual_full |> select(all_of(mde_keys),
                                       mde_actual_full = mde,
                                       mde_actual_full_reason = mde_reason),
            by = mde_keys) |>
  full_join(mde_l1 |> select(all_of(mde_keys), mde_shifted_l1 = mde,
                              mde_shifted_l1_reason = mde_reason),
            by = mde_keys) |>
  full_join(mde_lhat |> select(all_of(mde_keys), mde_shifted_lhat = mde,
                                mde_shifted_lhat_reason = mde_reason),
            by = mde_keys) |>
  left_join(scenario_meta |> select(scenario_id, scenario_label),
            by = "scenario_id") |>
  mutate(
    mde_gap_l1 = mde_shifted_l1 - mde_actual,
    mde_gap_lhat = mde_shifted_lhat - mde_actual,
    # ADVISORY 3: MDE coverage flag — TRUE only when the power curve
    # actually crosses 80% within the delta grid (mde_actual_reason ==
    # "interpolated"). Every ramp/delayed/state-step cell is FALSE (state
    # power curves top out ~0.55-0.74 within delta in [0, 0.20]) and is NOT
    # characterized by this table — see shift_vs_actual_power.csv /
    # discrepancy_summary.csv for those cells instead.
    mde_defined = !is.na(mde_actual) & mde_actual_reason == "interpolated"
  ) |>
  select(scenario_id, scenario_label, estimator, inference, estimand,
         mde_defined, mde_actual, mde_actual_reason, mde_actual_full,
         mde_actual_full_reason, mde_shifted_l1, mde_gap_l1,
         mde_shifted_l1_reason, mde_shifted_lhat, mde_gap_lhat,
         mde_shifted_lhat_reason) |>
  arrange(scenario_id, estimator, inference)

readr::write_csv(mde_comparison, file.path(OUTPUT_DIR, "mde_comparison.csv"))

n_mde_defined <- sum(mde_comparison$mde_defined)
message(sprintf(paste0(
  "\nADVISORY 3: MDE (%.0f%% power crossing) is DEFINED for only %d/%d ",
  "estimator x inference cells — the county headline scenario ",
  "('headline_county_nb_step') only. Every ramp/delayed/state-step cell ",
  "returns 'never_crosses_target' because those state-panel power curves ",
  "top out around 0.55-0.74 within delta in [0, 0.20] (see the figure). ",
  "The MDE table below does NOT characterize shift sufficiency for the ",
  "at-risk ramp/delayed shapes -- use discrepancy_l1/discrepancy_lhat in ",
  "shift_vs_actual_power.csv / discrepancy_summary.csv for those."),
  100 * MDE_POWER_TARGET, n_mde_defined, nrow(mde_comparison)))

message(sprintf(paste0(
  "\n=== FIX 5b (ADVISORY 2: paired mde_actual): MDE comparison (%.0f%% ",
  "power crossing; compute_mde() convention) ==="), 100 * MDE_POWER_TARGET))
print(mde_comparison |>
        mutate(across(c(mde_actual, mde_actual_full, mde_shifted_l1,
                         mde_gap_l1, mde_shifted_lhat, mde_gap_lhat),
                      \(x) round(x, 4))) |>
        select(-scenario_id), n = Inf)

################################################################################
# 17. Figure: paired-actual vs. shifted (L=1) vs. shifted (L_hat) power
#     curves, faceted by scenario x estimator; inference distinguished by
#     linetype, series by color
################################################################################

plot_df <- shift_vs_actual_power |>
  select(scenario_label, estimator, inference, delta, power_actual_paired,
         power_shifted_l1, power_shifted_lhat) |>
  pivot_longer(cols = c(power_actual_paired, power_shifted_l1,
                         power_shifted_lhat),
               names_to = "kind", values_to = "power") |>
  mutate(kind = recode(kind,
                        power_actual_paired = "Actual (paired)",
                        power_shifted_l1    = "Shifted (L=1)",
                        power_shifted_lhat  = "Shifted (L-hat, fitted)"))

fig <- ggplot(plot_df,
              aes(x = delta, y = power, color = kind, linetype = inference)) +
  geom_line(linewidth = 0.5) +
  geom_point(size = 1, alpha = 0.8, na.rm = TRUE) +
  facet_grid(rows = vars(scenario_label), cols = vars(estimator)) +
  scale_x_continuous(breaks = sort(unique(plot_df$delta))) +
  scale_color_manual(values = c(
    "Actual (paired)"          = "#1b9e77",
    "Shifted (L=1)"            = "#d95f02",
    "Shifted (L-hat, fitted)"  = "#7570b3")) +
  labs(x = "Imposed effect size (delta)", y = "Rejection rate (power)",
       color = NULL, linetype = "Inference") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUTPUT_DIR, "shift_vs_actual.png"), fig,
       width = 10, height = 14, dpi = 300, bg = "white")

################################################################################
# 18. Console summary
################################################################################

message("\n=== Discrepancy summary (max/mean |shifted - paired-actual| ",
        "power; L=1 vs. L_hat) ===")
print(discrepancy_summary |>
        mutate(across(c(max_abs_discrepancy_l1, mean_abs_discrepancy_l1,
                         max_abs_discrepancy_lhat, mean_abs_discrepancy_lhat,
                         l_hat), \(x) round(x, 4))) |>
        ungroup() |>
        select(-scenario_id, -name), n = Inf)

message(sprintf(paste0(
  "\nOverall: %d scenario(s), %d cell(s) checked, %d flagged under L=1 / ",
  "%d flagged under L_hat (exceeds 2*mc_se anywhere) out of %d estimator x ",
  "inference groups."),
  n_scenarios, nrow(shift_vs_actual_power),
  sum(discrepancy_summary$exceeds_2x_mc_se_l1),
  sum(discrepancy_summary$exceeds_2x_mc_se_lhat),
  nrow(discrepancy_summary)))

message(sprintf("\nOutputs written to %s/:", OUTPUT_DIR))
message("  - shift_vs_actual_power.csv")
message("  - discrepancy_summary.csv")
message("  - mde_comparison.csv")
message("  - loading_by_delta.csv")
message("  - shift_vs_actual.png")
