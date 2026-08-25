# Long differences as a pseudo-treatment experiment — design, era stress test, power

**Date:** 2026-08-19 · **Branch:** `power-cs-arm-and-shift-mode`
**Scripts:** [`analysis/diagnostics/longdiff_2x2_pseudo_power.R`](../analysis/diagnostics/longdiff_2x2_pseudo_power.R),
[`analysis/diagnostics/longdiff_era_variance.R`](../analysis/diagnostics/longdiff_era_variance.R)
**Outputs:** `output/longdiff_2x2_pseudo/`, `output/longdiff_era_variance/`

---

## 1. What changed and why

The previous plan truncated each state's panel at its own legalization date and
kept the real 2024-25 endpoint. Under the blindness protocol that leaves **6
usable states** at Ben's calendar — a 6-state design can only describe a
6-state design, so the resulting MDE would have been uninterpretable.

The fix, following **Black, Hollingsworth, Nunes & Simon (2022)**, who move the
ACA experiment from 2014-16 back to a 2011 pseudo-treatment: shift the *whole*
long-difference experiment into the pre-treatment era. No state legalized sports
betting of any kind before **2018-06** (DE, NJ), so an experiment placed wholly
before that date is untreated by construction — no per-state truncation, no
blindness cutoff, and the full state count survives.

## 2. The substrate question, and why it forced a data switch

Preserving the real geometry means preserving three things at once: **counts**
(~22 treated / 15 control), **window widths** (24-month baseline, 12-month
endpoint), and **baseline-to-endpoint distance** (~70 months).

The ETS monthly panel cannot host this. Its untreated era is
**2016-01 .. 2018-05 = 29 months** — a 24-month baseline and a 12-month endpoint
do not even fit disjointly, let alone with a 70-month gap.

The **annual county court panel**
(`data/raw/county_court-issued_2000_2023_ben_update_5_12.csv`, 2000-2023) does.
Measured, not assumed:

| calendar | states | counties | distance | split |
|---|---|---|---|---|
| **CY2008+2009 → CY2016 (primary)** | **37** | **1,549** | **72 mo** | **22 online-ever / 15 never** |
| CY2009 → CY2016 (12-mo baseline) | 39 | 1,595 | 72 mo | — |
| CY2010+2011 → CY2016 (crisis-free) | 42 | 1,897 | 61 mo | — |
| CY2010+2011 → CY2017 | 32 | 1,342 | 61 mo | breaks 22/15 |

The primary calendar matches the real design's 24/12 widths, its 70-month
distance (to within 2 months), and its 22/15 state split almost exactly. Every
year used predates the universal cutoff (2018-05-31), so the whole window is
untreated — this belongs in the protocol's deviation log as an approved
additional untreated input, not as a silent read.

Two substrates, two jobs: the **annual** file hosts the geometry-preserving
power simulation; the **ETS monthly** panel hosts the era-noise stress test and
the averaging-window exercise, which need monthly resolution.

## 3. Design as built

- **Assignment:** random, preserving 22 treated / 15 control, redrawn each rep.
  That is what makes this a power simulation rather than one placebo — and the
  same draws serve as the randomization-inference reference set.
- **Estimator:** county-level weighted 2x2 on the long difference
  `dY_c = log1p(filings_end) − mean log1p(filings_baseline)`, renter-weighted,
  state-clustered.
- **Effect imposition:** `count_nb` — extra filings drawn NegBin with mean
  `mu(exp(δ)−1)` and var/mean = 1.4, matching `R/power/impose_effects.R`, so
  results are comparable to every other arm in the framework.
- **Inference:** randomization inference **primary** (exact under the sharp
  null, immune to the MacKinnon-Webb fragility of cluster inference at 37
  unbalanced clusters); state CRVE and a null-imposed Rademacher wild cluster
  bootstrap reported alongside.
- **Reported per Black et al.:** size at δ=0, power curve, MDE-80, and —
  conditional on significance — sign-error rate (Type S) and exaggeration
  ratio (Type M).

## 4. Stress test — does the pre-2018 era understate post-COVID noise? **Yes, by 2-4x.**

This is the load-bearing caveat on any pre-era MDE. σ is the SD across states of
the state-level long difference, which is exactly what the clustered SE is built
from. Windows are slid over every feasible placement, at **matched geometry and
matched distance** on both sides, on states untreated in both eras.

**Median post/pre σ ratio across all 18 geometries** (never-online states,
Idaho pre-excluded — see below):

| statistic | median ratio | range |
|---|---|---|
| SD | **2.67** | 1.76 – 5.19 |
| SD, most extreme state trimmed | 1.94 | — |
| MAD-based | 2.09 | — |

Strict never-any-legalization states (only ~6 clear pre-era coverage, so
directional): median SD ratio **3.86**, range 1.71 – 7.38.

Three details that matter:

1. **The raw comparison inverts if Idaho is left in.** ID is the single most
   extreme state in **100%** of pre-era placements, and CLAUDE.md already
   excludes it for data quality. With ID in, the pre-era SD is *larger* than the
   post-era SD at wide geometries — an Idaho artifact, not an era effect. The
   trimmed and MAD statistics agreed with the ID-excluded answer all along.
2. **The gap widens with window width**: ~1.5-2x at a 1-month endpoint, ~3.9-4.4x
   at a 12-month endpoint with a 5-month gap.
3. **Never-treated states are ~1.5-1.6x noisier than the full state set** in the
   pre era (composition check). The real design's control pool *is* those states,
   so a pseudo-experiment run on all states understates noise on that count too.

**Real-calendar anchor — REVISED DOWN, see §4b.** The first pass measured
σ = 0.472 on the state panel and implied MDE-80 ≈ 0.44 log points ≈ 56%. That
figure is **contaminated by county-coverage artifacts** and should not be used;
the defensible range is σ ≈ 0.19–0.23, implying **MDE-80 ≈ +20% to +24%**.

## 4b. What actually drives the real-calendar σ — mostly a data artifact

Script:
[`analysis/diagnostics/longdiff_real_calendar_decomp.R`](../analysis/diagnostics/longdiff_real_calendar_decomp.R)
→ `output/longdiff_era_variance/real_calendar_decomp_*.csv`.

The σ = 0.472 above is carried by **two states out of seven**, and for both the
state panel disagrees with the county file it is nominally built from:

| state | state panel dY | county-aggregated dY | reporting counties, base → endpoint |
|---|---|---|---|
| **TX** | **+0.785** | **−0.493** | 12.8 → 8.5 |
| **MN** | **−0.715** | −0.024 | 68.2 → 63.2 |
| AK, GA, MT, OK, UT | — | identical to state panel | — |

Five of seven states agree exactly; TX and MN — precisely the two extremes that
generate the SD — do not. This is a data-construction discrepancy, not a fact
about evictions.

A second, independent artifact operates inside the county file itself: the set
of **reporting counties changes between the windows**, so a state total moves
mechanically. Rebuilding every state from a **fixed county basket** (counties
observed in every month of both windows) flips Texas from −0.49 to **+0.36**.

| specification | σ | MAD | implied MDE-80 |
|---|---|---|---|
| state panel (as first reported) | 0.472 | 0.377 | +56% |
| county-aggregated, as-reported | 0.233 | 0.284 | +24% |
| **county-aggregated, fixed county basket** | **0.190** | 0.187 | **+20%** |
| pre-COVID placebo (2016→2019), fixed basket | 0.189 | 0.058 | — |

Two readings follow. **(1) The real-calendar σ is roughly half what the state
panel says** — the honest range is 0.19–0.23, so the design's real-era MDE-80 is
nearer **+20-24%** than +56%. **(2) Genuine post-COVID heterogeneity is real but
smaller than the SD implied**: the fixed-basket SD matches the pre-COVID placebo
(0.190 vs 0.189), while the MAD does not (0.187 vs 0.058) — i.e. the typical
state is ~3x more dispersed post-COVID, and the pre-COVID SD is itself
outlier-driven.

**Does the §4 era factor survive?** Yes, reduced. Re-measured on county-built
aggregates at B=12/gap=5/E=12, never-online excluding Idaho: post/pre σ ratio
= **3.18** as-reported and **2.36** on a fixed basket, against 3.89 from the
state panel at the same cell. So roughly a third of the state-panel era ratio
was coverage drift; a genuine **~2.4x** remains.

**Caveat cutting the other way:** fixed baskets are small and possibly
unrepresentative (GA collapses to 1 county, TX to 8). Composition-fixing trades
a coverage artifact for a representativeness problem. Neither number is clean;
the range is the honest object.

**Action:** the TX and MN state-panel series need reconciling against the county
file before any long-difference estimate is reported. This is a data-integrity
item, not a modelling choice.

## 5. Averaging vs serial correlation (Ben's Burlig-Preonas-Woerman addition)

Measured with the endpoint window's **centre held fixed** and only its width
varying, so averaging is separated from distance (widening a window forward
also moves it further from the baseline — the naive sweep conflates the two).

Benchmark: if months were independent, a 12-month endpoint average would cut σ
to `1/sqrt(12) = 0.289` of the 1-month value.

| era | baseline | σ(E=12) / σ(E=1) | share of the iid benefit realized |
|---|---|---|---|
| **post-COVID** | 6 mo | 0.92 | **12%** |
| **post-COVID** | 12 mo | 0.95 | **7%** |
| pre-2018 (1 placement only) | 6 mo | 0.63 | 52% |
| pre-2018 (1 placement only) | 12 mo | 0.58 | 60% |

**In the post-COVID environment — the real one — a 12-month endpoint average is
worth almost nothing over a single month: 5-8% variance reduction against the
71% independence would deliver.** Serial correlation and state-level drift eat
the rest. This is a direct confirmation of the BPW concern on this data, and it
means endpoint-window length is not a lever worth spending design freedom on.

## 6. Selection check — were eventual legalizers already drifting?

Complementary to the randomized power draws: apply the **real** online-ever vs
never-online split on the same pre-treatment calendar, where nobody has
legalized anything. Script:
[`analysis/diagnostics/longdiff_2x2_selection_placebo.R`](../analysis/diagnostics/longdiff_2x2_selection_placebo.R);
4,999 randomization draws.

| design | baseline → endpoint | states (treated) | tau | in filings | RI p |
|---|---|---|---|---|---|
| main | 2008+09 → 2016 | 37 (22) | −0.014 | −1.4% | 0.90 |
| main_b12 | 2009 → 2016 | 39 (24) | −0.027 | −2.7% | 0.78 |
| late | 2010+11 → 2016 | 42 (26) | +0.093 | +9.7% | 0.74 |

**No evidence of pre-treatment divergence** between the states that would
eventually legalize online and those that never did. The RI dispersion
(SD 0.083 on the main design) also independently reproduces the power
simulation's MDE — 2.80 × 0.083 = 0.233 log points — which is a useful
internal consistency check on two separately coded paths.

*Blindness note:* this uses only pre-2018-06 data, so it is untreated and
permitted, but it does reveal the real group contrast that the randomized
simulation deliberately hides. It is written to its own directory and must not
feed estimator or window selection.

## 7. Power results (500 reps, 10-point delta grid)

`output/longdiff_2x2_pseudo/` — size, MDE-80, Type S and Type M for all three
inference arms and all three calendars.

### Size and MDE-80

| design | inference | size (δ=0) | size-valid | MDE-80 (log pts) | in filings |
|---|---|---|---|---|---|
| **main** (2008+09→2016) | **RI** | **0.050** | ✅ | **0.241** | **+27.2%** |
| main | WCB | 0.052 | ✅ | 0.241 | +27.2% |
| main | CRVE | 0.078 | ❌ | (0.220) | — |
| main_b12 (2009→2016) | RI | 0.052 | ✅ | 0.246 | +27.9% |
| main_b12 | CRVE | **0.124** | ❌ | — | — |
| late (2010+11→2016) | RI | 0.050 | ✅ | 0.364 | +43.8% |

Four things to take from this:

1. **Randomization inference is exactly nominal (5.0%) and the design's
   estimator is unbiased** (null bias −0.0008, SE/SD 0.884). The pre-committed
   choice of RI as primary is vindicated empirically, not just on theory.
2. **CRVE fails the size gate** — 7.8% on the main design and **12.4%** on the
   12-month-baseline variant, with SE/SD 0.88. At 37 unbalanced clusters the
   cluster-robust SE is too small; its apparently better MDE (0.220) is an
   artifact of over-rejection and must not be quoted.
3. **The 24-month baseline buys almost nothing over 12 months** (MDE 0.241 vs
   0.246). Combined with §5, both averaging levers — baseline length and
   endpoint length — are close to inert. This is the Burlig-Preonas-Woerman
   prediction confirmed on both margins.
4. **The crisis-free calendar is *worse*, not better** (MDE 0.364 vs 0.241,
   despite 42 states vs 37). The 2008-09 baseline is not flattering the main
   design; a 2010-11 baseline is noisier still.

### Type S and Type M (Black et al.), main design, RI

| δ | power | sign-error rate | exaggeration |
|---|---|---|---|
| 0.02 | 0.064 | 6.3% | **8.9x** |
| 0.05 | 0.124 | 1.6% | 3.8x |
| 0.10 | 0.246 | 0 | 2.1x |
| 0.20 | 0.566 | 0 | 1.28x |
| 0.30 | 0.998 | 0 | 1.00x |

At effects in the range the literature suggests (Hollenbeck et al. 2025 find
7.5-10% credit effects), **a significant estimate from this design would
overstate the truth by 2-4x**, and under CRVE at δ=0.02 more than a quarter of
significant estimates carry the wrong sign. Statistical significance here is
not evidence of a well-estimated effect.

### Reconciliation to the real era — the number that actually matters

The 27% figure is a **floor**: it is measured in the calm pre-2018 era. Applying
the era factor from §4, and the independent real-calendar anchor:

| route | MDE-80 (log pts) | in filings |
|---|---|---|
| pseudo-era, as measured (floor) | 0.241 | +27% |
| × fixed-basket era factor 2.36 | 0.57 | **+77%** |
| direct real-calendar σ anchor, **corrected** (§4b) | 0.18–0.22 | **+20% to +24%** |

**These two routes no longer agree, and the disagreement is informative.** The
era-inflated pseudo-era route says +77%; the direct real-calendar measurement
says +20-24%. They are not measuring the same thing — the pseudo route runs on
the annual court outcome with 37 county-clustered states, the anchor on ETS
state aggregates — and §4b shows the ETS inputs to both are coverage-unstable.
Until TX/MN are reconciled, the defensible statement is a **range of roughly
+20% to +80%**, not a point.

Even the optimistic end is well above the 7.5-10% effects the credit literature
reports, and above LP-DiD on the spliced state window (MDE-80 8.1%,
`time_agg_covid_calibration_memo_2026-08-19.md`). The ordering of the
recommendation is unchanged; the magnitude is not settled.

**Recommendation:** keep the 2x2 long difference as a transparent,
assumption-light descriptive contrast whose estimand is easy to defend, but do
not carry it as the PAP's powered specification. If it is reported, report the
MDE honestly at ~60-90% and report Type M alongside every significant estimate.

*Caveat on the bridge:* the pseudo-era power is measured on the annual court
outcome, the era factor on ETS monthly filings. The three routes agreeing to
within a factor of 1.6 is reassuring, but this is a bridge, not a measurement.

## 8. What this design cannot tell us

- Whether the 2008→2016 drift regime transports to 2018→2025 (foreclosure
  recovery vs COVID/moratoria). §4 bounds the gap; it does not close it.
- How the annual court outcome's coverage error maps onto ETS
  `filings_per_1k_renters` beyond an overlap-year variance bridge.
- The power cost of real-design baseline contamination (DE/NJ/WV legalize
  *inside* the real 2017-18 baseline). The pseudo era has no analogue — this is
  an estimand caveat, not a power question.
- Anything about heterogeneous exposure duration within the treated group; the
  2x2 pools a 2018 legalizer with a 2021 one by construction.
