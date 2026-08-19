# Adaptive CS MDE Search Implementation Plan

**Status:** APPROVED (overnight autonomous run, 2026-08-19; authorized by the overnight
prompt + the 2026-08-18 Opus review's "Recommended decision")
**Goal:** Replace shift-mode synthesis for the headline county CS MDE with an
adaptive/sequential grid that concentrates *full* CS estimation near the 80% power
crossing, gated by a null-size calibration that must pass before any MDE is reported.

**Trigger:** `quality_reports/sufficient_statistics_shift_mode_code_review.md`
(2026-08-18, disposition CRITICAL ERRORS): do not use shift-mode output for the
headline CS MDE; "use brute-force estimation or an adaptive/sequential grid that
concentrates full simulations near the power crossing."

---

## Architecture

New module `R/power/adaptive_mde.R` exposing `run_adaptive_mde(config_path, ...)`.
It **reuses** the existing per-cell machinery unchanged — `read_power_config`,
`expand_scenario_grid` / id assignment, `load_blinded_panel`, `make_pseudo_schedule`,
`impose_effect`, `run_estimator`, `.compute_truths`, `.attach_truth`,
`summarize_oc`, `.mde_from_curve` — and adds only a *scheduler* deciding which
(rep, delta) cells to estimate. No shift synthesis anywhere.

**Cell-equivalence invariant (the load-bearing design fact):** in the existing
brute-force path (`run_scenario_grid.R:1295-1313`), a rep's schedule is drawn with
`set.seed(seed_rep)` and each delta's injection re-seeds with `seed_rep + 1`, so the
estimator's RNG state at entry depends only on (rep, delta) — not on which other
deltas were visited. An adaptive scheduler that runs the same call sequence per cell
(schedule → impose → run_estimator, single estimator) therefore produces
**bit-identical** rows to a brute-force run of the same config for every cell it
visits. Verified explicitly by gate 6.

## Prespecified statistical rules (fixed BEFORE any county run)

1. **Size gate (design §14, unchanged):** per CS inference arm, δ=0 rejection at
   nominal α=0.05 over the full `n_reps = 250` must lie in **[2.5%, 10%]** (point
   estimate; Wilson 95% CI reported alongside). Arms outside the interval are
   disqualified. If **no** arm passes → calibration-failure report; **no MDE search,
   no CS power reported** (valid scientific stopping condition).
2. **Arms:** analytic, boot (genuine multiplier), boot_t. `jack` (CV3) stays OFF at
   county (H+1 ≈ 30 att_gt fits/rep ≈ 35h+ for δ=0 alone; state-level evidence
   `data/output/cs_cv3_calibration/state/`: 0.5% rejection — outside the gate on the
   conservative side). The report must state jack is untested at county.
3. **Candidate deltas = the config's 11-point grid only** (0, .01, .02, .03, .04,
   .05, .06, .08, .10, .15, .20). Adaptivity selects *which grid points* get full
   estimation and in what order — it never shrinks the grid's range and never
   proposes off-grid deltas, so the final MDE is computed by the *identical*
   interpolation rule as brute force (`.mde_from_curve`).
4. **Search rule:** bisection on grid indices. Classification of an evaluated δ>0:
   *decisively above* target (0.80) if Wilson 95% lower bound > target, or n =
   n_reps and p̂ ≥ target; *decisively below* if Wilson upper bound < target, or
   n = n_reps and p̂ < target; else undecided → allocate another batch (25 reps,
   rep ids strictly increasing from 1, matching brute-force rep ids).
5. **Bracket completion:** when lo (largest decisively-below δ) and hi (smallest
   decisively-above δ) are adjacent grid points, **both are topped up to the full
   n_reps** before the MDE is interpolated — interim early stopping only chooses
   *which* deltas get finished, never reduces replication at the decision points.
   δ=0 always has full n_reps (it is the size gate).
6. **Boundary verdicts:** grid-max decisively below target at full n_reps →
   `never_crosses_target` (power at grid max reported as a bound). Smallest positive
   grid point decisively above at full n_reps → `at_or_below_smallest_grid_point`.
7. **Multiple surviving arms:** the search is driven by the first surviving arm in
   priority order [boot, boot_t, analytic]; after its bracket completes, the loop
   re-runs for each other surviving arm (their crossings may differ) until every
   surviving arm has an adjacent full-rep bracket or a boundary verdict. Every
   arm's rows are recorded at every visited cell regardless (they come free from
   the same `att_gt` fit).
8. **MDE + CI:** point MDE via `.mde_from_curve` on full-rep points (bracket pair +
   any other full-rep points); bootstrap CI via `compute_mde`'s joint rep-resampling
   restricted to evaluated deltas (n_boot = 200).
9. **Monotonicity anomaly:** if classifications are non-monotone in δ (a higher δ
   decisively below a lower decisively-above δ), the run flags `anomaly = TRUE`,
   evaluates the whole disputed index range at full n_reps, and reports it — never
   silently reconciles.
10. **Adaptive-vs-brute agreement tolerance (gate 6):** overlapping (rep, δ) cells
    bit-identical (att/se/p exact match); MDE point difference ≤ 0.005 (the shift
    validation's own tolerance) when both cross, and identical verdict strings when
    either does not cross.

## File structure

- Create `R/power/adaptive_mde.R` — scheduler + driver + state file I/O.
- Create `tests/testthat/test-adaptive-mde.R` — unit + mock adaptive-search tests.
- Create `config/power_county_cs_adaptive.yml` — county CS, `shift_mode: false`,
  `estimators: [cs]`, `run_name: county_cs_adaptive` (never touches
  `output_blinded_power/county_cs`).
- Create `config/power_state_cs_adaptive_check.yml` — gate-6 state comparison config.
- Create `scripts/run_power_county_cs_adaptive.sh`.
- Create `quality_reports/adaptive_sim_overnight_log.md` (append-only overnight log).
- Modify nothing in `R/power/run_scenario_grid.R` (brute-force path must stay
  byte-identical; it is the comparison benchmark).

## Public interface

```r
run_adaptive_mde(config_path, run_name = NULL, workers = NULL,
                 scenarios = NULL, n_reps_override = NULL,
                 batch_size = 25L, power_target = 0.80, gate_alpha = 0.05,
                 gate_interval = c(0.025, 0.10),
                 arm_priority = c("boot", "boot_t", "analytic"),
                 impose_fn = NULL, estimator_fn = NULL, resume = TRUE)
```

Outputs under `output_blinded_power/<run_name>/`:
`partials/<scenario_id>.csv` (same row schema as run_scenario_grid partials),
`partials/<scenario_id>.csv.done_cells` (lines "rep,delta"),
`adaptive_state_<scenario_id>.json` (phase, per-delta tallies, per-arm gate
verdicts, bracket, next action, anomaly flags, last checkpoint, timestamps),
`oc_summary.csv`, `mde_adaptive.csv`, `size_gate.csv`, `run_metadata.json`.

Pure decision core (unit-testable without estimation):
```r
.amde_wilson(k, n, conf = 0.95)                  # c(lo, hi)
.amde_classify(k, n, n_full, target, conf)       # "above"|"below"|"undecided"
.amde_next_action(tally, grid, n_reps, batch_size, target, arm)
#  -> list(type = "null_batch"|"eval_batch"|"top_up"|"verdict_never_crosses"|
#          "verdict_at_or_below_smallest"|"bracket_done"|"anomaly",
#          delta = <numeric>, reps = <integer vector>)
```

## Progressive gates (from the overnight protocol; do not skip ahead)

1. Static inspection & design — this plan.
2. Targeted unit tests — decision core (Wilson, classify, next_action on synthetic
   tallies covering: bisection order, top-up, both boundary verdicts, anomaly,
   resume-tally reconstruction).
3. Full `tests/testthat` suite — no regressions.
4. Mock adaptive-search test — mocked estimator with known power curve
   power(δ) = pnorm(δ/σ − z): adaptive recovers the same MDE as brute force on the
   same mock, state file advances correctly, kill-and-resume reproduces the
   uninterrupted result exactly.
5. Cheap toy simulation — stochastic mock (real RNG dependence on seed_rep) proving
   cell bit-identity between the adaptive driver and `run_scenario_grid`'s
   brute-force path on the same config.
6. State-level brute-force comparison — real data, state/S2/D1, `cs`,
   `deterministic` + `count_nb` step, small n_reps (40): overlapping cells
   bit-identical; verdict/MDE agreement per rule 10.
7. County smoke — n_reps_override = 6 on the county headline scenario: plumbing,
   runtime measurement per county CS fit.
8. County null calibration — δ=0, 250 reps, all arms; size gate per arm.
9. County adaptive MDE run — ONLY if ≥1 arm passes gate 8. Otherwise
   calibration-failure report (`output_blinded_power/county_cs_adaptive/
   calibration_failure_report.md` + copy in quality_reports/).

## Known context feeding gate 8 expectations (evidence, not prejudgment)

- State-level (200 reps, D1, count_nb, δ=0): analytic 21.5%, boot 24.5%, boot_t
  23.0%, jack 0.5% — all outside [2.5%, 10%].
- County partial (`output_blinded_power/county_cs`, 125 reps, different seeds,
  shift-mode config): analytic 59.2%; boot & boot_t 1.6% (2/125 — Wilson CI spans
  2.5%, so the county gate is genuinely undecided for the boot arms).

## Escalation & review

- Repeated (3×) same failure → materially different approach; Opus consulted for
  statistical disputes (per overnight protocol).
- Before accepting gate 8/9 output: Opus review of the size-gate table and (if
  reached) the adaptive-vs-brute agreement.
