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

### ⚠ Null-bias caveat (new, 2026-08-25)

Every state arm's δ=0 mean estimate is **positive**: the pseudo-null distribution is not centered at zero on this design. For **vwatt the bias is +0.042 — 1.06× its own SD and ~48% of its 0.0875 MDE**; wild inference recenters under the null, which is why the size gate passes anyway. Consequences: (a) the measured power curve — and hence the MDE — is shifted by the bias for positive δ; (b) a real-data point estimate near +0.04 on this spec would be indistinguishable from the design's null artifact. **Undiagnosed** (candidates: D1 placement interacting with post-COVID recovery trends; count_nb augmentation asymmetry) — see gap 6. The county CS analogue is already documented (null bias +0.101); the principle "size-valid ≠ unbiased" now provably applies to the state arms too.

## 2. County-level

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
2. **County did2s power never completed at production scale** — the county workhorse's MDE rests on older simulations outside the blinded framework.
3. **County LP-DiD abandoned** at batch 5/12 (`lpdid_mde_county`).
4. **TWFE staggered power sim stale** (pre-schedule-repair); its old headline MDE cannot be cited until re-run.
5. **TWFE postcovid is not size-valid** (0.078–0.097 across runs) — the postcovid window currently has only LP-DiD wild arms as size-valid options.
6. **NEW — diagnose the systematic positive null bias** (§1 caveat): +0.013 to +0.042 across all state arms, worst for vwatt (+1.06 SD). Candidate diagnostics: run the deterministic benchmark mechanism at δ=0; vary placement rule; check count_nb augmentation symmetry. Until diagnosed, report MDEs jointly with null bias in the PAP.
7. **`boundary_B_2022_08` unfinalized** — 3,501 reps of finished work awaiting an aggregation step.

---
Maintained with RUN_LEDGER.md — update both when a run adds or changes a cell. History: `docs/findings-archive/`. Results (quarantined from this doc): FINDINGS.md.
