# Sketch: Four-Quarters Dose-Response Spec on the Spliced Window

**Date:** 2026-08-19. **Status:** SKETCH — design for discussion, not yet
pre-registered; power validation not yet run.
**Anchor:** Goss & Mangrum (FRBNY SR 1184): keep *legalization* as treatment
timing, fix each state's exposure *dose* from handle in the early post-launch
window — early enough that the dose is not an artifact of the market's own
later growth path. Prior repo groundwork:
`quality_reports/handle_four_quarters_data_profile.md` (2026-08-14, window
definition) and `data/processed/gambling_exposure_index.csv`.

## 1. Motivation (what this buys over the alternatives just examined)

- Uses the **full spliced window** (2016-01..2025-11 ex COVID 2020-03..2021-07)
  — the design with 22+ treated clusters and the framework's best calibrated
  power (county did2s Type I 4.1%; state LP-DiD MDE 8.1–8.9%) — instead of the
  post-COVID window whose 4–7 treated clusters cap valid MDEs at 24–32%.
- Answers the *intensity* question the "COVID legalizers who ramped later"
  idea was reaching for, **without contaminated pre-periods**: timing stays at
  legalization, so every pre-treatment month is genuinely gambling-free.
- The dose never touches eviction outcomes and is fixed by launch+15 months.

## 2. Dose construction (built: `data/processed/fourq_dose_per_adult.csv`)

`D_s` = mean monthly Handle over the **four complete calendar quarters after
the launch quarter** (launch quarter dropped as transition — the 2026-08-14
audit's recommended definition), divided by state adult (18+) population.
Normalization is per adult, NOT per renter: the panel's renter counts cover
only ETS counties (0/NA for RI/LA/MA/MO); a statewide-ACS per-renter variant
is a sensitivity to build later.

Realized dose vector, 22 in-panel treated states with complete windows
($ handle per adult-month; terciles for the discrete design):

| T3 (high) | T2 (mid) | T1 (low) |
|---|---|---|
| MA 96, NY 92, AZ 84, MD 82, KS 74, OH 69, NC 67 | KY 64, LA 61, CO 51, VA 50, CT 46, TN 43, ME 40 | VT 34, IN 29, DE 24, NH 22, RI 22, PA 19, WV 10, AR 10 |

p25 $25.6 / median $47.9 / p75 $68.9 (IQR ratio 2.7); MO excluded (launch
2025-12, window incomplete). For COVID-era launchers (CO/TN/VA) the dose
window overlaps the dropped COVID *outcome* months — harmless: the splice
drops eviction months, not handle data.

**The key confound, visible on sight: dose is strongly increasing in launch
date.** Every 2022+ launcher except AR sits in T2–T3; every 2018–19 launcher
sits in T1 (later markets launch into a mature national industry — brands,
app penetration, marketing). Dose variation is therefore largely *cross-cohort*
variation, and our cohorts are singletons, so there is no within-cohort dose
contrast to lean on. This drives the design choices below.

## 3. Estimands

1. **Extensive margin** (unchanged headline): ATT of legalization on
   log1p(filings).
2. **Intensive margin, discrete (primary dose estimand):** ATT difference,
   top-tercile vs bottom-tercile dose states, at event horizons 0..24.
3. **Intensive margin, continuous (secondary):** per-dollar slope —
   d E[log1p filings] / d(D_s), reported per IQR move ($43/adult-month).

## 4. Estimating equations

**(a) Primary — tercile-cohort discrete design** (robust: stays inside the
binary-DiD world where the framework's calibration evidence applies):
run the existing calibrated estimators separately by dose tercile and
contrast them. County panel, state clustering:

    did2s / LP-DiD on {T3 treated + never-treated}  ->  ATT_T3
    did2s / LP-DiD on {T1 treated + never-treated}  ->  ATT_T1
    Dose effect = ATT_T3 - ATT_T1  (SE via the two-sample combination;
    wild-cluster bootstrap arm for LP-DiD already plumbed, lpdid_wild)

**(b) Secondary — continuous-dose LP-DiD:** extensive dummy plus dose slope,

    y_ct = a_c + l_t + sum_h [ b_h 1{t-g_s=h} + c_h 1{t-g_s=h} (D_s - D̄) ] + e_ct

  c_h is the per-dollar slope at horizon h. Causal interpretation of c_h needs
  **"strong parallel trends"** (Callaway, Goodman-Bacon & Sant'Anna 2024,
  continuous-treatment DiD): potential outcomes at every dose level trend in
  parallel — strictly stronger than the binary assumption, and untestable
  across doses. Report (b) as descriptive support for (a), not the headline.

**(c) Timing-confound control (required in both):** because dose ≈ f(launch
year), any secular difference between early and late cohorts loads onto the
dose term. Mitigations, in order of preference:
  - contrast (a) re-estimated on the **timing-overlapped subsample** (drop the
    four 2018–19 T1 states; T1 then = AR/DE/VT/2022+ launchers vs T3 2022+
    launchers — dose contrast with common calendar support);
  - dose residualized on launch date (linear) before terciling — report the
    reshuffled terciles as a robustness column;
  - event-time × launch-era (pre/post-2022) interactions in (b).

**(d) Placebo:** re-run (a)/(b) with dose assigned from the *national*
industry ramp at each state's launch date (the mechanical
industry-maturity component alone). If the "dose effect" survives with the
mechanical dose, it is timing, not gambling intensity.

## 5. Inference

State clusters (~22 treated / 14–15 never-treated on the spliced county
panel). Tercile subdesigns have ~7 treated clusters each — the county
post-COVID experience (analytic over-rejection at 4–5 treated clusters) says
**gate every arm before use**: did2s analytic may not survive at
7-treated-cluster tercile subsamples; `lpdid_wild` is the fallback with
demonstrated exact size. Anticipated cost: tercile ATTs will be noisier than
the pooled ATT by roughly √3.

## 6. Power validation plan (framework extension, prespecify before running)

1. New effect shape `dose_step` in `impose_effects.R`:
   δ_ist = δ · (D_s / D̄) for treated post cells (mean-one scaling keeps grid
   deltas interpretable as average effects), with the **realized dose vector**
   as the scaling. Blindness note to be added to the protocol: D_s derives
   from handle data only (never eviction outcomes), extending the dates-only
   precedent (ramp75, maturation50) to handle *levels*; design-doc §18 chose a
   synthetic curve for this in 2026-07 — using the realized vector is a
   deliberate, documented amendment, justified because the PAP now needs power
   for a dose estimand that is *defined* by that vector.
2. Size gate (δ=0) per estimator × arm on: pooled spliced county design, and
   the T3-only / T1-only subdesigns (the actual cluster counts of estimand 2).
3. Power/MDE for: pooled ATT under dose_step; the T3−T1 contrast (the dose
   estimand); and the continuous slope c̄ over horizons 0–12. MDE reported per
   IQR dose move and in filings/year terms.
4. Reuse base_seed 20260723; run ladder smoke → full per framework convention.

## 7. Open decisions (blocking pre-registration, not the sketch)

- Amend the blindness protocol for realized-dose scaling (§6.1) — yes/no.
- Per-renter dose variant: needs statewide ACS renter counts.
- NH: known −57% data artifact in prior work — NH sits in T1; decide exclusion
  before the tercile contrast is run (it moved headline results before).
- Whether estimand 2 uses did2s (calibrated county, analytic) or LP-DiD-wild
  as primary — decide by the §6.2 gate, not post hoc.
- DC has handle + launch (2020-05) but no eviction panel; excluded throughout.

---

# §6.2 SIZE-GATE RESULTS (run 2026-08-19, `output_blinded_power/dose_tercile_gates/`)

County spliced window, δ = 0, 300 reps per design, D1 panel template,
`exclude_states` axis (commit 691d6e5). Gate = reject@.05 ∈ [2.5%, 10%] and
failure ≤ 5%.

| Design (treated/control) | did2s analytic | lpdid analytic | **lpdid wild** |
|---|---|---|---|
| pooled dose sample (16/12) | 13.6% FAIL (SE/SD 0.63) | 8.0% pass | **3.7% PASS** |
| T3 high-dose (5/12) | 18.4% FAIL (+4.0% failures) | 21.3% FAIL | **3.0% PASS** |
| T1 low-dose (6/12) | 20.8% FAIL | 17.7% FAIL | **5.7% PASS** |

**Decision (per §7): the dose analysis runs on LP-DiD with wild-cluster
inference in all three designs.** Every analytic arm fails in the tercile
subdesigns (5–6 treated clusters — the same few-treated-cluster regime as the
county post-COVID gates); lpdid-wild is inside the gate everywhere. Null bias
≤ 0.01 in all cells.

**Flag for follow-up (independent of the dose spec):** did2s analytic FAILS
the pooled county spliced gate here (13.6%, SE/SD 0.63, 300 reps), whereas
the 2026-08-10 corrected-design smoke reported 4.1% / SE-SD 0.96 on 50 reps.
Differences: 6× the replications, FL excluded (16 vs 17 cohorts), same
schedule/template/mechanism. The smoke's 50-rep MC interval (~±6pp) can
almost cover 13.6%, but SE/SD 0.96 vs 0.63 cannot both be right. The standing
"did2s is the calibrated county workhorse" claim should be re-verified with a
300-rep no-exclusion gate (or the Della 500-rep cheap-run results, job
12248328) before the PAP cites it.
