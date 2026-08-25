# Cheap Staged Power Simulation — Methodology Notes

**Created:** 2026-08-12 · **Scripts:** `analysis/cheap_sims/00_common.R` … `04_jackknife_diag.R`
**Outputs:** `output/cheap_power_sim/` (smoke runs in `output/cheap_power_sim/smoke/`)
**Plan:** `quality_reports/plans/2026-08-12_cheap-staged-sim-framework.md`

Purpose: cheaply determine whether the C&S staggered design is viable — test size
under a true zero, power under plausible ramped effects, and where identification
comes from (COVID-crossing vs clean comparisons) — before any expensive suite.

## Data used

- **Outcomes:** `data/raw/state_month_panel_with_treatment.csv`, state-month
  eviction filings, floored at 2016-01 (4 states carry legacy pre-2016 history).
  Outcome scale: `y_log1p = log(1 + filings_count)` (project baseline).
- **Treatment:** `online_start_date` from the **repaired**
  `data/raw/sports_gambling_legalization_dates.csv` (commit `2be0bd0`). The
  `treat_start` column embedded in the panel CSV is stale and never used.
- **Gambling intensity:** `data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv`
  (monthly Handle by state, June 2018+).

## Exclusions and repairs

- **Nevada:** hard-excluded everywhere. NV is absent from the schedule CSV, so any
  "never-treated = not in schedule" derivation silently miscodes it; it is
  online-treated before the post-PASPA era and belongs in neither treatment nor
  control.
- **Maine:** included (court-source repair 2026-07-23; online Nov 2023 ⇒ treated).
  Note this diverges from `R/power/load_blinded_panel.R`, which still drops ME.
- **Treated-without-post-data:** states whose outcome coverage ends before their
  online date (NC: coverage → 2023-06 vs online 2024-03; MO: online 2025-12,
  post-panel) are correctly *not-yet-treated in-sample*: they contribute control
  months, never treated cells, and are excluded from the placebo cohort template.
- **Idaho:** retained (monthly panel; the known ID data-quality exclusion applies
  to annual analyses).

## COVID definition

Baseline window **2020-03-01 … 2021-07-31, months dropped** — the blinded power
framework's protocol default (`R/power/config.R`); env-overridable
(`CHEAP_COVID_START/END`). Note other project artifacts used 2020-03…2022-03
(calibration scripts) and 2020-03…2021-06 (quintile-timing); sensitivity to the
cutoff is deliberately deferred (one definition, easy to change).

Cell classification (single-fit decomposition): for a post cell ATT(g,t) under
`base_period="varying"`, `anticipation=0`, the identifying comparison is base
month g−1 → outcome month t, so with COVID months dropped:

- `clean_pre` — outcome month before COVID start;
- `clean_post` — base month after COVID end;
- `cross` — base before COVID start, outcome after COVID end.

Designs are aggregations of these cell sets from ONE fit per rep: `full` (1A/3C),
`covid_clean` (1B/3D), `pre_covid` (3A), `post_covid` (3B), `cross_covid` (1C).
Under varying base + not-yet-treated controls these subset estimates are
numerically identical to sample-restricted re-estimation, at ~1/4 the compute.
A cohort dated *inside* the dropped window maps to the first observed month after
the gap (its base is the last pre-COVID month ⇒ classified `cross`, correctly).

## Untreated ("blinded") simulation panel

Black–Hollingsworth–Nunes–Simon style: real outcome histories perturbed with
known effects. Every state is censored at `first_start_date − 6` months
(anticipation floor, protocol §4), so all simulated outcomes are actually
untreated data; real serial correlation, missingness, calendar shocks (incl.
COVID), and coverage raggedness are preserved (Burlig–Preonas–Woerman point).

## Placebo assignment (calendar-preserving)

`make_calendar_placebo()`: the template is the **real online cohort calendar**
(20 cohorts, 22 state slots — treated states with observed post data). Dates are
held **fixed on the calendar** (unlike D1's anchor-shift, which would break
COVID alignment — here COVID alignment is the object of study). States eligible
for date d must observe ≥12 non-COVID months before d, ≥6 at/after d, and a base
month within 3 months before d. Cohorts fill scarcest-first without replacement;
unfillable slots are dropped and logged. In practice 18/22 slots fill; the
seed-invariant 4 dropped slots are mid-COVID/thin-control cohorts (2020-11,
2021-01, 2021-09, one of the two 2022-01 slots) — itself evidence about control
scarcity in the real design.

**Known placebo↔real divergence (documented, inherent to untreated-data
placebos):** cross-COVID cell support is thinner in the placebo world (≈3
cohorts) than in the real design (≈8 pre/mid-COVID cohorts), because a state can
host a pre-COVID pseudo date *and* supply post-COVID outcomes only if its real
treatment is late. Sim 1C's cross-COVID size estimate therefore rests on fewer
cells than the real design's cross-COVID share — treat it as indicative.

## Treatment-effect DGP

- **Injection mechanism:** `count_nb` (NegBin augmentation/thinning,
  var/mean θ = 1.4 — framework default). δ = 0 is a pure pass-through of the
  real data.
- **Ramp (Sim 2):** exposure_s(e) = Handle_s(month at online-event-time e) /
  mature_s, where **mature_s = the state's peak monthly Handle excluding the
  COVID window** — the definition settled in
  `analysis/exploratory/quintile_timing_analysis.R` (same work that calibrated
  `intensity_ramp`'s τ). Capped at 1 (only COVID months can exceed the non-COVID
  peak); interior gaps linearly interpolated; e<0 ⇒ 0. Monthly seasonality is
  deliberately kept. Population cancels in the normalization, so no per-capita
  series is needed. Pseudo-treated states draw **donor profiles** (seeded,
  without replacement) from the 28 real online states with handle data; beyond a
  donor's observed horizon, exposure holds at the donor's trailing-6-month mean.
  Imposed effect: δ_ist = δ_mature × exposure(e − lag). This is a simulation
  DGP, not a claim that observed handle is exogenous.
- **Outcome lag (Sim 2B):** identical, with lag = 6 months.
- **Step diagnostic:** `impose_effect(shape="step")` — full effect at e ≥ 0,
  used only to quantify how much the realistic ramp dilutes power.
- **Grid:** ramp lag0 δ ∈ {0, 1%, 2.5%, 5%}; ramp lag6 and step δ ∈ {1%, 2.5%, 5%}
  (log-point ≈ proportional effects on filings).
- **true_att:** each design's estimand truth is the cell-weighted mean of imposed
  δ over that design's realized (g,t) cells — bias/coverage/exaggeration target
  the design's own estimand, and the ramp's dose dilution is visible as
  true_att < δ_mature.

## Estimator (matches the authoritative project spec)

`did::att_gt`: `control_group="notyettreated"`, `est_method="reg"`,
`base_period="varying"`, `anticipation=0`, `faster_mode=FALSE` (TRUE errors on
this design), `xformla=~1`, panel unbalanced allowed. Inference: analytic
influence-function SE, t(n_states − 1) (as in `R/power/run_estimators.R`).
Subset aggregates replicate `did::aggte(type="simple")` exactly — weights
w_k ∝ P(G=g_k) **including the weight-estimation influence term (wif)**;
validated: full-design subset aggregate ≡ did's simple aggregate (att diff
~1e-16, SE ratio 1.00000).

**Differences from the real estimator:** none in the estimation call; the only
difference is that designs other than `full` are cell-subset aggregations that
the standard `aggte` types don't expose.

## Seeds / reproducibility

`seed_rep = 20260723 + 10007·rep + 101·scenario`, scenario 902 (901 = the CV3
calibration; shared base seed pairs panels across framework runs). One placebo
schedule per rep, shared across all DGP cells; injection seeds offset by DGP row.
All randomness is R-side and seeded; `att_gt(bstrap=FALSE)` is deterministic.

## Sim 4 (CV3 jackknife)

Rejection-rate question already answered by
`data/output/cs_cv3_calibration/state/` (200 null reps, D1 schedules): CS
analytic 21.5% / bootstrap 24.5% rejection at nominal 5%; **CV3 0.5% rejection,
SE/SD 1.24 — over-corrects**; did2s 31% (state level). `04_jackknife_diag.R`
adds the estimand-integrity anatomy KNMW warn about for singleton cohorts:
per delete-one-state replicate, disappearing ATT(g,t) cells, lost weight share,
weight shifts on shared cells (placebo world, paired seeds), and the unblinded
real-data LOSO influence plot.

## Verification pass (2026-08-12, rev. 2)

- `05_oracle_power.R`: oracle-inference power/MDE from the empirical MC
  distribution of the ATT (empirical size-corrected critical values + normal
  approximation). Separates bad inference from lack of information. Result:
  oracle 80% MDE ≈ 0.86 (full) / 0.41 (pre-COVID) mature-scale — information
  deficit is terminal regardless of SE method.
- `06_placebo_interrogation.R`: exchangeability audit of the placebo generator
  (eligibility matrix, empirical assignment probabilities vs equal-among-
  eligible, host-type composition by calendar era, untreated trajectory check,
  and a 250-rep balanced common-support null on AK/GA/MN/OK/TX/UT with fully
  exchangeable assignment). Result: the first-pass "+0.67 cross-COVID placebo
  bias" was a generator composition artifact (pre-COVID pseudo-dates hosted 5%
  by never-treated states; cross cells ~87% from real-late-treated states with
  wildly dispersed post-COVID trajectories); the balanced exchangeable null is
  mean-zero in every calendar class (cross mean −0.022, MC-SE 0.028). What
  survives: cross-cell noise (SD 0.35–0.44) and a few-cluster SE problem in
  the 6-state world (SE/SD ≈ 0.65).

## Unresolved methodological issues

1. RESOLVED in rev. 2: the placebo cross-COVID "bias" was generator sorting,
   not design bias (see verification pass above). The durable caveat is that
   calendar-preserving placebo assignment on this panel is inherently
   non-exchangeable — report exchangeability diagnostics with any placebo rate.
2. Analytic SEs at 38 clusters ignore few-cluster refinements; wild bootstrap
   exists for TWFE but not CS. CV3 is the candidate fix and over-corrects
   (estimand-composition variance; quantified in `jackknife/`).
3. Subset aggregates treat cohort-share weights as estimated (did convention)
   even though state cohort sizes are fixed by design — conservative.
4. COVID-window sensitivity (single baseline definition) deferred.
5. The panel's ragged late edge (states end 2023-06…2025-11) interacts with
   late-cohort support; not separately varied.
6. Placebos on untreated data cannot detect endogenous-adoption bias; late
   adopters are the most trajectory-heterogeneous group in the panel.
