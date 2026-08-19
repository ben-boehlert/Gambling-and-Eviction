# Adaptive CS MDE Search — Overnight Log (append-only)

Task: implement + validate an adaptive/sequential MDE search for the CS arm of the
blinded power framework, per the 2026-08-18 Opus shift-mode review; run the county
null-calibration gate; run the adaptive county MDE search only if a CS inference arm
passes the size gate. Plan: `quality_reports/plans/2026-08-19_adaptive-cs-mde-search.md`.

---

## 2026-08-19 ~03:0x — Stage: state recovery + design (Fable)

- Recovered prior state from disk: no adaptive code existed; trigger is the Opus
  review `quality_reports/sufficient_statistics_shift_mode_code_review.md` (2026-08-18,
  CRITICAL — shift-mode CS MDE disallowed; brute force or adaptive grid required).
- `output_blinded_power/county_cs` holds a 125/250-rep checkpointed partial
  (S5dfb55e048…, last write 2026-08-17 21:02, no R process running). PRESERVED — will
  not be touched or resumed by this task.
- Key prior evidence: state CV3 calibration (`data/output/cs_cv3_calibration/state/`)
  → all four CS arms outside the [2.5%,10%] size gate at state level. County partial
  δ=0 through 125 reps: analytic 59.2%, boot/boot_t 1.6% (2/125) — county boot arms
  genuinely undecided → gate 8 is a real decision point.
- Verified cell-equivalence invariant in `run_scenario_grid.R` (schedule seeded at
  seed_rep, injection re-seeded at seed_rep+1 per delta) → adaptive scheduler can be
  bit-identical to brute force per (rep, delta) cell.
- Plan written and saved. Next action: Task 1 — decision-core unit tests (TDD).

## 2026-08-19 01:20 — Gates 1-5 PASSED (Fable, TDD inline)

- `R/power/adaptive_mde.R` implemented: pure decision core (Wilson / classify /
  tally / grid-index bisection scheduler) + `run_adaptive_mde()` driver with
  per-cell checkpointing (`.done_cells` sidecar), per-scenario
  `adaptive_state_<id>.json`, size gate, per-arm search, full-rep-only MDE.
- `tests/testthat/test-adaptive-mde.R`: 14 unit tests (RED→GREEN) + 3 driver
  end-to-end tests with a known-power-curve mock: bracket (0.08, 0.10) found as
  theory predicts; interrupted run resumes to a bit-identical result; failed size
  gate stops before any delta>0 cell; overlapping cells bit-identical to
  `run_scenario_grid` brute force on the same config; identical MDE to 1e-12.
- Full 12-file test suite: PASS, no regressions.
- Next: commit, then gate 6 (state-level real-CS brute-force comparison; gate
  interval disabled for that run only — CS state arms are known miscalibrated and
  the run exists to validate search machinery + cell equivalence, not size).

## 2026-08-19 01:43 — Gate 6 PASSED: state-level real-CS adaptive vs brute force

- Config `config/power_state_cs_adaptive_check.yml` (state/S2/D1/count_nb/step, cs,
  n_reps 40); script `analysis/diagnostics/adaptive_vs_brute_state_check.R`.
- Adaptive visited 130 (rep, delta) cells (0, .06, .15, .20) vs brute's 440 — and
  all 16,980 overlapping rows are BIT-IDENTICAL (att/se/p/ci_lo/ci_hi/truth all
  TRUE), including genuine multiplier-bootstrap p-values → the cell-equivalence
  invariant holds on the real estimator, RNG paths included.
- MDE verdicts identical per arm: never_crosses_target for analytic/boot/boot_t
  (expected at state level; the size gate was intentionally disabled for this
  machinery-validation run). gate6_agreement.csv: all agree = TRUE.
- Wall clock: adaptive 5.5 min, brute 16.5 min (6 workers). State CS cell ≈ 17 s.
- Next: gate 7 county smoke (n_reps_override 6 → measures county CS cell cost and
  exercises the gate-fail stop path at county scale), then gate 8 (250-rep county
  null calibration, the decision point).

## 2026-08-19 01:45 — Gate 7 PASSED: county smoke

- `_amde_county_smoke` (n_reps_override 6, batch 3, 6 workers): end-to-end county
  plumbing OK; gate-failure stop path exercised at county scale (no delta>0 cells
  after a failed gate). Smoke gate rates (6 reps, not evidence): analytic 5/6,
  boot/boot_t 0/6 — direction consistent with the 125-rep county_cs partial.
- County CS cell cost measured: ~28 s (both att_gt fits) → 250-rep null phase
  ≈ 20-25 min on 6 workers; each searched delta ≈ 20 min.
- Smoke output dir kept (underscore-prefix validation-dir convention).
- Launching PRODUCTION run: output_blinded_power/county_cs_adaptive
  (gate 8 null calibration → size gate → gate 9 search only if an arm passes).

## 2026-08-19 02:05 — Opus design review received; MAJOR fixes implemented

- Opus review verdict: sound in principle (size gate free of optional stopping;
  A2/A3 residual biases second-order and conservative-signed; cell equivalence
  D11 verified), but 4 MAJOR classes to fix before reporting: (B1/B3/B4) gate must
  enforce the failure-rate criterion, enumerate expected arms, record its interval;
  (B2/D1) arm-specific n_done lost reps when an arm's row was missing → failure
  understatement + a potential infinite re-run loop; (C1/C2) bootstrap MDE CI was
  truncated to [lo, hi] and n_boot_finite was dropped; (X1) no prespecified
  headline-arm rule. Plus E2: cs_jack exclusion is defensible on COST only —
  report must scope any failure conclusion to the three tested arms.
- AMENDMENT 1 written to the plan at 01:57 — BEFORE any county delta>0 estimation
  (null phase still running): headline arm = LARGEST MDE among survivors (§15(2));
  flank top-up rule; gate = size criterion of §14 + failure rate (not full §14);
  expected-arm enumeration; scoped reporting language.
- Fixes implemented TDD (tests updated first): .amde_tally attempted-cell
  denominator; flank top-up before bracket_done; gate columns
  (gate_lo/gate_hi/reason) + failure-rate enforcement + expected arms; Phase-4
  output now carries n_boot_finite, power/n_used at bracket, full_deltas, ci_note;
  duplicate-cell + zero-row guards; per-arm iteration cap → scheduler_stalled;
  orphan-rename instead of unlink on unresumable partials; float-safe cell keys.
- Full suite green. The RUNNING county process (old code) is unaffected: its cells
  are bit-identical under either scheduler; after it finishes, the driver will be
  re-run with resume=TRUE under the fixed code to reuse every cell, add flank
  top-ups, and regenerate gate/MDE outputs in the new format.
- Interim county tallies at 75/250 (monitoring only): analytic 58.7%, boot 5.3%,
  boot_t 2.7%, failures 0.
