## Pre-Strategy Report

**Research spec:** **[ASSUMED — not found]**. No standalone research-specification file was located. The research question and intended estimand below are inferred from the repository guide, the literature reassessment, and the data-support profile.

**Literature review:** `docs/literature_review_2026-07_estimation_strategy.md`

**Data assessment:** `quality_reports/handle_cohort_support_data_profile.md`

**Domain profile:** **not found at the required path** `.Codex/references/domain-profile.md`. A project-specific fallback, `.claude/references/domain-profile.md`, was read but is not treated as a substitute for a formally approved domain profile.

**Research question:** **[ASSUMED]** What is the causal effect of operational legal online sports-betting access on eviction filings, allowing the effect to develop as betting markets mature?

**Key findings from literature:**

- Recent applied work on the same policy variation supports Gardner's two-stage DiD (`did2s`) or other imputation-style estimators as headline approaches, with TWFE as a comparison rather than the identifying estimator.
- Sparse treated cohorts and high-leverage event-time cells can make CS and SA inference unreliable even when the nominal number of clusters looks adequate; long leads and lags are particularly vulnerable.
- The largest substantive threats are cross-border gambling spillovers, retail-betting contamination of the comparison group, post-COVID eviction-backlog dynamics, weak pretrend-test power, and functional-form dependence.
- Handle grows slowly and heterogeneously after access. That supports estimating dynamic legal-access effects, but realized Handle is itself a post-treatment variable and cannot automatically replace legal access as exogenous treatment timing.

**Available data:**

- Eviction Tracking System state-month panel — 39 raw states, January 2012–November 2025; the default balanced no-COVID analysis contains 26 states and 91 observed months from January 2016–December 2024 after deleting March 2020–July 2021.
- LSR state-month Handle — 2,270 rows for 35 states, June 2018–May 2026; total reported Handle, without a retail/online channel split.
- Legalization schedule — operational online, retail, and first-start dates; 31 online dates among 38 schedule states.
- Actual identifying variation — state-level staggered legal access. Quartering changes the time grid but does not add independently treated states. In the balanced 26-state sample, legal timing gives 17 treated states; 50%-Handle timing gives 16.
- Existing calibration evidence — `output/cheap_power_sim/DECISION_MEMO.md` concludes that the state-panel CS design cannot resolve plausible effects even under oracle inference; its design-preserving null SD implies a mature-effect MDE far above plausible magnitudes. The calibrated county-level `did2s` design is the more promising headline architecture.

**Candidate designs from domain profile:** **[ASSUMED from the fallback project profile]** staggered legal-access DiD using `did2s`; CS group-time ATT; SA interaction-weighted event study; BJS imputation; generalized synthetic control; HonestDiD sensitivity; placebo-date/randomization inference.

Proceeding to strategy design.

# Strategy Memo: Quarterly Outcomes and Handle Ramp-Up

**Paper type:** Reduced-form causal paper (primary), with a descriptive/measurement component for market ramp-up (secondary).

**Decision:** Combining quarterly outcomes with a state-specific 50%-Handle treatment clock does **not** make CS or SA suitable as the headline causal design. Quarterly aggregation modestly improves legal-date cohorts; Handle threshold timing improves them more, but only by redefining treatment using an endogenous post-treatment outcome. The defensible architecture is:

1. keep operational legal online access as the treatment;
2. use a calibrated, heterogeneity-robust `did2s` estimate as the headline, preferably on the county panel with state-clustered inference;
3. use a quarterly version as temporal-aggregation robustness;
4. use CS and SA with **legal timing** only as calibrated secondary triangulation, with short supported horizons and explicit cohort tables; and
5. use Handle to describe take-up, validate ramp-up, and pre-specify event-time maturity windows—not to determine the primary causal treatment date or define ex-post subgroups.

This removes the need to defend naive staggered TWFE as the headline. TWFE can remain a diagnostic comparison.

## 1. Identification landscape

### Ideal experiment

Randomly assign otherwise comparable states to dates when legal online sportsbooks become operational, hold retail access and neighboring-state access fixed, and observe quarterly eviction filings for several years before and after. The target contrast would compare the same post-assignment horizons for assigned-access and not-yet-assigned states, with no cross-border betting.

### Distance from the ideal

Legalization is not random. Adoption timing may correlate with fiscal conditions, political preferences, income growth, eviction policy, retail gambling history, and COVID recovery. The data contain only 17 legally treated states in the balanced 26-state sample, and most exact-month cohorts are singletons. County observations improve outcome measurement but do not create additional independent treatment assignments.

### Source of identifying variation

The defensible source is the date on which online betting became legally and operationally accessible. This identifies an intention-to-treat/access effect: the effect of making online betting available, including incomplete take-up and endogenous market maturation. It does **not** identify the effect of an additional dollar of Handle.

The identifying assumption is conditional parallel trends for untreated potential eviction outcomes, together with no anticipation beyond a pre-specified window, no contamination of controls, stable measurement, and no state-specific concurrent shocks correlated with adoption.

## 2. What quarterly aggregation actually changes

### Cohort arithmetic

The following launch-quarter counts are obtained by mapping the audited monthly treatment dates to calendar quarters. They are descriptive support counts, not estimates.

| Sample and clock | Treated states | Quarter cohorts | Singleton cohorts | Other cohort sizes | Largest cohort |
|---|---:|---:|---:|---|---:|
| Balanced 26, legal online | 17 | 14 | 11 | three doubletons | 2 |
| Balanced 26, 50%-Handle | 16 | 9 | 4 | four doubletons, one four-state cohort | 4 |
| Post-COVID 30, legal online | 8 | 6 | 4 | two doubletons | 2 |
| Post-COVID 30, 50%-Handle | 8 | 5 | 2 | three doubletons | 2 |

For the balanced Handle schedule, the nine cohort sizes are `1, 2, 4, 1, 1, 1, 2, 2, 2`. Thus 12 of 16 treated states still lie in cohorts of size at most two. Quartering creates useful pooling, but not a conventional many-treated-clusters design.

Under legal timing—the treatment clock with a causal interpretation—11 of 14 quarter cohorts remain singletons. The improved Handle counts therefore cannot be used as evidence that legal-access CS/SA inference has been repaired.

### Number of observations and independent information

- The balanced panel has 2,366 state-month observations. Retaining every calendar-quarter label after the COVID deletion would yield 31 quarter labels, or 806 state-quarter observations, but two labels are incomplete: 2020Q1 has only January–February and 2021Q3 has only August–September.
- A strict full-quarter panel would have 29 quarters and 754 state-quarter observations.
- The intended April 2022–December 2024 panel has 11 complete quarters, or 330 state-quarter observations for 30 states.
- None of these transformations changes the number of treatment clusters: 26 states in the balanced sample, with 17 legally treated; or 30 states in the post-COVID sample, with eight treated in-window.

Quarterly pooling must not be described as creating independent treated observations. The inferential sample size is still governed primarily by independently treated states and the number of treated states contributing to each horizon.

### Serial correlation and precision

Non-overlapping quarterly sums can suppress high-frequency reporting noise, monthly seasonality, and idiosyncratic month-to-month volatility. They may therefore improve the signal-to-noise ratio. They do not eliminate persistent state-level shocks; aggregation of a serially correlated process remains serially correlated. Inference must remain clustered at the state level.

Quartering also removes roughly two-thirds of time observations. Precision can improve or deteriorate depending on whether the reduction in high-frequency noise exceeds the information lost from fewer periods. That is an empirical operating-characteristics question, not a reason to assume smaller standard errors.

### Treatment-quarter construction

Coding the entire launch quarter as treated mixes pre-access and post-access months, with exposure shares varying mechanically by launch month. The preferred quarterly construction is:

- retain the exact operational launch month for treatment classification;
- omit the launch quarter for each treated state as a transition quarter; and
- define event quarter zero as the first complete quarter after launch.

Controls in a comparison quarter must be legally untreated for the entire quarter. This avoids comparing a fully exposed treated quarter with a partially exposed control quarter. As a sensitivity, code the launch quarter as treated and report expected attenuation from partial exposure.

Quarters adjacent to the deleted COVID interval should also be omitted if they contain fewer than three observed months. Calendar-quarter indices must preserve the real gap rather than compressing 2020Q1 and 2021Q3 into adjacent event periods.

### Event-time support

Quartering turns monthly lags into coarser quarterly lags; it does not restore treated states at the tails. In the audited post-COVID monthly support, only two treated states remain at +24 months. The corresponding approximately +8-quarter coefficient is therefore still identified by about two treated states. For post-COVID SA, use individual coefficients only over a compact window such as `e = -2,...,+4` quarters, where the monthly audit implies at least roughly six treated states remain. Bin more distant endpoints and label them low-support summaries.

In the full no-COVID sample, legal treatment for TN and VA occurs inside the deleted interval; Handle treatment for WV, PA, and IN does too. Quartering does not recreate their missing near-treatment outcomes. A single event study spanning the gap must show the number of contributing states at every event quarter and separately report clean-pre, clean-post, and cross-gap cells.

## 3. What Handle can and cannot do

### A. Handle as treatment timing: not recommended for causal headline

A first crossing of 50% of a fixed pre-2025 peak defines entry into an absorbing “ever reached high observed activity” regime. That is not the legal intervention. Timing depends on realized betting demand, operator entry, promotions, reporting coverage, market rules, local income, population, and macroeconomic conditions. Several of those determinants may also affect evictions.

Additional problems are decisive:

- The threshold uses post-treatment data and a future within-window peak, so treatment timing is selected using future market realizations.
- States below the threshold are already legally exposed. Treating them as not-yet-treated controls estimates a high-activity-regime contrast, not an access effect.
- Handle is total reported Handle, not a clean online-only measure.
- Florida is legally online from December 2023 but has no LSR observations. The current threshold merge can misclassify it as untreated. Nevada presents a related pre-sample-treatment classification risk.
- Threshold crossing is not an intervention that plausibly satisfies as-if-random timing conditional on the usual DiD controls.

CS/SA using this clock can be presented only as an exploratory timing sensitivity: “results when exposure onset is proxied by first observed high activity.” It must not be interpreted as the causal effect of legalization or as a causal dose response.

### B. Handle as a continuous treatment: descriptive unless a separate design is defended

Standard binary CS and SA do not estimate a continuous dose-response function. Regressing evictions on contemporaneous Handle conditions on a mediator and is confounded by state-specific demand and economic conditions. A continuous-treatment DiD would require stronger dose-specific parallel-trends and selection assumptions that are not supported merely because pre-legal Handle equals zero.

Instrumenting Handle with legalization is also not automatically valid. Legalization may affect evictions through participation, promotions, substitution from illegal markets, cross-border betting, or forms of betting not captured in reported Handle. The exclusion restriction required to interpret a 2SLS coefficient as the effect per dollar of reported Handle is therefore doubtful. Any such IV should be mechanism/exploratory evidence with an explicit complier and exclusion discussion, not the headline.

### C. Handle as a heterogeneity moderator: do not use realized own-state Handle

Grouping states by first-year average, cumulative, peak, or 50%-threshold Handle conditions on a post-treatment outcome. It can induce mediator or collider bias and changes group membership based on the treatment response itself. Such estimates are descriptive effect–take-up correlations, not causal CATEs.

Defensible moderators must be fixed before legal access: pre-legislation regulatory provisions, permitted operator counts written into law, tax rates fixed before launch, pre-period demographics, or a genuinely out-of-sample predicted ramp. Even then, variables that directly affect eviction trends require conditional-parallel-trends justification.

### D. Recommended role for Handle

Use Handle without conditioning the causal outcome regression on each state's realized post-treatment value:

1. verify that operational legal dates are followed by reported betting activity;
2. document the average ramp by event quarter;
3. use that external/descriptive ramp to pre-specify **common event-time windows**, for example launch/early, developing, and mature periods;
4. report whether the legal-access event-study shape is qualitatively consistent with the independently plotted Handle ramp; and
5. run state-specific Handle-threshold timing only as a labeled measurement sensitivity.

The causal treatment remains legal access. Handle explains why effects may be dynamic; it does not supply exogenous timing.

## 4. Ranked candidate strategies

### 1. Recommended: legal-access `did2s`, county panel, state-clustered inference

**Design:** Gardner two-stage staggered DiD, retaining county outcomes but recognizing state-level assignment.

**Estimand:** ATT of operational legal online access for treated county-quarters/state-quarters. Report a state-weighted overall ATT and event-quarter ATTs. Pre-specify an early window and a later/maturity window rather than allowing the supported-state composition to silently define “the” dynamic effect.

**Treatment:** first operational legal online-access date; omit the transition quarter in quarterly specifications.

**Comparison group:** stable never-online states through the study cutoff as primary. Do not call a legally online state with missing Handle untreated. Use not-yet-online states as a secondary comparison-group specification.

**Key assumptions:** untreated potential outcomes follow the first-stage state/county and calendar-time structure; no differential untreated trends after conditioning; no anticipation beyond the excluded window; no spillovers; stable measurement.

**Why first:** it avoids already-treated states identifying other treated states, has direct applied precedent on sports-betting policy, and the repository reports favorable calibration for the county-level version. It gives the referee a modern staggered-DiD headline without relying on naive TWFE.

**Important qualification:** `did2s` still relies on its untreated-outcome model and must be calibrated on the exact quarterly/monthly sample. It is not immune to COVID recovery, spillovers, or control contamination.

### 2. Secondary: legal-access CS aggregate and SA event study on quarterly data

**Design:** CS group-time ATT with never-treated controls; SA interaction-weighted event study.

**Estimand:** CS state-weighted aggregate ATT over a pre-specified supported event window; SA dynamic ATT by event quarter over a compact window.

**Comparison group:** never-online states primary; not-yet-online plus never-online sensitivity. Retail histories must be made comparable rather than silently mixed.

**Use condition:** report only if an exact-design simulation shows acceptable null rejection, coverage, SE/sampling-SD alignment, and economically relevant power. The existing monthly state-panel CS evidence fails the power criterion; quarterly aggregation requires fresh calibration and should not be presumed to reverse that conclusion.

**Why secondary:** legal quarter cohorts remain mostly singleton, SA tails rapidly lose treated states, and the state-panel CS oracle MDE is already far outside plausible effect sizes.

### 3. Robustness: BJS/imputation and generalized synthetic control

BJS supplies a point-estimate comparison but needs careful inference when adoption periods contain very few treated states. Generalized synthetic control is useful because it constructs state-specific counterfactuals without pretending singleton dates are large cohorts. Both must enter the same design-matched calibration harness before inferential claims.

### 4. Exploratory only: quarterly 50%-Handle CS/SA or continuous Handle regressions

These analyses describe high-realized-activity regimes or effect–intensity associations. They do not identify the causal effect of legal access without substantially stronger assumptions.

## 5. Comparison groups and treatment regimes

“Online access” currently combines two different transitions:

- online-first/simultaneous launch: from no legal sports betting to online access;
- retail-to-online launch: from retail-only access to online access.

The cleanest implementation estimates these strata separately, then reports a pre-specified treated-state-weighted average if desired:

- online-first treated states versus states with no legal betting through the relevant comparison horizon;
- retail-to-online treated states versus retail-only states that remain offline through that horizon.

If sample size prevents credible stratum-specific inference, retain the pooled access ATT but state that it averages different policy transitions and show the two-stratum results as low-powered mechanism checks.

Cross-border access violates the untreated-control definition even when state law is unchanged. At minimum, reproduce the literature's distance-based robustness using control-state counties farther than 60 miles from a legal-state border and report the full distance gradient.

## 6. Estimation and inference specification

### Primary estimator

1. Estimate untreated outcomes using only state-quarters/county-quarters not yet legally online, with unit and calendar-quarter fixed effects. Never-treated controls are primary.
2. Residualize all observations with respect to this untreated-outcome model.
3. Regress residualized outcomes on post-access/event-quarter indicators.
4. Aggregate using explicit state weights so large states or states with many counties do not inadvertently dominate unless population weighting is the declared target.
5. Cluster at the state level and add restricted wild-cluster-bootstrap inference. Report placebo-date/randomization-inference p-values as a complementary small-cluster diagnostic.

### CS

- Estimate `ATT(g,t)` using legal first-full-quarter cohorts.
- Lead with never-treated controls; use not-yet-treated controls as robustness.
- Aggregate first by treated state and event quarter, then into the pre-specified summary window, so the estimand does not receive opaque last-pre-period or unbalanced-panel weights.
- Store and report treated states, comparison states, and weight for every `ATT(g,t)` cell.
- Do not use naive normal critical values as the only inference. Use the calibrated inferential method and disclose simulation rejection and coverage.

### SA

- Use legal-access cohort-by-event-quarter interactions, omitting `e=-1`.
- Restrict individual coefficients to supported horizons; bin endpoints.
- Report the number of treated states and cohorts beneath every plotted coefficient.
- Do not interpret a long-horizon coefficient supported by two states as general evidence about mature markets.

### Why not naive TWFE

Naive staggered TWFE can mix already-treated and newly treated comparisons and assign nontransparent weights under heterogeneous dynamic effects. It should be a comparison estimate and weight diagnostic, not the headline. Agreement with `did2s`, CS/SA point estimates, and GSC is useful evidence that heterogeneity weighting is not driving the result; disagreement is a reason to investigate, not to select the preferred estimate ex post.

## 7. Specification-level pseudo-code

```text
INPUTS
  monthly county/state eviction panel
  exact operational online-launch dates
  retail/first-access dates
  monthly Handle, used only for validation and ramp summaries

CLASSIFY STATES
  pre-sample online -> exclude from untreated pool
  online within sample -> legally treated
  never online through cutoff -> candidate control
  legally online but missing Handle -> treated for legal-access design;
                                       missing for Handle analyses, never control
  record retail-before-online status

BUILD QUARTERLY OUTCOME
  quarter = calendar quarter(month)
  require all 3 monthly observations per unit-quarter
  quarterly filings = sum(monthly filings)
  quarterly renters = mean(monthly renter households)
  quarterly filing rate = quarterly filings / quarterly renters * 1,000
  omit partial quarters adjacent to COVID deletion

DEFINE LEGAL TREATMENT
  launch_quarter_i = quarter(operational online date_i)
  omit unit i's launch quarter
  first_full_quarter_i = launch_quarter_i + 1
  D_iq = 1[q >= first_full_quarter_i]
  event_q_iq = q - first_full_quarter_i
  preserve actual calendar-quarter gaps

DEFINE HANDLE MEASUREMENT (NOT CAUSAL TREATMENT)
  merge Handle after legal launch; keep missing values missing
  calculate event-quarter average Handle ramp for plots
  pre-specify common event windows from external/descriptive ramp:
      early, developing, mature
  never create untreated status from missing Handle

PRIMARY DID2S
  untreated sample = D_iq == 0 under legal timing
  stage 1: outcome ~ unit FE + calendar-quarter FE, untreated sample only
  stage 2: residual ~ event-quarter indicators / post indicator
  aggregate with explicit treated-state weights
  inference: state cluster + restricted wild bootstrap

SECONDARY CS
  ATT(g,q), g = first_full_quarter_i
  controls = never-online; then not-yet-online sensitivity
  aggregate only supported cells in pre-specified window

SECONDARY SA
  interaction-weighted cohort x event-quarter regression
  reference e = -1
  bin tails; display contributing treated-state counts

CALIBRATION GATE
  simulate null and plausible ramp effects on exact sample skeleton
  for each estimator and horizon report:
      null rejection, coverage, sampling SD, mean SE, SE/SD, MDE
  headline eligibility requires nominal size/coverage and plausible MDE

ROBUSTNESS
  monthly vs quarterly
  launch-quarter included vs omitted
  never vs not-yet controls
  online-first vs retail-to-online strata
  border-distance restrictions
  levels vs logs
  COVID-clean cell subsets
  leave-one-treated-state-out
```

## 8. Robustness plan

Ordered by importance:

1. **Treatment-source integrity.** Assert that the estimator resolved the requested legal or Handle schedule; fail on disagreement. Keep Florida and other legally online/missing-Handle states out of the Handle control pool. Exclude or explicitly classify Nevada and other pre-sample-access states.
2. **Exact-design calibration.** Re-run null size, coverage, SE/SD, horizon-specific calibration, and power on the quarterly skeleton. Report rather than hide a failed gate. Quartering is useful only if calibration and MDE improve materially.
3. **Monthly versus quarterly legal timing.** Compare legal-access point estimates and supported windows. Explain that quarterly estimates average exposure over longer intervals.
4. **Transition-quarter rule.** Primary omits the launch quarter; sensitivity treats it as exposed. A larger effect after omission is consistent with attenuation from partial exposure.
5. **Comparison groups.** Never-online primary; not-yet-online secondary. Audit how the control composition changes in every quarter.
6. **Retail history.** Separate online-first/simultaneous launches from retail-to-online transitions; use no-betting and retail-only controls respectively.
7. **Cross-border contamination.** Exclude control counties within 60 miles of a legal border; estimate distance bands and border-state exclusions.
8. **COVID and backlog.** Report clean-pre, clean-post, and cross-gap estimates. Exclude cohorts treated near reopening and test balance at panel re-entry.
9. **Functional form.** Estimate log filings/count or log rate and levels of filings per 1,000 renters. Do not imply that parallel trends in one scale establishes it in another.
10. **Event-window stability.** Compare compact supported windows; show how the estimate changes when the low-support tail is added. Never choose a window from the outcome plot.
11. **State influence.** Leave one treated state out, recomputing cohorts, support, and weights each time. Report when deletion changes the estimand.
12. **Estimator triangulation.** `did2s` headline; CS, SA, BJS, GSC, and TWFE point-estimate comparisons. Use only estimators that pass the same calibration gate for inference.
13. **Handle measurement sensitivities.** Plot 25%, 50%, 75%, cumulative, and per-capita ramp definitions as descriptive checks. Do not relabel threshold results causal.
14. **Outcome measurement.** Require complete unit-quarter coverage; compare state aggregation with county-quarter data; audit changes in ETS coverage and filing definitions.
15. **Multiple inference.** Define one headline ATT family. Use simultaneous bands for event studies and Holm or Romano–Wolf adjustment for planned secondary outcomes/windows.

## 9. Falsification tests

1. **Exact-sample leads.** Estimate pre-treatment legal-access event-quarter coefficients on the exact headline sample. Report joint tests, equivalence bounds, and power/MDV; do not condition the choice of estimator on passing a low-powered pretest.
2. **HonestDiD sensitivity.** Report how large post-period trend deviations must be to overturn the headline interval.
3. **Pseudo-launch dates.** Assign calendar-preserving placebo dates only under an exchangeable and documented assignment scheme; verify host-state composition and support before interpreting rejection rates.
4. **Future-treatment placebo.** Test whether future legal access predicts current evictions in periods safely outside any anticipation window.
5. **Placebo court outcomes.** Use non-landlord/tenant civil filing categories, if measurement is comparable, that should not respond through the proposed household-finance mechanism.
6. **Handle first-stage validation.** Legal operational access should precede, not follow, the onset of reported online-era Handle. Failures indicate treatment-date or source problems, not evidence for a different causal clock.
7. **Fast- versus slow-ramp pretrend diagnostic.** Before legalization, eventual fast- and slow-ramp states should not exhibit differential eviction trends. Failure demonstrates selection into realized ramp speed and rules out causal post-Handle subgroup claims.
8. **Control-contamination gradient.** Effects in nominal control counties should be stronger near legal borders and decay with distance if spillovers are present. A flat gradient does not prove no spillovers, but a strong gradient invalidates SUTVA for the unrestricted control group.
9. **Panel re-entry placebo.** Around the first complete post-COVID quarter, compare untreated outcome level/trend changes across future-treated and control states. Differential jumps flag backlog recovery rather than gambling exposure.

## 10. Top five anticipated referee objections

### 1. “You chose the Handle threshold because it improves cohorts or pretrends.”

**Response:** Do not use Handle timing for the headline. Define operational legal access before inspecting outcomes. Present 50%-Handle timing only as a labeled exposure-measurement sensitivity, disclose its future-peak construction, and show 25/50/75% alternatives.

### 2. “Quartering does not solve the few-treated-cluster problem.”

**Response:** Agree and state it explicitly. Quartering reduces noise and coarsens dates; it does not create new assignment clusters. Report 17 legally treated states, 14 quarter cohorts, 11 singleton cohorts, state-clustered inference, design-matched calibration, and the MDE. Use county `did2s`, not state CS/SA, as the headline unless quarterly CS/SA unexpectedly clear the pre-specified calibration and power gates.

### 3. “SA/CS long-horizon effects are driven by one or two states.”

**Response:** Restrict the displayed dynamic window, bin tails, place contributing-state counts under every coefficient, report state-equal aggregations, and provide leave-one-state-out estimates. Treat mature-horizon estimates with fewer than a pre-specified minimum number of treated states as descriptive.

### 4. “Your controls are treated through retail access, cross-border mobile betting, or missing Handle.”

**Response:** Separate online-first and retail-to-online transition estimands; never use legally online/missing-Handle states as controls; classify pre-sample treated states explicitly; use distance-to-legal-border restrictions and retail-status-matched comparisons.

### 5. “The result reflects COVID recovery, court backlogs, or functional form rather than legalization.”

**Response:** Preserve the calendar gap, omit partial quarters, decompose clean-pre/clean-post/cross-gap comparisons, exclude reopening-adjacent cohorts, test panel re-entry balance, and report both log and level outcomes with HonestDiD bounds.

## 11. Go/no-go rule for CS and SA

Quarterly legal-timing CS/SA are **usable as secondary estimators now in principle**, provided the treatment-source and sample-classification errors are repaired and every result carries a support table. They become defensible for headline inference only if exact-design simulations demonstrate all of the following:

- null rejection close to the nominal level and approximately 95% interval coverage;
- mean reported SE reasonably aligned with the simulated sampling SD, overall and by event quarter;
- no headline coefficient supported by only one or two treated states;
- an 80% MDE within the range of effects the substantive literature makes plausible; and
- stability to never-treated controls, retail-history restrictions, border exclusions, and state deletion.

The existing state-panel evidence already fails the economically relevant power condition by a wide margin. Quarterly coarsening can be tested, but there is no basis to expect it to overcome the state-level information deficit. Handle-based cohort pooling cannot supply the missing exogenous clusters.

## Bottom line

Quarterly outcomes are a sensible robustness design and may make CS/SA plots less erratic. Handle is valuable for showing that exposure ramps and for defining ex ante event-time summaries. The two should **not** be fused into a headline “Handle-treatment CS/SA” design: that trades a support problem for an identification problem.

The referee-safe answer is not “use TWFE anyway.” It is “lead with calibrated legal-access `did2s`, show quarterly legal-access CS/SA as transparent secondary evidence, report support and MDEs, and keep realized Handle on the mechanism/measurement side of the design.”
