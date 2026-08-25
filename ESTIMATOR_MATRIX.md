# ESTIMATOR_MATRIX.md — Estimators × Specs × Runs

The cross-cut view of [RUN_LEDGER.md](RUN_LEDGER.md): what has each estimator been run on, under which spec, and what came out. Numbers are the artifact-verified values from [FINDINGS.md](FINDINGS.md) and the 2026-08-25 audit; dead/superseded numbers are shown ~~struck~~ with their killer. Mortgage runs are parked and excluded (see RUN_LEDGER Open items).

Spec shorthand: **level** state/county · **window** spliced (2016–24, COVID dropped) / postcovid / keepcovid · **treat_def** online / shift12 (launch+12mo) / ramp75 / maturation50 · **NV** in/out of control pool · LP-DiD **weights** ewatt/vwatt/cellsize(retired).

---

## 1. Size gates & MDEs (blinded power framework, state level)

All state-level, `S2` panel, D1 pseudo-schedules, `count_nb` DGP. **Bold = on the live PAP decision path.**

| Estimator | Inference | treat_def | Window | NV | Weights | Size (δ=0) | MDE | Run(s) | Status |
|---|---|---|---|---|---|---:|---:|---|---|
| **LP-DiD** | **wild** | **shift12** | **spliced** | **out** | **vwatt** | **0.0515 PASS** (2,000 reps) | **0.0875** (CI 8.3–9.1%) | `lpdid_shift12_gate_vwatt`, `lpdid_shift12_mde_vwatt` | **LIVE — recommended spec** |
| **LP-DiD** | **wild** | **shift12** | **spliced** | **out** | **ewatt** | **0.0325 PASS** (2,000 reps) | **0.115** | `lpdid_shift12_gate_ewatt`, `lpdid_shift12_mde_ewatt` | **LIVE — CS-matching estimand** |
| **TWFE** | **analytic** | **shift12** | **spliced** | **out** | — | **0.0495 PASS** | **0.163–0.165** | TWFE arm of the shift12 runs | **LIVE** |
| LP-DiD | analytic | shift12 | spliced | out | ewatt | 0.145 FAIL | n/a | `lpdid_shift12_gate_ewatt` | LIVE (gate evidence: analytic disqualified) |
| LP-DiD | analytic | shift12 | spliced | out | vwatt | 0.097 borderline | 0.075 (don't lead) | `lpdid_shift12_gate_vwatt` | LIVE (gate evidence) |
| LP-DiD | wild | shift12 | postcovid | out | ewatt | 0.071 pass | 0.240 | shift12 ewatt runs | LIVE (thin 7/7 design) |
| LP-DiD | wild | shift12 | postcovid | out | vwatt | 0.0615 pass | 0.368 | shift12 vwatt runs | LIVE (vwatt hostile to thin designs) |
| LDAM | jackknife | online | spliced / keepcovid / postcovid | out | — | 0.037 / 0.030 / 0.010 PASS | **none run — open item** | `ldam_gate_noNV`, `_keepcovid_noNV`, `_postcovid_noNV` | LIVE (gate only) |
| LDAM | analytic | online | all 3 windows | out | — | 0.57–0.70 FAIL, SE/SD 0.18–0.27 | n/a | same runs | LIVE (verdict: never quote LDAM analytic) |
| LP-DiD | wild | shift12 | spliced | out | ~~cellsize~~ | ~~0.058~~ | ~~0.0628~~ | `lpdid_shift12_gate_noNV`, `_mde_noNV` | SUPERSEDED — dead estimand (2026-08-24 weights fix) |
| LP-DiD | wild | ramp75 | spliced | out | ~~cellsize~~ | ~~0.037~~ | ~~0.0707~~ | `lpdid_ramp75_gate_noNV`, `_mde_noNV` | SUPERSEDED — dead estimand + ramp75 vintage artifact |
| LP-DiD | analytic | ramp75 | spliced | out | ~~cellsize~~ | ~~0.073~~ | ~~0.0597~~ | `lpdid_ramp75_mde_noNV` | SUPERSEDED — same |
| LP-DiD | wild/analytic | online (raw) | spliced | out | ~~cellsize~~ | ~~0.103 analytic FAIL~~ | ~~0.0487 (artifact)~~ | `lpdid_gate_noNV`, `lpdid_mde_noNV`, `lpdid_wild_gate_noNV` | SUPERSEDED — raw online fails size; the lag (shift12) is what fixes it |
| LP-DiD | all | online | spliced/postcovid | **in** | ~~cellsize~~ | various | various | `lpdid_gate`, `lpdid_gate_postcovid`, `lpdid_mde`, `lpdid_wild_gate`, `lpdid_ramp75_*` (non-noNV), `lpdid_mde_fixedpanel` | CONTAMINATED — pre-rebuild panel and/or NV in controls |
| LDAM | both | online | all 3 windows | **in** | — | ~~0.67–0.71 analytic~~ | n/a | `ldam_gate`, `_keepcovid`, `_postcovid` | CONTAMINATED (NV) → superseded by `_noNV` trio |
| TWFE | analytic | online | postcovid | out | — | 0.097 FAIL | n/a | ramp75 noNV runs (TWFE arm) | Note: NV was masking TWFE's postcovid miscalibration |
| did2s | analytic | online | spliced | in | — | ~~0.23–0.29 FAIL~~ | n/a | pre-rebuild state cheap runs | CONTAMINATED (pre-rebuild) — but state did2s failed size in every vintage tested |

## 2. Size gates & MDEs (blinded framework, county level)

| Estimator | Inference | Window | Size (δ=0) | MDE | Run(s) | Status |
|---|---|---|---:|---:|---|---|
| **CS-DiD** | analytic | spliced | **0.612 FAIL** (SE/SD 0.23, coverage 39%) | n/a | `county_cs_adaptive` (250 reps, faster_mode=FALSE, safe patches) | **LIVE — CS eliminated** |
| **CS-DiD** | boot / boot_t | spliced | **0.044 / 0.032 PASS** but SE/SD ≈ 1.74 | **none exists** — power flat ≈5–7% through δ=0.20, `never_crosses_target` | `county_cs_adaptive` | **LIVE — no finite MDE; CI ≈ 2 log points** |
| did2s | analytic | spliced | 4.1% (smoke-scale) | full 500-rep county cheap run: Della job 12248328 | `smoke` (contaminated state cell; county cell ok), `cheap` incomplete | county did2s power never completed at scale — gap |
| LP-DiD | wild | spliced/postcovid | — | abandoned at batch 5/12, 7/30 | `lpdid_mde_county` | DEAD (never finished; only NV-free county LP-DiD arm ever attempted) |
| CS-DiD | analytic | spliced | ~~—~~ | ~~—~~ | `county_cs` (shift-mode partial) | SUPERSEDED — shift mode barred for CS by Opus review → adaptive grid |

## 3. Null-calibration tests (real design skeleton, δ=0)

| Estimator | Level | Size | SE/SD | Verdict | Run | Status |
|---|---|---:|---:|---|---|---|
| **did2s** | county | **4%** | **0.97** | **calibrated — county workhorse** | `cs_calibration_multi_county` | LIVE |
| TWFE | county | 8% | 0.95 | mildly anti-conservative; use wild | same | LIVE |
| didimputation | county | 14% | 0.73 | robustness only | same | LIVE |
| Sun-Abraham | county | 30% | 0.51 | broken — skip | same | LIVE |
| CS analytic | county | 0% | 2.46 | over-corrects — skip | same | LIVE |
| CS analytic | state | ~~14%~~ | ~~0.67~~ | superseded by county test; DGP contained the panel breaks | `cs_calibration_multi_estimator` (2026-04-09) | SUPERSEDED |
| Sun-Abraham | state | ~~21%~~ | ~~0.58~~ | same | same | SUPERSEDED |
| TWFE | state | ~~1%~~ | ~~1.14~~ | same | same | SUPERSEDED |
| CS analytic | state, postcovid monthly | 5.0% PASS | 1.06–1.14 | **the COVID splice, not cohort count, is what breaks CS** | `time_agg_covid_gates` | LIVE |
| CS analytic | state, spliced, month/quarter/year | 18.3% / 16.7% / 24.7% FAIL | — | time-aggregation does NOT fix CS | same | LIVE |

## 4. Real-data estimates (eviction)

| Estimator | Spec | Estimate | Run | Status |
|---|---|---|---|---|
| **CS-DiD** | state, 26 states (17T/9N), spliced, unconditional | **ATT +0.020 (SE 0.057)**, PT not rejected (Holm p 0.170) | `pretrends_lottery_A_baseline` | **LIVE — headline pretrends baseline** |
| CS-DiD | + lottery-legal binary covariate | ATT +0.048 (SE 0.055), Holm p 0.914 | `pretrends_lottery_C_binary` | LIVE (preferred conditional spec) |
| CS-DiD | + lottery vintage continuous | ATT +0.136 (SE 0.128) — SE blowup at thin e=−2,−1 | `pretrends_lottery_B_conditional` | LIVE (do not use continuous conditioning) |
| **did2s** | county, pre-COVID cohorts, excl. NH | **+9.1%** (coef +0.087, SE 0.045; CI −0.001 to +0.175 log points ≈ −0.1% to +19.1%) | `border_diagnostic` | **LIVE — exploratory signal, not the PAP headline** |
| 2×2 long diff | annual court panel, binary online-by-2022, pseudo-treatment era | MDE-80 = 0.2401 (+27%) under RI; CRVE fails size (8.4%); selection placebo passes (τ −0.30%, RI p 0.976) | `longdiff_2x2_pseudo`, `longdiff_2x2_selection` | LIVE — descriptive contrast only, underpowered |
| LP-DiD | state real-data event studies (ramp75/shift12 launch) | ~~all outputs~~ | `output/deprecated/lpdid_statepanel/` | CONTAMINATED — cellsize weights; re-run post-fix pending |
| LP-DiD vs CS | equivalence decomposition (toy + real) | ewatt+pmd1 ≡ CS to 2.2e-16 on contiguous panels; breaks on interior time gaps (COVID splice) | `lpdid_cs_equivalence{,_keep}`, `lpdid_weights_compare{,_mde}` | LIVE — the weighting-fix proof |
| CS-DiD (old) | pre-repair panels/schedules | ~~ATT +0.011 / −0.225 / +0.080 …~~ | `pretrends_statepanel_me_included`, `pretrends_rebuild_*`, etc. | CONTAMINATED / DEAD — see ledger |
| TWFE | staggered power sim, "MDE = 5%" | ~~5% at 80% power~~ | `data/output/twfe_power_out_2024_with_me` | STALE — pre-schedule-repair; re-run is an open item |

## 5. Coverage gaps visible in this matrix

1. **LDAM has gates but no MDE** — the only size-valid state arm missing from the MDE comparison.
2. **County did2s power never completed at production scale** (the `cheap`/Della county runs died); the county workhorse's MDE rests on the older border-diagnostic simulations.
3. **County LP-DiD was abandoned** (`lpdid_mde_county`, batch 5/12).
4. **No post-weights-fix real-data LP-DiD event study** — `lpdid_statepanel` outputs are all cellsize-era.
5. **TWFE staggered power sim stale** (schedule vintage).

---
Maintained with RUN_LEDGER.md: when a run adds or changes a cell here, update both. History: `docs/findings-archive/`.
