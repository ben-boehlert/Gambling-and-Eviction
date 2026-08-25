# Strategy Memo: did2s and LP-DiD with a COVID-Interrupted Panel

## Pre-Strategy Report

**Research spec:** not found as a standalone discovery input; **[ASSUMED]** from `README.md`, the repository guide, and the task prompt  
**Literature review:** `docs/literature_review_2026-07_estimation_strategy.md`  
**Data assessment:** `quality_reports/state_panel_rebuild_data_audit_2026-08-20.md` (found, but it concludes that the rebuilt state panel is not yet safe for final state-level results)  
**Domain profile:** not found at `.Codex/references/domain-profile.md`

**Research question:** What is the causal effect of online sports-gambling legalization on state-level eviction filings, including its evolution after legalization? **[ASSUMED]**

**Key findings from literature:**

- Gardner's two-stage DiD estimates state and period effects using untreated observations, then estimates treatment effects from residualized outcomes; it is robust to staggered-adoption treatment-effect heterogeneity but still requires an appropriate model for untreated outcomes.
- Dube, Girardi, Jordà, and Taylor's LP-DiD uses horizon-specific long differences and “clean” controls, avoiding already-treated controls and permitting explicit estimand weights, covariate adjustment, and nonabsorbing-treatment extensions.
- The project review finds applied precedent for did2s in a closely related state-level sports-betting design, but it does not establish that did2s's untreated-outcome model is valid in this panel.

**Available data:**

- State-month eviction panel — 2016 through 2024/2025; treatment at the state level; typical balanced estimation samples contain roughly 24–26 states and 11–17 treated states, depending on treatment definition and exclusions.
- Online-gambling legalization schedule — staggered state adoption dates, with never-treated and not-yet-treated states available as comparisons.
- COVID interruption — commonly removed from March 2020 through July 2021 or March 2020 through March 2022.
- Variation available for identification — between-state differences in legalization timing, compared with contemporaneous changes in states not yet treated through the relevant horizon.
- Important measurement limitation — the 2026-08-20 audit flags unstable reporting geography and invalid rate construction in parts of the rebuilt panel. No estimator fixes a changing outcome definition.

**Candidate designs from domain profile:** unavailable because the profile was not found. The requested scope limits the comparison to did2s and LP-DiD; other staggered-DiD estimators are out of scope.

Proceeding to strategy design.

## Paper type

**Primary type:** reduced-form causal paper.  
**Design:** staggered state-level difference-in-differences.  
**Primary recommendation:** non-straddling, clean-control LP-DiD.  
**Secondary recommendation:** did2s estimated separately within pre-COVID and post-COVID regimes, never as a single pooled pre/post splice without strong additional restrictions.

## Bottom line

LP-DiD is the more credible of the two estimators in this setting, but its credibility is **moderate, not high**. It replaces did2s's global additive untreated-outcome restriction with a cohort-, date-, and horizon-specific parallel-changes restriction. That is a meaningful improvement when COVID splits the panel, provided every comparison crossing the COVID disruption is excluded. Its main costs are lost cohorts, rapidly shrinking support at long horizons, and an event-study composition that can change with the horizon.

Pooled did2s across the pre- and post-COVID segments is **low credibility** here. Month fixed effects absorb a COVID shock common to all states, but not state-specific shutdown, moratorium, court-backlog, or recovery shifts. Removing the COVID months leaves the pre/post splice intact: the first stage still estimates one state effect and one set of month effects from all untreated observations. Local simulations calibrated under an additive state-plus-month fixed-effect data-generating process validate computation and inference only under that model; they do not validate the model on the real untreated outcomes.

| Specification | Identification credibility | Appropriate role |
|---|---:|---|
| did2s pooling pre- and post-COVID observations with one state effect | **Low (2/5)** | Do not use as the headline |
| did2s within a single pre- or post-COVID regime, with eligible cohorts only | **Moderate (3/5)** | Secondary estimate and specification check |
| LP-DiD retaining comparisons that straddle COVID | **Low (2/5)** | Do not interpret causally |
| LP-DiD dropping all straddling comparisons and using clean controls | **Moderate (3.5/5)** | Primary estimator, subject to support and data-quality gates |

These ratings concern identification. Inference is separately fragile because treatment occurs at the state level and there are only about 24–26 clusters, with still fewer switchers within either COVID regime.

## Identification landscape

### Ideal experiment

Randomly assign online legalization dates to otherwise comparable states outside a nationwide disruption, preserve a fixed eviction-reporting geography, and observe untreated potential eviction paths for every treated state. The causal targets would be dynamic state-level ATTs by months since legalization and an explicitly weighted average over a prespecified horizon.

### Distance from the ideal

Legalization timing is policy-selected, COVID produces sharply heterogeneous state-level court and housing-market responses, the treatment is assigned at the state level, and the usable control pool is small. The current outcome panel also has reporting-composition problems. Thus the design requires both a defensible comparison-path assumption and a measurement release gate.

### Descriptive COVID evidence

`output/covid_global_pt/postcovid_boundary_sweep.csv` reports across-gap dispersion in never-treated state shifts of approximately 0.44–0.54 log points across alternative post-COVID start dates. That is much larger than a target effect near 0.05 log points. Treat this as a **descriptive red flag**, not as a valid formal rejection: there are few never-treated clusters, and state-by-regime interactions with saturated time effects make conventional clustered Wald tests unreliable. The important implication is that simply moving the post-COVID boundary later does not visibly restore a stable pre/post state effect.

## Strategy 1: non-straddling LP-DiD — recommended primary

### Estimand

For horizon \(h\), estimate an equal-weighted ATT among states that legalize in month \(t\), have an observed untreated baseline, and have clean comparison states that remain untreated through \(t+h\):

\[
\tau_h = E_w\!\left[Y_{i,t+h}(1)-Y_{i,t+h}(0)\mid G_i=t,\; (i,t,h)\in\mathcal S\right].
\]

Here \(\mathcal S\) is the prespecified non-straddling support set. The primary pooled estimand should be an equal-weighted average over \(h=0,\ldots,H\) and eligible treated states, with \(H\) chosen from support before viewing estimates. Report regime-specific aggregates as well as the pooled support-limited aggregate.

This is not automatically the ATT for all legalizing states. States treated inside the omitted COVID interval or without a valid pretreatment baseline are outside the estimand. If eligible cohorts change with \(h\), the dynamic profile also changes composition. Therefore report both:

1. a **fixed-cohort event study** using states supported at every horizon \(0,\ldots,H\), for comparability across horizons; and
2. a **maximal-support event study** using all eligible states at each horizon, for precision, with the contributor set shown at every point.

### Treatment and controls

- **Treatment:** first month of legal online sports betting, prespecified and verified against the treatment schedule. Alternative ramp/intensity timing is a different estimand and should not replace the launch specification silently.
- **Switcher:** a state first treated in base month \(t\).
- **Clean controls for horizon \(h\):** never-treated states and not-yet-treated states whose treatment begins after \(t+h\).
- **Exclusions:** any comparison whose baseline window or outcome horizon touches or crosses the COVID gap; states treated inside the gap when no valid adjacent pretreatment baseline exists; already-treated states.

### Identifying assumption

For each supported \((t,h)\), absent legalization, switchers and clean controls would have had the same expected change between the baseline and \(t+h\), conditional on prespecified covariates:

\[
E[\Delta_hY_i(0)\mid G_i=t,X_i]
=E[\Delta_hY_j(0)\mid G_j>t+h\text{ or }G_j=\infty,X_j].
\]

This is local relative to did2s, but it is not assumption-free. A post-COVID state recovery shock correlated with legalization timing can still violate it. Moreover, as \(h\) grows, the “local” long difference spans more months and the assumption becomes harder to defend.

### Estimation choices

- Use true calendar-month indexing, not row lags after removing COVID months.
- Primary baseline: \(t-1\), matching the cleanest LP-DiD contrast. Use 3- and 6-month pretreatment means as precision and transitory-noise robustness checks only; the entire baseline window must lie in the same regime.
- Include base-calendar-time fixed effects so switchers are compared with controls at the same date.
- Use equal-weight ATT reweighting so large or control-rich cells do not define the estimand unintentionally. Also report the unweighted/variance-weighted version as a sensitivity check.
- Start with \(H=12\) months; extend to 18 or 24 only if the support table shows an adequate prespecified minimum number of treated states and clean controls at each horizon. Given market maturation, longer horizons are substantively interesting but may not be empirically identified here.
- Estimate preperiod placebo horizons using the exact same cohort and control eligibility rules. Joint inference must retain cross-horizon covariance; do not combine marginal \(z\)-statistics as if horizons were independent.

### COVID remedy

The primary remedy is mechanical and transparent: no long difference may cross the COVID interval. Estimate pre-COVID and post-COVID regime effects separately, then optionally report a prespecified weighted average of the two regime-specific causal parameters. Do not treat agreement between them as required; they may genuinely differ because gambling access and eviction institutions differ by regime.

Test both plausible disruption windows—March 2020–July 2021 and March 2020–March 2022—but label the shorter-window analysis as more permissive, not automatically more credible. A cohort should enter only if its complete baseline and horizon fall within the chosen regime.

## Strategy 2: regime-specific did2s — recommended secondary

### Estimand

Within regime \(r\), estimate the average treated state-month effect after residualizing untreated outcomes with regime-specific state and month effects:

\[
Y_{it}(0)=\alpha_{ir}+\lambda_{tr}+X_{it}'\gamma_r+u_{it},
\qquad
\tau_r=E_w[Y_{it}(1)-Y_{it}(0)\mid D_{it}=1,r].
\]

For comparability with LP-DiD, also estimate event-time effects and a common-horizon average over the same eligible cohort set.

### Why the pooled version is not credible

The ordinary first stage, \(Y_{it}(0)=\alpha_i+\lambda_t+u_{it}\), treats the state's untreated level difference as stable across the entire retained panel. Dropping COVID observations removes contaminated outcomes but does not remove the restriction \(\alpha_{i,pre}=\alpha_{i,post}\). A common COVID shock is absorbed by \(\lambda_t\); differential state responses and recoveries are not.

Adding state-by-post-COVID intercepts is algebraically similar to allowing separate regimes, but it only works for states with untreated observations in each regime. If a state is already treated at the start of the post-COVID regime, its post-regime untreated state effect is not observed. Estimating it would again require extrapolation. Therefore:

- the pre-COVID did2s analysis may include only cohorts with sufficient untreated observations and treatment within the pre-COVID regime;
- the post-COVID analysis must drop states already treated at regime entry and use only later switchers plus clean controls;
- the two estimates should be reported separately unless an explicit aggregation target and weights are declared.

### Conditional adjustments

Covariate adjustment can make either design more plausible, but it changes unconditional parallel trends to conditional parallel trends; it does not prove it. Prespecify a small set of plausibly exogenous confounders measured before or contemporaneously with treatment, such as renter exposure, unemployment, income, and independently determined eviction-policy/court-operation indicators. Do not control for variables plausibly caused by gambling legalization.

Region-by-month effects can absorb region-specific COVID and recovery paths, but with roughly 24–26 states they may leave little comparison variation. Use them only after a cell-support and leverage audit. State-specific linear trends should be a sensitivity check within regimes, not a default cure: they can absorb treatment dynamics, extrapolate poorly, and do not capture nonlinear backlog unwinding.

## Inference plan

- Cluster at the state level in every specification. County or state-month observation counts do not increase the effective number of treatment-assignment clusters.
- Report analytic state-clustered intervals and null-imposed wild-cluster-bootstrap intervals/p-values, using many replications and a small-cluster weight distribution such as Webb weights.
- For regime splits, disclose the number of treated and control clusters used in each coefficient. If only a handful of switchers identify a horizon, emphasize the estimate and interval rather than a binary significance label.
- Use a state-level cluster bootstrap or stacked estimating system for joint tests and pooled LP-DiD estimates so covariance across horizons is preserved.
- Add treatment-date placebo/randomization exercises as falsification evidence, not as exact randomization inference unless the policy-assignment mechanism can be defended as exchangeable.

## Robustness and falsification plan

Ordered by importance:

1. **Measurement release gate:** use a fixed reporting geography or otherwise resolve the data-audit problems before interpreting either estimator.
2. **COVID-window sensitivity:** repeat non-straddling estimates under both candidate gap endpoints; show cohort eligibility and horizon support for each.
3. **Regime estimates:** report pre- and post-COVID estimates separately. For did2s, this is mandatory; for LP-DiD, it reveals whether aggregation hides regime heterogeneity.
4. **Fixed versus varying horizon support:** compare the fixed-cohort and maximal-support LP-DiD event studies.
5. **Control definitions:** never-treated only; then never-treated plus not-yet-treated clean controls. Audit controls for retail-only gambling and cross-border online access.
6. **Boundary-adjacent cohorts:** exclude states treated within 6 and 12 months of the COVID/reopening boundary, where backlog unwinding is most plausible.
7. **Baseline sensitivity:** \(t-1\) versus 3- and 6-month pretreatment means, with no cross-gap baselines.
8. **Conditional trends:** parsimonious covariates; region-by-month effects where supported; state trends only as a sensitivity exercise.
9. **Functional form:** log filings and a valid rate/level outcome after denominator repair. Parallel trends in logs does not imply parallel trends in levels.
10. **Influence:** leave one treated state and one control state out; report changes in both estimates and support.
11. **Placebo leads:** estimate pretreatment horizons on the exact estimation sample and with the same clean-control rule; use a covariance-aware joint test and equivalence bands relative to economically meaningful violations.
12. **Pseudo-treatment dates:** assign placebo adoption dates within the same regime to never-treated/late-treated states while preserving the empirical cohort pattern. Large placebo effects weaken the design.
13. **Placebo outcomes:** use court case categories that should not respond to gambling legalization, if comparably measured.
14. **Untreated-path diagnostics:** plot switcher and clean-control long differences before treatment by cohort and regime; compare COVID-boundary shift magnitudes with ordinary within-regime placebo boundaries.

## Specification-level pseudo-code

```text
INPUT: fixed-geography state-month outcome, verified launch dates, COVID gap,
       prespecified H, covariates, and eligible states

FOR each COVID regime:
    retain months wholly inside regime
    classify states as never treated, later treated, already treated, or switchers
    exclude already-treated-at-entry states from regime-specific causal contrasts

LP-DiD FOR each horizon h = 0,...,H:
    FOR each candidate switch month t:
        treated = states with G_i = t
        controls = states with G_i > t+h or G_i = infinity
        require baseline and t+h inside same regime
        construct delta_y = y_(t+h) - y_(t-1)
        retain cells with treated and controls
    estimate delta_y on switcher indicator + base-time effects
    apply declared equal-treated-state weights
    cluster by state; obtain wild-cluster-bootstrap inference
    save contributing treated states and controls
aggregate horizons using declared weights; estimate covariance jointly

DID2S WITHIN each regime:
    first stage on untreated observations only:
        y = state FE + month FE + prespecified covariates
    residualize all supported observations
    second stage:
        residual = event-time indicators or treatment indicator
    restrict aggregation to declared cohorts/horizons
    cluster and wild-bootstrap by state

OUTPUT:
    regime-specific estimates, fixed-support and maximal-support LP-DiD,
    cohort/horizon support table, influence diagnostics, and falsification tests
```

## Top referee objections and planned responses

1. **“Dropping COVID months does not restore parallel trends.”** Agree. The headline LP-DiD excludes all cross-gap long differences, and did2s is estimated separately by regime. Show alternative boundaries and boundary-adjacent cohort exclusions.
2. **“Post-COVID recovery is still differential and correlated with legalization.”** Add parsimonious predetermined covariates and supported region-by-month adjustments; show regime-specific untreated-path diagnostics. State honestly that no adjustment eliminates unobserved state-specific recovery confounding.
3. **“Your long-horizon effects come from different states than your short-horizon effects.”** Make the fixed-cohort event study primary for dynamics; show maximal-support results and the contributor set at every horizon.
4. **“There are too few state clusters for conventional inference.”** Use state clustering plus null-imposed wild-cluster bootstrap, show treated/control counts and leave-one-state-out results, and avoid binary claims at thinly supported horizons.
5. **“The outcome itself changes when reporting counties enter or exit.”** Resolve the 2026-08-20 data-audit release gate before estimation; neither did2s nor LP-DiD can turn composition changes into a causal outcome.

## Decision rule

Use **non-straddling LP-DiD as the primary estimator** if, after the data release gate, at least a defensible number of treated states and clean controls support the prespecified 0–12 month horizon within regimes and placebo diagnostics do not show economically large violations. Use **regime-specific did2s as a secondary summary and specification check** on the same cohort/horizon support.

If LP-DiD support collapses after excluding cross-gap and boundary-adjacent comparisons, the honest conclusion is that the panel does not identify a full dynamic causal path. Shorten the estimand to supported horizons or report regime-specific short-run effects; do not restore sample size by reconnecting pre- and post-COVID observations through an unverified global parallel-trends assumption.

## Primary methodological references

- John Gardner, [“Two-Stage Differences in Differences”](https://arxiv.org/abs/2207.05943) (2022).
- Kyle Butts and John Gardner, [“did2s: Two-Stage Difference-in-Differences”](https://journal.r-project.org/articles/RJ-2022-048/) (2022).
- Arindrajit Dube, Daniele Girardi, Òscar Jordà, and Alan M. Taylor, [“A Local Projections Approach to Difference-in-Differences”](https://doi.org/10.1002/jae.70000), *Journal of Applied Econometrics* 40(7), 2025.

## Scope note

This memo intentionally does not assess other staggered-DiD estimators. Existing LP-DiD saved reports were produced under an older COVID endpoint and must be rerun before any numerical result is quoted. No current treatment-effect estimate is endorsed here.
