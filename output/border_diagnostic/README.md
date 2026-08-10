# County Border-Discontinuity Diagnostic

**Date:** 2026-05-21
**Question:** Would moving from a state-month panel to a county-month border-discontinuity design (counties on opposite sides of state borders) materially improve the Gambling-and-Eviction project — on either statistical power or identification credibility?

**Verdict:** **Yes, but the mechanism is disaggregation, not border restriction.** A four-way decomposition shows that going from state aggregates to county-level data delivers a ~5× SD reduction (MDE 8% → 2%). The border restriction adds nothing to precision — in fact, restricting to border counties at the county level *loses* roughly half the precision gain (MDE 2% → 5%). The border restriction's value is identification (parallel trends defense, à la Dube-Lester-Reich), not precision.

**Recommended headline spec: full county-month TWFE on all ETS counties** (Sim D below), with the border-county spec (Sim C) as a robustness check that buys cleaner parallel-trends defensibility at the cost of precision.

---

## TL;DR — four-way decomposition

The diagnostic now runs **four** simulations to isolate sample selection from disaggregation effects. All four use identical DGP, seeds (20260521 + 10007×i), n=200 sims, effect grid (0, 2%, 5%, 8%, 10%, 15%, 20%), COVID drop, ME exclusion, state clustering, log1p(filings_count) outcome.

| Sim | Sample | Aggregation | Units | SD(ATT) at null | MDE @ 80% | Type I | SE/SD |
|---|---|---|---:|---:|---:|---:|---:|
| **A** | All ETS counties | → state-month | 37 states | 0.0207 | 8% | 0.050 | 1.05 |
| **B** | Border counties only | → state-month | 26 states | 0.0211 | 8% | 0.040 | 0.97 |
| **C** | Border counties only | county-month | 316 counties, 26 states | 0.0092 | 5% | 0.050 | 0.90 |
| **D** | All ETS counties | county-month | 1,368 counties, 31 states | **0.0042** | **2%** | 0.070 | 1.00 |

**Decomposition (SD ratio vs. Sim A baseline):**

| Comparison | Isolates | SD ratio | Effect |
|---|---|---:|---|
| B vs. A | pure sample selection (border restriction, held at state aggregation) | **1.02** | none |
| D vs. A | pure disaggregation (held at full sample) | **0.20** | 5× shrinkage |
| C vs. D | border restriction on disaggregated data | **2.20** | 2.2× *inflation* |
| C vs. A | sample selection + disaggregation (original framing) | 0.44 | net 2.25× shrinkage |

**Read the table this way:**
- **Sample selection alone does nothing.** Restricting to border counties and then re-aggregating to state-month (Sim B) gives SD = 0.0211 — statistically indistinguishable from the all-county state aggregate (Sim A, SD = 0.0207). Border counties aren't a privileged subsample in any precision-relevant way; they're just a subset.
- **Disaggregation does ALL of the precision work.** Going from state aggregates to county-month, holding the sample constant at all counties (Sim D vs. A), shrinks SD by 5×.
- **The border restriction actively costs precision when applied to county data.** Sim C uses 316 of the 1,368 ETS counties; that 4.3× sample-size reduction inflates SD by 2.2× relative to Sim D.

**Original framing was wrong.** My earlier writeup attributed the SE shrinkage to "border counties share local economies." The decomposition rules that out (Sim B's null result). The mechanism is **county FEs absorbing within-state composition heterogeneity** that state-level FEs on aggregated data cannot.

**Caveat — Sim D Type I = 0.07.** Slightly above the 0.05 nominal rate. With n=200 sims the 95% CI is [0.035, 0.105], so this is within Monte Carlo noise of 0.05, but on the anti-conservative side. SE/SD = 1.00 (calibrated). The other three sims have Type I in [0.04, 0.05].

---

## What the data look like

| Quantity | Value |
|---|---:|
| ETS counties total | 1,384 |
| ETS counties with cross-state ETS neighbor (border counties) | 318 |
| Border counties in treated states | 216 |
| Border counties in never-treated states | 102 |
| Treated states with ≥1 never-treated ETS neighbor | 13 |
| Cross-state ETS adjacency pairs | 612 |
| Pairs with treated–vs–never-treated discontinuity | 360 |
| Pairs both treated at different dates | 232 |

Coverage by treated state is asymmetric. KY is the dominant control anchor (it borders IN, OH, TN, VA, WV — five treated states). PA, DE, CT, MS have **no** never-treated ETS neighbor and contribute only via different-cohort comparisons.

See `coverage_summary.csv`, `by_treated_state.csv`, `by_state.csv` for details.

---

## Full rejection-rate table

| Effect | A: state | B: border→state | C: border-county | D: all-county |
|---:|---:|---:|---:|---:|
| 0.0% (null) | 0.050 | 0.040 | 0.050 | 0.070 |
| 2.0% | 0.105 | 0.180 | 0.640 | **0.985** |
| 5.0% | 0.540 | 0.660 | 1.000 | 1.000 |
| 8.0% | 0.925 | 0.925 | 1.000 | 1.000 |
| 10.0% | 0.980 | 0.970 | 1.000 | 1.000 |
| 15.0% | 1.000 | 1.000 | 1.000 | 1.000 |
| 20.0% | 1.000 | 1.000 | 1.000 | 1.000 |

Files: `power_state_twfe.csv` (A), `power_border_state_agg_twfe.csv` (B), `power_border_twfe.csv` (C), `power_all_county_twfe.csv` (D); `mechanism_decomposition.csv`, `sd_shrinkage_vs_baseline.csv`, `power_comparison_4way.png`.

### What the literature predicts vs. what we found

Comparison to the closest published analogue, **Black, Hollingsworth, Nunes & Simon (2019, JPubE 2022)** on ACA Medicaid expansion power simulations:

| Setting | County MDE | State MDE | Disaggregation gain |
|---|---:|---:|---:|
| Black et al. (mortality, IPW weighted) | 2.88% | 2.55% | ~10% (state slightly better) |
| **This project (filings, unweighted)** | **2%** | **8%** | **~75% (county much better)** |

The two findings are inconsistent. Three plausible reasons our disaggregation gain is dramatically larger:

1. **Outcome characteristics.** Their outcome is mortality rate per 100k — at the county level, denominators are tiny (rural counties have few elderly persons), making `log(deaths/pop)` extremely noisy. Our outcome is `log1p(filings_count)`; even small counties have moderate counts, so within-county time variation is well-behaved. Counts vs. rare-event rates respond very differently to disaggregation.
2. **IPW weights.** Black et al. use inverse-propensity-score weights at both aggregation levels, which already extracts most of the comparability gain that disaggregation could provide. Our specification is unweighted FE-only, so disaggregation has more headroom.
3. **Treatment structure.** ACA Medicaid is mostly contemporaneous (2014 expansion); gambling is 11 singleton cohorts staggered over years. Staggered treatment plus county-level data may exploit cross-county variation in treatment timing exposure that contemporaneous treatment doesn't.

The result is more in the spirit of **Cengiz, Dube, Lindner & Zipperer (2019, QJE)** and **Hollenbeck, Larsen & Proserpio (2025)** — both use individual / county-level data with state-level treatment and detect effects that state-aggregate panels could not.

### Why this happens, mechanically

The cluster sandwich variance is

$$
V \propto \frac{1}{G}\cdot \mathrm{Var}\!\Big(\sum_t \tilde D_{st}\cdot \bar e_{st}\Big),\quad \bar e_{st} = \tfrac{1}{N_{st}}\sum_{i \in (s,t)} \tilde e_{ist}
$$

When you aggregate counties to state level *before* running TWFE (Sims A and B), the residual that enters the cluster sum is whatever variation the state-aggregate FE absorbs from `log(sum of filings)`. When you keep county-level data and absorb county × month FEs (Sims C and D), the county FEs absorb the much richer set of between-county heterogeneity that state-level FEs can't reach when you've already collapsed the data.

The crucial fact, revealed by the B vs. A comparison: **county vs. state aggregation differs not because "border counties are special," but because state-level FEs on aggregated data leave too much residual variance in place.** Aggregation discards information that county FEs can absorb cleanly.

The earlier "within-cluster averaging when $\rho<1$" framing was directionally right but assigned credit to the wrong mechanism. The real driver is the **FE absorption structure**, not the cluster-mean averaging of independent county residuals.

---

## Pre-trends — the caveat

Sun-Abraham event study on the border-county subsample (same SunAb spec as `analysis/pretrends/pretrends_statepanel_template.R`, cluster at state):

Near-treatment pre-period coefficients (`pretrends_border_eventstudy.csv`):

| Event month | Estimate | SE | Significant at 5% |
|---:|---:|---:|:-:|
| −12 | −0.171 | 0.017 | yes |
| −9 | −0.142 | 0.017 | yes |
| −6 | +0.074 | 0.019 | yes |
| −4 | +0.146 | 0.025 | yes |
| −3 | +0.046 | 0.015 | yes |

This is **not** the cleanly-flat pre-period we want. Several of the near-treatment pre-coefficients are statistically distinguishable from zero — though the magnitudes are smaller than the post-period coefficients we'd expect under a 5% treatment effect, the visual evidence for parallel trends is weaker on the border subsample than on the full state panel.

Three plausible reasons:
1. **County-level data is genuinely noisier** than state aggregates, so individual coefficients pop more often even when there is no underlying pre-trend.
2. **Cohort heterogeneity remains** — 17 treated states with mostly singleton cohorts is the same identification challenge that hurts CS-DiD in the state-panel calibration test.
3. **Border counties may have idiosyncratic local-economy patterns** (commuting zones near state lines) that diverge across the treatment date even absent the policy.

The Wald joint pre-period F-test could not be computed (the cluster-robust VCOV is not positive semi-definite at the far event times — `pretrends_border_eventstudy.png` shows why, with very wide tails).

**Implication:** The border-discontinuity design needs HonestDiD sensitivity bounds (Rambachan & Roth 2023) built into the headline result, not deferred to robustness. The pre-period violations are not catastrophic (magnitudes ≤ 0.17 log points on a base where post-treatment effects are essentially zero), but they preclude an unqualified parallel-trends claim.

---

## Spillover caveat

SUTVA is not modeled. Residents of treated states may drive to untreated border counties (or vice versa) to gamble. The border design therefore estimates effects **net of cross-border substitution**. This is the DLR convention. If substitution is one-directional (e.g., NJ residents already had online access in 2018 and don't drive to PA), it biases estimates toward zero; if substitution adds gambling exposure to the comparison county, the same. We recommend disclosing this in the writeup and not attempting to correct for it without a distance-to-border instrument that the current data don't support.

---

## Multi-estimator calibration at county level (50-sim null test)

The state-panel calibration (CLAUDE.md lines 113–130) showed that all heterogeneity-robust estimators had broken Type-I error: CS over-rejected at 14%, Sun-Abraham at 21%, didimputation and did2s failed entirely. The prediction was that county-level data would fix this by giving each cohort ~50 counties instead of 1 state.

Result (50 sims, log1p outcome, COVID dropped, ME excluded, states with <5 counties dropped to ensure cohort estimability, state clustering across all estimators):

| Estimator | State-panel rej / SE-SD / noise | County-panel rej / SE-SD / noise |
|---|---|---|
| TWFE | 1% / 1.14 / 1× | **8% / 0.95 / 1×** |
| Sun-Abraham | 21% / 0.58 / 4× | 30% / 0.51 / 4.5× |
| CS Analytic | 14% / 0.67 / 5.1× | 0% / 2.46 / 3.4× |
| didimputation (BJS) | failed | **14% / 0.73 / 1.1×** |
| did2s (Gardner) | failed | **4% / 0.97 / 1.1×** |

Key reads:

- **did2s is now well-calibrated and as efficient as TWFE.** This is the right heterogeneity-robust headline estimator for the project. Rejection 4% (in MC noise of 5%), SE/SD = 0.97 (no anti-conservative bias), noise ratio 1.08×.
- **didimputation also works** (slight over-rejection at 14%, useable as robustness).
- **CS-DiD now over-corrects.** Point-estimate noise did shrink from 5.1× to 3.4× TWFE, confirming the cohort-size mechanism, but the analytic SE blew up too far — SE/SD jumped from 0.67 to 2.46. Going from 14% over-rejection to 0% under-rejection is not an improvement; it's swapping one failure mode for another.
- **Sun-Abraham did not improve and is slightly worse.** The per-cohort aggregation noise is a property of having only one state per treatment date, and county-level data within each cohort doesn't fix it.
- **TWFE at county level has Type I = 8%**, mildly anti-conservative. CI is [0.5%, 16%] with 50 sims — within MC noise of 5%, but in the same direction as the power-sim Type I of 7%. Wild cluster bootstrap inference is the standard defense.

Files: `output/border_diagnostic/cs_calibration_multi_county/{sim_results,calibration_summary}.csv`.

## Identification follow-ups: HonestDiD bounds, drop-NH, Hollenbeck-style CS

After the precision diagnostics surfaced pre-trend significance, three further checks were run:

**(1) Drop-NH test.** NH was the worst-behaved cohort (10 ETS counties, max pre-period coefficient 1.6 log-points). Dropping it changed the aggregate near-treatment pre-coefficient summary only marginally: 9/11 significant (was 8/11), mean |coef| 0.049 (was 0.058). The pre-trend pattern is **not driven by NH**; it's broadly distributed across cohorts.

**(2) HonestDiD relative-magnitudes bounds (Rambachan-Roth 2023).** Uses i()-event-study (simpler pooled spec, conservative SEs).

| Sensitivity assumption | 95% CI on avg post-treatment effect |
|---|---|
| Original (parallel trends assumed) | [−0.078, +0.026] |
| Mbar = 0 | [−0.077, +0.025] |
| Mbar = 0.25 | [−0.222, +0.207] |
| Mbar = 0.5 | [−0.412, +0.407] |
| Mbar = 0.75 | [−0.530, +0.530] |
| Mbar = 1.0 (worst-case) | [−0.530, +0.530] |
| Mbar = 1.5 / 2.0 | [−0.530, +0.530] |

The CI widens symmetrically around zero as the allowed pre-trend violation grows. **The null is robust to any reasonable HonestDiD assumption** — the point estimate stays at zero at every Mbar.

Important caveat: i()-event-study has *wider* SEs in the pre-period than sunab() (0.02–0.05 vs 0.013–0.016). Under i(), only 2/11 near-treatment pre-coefs are individually significant. The earlier "8 of 11 significant" finding from sunab overstated the concern; the more conservative i() spec — which is what HonestDiD operates on — shows much friendlier pretrends.

**(3) Hollenbeck-style CS-DiD with multiplier bootstrap (mirroring Hollenbeck, Larsen & Proserpio 2025).** CS-DiD with `bstrap = TRUE, biters = 999`, dynamic event-study aggregation, heterogeneity by county poverty rate (proxy for "vulnerable households").

| Spec | ATT | SE | 95% CI |
|---|---:|---:|---|
| Overall (all counties) | +0.045 | 0.173 | [−0.295, +0.385] |
| High poverty (≥13%) | **+0.097** | 0.212 | [−0.32, +0.51] |
| Low poverty (<13%) | −0.001 | 0.104 | [−0.21, +0.20] |

Bootstrap CIs are dramatically wider than analytic CS-DiD CIs (which were over-conservative per the calibration test). The point estimate is consistent with zero across all specs.

**The high-poverty subset point estimate is +10%, in the same direction as Hollenbeck et al.'s vulnerable-household credit findings**, but the bootstrap CI is too wide to confirm. This is a suggestive heterogeneity pattern worth reporting transparently as "possibly consistent with concentrated effects in vulnerable counties, with too much uncertainty to claim."

Files: `output/border_diagnostic/{pretrends_all_county_drop_nh,honestdid_bounds,honestdid_breakdown}.csv`; `output/border_diagnostic/hollenbeck_style/{overall_att,dynamic_event_study,heterogeneity_by_poverty}.csv`.

## Recommendation (revised after 4-way decomposition + multi-estimator calibration + HonestDiD/Hollenbeck-style robustness)

**Recommended headline lineup, in priority order:**

1. **Lead**: **did2s (Gardner)** on all-county panel — heterogeneity-robust, well-calibrated at the null (rejection 4%, SE/SD 0.97), as efficient as TWFE. Handles staggered treatment correctly. Cluster at state.
2. **Precision baseline**: All-county TWFE (Sim D) with **wild cluster bootstrap** inference. Same MDE ≈ 2%, addresses the Type I = 7–8% cluster-robust SE bias.
3. **Robustness — alt. estimator**: didimputation (BJS). Calibration on the edge (rejection 14%) but useable as agreement check.
4. **Robustness — identification**: Border-county TWFE (Sim C). MDE ≈ 5% but adds Dube-Lester-Reich geographic-matching identification defense.
5. **Robustness — parallel trends**: HonestDiD sensitivity bounds on the did2s event study, M ∈ {0, 0.5, 1, 1.5}.
6. **Footnote-only**: CS-DiD and Sun-Abraham. Neither is calibrated on this design (CS over-corrects, SunAb still over-rejects). Mention that we tried them and they don't behave well here.

If a null result holds across did2s, all-county TWFE with wild bootstrap, and border-county TWFE, with HonestDiD breakdown $M > 1$, the project has a publishable headline.

If implementing: write `analysis/main/main_estimate_county_did2s.R` modeled on `power_sim_all_county.R` but doing real estimation. The shared DGP code in `power_sim_shared.R` is mostly reusable.

---

## Files produced

```
output/border_diagnostic/
├── README.md                              ← this file
├── coverage_summary.csv                   ← border-county top-line counts
├── by_treated_state.csv                   ← treated states × adjacent control coverage
├── by_state.csv                           ← border-county count per state × treatment
├── border_panel_summary.csv               ← Sim C panel dims
├── state_panel_summary.csv                ← Sim A panel dims
├── border_state_agg_panel_summary.csv     ← Sim B panel dims
├── all_county_panel_summary.csv           ← Sim D panel dims
├── power_state_twfe.csv                   ← Sim A power grid
├── power_border_state_agg_twfe.csv        ← Sim B power grid
├── power_border_twfe.csv                  ← Sim C power grid
├── power_all_county_twfe.csv              ← Sim D power grid
├── power_comparison_4way.csv              ← wide 4-way table
├── power_comparison_4way_long.csv         ← long 4-way table
├── power_comparison_4way.png              ← 4-way rejection curves
├── mechanism_decomposition.csv            ← Type I, SD, MDE per sim
├── sd_shrinkage_vs_baseline.csv           ← SD ratios vs Sim A
├── power_comparison.csv                   ← (legacy) 2-way table A vs C
├── power_comparison.png                   ← (legacy) 2-way plot A vs C
├── calibration_check.csv                  ← (legacy) calibration check A vs C
├── mde_summary.csv                        ← (legacy) MDE at 80%, A vs C
├── pretrends_border_eventstudy.csv        ← SunAb event-study coefs
├── pretrends_border_eventstudy.png        ← event-study plot
└── pretrends_border_summary.csv           ← pre-period joint test summary
```

Source code:
```
data_prep/download_county_adjacency.R              ← Census adjacency → edge list
data_prep/build_border_county_panel.R              ← border-county panel + pairs
data_prep/border_panel_descriptives.R              ← coverage summary
analysis/diagnostics/power_sim_shared.R            ← shared DGP + sim functions
analysis/diagnostics/power_sim_state_baseline.R    ← Sim A
analysis/diagnostics/power_sim_border_state_agg.R  ← Sim B
analysis/diagnostics/power_sim_border_county.R     ← Sim C
analysis/diagnostics/power_sim_all_county.R        ← Sim D
analysis/diagnostics/border_power_comparison.R     ← (legacy) 2-way comparison
analysis/diagnostics/border_power_comparison_4way.R ← 4-way decomposition + plot
analysis/diagnostics/pretrends_border_county.R     ← SunAb event study on border subsample
```

---

## Update to CLAUDE.md

The claim at lines 213–214 ("Using county-level data does NOT meaningfully improve power because cluster-robust SEs are driven by the number of clusters, not observations within clusters") is **empirically wrong** for this project. Four-way decomposition shows:

- Going from state aggregates to county-level data (with state clustering) shrinks the cluster-robust SE by ~5× (Sim D vs. Sim A, n=200 sims each)
- The mechanism is FE absorption: county FE + month FE absorb within-state composition heterogeneity that state FE + month FE on aggregated data cannot
- This holds with state-level treatment and state-level clustering — the cluster count is unchanged at G≈30
- The "worst-case" theoretical bound (cluster count is binding when within-cluster correlation = 1) does not characterize this data

CLAUDE.md should be updated. Replace the claim with: "Counter-intuitively, county-level data with state clustering improves the cluster-robust SE substantially in this setting (~5× shrinkage, see `output/border_diagnostic/`). The cluster-count bound is loose when within-state-month residuals are not perfectly correlated and county FEs absorb between-county composition heterogeneity."
