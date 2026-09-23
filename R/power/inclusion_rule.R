################################################################################
# R/power/inclusion_rule.R
#
# THE SWITCHER INCLUSION RULE for the clean 12-24 LP-DiD design (2026-09-16).
#
# A state (or county unit) is a switcher at launch month L if
#   (i)  every month of the pre-launch baseline [L - pmd, L - 1] is observed
#        AND none of them is splice-adjacent (2026-09-17: see below), and
#   (ii) at least `min_horizons` of the outcome months [L + h_lo, L + h_hi]
#        are observed AND not splice-adjacent (see splice_excluded_months()).
# Anything with a launch date that fails (i) or (ii) is DIRTY: neither a
# switcher nor a control.
#
# 2026-09-17 -- THE BASELINE IS NOW HELD TO THE SAME STANDARD AS THE OUTCOME.
# As first written the splice exclusion applied only to outcome months, while
# the baseline was a pure presence test. That was internally inconsistent: if a
# month is too close to the COVID splice to MEASURE an outcome, it is too close
# to ANCHOR one. Exactly one real switcher was affected -- AR (launch 2022-03,
# baseline [2021-09, 2022-02], of which 2021-09 and 2021-10 are splice-
# excluded); no other switcher has a single such month. AR/s own filings in
# that window are fine (2021-09 is +17% on its neighbours, broad-based across
# 9 of 12 basket counties -- NOT the artifact an early read of LSC/s fixed-
# baseline percentage suggested). The reason to exclude it is the rule, not
# the data: AR/s baseline sits where the CONTROL pool is most dispersed (the
# moratorium unwind), and unwind exposure predicts the placebo long-difference
# SD monotonically -- 6 unwind months 0.222 (AR), 4 0.167 (KS), 2 0.160 (MD),
# 0 0.107 (the other seven). Set baseline_clean = FALSE to restore the old
# behaviour.
#
# One rule, applied identically in three places:
#   * placement  (make_pseudo_schedules.R, eligibility = "presence"): a state
#     is eligible for pseudo-date d exactly when it would qualify as a switcher
#     at the implied launch d - lag;
#   * estimation (run_estimators.R .re_lpdid, spec lpdid_min_horizons /
#     lpdid_excluded_months): switchers below the floor are dropped, and cells
#     whose outcome month is splice-adjacent are skipped for everyone;
#   * real data  (analysis/main/lpdid_statepanel.R, MIN_HORIZONS /
#     SPLICE_BUFFER): same two filters on the real switcher set.
#
# WHY (docs/findings-archive/2026-09-16_county-arm-renter-weights.md and the
# eligibility_window_placement_probe): the legacy min_pre/min_post box is a
# SPAN check that never expressed what the estimator needs. (12,6) admitted
# switchers with no observed baseline (41% of placed slots dead); (18,0)
# admitted switchers whose only outcome months are the ones flanking the COVID
# splice, nearly doubling the delta = 0 SD. Choosing between two ad hoc boxes
# by SD is design shopping; this rule is stated in design terms and the SD is
# whatever it is.
#
# Month indices: every function takes integer month indices in the CALLER's
# convention (make_pseudo_schedules uses year*12 + month - 1; run_estimators
# uses year*12 + month). Convert `obs`, `launch`, and `excluded` with the same
# helper and the arithmetic is consistent. splice_excluded_months() returns
# first-of-month DATES for that reason.
################################################################################

#' Splice-adjacent months to exclude as OUTCOME months
#'
#' @param covid_drop Two dates (start, end) of the dropped COVID window.
#' @param buffer Months on each side to exclude (0 = none).
#' @return Date vector (first-of-month), possibly empty.
#' @export
splice_excluded_months <- function(covid_drop, buffer) {
  buffer <- as.integer(buffer)
  if (!is.finite(buffer) || buffer <= 0L) return(as.Date(character(0)))
  start <- lubridate::floor_date(as.Date(covid_drop[1]), "month")
  end   <- lubridate::floor_date(as.Date(covid_drop[2]), "month")
  pre  <- start %m-% months(rev(seq_len(buffer)))
  post <- end   %m+% months(seq_len(buffer))
  sort(c(pre, post))
}

#' Usable outcome horizons of one unit at one launch month
#'
#' @param obs Integer vector of the unit's observed month indices.
#' @param launch Integer launch month index (same convention).
#' @param pmd Baseline months before launch (strict, all must be observed).
#' @param h_lo,h_hi Outcome window in months after launch (12..24 headline).
#' @param excluded Integer month indices excluded as outcome months, and --
#'   when \code{baseline_clean} is TRUE -- as baseline months too.
#' @param baseline_clean Require the baseline to contain no excluded month
#'   (default TRUE, 2026-09-17). FALSE restores the presence-only test.
#' @return list(baseline_ok = logical, n_usable = integer, usable = integer
#'   month indices of usable outcome months).
#' @export
switcher_usable_horizons <- function(obs, launch, pmd = 6L, h_lo = 12L,
                                     h_hi = 24L, excluded = integer(0),
                                     baseline_clean = TRUE) {
  obs <- as.integer(obs); launch <- as.integer(launch)
  excluded <- as.integer(excluded)
  base <- (launch - as.integer(pmd)):(launch - 1L)
  win  <- (launch + as.integer(h_lo)):(launch + as.integer(h_hi))
  usable <- win[win %in% obs & !(win %in% excluded)]
  list(baseline_ok = all(base %in% obs) &&
         (!isTRUE(baseline_clean) || !any(base %in% excluded)),
       n_usable    = length(usable),
       usable      = usable)
}

#' Does a unit qualify as a switcher at this launch month?
#' @inheritParams switcher_usable_horizons
#' @param min_horizons Minimum usable outcome months (NA = no floor; then only
#'   the baseline and >= 1 outcome month are required).
#' @export
switcher_inclusion_ok <- function(obs, launch, pmd = 6L, min_horizons = 7L,
                                  h_lo = 12L, h_hi = 24L,
                                  excluded = integer(0), baseline_clean = TRUE) {
  u <- switcher_usable_horizons(obs, launch, pmd, h_lo, h_hi, excluded,
                                baseline_clean = baseline_clean)
  k <- suppressWarnings(as.integer(min_horizons))
  floor_k <- if (length(k) == 1L && is.finite(k)) max(1L, k) else 1L
  isTRUE(u$baseline_ok) && u$n_usable >= floor_k
}
