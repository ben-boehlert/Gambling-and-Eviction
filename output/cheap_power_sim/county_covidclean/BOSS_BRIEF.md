# Gambling → Evictions: Power Triage Summary (2026-08-13)

**Takeaway: with the eviction data we currently have, no specification is both
credible through COVID and powered for plausible effect sizes — the credible
(COVID-clean) designs have minimum detectable effects of roughly 40–70% of a
mature-market gambling effect, versus the ~2.5–10% range that theory and the
credit-outcomes literature (Hollenbeck et al. 2025) make plausible. Expanding the
eviction panel (court records) is the only route to a design that is
simultaneously valid and powered; no estimator or inference fix changes this.**

## The numbers (Monte Carlo on real untreated eviction data, known injected effects)

Effects are proportional changes in eviction filings at gambling-market maturity,
delivered through each state's actual observed betting-handle ramp-up. "Oracle
MDE" = smallest mature effect detectable at 80% power even with perfectly
calibrated inference — i.e., a pure information measure.

| Design | Why it matters | Null SD of estimate | Oracle 80% MDE (mature effect) |
|---|---|---:|---:|
| State-month C&S, full panel | Original headline spec | 0.065–0.14 | **~40–86%** |
| State-month, pre-COVID cells only | Cleanest identification | 0.04–0.07 | ~40% |
| County did2s, pre-COVID regime only | Best slice found anywhere | 0.044 | ~30% |
| **County did2s, post-COVID regime only** | **The COVID-defensible spec** | 0.10–0.12 | **~56–67%** |

Key structural facts behind the county number: restricting to post-COVID
identification (required, because imputation estimators like did2s assume a
common untreated-trends model that state-specific COVID shocks violate) leaves
only 14 states and 5 usable adoption cohorts (Sep 2022–Jan 2024). County
disaggregation does not rescue power because inference is clustered at the
state level — the state count, not the county count, is binding. Test size is
also inflated there (did2s rejects a true null 33% of the time at nominal 5%
with 14 clusters), but that is second-order: the oracle numbers ignore
inference entirely and still come out an order of magnitude above plausible
effects.

## What this establishes

1. **Not a null result — an uninformative design.** The correct claim is "state
   ETS data cannot resolve gambling→eviction effects below ~40%," not
   "gambling doesn't affect evictions."
2. **The result is robust to how we simulate.** Verified three ways: placebo
   reassignment, a balanced exchangeable subset, and a design-preserving
   simulator that keeps all real treatment timing/missingness and varies only
   untreated outcome paths (Black et al.-style generator-sensitivity check).
3. **Two methods findings worth keeping** (independent value): (a) the C&S
   estimator carries a deterministic bias (~−0.07 here) on unbalanced panels
   via its repeated-cross-section path — fixable by balancing or state-demeaning;
   (b) the cluster-jackknife (CV3) fix for C&S inference over-corrects ~1.8×
   in singleton-cohort designs because deleting a state changes the estimand.
4. **The constructive fact (see figure `exposure_post_recovery.png`):**
   treatment *dose* is overwhelmingly a post-COVID phenomenon regardless of
   statute date. Using the month never-treated states' filings returned to
   ≥95% of pre-pandemic baseline (Sep 2021) as the recovery point: all 8
   during-COVID legalizers wagered 88–99% of their cumulative handle after
   recovery, 15 states legalized entirely after, and even the earliest
   adopters (NJ/WV, 2018) are 71–75% post-recovery. Dollar-weighted, ~91% of
   all U.S. online-era handle post-dates the eviction recovery. (Refreshed
   2026-08-14 with the updated LSR series through May 2026, adding WV and the
   newly launched MO.) An exposure-timed
   design can therefore recover the during-COVID legalizers for clean
   post-recovery identification — the main lever for improving power without
   new data.
5. **Implication for the Arnold ask:** the court-records panel expansion is not
   an enhancement, it is the binding constraint — more treated states with
   long, COVID-clean coverage is the only way to shrink the MDE into the
   plausible-effect range. The simulation framework built this week produces
   the exact power numbers for any proposed expanded panel before we buy data.

*Basis: ~1,500 Monte Carlo estimations on real ETS eviction panels (2016–2025),
repaired legalization schedule, observed LSR handle ramps; 100–250 reps per
cell; full methodology and outputs in the project repo
(`output/cheap_power_sim/`, `analysis/cheap_sims/`).*
