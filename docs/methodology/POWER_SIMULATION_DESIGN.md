# Blinded Power-Simulation Design

**Date:** 2026-07-23
**Status:** Pre-registered design. Written after the code/data audit
(`POWER_SIMULATION_CODE_AUDIT.md`) and before any operating characteristic was computed.
Governed by `POWER_SIMULATION_BLINDNESS_PROTOCOL.md`.

**Methodological anchors:** Black, Hollingsworth, Nunes & Simon (2022, *J. Public Econ.*)
simulated-power template (real untreated data, imposed known effects, repeated re-estimation);
adapted — not copied — for staggered state-level adoption, monthly county count outcomes, and
heterogeneity-robust estimators. Their common-treatment-date assumption, binomial *thinning* (we
need augmentation: hypothesized effect is an increase), propensity-weighting, and Stata
architecture are **not** inherited. Additional anchors: Athey, Imbens, Qu & Viviano (2025) on
calibrating simulations to one's own panel; Abadie, Angrist, Frandsen & Pischke (2025) on
pretest size/power; Roth (2022); Rambachan & Roth (2023). Burlig–Preonas–Woerman (2020) is cited
via BHNS (the PDF is not in `Literature/`); its lesson — serial correlation makes iid-error power
calculations overstate power — is incorporated as a first-class scenario dimension (error
models preserving autocorrelation).

---

## 1. Estimand

**Primary:** the overall average treatment effect on the treated (ATT) of sports-gambling
legalization on eviction filings, expressed as a **proportional change in filings**, estimated
on the log1p scale: θ = E[log1p(Y(1)) − log1p(Y(0)) | treated post cells]. This matches the
intended analysis pipeline (`pretrends_statepanel_template.R`, outcome `log1p_filings_count`).

**Secondary:** dynamic event-time ATTs e = 0…24 (for recovery of effect shapes) and the
event-window average over e ∈ [0, 12].

**Simulated truth for comparison (exact definitions):**
- For the "simple/overall" aggregation: truth = the average of the imposed δ_ist over exactly
  the treated (unit, post-period) cells that the estimator's aggregation targets, weighted the
  way the aggregation weights them (CS `aggte(type="simple")`: group-size-weighted average over
  identifiable (g,t) cells; TWFE/did2s static: equal-weighted average over treated unit-months
  in the estimation sample). The framework computes this truth cell-by-cell from the injection
  metadata each replication — it is never assumed equal to the nominal grid value except for
  constant-step effects.
- For dynamic aggregations: truth at horizon e = average imposed δ over cells at event time e.

## 2. Units

- **Treatment assignment:** state. Every county in a pseudo-treated state receives the identical
  pseudo-treatment date (enforced by test).
- **Outcome observation:** primary — county-month (`monthly_county_data_download.csv`, PR/USVI
  FIPS 72xxx/78xxx excluded); secondary — state-month aggregate; variants — quarterly
  aggregation of each.
- **Clustering:** state, always (treatment-assignment level; Abadie, Athey, Imbens & Wooldridge
  2023).

## 3. Treatment definitions

- **T1 (primary):** online launch (`online_start_date`) — matches the intended analysis and the
  mechanism in the reference literature (online access drives financial-distress effects).
- **T2:** any legal sports betting (`first_start_date`).
Retail-only is not simulated separately (subsumed by T1 vs T2 contrast).

## 4. Comparison groups

- Not-yet-treated controls (CS `control_group="notyettreated"`) — primary, matching the
  pipeline.
- Never-treated controls (`control_group="nevertreated"`) — variant.
- The county panel has 13 never-treated states; the state panel 15. Effective control counts are
  reported as an operating characteristic per scenario.

## 5. Candidate estimators (finite set, substantively justified)

| ID | Estimator | Implementation | Inference |
|---|---|---|---|
| E1 | Callaway–Sant'Anna | `did::att_gt` (CRAN 2.3.0), `est_method="reg"`, `xformla=~1`, `allow_unbalanced_panel=TRUE`, `faster_mode=TRUE`, `clustervars=<state>`, `base_period="varying"` (universal as sensitivity), `anticipation ∈ {0, 6}` | (a) analytic SE + t(df = n_clusters − 1); (b) multiplier bootstrap (biters=199): both the genuine bootstrap p-value/critical value **and** the legacy t-on-bootstrap-SE are recorded separately (audit F2) |
| E2 | TWFE | `fixest::feols(y ~ post | id + t)`, cluster = state | (a) cluster-robust t; (b) wild cluster bootstrap (`fwildclusterboot`, Rademacher weights, WCR) |
| E3 | Gardner two-stage | `did2s::did2s`, first stage `~0 | id + t`, cluster = state | cluster-robust t(df = n_clusters − 1) |
| E4 (diagnostic only) | Sun–Abraham | `fixest::sunab` | cluster-robust t |

E1 is the intended paper specification; E2 is the diagnostic benchmark (not automatically
preferred); E3 is the credible alternative already supported by the project. E4 is retained only
to document its calibration, given the audit's history of singleton-cohort problems. `est_method
="reg"` avoids the DRDID/fastglm segfault path entirely, so the patched local packages are not
required (audit F4); if any scenario switches to "dr"/"ipw", `patches/att_gt_safe.R` +
`reg_did_rc_safe.R` must be sourced.

## 6. Outcome transformations

- **Y1 (primary):** `log1p(filings_count)` — matches pipeline.
- **Y2:** `log(filings_per_1k_renters + 0.01)` (rate).
- **Y3:** `asinh(filings_count)` — sensitivity.
- Counts are simulated as counts (integers) and transformed after injection under M1 (§9).

## 7. Calibration samples

All built by `load_blinded_panel()` under the protocol's cutoffs (universal cutoff 2018-05-31;
per-state cutoff g_s − 1 − A months, default anticipation exclusion A = 6, sensitivity {0, 3, 12}).

| ID | Sample | Content | Known limitation (documented, not hidden) |
|---|---|---|---|
| S1 | Strict universal | All states, 2016-01–2018-04 (28 months) | Short T: supports only short event windows; seasonal cycle observed ~2.3 times |
| S2 | State-specific risk set | Each state's own untreated months (6–84 per treated state) | Composition varies by calendar time; late cohorts contribute most |
| S3 | Never-treated | 13 (county) / 15 (state) never-treated states, full 2016–2025 | Never-treated states may differ systematically; smaller cross-section |
| S4 | Calendar variants | S2/S3 partitioned pre-COVID (< 2020-03), COVID (2020-03–2021-07; 2022-03 sensitivity), post-COVID | Variance/seasonality regime changes across segments |
| S5 | Synthetic/residual | Residual-resampling DGP (FE on untreated + month-stratified or AR(1) residuals) and `augment_panel`-style synthetic clusters | Sensitivity only. All imposed covariance/distribution/trend assumptions stated in config; BHNS warn fully synthetic data inflated their MDEs 2–4× |

**Comparison discipline:** power/size are reported for **all** samples side-by-side; the
pre-analysis plan cites the range, not the best case.

## 8. Pseudo-treatment schedules

All assign treatment at the state level; all are generated by `make_pseudo_schedules()` with
recorded seeds; all have a **null (δ=0) counterpart** used for size.

- **D1 Cohort-preserving reassignment (primary).** Preserve the actual number of cohorts, each
  cohort's state count, and inter-cohort spacing (from the real schedule under the chosen
  treatment definition, e.g. online: 18 cohorts, max size 2); reassign which eligible states
  belong to each cohort, uniformly at random among states with ≥ `min_pre` untreated months
  before and ≥ `min_post` after the candidate date (risk-set respect). Used with S2/S3/S4.
- **D2 Shifted actual design.** Keep real treated-state identities and the schedule's relative
  structure, shifted back into the untreated window. The real online schedule spans 55+ months;
  S1 offers 28. Compression rule (documented in every output): preserve cohort *order* and
  *count*, rescale inter-cohort gaps proportionally to fit `[first_month + min_pre,
  last_month − min_post]`; flag every scenario where rescaling was needed. Where even rescaling
  is infeasible, the scenario is reported as infeasible rather than silently altered.
- **D3 Untreated-risk-set draws.** Draw each pseudo-cohort date uniformly from periods where the
  assigned states are genuinely untreated (post-anticipation-exclusion), preserving cohort
  counts.
- **D4 Never-treated placebo.** Assign the cohort structure within never-treated states only
  (13 states vs 24 actual treated: the framework preserves cohort spacing and scales cohort
  counts proportionally, reporting the achieved structure).
- **D0 Null.** Every design above run with δ = 0 — required for false-positive rates.

A common-date random assignment is implemented **only** inside the BHNS validation module
(§13), never as a primary design.

> **Addendum (2026-08-10): D1 × S3 is structurally infeasible.** D1 places the *full* real
> template — under the online definition, 18 cohorts covering ~24 treated states over a 55-month
> span — but S3 contains only 12 (county) / 14 (state) never-treated states. No placement can
> supply ~24 pseudo-treated states from a 12–14 state pool; relaxing `min_pre`/`min_post` cannot
> help. Confirmed empirically: both S3 primary scenarios abort at startup with the
> `make_pseudo_schedule()` feasibility error (Della run 12114571, tasks 2 and 8), reproduced
> locally. Contrary to the "Used with S2/S3/S4" note under D1 above, **D1 is usable with S2/S4
> only; the never-treated-sample comparison is D4's job** (proportional cohort-count scaling).
> Resolution: S3 removed from the D1 blocks of the cheap config (and pending removal from
> `power_primary.yml`); the pre-analysis plan reports this infeasibility and cites D4 for the
> never-treated check, per the same reported-not-silently-altered principle as D2 rescaling.

## 9. Effect injection

- **M1 Count-based stochastic augmentation (primary).** For treated county-month (i,s,t) with
  imposed proportional effect δ_ist ≥ 0: draw
  `ΔY ~ NegBin(mean = μ_ist · (exp(δ_ist) − 1), dispersion θ̂)` and set `Y* = Y + ΔY`, where
  μ_ist is a **fitted baseline expected count** (county × calendar-month means from the
  calibration sample, floor at the county's untreated mean; never the realized Y alone), so
  zero-count cells still receive strictly positive expected injections. θ̂ is calibrated to the
  audited untreated overdispersion (median within-county var/mean ≈ 1.4; Poisson variant as
  sensitivity). Guarantees nonnegative integers; E[Y*] ≈ E[Y]·exp(δ) for small δ up to the
  log1p-vs-log approximation, which the OC module measures rather than assumes (truth is
  computed from injected cells, §1). Negative δ scenarios use binomial thinning
  (`Y* = Y − Binomial(Y, 1 − exp(δ))`), the BHNS mechanism.
- **M2 Deterministic transformed-scale shift (benchmark).** `y* = y + δ_ist` directly on the
  analysis scale (log1p / log-rate / asinh). Transparent, exact truth; not claimed realistic.

**Effect shapes (both mechanisms):** constant step; delayed onset (start at e = 6; motivated by
the ~2-year onset in Hollenbeck et al. and slow handle maturation); linear ramp to plateau at
e = 18 (proxy for market maturation: median state reaches 80% of peak handle ≈ 30 months);
temporary pulse (e ∈ [0, 12) then 0); anticipation (onset at e = −3); cohort-heterogeneous
(δ_g ~ spread ±50% around the grid value); state-heterogeneous (mean-preserving lognormal
multiplier); county-exposure-heterogeneous (δ scaled by within-state renter-share exposure);
intensity-proportional (δ scaled by a maturation curve standing in for handle growth); and null.
Every replication saves the full imposed-truth metadata.

## 10. Effect-size grid (with sources; NOT derived from this project's estimates)

Grid in proportional-change units: **{0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20}%**, finer (1-pp steps)
in the 1–6% region where the MDE plausibly lies given cluster counts comparable to BHNS (41
states → MDE ≈ 2–3% on log mortality).

Benchmarks anchoring the grid (all external):
- Financial-distress effects of legalization: bankruptcy ≈ +25% and credit-card delinquency
  ≈ +25% (retail-to-online), auto-loan delinquency +8% (general access), collections +9%
  (Hollenbeck, Larsen & Proserpio 2026); overall delinquency +0.3 pp on a 10.7% base ≈ +2.8%
  relative (Goss & Mangrum, FRBNY SR 1184, 2026); food insufficiency −2.1% ITT (Guo, Peng &
  Meyerhoefer 2026). Eviction is a further-downstream, more extreme margin than delinquency, so
  policy-relevant eviction effects are plausibly at or below the 2–10% range; 15–20% points
  characterize "crisis-size" effects that any usable design must detect.
- Policy scale: ~3.6M eviction filings/year nationally (Gromis et al. 2022, Eviction Lab), so
  1% ≈ 36,000 filings/year — a 1–2% effect is already policy-relevant, which is why the grid is
  dense there.
- Raw-count and standardized translations of each grid point (using untreated-sample means/SDs)
  are emitted alongside results by the OC module.

## 11. Simulation repetitions, seeds, execution

- Reps: primary scenarios 500 (TWFE/did2s) and 250 (CS, budgeted for `att_gt` cost); quick
  validation tier 25; sensitivity tier 200. All set in config, never hardcoded.
- Seeds: `seed_rep = base_seed + 10007·rep` (project convention), with
  `future_map(..., furrr_options(seed = TRUE))` L'Ecuyer streams for parallel safety; identical
  results serial vs parallel (tested).
- Batched execution with checkpoint/resume (`run_scenario_grid.R`), progress logging, per-rep
  failure capture (estimator errors are logged rows, never dropped).
- Runtime/memory per scenario recorded in metadata.

## 12. Operating characteristics (per scenario × estimator × inference method)

False-positive rate at α ∈ {0.10, 0.05, 0.01} (from D0 nulls); power over the full grid; MDE at
80% and 90% power (local-linear interpolation at the crossing, BHNS-style, with bootstrap CI over
replications); bias; RMSE; median absolute error; CI coverage of the simulated truth; mean CI
width; sign-error rate (Type-S); exaggeration ratio conditional on significance (Type-M);
"believability" share (significant ∧ correct sign ∧ ≤ 2× truth; Gelman & Carlin 2014 via BHNS);
convergence/failure rates; effective treated and control cluster counts; runtime; pre-trend-test
rejection rates (CS Holm-adjusted joint test over e ∈ [−12, −1]) under D0 and under anticipation
scenarios; sensitivity of all of the above across calibration samples, injection mechanisms, and
cohort-heterogeneity scenarios.

## 13. Validation against Black et al. (before trusting gambling-specific results)

`validate_simulation.R` implements a simplified BHNS reproduction on this project's real
untreated data: S1-style panel, common-date random pseudo-treatment of half the states,
binomial-thinning injection over a small grid, TWFE re-estimation, power = rejection frequency —
verifying the engine produces (a) ≈ nominal size at δ=0, (b) monotone power in δ, (c) a stable
interpolated MDE. Plus toy-panel unit tests: a known constant effect recovered exactly by TWFE
on a clean synthetic panel; null size ≈ α in a known-DGP test.

## 14. Failure criteria (a specification is flagged FAILED if any holds)

- Size at nominal 5% outside [2.5%, 10%] under D0 across primary calibration samples.
- CI coverage of truth below 90% (nominal 95%) under constant effects.
- Estimator failure/non-convergence > 5% of replications.
- Estimand mismatch: |bias| > 25% of truth under constant effects (aggregation not targeting
  the claimed estimand).
- Fragility: passes only under one calibration sample or one injection mechanism.

## 15. Selection rule for the pre-analysis plan

1. Eliminate specifications meeting any failure criterion (§14).
2. Among survivors, compare MDE-80 and power at 3% and 5% imposed effects, **across** samples
   and mechanisms — using the worst reasonable case, not the best.
3. Prefer the simplest substantively adequate specification; adopt added complexity only for a
   clear, robust improvement.
4. Treat single-sample or single-mechanism power gains as fragile; exclude them from the
   headline.
5. If no specification detects ≤ 5% effects with 80% power under credible calibrations, the
   pre-analysis plan states this bound explicitly and frames the study as bounding, not
   detecting. Simulated power never substitutes for identification credibility.

## 16. Architecture and module contract

```
R/power/
  config.R          # read_power_config(path): parse YAML, validate, fill defaults; returns list
  blindness_checks.R# assert_blinded(panel, schedule, anticipation); assert_no_forbidden_paths(path);
                    # blinded_output_path(...): errors unless under output_blinded_power/
  load_blinded_panel.R # load_blinded_panel(level = c("county","state"), treat_def, anticipation,
                    #   sample = c("S1","S2","S3"), covid = c("drop","pre","covid","post","keep"),
                    #   quarterly = FALSE, config): returns tibble
                    #   [unit_id, state_abb, month_date, t, filings_count, renters, y_* transforms,
                    #    g = 0 (always untreated by construction), meta attrs: cutoffs, sample_id]
  make_pseudo_schedules.R # make_pseudo_schedule(design = c("D1","D2","D3","D4"), panel, real_schedule,
                    #   treat_def, min_pre, min_post, seed): tibble [state_abb, pseudo_g(month_date)]
                    #   + attrs (cohort structure achieved, feasibility flags)
  impose_effects.R  # impose_effect(panel, schedule, mechanism = c("count_nb","count_pois",
                    #   "thinning","deterministic"), shape, delta, params, seed):
                    #   returns panel + y_sim + truth metadata (per-cell imposed delta)
  run_estimators.R  # run_estimator(panel_sim, estimator = c("cs","twfe","did2s","sunab"),
                    #   spec list): one row per estimand x inference method:
                    #   [att, se, p, ci_lo, ci_hi, inference, n_treated_clusters, n_control_clusters,
                    #    converged, error_msg, runtime_s] — errors captured, never thrown
  summarize_operating_characteristics.R # summarize_oc(results, truths, alpha_vec): the §12 table;
                    # compute_mde(power_curve, target)
  validate_simulation.R # §13 BHNS validation + invariant re-checks; writes validation report
  run_scenario_grid.R   # run_scenario_grid(config_path): expands scenario grid from YAML, runs
                    # batched/parallel/resumable, writes results + metadata to output_blinded_power/
config/
  power_primary.yml     # primary candidate set
  power_sensitivity.yml # full sensitivity grid
  power_validation.yml  # small fast tier (used by tests/CI and quick runs)
tests/testthat/       # see §17
scripts/run_power_validation.sh, run_power_primary.sh, run_power_sensitivity.sh
output_blinded_power/ # isolated outputs only
```

Existing code reused by sourcing (not copying where possible):
`utils/eviction_treatment_schedule.R`; residual-pool + AR(1) error models (ported from
`cs_calibration_unified.R` with attribution comments); Type-S/M metric logic
(`power_simulation_cs.R`); batching pattern (`power_simulation_twfe_...fixed.R`).

## 17. Required tests (testthat)

Blinded loader never returns treated/anticipation rows; zero imposed effect leaves outcomes
identical; pseudo-treatment constant within state; cohort counts preserved (D1) / structure
reported (D2/D4); no assignment without min_pre/min_post support; TWFE recovers a known effect
in a toy panel (tolerance by simulation SE); null size ≈ α in a known-DGP toy test; count
augmentation returns nonnegative integers; same seed → identical schedule and injected outcome;
serial ≡ parallel results; estimator failures logged not dropped; forbidden-path guard blocks
`output/` and `figures/` reads.

## 18. Out of scope (recorded)

- The expanded-panel states (MD/OR/NH/IL post-treatment-only sources) are excluded from
  calibration by construction (audit F12); MI-annual is not integrated in this iteration.
- Propensity-score-based pseudo-assignment (Athey et al. 2025-style confounded assignment) is
  noted as a possible extension; the primary designs use risk-set-respecting random assignment.
- Handle-intensity heterogeneity uses a synthetic maturation curve, not realized handle merged
  to outcomes (blindness: realized handle exists only post-treatment).
