# Poverty DDD: Power Analysis — FINAL (500 reps)

**Date:** 2026-08-21 · **Status:** FINAL for this specification.
500 reps x 7 deltas x 2 DGPs x 2 COVID windows, 500/500 feasible in both arms.
Outputs: `output/ddd_power/main/`.

> **Bottom line: the DDD does NOT buy precision here, and its apparent COVID
> robustness is largely a SIZE FAILURE, not power.** The TWFE DiD passes the
> size gate in both windows; the DDD fails both. See section 3.

## The design tested

    Y_cst = alpha_c + lambda_st + gamma_t*H_c + beta*(D_st x H_c) + eps_cst

county FE + state x month FE + poverty-group x month FE; H_c = fixed
within-state median split of county `poverty_rate`; cluster by state.
beta identifies **tau_high - tau_low**, not the ATT.

Code: `R/power/ddd_power.R`, `analysis/power/run_ddd_power.R`,
`analysis/diagnostics/ddd_covid_gap_stability.R`.
Blinded per POWER_SIMULATION_BLINDNESS_PROTOCOL.md (untreated county-months
only, D1 panel-template pseudo-schedules, count_nb DGP, base seed 20260723).

## 1. The design is feasible (verified)

- 1,226 counties / **27 states retain a within-state high-low contrast**
  (only KS and MS drop, each having 1 county in ETS). 57,382 county-months
  with COVID dropped; 64,939 with it kept.
- Estimator is unbiased on the differential: injected delta = 0.10 returned
  beta-hat = 0.0995 (SE 0.040).
- Schedule placement feasible 500/500 reps (contrast: national-template D1 is
  deterministically INfeasible on county/S2 — see CLAUDE.md).
- **Placebo passes:** a uniform effect (delta_high = delta_low) returns
  DDD beta-hat ~ 0 at every delta up to 0.20. The design does not manufacture
  a differential out of a level effect.

## 2. COVID diagnostic — the main substantive result (COMPLETE, 500-rep-independent)

Untreated county-months only. SD across state-months of (a) the state-level
mean log filings and (b) the within-state high-low gap:

| Era | SD state level | SD high-low gap | gap / level |
|---|---|---|---|
| Non-COVID | 0.184 | 0.266 | 1.45 |
| COVID window | 0.549 | 0.401 | 0.73 |

**Two-sided verdict.**
- The DDD's promise is real but PARTIAL: COVID inflates the state-level shock
  **3.0x** (0.184 -> 0.549) but the high-low gap only **1.5x** (0.266 -> 0.401).
  state x month FE remove the larger problem.
- The DDD is NOT immune. Cross-state dispersion of the gap rises 0.215 -> 0.350
  (**+63%**) in the COVID window. COVID *did* move the high-low gap, and moved
  it differently across states — exactly the Olden-Moen failure mode. The
  identifying assumption is weakened, not satisfied, during the pandemic.
- **The DDD is not free in normal times:** outside COVID the gap is 1.45x
  NOISIER than the state level. Differencing two county groups amplifies noise.
  You buy COVID robustness by paying a variance penalty in calm periods.

## 3. Power and size — FINAL (500 reps)

### Size gate at delta = 0 (nominal 5%) — the decisive table

| COVID window | Estimator | Rejection | SE/SD | Null bias | Verdict |
|---|---|---|---|---|---|
| dropped | DDD | **7.6%** | 0.954 | **+0.0156** | FAIL (marginal) |
| dropped | TWFE DiD | 5.6% | 0.913 | +0.0046 | PASS |
| kept | DDD | **10.2%** | 0.896 | -0.0036 | **FAIL** |
| kept | TWFE DiD | 5.2% | 0.966 | -0.0057 | PASS |

### MDE-80, each estimator on its own estimand

| COVID window | DDD (tau_high - tau_low) | TWFE DiD (average effect) |
|---|---|---|
| dropped | 6.7% *(size-invalid)* | **6.9%** (size-valid) |
| kept | 7.5% *(size-invalid)* | **9.9%** (size-valid) |

**Reading.** With COVID dropped the DDD's MDE (6.7%) and the DiD's (6.9%) are a
wash — and the DDD's is *optimistic* because it over-rejects. With COVID kept
the DDD looks far better than the DiD (7.5% vs 9.9%), but it rejects a true
null 10.2% of the time. That gap is over-rejection, not power. **No DDD MDE in
this table is currently defensible.**

The DDD is therefore NOT a precision upgrade over the plain DiD. Its case must
rest on being a different, mechanism-relevant estimand (tau_high - tau_low) and
on its robustness argument — not on statistical power.

### Two distinct failures, requiring different fixes

**(a) SE understatement (inference).** SE/SD = 0.896 in the kept-COVID arm:
cluster-robust SEs at 27-28 clusters are ~10% too small. A wild cluster
bootstrap is the standard fix and is untested here. This is the tractable half.

**(b) Null bias (design) — a bootstrap will NOT fix this.** With COVID dropped
the DDD returns **+0.0156** under a true null (t ~ 11.7 across 500 reps; ~23% of
the MDE). Randomly placed pseudo-treatment on real untreated data produces a
spurious positive high-low differential. Because the D1 panel template assigns
the REAL treated states, this says treated states' high-low gaps drift relative
to control states' gaps. That is a substantive warning about the design, not a
software artifact.

## 3b. log1p distortion generates a SPURIOUS poverty differential (new finding)

The placebo is well-behaved with COVID dropped but **drifts with COVID kept**: a
strictly uniform effect yields DDD estimates trending to **-0.0189** at
delta = 0.20, with rejection climbing 10.2% -> **18.0%**.

Mechanism confirmed. High-poverty counties are systematically **smaller**:

| H | median filings | share < 10 filings | mean renters |
|---|---|---|---|
| low poverty | 14 | 41.4% | 19,912 |
| high poverty | 7 | 56.7% | 11,513 |

log1p compresses proportional changes at small counts, so a uniform effect *in
counts* registers as a **smaller log-point effect in high-poverty counties** —
a mechanical negative differential. This applies to **any log1p county-level
poverty split, not just this DDD.** It biases toward finding *smaller* effects
in poor counties, i.e. against the Hollenbeck-style hypothesis, so it is
conservative for that hypothesis — but it is a bias, and it inflates size.

Corroborating signature: in the differential DGP the bias *falls* as delta rises
(+0.0156 at delta=0 -> +0.0044 at delta=0.20), the same compression pulling the
other way. Fix by testing `y_lograte` / `asinh`, or restricting to counties
above a minimum filing count.

## 4. Interpretation anchor

The repo's existing poverty split (`output/border_diagnostic/hollenbeck_style/`)
gives high-poverty +9.7% vs low-poverty -0.1% — a **~9.8pp differential**, above
the ~6.7-7.5% DDD MDE. So the design is plausibly powered for the differential
these data suggest, *if* the size and bias problems are fixed. It is powerless
by construction if gambling effects are uniform across poverty.

## 5. Required before this is citable

1. **Wild cluster bootstrap** for the DDD (fixes SE/SD 0.896; use `fe = "id"` —
   see the CLAUDE.md boottest memory-bomb lesson). Will NOT fix item 2.
2. **Diagnose the +0.0156 null bias.** Run design D4 (never-treated controls)
   and a random-state template to separate "real treated states have drifting
   gaps" from "any placement does this."
3. **Re-run on `y_lograte` / `asinh`** to confirm the section 3b distortion is a
   log1p artifact and not the design.
4. **`poverty_rate` vintage is UNVERIFIED** — time-invariant in the ETS county
   file, no codebook in-repo. The spec needs H measured PRE-treatment; a
   2019-2023 ACS vintage is post-treatment for early legalizers.
5. **Pre-trend event study on the high-low gap** — section 2 shows the gap is
   not automatically stable. Mandatory, not optional.
6. County composition churn (CLAUDE.md: FL/TN/TX baskets change 2024).
