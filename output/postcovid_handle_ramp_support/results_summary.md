# Post-COVID Handle-ramp support diagnostic

## Answer

A Handle-ramp definition is **not credible as the main treatment date**. Handle is realized after legalization, responds to demand and policy, and is seasonal. Reclassifying legally exposed months as untreated therefore changes the estimand from legal access to market maturation and imposes a strong no-effect-during-ramp assumption.

There is one plausible exploratory sensitivity: Arkansas at 25% of its frozen peak (September 2022). Arkansas legalized online in March 2022, only one month before the analysis window, and the 25% date joins Kansas's September 2022 cohort. Within the common Handle-measured sample, this adds one state without adding a cohort. Relative to the full legal-date ITT sample, however, Arkansas replaces rather than augments Florida because Florida lacks Handle data. It is still post-treatment timing, so it should be labeled as an exploratory different-estimand sensitivity only.

The 50% definition adds Arkansas as a new singleton cohort. The 75% and sustained-50% definitions add more nominally treated states, but do so by calling long-established legal markets untreated until later, often football-season Handle peaks. Their apparent cohort pooling is not an identification improvement.

## Balanced post-COVID sample

| Treatment clock | Treated states | Cohorts | Singleton cohorts | States in singleton cohorts | Incremental states vs common-sample legal |
|---|---:|---:|---:|---:|---:|
| Online legal | 7 | 6 | 5 | 71.4% | +0 |
| Handle 25% | 8 | 6 | 4 | 50.0% | +1 |
| Handle 50% | 8 | 7 | 6 | 75.0% | +1 |
| Handle 75% | 13 | 8 | 5 | 38.5% | +6 |
| Sustained Handle 50% | 8 | 8 | 8 | 100.0% | +1 |

The table uses the 28-state common Handle-measurement sample observed in all 33 months from April 2022 through December 2024. Florida is excluded because Handle is missing, and Nevada is excluded as pre-sample treated.

**Comparison caveat:** the full legal-date ITT sample can retain Florida and contains 8 treated states in 7 cohorts. The common-measurement legal row above contains 7 treated states in 6 cohorts, while Handle 25% contains 8 treated states in 6 cohorts after Arkansas replaces Florida. Thus, the Handle-25 design does not increase treated-state N relative to the actual legal-date main design. A hybrid that keeps Florida on the legal clock and Arkansas on the Handle clock would mix estimands and is not recommended.

## Pre-window legal states moved into the post-window treatment set

| State | Clock | Effective month | Post-window pre-threshold months | Handle/peak at window start | Cohort size | Recommendation |
|---|---|---|---:|---:|---:|---|
| AR | handle_25 | 2022-09 | 5 | 13.0% | 2 | sensitivity_only_preferred |
| AR | handle_50 | 2023-03 | 11 | 13.0% | 1 | sensitivity_only_speculative |
| AR | handle_50_sustained | 2023-09 | 17 | 13.0% | 1 | sensitivity_only_speculative |
| AR | handle_75 | 2023-11 | 19 | 13.0% | 3 | reject_as_untreated |
| CT | handle_75 | 2023-10 | 18 | 47.8% | 3 | reject_as_untreated |
| LA | handle_75 | 2023-11 | 19 | 50.4% | 3 | reject_as_untreated |
| NY | handle_75 | 2023-01 | 9 | 60.0% | 2 | reject_as_untreated |
| TN | handle_75 | 2023-11 | 19 | 49.3% | 3 | reject_as_untreated |
| VA | handle_75 | 2023-10 | 18 | 52.5% | 3 | reject_as_untreated |

## CS and SA implications

Every treatment clock still has small cohorts. Under CS, the share of group-time cells attached to cohorts smaller than five ranges from 100.0% to 100.0%. All mechanically constructed cells retain at least one eligible not-yet/never-treated control, so treated-cluster leverage—not formal control existence—remains the constraint.

For SA, the number of contributing treated states at event month +12 ranges from 5 to 11 across definitions. More nominal treatment dates do not create more independent states, and tail support remains thin.

## Credibility ranking

1. **Arkansas, 25% Handle: exploratory sensitivity preferred.** It is the smallest estimand departure and expands an existing common-sample cohort from one to two states, but does not add a net treated state relative to the full legal ITT.
2. **Arkansas, 50% or sustained 50%: speculative sensitivity.** Adds one state but generally as a singleton after many legally exposed months.
3. **75% Handle candidates and delayed sustained crossings in established markets: reject.** They depend heavily on realized growth, peak normalization, and sports seasonality.

## Is it worth including?

Possibly, but only as one clearly labeled exploratory market-maturation sensitivity using Arkansas's 25% date. It provides a stress test of the post-COVID sample and slightly improves the September 2022 cohort within the Handle-measured sample, but it does not increase treated-state N over the full legal ITT. It is **not enough to change the small-cohort diagnosis**, justify CS/SA as headline estimators, or replace legal-date treatment. Report the legal-date design first and explain that the Handle clock is an endogenous maturation estimand.

## Identification caveats

- Handle thresholds are post-treatment and may respond to the same economic conditions that affect evictions.
- A threshold design assumes no effect of legal betting below the selected threshold; this cannot be verified from Handle support alone.
- Frozen own-state peak normalization avoids future data revisions after 2024, but it makes thresholds relative and state-specific.
- Seasonal clustering—especially at 75%—can manufacture larger fall cohorts without adding independent quasi-experimental variation.
- Candidate states are not valid legal-access controls during their ramp months; they are only pre-effective observations under the alternative maturation estimand.

## Paper-to-code naming map

| Paper notation | Code name | Description |
|---|---|---|
| $Y_{st}$ | `filings_count` | State-month eviction filings (not modeled here) |
| $G_s^{legal}$ | `legal_online_start` | Online legalization month |
| $G_s^{25}$ | `handle_25_date` | First 25%-peak month |
| $G_s^{50}$ | `handle_50_date` | First 50%-peak month |
| $G_s^{75}$ | `handle_75_date` | First 75%-peak month |
| $G_s^{50,S}$ | `handle_50_sustained_date` | First of three consecutive 50%-peak months |
| $e_{st}$ | `event_time` | Months relative to effective treatment |

## Reproducibility

Run `Rscript analysis/diagnostics/postcovid_handle_ramp_support.R` from the project root. No outcome model is fitted and no production panel or runner is modified.
