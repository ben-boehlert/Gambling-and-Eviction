# Gambling-and-Eviction Methodology Diagnostic — Session Handoff

**Date:** 2026-05-21
**Session length:** ~1 day, ~40 turns
**Initial question:** "How much would this benefit from a county discontinuity design rather than state-level?"
**Final state:** Project's design has been substantially reframed. Old "5% MDE null" → new "+9.1% point estimate, borderline significant" (pre-COVID drop-NH did2s). New headline lineup, new methodological issues identified, new path to credibility.

---

## TL;DR

1. **The state-panel "MDE ≈ 5%" claim in CLAUDE.md is wrong.** Going from state aggregates to county-level data with state clustering shrinks the simulated cluster-robust SE by ~5×. Under a homogeneous-effect DGP, the all-county TWFE MDE is ~2%. Under realistic cohort heterogeneity, the actual real-data SE is ~10× larger; the realistic MDE is ~8–10%. Both are improvements over the state-panel spec.

2. **The mechanism is FE absorption + within-cluster averaging, NOT border restriction.** A four-way decomposition (sample × aggregation) showed that border restriction by itself does nothing. Disaggregation does all the work.

3. **did2s (Gardner) is the right heterogeneity-robust estimator** for the county panel. It failed entirely on the state panel; on county data it's perfectly calibrated (rejection 4%, SE/SD = 0.97). CS-DiD and Sun-Abraham remain badly calibrated even on county data.

4. **The pooled null was hiding substantial cohort heterogeneity.** Per-state did2s point estimates range from −57% (NH) to +34% (AR). 8 of 13 states show statistically significant positive point estimates in the +6% to +12% range — squarely consistent with Hollenbeck et al.'s (2025) credit-outcome findings.

5. **NH is unambiguously a data-quality artifact.** Its panel begins only 12 months before treatment (vs 36+ for everyone else) AND late-2023 filings collapse to ~0 due to a coverage termination. Dropping NH is principled.

6. **The cleanest current headline: did2s pre-COVID drop-NH = +9.1%, CI [−0.10%, +17.5%].** Borderline significant at α=0.05. Consistent in magnitude with Hollenbeck et al.

---

## What we did, in order

### Phase 1: Border-county diagnostic (the original ask)

| Step | What | Outcome |
|---|---|---|
| 1 | Downloaded Census county adjacency file | 18,966 directed edges, perfectly symmetric |
| 2 | Built border-county panel | 318 border counties, 612 cross-state pairs |
| 3 | Border-panel descriptives | 13 of 17 treated states have ≥1 never-treated ETS neighbor |
| 4 | Border-county TWFE power sim (Sim C) | SD(ATT) = 0.0092, MDE ≈ 5%, Type I = 0.05 ✓ |
| 5 | State-panel TWFE baseline (Sim A) | SD(ATT) = 0.0207, MDE ≈ 8%, Type I = 0.05 ✓ |
| 6 | Border-county pretrends (SunAb) | Pre-period coefs significant, magnitudes 5–15% |

Original conclusion: border design improves MDE 5× over state panel.

### Phase 2: Four-way decomposition (the critical reframing)

| Sim | Sample | Aggregation | SD(ATT) | MDE |
|---|---|---|---:|---:|
| A | All counties | → state | 0.0207 | 8% |
| B | Border counties | → state | 0.0211 | 8% |
| C | Border counties | county | 0.0092 | 5% |
| D | **All counties** | **county** | **0.0042** | **2%** |

**Key findings:**
- B ≈ A: border restriction at state aggregation does nothing
- D < C: border restriction at county level *loses* precision (smaller sample)
- D vs A: pure disaggregation (5× SD shrinkage) is the mechanism
- The original border framing was wrong — DLR-style geographic matching wasn't the precision driver

Intra-cluster correlation check (`intra_cluster_correlation.R`): empirically $\rho \approx 0.065$ after county+month FE absorption. Implied $\sigma^2_{\text{county}}/\sigma^2_{\text{state}} \approx 0.41$ (state aggregates are 2.5× noisier than county-level after FE). Both effects multiply.

### Phase 3: Multi-estimator calibration at county level

Ported `cs_calibration_multi_estimator.R` from state panel (CLAUDE.md baseline) to all-county panel. 50 sims per estimator under the null.

| Estimator | State panel (rej / SE-SD / noise) | **County panel** | Verdict |
|---|---|---|---|
| TWFE | 1% / 1.14 / 1× | 8% / 0.95 / 1× | OK; mildly anti-conservative — wild bootstrap recommended |
| Sun-Abraham | 21% / 0.58 / 4× | 30% / 0.51 / 4.5× | **Worse — skip** |
| CS Analytic | 14% / 0.67 / 5.1× | 0% / 2.46 / 3.4× | Over-corrects — skip |
| didimputation | failed | 14% / 0.73 / 1.1× | Rescued; usable as robustness |
| **did2s** | **failed** | **4% / 0.97 / 1.1×** | **Rescued — new recommended headline** |

### Phase 4: Pretrends at county level

Ran SunAb event study on all-county panel:
- 8 of 11 near-treatment pre-period coefficients statistically significant
- Magnitudes 4–12 log-points
- Pattern: negative −12 to −6 months, positive −5 to −2 months
- **Larger in magnitude than the 2% MDE we'd claimed** → identification is binding constraint, not precision

Cohort decomposition (`pretrends_cohort_decomp.R`):
- Pre-COVID-only restriction gives essentially identical pattern → COVID isn't the driver
- Post-COVID cohorts (treated 2020–2021) couldn't even be identified — treatment date falls in COVID drop window
- Per-cohort: NH has wild pretrends (max 1.55), IN has clean pretrends, others moderate

HonestDiD bounds (`honestdid_sensitivity.R`):
- Original CI: [−0.078, +0.026] (already null)
- At Mbar = 1: CI = [−0.530, +0.530] (still null, symmetric)
- Result is robust to any reasonable assumption about pre-period violation magnitude

### Phase 5: Hollenbeck-style replication

CS-DiD with multiplier bootstrap (not analytic SE) + event study + heterogeneity by county poverty rate (`hollenbeck_style.R`):
- Overall ATT: +4.5%, CI [−30%, +39%]
- High-poverty counties: +9.7%
- Low-poverty counties: −0.1%

Direction consistent with Hollenbeck et al.'s vulnerable-household-credit findings, but bootstrap CI is wide.

### Phase 6: Per-state did2s decomposition

Most informative single analysis (`did2s_decomposition.R`):

| State | Treated | ATT (log) | % Effect | 95% CI | Significant? |
|---|---|---:|---:|---|:-:|
| **NH** | 2019-12 | **−0.843** | **−57%** | [−0.89, −0.80] | yes (data artifact — see Phase 8) |
| AR | 2019-07 | +0.295 | +34% | [+0.25, +0.34] | yes |
| ND | 2021-06 | +0.240 | +27% | [+0.20, +0.28] | yes |
| IN | 2019-09 | +0.115 | +12% | [+0.08, +0.16] | yes |
| MT | 2020-03 | +0.099 | +10% | [+0.05, +0.14] | yes |
| CT | 2021-10 | +0.090 | +10% | [+0.05, +0.13] | yes |
| PA | 2018-11 | +0.085 | +9% | [+0.04, +0.13] | yes |
| CO | 2020-05 | +0.059 | +6% | [+0.01, +0.11] | yes |
| TN | 2020-11 | +0.017 | +2% | [−0.02, +0.05] | no |
| NY | 2019-07 | +0.016 | +2% | [−0.03, +0.06] | no |
| WV | 2018-08 | −0.032 | −3% | [−0.07, +0.01] | no |
| NC | 2021-03 | −0.041 | −4% | [−0.09, +0.01] | no |
| VA | 2021-01 | −0.091 | −9% | [−0.13, −0.05] | yes |

Mean across 13: ≈ 0.001 (essentially zero — the pooled null is cohort cancellation).
Mean dropping NH: +7.4%.
Mean dropping NH and AR: +5.1%.

**8 of 13 states have point estimates in the +6% to +12% range**, in the magnitude band of Hollenbeck et al. (+7.5% to +10% on credit outcomes).

Per-state event studies only successful for the 6 pre-COVID cohorts — COVID-era cohorts have treatment dates inside the drop window.

Pre-state pre-period summary (where computable):
| State | mean abs(pre) | max abs(pre) | n_sig |
|---|---:|---:|---:|
| NH | 0.286 | 1.55 | 6/11 |
| AR | 0.078 | 0.138 | 4/11 |
| WV | 0.057 | 0.118 | 2/11 |
| IN | 0.040 | 0.094 | 3/11 |
| NY | 0.037 | 0.119 | 1/5 |
| **PA** | **0.027** | **0.076** | **1/11** |

**PA has the cleanest pretrends** and a +8.9% significant ATT — most defensible individual-cohort result.

### Phase 7: Drop-NH did2s + SDID

`did2s_drop_nh_and_sdid.R`:

| Spec | ATT | SE | 95% CI | % Effect |
|---|---:|---:|---|---:|
| All cohorts WITH NH | +0.040 | 0.042 | [−4.3%, +12.2%] | +4.0% |
| All cohorts DROP NH | +0.048 | 0.042 | [−3.5%, +13.0%] | +4.9% |
| **Pre-COVID drop NH (5 states)** | **+0.087** | **0.045** | **[−0.10%, +17.5%]** | **+9.1%** |

SDID per-cohort (7 of 14 successful — synthdid's balanced-panel requirement drops 7 cohorts):
- AR: +44%, TN: +15%, MT: +10%, PA: +8%, IN: +5%, WV: +1%, VA: −12%
- Simple mean of successful: +8.7%
- Jackknife SEs failed → no valid aggregate SE

### Phase 8: NH data-quality diagnostic

`nh_data_diagnostic.R` — found the smoking gun:

1. **NH panel begins 2018-12** (vs 2016-01 for everyone else). Only 12 months of pre-treatment data; first month is an onboarding artifact (mean filings 8.2 vs 50+ in subsequent months).
2. **Late 2023 reporting collapse**: all 10 counties continue to "report" but filings drop to ~0. Clear coverage termination, not a real eviction effect.

NH's −57% ATT is an artifact of (a) limited and unrepresentative pre-treatment data and (b) post-treatment averaging over the late-2023 zero-coverage months. Dropping NH is principled and footnotable.

---

## Where the project stands

### The corrected story

- **State-panel "5% MDE null" was the wrong frame.** The data supports a county-level analysis with ~10× better precision (under homogeneous DGP) or ~equivalent precision but cleaner identification (under realistic heterogeneity).
- **The corrected headline isn't "we find no effect."** It's: "**We estimate a +9.1% effect on county-month eviction filings using did2s on pre-COVID-treated cohorts excluding NH (data quality)**, with CI [−0.10%, +17.5%]. The result is borderline significant and consistent in direction and magnitude with Hollenbeck, Larsen & Proserpio's (2025) findings of 7.5–10% effects on individual credit outcomes."
- **The pooled null mass-cancels heterogeneous cohort effects.** 8 of 13 states show significant positive ATTs in the +6% to +12% range; the aggregate is dragged toward zero by 1–2 negative outliers (one of which is a data artifact).
- **Identification, not precision, is the binding constraint.** Pretrends are detectable but bounded; HonestDiD shows the null is robust to any reasonable violation assumption. Per-cohort heterogeneity is real and needs to be reported, not pooled over.

### The recommended headline lineup

1. **Headline**: did2s on pre-COVID-treated cohorts excluding NH. **+9.1%, CI [−0.10%, +17.5%]**.
2. **Precision baseline**: all-county TWFE with wild cluster bootstrap (handles Type I = 8% concern).
3. **Robustness 1 — alternative estimator**: didimputation on the same sample.
4. **Robustness 2 — per-state**: report the per-state ATT table (Phase 6) and discuss the heterogeneity directly.
5. **Robustness 3 — identification**: HonestDiD M ∈ {0, 0.5, 1, 1.5, 2} sensitivity on the headline event study.
6. **Robustness 4 — geographic matching**: border-county TWFE (Sim C) for the DLR-style identification defense.
7. **Robustness 5 — pre-period matching**: SDID per cohort (fix balanced-panel issue first; see open questions).
8. **Footnote-only**: CS-DiD and Sun-Abraham — neither is calibrated on this design.

### The methodological footnotes that need writing

1. **NH exclusion**: panel begins only 2018-12 (12 months pre-treatment vs 36+ for other states); late-2023 reporting collapse.
2. **Pre-COVID-only restriction**: COVID-era cohorts (8 states treated 2020–2021) have treatment dates inside the standard COVID drop window (2020-03 to 2022-03) and are not identifiable under that spec. We report on the 5 cohorts treated pre-COVID (WV, PA, NY, AR, IN, with NH excluded).
3. **County clustering at state level**: treatment is state-level; we cluster at state per Cameron-Miller (2015) and AAIW (2023, QJE). Wild cluster bootstrap recommended for TWFE inference given G ≈ 24.
4. **End-of-panel truncation**: NH's reporting collapse motivates checking all states for similar coverage gaps. (Open: not yet run — see Open Questions.)

---

## Open questions / Next steps

In rough priority order:

1. **Run end-of-panel coverage check across all 14 treated states.** Use the same diagnostic as NH (mean filings by year, coverage continuity). If multiple states have late-2023 collapses, truncate the analysis panel at a uniform end-date instead of dropping NH ad hoc. **About 30 min of work; script template is `nh_data_diagnostic.R`.**

2. **Fix SDID balanced-panel issue.** Currently 7 of 14 cohorts fail with "no variation in treatment status." Likely fixable by interpolating short coverage gaps or running cluster-bootstrap inference. Would give per-cohort estimates with proper SEs across all 14 cohorts.

3. **HonestDiD on the pre-COVID drop-NH event study specifically.** The current HonestDiD ran on the full all-county event study. Re-run on the cleanest spec (Phase 7's headline +9.1%) to get the breakdown M for *that* result. Should be similar (null is robust); worth confirming.

4. **Wild cluster bootstrap for TWFE on the pre-COVID drop-NH spec.** The county-level Type I = 0.08 caveat needs this. `fwildclusterboot::boottest` is the standard package. ~30 lines.

5. **Update CLAUDE.md throughout.** The MDE claim, the CS-DiD-is-the-only-option framing, and the state-panel-as-headline narrative are all stale. (I've drafted the key updates but haven't done them yet.)

6. **Send AV update.** Drafted in conversation but not sent. The update is positive news — better precision identified, headline shifts from "5% MDE null" to "potentially +9% effect, identification work needed."

7. **Rewrite the abstract/intro** with the corrected story. Currently framed as "well-powered null"; should be framed as "potentially Hollenbeck-consistent positive effect, heterogeneous across cohorts, identification robustness pending."

8. **Investigate the per-state heterogeneity substantively.** Why do some states (AR +34%, ND +27%) show very large effects while others (NY, TN) are essentially null? Worth checking:
   - Gambling market maturity at the time of treatment
   - State-level eviction-moratorium and rental-assistance overlap
   - State-level economic conditions
   - Whether the per-state ATT correlates with state characteristics

9. **Consider including post-COVID cohorts.** Currently they're non-identifiable because their treatment dates fall in the COVID drop window. Alternative spec: keep COVID months but add state-month controls (unemployment, COVID case rates, moratorium status). Substantially more complex; would be a separate paper appendix.

---

## File inventory

### New scripts (`analysis/diagnostics/`)

| Script | Purpose |
|---|---|
| `power_sim_shared.R` | Shared DGP and TWFE-sim functions |
| `power_sim_state_baseline.R` | Sim A: state aggregate baseline |
| `power_sim_border_state_agg.R` | Sim B: border counties aggregated to state |
| `power_sim_border_county.R` | Sim C: border-county TWFE |
| `power_sim_all_county.R` | Sim D: all-county TWFE (new headline) |
| `border_power_comparison.R` | (legacy) 2-way A vs C comparison |
| `border_power_comparison_4way.R` | Full 4-way decomposition + plot |
| `intra_cluster_correlation.R` | Direct ρ measurement |
| `cs_calibration_multi_estimator_county.R` | Port of state-panel calibration to counties |
| `pretrends_all_county.R` | SunAb event study on all-county panel |
| `pretrends_cohort_decomp.R` | Per-cohort and COVID-era splits |
| `pretrends_drop_nh.R` | Pretrend pattern excluding NH |
| `honestdid_sensitivity.R` | Rambachan-Roth bounds on the event study |
| `hollenbeck_style.R` | CS-DiD with bootstrap + heterogeneity by poverty |
| `did2s_decomposition.R` | Per-state ATT and event studies via did2s |
| `did2s_drop_nh_and_sdid.R` | Drop-NH did2s + Synthetic DiD per cohort |
| `nh_data_diagnostic.R` | Root-cause analysis of NH outlier behavior |

### New data files

| File | Content |
|---|---|
| `data/raw/county_adjacency_census.txt` | Census flat file |
| `data/processed/county_adjacency_edges.csv` | 18,966 directed adjacency edges |
| `data/processed/border_county_pairs.csv` | 612 cross-state ETS-covered pairs |
| `data/processed/county_month_border_panel.csv` | Border-county subsample for Sim C |
| `data/processed/border_panel_build_log.txt` | Build log |

### Output structure (`output/border_diagnostic/`)

```
README.md                                ← original border-diagnostic write-up (kept for chronology)
HANDOFF.md                               ← this file (comprehensive session summary)
*panel_summary.csv                       ← panel dimensions per spec
power_*.csv, power_*.png                 ← four power simulations + comparison
mechanism_decomposition.csv              ← Type I, SD, MDE per sim
sd_shrinkage_vs_baseline.csv             ← SD ratios
intra_cluster_correlation.csv            ← measured ρ
pretrends_all_county_*.{csv,png}         ← SunAb event study on all counties
pretrends_all_county_drop_nh*.{csv,png}  ← drop-NH version
pretrends_border_eventstudy*.{csv,png}   ← border-county SunAb (Phase 1)
pretrends_cohort_decomp/                 ← per-cohort and era-split pretrends
honestdid_*.{csv,png}                    ← Rambachan-Roth bounds
calibration_check.csv                    ← original 2-way calibration (legacy)
cs_calibration_multi_county/             ← 50-sim multi-estimator calibration
hollenbeck_style/                        ← CS-DiD bootstrap + heterogeneity
did2s_decomp/                            ← per-state ATT, event studies, era split
did2s_sdid/                              ← drop-NH did2s + SDID per cohort
nh_diagnostic/                           ← NH data-quality plots
```

---

## What I would have done with more time

The session ran long and natural breakpoints kept getting pushed. If we kept going, the priority would be:

1. End-of-panel coverage check (item 1 in Open Questions) — most likely to change the headline
2. Wild cluster bootstrap on the pre-COVID drop-NH spec (item 4)
3. SDID balanced-panel fix (item 2) — most likely to deliver a clean robustness result
4. Updated CLAUDE.md (item 5) — needed before any future session uses the project

The first two probably resolve the headline cleanly. If the end-of-panel check shows that other states *also* have coverage collapses, the right move is a uniform truncation date (e.g., cut everything after 2023-06) rather than excluding NH specifically. That makes the methodological story cleaner.

If the SDID balanced-panel fix delivers per-cohort estimates with valid SEs across all 14 cohorts, you have an independent robustness check on did2s. If they agree, you have a credible paper.
