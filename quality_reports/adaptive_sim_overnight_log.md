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
