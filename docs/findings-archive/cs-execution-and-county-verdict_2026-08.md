> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### CS in the Blinded Power Framework: Two Execution Flags (2026-08-17)

The CS arm of `R/power/` could not run at all until this date. Two run-level config keys
now govern it; both default to historical behavior and both are hashed into the scenario
id **only when non-default AND only for CS-bearing scenarios**, so enabling either never
moves a twfe/did2s id or orphans a completed partial. Full write-up:
`docs/methodology/POWER_SIMULATION_DESIGN.md` §16a. Tests:
`tests/testthat/test-cs-safe-patches.R`.

- **`cs_safe_patches`** (default `FALSE`). `att_gt` → `DRDID:::reg_did_rc` → `fastglm`
  **aborts the R process** (C-level, uncatchable) on zero-row design matrices from
  non-identifiable (g,t) cells — ~1 rep in 4 on the D1 state design. Under furrr the
  worker dies and the scenario is lost. `TRUE` installs `patches/reg_did_rc_safe.R`.
  **Must patch two bindings**: `did` does `importFrom(DRDID, reg_did_rc)` and copies it by
  value, and under `faster_mode=TRUE` calls it unqualified — patching DRDID alone leaves
  the hot path unguarded while appearing to succeed.
- **`cs_faster_mode`** (default `TRUE` = historical). With `TRUE`, CS failed on **100%**
  of probed rep × delta cells: "singular matrix due to not enough control units. Try
  changing faster_mode=FALSE." TWFE/did2s converged on 100% of the same reps.
  `analysis/diagnostics/cs_cv3_calibration_state.R:64-66` found this on 2026-08-11 and
  fixed it only in that script. `FALSE` is also *faster* here (24–40 s vs 57–101 s/fit).
  **Implication: every prior CS run in this framework used a non-estimating code path.**

**Unresolved:** the two `faster_mode` settings return materially different ATTs on
identical data (−0.033 vs +0.557 on one rep, with different SEs). `faster_mode` is meant
to be a pure computational shortcut, so this should not happen. Treat CS point estimates
from this framework as provisional and always record which mode produced them.

### County CS Verdict via the Adaptive MDE Search (2026-08-19 — RESOLVED question)

Shift mode was barred for the headline CS MDE by an Opus review
(`quality_reports/sufficient_statistics_shift_mode_code_review.md`); the replacement is
`R/power/adaptive_mde.R` (`run_adaptive_mde()`, design doc §16c) — an adaptive grid where
every cell is a genuine full estimate, bit-identical per (rep, δ) to brute force
(verified on real state CS). Production run `output_blinded_power/county_cs_adaptive/`
(county/S2/D1-panel/count_nb/step, 250 reps, faster_mode=FALSE, safe patches on):

- **Size gate:** analytic 61.2% FAIL (SE/SD 0.23, coverage 39%); **boot 4.4% and
  boot_t 3.2% size-valid** (0 failures) — the multiplier bootstrap that over-rejected at
  state (24.5%) is size-valid at county — **but NOT calibrated**: SE/SD ≈ 1.74, CI width
  ≈ 2 log points ([−60%, +150%] in filings).
- **Power curve is FLAT for both size-valid arms** — power ≈ size everywhere, 7.2%/4.8%
  at δ=0.20 with full 250 reps → `never_crosses_target`. **No defensible finite county CS
  MDE exists on the pre-registered grid** (do not write "MDE > 20%" as if it sits nearby).
- **CS point estimate is biased +0.10 upward under the null** on this cell (t ≈ 4.7),
  which inflates power and so strengthens the never-crosses verdict a fortiori; the cell
  must not be reused for point-estimate claims.
- PAP consequence: CS is eliminated on power among size-valid arms (did2s remains the
  calibrated county workhorse). One-cell scope; §14 fragility criterion unmet by design.
- Full report: `quality_reports/adaptive_cs_mde_report_2026-08-19.md`; overnight
  narrative: `quality_reports/adaptive_sim_overnight_log.md`. The old shift-mode partial
  `output_blinded_power/county_cs/` is preserved untouched.

