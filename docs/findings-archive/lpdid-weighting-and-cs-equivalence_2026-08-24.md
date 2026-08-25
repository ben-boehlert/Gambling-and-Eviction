> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### LP-DiD REWEIGHTING WAS WRONG — EVERY LP-DiD NUMBER BELOW IS ON A THIRD ESTIMAND (2026-08-24)

`.re_lpdid` weighted stacked cells by `1/Var_cell(D)` and called the result an
equally-weighted ATT. It is neither of the paper's two estimands. By
Frisch-Waugh-Lovell a cell-FE regression of `dy` on `D` contributes each cell's
own DiD with weight `w_c * N_c * Var_c(D)`, so:

| observation weight | cell weight | estimand |
|---|---|---|
| `1` | `N_c Var_c(D)` | VWATT — the Cengiz et al. (2019) stacked regression |
| `1/(1 - Dbar_c)` | `N_treated,c` | **EWATT — Dube, Girardi, Jordà & Taylor §2.5.2** |
| `1/Var_c(D)` | `N_c` | **neither — what this repo actually ran** |

The old scheme weights each cell by its TOTAL size (switchers + surviving clean
controls), over-weighting early cohorts and short horizons where the
clean-control pool is largest. All three are convex combinations of
cell-specific DiDs, so nothing was BIASED under parallel trends — but the
reported estimand was mislabelled, and it is not the one the paper proves equal
to CS. Fixed in `run_estimators.R` (`.re_lpdid_weights`) and
`analysis/main/lpdid_statepanel.R` (`lpdid_cell_weights`).

**Consequence: every LP-DiD size and MDE figure in the sections below —
shift12 6.3%, ramp75 7.1%, all 7 gates, LDAM, `lpdid_statepanel.R` outputs —
was computed on the `cellsize` estimand.**

**Corrected shift12 re-runs (NV-free, gate 2,000 reps / MDE 300 reps × 13 δ,
2026-08-24; `lpdid_shift12_{gate,mde}_ewatt`):**

| window | inference | size cellsize → ewatt | SE/SD | MDE cellsize → ewatt |
|---|---|---|---|---|
| spliced | analytic | 0.087 → **0.145 FAIL** | 1.00 → 0.67 | 0.052 → 0.096 (n/a, fails gate) |
| spliced | **wild** | 0.058 → **0.033 PASS** | 1.00 → 0.67 | **0.063 → 0.115** |
| postcovid | analytic | 0.063 → **0.115 FAIL** | 0.98 → 0.81 | 0.209 → 0.221 |
| postcovid | wild | 0.054 → 0.071 pass | 0.98 → 0.81 | 0.236 → 0.240 |

TWFE unchanged within MC noise in every cell (0.14–0.17 MDE) — the check that
only the LP-DiD knob moved. NOTE the runs are NOT rep-paired despite the shared
base_seed (seed_rep includes the scenario-hash offset and `lpdid_weights` is
hashed); TWFE's stability is the pairing check.

**Why the correction HURTS: EWATT ≈ CS, so it inherits CS's miscalibration.**
Equal weight per treated unit puts full weight on late cohorts and long
horizons with thin clean-control pools; estimand SD jumps 2.3× (0.022 → 0.050
spliced) and the analytic clustered SE does not track it. The accidental
`cellsize` weighting had been down-weighting exactly those noisy cells — a
quasi-variance-weighting that is why it looked so well calibrated. This is the
estimand-vs-inference trade-off, now explicit.

**Corrected headline state spec: shift12 + LP-DiD(ewatt) + wild bootstrap,
spliced, NV-free — size 0.033, MDE 11.5% (CI 10.2–12.5%), not 6.3%.** The
6.3% figure is dead: it was the mislabelled estimand. If 11.5% is too weak, the
pre-registrable alternatives are (a) `vwatt` or (b) TWFE (size-valid both
windows, MDE ~0.16). Choosing vwatt/TWFE for power is defensible
pre-registration; relabelling cellsize as EWATT was not.

**vwatt gate (2,000 reps, `lpdid_shift12_gate_vwatt`): wild PASSES both
windows** — spliced 0.0515, postcovid 0.0615; analytic 0.097/0.087 (fails
spliced, borderline postcovid); SE/SD 1.14. Estimand SD 0.040, between
cellsize (0.022) and ewatt (0.050).

**vwatt MDE (`lpdid_shift12_mde_vwatt`, 300 reps × 13 δ): spliced wild
0.0875 (CI 8.3–9.1%)**; spliced analytic 0.075 (borderline gate, don't
lead with it); postcovid 0.32–0.37 (the thin postcovid design is hostile
to variance weighting — do not use vwatt there).

**Final PAP decision table (shift12, NV-free, spliced, size-valid arms):**

| arm | size (2,000 reps) | MDE | estimand |
|---|---|---|---|
| LP-DiD vwatt + wild | 0.0515 | **0.0875** | variance-weighted (Cengiz stack) |
| LP-DiD ewatt + wild | 0.0325 | 0.115 | equally-weighted ATT (= CS's) |
| TWFE analytic | 0.0495 | 0.165 | TWFE pooled |

Both LP-DiD arms are honest; pick by which estimand the PAP wants to
defend — vwatt buys ~24% MDE by down-weighting thin cells (a property of
the design, defensible if stated), ewatt matches the CS estimand the
literature reports. The dead 6.3% sat between them because the cellsize
weights were an accidental hybrid.

**New config knobs**, both plumbed config → grid → spec → estimator:
- `lpdid_weights`: `ewatt` (new default) | `cellsize` (pre-fix) | `vwatt`
- `lpdid_pmd`: base-period width, default 3 (was hard-wired, never plumbed)

`lpdid_weights` **inverts** the usual conditional-hash rule — the new default is
hashed, `cellsize` is not — because here the DEFAULT changed behavior. Post-fix
runs land on new scenario ids and cannot silently pool with pre-fix partials;
`lpdid_weights: cellsize` still reproduces the old ids bit-for-bit. Verified:
`Se4ad20df56` → `Sdc1ca7a0b5` on the shift12 spliced cell.

### THE CS EQUIVALENCE IS REAL, BUT NEEDS A CONTIGUOUS PANEL (2026-08-24)

DGJT footnote 23: with no covariates, binary absorbing treatment, and only
not-yet-treated controls, **reweighted FIRST-LAG LP-DiD is numerically
equivalent to CS at every h ≥ 0** — point estimates only, and the paper says
explicitly it does not extend to pre-trends. Confirmed here to machine
precision, and it is the independent proof the weighting fix was right
(`tests/testthat/test-estimators.R`), max |LP-DiD − CS| over h = 0..8:

| arm | diff | |
|---|---|---|
| `ewatt` + `pmd 1` | **2.2e-16** | the equivalence |
| `vwatt` + `pmd 1` | 1.7e-03 | variance-weighted |
| `cellsize` + `pmd 1` | 2.1e-02 | **the pre-fix weights** |
| `ewatt` + `pmd 3` | 2.3e-02 | pre-mean-differenced (the BJS-ish variant) |

2.1e-02 against an imposed 0.20 is a 10% relative error — the old weighting was
not a rounding matter.

**But it breaks on our panel, and balance is not why.** Controlled
decomposition (`analysis/diagnostics/lpdid_cs_equivalence.R`):

| toy design | max diff | |
|---|---|---|
| A. balanced, contiguous | 2.2e-16 | holds |
| B. unbalanced, staggered entry | 7.8e-16 | **holds** |
| C. balanced but a 7-month interior hole | 1.1e-01 | **BREAKS** |

**An interior TIME GAP breaks it; unbalancedness does not.** Mechanism:
`.re_prep()` hands `did::att_gt` a CONSECUTIVE rank index
(`t_c <- match(month_date, months)`), collapsing every hole — so CS treats the
month before the COVID splice and the month after as adjacent. `.re_lpdid`
indexes true calendar months and refuses to bridge, by design.

Not a corner case here: the S2 state panel has **8 states with interior holes
(84 months) on covid-keep and 19 states with 360 on covid-drop**, on top of the
25-month splice. Real-panel results track the toy: on the near-contiguous keep
window `ewatt`+`pmd 1` is the closest arm (median |diff| 0.0097, max 0.090); on
the spliced window the ordering dissolves (all arms 0.26–0.32).

**Two consequences.** (1) For the PAP: on this panel LP-DiD and CS are NOT
numerically identical — first-lag reweighted LP-DiD is only the closest arm; do
not claim the equivalence without the contiguity caveat. (2) **Wider and
unresolved: every CS run in this framework differences across the COVID hole as
though it were one month.** That is independent of LP-DiD and needs its own
investigation — it may be part of why CS calibration is so much worse on
spliced windows than post-COVID ones (see the time-aggregation memo, which
reached the same "splice is the problem" conclusion from the size side).

**Also relevant and unused:** DGJT's Simulation 2 shows LP-DiD beating CS/SA/BJS
only because it adds **one lag of Δy as a control**, which the regression form
permits and the others do not. `.re_lpdid` fits `dy ~ D_treat | cell` with no
covariates, so we are not using the feature the paper sells.


