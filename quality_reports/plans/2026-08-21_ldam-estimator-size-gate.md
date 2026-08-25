# L-DAM (debiased autoregression) as a blinded-framework estimator + size-gate runs

## Context

Antonelli et al. (AOAS 2026, arXiv:2408.09012) propose the debiased linear autoregression
model (L-DAM) for state-policy panels: identification via ignorability conditional on the
prior control counterfactual (selection-on-lagged-outcomes), not parallel trends. In their
51-state simulations, CS-DiD and synthetic control had ~no power against small effects while
L-DAM detected them in >50% of datasets — directly targeting this project's binding
constraint (MDE 5–8% at best, 20%+ for het-robust estimators). Per the pre-registered PAP
decision rule, any candidate estimator enters only through the blinded calibration ladder:
size gate first, MDE only for survivors. This plan wires L-DAM into `R/power/` and runs the
size gate on three state-level cells: spliced (covid: drop), post-COVID (covid: post), and
keep-COVID (covid: keep — the AR-specific hypothesis that conditioning on each state's own
lagged outcome absorbs state-specific COVID paths, which did2s's global α_i cannot).

## Model and estimator design

Paper's eq. (3) with calendar-time effects (their Assumption 6 allows α_t):

    Y_it = α_t + β(Y_{i,t−1} − θ·A_{i,t−1}) + θ·A_it + ε_it

- A_it: absorbing treatment from `pseudo_g` (event date; same coding as twfe/did2s).
- α_t: calendar-month fixed effects.
- Lags on TRUE calendar months (the `.re_lpdid` m-index pattern at
  `R/power/run_estimators.R:993`) — a row whose t−1 falls in the covid gap, a panel edge,
  or a coverage hole drops; never bridge the gap by row position.
- k = 1 lag for v1 (the paper's main specification); expose `ldam_k` as a spec knob but
  do not exercise it in the gate.

Estimation — iterative profiling (θ appears in two terms):
θ⁰ = 0; repeat { ỹlag = y_lag − θ·a_lag; feols(y ~ ỹlag + a | m, cluster = ~state_abb);
θ ← coef(a) } until |Δθ| < 1e-10 (max 100 iters). Contraction for |β| < 1; converges in a
few iterations under an absorbing step treatment.

Two inference arms (both reported; the gate adjudicates):
1. `analytic` — clustered SE from the final iteration. Ignores the generated-regressor
   uncertainty in the lag adjustment; the size gate tests whether that matters.
2. `jack` — delete-one-state jackknife re-running the full iteration (~26 cheap refits),
   t with df = n_states − 1. Mirrors `.re_longdiff`'s inference
   (`R/power/run_estimators.R:455`).

Estimand row: `simple` (θ is the constant additive effect on the y_log1p scale — correctly
specified for the framework's step-shape delta shifts, so the gate is fair). All failures
return `.re_row(..., converged = FALSE, error_msg = ...)` — never throw (framework contract).

## Files to modify

1. **`R/power/run_estimators.R`**
   - New `.re_ldam(panel_sim, sp, cl, df_cluster)` following the `.re_lpdid` template
     (build Y matrix by calendar month; needs `panel_sim` directly, not `.re_prep` output).
   - Register: add `"ldam"` to the `match.arg` vector and `switch` in `run_estimator()`
     (line ~306/321), routed like lpdid/longdiff (calendar-month path).
   - Spec knobs in `.re_spec`: `ldam_k` (default 1L), `ldam_tol`, `ldam_maxit`.
2. **`R/power/run_scenario_grid.R`** — check the lpdid special-case at line 279 (monthly-
   frequency guard); extend to ldam if it is a frequency guard (ldam lags are also
   calendar-monthly; quarterly/annual out of scope for v1).
3. **`config/power_ldam_gate.yml`** (new) — clone of `power_lpdid_gate.yml`:
   covid: drop, state/S2/D1-panel/count_nb/step, estimators [twfe, did2s, lpdid, ldam],
   effect_grid [0, 0.05], n_reps 300, base_seed 20260723 (rep-for-rep pairing with every
   prior run), run_name `ldam_gate`.
4. **`config/power_ldam_gate_postcovid.yml`** (new) — same, covid: post,
   run_name `ldam_gate_postcovid`.
5. **`config/power_ldam_gate_keepcovid.yml`** (new) — same, covid: keep
   (`load_blinded_panel` already supports it, `R/power/load_blinded_panel.R:135`),
   run_name `ldam_gate_keepcovid`. Novel cell — no prior baseline; all four estimators run
   so did2s/lpdid/twfe get their first keep-COVID calibration alongside ldam. Note: the
   count_nb DGP built on the keep panel includes COVID-era noise in its residual process —
   that is the point of the cell.
   New run_names + content-hashed scenario ids ⇒ no resume collisions with prior runs.
6. **`tests/testthat/test-estimators.R`** — two tests following the existing pattern
   (lines 56–174): (a) ldam recovers a known constant effect on a toy AR(1) staggered
   panel (deterministic); (b) degenerate panel (too few months for a lag) is logged, not
   thrown; assert `.RE_SCHEMA` columns on both.

## Execution

1. `Rscript -e 'testthat::test_file("tests/testthat/test-estimators.R")'` — new + existing
   tests pass.
2. Smoke: `run_scenario_grid("config/power_ldam_gate.yml", n_reps_override = 5)` — wiring,
   schema, runtime check.
3. Full runs (local, background, sequential): drop → post → keep. Prior state gates at
   300 reps ran in tens of minutes locally; ldam adds ~1s/rep (jackknife) — total well
   under prior runs.
4. Summarize per cell: rejection @ α = 0.05 (δ=0), SE/SD, null bias, power at δ=0.05 —
   side-by-side with twfe/did2s/lpdid on the identical reps (shared base_seed).
5. Logging per repo rules: research journal entry + SESSION_REPORT append (+ mirror).
   Blindness: simulated outcomes only, pre-committed effect grid — compliant; no
   real-data treated ATTs produced.

## Out of scope (next steps if the gate passes)

- MDE run on the 11-point delta grid for surviving ldam arms (the ladder's second rung).
- `ldam_k > 1`, negative-binomial/log-link variant (paper §4.5), l-limited carryover lags,
  county-level cell.

## Verification / success criteria

- Tests green; smoke run produces schema-conformant rows for all 4 estimators.
- Gate read-out: an ldam arm "passes" if δ=0 rejection is within MC noise of nominal
  (the project's existing standard: not materially off 5% at 300 reps) with SE/SD near 1.
- Deliverable: results tables under `output_blinded_power/ldam_gate*/` + a short memo
  section in the session report comparing the three cells.
