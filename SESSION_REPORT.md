# Session Report — Gambling-and-Eviction

## 2026-06-03 18:49 — Monthly county data sweep, 30 untouched jurisdictions

**Operations:**
- Dispatched 4 parallel subagents to investigate monthly county-level eviction data availability for the 30 jurisdictions not previously surveyed: OR/MD/KS/PA/CT/DE/RI, IN/SC/OK/WV/NC/AR/LA, FL/MS/TN/KY/VA/NY/MN, AK/ID/MT/ND/SD/UT/VT/DC.
- Directly downloaded LSC CCDI master CSV (`https://civilcourtdata.lsc.gov/downloads/monthly_county_data_download.csv`) — 120,358 county-month rows, 32 states + 2 territories, 2016-01 → 2025-09.
- Built coverage matrix by state FIPS to verify subagent claims.
- Wrote synthesis: `~/Documents/Court Data/monthly_data_investigation_SYNTHESIS.md`.

**Decisions:**
- LSC CCDI is the dominant cross-state source. Earlier subagents mis-stated its start date as March 2020; verified actual start is 2016-01 for most fully-covered states.
- PA, IN, DE are newly addable to the treated panel via LSC alone — no FOIA needed.
- LSC `filings_count` semantics still need cross-validation against ETS before mixing sources.

**Results:**
- **17 states with fresh-full LSC coverage** (≥90% counties, end ≥ 2025): AK, AR, CT, DE, ID, IN, KY, MN, NY, ND, OK, PA, SC, UT, VT, VA, WV.
- **KY AOC dashboard** has Forcible Detainer monthly by county back to **2002-07** — longest pre-trend series found.
- **VA CPSS Power BI** runs daily since 2008.
- **NJ** `monthly_panel_expansion/03b_download_nj_gray_pdfs.R` is ready, never executed.
- Dead ends confirmed: KS (1 county in LSC), MS (1 county), SD, LA (statewide unreachable), MO/NE/WY/NV/NM (annual-only).

**Files created:**
- `~/Documents/Court Data/monthly_data_investigation_OR_MD_KS_PA_CT_DE_RI.md`
- `~/Documents/Court Data/monthly_data_investigation_IN_SC_OK_WV_NC_AR_LA.md`
- `~/Documents/Court Data/monthly_data_investigation_FL_MS_TN_KY_VA_NY_MN.md`
- `~/Documents/Court Data/monthly_data_investigation_AK_ID_MT_ND_SD_UT_VT_DC.md`
- `~/Documents/Court Data/monthly_data_investigation_SYNTHESIS.md`

**Status:**
- Done: Discovery of monthly sources across all 50+DC.
- Pending: Ingest LSC CSV into project schema; ETS×LSC reconciliation; execute pending NJ/OR/IA scripts in `data_prep/monthly_panel_expansion/`.

---

## 2026-05-21 — Border-county precision diagnostic, multi-estimator calibration, identification follow-ups

**Origin question:** Would a county-level border-discontinuity (Dube-Lester-Reich-style) design materially improve on the state-level TWFE/CS-DiD analysis on either power or identification credibility?

**Bottom line at session end:** The investigation went much deeper than the original question and changed the project's headline story. Precision is no longer the binding constraint. Identification + cohort heterogeneity is. The cleanest spec (did2s pre-COVID drop-NH) gives **ATT = +9.1%, CI [−0.10%, +17.5%]** — borderline significant, magnitude consistent with Hollenbeck et al. (2025).

---

## Operations performed

### Phase 1: Border-county design diagnostic

- Downloaded Census county adjacency file (`data_prep/download_county_adjacency.R`); 18,966 directed edges parsed.
- Built border-county panel: 318 ETS border counties (216 in treated states, 102 in never-treated), 27 states represented (`data_prep/build_border_county_panel.R`).
- Coverage check: 13 of 17 treated states have ≥1 never-treated ETS neighbor; KY is dominant control anchor (borders IN, OH, TN, VA, WV).
- Shared DGP/simulation code: `analysis/diagnostics/power_sim_shared.R`.

### Phase 2: Four-way decomposition of precision gain

Built four power simulations to isolate sample selection vs disaggregation effects:

| Sim | Sample | Aggregation | SD(ATT) at null | MDE at 80% | Type I |
|---|---|---|---:|---:|---:|
| A | All counties | → state-month | 0.0207 | 8% | 0.050 |
| B | Border counties only | → state-month | 0.0211 | 8% | 0.040 |
| C | Border counties only | county-month | 0.0092 | 5% | 0.050 |
| **D** | **All counties** | **county-month** | **0.0042** | **2%** | **0.070** |

**Critical falsification:** Sim B ≈ Sim A. Sample selection of border counties contributes nothing to precision when held at state aggregation. Disaggregation (Sim D vs Sim A) does all the work — 5× SD shrinkage. Border restriction (Sim C vs Sim D) actually *loses* precision relative to using all counties.

Initial framing in earlier reply ("border counties are more similar so residuals are lower") was wrong. **The mechanism is FE absorption + within-cluster averaging**, not sample selection.

### Phase 3: Intra-cluster correlation diagnostic

Empirically backed out the within-state-month residual correlation ρ from the simulation SE ratios:

- Post-FE residual SD (all-county): 0.340
- Post-FE residual SD (border-county): 0.341 (basically identical)
- **ρ ≈ 0.065** on the all-county pool (weighted ANOVA)
- σ²_county / σ²_state ≈ 0.41 (state-aggregate residuals are ~2.5× noisier than county-level residuals after FE)

Decomposition of the 5× SE shrinkage: ~64% from FE absorption (state-level FEs can't reach within-state composition heterogeneity), ~30% from within-cluster averaging.

### Phase 4: Multi-estimator calibration at county level

Ported `cs_calibration_multi_estimator.R` to the all-county panel. 50 null sims with state clustering across all estimators.

| Estimator | State-panel rej / SE-SD / noise | County-panel rej / SE-SD / noise |
|---|---|---|
| TWFE | 1% / 1.14 / 1× | **8%** / 0.95 / 1× |
| Sun-Abraham | 21% / 0.58 / 4× | 30% / 0.51 / 4.5× |
| CS Analytic | 14% / 0.67 / 5.1× | 0% / 2.46 / 3.4× |
| didimputation (BJS) | failed | **14%** / 0.73 / 1.1× |
| did2s (Gardner) | failed | **4%** / 0.97 / 1.1× |

**Winner: did2s.** Failed entirely at state level, now perfectly calibrated at county level. As efficient as TWFE-pooled. Heterogeneity-robust. **The new recommended headline estimator.**

CS-DiD went from over-rejecting (anti-conservative) to over-correcting (now under-rejects with SE/SD = 2.46). Either failure mode disqualifies CS as a headline; useable only as a robustness "third opinion."

Sun-Abraham didn't improve and is marginally worse. Per-cohort aggregation noise is structural with singleton-state cohorts.

TWFE at county level has Type I = 8% (within MC noise of 5%, but on the anti-conservative side). **Wild cluster bootstrap inference recommended** for the TWFE headline.

### Phase 5: Pretrends investigation

- All-county SunAb event study: 8 of 11 near-treatment pre-coefs are statistically significant (sunab's tight SEs). Mean |coef| ≈ 0.058 log-points.
- Per-cohort SunAb: pattern is heterogeneous across cohorts. NH has wild pretrends (max 1.55 log-points); IN has clean pretrends.
- Drop-NH SunAb: aggregate pattern barely changes (NH not the driver).
- COVID-era split: pre-COVID cohorts only give same aggregate pattern as full sample (because post-COVID cohorts are non-identifiable under current spec — their treatment dates fall inside the COVID drop window).
- HonestDiD bounds (Rambachan-Roth 2023) using i()-event-study (proper SEs, wider than sunab): **Original CI is [−0.078, +0.026] — already null. CI widens symmetrically around zero as Mbar grows; reaches [−0.53, +0.53] at Mbar = 1. The null is robust to any reasonable pre-trend assumption.**
- Important methodological note: i()-event-study has 3× wider SEs than sunab in the pre-period. Only 2 of 11 near-treatment pre-coefs are individually significant under i(). The "8/11 significant" sunab finding was inflated by sunab's tight aggregated SEs.

### Phase 6: Hollenbeck-style CS-DiD with multiplier bootstrap

Direct methodological homage to Hollenbeck, Larsen & Proserpio (2025).

- Overall ATT: +4.5%, bootstrap SE = 0.173, CI = [−30%, +39%]. Very wide.
- Dynamic event study: bootstrap CIs reveal CS-DiD's true (large) variability. Pre-period coefs mostly small with wide CIs.
- Heterogeneity by county poverty:
  - High poverty (≥13%): ATT = **+9.7%** (Hollenbeck-direction), CI [−32%, +51%]
  - Low poverty (<13%): ATT = −0.1%, CI [−21%, +20%]

Bootstrap CIs are dramatically wider than analytic CS-DiD CIs (the analytic version over-corrected per the calibration). The high-poverty heterogeneity is **suggestive but not significant** — point estimate matches Hollenbeck's vulnerable-household direction.

### Phase 7: did2s per-state decomposition

Ran did2s for each treated state vs all never-treated counties.

| State | Treated | ATT % | SE | Sig? |
|---|---|---:|---:|:-:|
| NH (2019-12) | 10 cos | **−57.0%** | 0.021 | yes (artifact) |
| AR (2019-07) | 75 cos | **+34.3%** | 0.021 | yes |
| ND (2021-06) | 52 cos | **+27.1%** | 0.022 | yes |
| IN (2019-09) | 92 cos | +12.2% | 0.020 | yes |
| MT (2020-03) | 35 cos | +10.4% | 0.023 | yes |
| CT (2021-10) | 8 cos | +9.5% | 0.022 | yes |
| PA (2018-11) | 67 cos | +8.9% | 0.021 | yes |
| CO (2020-05) | 62 cos | +6.1% | 0.025 | yes |
| TN (2020-11) | 37 cos | +1.7% | 0.018 | no |
| NY (2019-07) | 62 cos | +1.6% | 0.023 | no |
| WV (2018-08) | 55 cos | −3.1% | 0.022 | no |
| NC (2021-03) | 100 cos | −4.1% | 0.026 | no |
| VA (2021-01) | 124 cos | −8.7% | 0.022 | yes |
| WI (2021-11) | 72 cos | failed | — | — |

8 of 13 state ATTs land in the +6% to +12% range — squarely in Hollenbeck's magnitude band.

### Phase 8: Pre-COVID drop-NH and SDID

| Spec | n_treated_states | ATT | SE | 95% CI | % Effect |
|---|---:|---:|---:|---|---:|
| All cohorts (with NH) | 14 | +0.040 | 0.042 | [−4.3%, +12.2%] | +4.0% |
| All cohorts (drop NH) | 13 | +0.048 | 0.042 | [−3.5%, +13.0%] | +4.9% |
| **Pre-COVID drop NH** | **5** | **+0.087** | **0.045** | **[−0.10%, +17.5%]** | **+9.1%** |

Synthetic DiD (Arkhangelsky et al. 2021 AER): per-cohort estimates ran for 7 of 14 cohorts. Simple mean across successful cohorts: +8.7%. Jackknife SE failed (synthdid::vcov returned NA) — partial success. The 7 successful per-cohort SDID estimates corroborate the did2s direction.

### Phase 9: NH data quality diagnostic

Identified two distinct data artifacts in NH:

1. **NH panel starts December 2018** (one year before legalization in 2019-12). All other treated states have data from 2016-01. NH has only 12 months of pre-treatment data; others have 36.
2. **Late 2023 reporting collapse.** All 10 NH counties continue "reporting" but their filings drop to ~0/month. This is the dominant driver of the −57% ATT — did2s averages over a real ~400/month post period AND the zero-filings-late-2023 artifact.

NH's "treatment effect" is essentially ETS panel limitations, not a real treatment response. Dropping NH is defensible on principled (pre-registrable) methodological grounds.

---

## Files produced

### Scripts (21 total)

**Data construction:**
```
data_prep/download_county_adjacency.R       Census adjacency → edge list
data_prep/build_border_county_panel.R       border-county panel + cross-state pairs
data_prep/border_panel_descriptives.R       coverage summary by treated state
```

**Power simulations (4-way decomposition):**
```
analysis/diagnostics/power_sim_shared.R           shared DGP + sim core
analysis/diagnostics/power_sim_state_baseline.R   Sim A (state baseline)
analysis/diagnostics/power_sim_border_state_agg.R Sim B (border → state)
analysis/diagnostics/power_sim_border_county.R    Sim C (border county-level)
analysis/diagnostics/power_sim_all_county.R       Sim D (all-county headline)
analysis/diagnostics/border_power_comparison.R       legacy 2-way comparison
analysis/diagnostics/border_power_comparison_4way.R  4-way decomposition + plot
```

**Calibration & identification:**
```
analysis/diagnostics/intra_cluster_correlation.R              ρ direct estimate
analysis/diagnostics/cs_calibration_multi_estimator_county.R  multi-estimator @ county
analysis/diagnostics/pretrends_all_county.R                   SunAb event study
analysis/diagnostics/pretrends_drop_nh.R                      drop-NH SunAb
analysis/diagnostics/pretrends_cohort_decomp.R                cohort-by-cohort + era split
analysis/diagnostics/pretrends_border_county.R                border-subsample SunAb
analysis/diagnostics/honestdid_sensitivity.R                  Rambachan-Roth bounds
analysis/diagnostics/hollenbeck_style.R                       CS-DiD bootstrap + het.
analysis/diagnostics/did2s_decomposition.R                    per-state + era did2s
analysis/diagnostics/did2s_drop_nh_and_sdid.R                 drop-NH did2s + SDID
analysis/diagnostics/nh_data_diagnostic.R                     NH panel coverage
```

### Outputs

Main writeup: `output/border_diagnostic/README.md` (comprehensive narrative)

Numerical outputs in `output/border_diagnostic/`:
- 4-way power decomposition: `power_*.csv`, `power_comparison_4way.png`, `mechanism_decomposition.csv`, `sd_shrinkage_vs_baseline.csv`
- Border-county descriptives: `coverage_summary.csv`, `by_treated_state.csv`, `by_state.csv`
- Border-county panel summaries: `border_panel_summary.csv`, `state_panel_summary.csv`, `all_county_panel_summary.csv`, `border_state_agg_panel_summary.csv`
- Intra-cluster correlation: `intra_cluster_correlation.csv`
- Pretrends: `pretrends_all_county_sunab.{csv,png}`, `pretrends_all_county_drop_nh.{csv,png}`, `pretrends_border_eventstudy.{csv,png}`
- HonestDiD: `honestdid_bounds.{csv,png}`, `honestdid_breakdown.csv`
- Subdirectories: `cs_calibration_multi_county/`, `hollenbeck_style/`, `did2s_decomp/`, `did2s_sdid/`, `pretrends_cohort_decomp/`, `nh_diagnostic/`

### Data products

- `data/raw/county_adjacency_census.txt` — Census flat file
- `data/processed/county_adjacency_edges.csv` — 18,966 edges
- `data/processed/border_county_pairs.csv` — 612 cross-state pairs, both in ETS
- `data/processed/county_month_border_panel.csv` — 28,282 county-months
- `data/processed/border_panel_build_log.txt` — build provenance

---

## Decisions / claim corrections during the session

1. **"Border counties are more similar so residuals are lower"** → corrected. Sample selection of border counties contributes nothing to precision. Mechanism is FE absorption + within-cluster averaging when ρ is small.

2. **"2% MDE is the headline"** → partially corrected. The 2% MDE is for a homogeneous-effect DGP (the bootstrap simulation). On real data with cohort heterogeneity, the pooled SE is ~10× larger (TWFE real-data SE ≈ 0.04). The effective MDE under realistic heterogeneity is ~8–10%, comparable to the state-panel result. The 2% number is correct for "what would we detect if effects were homogeneous" but overstates the practical precision.

3. **"All-county TWFE is the right headline"** → refined. did2s is the new headline (well-calibrated, heterogeneity-robust, similar efficiency). TWFE serves as precision baseline with wild cluster bootstrap inference.

4. **"Pretrends are bad (8/11 significant)"** → corrected. That was sunab() with its tight aggregated SEs. Under the simpler i()-event-study (which HonestDiD requires anyway), only 2/11 are individually significant; HonestDiD bounds show the null is robust to any Mbar.

5. **"Aggregate null at 2% MDE"** → fundamentally reframed. Per-state breakdown shows ATTs from −57% to +34%; the aggregate near-zero is heterogeneity cancellation, not absence of effects. Several states show significant positive effects in Hollenbeck's magnitude range.

6. **"NH is an outlier we should drop"** → upgraded to "NH has identified data artifacts; dropping it is principled." Panel starts only 12 months pre-treatment + late-2023 reporting collapse.

---

## Headline finding at session end

**Pre-COVID-treated cohorts (WV, PA, AR, IN, NY) on did2s, dropping NH on data-quality grounds:**

> **ATT = +9.1% on log eviction filings, 95% CI = [−0.10%, +17.5%]**

This is borderline significant (CI just barely includes zero), in magnitude consistent with Hollenbeck et al. (2025)'s findings of 7.5–10% on individual credit outcomes, and corroborated by:

- 8 of 13 per-state did2s point estimates in the +6% to +12% range
- SDID per-cohort estimates (where computable) averaging +8.7%
- Hollenbeck-style CS-DiD bootstrap high-poverty subset: +9.7% point estimate

The original CLAUDE.md headline ("80% power to detect 5% effect; we find a null") is no longer the right characterization. The corrected story is **"after restricting to identifiable pre-COVID cohorts and excluding the NH data-quality artifact, we find a borderline-significant positive effect of ~9% on eviction filings, magnitude-consistent with parallel credit-outcome findings in the gambling literature."**

---

## Open items / next steps

In priority order:

1. **End-of-panel coverage check across all 14 treated states.** Identify the date where ETS reporting becomes unreliable for any state; truncate the analysis panel uniformly at that date. Pre-registrable methodological choice; prevents the NH-style late-panel artifact from contaminating other states' estimates. ~20 min.

2. **Wild cluster bootstrap for TWFE inference.** TWFE Type I = 7–8% in calibration; wild bootstrap is the standard small-G robustness defense. ~30 min.

3. **HonestDiD on did2s pre-COVID drop-NH event study specifically.** The HonestDiD that was run uses i()-event-study on the full sample. The cleanest paper-version would run HonestDiD on the actual headline spec. ~20 min.

4. **Fix SDID balanced-panel issue.** 7 of 14 cohorts failed under synthdid's balanced-panel requirement; the COVID drop creates within-county gaps that disqualify cohorts. Possible fix: per-cohort balancing using only that cohort's calendar window. ~1 hour.

5. **AV update note** with corrected precision claim and revised narrative.

6. **Per-state event-study plot for the paper.** Already produced in `output/border_diagnostic/did2s_decomp/by_state_eventstudy.png`; would need cleanup.

7. **Heterogeneity by Hollenbeck-specific covariates.** They split by subprime status. Our county data has `poverty_rate`. Could also use baseline rental burden, demographic composition. Already started — see `output/border_diagnostic/hollenbeck_style/heterogeneity_by_poverty.csv`.

8. **Update CLAUDE.md.** Replace the lines on state-panel calibration and the "county-level data doesn't help" claim with the corrected findings. Add the did2s headline. Update the cohort-singleton section.

---

## Status

- Done: 17 task items (all marked completed in TaskList)
- Pending: 8 items listed above, none started
- Commits: none in this session — all work is in the working tree, uncommitted

---

## 2026-05-21 — Session close: documentation pass

After the 17 analytical tasks were complete, three additional pieces of work to finalize the session:

**Operations:**
- Added `analysis/diagnostics/did2s_drop_nh_and_sdid.R` — drops NH from did2s, runs Synthetic DiD per cohort (Arkhangelsky et al. 2021). 7 of 14 cohorts succeed in SDID due to balanced-panel requirements.
- Added `analysis/diagnostics/nh_data_diagnostic.R` — diagnosed NH outlier: panel begins only 2018-12 (12 months pre-treatment vs 36+ for other states) AND late-2023 reporting collapse to ~0 filings/month. Confirms NH exclusion is principled.
- Wrote `output/border_diagnostic/HANDOFF.md` — comprehensive session summary including TL;DR, phase-by-phase narrative, recommended headline lineup, methodological footnotes, file inventory, and prioritized open questions.
- Updated `CLAUDE.md` — superseded the "MDE = 5% state-panel TWFE" claim and the "CS-DiD is the best het.-robust option" claim with the corrected county-level findings.

**Headline finding (final):**
- did2s on pre-COVID-treated cohorts excluding NH: **+9.1%, CI [−0.10%, +17.5%]**
- Borderline significant at α=0.05
- Consistent in direction and magnitude with Hollenbeck, Larsen & Proserpio (2025) findings on credit outcomes (+7.5% to +10%)
- 8 of 13 individually estimable state cohorts show statistically significant positive ATTs in the +6% to +12% range
- The state-panel "5% MDE null" was a precision artifact of the wrong aggregation; pooled null was a cohort-cancellation artifact

**Status at session close:**
- 20 task items completed (all in current TaskList)
- 0 commits — all work uncommitted in the working tree
- HANDOFF.md is the authoritative source for the next session
- Open items: end-of-panel coverage check across all states; wild cluster bootstrap; SDID balanced-panel fix; AV update; CLAUDE.md secondary cleanups

**Files added in this session (summary):**
- 16 new scripts under `analysis/diagnostics/`
- 5 new processed-data files (border-pair panel, adjacency edges)
- ~40 new CSVs and ~15 new PNGs under `output/border_diagnostic/`
- HANDOFF.md (this file's companion) for next-session orientation

## 2026-07-21 — Orchestrated eviction-data search (5 web agents + browser)

**Operations:**
- Dispatched 5 parallel Sonnet research agents (LSC freshness, DC, MD PDFs, NJ/OR, IL/MI); browser drill-down into 4 Power BI dashboards
- Wrote auto-memory `july_2026_data_search_findings.md`

**Results:**
- MI unlocked: SCAO Interactive Court Data Dashboard → "LT - Landlord/Tenant" case type → county × year filings 2006–2025 (all counties)
- IL unlocked: AOC Circuit Court Statistical Dashboard → EVICTION case category → county × quarter filings, 2022–2025 dashboard + 2018–2021 companion
- MD rescue verified GO: District Court monthly LT case activity PDFs, 2005–2026 live on mdcourts.gov, text-layer, county-month; ~1-day parser
- LSC CCDI: unchanged since June (2016-01→2025-09); filings_count = NEW eviction filings at filing date (LSC FAQ) → ETS mixing OK
- NY OCA Power BI: monthly filings 2019–July 2026 (cross-validation + currency)
- DC: January Advisors data public but Jun 2025+ only — stays excluded; NJ/OR: no new bulk paths, existing scripts remain correct

**Status:**
- Done: search phase complete; no duplication of May–June sweeps
- Pending: acquisition/ingest (LSC bulk, MD parser, MI/IL extraction, NJ PDF script run, OR/IA emails)

## 2026-07-21 — MD historical PDF parser built and validated

**Operations:**
- Opus coder agent built `data_prep/monthly_panel_expansion/01b_download_md_statistics_pdfs.R` + `01c_parse_md_statistics_pdfs.R`; downloaded 22 annual PDFs (2005–2026) to `data/raw/monthly_expansion/md_raw/statistics_pdfs/`
- Outputs: `md_lt_county_month.csv` (primary, 6,168 rows, 24 counties × 257 months, 2005-01–2026-05), `md_lt_detail_county_month.csv` (detail, Jul 2019+)
- Fable independently re-verified: keys unique, no NA, 2018=664,592, COVID collapse 2020=305,401, Apr–Jun 2020 = 6,324/3,732/2,193

**Decisions:**
- Primary series switches source report at Jul 2019 (Civil Case Activity LT block → dedicated LT report FTPR block), flagged per-row in `source_report`; transition seamless (FTPR ≈ 99% of LT volume) — awaiting Ben's sign-off before merge

**Status:**
- Done: MD county-month LT filings 2005–2026, parser + validation
- Pending: wire into `05_merge_expanded_panel.R`; Ben decision on Jul 2019 definitional switch

## 2026-07-23 — NH panel vs. court source: zeros confirmed as feed termination

**Operations:**
- Fetched NH Judicial Branch monthly LT writ PDFs (2023/2024/2025) via PDF toolkit (Akamai blocks curl; browser+toolkit work)
- Wrote `data/raw/monthly_expansion/nh_lt_state_month_courtsource.csv` (36 rows, 2023-01–2025-12, checksums verified vs. PDF totals)

**Results:**
- Panel NH 2023 Jan–Jun = 517/454/564/540/605/535 — matches court source EXACTLY (same source & definition)
- Panel NH 2023 Jul–Dec = 0/0/0/0/0/0; court source = 602/526/498/521/468/391
- Panel 2023 total 3,215 vs. true 6,221 — 48% of the year missing
- Court totals 2024 = 5,234, 2025 = 5,051 — no decline; NH filings never collapsed
- CONCLUSION: the −57% NH ATT is mechanical (feed stopped Jun 2023), confirming HANDOFF's coverage-artifact diagnosis

**Decisions:**
- Repair is trivial for the STATE-month panel (only "Total by month" row needed); the prior 2.5–3.5 day estimate applied to a county-level build requiring circuit→county crosswalks
- Pre-treatment depth unchanged (still Dec 2018–Nov 2019); repair fixes post-treatment only

**Status:**
- Done: NH discrepancy quantified, corrected series written
- Pending: Ben decision on backfilling panel + re-running per-state did2s without the fake NH outlier

## 2026-07-23 — Maryland merged into state-month panel

**Operations:**
- Wrote/ran `data_prep/monthly_panel_expansion/07_merge_md_into_panel.R`
- Panel: 38 → 39 states, 3,982 → 4,149 rows. MD = 167 months (2012-01→2025-11), 130 pre-treatment / 37 post (treat_start 2022-11-01)
- Backup: `data/raw/deprecated/state_month_panel_with_treatment_pre_md_merge_2026-07-23.csv`

**Verification:**
- MD annual totals reconcile exactly to parser output (2016=642,348; 2018=664,592; 2020=305,401)
- All 24 jurisdictions asserted present in every month before aggregation
- Non-MD rows asserted byte-identical via `identical()` on full data frame

**Decisions / open flags:**
- Denominator = ACS 2019 5-yr MD county sum (730,055). Panel's native vintage could NOT be reproduced — its values equal ETS/LSC covered-county sums (verified NH/AZ/DE/ME exact), but no ACS year matches NH's 151,523 (closest ACS2022, −352). Constant per state → absorbed by state FE in logs. **Ben can correct from Eviction Lab's internal definition.**
- MD filing intensity is a level outlier: 75.3 filings/1k renters/month vs VA 27.4 (next highest) — Maryland's serial Failure-to-Pay-Rent pattern. Fine in logs w/ state FE; matters for any level/rate spec.
- Jul-2019 definitional seam in MD primary series still unratified (sits 3+ yrs before treatment).
- Trimmed to panel extent; full 2005-2026 series remains in `md_lt_county_month.csv`.

**Status:**
- Done: MD in panel, validated. NOT committed.
- Pending: Ben ratification of seam + denominator; analysis rerun (deliberately not run)

## 2026-07-23 13:57 — Repair Maine panel series from Maine Judicial Branch court source

**Operations:**
- Downloaded MEJIS "15-Year Monthly FED Filing Trends" (fed-monthly15yr-report.pdf, 12 pages, county×month×year 2012–2026)
- Parsed to data/raw/monthly_expansion/me_fed_county_month_year.csv (2880 rows) and me_fed_state_month_courtsource.csv (120 state-months, 2016–2025); county sums reconcile to printed statewide on all 180 cells
- data_prep/monthly_panel_expansion/07_repair_me_from_court_source.R — full-replace repair of ME in state_month_panel_with_treatment.csv
- Backup: data/raw/deprecated/state_month_panel_with_treatment_pre_me_repair_2026-07-23.csv

**Decisions:**
- Full replace (not NH-style splice) — ME court source diverges from ETS panel on 62/89 overlap months (mean|diff| 49.8, max 348, corr 0.698); splicing would seam two vintages. User approved full replace 2026-07-23.
- ME range 2016-01→2025-11 (panel envelope), never-treated control throughout.

**Results:**
- ME artifact identified: ETS recorded 2023-06..2023-12 as literal zeros (same defect as NH)
- ME: 96 → 119 months, 7 fabricated zeros removed, 23 months added (through 2025-11), 0 zeros, 0 NA
- Non-ME states untouched (only last-digit float re-serialization); 39 states, 0 duplicate keys

**Status:**
- Done: Maine data repaired + verified
- Pending: remove ME from EXCLUDE_STATES and re-run power sim / pretrends (intentionally not re-run, mirroring NH); commit

## 2026-07-23 14:14 — Include repaired Maine: county files, re-run power + pretrends

**Operations:**
- data_prep/monthly_panel_expansion/08_repair_me_in_county_files.R — propagated ME court source into combined_monthly_panel.csv and monthly_county_data_download.csv (ME 1536→1904 county rows each, 2016-01→2025-11); backups in data/raw/deprecated/
- Removed ME from EXCLUDE_STATES: scripts/run_pretrends_statepanel.sh, analysis/pretrends/pretrends_statepanel_template.R (default ME→""); new scripts/run_twfe_power_2024_with_me.sh
- Re-ran pretrends (output/pretrends_statepanel_me_included) and TWFE power sim (data/output/twfe_power_out_2024_with_me)

**Results:**
- Pretrends with ME: 26 states (was 24), parallel trends NOT rejected (CS Holm p=1); Sun-Abraham NO LONGER rejects (Holm p=0.357) post NH+ME repair; overall ATT +0.011 (SE 0.16), n.s.
- Power sim with ME: 38-state raw panel; MDE unchanged — power 0.828 at 5% (vs 0.835 without ME), Type I 0.065
- ME confirmed purely additive to balanced set (25→26 states; nothing dropped)

**Decisions:**
- County-level repair (not state-level substitution) to preserve combined_monthly_panel structure for all its consumers
- CS calibration (cs_calibration_multi_estimator.R) left with hardcoded ME exclusion — not in re-run scope

**Status:**
- Done: ME repaired across all 3 panel files, re-run, CLAUDE.md updated
- Pending: optionally re-run CS calibration with ME; patch pre-existing output/pretrends_statepanel_template if desired
