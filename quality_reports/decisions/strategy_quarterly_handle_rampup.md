# Decision Record: Quarterly Outcomes and Gambling-Handle Ramp-Up

**Date:** 2026-08-14

## Decision

Use operational legal online access—not realized gambling Handle—as the causal treatment. The prospective headline design is a precisely defined, COVID-clean, legal-access two-stage DiD (`did2s`) on the county panel with state-level inference and explicit state weighting, conditional on exact-design calibration. Quarterly legal-timing Callaway–Sant'Anna and Sun–Abraham estimates may be reported as secondary, short-horizon triangulation if their full procedures pass calibration. Use Handle to document the first stage and market ramp-up and to motivate common event-time windows; label state-specific Handle-threshold estimates exploratory.

## Alternatives Considered

1. Quarterly CS/SA with first crossing of 50% of observed peak Handle as treatment.
2. Quarterly CS/SA with operational legal online dates.
3. Continuous or thresholded Handle as a causal dose.
4. Naive staggered TWFE as the headline.
5. BJS imputation, generalized synthetic control, and randomization inference as complements.

## Why Alternatives Were Not Chosen as the Headline

- **Handle-timed CS/SA:** realized Handle is post-treatment and its threshold date depends on betting demand, market rules, promotions, reporting, economic conditions, and a future within-window peak. Already-online states below the threshold are not untreated controls.
- **Legal-timing CS/SA:** quarterly aggregation does not add independent treated states. In the balanced sample, 17 treated states still form 14 legal launch-quarter cohorts, 11 of them singletons; long horizons rapidly lose support.
- **Continuous Handle:** standard binary CS/SA do not identify this dose response, and contemporaneous Handle is an endogenous mediator. A legalization instrument would require a doubtful exclusion restriction.
- **Naive staggered TWFE:** under heterogeneous dynamic effects it can use already-treated comparisons and opaque weights. It remains a diagnostic benchmark only.
- **Other modern estimators:** useful for triangulation, but each requires the same design-matched calibration and exact support disclosure before inferential use.

## Key Assumptions

- Conditional parallel trends for untreated eviction outcomes under the exact legal-access sample and outcome scale.
- No material anticipation outside the declared transition window.
- No untreated-control contamination from retail betting, cross-border online access, or missing Handle classification.
- No differential COVID backlog/reopening dynamics in the primary COVID-clean comparisons.
- State-level inference correctly propagates the full two-stage estimation and weighting procedure.
- The event-time window and state weights are fixed before outcome inspection.

## What Would Invalidate or Change the Decision

- Exact-design simulations show materially non-nominal size, poor coverage, SE-to-sampling-SD mismatch, or an MDE outside the substantively relevant range.
- The prospective headline assigns substantial weight to cross-COVID contrasts or gap-treated cohorts without credible local counterfactuals.
- Exact-sample pretrend, equivalence, or HonestDiD analyses reveal economically important violations.
- Results are driven by one treated state, one cohort, contaminated border controls, or retail-history composition.
- Treatment-source audits show legally online or pre-sample-treated states entering the untreated pool.
- A defensible external source of exogenous Handle variation becomes available, permitting a separately justified dose-response design.
