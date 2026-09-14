# Is the simulated null bias an artifact, or a real selection-on-trends problem?

**Date:** 2026-09-14
**Script:** [`analysis/diagnostics/nullbias_real_schedule_check.R`](../../analysis/diagnostics/nullbias_real_schedule_check.R)
**Output:** [`output/nullbias_real_vs_sim/`](../../output/nullbias_real_vs_sim/)
**Bears on:** FINDINGS §2 (recentering), [`quality_reports/nullbias_decomposition_2026-08-25.md`](../../quality_reports/nullbias_decomposition_2026-08-25.md)

## The untested premise

The 2026-08-25 decomposition traced the +0.9 SD null center to `cor_date_trend` — across
pseudo-treated states, the correlation between pseudo-adoption month and that state's own real
trend slope. It is negative in 4,000/4,000 draws (mean −0.194), caused by the eligibility
structure of `.assign_cohorts()`. FINDINGS §2 concluded recentering is "the correct handling
rather than a patch."

That rests on a premise nobody tested: **that the correlation is an artifact of pseudo-placement.**
If the real schedule shows the same correlation, the simulated bias is not an artifact — it is a
faithful reproduction of a real selection-on-trends problem.

## Result

Same feature as the memo (`lm(y_log1p ~ t)` per state on the covid-drop panel), against the
**real** online-legalization dates:

| Quantity | Value |
|---|---|
| Real `cor_date_trend`, 24 online legalizers (ex NV/ID/HI/MS) | **−0.212** (95% CI −0.567, +0.209; p = 0.320) |
| Real, Spearman | −0.146 |
| Real, restricted to the 13 clean-anchor switchers | −0.124 (Spearman −0.168) |
| Simulated, 4,000 draws | mean −0.194, sd 0.094, 98.7% negative |
| **Percentile of the real value in the simulated distribution** | **43.3%** |

**The real schedule sits in the middle of the simulated distribution.** The pseudo-placement is not
generating a correlation the real design lacks — it is reproducing one the real design appears to
have, slightly more negative than the simulated mean.

## What follows

1. **The premise behind recentering is not supported.** Recentering is valid if the null center is
   an artifact of the placebo machinery. This says it probably is not. Recentering then removes
   from the size gate a bias the real estimate genuinely carries — and no one can recenter a
   real-data estimate, because the real null center is unknown.
2. **This is an identification problem wearing an inference costume.** A negative date/trend
   correlation is selection-on-trends: later adopters have systematically different pre-existing
   trajectories. That belongs in the parallel-trends channel, not in a size correction.
3. **It converges with the pretrends finding.** `lpdid_pretrends_shift12_clean` (2026-09-06) already
   reports that Roth (2022) pretest power is weak enough that a trend the pretest would miss half
   the time implies up to 0.20 log pts of bias on the 12–24 ATT — larger than the 0.127 MDE. Two
   independent diagnostics point at the same vulnerability.

## Caveat that limits how hard this can be pushed

The real correlation is estimated on 24 states (13 for the switcher-restricted version), so it is
very imprecise: the 95% CI is [−0.567, +0.209] and p = 0.320. It is consistent with the simulated
mean, but also consistent with zero. **This does not prove the real design carries the bias.** What
it does establish is the weaker, sufficient claim: the data give no support for treating the
simulated bias as a pure placebo artifact, which is what recentering assumes.

## Recommended handling (not yet decided)

Report **both** raw and recentered size in the PAP and disclose the gap, rather than
pre-registering the recentered number alone as FINDINGS §2 currently proposes. Route the
substantive concern to HonestDiD sensitivity, where FINDINGS already reports that Mbar = 1
quadruples the null bound (±0.092 → ±0.34). Decide before unblinding — do not shop after.

---

## Addendum (same day): is `cor_date_trend` the same thing HonestDiD measures?

**No — near-orthogonal objects in this sample.** Per-state trend slopes (log pts/yr) on the
covid-drop panel, split two ways:

| Object | Value | What it is |
|---|---|---|
| Treated vs never-legal mean slope gap | **+0.011 log pts/yr** (95% CI −0.025, +0.046; p = 0.533) | the pooled differential trend that pre-period event-study coefficients estimate — **HonestDiD's anchor** |
| Within-treated timing gradient | **−0.034 log pts/yr** across the 88-month adoption span (−0.00039/month) | trend heterogeneity correlated with adoption timing — **what `cor_date_trend` captures** |

The treated-vs-control contrast is essentially zero while the within-treated gradient is not. A
design can therefore look clean to a pooled pre-trend test and still carry the bias the simulation
exhibits, because in staggered DiD with not-yet-treated controls **every cell compares a switcher to
a not-yet-launched pool whose trend composition shifts with event time** — that bias does not
require the treated group's average slope to differ from the controls'.

HonestDiD partially covers this (event-study coefficients do aggregate across cohorts, so a timing
gradient can leave a pre-period footprint), but its relative-magnitudes assumption bounds
post-period violation by *observed pre-period* violation, and in a staggered design the comparison
set is not held fixed across that boundary. **HonestDiD remains the right reporting channel; it is
not a substitute diagnostic for the timing gradient, and citing it does not dispose of the
recentering question.**

### Robustness of the real correlation (important)

- Leave-one-state-out jackknife: **all 24/24 values negative**, range [−0.262, −0.055]. Sign is stable.
- But the magnitude is leverage-driven: dropping **MO** alone moves it from −0.212 to −0.055.
- A median split on adoption timing shows **no gradient** (early −0.0159, late −0.0131 log pts/yr).

So the relationship is carried by the tails of the adoption-timing distribution, not by a monotone
trend. Read the sign as suggestive and the magnitude as unreliable at n = 24.

**Figure:** `figures/mo_leverage_cor_date_trend.{png,pdf}` ([`analysis/visualization/plot_mo_leverage.R`](../../analysis/visualization/plot_mo_leverage.R)). MO is extreme on both axes and its slope is not comparable to the others':

| | MO | other 23 |
|---|---|---|
| Online legalization | 2025-12 (21 months after NC, the next-latest) | 2018-08 .. 2024-03 |
| Trend slope | **-0.088 log pts/yr** (most negative bar LA) | mostly -0.03 .. +0.02 |
| Calendar window the slope is fit on | **2012-01 .. 2023-01** | typically 2016-01 .. 2025-09 |

**MO's slope is estimated entirely on data that ends 35 months BEFORE MO legalizes**, on a calendar window that barely overlaps the other states'. It is not a comparable observation, and it is single-handedly producing the magnitude of the correlation. LA has a comparably extreme slope (-0.11) but sits mid-range on timing, so it carries almost no leverage -- confirming the issue is MO's position on the timing axis, not its slope alone.
