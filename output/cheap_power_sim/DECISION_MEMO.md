# Decision Memo — Cheap Staged Power Simulations (C&S state-panel design)

**Date:** 2026-08-12 (rev. 2 after verification pass) · **Author:** Claude (autonomous
session, Ben's spec of 2026-08-12; verification requests of same date)
**Inputs:** 250-rep calendar-preserving placebo Monte Carlo, Stage-0 audit, oracle-power
analysis, placebo-generator interrogation incl. 250-rep balanced exchangeable null,
real-data COVID decomposition + LOSO, prior 200-rep CV3 calibration.
**Method notes:** `analysis/cheap_sims/CHEAP_POWER_SIM_NOTES.md`. Effects in log points
on log(1+filings); "mature δ" = effect at full market maturity, imposed via each
state's observed handle ramp (average realized dose ≈ 0.41–0.46 of mature).

## Headline

The state-month C&S design is **not viable for plausible effect sizes, and the reason
is fundamental information deficit, not inference**. With a *perfectly calibrated*
oracle test, power against a 5% mature effect is ~7%, and the oracle 80% MDE is
**≈0.86 log points (mature scale) for the full design and ≈0.41 for its cleanest
(pre-COVID) slice** — 15–35× larger than plausible effects. No SE method (analytic,
bootstrap, CV3) can rescue that. Separately, the first-pass "+0.67 cross-COVID placebo
bias" did **not** survive interrogation: it is a placebo-generator composition artifact,
not evidence the actual ATT is biased — but cross-COVID comparisons remain 3–6× noisier
than clean ones and account for 42% of the real estimand's weight.

## Verification addendum (what changed in rev. 2)

**A. Oracle inference** (`oracle_power.csv`, `oracle_mde.csv`): using the empirical MC
distribution of the ATT with (i) empirical size-corrected critical values and (ii) a
normal approximation, per design:

| Design | Null SD of ATT | Oracle power, δ=5% mature | Oracle 80% MDE (ATT scale) | Oracle 80% MDE (mature scale) |
|---|---:|---:|---:|---:|
| Full | 0.140 | 0.068 | 0.39 | **0.86** |
| COVID-clean | 0.113 | 0.056 | 0.32 | 0.77 |
| Early/pre-COVID | 0.059 | 0.060 | 0.16 | **0.41** |
| Late/post-COVID | 0.149 | 0.072 | 0.42 | 1.00 |
| Cross-COVID | 0.349 | 0.040 | 0.98 | 1.56 |

This cleanly separates the two failure modes: bad inference exists (CV3 ~1.8× too
wide, analytic conservative on the full design) but is **second-order** — the point
estimate itself moves with SD 0.06–0.35 against realized doses of 0.005–0.023.

**B. Placebo-generator interrogation** (`placebo_interrogation/`): the first-pass
cross-COVID pathology was interrogated four ways.

1. *Assignment is not exchangeable.* Against an equal-probability-among-eligible
   benchmark, per-state assignment ratios within early cohorts range 0–8.2×; the
   2021-09 cohort (15 eligible states) is never assigned at all — the scarcest-first
   filler consumes shared pools on scarcer cohorts.
2. *Coverage sorts state types into dates.* Pre-COVID pseudo-dates (the only
   cross-capable cohorts) are hosted only 5% by never-treated states; ~87% of
   cross-COVID placebo cells come from real-late-treated states (MA, FL, ME, KS, KY,
   VT, OH, MO), whose untreated post-vs-pre-COVID trajectory changes are hugely
   dispersed (SD 0.70; MO +1.46 to MA −0.73) relative to never-treated states (SD 0.42).
3. *The "+0.67" vanishes under exchangeability.* A 250-rep null on the balanced
   common-support subset (AK, GA, MN, OK, TX, UT — every state eligible for every
   date, assignment uniform) gives cross-COVID mean placebo ATT **−0.022 (MC-SE
   0.028)**; all calendar classes are mean-zero.
4. *What survives:* cross-cell placebo **noise** (SD 0.35 main / 0.44 balanced vs
   0.06–0.13 clean-pre), and a distinct few-cluster inference problem visible in the
   balanced world (SE/SD ≈ 0.65, 12–22% rejection with 6 clusters).

**Conclusion of the addendum:** treat the earlier cross-COVID "bias" table as a
placebo-design artifact; the durable, verified facts are the oracle MDEs, the
cross-cell noise multiple, and the real design's 42% weight on those cells.

**C. Design-preserving re-verification of the oracle SD (rev. 3, same date;
`design_preserving/`).** Because the first placebo generator proved
nonexchangeable, the null SD was re-derived holding the REAL design fixed —
actual treated states, legalization dates, cohorts, missingness, and C&S
weights — varying only the untreated outcome process (two-way FE model fit on
genuinely untreated observations; disturbances from three serial-correlation-
preserving generators: calendar-aligned never-treated donor blocks, own-path
moving blocks, Gaussian AR(1)). 250 reps each:

| Generator | Full-design null SD | Pre-COVID null SD |
|---|---:|---:|
| Donor blocks (calendar-aligned) | 0.088 | 0.044 |
| Own-path moving blocks | 0.065 | 0.071 |
| AR(1), state-specific variance | 0.073 | 0.065 |
| *Reference: calendar-preserving placebo* | *0.140* | *0.059* |
| *Reference: balanced 6-state placebo* | *0.307* | *0.132* |

The SD is generator-robust at **0.065–0.088** — slightly below the placebo's
0.140 (which adds reassignment/composition variance) and below the 0.10–0.15
band, which only tightens the oracle MDE to ≈0.18–0.25 (ATT scale) ≈
**0.40–0.54 mature-scale** — still 16–22× the 2.5% benchmark. The information
conclusion is established under every sensible generator (BHNS point checked).

**D. New mechanical finding uncovered by C: a deterministic composition
artifact in C&S on the ragged unbalanced frame.** Feeding the estimator a
NOISELESS two-way outcome (α̂_s + γ̂_t) on the real frame returns −0.070
overall (−0.117 on post-COVID cells; single cells up to |3.07|) instead of 0.
It is exactly zero on a balanced frame or after state-demeaning the outcome —
the cause is the repeated-cross-section 2×2 path (`reg_did_rc`) with
control-group composition changing between base and outcome months, so state
fixed effects do not cancel. Implications: (i) roughly half of the real-data
full ATT (−0.145) is a plug-in mechanical offset (−0.070) under a two-way
null on this frame; (ii) any unbalanced-frame C&S run in this project should
state-demean the outcome first or balance the frame (the pretrends pipeline's
BALANCE_COMMON_MONTHS choice is retroactively vindicated); (iii) the placebo
sub-design means in the table of §1 partly reflect this offset, not outcome
dynamics.

## 1. Is the design correctly sized?

Approximately yes once the generator artifact is set aside — and where it is not, the
causes are known. Full-design analytic inference is conservative under the
calendar-preserving placebo (0% rejection, SE/SD 1.24; coverage 100%); the balanced
exchangeable null is mean-zero in every calendar class. Residual size distortions are
attributable to (i) few effective clusters (balanced world: SE/SD ≈ 0.65) and (ii)
placebo-calendar alignment (D1-shifted schedules yield 21.5% rejection vs 0% here) —
i.e., the test's behavior is dominated by calendar structure and cluster count, not by
an intrinsic cross-COVID bias detectable in untreated data. Caveat: a placebo on
untreated data cannot test endogenous-adoption bias — late adopters' untreated
trajectories are the most heterogeneous group in the panel.

## 2. Is the design adequately powered? — No, by an order of magnitude, even with oracle inference.

Realized power at 1%/2.5%/5% mature effects is ≤0.4% with actual (conservative)
inference and 5–7% with oracle inference. The oracle MDE table above is the headline:
**detecting a 2.5% mature effect would require the placebo SD to shrink ~30-fold.**
The 2.5% benchmark question is answered definitively: not detectable.

## 3. Can we avoid cross-COVID identification? — Validity yes; power no.

Pre-COVID early adopters (WV, PA, RI, IN, NH; 41 cells, ~5% of real estimand weight)
are the cleanest slice — lowest noise (SD 0.059), mean-zero, conservative inference —
but their oracle mature-scale MDE is still ≈0.41 because early states had accumulated
only ~0.3–0.6 of mature exposure before Feb 2020. Post-COVID cohorts carry 53% of the
real weight with 2.5× the pre-COVID noise. A COVID-clean estimand is the right
*validity* choice (and the cell-subset machinery now exists) but does not deliver
usable power at the state level.

## 4. Does the gambling ramp materially reduce power? — Halves the dose; not binding.

Dose ratio ≈ 0.41–0.46 vs an immediate step (at δ=2.5%: realized ATT 1.14% vs 2.50%).
In a healthy design this would ~double the MDE; here both variants sit at power ≈
size. The binding constraint is the state-level noise floor.

## 5. Does a 6-month outcome lag change viability? — No.

It trims the realized dose further (1.14% → 0.66% at δ=2.5%); oracle and actual power
are indistinguishable from the contemporaneous case. Far below design resolution.

## 6. Does the CV3 cluster jackknife help? — No; over-corrects, and the estimand moves.

- Prior 200-rep D1 null calibration: analytic 21.5% → CV3 0.5% rejection, SE/SD 1.24.
- Mechanism now quantified: 86% of treated-cluster deletions remove ATT(g,t) cells
  (singleton cohorts; mean 9.2 cells, 5.3% of weight; control deletions never do), and
  treated deletions produce ~3× the delete-one deviation of control deletions — the
  CV3 spread prices estimand-composition change as sampling noise (mean CV3 SE ≈ 1.8×
  the true placebo sampling SD). On real data: 17/24 treated deletions lose cells
  (PA: 60 cells, 7% of weight); CV3/analytic = 1.10; LOSO ATTs all in [−0.18, −0.09]
  around −0.145 (no influential state).
- With oracle power this low, inference repair is moot regardless.

## 7. What should be done next?

1. **Do not build a second-stage suite for this design; Della is unnecessary**
   (250 reps ≈ 1 h locally). The oracle result is terminal: no replication count or
   SE method changes MDE ≈ 15–35× plausible effects.
2. **Report the real-data estimate with its decomposition.** Real full ATT −0.145
   (SE 0.115) carries 42% weight on cross-COVID cells (subset −0.27) vs COVID-clean
   −0.05 (p = 0.65). Honest framing: *the COVID-clean state-level C&S estimate rules
   out only effects ≳30–40%; plausible effects are unresolvable at this level.*
3. **Redirect to the county-level did2s design** (already calibrated: 4% Type I,
   SE/SD 0.97). Port the COVID cell-classification + subset-aggregation machinery to
   quantify how much of *its* identification is cross-COVID before trusting it.
4. If a C&S estimand stays in the PAP, pre-commit to **COVID-clean cell subsets** and
   present the pre-COVID arm as the design-clean bound with its honest (oracle) MDE.
5. Placebo-generator lesson for any future placebo work on this panel: report the
   exchangeability diagnostics (eligibility matrix, assignment ratios, host
   composition) alongside any placebo rejection rate; coverage-driven sorting can
   manufacture or mask "bias" an order of magnitude larger than real signals.

**Bottom line: verified twice over — the state-panel C&S design cannot detect
plausible effects under any inference method, its cleanest identification is 5% of
the estimand with a 41% mature-scale oracle MDE, and the one alarming placebo result
(+0.67 cross-COVID) was an artifact of the placebo generator, not the design. Stop
here; move to the county did2s design with COVID-clean estimands.**
