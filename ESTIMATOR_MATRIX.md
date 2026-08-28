# ESTIMATOR_MATRIX.md — Design Diagnostics for the PAP (Estimators × Specs × Runs)

**Results-free by design.** This document carries only pre-analysis design diagnostics — size, SE/SD calibration, null bias, coverage, MDE, pre-trends validity. Real-data treatment estimates are deliberately excluded to keep PAP spec choices blind; they live in [FINDINGS.md](FINDINGS.md) and [RUN_LEDGER.md](RUN_LEDGER.md). Mortgage arms are parked and excluded.

All numbers extracted directly from run artifacts (`oc_summary.csv` / `mde_table.csv` / `size_gate.csv`) on 2026-08-25. Spec shorthand: window **spliced** (2016–24, COVID dropped) / **postcovid** / **keepcovid**; treat_def **shift12** = launch+12mo (blind, no outcome data); **NV out** = Nevada excluded from controls; LP-DiD weights **ewatt** (equally-weighted ATT = CS's estimand) / **vwatt** (variance-weighted stack) / ~~cellsize~~ (retired).

---

## 1. State-level decision table (blinded framework; S2 / D1 / count_nb / y_log1p)

Gates are 2,000 reps; MDEs 300 reps × 13 δ. Decision rule: size gate first, MDE among survivors. **Bias = mean ATT-hat at δ=0** (pure null), from the 2,000-rep gate runs.

| Arm | Spec | Size (δ=0) | SE/SD | Null bias (÷SD) | Coverage | MDE-80 | Runs | Status |
|---|---|---:|---:|---:|---:|---:|---|---|
| **LP-DiD vwatt + wild** | shift12 · spliced · NV out | **0.0515 PASS** | 1.14 | **+0.042 (+1.06 SD)** ⚠ | n/a (wild) | **0.0875** (CI 8.3–9.1%) | `lpdid_shift12_gate_vwatt` · `_mde_vwatt` | LIVE — recommended, but see bias caveat |
| **LP-DiD ewatt + wild** | shift12 · spliced · NV out | **0.0325 PASS** | 0.67 | +0.013 (+0.27 SD) | n/a (wild) | **0.115** (CI 10.2–12.5%) | `lpdid_shift12_gate_ewatt` · `_mde_ewatt` | LIVE — CS-matching estimand |
| **TWFE analytic** | shift12 · spliced · NV out | **0.044–0.0495 PASS** | 1.02–1.04 | +0.021/+0.025 (+0.4 SD) | 0.951–0.956 | **0.163–0.165** | TWFE arm of shift12 runs | LIVE |
| LP-DiD ewatt analytic | shift12 · spliced · NV out | 0.145 FAIL | 0.67 | +0.013 | 0.855 | n/a — fails gate | `lpdid_shift12_gate_ewatt` | LIVE (disqualifies analytic arm) |
| LP-DiD vwatt analytic | shift12 · spliced · NV out | 0.097 borderline | 1.14 | +0.042 | 0.903 | 0.075 (don't lead) | `lpdid_shift12_gate_vwatt` | LIVE (gate evidence) |
| LP-DiD ewatt + wild | shift12 · postcovid · NV out | 0.071 pass | 0.81 | +0.038 (+0.62 SD) | n/a | 0.240 | shift12 ewatt runs | LIVE — thin 7T/7C design |
| LP-DiD vwatt + wild | shift12 · postcovid · NV out | 0.0615 pass | 0.84 | +0.029 | n/a | 0.368 | shift12 vwatt runs | LIVE — vwatt hostile to thin designs |
| TWFE analytic | shift12 · postcovid · NV out | 0.078–0.0845 marginal FAIL | 0.98–0.99 | +0.019 | 0.915–0.922 | — | shift12 runs | LIVE (postcovid TWFE not size-valid) |
| LDAM + jackknife | online · spliced / keep / postcovid · NV out | 0.037 / 0.030 / 0.010 PASS | 1.01 / 0.98 / 1.25 | +0.003 / +0.009 / **+0.042** | 0.963 / 0.970 / 0.990 | **no MDE run — open gap** | `ldam_gate*_noNV` | LIVE (gates only) |
| LDAM analytic | online · all 3 windows · NV out | 0.57–0.70 FAIL | 0.18–0.27 | same | 0.30–0.43 | n/a | same runs | never quote LDAM analytic |
| did2s analytic | online · spliced / keep / postcovid · NV out (state) | 0.153 / 0.110 / 0.273 FAIL | 0.77 / 0.82 / 0.64 | +0.037 / +0.011 / +0.020 | 0.847–0.890 | n/a | LDAM-gate runs (did2s arm) | **state did2s fails size in every window** |
| ~~LP-DiD cellsize~~ (all treat_defs) | various | ~~0.037–0.103~~ | — | — | — | ~~0.0487–0.0933~~ | `lpdid_gate*`, `lpdid_mde*`, `ramp75*`, `shift12*_noNV` | SUPERSEDED — dead estimand (2026-08-24) and/or CONTAMINATED (panel / NV vintage) |

### ⚠ Null-bias caveat — DIAGNOSED 2026-08-25

Every state arm's δ=0 mean estimate is **positive**: the pseudo-null distribution is not centered at zero. For **vwatt the bias is +0.042 — 1.06× its own SD and ~48% of its 0.0875 MDE**; wild inference recenters under the null, which is why the size gate passes anyway.

**Cause (memo: [`quality_reports/nullbias_decomposition_2026-08-25.md`](quality_reports/nullbias_decomposition_2026-08-25.md); placements regenerated from recorded seeds and verified to reproduce the recorded estimates to 2.8e-17): eligibility-constrained pseudo-treatment placement.** `.assign_cohorts()` fills scarcest cohorts first, which makes assignment non-exchangeable: a pseudo-treated state's adoption date is negatively correlated with its own real trend slope in **all 4,000 draws examined** — never positive. That skew explains 62–64% of TWFE's rep-to-rep bias variance (6–15% for LP-DiD, whose weighting adds state-identity heterogeneity in the same family); across its observed range the bias swings +0.07 → −0.05, wider than the mean bias itself. Ruled out: composition-break artifacts (the panel is fixed-basket — `basket_share` = 1 for every state-month, verified independently) and calendar timing (D1 cohort dates barely move; center-of-mass SD ≈ 0.8 months).

**Consequences for the PAP.** The δ=0 distribution is the design's *reference null*, not a zero. (a) Power curves and MDEs are shifted by the bias for positive δ; (b) a real-data estimate near +0.04 on the state vwatt spec would be indistinguishable from the design artifact. The defensible, pre-registrable fix is to **recenter/bias-correct the null before computing size and MDE** (or stratify the gate by eligibility skew) rather than assume unbiasedness — this would change every number in the decision table, so it is a decision for Ben, not a silent adjustment. Censoring "churn states" is a no-op on this panel and should not be pursued.

**Can it be fixed by resampling? No — tested 2026-08-26.** Randomizing the cohort fill order moves the date/trend correlation from −0.196 to −0.190; strict exchangeable (uniform) sampling is infeasible in 300/300 draws; common support is 7 states against 21 treated slots. The skew comes from the eligibility structure (pseudo-adoption date is pinned to coverage, corr 0.58), not from the fill heuristic — so **recentering is the correct handling, not a patch**, and the earlier "fix the placement instead" recommendation is withdrawn. Residual caveat for the PAP: the real adoption process shows no such skew (−0.078 / +0.215, both n.s.), so the simulated null still does not match the real assignment mechanism — declare it, don't silently correct it. Memo: [`quality_reports/placement_exchangeability_test_2026-08-26.md`](quality_reports/placement_exchangeability_test_2026-08-26.md).

**County comparison (§2): the bias shrinks ~3–4× but does not vanish** — consistent with a mechanism that enters through state-level placement and is diluted, not broken, by disaggregation.

## 2. County-level

**Shift12 county gate (NEW, 2026-08-25 — 2,000 reps, corrected weights, `lpdid_shift12_gate_county_vwatt` + `_ewatt`).** Run to test whether county estimation escapes the state arms' null bias. Wild was unavailable for the LP-DiD arm at county when these gates ran (boottest cannot do WLS with absorbed FEs), so LP-DiD is analytic-only in this table; the 2026-08-28 cell-scaled engine has since unlocked it — see the wild smoke block below.

| Arm | Window | Size (δ=0) | SE/SD | Null bias (÷SD) | Coverage | Clusters | Verdict |
|---|---|---:|---:|---:|---:|---:|---|
| **TWFE + wild** | spliced | **0.0410 PASS** | 0.92 | **+0.003 (+0.10 SD)** | — | 17T/12C | **the size-valid + near-unbiased county arm** |
| TWFE analytic | spliced | 0.0685 marginal | 0.92 | +0.003 | 0.931 | 17T/12C | use wild |
| LP-DiD vwatt analytic | spliced | 0.1510 FAIL | 0.77 | +0.012 (+0.36 SD) | 0.849 | 17T/12C | no size-valid inference at county yet |
| did2s analytic | spliced | 0.1112 FAIL | 0.65 | −0.004 (−0.08 SD) | 0.889 | 17T/12C | **fails size in-framework** (cf. 4% in the calibration harness) |
| LP-DiD **ewatt** analytic | spliced | 0.1720 FAIL | 0.66 | +0.007 (+0.16 SD) | — | 17T/12C | worse-calibrated than vwatt at county |
| did2s analytic (ewatt run) | spliced | 0.1205 FAIL | 0.63 | −0.002 (−0.05 SD) | — | 17T/12C | replicates the vwatt run's did2s failure |
| TWFE + wild (ewatt run) | spliced | 0.0490 PASS | 0.90 | +0.003 (+0.12 SD) | — | 17T/12C | TWFE stability check — matches the vwatt run within MC noise |
| **TWFE + wild** | postcovid | **0.0460 / 0.0440 PASS** | 0.68 | +0.003 (+0.03 SD) | — | 5T/9C | only size-valid arm in this window (vwatt / ewatt runs) |
| LP-DiD ewatt analytic | postcovid | 0.3055 FAIL | 0.52 | −0.007 (−0.04 SD) | 0.695 | 5T/9C | worst-calibrated cell measured |
| TWFE analytic | postcovid | 0.1610 FAIL | 0.68 | +0.003 | 0.839 | 5T/9C | — |
| LP-DiD vwatt analytic | postcovid | 0.2785 FAIL | 0.55 | +0.004 (+0.03 SD) | 0.722 | 5T/9C | thin design (5 treated states) |
| did2s analytic | postcovid | 0.2360 FAIL | 0.62 | −0.002 | 0.764 | 5T/9C | — |

Convergence: 2.4–2.5% did2s failures spliced / 0.9–1.1% postcovid (Lapack `dgesdd`); LP-DiD and TWFE 100% in all four scenario-runs.

**Both county configs are complete** (`_vwatt` and `_ewatt`, 2,000 reps × 2 windows each). Every county LP-DiD analytic cell fails size (0.151 / 0.172 spliced; 0.279 / 0.306 postcovid) with SE/SD 0.52–0.77; TWFE + wild passes all four (0.041–0.049).

**County LP-DiD wild SMOKE (2026-08-28 — 300 reps, lpdid-only, `lpdid_shift12_gate_county_{vwatt,ewatt}_wildsmoke`).** First runs of the county wild arm, enabled by the cell-scaled boottest engine (commit 8790c52: every LP-DiD weight scheme is cell-constant, so the WLS bootstraps exactly as √w-scaled OLS through boottest's `fe=` path; engine equivalence vs the legacy dummy path is unit-tested on enumerated draws). EXPLORATORY — MC SE ≈ 0.013 at p=0.05; a 300-rep smoke cannot classify against the 0.075 line:

| Arm | Window | Size (δ=0) | Analytic same-reps | Verdict |
|---|---|---:|---:|---|
| LP-DiD vwatt + wild | spliced | **0.033** | 0.187 | wild rescues size — consistent with the state pattern |
| LP-DiD ewatt + wild | spliced | **0.060** | 0.167 | near-nominal; too close to the 0.075 line to classify at 300 reps |
| LP-DiD vwatt + wild | postcovid | 0.103 | 0.290 | improves but likely still fails — 5 treated clusters |
| LP-DiD ewatt + wild | postcovid | 0.090 | 0.343 | same reading |

Wild converged 300/300 in all four cells; `base_seed` is shared with the 2,000-rep gates, so the analytic columns are the same simulated panels as those gates' first 300 reps (spliced analytic 0.187/0.167 vs 0.151/0.172 at 2,000 reps — consistent within MC noise). **Next step before citing:** promote the spliced cells to a 2,000-rep gate (flip `lpdid_wild: true` in the full-rep county configs under a fresh `run_name`).

**The null-bias 2×2 (LP-DiD, spliced, δ=0, 2,000 reps each).** Both axes reduce the bias, and they compound:

| | vwatt | ewatt |
|---|---:|---:|
| **state** | **+0.042 (+1.06 SD)** | +0.013 (+0.27 SD) |
| **county** | +0.012 (+0.36 SD) | **+0.007 (+0.16 SD)** |

State→county cuts it ~2–3.4×; vwatt→ewatt cuts it ~1.8–3.2×. The worst cell is the current recommended spec (state vwatt); the best is county ewatt — which has no usable inference arm, so it cannot be adopted on that basis alone. TWFE is stable across the two runs (+0.0027 vs +0.0032, size 0.0685 vs 0.0715), the intended check that only the LP-DiD knob moved (the runs are not rep-paired: `lpdid_weights` is hashed into `seed_rep`).

**Reading:** county estimation **cuts the null bias ~3–4× but does not remove the mechanism** — LP-DiD 1.06 SD → 0.36 SD, TWFE 0.4 SD → 0.10 SD, with the LP-DiD:TWFE bias ratio (~4×) preserved at both levels. Consistent with the decomposition: the bias enters through *state-level* pseudo-adoption placement, which county disaggregation dilutes but does not break. County's real advantage here is calibration (TWFE-wild is both size-valid and near-unbiased in both windows); its cost — no size-valid LP-DiD inference — is now provisionally lifted by the wild smoke above, pending the full-rep gate.

### Earlier county work

| Arm | Size (δ=0) | SE/SD | Null bias | MDE-80 | Runs | Status |
|---|---:|---:|---:|---:|---|---|
| CS-DiD analytic | **0.612 FAIL** (coverage 0.39) | 0.23 | +0.101 (t≈4.7) | n/a | `county_cs_adaptive` (250 reps, faster_mode=FALSE, safe patches) | LIVE — CS analytic eliminated |
| CS-DiD boot / boot_t | 0.044 / 0.032 PASS | ~1.74 (uncalibrated) | +0.101 | **none — power flat ≈5–7% through δ=0.20** (`never_crosses_target`; CI ≈ 2 log pts) | `county_cs_adaptive` | LIVE — CS eliminated on power |
| did2s analytic | 4.1% (smoke-scale only) | 0.96 | — | **never completed at production scale** | `smoke` county cell; `cheap` incomplete; Della 12248328 | open gap |
| LP-DiD wild | — | — | — | abandoned (batch 5/12, 7/30) | `lpdid_mde_county` | DEAD — only NV-free county LP-DiD attempt |

## 3. Null-calibration tests (real design skeleton, δ=0)

| Estimator | Level / window | Size | SE/SD | Verdict | Run | Status |
|---|---|---:|---:|---|---|---|
| **did2s** | county | **4%** | **0.97** | calibrated — county workhorse | `cs_calibration_multi_county` | LIVE |
| TWFE | county | 8% | 0.95 | mildly anti-conservative; use wild | same | LIVE |
| didimputation | county | 14% | 0.73 | robustness only | same | LIVE |
| Sun-Abraham | county | 30% | 0.51 | broken — skip | same | LIVE |
| CS analytic | county | 0% | 2.46 | over-corrects — skip | same | LIVE |
| CS analytic | state · postcovid monthly | 5.0% PASS | 1.06–1.14 | **the COVID splice, not cohort count, breaks CS** | `time_agg_covid_gates` | LIVE |
| CS analytic | state · spliced · month/qtr/year | 18.3 / 16.7 / 24.7% FAIL | — | time aggregation does not fix CS; CS null bias −0.20 to −0.58 on postcovid cells even where size passes | same | LIVE |
| CS / SunAb / TWFE | state (2026-04 harness) | ~~14 / 21 / 1%~~ | ~~0.67 / 0.58 / 1.14~~ | superseded by county test | `cs_calibration_multi_estimator` | SUPERSEDED |

## 4. Identification & design-validity diagnostics (no effect estimates)

| Check | Spec | Diagnostic | Run | Status |
|---|---|---|---|---|
| CS joint pre-trend test | state · 26 states (17T/9N) · spliced · unconditional | Holm p = 0.170 — PT not rejected; mean \|pre-ATT\| 0.0285, max 0.0689 | `pretrends_lottery_A_baseline` | LIVE baseline |
| CS joint pre-trend test | + lottery-legal **binary** covariate | Holm p = 0.914; mean \|pre-ATT\| 0.0285 (identical to unconditional), max 0.0648 | `pretrends_lottery_C_binary` | LIVE — preferred conditional spec |
| CS joint pre-trend test | + lottery vintage **continuous** | Holm p = 0.449 but SE blowup concentrated at thin cells e=−2,−1 (max \|pre-ATT\| 0.2308) | `pretrends_lottery_B_conditional` | LIVE — do **not** use continuous conditioning |
| Sun-Abraham pre-trends | same panel | no rejection (companion arm of the lottery runs) | same runs | LIVE |
| Selection-on-adoption placebo | annual court panel, eventual online legalizers vs never | RI p = 0.976 — no pre-treatment divergence | `longdiff_2x2_selection` | LIVE |
| 2×2 long-diff power | annual court panel · pseudo-treatment era | MDE-80 = 0.2401 (+27%) under RI; RI size exactly nominal (5.0%); CRVE FAILS size (8.4%); Type M 2–4× at small δ | `longdiff_2x2_pseudo` | LIVE — descriptive contrast only, underpowered |
| LP-DiD ≡ CS equivalence | toy + real decomposition | ewatt+pmd1 ≡ CS to 2.2e-16 on contiguous panels; an interior time gap (the COVID splice) breaks it — unbalancedness does not | `lpdid_cs_equivalence{,_keep}` · `lpdid_weights_compare{,_mde}` | LIVE — the weighting-fix proof |
| Era-variance inflation | matched-geometry window sweep | post/pre σ ratio ≈ 2.04 (NV-free); pre-era MDEs must be inflated accordingly; Idaho excluded (extreme in 100% of pre-era placements) | `longdiff_era_variance` (NV-free re-run) | LIVE |

## 5. Coverage gaps (the PAP to-do list this matrix exposes)

1. **LDAM has gates but no MDE** — the only size-valid state arm missing from the MDE comparison. If its jackknife MDE lands under 0.0875, the recommended spec changes.
2. **Wild-at-county for LP-DiD: BUILT 2026-08-28** (cell-scaled boottest engine, commit 8790c52; smoke: spliced wild 0.033 vwatt / 0.060 ewatt at 300 reps). Remaining gap: the 2,000-rep county wild gate has not run — the smoke is EXPLORATORY and cannot classify ewatt against the 0.075 line.
3. **County did2s power never completed at production scale** — the county workhorse's MDE rests on older simulations outside the blinded framework.
4. **County LP-DiD MDE still unrun** — the 2026-08-17 attempt was abandoned at batch 5/12 (`lpdid_mde_county`, online treat_def + retired weights); the new county gate is δ=0 only. Blocked behind gap 2 in any case.
5. **TWFE staggered power sim stale** (pre-schedule-repair); its old headline MDE cannot be cited until re-run.
6. **Postcovid window is inference-fragile.** At state, TWFE analytic is not size-valid (0.078–0.097), leaving only LP-DiD wild arms. At county, TWFE-wild IS size-valid in both windows (0.041 spliced / 0.046 postcovid) while every analytic arm fails badly (0.16–0.28).
7. **Null bias — diagnosed, unfixable by resampling, decision pending.** Cause is the eligibility structure (not the fill heuristic — tested 2026-08-26: exchangeable placement infeasible 300/300, common support 7 states vs 21 slots). **Open decision:** recenter the null before computing size/MDE — which is now the recommended handling and would raise MDEs by roughly the bias (vwatt ~0.0875 → ~0.13, likely reversing the vwatt-over-ewatt ranking) — vs. report MDEs alongside uncorrected bias.
8. **`boundary_B_2022_08` unfinalized** — 3,501 reps of finished work awaiting an aggregation step.

---
Maintained with RUN_LEDGER.md — update both when a run adds or changes a cell. History: `docs/findings-archive/`. Results (quarantined from this doc): FINDINGS.md.
