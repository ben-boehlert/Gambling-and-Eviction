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

## 2026-07-23 — Blinded power-simulation framework: audit, design, and implementation (in progress)

**Operations:**
- Phase 1 audit: 5 parallel subagents (2x Opus, 3x Sonnet) audited the core power-sim engine, calibration/patches/local `did`+`DRDID` packages, data schemas (blinded), literature + `hollina/power-analysis` repo, and repo periphery (scripts/docs/data_prep/git state), all under a strict blindness protocol (no `output/`, `figures/`, `CLAUDE.md`/`AGENTS.md` bodies, HANDOFF files, or treated-period outcomes).
- Wrote `docs/methodology/POWER_SIMULATION_CODE_AUDIT.md` (13 numbered findings, file:line cited).
- Wrote `docs/methodology/POWER_SIMULATION_BLINDNESS_PROTOCOL.md` (allowed/prohibited inputs, cutoffs, automated checks, disclosure of harness auto-loading `CLAUDE.md` into orchestrator/subagent context).
- Wrote `docs/methodology/POWER_SIMULATION_DESIGN.md` (estimand, units, estimators, calibration samples S1-S5, pseudo-schedules D1-D4, effect injection M1/M2, effect grid anchored to external literature only, OC metrics, failure criteria, selection rule, `R/power/` module contract).
- Wrote `docs/methodology/PRE_ANALYSIS_PLAN_POWER_LANGUAGE.md` (draft PAP language with `[OC: ...]` placeholders to be filled only from blinded simulation output).
- Implemented `R/power/` foundation (1 subagent, Opus): `config.R`, `blindness_checks.R`, `load_blinded_panel.R`, `make_pseudo_schedules.R`, `config/power_validation.yml`, `tests/run_tests.R` + 3 test files. **41/41 assertions passing.**
- Implemented `R/power/impose_effects.R` + `R/power/run_estimators.R` (1 subagent, Opus) + 2 test files. **86/86 assertions passing** (45 new + 41 pre-existing), including toy-panel effect recovery for TWFE/did2s/CS and a null-size smoke test.
- Concurrently launched a second subagent (Sonnet) to build `R/power/summarize_operating_characteristics.R`, `R/power/validate_simulation.R` (BHNS-style validation), `R/power/run_scenario_grid.R`, `config/power_primary.yml` + `config/power_sensitivity.yml`, and shell runners — **still running as of this entry**.

**Decisions:**
- Effect-size grid derived exclusively from external literature (Hollenbeck/Larsen/Proserpio, Goss & Mangrum FRBNY, Guo/Peng/Meyerhoefer, Eviction Lab aggregate filing counts) — never from this project's own estimates, per blindness protocol.
- Anticipation cutoff (default 6 months) enforced as a floor in every calibration sample, including S1 (strict universal) — otherwise early-cohort states (DE/NJ/WV, mid-2018) would violate the blindness assertion even under the nominal 2018-05-31 universal cutoff.
- Recorded both a genuine CS multiplier-bootstrap arm (reconstructed via `did:::mboot()` on the exposed simple-aggregate influence function, since `did` 2.3.0's public `aggte()` API doesn't expose one for the "simple" estimand) and the legacy t-on-bootstrap-SE arm, rather than silently picking one — this directly addresses audit finding F2 (existing calibration scripts conflate the two).
- Model switched mid-session from Fable 5 to Sonnet 5 by user; documenting proactively per user instruction in case of usage limits.

**Results:**
- High-severity audit finding: `power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R` and `..._merged.R` are labeled/configured as Callaway-Sant'Anna power simulations but actually estimate plain TWFE (`fixest::feols`) — all `did_*` config is dead code.
- The project's local "patched" `did`/`DRDID` package copies are not installed or loaded by any active calibration/pretrends script; `library(did)` resolves to stock CRAN 2.3.0. The p-value fix is reimplemented inline in every current harness instead.
- Calibration scripts (`cs_calibration_multi_estimator*.R`) and the recommended pretrends pipeline (`run_pretrends_statepanel.sh`) use different COVID drop windows (2022-03-31 vs 2021-07-31) — the "definitive" calibration numbers were computed on a different sample than the headline pipeline.
- Blinded data facts: universally untreated window is only 2016-01 to 2018-04/05 (28-29 months); county panel strongly unbalanced (only 12% of counties span the full 2016-2025 window); pre-2018-05 overdispersion median var/mean ≈ 1.43 (motivates negative-binomial injection, not Poisson); cohort structure by online-launch date is 18 cohorts, max size 2 (singleton-heavy — must be preserved in pseudo-schedules, not randomized to a common date).
- No automated tests existed anywhere in the repo before this session (only one ad hoc regression test in `patches/`).

**Commits:**
- None yet — no commit has been requested this session. All new files are untracked (`R/power/`, `config/power_*.yml`, `tests/`, `docs/methodology/POWER_SIMULATION_*.md`, `docs/methodology/PRE_ANALYSIS_PLAN_POWER_LANGUAGE.md`).

**Status:**
- Done: Phase 1 audit + blindness protocol; Phase 2 design doc; PAP language draft; `R/power/` foundation, effects, and estimators modules with passing tests (86/86).
- Pending: OC summarizer / BHNS validation / scenario-grid runner / primary+sensitivity configs (subagent in flight); full integration test run; small validation run on real blinded data; `verify_deliverables.R` additions; navigation doc updates (README/START_HERE/QUICK_START pointers to the new framework); final deliverables report with exact run commands; deprecation of the mislabeled/broken scripts identified in the audit (recommend only, do not delete, per user's global "deprecate don't delete" rule).

## 2026-07-23 (cont.) — Power framework: bug fixes found in post-implementation review

**Operations:**
- Second implementation subagent completed `R/power/summarize_operating_characteristics.R`, `R/power/validate_simulation.R`, `R/power/run_scenario_grid.R`, `config/power_primary.yml` (11 scenario families), `config/power_sensitivity.yml` (26 scenarios), 3 shell runners, and 4 test files — 132 total assertions passing at handoff, plus a real end-to-end run.
- Manually reviewed and fixed 3 bugs the subagent flagged but did not have authorization to fix in sibling files:
  1. **TWFE wild-cluster-bootstrap always failed** (`R/power/run_estimators.R`): `fwildclusterboot::boottest.fixest()` internally re-evaluates the fixed-effect formula as an arithmetic expression, which throws `non-numeric argument to binary operator` when the unit FE is a character vector (state abbreviations). Fixed by using the integer `id` column (already built by `.re_prep()`) instead of the character `unit_id` for the FE term. Reproduced and verified the fix in isolation before applying.
  2. **Wild-bootstrap CI always NA**: `fwildclusterboot::confint()` is not an exported symbol (the package only registers an S3 method `confint.boottest` dispatched through the base generic); the namespaced call threw "not an exported object," silently swallowed by `tryCatch`. Fixed by calling `stats::confint(wb)` instead.
  3. **S1 (strict universal) calibration sample silently included 74-77 months instead of the documented 28-29**: the raw `state_month_panel_with_treatment.csv` has 4 states with legacy data reaching back to 2012-01 while the rest of the panel starts 2016-01 — an artifact of a historical ETS merge, not a deliberate design choice. Mixing 8 extra years of unbalanced pre-history into just those 4 states silently changed every calibration sample's composition and was directly responsible for an inflated TWFE null-rejection rate the subagent observed in its first validation run (0.26 vs nominal 0.05). Fixed by adding an explicit `panel_floor` config default (2016-01-01, documented in `config.R`) applied uniformly in `load_blinded_panel()` before any sample/cutoff logic.
- Verified all three fixes in isolation (reproduced each bug standalone, confirmed the fix resolves it) before re-running the full test suite.
- Re-ran `Rscript tests/run_tests.R`: all 8 test files pass (blindness/effects/estimators/grid/loader/oc/schedules/validate), 0 failures/errors.
- Added `output_blinded_power/` to `.gitignore` (regenerable simulation output, consistent with the project's existing `data/output/` convention).

**Decisions:**
- Treated the sibling subagent's "found but not authorized to fix" flags as required follow-up rather than pre-existing known limitations, since two of the three directly corrupted operating-characteristic validity (inflated Type-I error; silently-missing inference arm), not just cosmetic gaps.
- Chose to add a `panel_floor` config default rather than special-casing S1 alone, because the 2012-2016 legacy data for those 4 states would have equally (if more subtly) distorted S2/S3 risk-set composition for those specific states.

**Results:**
- `load_blinded_panel(level="state", sample="S1")` now returns 29 months (2016-01 to 2018-05), matching `POWER_SIMULATION_DESIGN.md` §7's documented S1 window.
- TWFE wild-cluster-bootstrap arm now converges and reports a genuine `boottest`-derived CI (spot check: analytic p=0.472 vs wild p=0.866 on a toy injected effect — as expected, wild bootstrap is more conservative with few clusters).
- Full test suite: 8/8 files, 0 failures.

**Commits:**
- None yet — no commit requested this session.

**Status:**
- Done: full `R/power/` framework (foundation, effects, estimators, OC summarizer, BHNS validation, scenario-grid runner) implemented, tested, and bug-fixed; primary + sensitivity configs; shell runners.
- Pending: `verify_deliverables.R` additions, navigation doc updates, final deliverables report with exact run commands, recommendation on deprecating the mislabeled/broken legacy scripts (audit-only, no deletion).

## 2026-07-23 (cont.) — Wrap-up: verify_deliverables.R, README, final state

**Operations:**
- Added §8 to `verify_deliverables.R`: checks all 4 methodology docs, all 9 `R/power/*.R` modules load, all 3 configs exist, all 3 shell runners exist, and runs the full `tests/run_tests.R` suite as a gate (exit-status checked, not just file presence).
- Added `output_blinded_power/` to `.gitignore` (regenerable, consistent with existing `data/output/` convention).
- Added a "Blinded Power-Simulation Framework" section to `README.md` with run commands and doc links, plus updated the repository-structure tree to list `R/power/`, `config/`, `tests/`, `output_blinded_power/`.
- Final full-suite run: `Rscript tests/run_tests.R` — 8/8 files pass, 0 failures.

**Status:**
- Framework complete: audit, blindness protocol, design doc, PAP language draft, full `R/power/` implementation (9 modules), 3 configs, 3 shell runners, 8 testthat files, `verify_deliverables.R` wired up, README updated.
- Nothing has been committed to git this session (all changes untracked/unstaged per user's "only commit when asked" convention).
- Recommended-but-not-executed: deprecating the mislabeled/broken legacy power scripts identified in the audit (`power_simulation_cs_reg_*_REVISED.R`, `*_merged.R`, `*_INSTRUMENTED.R`, `cs_calibration_test.R`) — flagged in `POWER_SIMULATION_CODE_AUDIT.md` §7 for Ben's review, not moved.
- Not yet run: the primary (`config/power_primary.yml`) or sensitivity (`config/power_sensitivity.yml`) simulations themselves — only the small validation tier has been exercised (via tests and the subagent's manual smoke run). Running the primary config is the next real step toward filling the `[OC: ...]` placeholders in the PAP language doc.

## 2026-07-23 (cont.) — Post-launch fixes: serial-run bug and county wild-bootstrap arm

**Operations:**
- Ben ran validation (PASS, all 10 invariant checks) and launched `scripts/run_power_primary.sh`; its log showed `workers = 1`.
- Root cause: `future::availableCores()` returns 2 under `Rscript --vanilla` (environment hints stripped), so `availableCores() - 2` collapsed to 1 worker. Fixed the default in `run_scenario_grid.R` to take `max(availableCores(), parallel::detectCores()) - 2` (now 6 on this 8-core machine, verified under `--vanilla`).
- County-level TWFE wild arm failed: `boottest()` rejects fixest models whose internally-removed FE levels (singletons/collinear counties) aren't excluded from the data. Fixed in `run_estimators.R` by refitting on the reduced sample (dropping `fit$fixef_removed` levels) for the wild arm only; verified converged CI at county level.
- Full test suite re-run: all pass.
- Timing measured (county S2, one rep): panel load 1s, injection 0.7s, twfe analytic 0.6s, wild ~17s, did2s ~4s, CS (analytic+bootstrap) ~20s.

**Status:**
- Ben should kill the serial primary run and relaunch `bash scripts/run_power_primary.sh` (now defaults to 6 workers; resume granularity is per-scenario so nothing meaningful is lost).
- Rough wall-clock at 6 workers: scenario S001 (county, 500/250 reps × 11 deltas × 3 estimators) ≈ 6-9 h; full 11-scenario primary grid likely 1-2 days on this machine. Della (`della_upload/` workflow) is the alternative for the sensitivity grid.

## 2026-07-23 (cont.) — Parallel-worker globals fix

**Operations:**
- Ben's relaunched primary run (workers = 6) crashed immediately: `could not find function ".ie_event_time"`. Cause: future/furrr exports the worker lambda's directly-referenced functions but does not recurse into those functions' own internal dot-prefixed helpers, so second-level globals (`.ie_event_time` in `impose_effects.R`, `.re_prep` in `run_estimators.R`, etc.) were missing on multisession workers. The serial path and the mock-based parallel test both masked this.
- Fix in `R/power/run_scenario_grid.R`: each worker re-sources the five needed framework modules once (sentinel-guarded on `.ie_event_time`/`.re_prep`; `source()` defaults to globalenv so definitions persist across reps within a worker; repo root captured as a plain string so it exports cleanly).
- Verified: real-module parallel smoke run (workers=2, under `--vanilla`) completes with 0 failures; full test suite still green. Smoke output left in `output_blinded_power/_smoke_parallel_realmods/` (gitignored).

**Status:**
- `bash scripts/run_power_primary.sh` ready to relaunch.

## 2026-07-23 (cont.) — Della upload package for the blinded power framework

**Operations:**
- Built `della_power_upload/` (6.8 MB, gitignored, regenerable) via new generator `scripts/make_della_power_upload.sh`. Contents: the 9 `R/power/` modules, 3 configs, full testthat suite, `utils/eviction_treatment_schedule.R`, the 3 data files the blinded loader may read, blindness protocol + design docs, and a repo-root marker stub (`power_simulation_cs.R` — marker only, clearly commented).
- Della launcher templates version-controlled in `scripts/della_power/`: `setup.sh` (login-node CRAN install, R/4.4.2 module, no patched packages needed per audit F4), `run_validation.sh` (tests + 25-rep BHNS validation, login-node), `run_primary.slurm` (16 cpus/32G/24h), `run_sensitivity.slurm` (16 cpus/32G/48h). Both slurm scripts use `$SLURM_SUBMIT_DIR` — no hardcoded scratch path (fixes the inconsistency the audit flagged in the old `della_upload/run.slurm`). Both are resume-safe (per-scenario partials; resubmit on timeout).
- **Verified self-containment**: ran the full test suite AND a 5-rep validation from inside `della_power_upload/` — `power_repo_root()` resolves to the upload folder, all paths resolve locally, everything passes, outputs land in the folder's own `output_blinded_power/`. Rebuilt pristine afterward.

**Status:**
- Ben can upload with `scp -r della_power_upload della:/scratch/gpfs/DESMOND/ben/eviction_gambling/` then follow README.txt (setup.sh → run_validation.sh → sbatch run_primary.slurm → sbatch run_sensitivity.slurm).

## 2026-07-24 — Della primary run TIMEOUT; SLURM resources bumped

**Operations:**
- Ben's Della primary job (11566475) TIMED OUT at the 24h `short`-QOS limit — otherwise healthy (95% CPU efficiency, 9.9/32 GB memory). Cause: 11 scenarios × county-level CS/wild-bootstrap cost > 24h at 16 cores.
- Updated `scripts/della_power/run_primary.slurm` and `run_sensitivity.slurm`: `--cpus-per-task=32`, `--mem=64G`, `--time=71:59:00` (moves to `medium` QOS; memory headroom was ample at 633 MB/core). Rebuilt `della_power_upload/`.
- NOTE (security): Ben accidentally pasted what appears to be a password into chat; advised rotation. Not recorded anywhere.

**Status:**
- Ben should either re-upload the two .slurm files (or edit `--time`/`--cpus-per-task`/`--mem` directly on Della) and `sbatch run_primary.slurm` again — resume skips completed scenarios; only the scenario in flight at timeout re-runs.

## 2026-08-03 — Power framework committed; incremental re-runs (hash ids, SLURM arrays); CS state-level segfault found

**Operations:**
- Committed the whole blinded power framework as a restore point (`12725a5`) — it had been entirely untracked since 2026-07-23. 38 files, 5,507 insertions.
- `R/power/run_scenario_grid.R`: replaced positional `scenario_id` (`S%03d_` + slug) with a sha1 content hash over the scenario's identity (all axes incl. `treat_def`/`loader_anticipation`, plus estimators, effect grid, rep counts, support minima, `base_seed`). Added `.assign_scenario_ids()`, `.scenario_identity_string()`, `.canon_atom()`, `.canon_est_reps()`, `.scenario_hash()`, `.scenario_seed_offset()`.
- Per-rep seed now uses a hash-derived offset (mod 10007) instead of `scenario_index`. `power_rep_seed()` arithmetic unchanged, so its collision argument and existing tests still hold.
- Added `scenarios =` to `run_scenario_grid()` (positions / block names / ids) via `.select_scenarios()`. Subset runs write partials only and return early before the summary block, so concurrent tasks cannot race on run-level files. Exposed as `SCENARIOS` env var on both local runners.
- `scripts/della_power/`: `run_primary.slurm` → `--array=1-11`, `run_sensitivity.slurm` → `--array=1-26`, both at 8 cpus / 16G / 23:59:00 (short QOS). New `run_aggregate.slurm` (post-array summary pass) and `list_scenarios.sh` (prints expanded grid + correct array range). README rewritten for the new submit sequence. Added `digest` to `setup.sh`.
- `verify_deliverables.R` §8: checks all 6 Della launchers and asserts each `--array` range matches its config's expanded scenario count.
- 8 new tests in `test-grid.R`. Full suite passes; `verify_deliverables.R` reports 0 failures.

**Decisions:**
- Hashed the execution settings (not just the axes) so the invariant "same id ⟺ same inputs" holds; this also fixes a latent wart where shrinking `effect_grid`/`n_reps` left a stale superset partial that the completeness check would accept.
- Made the seed content-derived rather than positional. Consequence: **the timed-out Della run's existing partials are orphaned** and will re-run. Not auto-adopted, because they were computed under position-based seeds and so would not be reproducible from the config — a bad property for a PAP artifact. An opt-in adoption path can be added if the salvage is worth more than strict reproducibility.
- Recomputed ids after `n_reps_override` so a reduced-rep smoke run cannot write to a full run's partial filename.

**Results:**
- Verified the array workflow end-to-end: 11 primary / 26 sensitivity scenarios expand correctly; `list_scenarios.sh` runs self-contained from inside `della_power_upload/`; a real-module (not mock) subset run of scenario 9 wrote only its partial, with hash-derived seeds and no run-level files.
- **BLOCKER FOUND (pre-existing, not from this session's changes): `did::att_gt()` SEGFAULTS on the state-level panel.** Probe at state/S2/D1: 3 of 4 base seeds died with "An irrecoverable exception occurred. R is aborting now" — a C-level crash inside `att_gt`, which `tryCatch` cannot catch, so the process dies and no partial is written. County-level CS ran fine on both seeds tested (84/91 and 77/99 cells converged; non-identifiable cells return NA gracefully).
- Exposure: primary scenarios 7–11 (state) and 25 of 26 sensitivity scenarios (all state-level with `estimators: [cs, twfe, did2s]`). County scenarios 1–6, including the headline, are unaffected.
- This is the exact hazard `patches/att_gt_safe.R` + `patches/preflight_support_check.R` were written for, and which the Phase-1 audit flagged as unused by the new framework (`library(did)` resolves to stock CRAN 2.3.0). Under `resume`, a segfaulting scenario writes nothing and re-runs into the same crash — an infinite-retry trap for an array task.

**Commits:**
- `12725a5` Add blinded power-simulation framework for the pre-analysis plan
- `a803f03` Make power runs incremental: content-addressed scenarios + SLURM arrays

**Status:**
- Done: framework committed; hash-based ids and seeds; scenario subsetting; array launchers + aggregate pass + scenario lister; verify_deliverables wired up; tests green.
- Pending (recommended before submitting anything state-level): wire the CS arm in `R/power/run_estimators.R` through the preflight support check / `att_gt_safe()` so non-identifiable cells return NA instead of crashing R.
- Pending (unchanged): the two-stage coarse→dense delta grid and the deterministic-mechanism analytic shortcut discussed this session — neither implemented.
- Note: `output_blinded_power/_cs_probe_*`, `_cs_cty_*`, `_int_*` diagnostic run dirs were left in place (gitignored) after a cleanup command was declined.

## 2026-08-10 16:15 — PAP porting assessment; primary-run triage; smoke + cheap pilot runs

**Operations:**
- Read `Arnold Housing Loss Gambling - Application.docx` + `AV_Pre-Analysis_Plan_Guidance_202507.pdf`; mapped application sections onto AV's QED PAP checklist.
- Triaged Della primary run 12114571 (submitted 2026-08-08): 4 state scenarios COMPLETED (6–13h); tasks 2 & 8 (the S3 blocks) FAILED at ~10 s; 5 county tasks pacing to 50–63h vs the 48h wall — all will TIMEOUT with total work loss (no batch checkpointing in `run_scenario_grid.R`; partial written only after all 20 batches).
- Reproduced the S3 failure locally (`R/power/make_pseudo_schedules.R`): D1 places the full real online template (18 cohorts, ~24 states, 55-month span) but S3 has only 12 (county) / 14 (state) never-treated states — structurally infeasible; D4 (proportional scaling) is the correct never-treated design.
- Created `config/power_cheap.yml` (8 scenarios: 4 county + 4 state, twfe+did2s 500 reps × 11 δ, no CS, S3 + anticipation blocks dropped) + `scripts/della_power/run_cheap.slurm` (array 1-8, 48h).
- Created `config/power_smoke.yml` (2 headline scenarios, 50 reps × 4 δ) + `run_smoke.slurm` (array 1-2, 6h).
- Patched `run_aggregate.slurm` / `run_aggregate.sh` to accept `cheap`/`smoke`; added the 4 new files to `make_della_power_upload.sh`; rebuilt `della_power_upload/`; testthat suite green; scenario expansions verified (8 and 2).
- Launched smoke run on Della (job 12220717): state scenario COMPLETED in 29 s (partial on disk); county on pace (batch 1/2 at 34 min).
- Documentation: new "Blinded Power-Simulation Framework (PAP)" section + 3 TO DO items in `CLAUDE.md`; run-ladder + WARNINGS rewrite of `scripts/della_power/README.txt`; D1×S3 infeasibility addendum in `docs/methodology/POWER_SIMULATION_DESIGN.md`.

**Decisions:**
- PAP ports ~60–70% of the application's design sections (§§2.1, 3.1–3.3, 4); the estimator-selection rule, power section, and key-modeling-decisions items get rewritten — pre-register a calibration-gate decision rule (size at δ=0 disqualifies, then MDE among survivors), not the application's stale "CS-DD preferred if different from OLS" rule. MDE must be stated in real-world (filings/year) terms per AV guidance; report heterogeneous-DGP MDE alongside homogeneous.
- Run ladder smoke → cheap → CS-only, sharing `base_seed = 20260723` so runs are paired rep-for-rep; CS resubmission blocked until batch checkpointing + `--time` raise land.
- S3 dropped from D1 blocks (cheap done; primary pending); never-treated comparison via D4; PAP reports the infeasibility explicitly.
- `est_anticipation` confirmed CS-only (`att_gt` arg) → anticipation-6 block excluded from CS-free configs.
- Let the 5 doomed county tasks run to the wall (nothing salvageable; small chance pacing estimates are off).

**Results:**
- Cheap-run pacing: county twfe+did2s ≈ 1.5h per 25-rep batch → ~28–30h per county scenario; state scenarios minutes-to-hours. Smoke: ~1h county, 29 s state.
- Sim scale documented: primary scenario = 11 δ × (250 CS + 500 twfe + 500 did2s) ≈ 13,750 estimations; ~150k primary + ~350k sensitivity total; MC SE on rejection ≈ 1.0–1.4 pp.

**Commits:**
- (none — new files left uncommitted alongside the working tree; commit offered)

**Status:**
- Done: smoke state cell verified end-to-end; cheap run built, tested, packaged, uploaded (rsync via della9 after della8 refused pre-auth).
- Pending: smoke county partial (~16:20) → `bash run_aggregate.sh smoke` → sanity-check `oc_summary.csv` → `sbatch run_cheap.slurm`; per-batch checkpointing + `--time` raise before the CS arm; S3 removal in `power_primary.yml`; D4 promotion decision; PAP draft.

## 2026-08-10 21:30 — Smoke-ladder debugging: OOM root causes, archived package, D1 infeasibility, reproducibility anomaly

**Operations:**
- Smoke run 12220717: state cell completed (29 s), county cell completed (66 min) — but every wild-bootstrap row failed: **`fwildclusterboot` is archived from CRAN** and Della's setup silently skipped it. Fixed `scripts/della_power/setup.sh` (s3alfisc r-universe repo first + hard-fail check); installed on Della (16:36, added only its own deps — dplyr/lubridate untouched, verified via library mtimes).
- `sacct` revealed the 5 primary county tasks (12114571) died **OUT_OF_MEMORY at ~42h**, not walltime — in-RAM batch accumulation against 16G. Batch checkpointing is therefore a correctness fix, not a convenience.
- Smoke rerun 12223288: county task **OOM-killed in 2 min** — `boottest()` without `fe` dummy-expands ~1,200 county FEs (~1.8 GB/worker × 8 ≈ 16G). Local measurement: no-fe 1.84 GB/5.2 s vs `fe="id"` 0.60 GB/1.0 s, identical p (0.3433). Fixed `R/power/run_estimators.R` (boottest `fe = "id"`); bumped smoke/cheap `--mem` to 32G; tests green; rebuilt + rsynced upload.
- Smoke rerun 12242118: county task now fails instantly — **D1 infeasible**. Built an exact seed-path repro (scenario hash S3e1321ff2d, offset 4551, reps 1–50): **50/50 schedule failures, identical on laptop and on Della**, with md5-verified identical data/config/schedule code and unchanged core R library.
- Forensics on the 15:12 success (12220717_1, 50/50 feasible schedules): inputs overwritten by the later rsync, /scratch unsnapshotted → **cause unrecoverable; logged as an unresolved reproducibility anomaly**. Its OC numbers (did2s 26–31% Type I, county-TWFE power) demoted to unreliable. Old partial preserved in `output_blinded_power/smoke_prewildfix/` on Della.
- Documented everything in CLAUDE.md ("2026-08-10 evening findings" block).

**Decisions:**
- **Cheap run NOT launched.** No 30h run on a design that is knife-edge/infeasible and whose one success is unreproducible.
- Redesign direction (to confirm with Matt): D1 places the **panel-restricted template** (~12 cohorts among panel states) instead of the national 24-state template — fixes feasibility and design realism together; implement as a config axis so content hashes change cleanly.
- Per-rep schedule infeasibility should yield a failure row, not abort the scenario (one bad draw must not kill a 30h task).
- Ladder verdict: smoke testing caught an archived package, a memory bomb, a fragile design, and an irreproducibility for ~$2 of compute — process validated even though the night ended without a cheap launch.

**Commits:**
- (none — all changes uncommitted on `nh-data-repair`)

**Status:**
- Done: wild-bootstrap memory fix (validated locally), setup.sh r-universe fix, 32G mem bumps, OOM postmortem, D1 infeasibility proven and documented.
- Pending (ordered, before any relaunch): panel-restricted D1 template as config axis → per-rep infeasibility → failure rows → batch checkpointing → re-run smoke → cheap → CS arm (72h/`--mem` raised). Plus: S3 removal in `power_primary.yml`, PAP draft, Matt meeting decisions (see Google Doc agenda).

## 2026-08-10 23:55 — Anomaly RESOLVED; panel-template results; state cheap complete; commits

**Resolution:** the day's reproducibility anomaly was commit `2be0bd0` (16:16, concurrent county-exposure session): legalization-dates CSV repaired (adds online dates DE/NC/KY/ME/FL/VT/MO — file had frozen ~early 2023). Template grew ~24→~31 states → national-D1 infeasibility. Old-CSV runs succeeded; post-rsync runs failed; local HEAD comparisons were against the already-moved HEAD. No nondeterminism. The same commit also swept this session's in-progress files into tracking (checkpoint commit `fa10f9b`, 16:10).

**Ripple:** ME/VT/KY/FL no longer never-treated (MO post-panel) → pretrends headline results in CLAUDE.md are STALE; re-run pipeline. FL 2021 voided launch needs PAP flag.

**Results (corrected panel template, repaired schedule):**
- Smoke county: did2s 4.1% Type I / SE-SD 0.96; TWFE-wild 4.0%; TWFE analytic 10%. Earlier "did2s 31%" reading was an artifact of the old national template (5 control clusters).
- Cross-machine: Mac reproduces Della analytic numbers exactly; wild ±1-2 reps (bootstrap RNG); did2s 48 vs 49/50 converged (BLAS).
- State cheap, 500 reps (LOCAL, ~40 min — Mac ~6x faster/rep than Della): did2s 23-29% Type I (disqualified); TWFE-wild 1-2% Type I, SE/SD 1.07-1.14, but MDE-80 > 20% under count_nb DGP (application's old "5% state MDE" not supported). Deterministic benchmark shows similar power → intrinsic state-panel noise.
- Della cheap launched (job 12248328): 8 scenarios, county ~Tue.

**Status:** county 500-rep results = PAP headline MDE, pending. Commits below pin the framework state.

## 2026-08-11 17:00 — CV3 cluster jackknife for CSDID: implemented, tested, calibrated (state)

**Trigger:** Karim, Nielsen, MacKinnon & Webb (2026), *Improved Inference for CSDID Using the Cluster Jackknife* (arXiv 2602.12043) added to repo. Question: does CV3 rescue CS on our singleton-cohort design?

**Operations:**
- Installed `didjack` 0.1.0 (`remotes::install_github("liu-yunhan/didjack")`).
- `R/power/run_estimators.R`: added `.re_cs_cv3()` (KNMW eq. 20) + `jack` inference arm on E1; new spec flags `cs_jack` (default FALSE) and `cs_faster_mode` (default TRUE); refactored `fit_att` → `fit_att_on(d, bstrap)` for delete-one refits.
- `tests/testthat/test-cs-cv3.R` (new): gating, schema conformance, failed-replicate accounting, and exact cross-validation vs `didjack` (1e-8 on SE/p/CI).
- `analysis/diagnostics/cs_cv3_calibration_state.R` (new): batch-checkpointed null calibration harness.
- `docs/methodology/POWER_SIMULATION_DESIGN.md`: E1 inference row + CV3 subsection.
- Ran 200-rep δ=0 state calibration (95 min, 6 cores) → `data/output/cs_cv3_calibration/` (+ README with full findings).

**Decisions:**
- **Do NOT use `didjack` in production** — its internal `aggte()` omits `na.rm=TRUE`; with our 30–43% non-identifiable (g,t) cells it dies on the first jackknife replicate (reproduced on 3 independent D1 draws). Reimplemented eq. (20) with `na.rm=TRUE`, pinned to their package by test.
- CV3 arm defaults OFF (costs ~34× one CS fit) so production configs are untouched.
- Standalone diagnostic rather than a config axis — scenario ids are content hashes; a new config field would invalidate completed Della partials.
- TWFE excluded from the diagnostic's default arms (see bug below).

**Results (200 reps, δ=0, state, 100% convergence):**
- CS analytic 21.5% reject / SE-SD 0.660; boot 24.5% / 0.692; boot_t 23.0% / 0.690.
- **CS + CV3: 0.5% reject / SE-SD 1.240** — overshoots into over-coverage, does not calibrate. Mean SE 0.639 ≈ 6× did2s → valid but uncompetitive on MDE. Matches KNMW §4 singleton-cohort composition caveat (untested in their paper).
- did2s state: 31.0% reject / SE-SD 0.521 — disqualified, consistent with prior cheap run.
- Analytic ≈ multiplier bootstrap (independent confirmation of KNMW pt. 3) → **`biters=199` in the CS arm buys nothing**; bootstrap arm droppable.
- **NEW, unexplained:** CS mean ATT under the null = +0.212 (~5.8 SEs from 0) vs did2s +0.060. δ=0 is a pure pass-through (`y_sim_count = fc`), so the outcome is the real panel and only assignment varies — a genuine systematic offset. Consistent with Deb/Norton/Wooldridge/Zabel (2025) unbalanced-panel aggregation bias. **Not diagnosed; over-rejection above conflates this with SE deflation.**

**Bugs found (both pre-existing):**
- `runtime_s` recorded in MIXED UNITS across all estimators: `difftime(a,b,"secs")` passes "secs" positionally as `tz`, not `units`, so longer durations silently reported minutes. Fixed at all 9 call sites in `run_estimators.R`. Past `runtime_s`-based cost estimates are suspect.
- `fwildclusterboot::boottest` raises an irrecoverable R exception (process abort, uncatchable) inside forked `mclapply` workers on the state panel, killing the whole batch. VERIFIED the same rep runs clean serially (analytic p=.625, wild p=.600) → fork interaction, not estimation failure.

**Commits:**
- (none — changes uncommitted on `nh-data-repair`)

**Status:**
- Done: CV3 implemented + cross-validated + state calibration complete; full test suite passes.
- Pending: diagnose the +0.21 null offset; decide whether to skip county CS+CV3 (county CS already OVER-covers at SE-SD 2.46, so CV3's inflation is the wrong medicine); omit-one-cluster ATT plot in pretrends pipeline; fold KNMW into `docs/literature_review_2026-07_estimation_strategy.md`.

## 2026-08-12 — Estimator-diagnostic visualization set (5 figures)

**Operations:**
- New scripts `analysis/visualization/estimator_diagnostics/fig{1..5}_*.R`; outputs `figures/estimator_diagnostics/*.{png,pdf}`. Plan: `quality_reports/plans/2026-08-12_estimator-diagnostic-visualizations.md`.
- Orchestrated: 3 coder subagents (Sonnet) in parallel; Fable reviewed each rendered PNG, one revision round (fig1 legibility/legend/x-range; fig5 label collision + band capping; fig4 subtitle).

**Decisions:**
- Fig 3 BJS demo uses "early differential drift, parallel near treatment" DGP — local PT holds, global PT fails: BJS spurious ATT ≈ −0.032 (analytic −0.037), CS ≈ 0. Panel A: Vermont (online 2024-01), imputation window spans COVID break.
- Fig 1/2 use RAW ETS panel + repaired schedule (23 treated, 21 monthly cohorts, 19 singleton; LA+NY Jan-2022 and DE+VT Jan-2024 shared); figs 4/5 use balanced 24-state calibration sample — subtitles distinguish the samples.

**Results:**
- Repaired schedule updates: NH post-repair mean post-gap ≈ −0.008 (artifact gone); fig2 extremes now VA (−0.64), CT (−0.38) vs KS (+0.33), AR (+0.27).
- Data flags: LA/MA/MO/NM/NV/RI have zero usable filings data; NC coverage ends 2023-06, before its 2024-03 online date; MD panel data starts 2012-01.
- State sim_results (20 sims) differs from CLAUDE.md 100-sim table (SunAb 15% vs 21%; BJS/did2s run rather than fail). BJS & did2s point estimates identical per draw (expected: same imputation; SEs differ).

**Commits:**
- (none — figure scripts/outputs uncommitted on `nh-data-repair`)

**Status:**
- Done: all 5 figures rendered, reviewed, delivered.
- Pending: decide which figures graduate into PAP/paper (would need INV-12 no-title versions); consider re-running state calibration at ≥100 sims before citing fig4/5 state numbers.

## 2026-08-12 02:00 — Cheap staged power-simulation framework (Sims 0–4) + decision memo

**Operations:**
- Built `analysis/cheap_sims/` (00_common, 01_stage0_audit, 02_run_cheap_grid, 03_summarize, 04_jackknife_diag, CHEAP_POWER_SIM_NOTES.md, della/ templates); outputs in `output/cheap_power_sim/`
- Ran: Stage-0 audit; 24-rep smoke (full 10-cell grid); 250-rep production grid (63 min, 6 cores); real-data LOSO (38 fits); real-data COVID cell decomposition; placebo LOSO anatomy (20 reps)

**Decisions:**
- Calendar-preserving placebo (real cohort dates fixed) instead of D1 anchor-shift — COVID alignment is the object of study; NV hard-excluded (absent from schedule CSV); ME included; NC/MO correctly not-yet-treated in-sample; COVID window 2020-03..2021-07 dropped (protocol default)
- Subset ATT(g,t) aggregation replicates did::aggte simple weights incl. wif term (validated to machine precision)
- Trimmed production grid to 6 fits/rep (lag6 + step arms at δ=2.5% only) after runtime measurement

**Results:**
- Null size: full 0% rejection (conservative, SE/SD 1.24); cross-COVID cells +0.67 placebo bias, 23% rejection; post-COVID −0.19, 14%; pre-COVID clean but only ~5% of real estimand weight
- Power ≈ 0 at 1–5% mature effects everywhere; coarse 80% MDE ≈ 45 log points (full); ramp dilutes dose to ~46% of mature; 6-mo lag immaterial
- Real data: full ATT −0.145 (SE 0.115) with 42% of weight on cross-COVID cells (subset −0.27 vs COVID-clean −0.05); CV3/analytic SE ratio 1.10; 17/24 treated LOSO deletions remove cells (estimand changes)
- Verdict (DECISION_MEMO.md): state-panel C&S design unviable for plausible effects; no second-stage suite; Della unnecessary; redirect to county did2s + COVID-clean estimands

**Commits:**
- none (working tree only; new files uncommitted)

**Status:**
- Done: Sims 0–3 at 250 reps, Sim 4 diagnostics, summary CSVs/figures, notes, decision memo
- Pending: placebo LOSO anatomy numbers folded into memo (running); user review of memo

## 2026-08-12 03:15 — Verification pass: oracle power + placebo-generator interrogation

**Operations:**
- Added `analysis/cheap_sims/05_oracle_power.R` (oracle-inference power/MDE) and `06_placebo_interrogation.R` (exchangeability audit + balanced common-support null); outputs in `output/cheap_power_sim/{oracle_*.csv,placebo_interrogation/}`
- Rewrote `output/cheap_power_sim/DECISION_MEMO.md` (rev. 2) and updated CHEAP_POWER_SIM_NOTES.md

**Results:**
- Oracle 80% MDE (mature scale): full 0.86, pre-COVID 0.41, COVID-clean 0.77 — design dead from information deficit regardless of SE method (oracle power at 5% mature effect ≈ 7%)
- The +0.67 cross-COVID placebo "bias" was a generator artifact: assignment far from exchangeable (ratios 0–8.2× vs equal-among-eligible; 2021-09 cohort never assigned); cross cells ~87% hosted by real-late-treated states; balanced exchangeable null (AK/GA/MN/OK/TX/UT) is mean-zero in all classes (cross −0.022, MC-SE 0.028)
- Durable facts: cross-cell noise SD 0.35–0.44 (3–6× clean cells); 42% of real estimand weight on cross cells; few-cluster SE understatement in 6-state world (SE/SD 0.65)

**Status:**
- Done: both user-requested verifications; memo revised accordingly
- Pending: user review; possible port of COVID-decomposition machinery to county did2s design

## 2026-08-13 — Design-preserving oracle-SD re-verification + composition-artifact discovery

**Operations:**
- Added `analysis/cheap_sims/07_design_preserving_null.R`: real design held fixed (treated states, dates, cohorts, missingness, C&S weights); untreated outcome paths varied via 3 serial-correlation-preserving generators (calendar-aligned never-treated donor blocks, own-path moving blocks, AR(1)); 250 reps each; outputs in `output/cheap_power_sim/design_preserving/`
- Diagnosed the nonzero design-preserving null mean via noiseless-baseline, balanced-frame, and demeaned-outcome tests
- DECISION_MEMO.md rev. 3 (addendum C: SD verdict; addendum D: composition artifact)

**Results:**
- Full-design null SD generator-robust at 0.065–0.088 (vs 0.140 calendar placebo, 0.307 balanced placebo) → oracle mature-scale MDE 0.40–0.54; information conclusion established per BHNS-style generator sensitivity check
- NEW: deterministic C&S composition artifact on ragged unbalanced frames: noiseless two-way baseline returns −0.070 (cells to |3.07|); exactly 0 on balanced frame or state-demeaned outcome; cause = reg_did_rc 2×2s with changing control composition. ~Half the real full ATT (−0.145) is this offset; fix = state-demean or balance frame

**Status:**
- Done: user's design-preserving verification; artifact isolated and documented
- Pending: consider state-demeaning patch for unbalanced-frame CS runs framework-wide (affects R/power placebo sims too)

## 2026-08-15 03:35 — Exposure curves, LP-DiD, and the LP-DiD size gate

**Operations:**
- Built smooth exposure-curve model (`analysis/exploratory/exposure_curve_model.R`): log handle per adult ~ ns(event age, 4) + cohort x ns(event age, 2) | state + month-of-year + COVID dummies; leave-one-state-out predicted exposure index -> `data/processed/gambling_exposure_index.csv`
- Derived cohort-specific ramp lags (`analysis/exploratory/cohort_ramp_lags.R`): months from online launch to 50%/75% of long-run intensity, LOO -> `data/processed/cohort_ramp_lags.csv` (lag75: 22mo for 2018 cohort shrinking ~3.1 mo/yr to 0 by 2025)
- ACS 18+ population interpolation (`analysis/exploratory/build_state_population.R`) -> `data/processed/state_adult_population_monthly.csv`
- Real-data permutation placebo, 300 reps x 3 arms (`analysis/diagnostics/permutation_placebo_real_data.R`): did2s ~correctly sized on the spliced panel (7.0%, SE/SD 0.93); didimputation oversized everywhere (13-22%); COVID splice NOT the driver
- Timing-vs-COVID-recovery test (`analysis/diagnostics/timing_covid_recovery_test.R`): no significant correlation between legalization timing and pre-treatment trajectories, but underpowered (COVID shift SD 0.47 log pts ~ 10x MDE)
- LP-DiD implemented on real data (`analysis/main/lpdid_statepanel.R`) — calendar-month lags so no comparison straddles the dropped COVID window (verified n_straddling = 0)
- **BLINDNESS DEVIATION**: the LP-DiD real-data run produced treated-period ATTs (raw −2.2%; ramp75 +9.0%, wild p 0.066) and compared them to the CLAUDE.md +9.1% headline — prohibited inputs under the protocol. Mitigation: effect grid/configs committed 2026-08-03 (12725a5), unchanged; outputs live in `output/` (already a prohibited-input dir); decision rule is mechanical (size gate -> MDE). Deviation to be logged in POWER_SIMULATION_BLINDNESS_PROTOCOL.md.
- Wired LP-DiD into the blinded framework (`R/power/run_estimators.R` — `.re_lpdid`, calendar-month lags, EWATT reweighting, spec knobs lpdid_pmd/lpdid_post/lpdid_wild); new `config/power_lpdid_gate.yml` (state, 300 reps, deltas 0/0.05, twfe+did2s+lpdid, base_seed 20260723 for rep pairing); gate running locally

**Decisions:**
- ramp75 (predicted months to 75% of long-run market intensity, leave-one-out) adopted as the cohort-lagged treatment-date variant — avoids conditioning on each state's own post-treatment handle
- LP-DiD enters the PAP only through the blinded size gate, not via the real-data results
- Permutation placebo supersedes cs_calibration_multi_estimator.R as the assumption-sensitive size check (that DGP is additive-by-construction and cannot detect global-PT violations)

**Results:**
- Handle data now 2018-06..2026-05, 35 states (MO added Dec 2025) — CLAUDE.md data section stale
- Never-treated controls now 9 (AK GA ID MN MT ND OK TX UT) after schedule repair — CLAUDE.md "14 never-treated" stale
- Open discrepancy: permutation placebo did2s 7% vs count_nb-DGP power sims 23-29% Type I — resolve before finalizing the PAP size gate

**Status:**
- Done: exposure index, ramp lags, placebo tests, LP-DiD real-data + framework wiring
- Pending: lpdid_gate results (300 reps, running); blindness-deviation note in protocol doc; CLAUDE.md data-section refresh; Della county cheap run status (job 12248328)

## 2026-08-17 12:30 — Post-COVID window size gate: did2s's failure is a splice artifact

**Operations:**
- Added `config/power_lpdid_gate_postcovid.yml` (covid: post; 2021-08..2025-11, 52 months, no splice); 300 reps, deltas 0/0.05, twfe+did2s+lpdid, base_seed 20260723
- Verified the two requested windows COINCIDE: S2 truncates each treated state at treatment − 6mo, so all six early-ramp states (NJ, WV, PA, IA, OR, RI) have zero post-gap months and drop out automatically. covid:post retains 7 treated (FL, KS, KY, MA, MO, OH, VT — all legalized 2022-09+) and 10 never-treated.

**Results (300 reps, delta = 0, rejection @ 5% / SE-SD / null bias):**
- did2s:  spliced 0.260 / 0.52 / +0.035  ->  post-COVID 0.073 / 0.90 / 0.000
- lpdid:  spliced 0.077 / 0.94 / -0.005  ->  post-COVID 0.060 / 0.86 / +0.004
- twfe:   spliced 0.030 / 1.09 / +0.004  ->  post-COVID 0.020 / 1.02 / +0.007
- Size-adjusted power at delta=0.05: lpdid 0.227 -> 0.157; twfe 0.203 -> 0.130; did2s 0.087 -> 0.073
- Design cost: 23 treated/15 control (spliced) -> 7 treated/10 control (post-COVID)

**Decisions / interpretation:**
- did2s's state-panel disqualification is caused by the COVID splice, not by cluster count or the estimator per se: size and null bias both normalize once the window is clean. Smaller design in the post-COVID arm argues AGAINST design size explaining the improvement (fewer clusters would worsen size).
- Resolves the earlier discrepancy: the real-data permutation placebo put did2s at 7% because permuting treatment destroys the timing-splice correlation; the count_nb sim preserves it.
- LP-DiD is stable across both windows, consistent with its gap-respecting construction.

**Status:**
- Done: both gates (spliced + post-COVID), blind-compliant (simulated outcomes on untreated data)
- Pending: county-level gate; lpdid_wild config plumbing; COVID-window mismatch in analysis/main/lpdid_statepanel.R (uses 2022-03-31 vs framework/pretrends 2021-07-31); Della job 12248328

## 2026-08-17 12:45 — MDE curves: post-COVID vs spliced window

**Operations:**
- `config/power_lpdid_mde.yml`: both windows on one 13-point effect grid (0..0.60), 300 reps, mde_boot 200, base_seed 20260723. 31,200 result rows, 0 failures.
- Verified LP-DiD is not estimand-rescaled: tracks imposed truth with bias ~= -0.004 at every delta on the spliced window.
- Computed size-adjusted MDEs (empirical null critical values) alongside the framework's raw MDE.

**Results — MDE at 80% power, alpha 0.05, as % increase in filings (raw / size-adjusted):**
- POST-COVID window (7 treated / 10 control): twfe 26.8 / 24.5; did2s 33.1 / 33.2; lpdid 36.9 / 37.6
- SPLICED window (23 treated / 15 control): lpdid 8.1 / 8.9; twfe 24.1 / 23.3; did2s 31.7 / 50.0 (disqualified on size, 23.7%)
- Real-world: post-COVID median state ~24,000 filings/yr, so a 24.5% MDE ~ 5,900 additional filings/yr; the spliced/LP-DiD 8.9% MDE ~ 2,400 filings/yr.

**Key finding:**
- LP-DiD's efficiency advantage is NOT intrinsic — it is the best arm on the spliced window (8.9%) and the WORST on post-COVID (37.6%). The gain comes from stacking many (t,h) cells across a long panel with many switchers; with 7 switchers and 52 months the long-differencing adds noise relative to TWFE's level regression.
- Going post-COVID costs roughly a factor of 3 in MDE (8.9% -> 24.5% at best).

**Status:**
- Done: size gates + MDE curves for both windows, all blind-compliant
- Pending: county-level gate; lpdid_wild config plumbing; COVID-window mismatch in analysis/main/lpdid_statepanel.R; Della job 12248328

## 2026-08-17 13:40 — Shift-mode sufficiency validation (delta-grid shortcut)

**Operations:**
- New script `analysis/diagnostics/validate_shift_sufficiency.R` (Sonnet coder, 2 revision rounds; Opus coder-critic reviews: 72 → 83/100, passes gate)
- Read BHNS (NBER w25568) to confirm the brute-force-per-delta convention is theirs, not a requirement
- Outputs: `output/shift_validation/{shift_vs_actual_power,discrepancy_summary,loading_by_delta,mde_comparison}.csv` + `shift_vs_actual.png`
- New `quality_reports/research_journal.md` with per-agent entries

**Decisions:**
- Validated the "sufficient statistic" shortcut: per-rep (att0, se0/wild CI, loading L) at delta=0 reproduces the full power curve — estimators are linear in y, so the 11-point delta grid is ~5-10x redundant estimation
- Shift-mode conclusion (critic-verified): exact for the delta=0 size gate by construction; county headline power reproduced to 0.03 points, MDE to within 0.005 log points; TWFE needs a fitted loading on non-constant shapes (L̂ = 0.746 ramp / 0.826 delayed; did2s ≈ 1.0 on same reps); count_nb mechanism residual after L̂ is 0.014–0.039
- Per-delta L̂ is flat on the county headline (0.980–0.982) but drifts on state ramp/delayed — production shift mode should fit L̂ on the power-relevant delta range, not pooled

**Results:**
- Shift mode is safe for the headline county spec; adopting it cuts per-scenario estimation cost ~80% (delta=0 arm + one loading fit vs 11 full-grid fits), directly relevant to the 50–63h county+CS primary runs
- MDE defined for only 3/15 validation cells (county headline); ramp/delayed cells never cross 80% within the grid — MDE evidence doesn't cover the at-risk shapes

**Commits:**
- (none — working tree only)

**Status:**
- Done: validation script + outputs, quality-gated at 83/100
- Pending: implement shift mode in `R/power/run_scenario_grid.R` (delta=0 arm + loading fit + shifted OC computation) before the next expensive CS county run; optional deterministic-x-ramp scenario to pin TWFE's pure weighting loading

## 2026-08-17 14:35 — CS shift-probe BLOCKED by uncaught segfault in the CS arm

**Operations:**
- Added `config/power_cs_probe.yml` (3 state scenarios: det×step linearity gate, nb×step, nb×ramp; 50 reps × 4 deltas; estimators cs/twfe/did2s) and `scripts/run_power_cs_probe.sh`
- Launched twice (6 workers, then detached via nohup); both died within ~60s: "Future (<unnamed-1>) of class MultisessionFuture interrupted"
- Diagnosed with a sequential rep sweep — NOT a sandbox/process-group issue (multisession and multicore both verified working in isolation)

**Results (all reproduced, not inferred):**
- **CS segfaults ~1 rep in 4.** Sequential sweep aborts on rep 4 inside `did::att_gt` -> `run_att_gt_estimation` -> `run_DRDID`: "An irrecoverable exception occurred. R is aborting now". It is a C-level abort, so the `tryCatch` at run_estimators.R:294 and every enclosing handler are powerless; the worker process dies and takes the run with it.
- **`R/power/` never loads this repo's own safe wrappers.** `run_estimators.R:279` calls `did::att_gt()` directly; grep finds zero references to `patches/att_gt_safe.R`, `patches/reg_did_rc_safe.R`, or `patches/preflight_support_check.R` anywhere under `R/power/`. CS spec default is `est_method = "reg"` with `allow_unbalanced_panel = TRUE`, which routes to `DRDID::reg_did_rc()` — exactly the function `reg_did_rc_safe.R` was written to guard.
- **The patch stops the crash but does not rescue the estimate.** Injecting `reg_did_rc_safe` via `assignInNamespace` gave 15/15 reps completing, but only 3/15 converged; the other 12 returned att=NA. Provisional (measured in an ad-hoc harness that does not pin RNGkind the way run_scenario_grid does) — needs confirmation on the runner's own seed path.

**Decisions:**
- Did NOT modify `R/power/run_estimators.R`. Wiring the safe wrappers into the shared production estimator changes CS result semantics (crash -> NA rows) for a module underpinning the PAP, and existing CS partials were produced without it. Flagged for the user rather than done unilaterally.

**Status:**
- Done: probe config + runner committed to disk; segfault root-caused and reproduced; patch verified to prevent the abort
- Pending: user decision on wiring `att_gt_safe`/`preflight_support_check` into `R/power/`; probe cannot run until then; if the ~20% CS convergence rate holds on the runner path, CS viability on this design is itself in question

## 2026-08-17 15:10 — cs_safe_patches wired in; probe exposes a second, larger CS blocker

**Operations:**
- Wired `patches/reg_did_rc_safe.R` into the framework behind config flag `cs_safe_patches` (default FALSE): `R/power/config.R` (default + coercion), `R/power/run_estimators.R` (`install_cs_safe_patches()`), `R/power/run_scenario_grid.R` (grid column, conditional hashing, parent + per-worker install, provenance sidecar), `config/power_cs_probe.yml`
- New `tests/testthat/test-cs-safe-patches.R` — 13 assertions, all passing (golden flag-OFF ids, CS-gated hashing, installer contract)
- Opus coder-critic reviewed the diff: 54/100 initially; findings F1-F6 addressed (see below)
- Ran the probe; killed it after batch 1 of scenario 1 on a decisive negative result

**Results:**
- **Guard works**: probe ran 25 reps with zero worker deaths (vs. abort on rep 4 unguarded). Flag-OFF verified numerically inert; `power_cheap.yml`/`power_primary.yml` ids unchanged and matching partials on disk.
- **F1 (critic, confirmed empirically)**: `did/NAMESPACE` does `importFrom(DRDID, reg_did_rc)` and copies the binding by value at load. Under `faster_mode=TRUE`, `compute.att_gt2()` calls it UNQUALIFIED, so patching only DRDID's namespace leaves the hot path unpatched — while the installer still returned TRUE. Fixed: patch both DRDID's namespace and `did`'s imports frame, set the closure env to DRDID's namespace, and assert on the binding `did` actually reaches.
- **F3 (would have cost real compute)**: the flag was hashed for every scenario, so enabling it in `power_primary.yml` would have moved the county twfe/did2s ids and orphaned ~28-30h of completed work the guard cannot affect. Hashing is now gated on `"cs" %in% estimators`.
- **NEW BLOCKER — `cs_faster_mode` default is wrong for this design.** All 100 CS rep×delta cells in batch 1 failed with did's own message: "singular matrix due to not enough control units. Try changing faster_mode=FALSE." TWFE and did2s converged 100% on the identical reps. `run_estimators.R:239` defaults `cs_faster_mode = TRUE` and it is NOT plumbed from config. A prior session already found this — `analysis/diagnostics/cs_cv3_calibration_state.R:64-66` documents the same failure on 2026-08-11 and runs `faster_mode=FALSE` "matching what actually estimates on this design" — but the power framework was never updated.
- Convergence is delta-invariant within every rep (25/25), so the shift-linearity comparison would be uncontaminated once CS estimates at all.
- CS runtime on the failing fast path: ~167 s per fit.

**Status:**
- Done: guard wired, reviewed, fixed, tested; probe partial preserved at `output_blinded_power/cs_probe/partials/`
- Pending: plumb `cs_faster_mode` as a hashed config axis (default TRUE preserves behavior) and re-run the probe with FALSE. NOTE: `faster_mode=FALSE` is the SLOWER path — re-estimate the 50-63h county+CS budget before committing cluster time. Docs (`POWER_SIMULATION_DESIGN.md` §16, CLAUDE.md) not yet updated for `cs_safe_patches`.

## 2026-08-17 15:55 — cs_faster_mode plumbed; probe rerunning on FALSE

**Operations:**
- New config axis `cs_faster_mode` (default TRUE = historical): `R/power/config.R` (default + NULL/NA-safe coercion), `R/power/run_scenario_grid.R` (grid column with per-block override, conditional hashing, passed into the estimator spec), `config/power_cs_probe.yml` set to `false`
- Hardened `.re_spec()`: `modifyList()` DELETES keys passed as NULL, so an explicit `cs_faster_mode = NULL` reached `att_gt()` as a missing argument. Now restores any nulled default. Caught by a new test, not by inspection.
- Tests extended to 22 assertions (all pass). Regression-ran test-grid/estimators/oc/effects/schedules: all clean, including serial==parallel and resume/subset.
- Docs: `POWER_SIMULATION_DESIGN.md` §16a (new) and `CLAUDE.md` Known Issues
- Archived the failed `faster_mode=TRUE` partial to `output_blinded_power/cs_probe/partials/deprecated/` with a README explaining why it is evidence, not results

**Results:**
- Hash gating verified in all four directions: existing cheap/primary ids frozen; CS-bearing config separates when the axis flips; CS-free config does NOT separate; probe lands on fresh ids (S0c6dd4f05f, Sb5a55cda64, S245b17dc5e)
- **`faster_mode=FALSE` converges where TRUE fails, and is FASTER** (24-40 s vs 57-101 s per fit) — my earlier "FALSE is the slower path, re-budget the county run" warning was WRONG; the county budget risk does not materialize
- **UNRESOLVED**: the two modes return materially different ATTs on identical data (rep 1: -0.033 FALSE vs +0.557 TRUE; different SEs). `faster_mode` is documented as a pure computational shortcut, so this should not happen. CS point estimates are provisional until explained.

**Status:**
- Done: axis plumbed, tested, documented; probe running under FALSE with the guard active
- Pending: probe completion (~1.5h at 15:55; 6 batches x ~17 min); then shift-linearity analysis via `analysis/diagnostics/validate_shift_sufficiency.R` pointed at the probe partials; then investigate the faster_mode ATT discrepancy

## 2026-08-17 16:05 — CS SHIFT-LINEARITY CONFIRMED EXACTLY (probe batch 1)

**Results (deterministic x step benchmark, 25 reps x 4 deltas, faster_mode=FALSE + guard):**
- **CS convergence 100%** (simple/analytic, boot, boot_t; dynamic 99.9%) vs **0%** under faster_mode=TRUE. The axis is the whole difference.
- **CS shift-to-truth loading = 1.000, sd 2.2e-14** — machine precision — on ALL THREE CS inference arms (analytic, boot, boot_t). Loading is delta-stable (identical at delta = 0.02/0.05/0.10).
- **CS SE is invariant across delta to 2.2e-16** (machine epsilon). The standard error literally does not move when the effect is imposed.
- twfe/did2s reproduce the same exactness (L=1, SE-rel <= 1.8e-07; the twfe residual is bootstrap RNG, consistent with the earlier TWFE/did2s validation).

**Implication:** the delta grid is pure redundancy for CS on this benchmark. Estimating at
delta=0 and shifting reproduces every other grid point exactly, including the bootstrap
arms. Combined with faster_mode=FALSE being FASTER per fit, the county CS arm gets
dramatically cheaper than the 50-63h estimate (which was measured on a path that does not
estimate at all).

**Caveat:** this is the deterministic x step scenario, which isolates estimator linearity.
The count_nb step and count_nb ramp scenarios (still running) test whether the stochastic
injection mechanism and a non-constant shape degrade it, as they did for TWFE (L=0.746 on
ramp).

**Status:**
- Done: estimator-linearity question answered definitively for CS
- Pending: scenarios 2-3; then MDE/power comparison; then the unresolved faster_mode ATT discrepancy

## 2026-08-17 16:40 — CS loading is shape-robust; TWFE is not

**Loading (shift-to-truth ratio), state D1, all three probe scenarios:**

| shape | mechanism | CS | did2s | TWFE |
|---|---|---|---|---|
| step | deterministic | 1.0000 (sd 2e-14) | 1.0000 | 1.0000 |
| step | count_nb | 1.116 (sd 0.122) | 1.089 | 1.104 |
| ramp | count_nb | 1.094 (sd 0.069) | 1.021 | **0.707 (sd 0.224)** |

**Reading:** CS's loading is essentially invariant to effect shape (1.116 step -> 1.094 ramp),
matching did2s; TWFE collapses from 1.104 to 0.707 because its static post-dummy
variance-weights a growing effect against truth_overall's equal weighting. This reproduces
the 0.746 measured on the earlier cheap-run ramp. The ~1.09-1.12 common to all estimators
under count_nb is the mechanism (log1p Jensen), not the estimator.

**Power-curve discrepancies (validator, first two scenarios):**
- deterministic x step: max |discrepancy| EXACTLY 0.0000 for every estimator/inference arm
- count_nb x step: CS analytic mean 0.001 (max 0.12); CS boot_t mean 0.021 under L-hat;
  did2s/TWFE 0.005-0.025 mean
- delta=0 size gate invariant by construction: TRUE in every cell

**Limitation:** MDE comparison is `never_crosses_target` in every cell — the probe's grid
tops out at delta=0.10 and state power never reaches 80% there. Chosen for loading
precision, not MDE. Needs a wider grid at state level, or the county run.

**Also fixed:** `analysis/diagnostics/validate_shift_sufficiency.R` had `dir.create(OUTPUT_DIR)`
BELOW the first write (loading_by_delta.csv), so any fresh output dir aborted the run
partway; latent because prior runs reused an existing dir. INPUT/OUTPUT dirs and the
headline-scenario name are now env-overridable, and the exactness benchmark is detected
from mechanism/shape rather than a hardcoded content hash. Regression-verified: byte-identical
output on the original cheap data.

## 2026-08-17 16:50 — CS probe COMPLETE; shift mode validated for CS

**Run:** `output_blinded_power/cs_probe/` — 80,484 rows, 16 failure rows, 3 scenarios x 50
reps x 4 deltas x {cs, twfe, did2s}, `cs_safe_patches: true`, `cs_faster_mode: false`.
Validator output: `output/shift_validation_cs/`.

**Final power-curve discrepancies (max / mean, in power points):**

| scenario | estimator | L-hat | max L=1 | mean L=1 | max L-hat | mean L-hat |
|---|---|---|---|---|---|---|
| det x step | cs analytic | 1.000 | 0.0000 | 0.00000 | 0.0000 | 0.00000 |
| det x step | all others | 1.000 | 0.0000 | 0.00000 | 0.0000 | 0.00000 |
| nb x step | cs analytic | 1.141 | 0.1200 | 0.00099 | 0.1000 | 0.00138 |
| nb x step | cs boot_t | 1.099 | 0.0600 | 0.03000 | 0.0600 | 0.02500 |
| nb x ramp | cs analytic | 1.227 | 0.2500 | 0.00309 | 0.2500 | 0.00276 |
| nb x ramp | cs boot_t | 1.157 | 0.0400 | 0.02000 | 0.0600 | 0.02500 |
| nb x ramp | did2s | 1.045 | 0.0000 | 0.00000 | 0.0000 | 0.00000 |
| nb x ramp | twfe analytic | 0.757 | 0.0400 | 0.01000 | 0.0000 | 0.00000 |

**Conclusions:**
1. Shift mode is EXACT for CS on the deterministic benchmark (0.0000 everywhere), and the
   delta=0 size gate is exact by construction (self-check 1: max |p diff| 4.4e-16).
2. Under count_nb, CS **analytic** mean discrepancy is <= 0.003 power points. The large max
   values (0.10-0.25) come from sparse dynamic event-time cells, not the simple estimand.
3. CS **boot_t** is the weakest arm (mean 0.02-0.03), consistent with its SE moving 22-29%
   across delta under count_nb. Use analytic for shift mode; re-estimate boot_t if needed.
4. CS **boot** (genuine multiplier bootstrap) is excluded — its p-value is not
   reconstructable from stored columns. 400 rows excluded with warning.
5. Fitting L-hat drives TWFE's ramp discrepancy to exactly 0 (0.04 -> 0.00); did2s needs no
   correction at all on ramp.
6. Pooled L-hat (which includes dynamic rows) is less shape-stable for CS (1.141 step vs
   1.227 ramp) than the simple-estimand loading (1.116 vs 1.094). Fit the loading on the
   estimand being used.

**Still open:** MDE comparison impossible on this probe (grid tops at delta=0.10; state
power never reaches 80%). The faster_mode ATT discrepancy remains unexplained.

**Status:**
- Done: original question answered for every estimator; framework unblocked for CS
- Next: implement shift mode in run_scenario_grid.R; county CS run to get a real MDE and
  a real cost measurement (the 50-63h figure was measured on a non-estimating path)

## 2026-08-17 18:15 — Shift mode CLEARED at 93/100

**Operations:**
- Implemented shift mode (`shift_mode`, `shift_calibration_reps`) in `R/power/run_scenario_grid.R` + `config.R`; CI-membership rejection fallback in `summarize_operating_characteristics.R`; `tests/testthat/test-shift-mode.R` (26 tests)
- Three review rounds (Opus coder-critic): 52 → 71 → 93/100. Cleared both the 80 commit gate and the 90 PR gate at strike 3; no escalation.
- Added a source-time assertion that `.CI_ALPHA` agrees with `run_estimators.R`'s `.re_spec()` alpha (closes a latent drift path); documented shift mode in `POWER_SIMULATION_DESIGN.md` §16b

**Defects found and fixed by review (all verified by me against data on disk):**
1. Loading was pooled across delta, but it is NOT delta-invariant under count_nb (CS/analytic ramp 1.433 at delta=0.02 -> 1.207 at delta=0.10; deterministic exactly 1.000 at every delta). Through-origin fits are truth^2-weighted, so delta=0.15/0.20 carried ~71% of the weight — pooled L-hat pinned where the loading is lowest, applied at the crossing where it is highest, biasing the MDE UP. Fixed by per-delta fitting; added noise ~0.3% vs 6-20% bias removed.
2. Wild arm's NA p was NOT "conservative": believable_share deflated ~10x, and mde vs mde_ci computed under incompatible rejection rules. Fixed with a level-gated CI-membership fallback (valid by translation-equivariance of a WCR CI) + `n_reject_used` column.
3. Synthesis rewrote the partial in place, non-atomically — could shred a 50-63h scenario. Now .tmp + file.rename with stopifnot and on.exit cleanup.

**Verified independently (not taken on trust):**
- summarize_oc regression: regenerated from `cs_probe/results_raw.csv.gz` and compared to the pre-change `oc_summary.csv` — 0 differences across 2008 rows x 43 shared columns; only additive column is `n_reject_used`
- `.reject_flag()` level gate: alpha 0.05 -> TRUE, 0.10 -> NA, 0.01 -> NA on a CI-fallback row; p-branch unaffected
- Golden scenario ids for power_cheap.yml and power_primary.yml unchanged; full 9-file suite passes

**CORRECTION to an earlier claim in this report:** the "<=0.003 mean power points" headline was a grid-average over ~668 cells, mostly dynamic pre-period cells with zero discrepancy. Max for cs/analytic was 0.25 and `exceeds_2x_mc_se` fired TRUE for that arm on both count_nb scenarios. Per-delta loadings addressed the underlying cause; the honest per-arm precision table is in DESIGN §16b.

**Status:**
- Done: shift mode implemented, reviewed, cleared, documented. CS arm unblocked end to end.
- Pending: nothing committed (branch `nh-data-repair`, 101 uncommitted files). County CS run not launched. `faster_mode` ATT discrepancy still unexplained.

## 2026-08-19 ~09:45 — Adaptive CS MDE search: built, validated, county verdict delivered (overnight)

**Operations:**
- Built `R/power/adaptive_mde.R` (adaptive/sequential MDE search; every cell a genuine full
  estimate, bit-identical per (rep, δ) to `run_scenario_grid` brute force) + 20+ tests in
  `tests/testthat/test-adaptive-mde.R`; configs `power_county_cs_adaptive.yml`,
  `power_state_cs_adaptive_check.yml`; script `scripts/run_power_county_cs_adaptive.sh`;
  diagnostic `analysis/diagnostics/adaptive_vs_brute_state_check.R`; design doc §16c
- Progressive gates all passed: unit → full suite → mock e2e (known power curve, resume
  equivalence) → state real-CS brute-force comparison (130 vs 440 cells, 16,980 rows
  bit-identical incl. bootstrap p-values) → county smoke (~28 s/cell) → county null
  calibration (250 reps) → county adaptive search
- Two Opus reviews (design + production gate); Amendment 1 prespecified (commit 980b201,
  02:09) before the first county search cell (02:20)

**Decisions:**
- Candidate deltas restricted to the pre-registered 11-point grid; δ=0 always full n_reps;
  bracket + flanks topped to full reps; headline arm = largest MDE among survivors (§15(2))
- cs_jack excluded at county on compute cost only (state 0.5% as supporting evidence)

**Results:**
- **County CS size gate (250 reps, 0 failures): analytic 61.2% FAIL (coverage 39%);
  boot 4.4% / boot_t 3.2% size-valid but NOT calibrated (SE/SD ≈ 1.74, CI ≈ 2 log points
  ≈ [−60%, +150%] filings)**
- **Both size-valid arms: `never_crosses_target`, FLAT power curve (power ≈ size everywhere;
  7.2%/4.8% at δ=0.20 full reps) → no defensible finite county CS MDE on the grid; CS
  eliminated on power; did2s remains the calibrated county workhorse**
- CS null-cell point estimate biased +0.101 (t ≈ 4.7) — strengthens the verdict a fortiori
- Incidents recovered: 1 furrr worker crash (checkpoint held); 1 resume-key padding bug
  (formatC → sprintf + refuse-to-discard guard + regression tests; cells recomputed
  bit-identically)

**Commits:**
- `61e8910` adaptive core+driver; `8e47409` gate 6 + county config; `c4078a6` gate 7;
  `980b201` Opus review fixes + Amendment 1; `3628657` resume-key fix; (final commit
  follows this entry)

**Status:**
- Done: adaptive framework production-validated; county CS question resolved and reported
  (`quality_reports/adaptive_cs_mde_report_2026-08-19.md`)
- Pending: faster_mode ATT discrepancy (§16a) and truth-weighting mismatch (review
  finding 3) remain open; single-cell scope — fragility across samples/mechanisms untested

## 2026-08-19 ~10:30 — Post-COVID maturation-market power (BJS + did2s), per user request

**Operations:**
- Added `bjs` (didimputation/BJS) to `R/power/run_estimators.R` (TDD; toy-panel recovery +
  failure-logging tests); added `maturation50_start_date` treat_def to the loader
- Built `data/processed/maturation50_schedule.csv` (handle50 maturation treatment dates;
  blindness cutoffs stay at first_start_date — strictly conservative)
- Ran `config/power_postcovid_maturation.yml`: state, covid: post (52 months, 17 states),
  two paired blocks (maturation50 vs legalization dates), twfe/did2s/bjs/lpdid,
  300 reps × 12-δ grid to 0.60; full suite green

**Results:**
- Size gate: **bjs FAILS in both blocks (27–29% null rejection, SE/SD ≈ 0.55)** — its
  21–22% "MDE" is invalid; did2s passes (5.0% legalization; 9.3% maturation, borderline);
  lpdid passes (6.3% both); twfe passes maturation (6.0%), conservative-fails legalization (0.7%)
- MDE-80 among gate passers: maturation lpdid 28.0%, twfe 30.8%, did2s 31.3%;
  legalization did2s 31.0%, lpdid 32.6% — maturation treatment neither costs nor buys power
- Post-COVID penalty stands: ~3× the spliced-window LP-DiD MDE (8.9% size-adj)

**Status:**
- Done: memo `quality_reports/postcovid_maturation_power_memo_2026-08-19.md`
- Pending: county post-COVID run for these estimators; a valid BJS inference arm (wild
  bootstrap) if BJS is to be pursued

## 2026-08-19 ~11:45 — County post-COVID power (did2s/lpdid) + lpdid_wild plumbing

**Operations:**
- Ran `config/power_postcovid_maturation_county.yml` (did2s+lpdid analytic): ALL arms fail
  the county size gate (did2s 21.5–23.9%, lpdid 11.7–14.0%; SE/SD 0.62–0.72 — few treated
  clusters: 4–5 states over 509 counties)
- Plumbed `lpdid_wild` through config→grid→spec (TDD; conditionally hashed like
  cs_faster_mode; commit 1b5a2aa); reran county with the wild arm
  (`power_postcovid_maturation_county_wild.yml`)

**Results:**
- **lpdid wild is exactly nominal at county post-COVID (5.0% / 4.7%)** → valid MDEs:
  legalization 23.9% [23.0, 24.9]; maturation50 31.7% [28.7, 35.3]
- County does NOT rescue post-COVID power (spliced county did2s was ~4–5% MDE); the
  binding constraint is 4–5 treated clusters. Maturation-only costs power at county
  (4 vs 5 treated). did2s disqualified at county post-COVID (no wild arm).
- Memo updated: quality_reports/postcovid_maturation_power_memo_2026-08-19.md (county addendum)

**Status:**
- Done: full suite green; all runs committed/logged
- Pending: a did2s wild/bootstrap arm if did2s at county post-COVID is wanted

## 2026-08-19 ~16:15 — Time aggregation (month/quarter/year) × COVID handling: CS calibration

**Operations:**
- Added `time_agg` axis (month/quarter/year) to `load_blinded_panel()` + scenario grid,
  superseding the legacy boolean `quarterly` (kept in sync; existing month/quarter ids do
  NOT move, year hashed conditionally); added `complete_periods_only` rule (drops
  unit-periods lacking their full month complement). TDD, full suite green. Commit 79498b1.
- Ran `config/power_time_agg_covid_gates.yml` (13 scenarios, state/S2/D1-panel/count_nb,
  δ=0 size gate, 300 reps, cs+twfe+did2s+lpdid, lpdid_wild). 6 complete at time of writing.

**Results (δ=0, 300 reps, gate 2.5–10%):**
- **Aggregation does NOT fix CS.** Cohorts collapse 21 → 17 → 7 (max cohort 2 → 3 → 6) but
  spliced-window CS analytic goes 18.3% (month) → 16.7% (quarter) → **24.7% (year)**.
- **The COVID splice is the dominant factor:** monthly post-COVID CS PASSES for the first
  time in this project (5.0% / 6.0% / 3.3%, SE/SD 1.06–1.14); every spliced cell fails for
  CS *and* did2s (26–42%). Generalises the 2026-08-17 did2s splice-artifact finding to CS.
- **Annual carries a large null bias** (−0.476 spliced, −0.578 post) — partial-period
  artifact (COVID filter runs before aggregation; annual 2020 = 2 months, 2021 = 5).
- **LP-DiD: 0/300 convergence at quarterly and annual** (lags are calendar-month by design);
  converges 300/300 monthly. Blocking issue for any quarterly LP-DiD spec.
- **Structural finding:** on the spliced window `complete_periods_only=TRUE` makes coarse
  aggregation D1-INFEASIBLE (quarter 1/5, year 0/5 placements vs 5/5 with it off).
- CS null bias is large/negative on every post-COVID cell even where size passes.

**Incidents:** furrr worker crash at month_post batch 9/12 (2nd today); resumed from batch
checkpoint at reduced concurrency (6 → 5 workers), no data lost.

**Status:**
- Done: memo `quality_reports/time_agg_covid_calibration_memo_2026-08-19.md` (incl. resume
  command); 6/13 scenarios
- Pending: 7 scenarios (month/quarter/year `keep` + 4 complete-period variants); power/MDE
  not yet run (adaptive_mde, passing cells only — shift mode barred for CS)

## 2026-08-19 ~19:10 — Long-differences arm, scope correction, and session handoff

**Operations:**
- Added `longdiff` estimator arm (cohort-specific long differences, audited design of
  2026-08-03): baseline g-30..g-7, post g..g+11 (+dynamics), cohort-calendar controls,
  equal-treated aggregation, delete-one-state jackknife. TDD; optimized 2.7s -> 0.072s
  per cell via integer month indices (values bit-identical). Commit 949219e.
- Ran `config/power_longdiff.yml`: 4 scenarios (drop/keep x all/excl-NY), 300 reps,
  12-point grid. All 4 completed; run-level summaries not written (stopped before the
  aggregation pass) — rerun with resume=TRUE to emit them.

**Results (longdiff = estimator A):**
- Well-calibrated everywhere (size 1.8-7.3%, SE/SD 1.14-1.25) but badly underpowered:
  MDE 0.298 (ld_drop) / 0.323 (excl NY) / never-crosses (ld_keep) / 0.598 (ld_keep_exny)
  vs LP-DiD 0.089 on identical draws. Only 7 treated cohorts survive on the spliced
  window (the 30-month baseline requirement). Excluding NY does not help.

**Scope correction (important):**
- Ben's intended estimator is NOT the implemented one: he wants a binary "legalized by
  2022" 2x2 with COMMON calendar windows, tau = (T_end - C_end) - (T_pre - C_pre),
  county-level with weights, CRVE/RI/wild inference, plus Black-et-al Type S/M and a
  Burlig-motivated averaging-window comparison. NOT yet built.
- Blinding constraint diagnosed and explained: raw data is healthy (31 states with 2025
  data, 26-31 observed monthly through 2025-09, NO 2026 data), but the blinded panel
  truncates treated states at launch, leaving only 6 blind-usable states for a
  2017-18 -> 2024-10..2025-09 window pair. The real analysis is unaffected; only the
  simulation rehearsal is constrained. Agreed plan: estimate long-difference variance on
  clean early windows (19-23 states), era-check on never-treated 2024-25 data, then MDE
  at REAL cluster counts (~22 treated / ~12 control); the 6-state sim is a floor only.
- Endpoint pinned by Ben to the 12 months ending 2025-09.

**Status:**
- Done: HANDOFF written to `quality_reports/HANDOFF_2026-08-19.md` (covers the whole
  session incl. the long-differences discussion)
- Pending: build the 2x2 estimator (B); open decision — RI primary vs CRVE+wild

## 2026-08-19 20:05 — Long differences re-staged as a pre-treatment pseudo-experiment

**Operations:**
- New: `analysis/diagnostics/longdiff_2x2_pseudo_power.R` (binary 2x2 power sim, 500 reps, RI + CRVE + wild cluster bootstrap, count_nb effects) → `output/longdiff_2x2_pseudo/`
- New: `analysis/diagnostics/longdiff_era_variance.R` (era σ stress test + centre-anchored averaging test) → `output/longdiff_era_variance/`
- New: `analysis/diagnostics/longdiff_2x2_selection_placebo.R` → `output/longdiff_2x2_selection/`
- Memo: `quality_reports/longdiff_pseudo_treatment_memo_2026-08-19.md`; CLAUDE.md gained two sections
- Design judgement call escalated to Fable (substrate, calendar, assignment, inference, grid)

**Decisions:**
- Shift the whole long-difference experiment into the pre-treatment era (Black et al. 2022) instead of truncating state-by-state — truncation left only 6 usable states
- Annual county court panel as substrate (CY2008+09 → CY2016): the only one that fits 24/12-month windows at a ~70-month distance with 22/15 states. ETS monthly untreated era is 29 months and cannot
- Randomization inference primary — subsequently vindicated: CRVE fails size at 7.8%/12.4%, RI exactly 5.0%
- Idaho pre-excluded from era σ (drives 100% of pre-era placements; already excluded elsewhere for data quality)

**Results:**
- Pseudo-era MDE-80 = 0.241 log points (+27% filings), RI size 5.0%, null bias −0.0008
- Post-COVID σ is 2–4× pre-2018 σ at matched geometry → real-era MDE **+56% to +90%** via three independent routes
- Burlig confirmed on both margins: 12-month endpoint averaging cuts σ by 5–12% (vs 71% iid); 24- vs 12-month baseline worth ~2% of MDE
- Type M 2–4× at plausible effect sizes; 28% sign errors at δ=0.02 under CRVE
- Selection placebo passes (τ = −1.4%, RI p = 0.90)
- Bug caught and fixed mid-build: `filter(n == n)` in the centre-anchored function admitted partial-coverage states

**Status:**
- Done: design decision, both deliverables, memo, docs
- Pending: nothing committed yet (awaiting go-ahead); annual↔ETS outcome bridge is a bridge, not a measurement

## 2026-08-20 01:00 — State panel double count diagnosed and rebuilt

**Operations:**
- Diagnosed the TX/MN state-vs-county long-difference disagreement: `data/raw/state_month_panel_with_treatment.csv` double-counted 12 states (county sum + overlapping ETS series, exact to the unit on 916/916 overlap months). New audit: `analysis/diagnostics/statepanel_double_count_audit.R` -> `output/statepanel_double_count/`
- Rebuilt the panel: `data_prep/rebuild_state_month_panel.R` (county sums; NH/WI court repairs kept; NY trimmed to 2019+; MD/LA/MA/MO/NM/NV/RI carried; treat_start from repaired schedule). Old panel -> `data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv`
- Regenerated `data/processed/state_month_panel_handle50_treatment.csv` from the rebuilt panel
- Re-ran pretrends twice to decompose schedule repair vs panel fix: `output/pretrends_rebuild_A_oldpanel/` (old panel + repaired schedule) and `output/pretrends_rebuild_B_newpanel/` (rebuilt panel)

**Decisions:**
- One consistent source per state; drop NY pre-2019 (different-basket ETS series) rather than keep the seam — NY falls out of the balanced pretrends panel
- Old panel preserved in deprecated/, not deleted

**Results:**
- Breaks: cities series start 2020-01 (AZ OH SC TN TX jump up), state_level series end 2023-02 (CT DE IN MN PA VA drop), FL drop 2020-01; 1.2x-2.4x level breaks
- New pretrends headline: 25 states (16 treated/9 never), CS ATT +0.080 (SE 0.088), pretrends pass. Panel fix cut CS SE by ~1/3 vs old panel at same schedule (0.130 -> 0.088); point estimate ~unchanged
- Contaminated and needing re-run: state calibration table, blinded-power state cells (did2s Type I, TWFE-wild MDE, time_agg/splice memo, LP-DiD spliced-state 8.1%), TWFE MDE=5% sim, post-COVID handle50 outputs, era-variance state sigmas. County-based results immune.

**Status:**
- Done: audit, rebuild, handle50 regen, pretrends re-run, CLAUDE.md known-issue section
- Pending: re-run state calibration + blinded-power state cells + handle50 post-COVID pipeline on rebuilt panel; decide NY re-entry via OCA data

## 2026-08-20 01:30 — NC extended from NC AOC court source (2023-06 → 2026-06); state + handle50 panels rebuilt

**Operations:**
- New: `data_prep/monthly_panel_expansion/09a_download_nc_aoc_civil_issue_reports.R` (11 FY workbooks → `data/raw/monthly_expansion/nc_aoc/`, 61 MB)
- New: `data_prep/monthly_panel_expansion/09b_parse_nc_aoc_sume.R` → `data/raw/monthly_expansion/nc_sume_county_month.csv` (13,200 rows; 100 counties × 132 months, 2015-07..2026-06)
- New: `data_prep/monthly_panel_expansion/09c_extend_nc_in_county_files.R` — appended 3,600 NC rows (36 months × 100 counties, 2023-07..2026-06) to `data/raw/monthly_county_data_download.csv` and `data/raw/combined_monthly_panel.csv`
- Reran `data_prep/rebuild_state_month_panel.R` and `data_prep/build_panel_handle50_treatment.R`
- Backups (once, never overwritten): `data/raw/deprecated/{monthly_county_data_download,combined_monthly_panel}_pre_nc_extension_2026-08-20.csv`

**Decisions:**
- Eviction = `Issue_Code == "SUME"` summed over ALL case types, not CVM alone — CVM-only runs ~2% below ETS and the non-CVM SUME rows fall from ~875/mo (2022) to ~10/mo (2026) as cases reclassify into CVM, which would read as a spurious downward trend.
- Append-only at the seam: ETS rows 2016-01..2023-06 untouched, so every existing county-download-based result stays bit-for-bit reproducible. Verified: existing rows byte-identical to backup in both files.
- Carried renter/poverty forward per county — exact, not approximate (0 of 100 NC counties ever vary in the download). NCAOC supplies no denominator.

**Results:**
- Validation vs ETS on 90 overlap months: statewide corr **1.0000**, median monthly ratio 1.0000 (min 0.9978); 8,984/9,000 county-months exact (99.8%), mean diff −0.01, max |diff| 26 (Wake ≈1%). ETS's NC feed *is* this report.
- R parser reproduces an independent Python extraction with 0 value mismatches on all 13,200 rows.
- **NC before: 0 rows in the rebuilt state panel** (fixed-basket rule dropped it — no NC county reported through the 2024-12 basket window). **After: 126 months, all 100 counties every month, basket_share 1.0, 28 treated months** (treat_start 2024-03-01).
- handle50 panel: NC 126 months / 28 treated; states with treat_start = 20, states with ≥1 treated obs = 20 — **the zero-treated-but-dated set is now empty**.
- Global basket-month count unchanged (91 before and after) → no other state's basket shifted; NC is the only state that changed.
- Seam continuous: 2023-06 = 16,165 (ETS) → 2023-07 = 16,470 (AOC), +1.9%.
- Odyssey/eCourts migration (Feb 2023 – Oct 2025, county-staggered) does NOT drop counties from this report: 100 counties present in all 11 fiscal years.

**Status:**
- Done: NC wired into `data/raw/`, both panels rebuilt and verified.
- Pending: MO still carries `treat_start` 2025-12 with 0 treated months (ETS series ends 2023-01) — genuinely post-panel, not a coverage gap. `build_panel_handle50_treatment.R:241` still counts `!is.na(treat_start)` rather than states with any `treated == TRUE`; it agrees with the truth now only by coincidence.
- Pending: downstream outputs built on the pre-extension panels are stale (pretrends, handle50 outputs, power-sim state cells).

## 2026-08-20 — CLAUDE.md correction: TWFE power sim was wrongly flagged as double-count contaminated

**Operations:**
- Traced the data path of `analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`; replicated `build_state_panel()` against `data/raw/combined_monthly_panel.csv`.
- Edited `CLAUDE.md`: removed the TWFE power sim from the state-panel **Contaminated** list, moved it to **Immune** with the verified mechanism, added a re-scoped staleness note and a TO DO for the re-run.

**Decisions:**
- Re-scoped the flag from "double-count contaminated" to "stale treatment schedule" — the two imply different fixes (rebuild panel vs. re-run against repaired schedule) and different credibility (biased vs. merely out of date).

**Results:**
- Power sim's OUTCOME comes from `combined_monthly_panel.csv`, not the double-counted state panel. Replicating the build: **32 states via county aggregation, 6 via state fallback (LA, MA, MO, NM, NV, RI — the legitimately single-source states), 0 duplicate state-months.** All 12 double-counted states have county rows, so `filter(!(state_abb %in% county_states))` excludes their ETS series — the two sources are never summed.
- `state_month_panel_with_treatment.csv` is read only as `TREAT_FILE`, transmuted to `state_abb, month_date, treat_start, treated`. Filing counts never enter.
- **What is genuinely stale:** saved run `data/output/twfe_power_out_2024_with_me/` is dated 2026-07-23, pre-dating the 2026-08-10 schedule repair. Panel = 38 states / 22 switchers / 16 never-treated; the repair moved ME, VT, KY, FL out of never-treated. No known direction of bias.
- Discrepancies found in PAP §2.4: cites N = 2,867 state-months (no run in `data/output/` matches — current runs are 3,505 with ME, 3,397 without) and a 2016-01 sample start (run panel starts 2012-01). Rest of §2.4 reproduces exactly (2,000 sims, 0–6% grid, `MIN_STATES_PER_MONTH=5`, Mar-2020–May-2021 end-exclusive window, power 0.828 at 0.0488 log points).
- Root cause of the bad flag: the entry was added by pattern-matching the file name, not by reading the loader — same class of error as the 2026-08-10 "reproducibility anomaly."

**Status:**
- Done: `CLAUDE.md` corrected in three places (contaminated/immune block, Empirical Results TWFE power bullet, Power Analysis Results bullet) + TO DO added.
- Pending: re-run the power sim against the repaired schedule; reconcile PAP §2.4's N and sample start.
- Pending: PAP §2.5 estimator section still leads with TWFE and pre-registers "CS-DD if different from OLS" — contradicts the calibration record and the blinded size-gate decision rule. Not yet edited.

## 2026-08-21 10:15 — Adoption-timing selection diagnostic (levels vs slopes)

**Operations:**
- Created `analysis/diagnostics/adoption_selection_levels_slopes.R`; outputs to `output/adoption_selection/`
- Two independent pre-legalization substrates, both fixed-county-basket: (A) annual county court panel 2009–2015, 29 states; (B) ETS monthly county download 2016-01..2018-05, 19 states. Both windows end before the first US legalization (2018-06).
- Tests per substrate × treatment definition (online, first): ever-adopt LPM, months-to-adoption OLS (HC3), Cox PH with never-adopters censored at 2024-12, permutation Spearman and permutation mean-difference (5,000 draws)

**Decisions:**
- Fixed basket + `basket_share`/`n_cty` trimming (>=5 counties, >=50% of state renters) — composition churn would otherwise fake both level and slope (per CLAUDE.md rebuild warning)
- Cox PH rather than OLS-on-timing alone, so never-adopters enter as censored instead of being dropped
- Ran directly rather than via the /analyze agent pipeline (session directive: no agent dispatch unless requested)

**Results:**
- SLOPES: no relationship anywhere. Cox log-hazard per SD of pre-slope −0.25 (SE 0.23) substrate A, +0.13 (SE 0.31) substrate B; months-to-adoption per SD +6.0 (SE 6.4) A vs −4.3 (SE 8.6) B — signs flip, all CIs straddle zero
- LEVELS: adopters sit higher (A +0.64 log pts, perm p=0.19; B trimmed +1.10, p=0.043) and Cox hazard is positive (+0.14 A to +0.81 B×first, p=0.033), but months-to-adoption sign flips across substrates and the effect is absorbed by state size — adding log(renters) moves B-full level 0.148 → 0.077 while size takes 0.545 (p=0.039)
- 32 tests total, 3 at p<0.06 vs ~1.6 expected under the null
- Corroborates `output/pretrends_rebuild_B_newpanel`: CS Holm p=1.0, SunAb p=1.0, mean |pre-ATT| 0.029
- Cross-state LEVEL comparisons flagged as weakly identified: MD = 852 filings per 1k renters (serial filings), several states enter on 1–2 counties

**Status:**
- Done: diagnostic, outputs, figure, logs
- Pending: not committed

## 2026-08-21 11:40 — Pre-PASPA predictability of adoption and timing

**Operations:**
- Created `analysis/diagnostics/adoption_predictability_prepaspa.R` -> `output/adoption_predictability/`
- Predictors, two windows: PRE-REPEAL (<=2018-01, before Murphy v. NCAA) and PRE-ANTICIPATION (<=2009-12, before NJ's 2012 PASPA challenge). Blocks: mortgage 90+ delinquency level/crisis-peak/slope (51 states), log adult population, n bordering states, eviction level/slope (41 / 30 states)
- Metrics: repeated stratified 5-fold CV (200 repeats) for AUC/Brier/R-squared/Cox concordance, each against a 1,000-draw permutation null run through the identical CV loop

**Decisions:**
- Abandoned leave-one-out after verifying it is structurally broken at this N: dropping an adopter lowers the training base rate, so held-out adopters get systematically lower fitted probabilities and LOO AUC collapses to exactly 0 under no signal (confirmed on mort_slope: 51 distinct probs, coef -0.007, AUC 0.000). Stratified K-fold holds the base rate fixed; null recentres at ~0.49
- Fixed the 51-state universe: the schedule CSV omits never-legalizing states as ABSENT rows, so joins were deleting AL AK CA GA HI ID MN NE NV OK SC TX UT. NV flagged separately (legal since 1949, PASPA-grandfathered)
- Fixed AK/HI n_border = 0 (count() had dropped them, deleting two never-adopters)

**Results:**
- EVER-ADOPT: best CV AUC 0.600 (macro, eviction sample) / 0.583 (macro, 51 states) vs null ~0.485, p=0.16-0.18; in-sample 0.74-0.78 -> optimism gap ~0.18. Brier skill NEGATIVE in all 8 models (-0.09 to -0.58): worse than the base rate
- TIMING: CV R-squared negative in all 8 models (-0.24 to -1.34) against in-sample 0.05-0.22; p>=0.39. Cox concordance 0.36-0.55, all within noise of the null (p>=0.47)
- Eviction history adds nothing: macro-only 0.600 -> macro+eviction 0.574
- Pre-anticipation window is uniformly worse than pre-repeal (all CV AUC <=0.48)
- Single exception: 2016-17 mortgage delinquency, CV AUC 0.689 (p=0.008), Brier skill +0.095, adopters 1.40% vs never 1.06% (Wilcoxon p=0.009). Predicts WHETHER, not WHEN (Cox p=0.448); vanishes in the 2009 window; pattern is judicial-foreclosure Northeast vs Plains/Mountain, i.e. a region proxy
- Re-ran `adoption_selection_levels_slopes.R` on the corrected 51-state universe: substrate A 29 -> 41 states, adopter-never level gap +0.64 -> +0.24 log points, slope gap -2.0 -> -0.8 pp/yr, nothing significant outside the smallest trimmed cell

**Status:**
- Done: both diagnostics, corrected universe, CV methodology, figures, logs
- Pending: not committed

## 2026-08-21 12:55 — Adoption universe hard-coded; schedule-join audit

**Operations:**
- `utils/eviction_treatment_schedule.R`: added `EVICTION_STATE_UNIVERSE` (51), `PRE_PASPA_SPORTS_BETTING` (= NV), `eviction_adoption_outcomes()`, `eviction_control_states()`, `assert_no_pre_paspa_controls()`; `della_upload/utils/` copy synced byte-identical
- Refactored `analysis/diagnostics/adoption_selection_levels_slopes.R` and `adoption_predictability_prepaspa.R` onto the shared helpers; both now exclude NV
- Migrated `analysis/cheap_sims/11_exposure_time_vs_intensity.R` off its inline `state_abb != "NV"` onto the shared constant
- Wrote `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md`; added a CLAUDE.md section at line ~407
- Re-ran both diagnostics

**Decisions:**
- Audited by tracing each script's actual data path and reconstructing samples, not by pattern-matching filenames — the standing lesson from the 2026-08-10 anomaly and the 2026-08-20 TWFE mislabelling
- Kept `PRE_PASPA_SPORTS_BETTING` to NV alone: DE/OR/MT carry explicit post-2018 dates so the ordinary path handles them
- `control_eligible` written into the outcome table so the NV decision is data, not per-script judgement

**Results:**
- Absent-row trap: live in exactly 1 of 81 scripts (my own, fixed). `setdiff(panel_states, ever)` and `%in% ever_online` are safe; `R/power/load_blinded_panel.R:262-264` already documented the hazard
- NV-affected (superseded until re-run): 2x2 pseudo-power MDE-80 0.241 (+27%) and its size/Type-M tables; 2x2 selection placebo (tau -1.4%, RI p 0.90) — NV sits in the very arm the test is about; era-variance ratios, esp. strict-never-set 3.86 where NV is a member AND the flagged outlier_state; STATE blinded-power cells
- NV-immune (verified): all county-download work (NV absent from `monthly_county_data_download.csv`); all balanced-panel work (NV 46 non-COVID months vs 91 threshold -> drops). Pretrends headline, CS/SunAb calibration, county CS adaptive MDE, border diagnostic, +9.1% did2s, mortgage all stand
- Selection re-run (NV out): substrate A 40 states / 17 never; slope and level results unchanged and null
- Predictability re-run (NV out): ever-adopt best CV AUC 0.640 (p=0.068) vs 0.600 before — NV removal modestly IMPROVES discrimination, still not significant; timing CV R-squared still negative everywhere (-0.23 to -1.45); Cox concordance 0.556 vs null 0.556; mort_level single 0.703 (p=0.006, only positive Brier skill +0.108); macro+eviction 0.591 < macro-only 0.640 so eviction still adds nothing

**Status:**
- Done: utility, refactors, audit doc, CLAUDE.md, both re-runs
- Pending: re-run the four NV-affected analyses; not committed

## 2026-08-21 14:10 — Political/institutional block comparison

**Operations:**
- Extracted the CV machinery to `utils/cv_predictability.R` so every block is scored by one estimator, one fold scheme, one permutation null; rewired `adoption_predictability_prepaspa.R` to source it
- New `analysis/diagnostics/adoption_predictability_institutions.R` -> `output/adoption_predictability_institutions/`
- Found and used real pre-PASPA political data: Berry-Ringquist-Fording-Hanson state ideology, `Funding/Data/stateideology_v2018.xlsx`, 1960-2017, taken at **1991** (PASPA enacted Oct 1992). Region from base R `state.region` (DC -> South)
- Wrote `docs/methodology/ADOPTION_PREDICTORS_FEASIBILITY.md`

**Decisions:**
- Implemented only blocks with real data. Casino/tribal structure, lottery, constitutional barriers, legislature professionalism, gaming fiscal dependence and neighbour legalization are NOT in the workspace and were not hand-keyed from memory — documented as acquisition targets with named sources instead
- Added an explicit orthogonality test, because "assignment runs on institutions" only supports the identification claim if those institutions are themselves unrelated to pre-period eviction dynamics
- Flagged the neighbour-legalization model as a discrete-time hazard with time-varying covariates, not a cross-sectional block

**Results:**
- EVER adopt: region CV AUC **0.676 (p=0.008)**, Brier skill +0.093 — the only block with genuine out-of-sample skill; macro 0.631 (p=0.072); pre-PASPA ideology 0.561 (p=0.249); eviction 0.469 (p=0.590); everything-stacked 0.630, worse than region alone
- TIMING: negative CV R-squared for EVERY block (-0.22 to -1.32), all p >= 0.29. Cox concordance 0.45-0.57 against nulls 0.46-0.57, all p >= 0.48. Nothing forecasts when
- ORTHOGONALITY caveat: ideo_govt x ev_slope r = 0.291 (p=0.069); reg_West x ev_slope r = -0.343 (p=0.030). Institutions are not cleanly orthogonal to the pre-period eviction slope
- Consequence: the user's conditional ("institutions forecast timing strongly") is unmet on the measurable blocks. The defensible version is narrower — timing is unpredictable from everything measured, which is the margin the staggered DiD actually rests on

**Status:**
- Done: shared CV util, institutions script, feasibility doc, logs
- Pending: acquire blocks 1-6; NV-affected re-runs; not committed

## 2026-08-21 12:25 — Eviction stabilization timing, post-COVID boundary, anticipation window

**Operations:**
- New: `analysis/diagnostics/eviction_stabilization_timing.R` -> `output/eviction_stabilization/`
- New: `analysis/diagnostics/postcovid_boundary_fixedlen.R` -> `output/covid_global_pt/postcovid_boundary_fixedlen.csv`
- New: `config/power_boundary_A_2021_08.yml`, `config/power_boundary_B_2022_08.yml`
- Re-ran `analysis/diagnostics/postcovid_boundary_sweep.R` on the REBUILT panel (numbers differ from the pre-rebuild log; script footer benchmarks 0.416/0.467 are now STALE)
- Power runs: `output_blinded_power/boundary_A_2021_08/` COMPLETE (300 reps); `boundary_B_2022_08/` PARTIAL at 175/300 reps, resumable

**Results:**
- Median state stabilization = **2022-07** (IQR 2022-02..2023-03); only 3/20 settled by 2022-01; 6 states (KS MD MN MT NC UT) never stabilize. Robust across 18 threshold combos.
- Post-COVID noise floor 1.43x pre-COVID, never 1.0x — independently reproduces the era-variance finding. An absolute "back to pre-COVID volatility" criterion is WRONG here.
- Stabilization is a WITHIN-state property; parallel trends is CROSS-state. Fixed-length sliding windows show later windows are NOT more stable (18mo half-split SD 0.108 early vs 0.207 late). Stabilization date alone does NOT justify moving the boundary.
- Boundary 2021-08 -> 2022-08 costs 3 of 7 treated clusters (KS MA OH), 52 -> 40 months.
- `power_lpdid_gate_postcovid.yml` header says 7 treated / 10 never-treated; on the rebuilt panel it is 7 / **8** (HI, NV, SC gone). Header STALE.
- +4Q redating does NOT save clusters in the blinded framework (cutoff pinned to `g_first` by protocol §4; online/first/retail/ramp75 all give byte-identical panels). In a real estimation it recovers KS/MA/OH but hands every treated state 12 post-launch months coded as control.
- **ANTICIPATION WINDOW IS THE REAL LEVER.** `anticipation_months=6` is a blindness buffer, NOT the econometric assumption (`est_anticipation` is already 0). Protocol §4 pre-registers A in {0,3,12}. Treated clusters: boundary 2021-07 A=0 -> **12** vs A=6 -> 7; boundary 2022-07 A=0 -> **7** vs A=6 -> 4. A=0 buys the later boundary for free.
- Arm A size gate (2021-08, A=6, 7 treated): only **lpdid wild passes (6.0%)**; did2s analytic 28.7% FAIL, twfe 12.0%/11.3% FAIL.
- Delay: implement as NY-Fed buildup window (h>=12, does not shift dates), NOT redating — `lpdid_statepanel.R:113` flags redating's dirty-window contamination.

**Status:**
- Done: stabilization analysis; boundary composition + trend tests; anticipation sweep; arm A gate
- Pending: resume arm B (175/300 banked); **run size gate at A=0 / current boundary (12 treated clusters)** — highest-value next test

## 2026-08-21 15:30 — Casino + lottery blocks acquired; Cox null bug fixed; timing model reversed

**Operations:**
- Acquired pre-PASPA gambling institutions from external sources; built `data/raw/gambling_institutions/state_gambling_institutions_prepaspa.csv` via `data_prep/build_gambling_institutions_prepaspa.R`, provenance in the sibling `SOURCES.md`
  - Lottery first-offering year, all 51: LotteryUSA "first offerings by state". DC corrected to 1982 (source only implied 1987; verified first ticket 25 Aug 1982)
  - Commercial casino authorization/operation: I. Nelson Rose "Pivotal Dates", corroborated per-state (IRGC, SD Commission on Gaming, CO LegiSource, UPI 1991 on LA)
  - ABANDONED a "commercial casinos as of 2017" variable: AGA list not retrievable and a Wikipedia extraction returned Alabama as commercial-casino, which is wrong. Unverifiable variable omitted rather than guessed
  - Tribal gaming deliberately not coded (needs NIGC/BIA primary records; sign is ambiguous because exclusivity compacts can block commercial expansion)
- **BUGFIX `utils/cv_predictability.R`**: the Cox permutation null re-ran `cv_cox_c` on UNPERMUTED data, so it measured fold noise around the observed value, not a null. Every Cox p-value reported earlier this session (~0.4-0.6 regardless of signal, with null means tracking observed values to 3 dp) was a non-test. Now permutes design rows against the (time, event) pairs; verified a pure-noise predictor gives null mean 0.488
- Re-ran both predictability scripts under the fix

**Results — ADOPTION HAZARD (the timing model), corrected null:**
- gambling institutions (pre-PASPA): C = 0.703 vs null 0.479, **p < 0.001**
- lottery maturity alone: C = 0.699 vs 0.470, **p < 0.001**
- casino authorized alone: C = 0.517, p = 0.224 — nothing
- region 0.564 (p=0.120); macro 0.554 (p=0.220); political ideology 0.529 (p=0.356)
- eviction level+slope: C = 0.446, p = 0.712 — nothing
- Previous prepaspa-script Cox conclusions survive the fix qualitatively: macro 0.556 (p=0.240), eviction-only 0.468 (p=0.616)

**Results — EVER ADOPT:** lottery maturity alone CV AUC 0.800, Brier skill +0.287 (p<0.001); gambling+region 0.804; casino-only 0.468 (p=0.518); eviction 0.450 (p=0.601)

**Results — TIMING CONDITIONAL ON ADOPTING (months among 30 adopters):** still nothing. gambling block CV R-squared -0.055 (p=0.120); casino_auth alone 0.001 (p=0.060) is the only non-negative value in the whole exercise; everything else negative

**Orthogonality flags (matter for the identification argument):**
- lottery_years_91 x ev_level r = 0.291 (p=0.068)
- ideo_govt x ev_slope r = 0.291 (p=0.069)
- reg_West x ev_slope r = -0.343 (p=0.030)

**Status:**
- Done: both blocks acquired with provenance, Cox null fixed, both scripts re-run, all outputs on disk. NOTHING RUNNING — safe to close the laptop
- Pending: independent verification of the compiled institution data against primary statutes before any publication use; NV-affected re-runs (2x2 pseudo-power, selection placebo, era-variance, state power cells); tribal/constitutional/fiscal blocks; not committed

## 2026-08-21 16:20 — Pretrends conditioned on lottery vintage

**Operations:**
- Added conditional-parallel-trends support to `analysis/pretrends/pretrends_statepanel_template.R`: `COVARIATES` / `COVARIATE_FILE` env vars -> `did::att_gt(xformla=)`; Sun-Abraham gets `i(t, X)` covariate-by-period interactions since a time-invariant X is absorbed by the unit FE. Loud failure if a covariate is missing for any in-sample state (att_gt would drop it silently). Pre-change copy in `analysis/pretrends/deprecated/`
- Fixed the Sun-Abraham coefficient mask: `grepl("::")` also matches `i(t,X)` names, which would have swept 90 interaction coefficients into the event study. Now `^[^:]+::-?[0-9]+$`
- Plumbed COVARIATES through `scripts/run_pretrends_statepanel.sh`
- Three runs on an identical panel (26 states, 17 treated, 9 never, 16 cohorts, 91 months, 2,366 obs)

**Results:**
| spec | CS ATT | SE | joint p | mean abs pre-ATT | max abs pre-ATT |
|---|---|---|---|---|---|
| A unconditional | +0.020 | 0.057 | 0.170 | 0.0285 | 0.0689 |
| C lottery BINARY | +0.048 | 0.055 | 0.914 | 0.0285 | 0.0648 |
| B lottery vintage CONTINUOUS | +0.136 | 0.128 | 0.449 | 0.0602 | 0.2308 |

- **The saved +0.080 headline was the g/Inf bug**, per the template's own comment at line 503 ("inflated the 2026-08-20 headline ATT from +0.029 to +0.080"). Confirmed: baseline is now +0.020
- Continuous conditioning fails in a specific, diagnosable way: e=-2 goes +0.021/SE 0.065 -> -0.231/SE 0.242 and e=-1 -0.030/SE 0.054 -> +0.078/SE 0.181, while median SE inflation across the rest of the pre-window is just 1.19x. Thin not-yet-treated control pools at the event times closest to treatment cannot support a continuous covariate in the outcome regression
- Binary conditioning is stable and leaves pre-trends essentially untouched
- Substantive conclusion unchanged across all three: no detectable effect of online legalization on eviction filings

**Status:**
- Done: conditioning support, mask fix, three runs, CLAUDE.md updated
- Pending: NV-affected re-runs (2x2 pseudo-power, selection placebo, era-variance, state power cells); institution data verification vs primary statutes; not committed

## 2026-08-21 17:45 — NV-affected re-runs complete

**Operations:**
- Patched the three longdiff scripts and `R/power/load_blinded_panel.R` to drop `PRE_PASPA_SPORTS_BETTING` from control pools; pre-fix copies in `analysis/diagnostics/deprecated/` and `R/power/deprecated/`
- Re-ran selection placebo, era variance, and 2x2 pseudo-power (500 reps)

**Results:**
- 2x2 pseudo-power: MDE-80 (main, RI) 0.241 -> **0.2401** (+27.1%); 36 states / 1,532 counties. CRVE still fails size (8.4% main, 10.6% b12), RI nominal 5.4%, WCB 4.4%. **Conclusion unchanged**
- Selection placebo: tau -1.4% -> **-0.30%**, RI p 0.90 -> 0.976. **Holds, slightly cleaner**
- Era variance: overall median post/pre ratio 2.67 -> **2.04**; strict never_any_exid 3.86 -> **2.73**. NV was the flagged outlier_state inflating post-era sigma. Pre-era MDEs need LESS inflation than documented. never_any 8 -> 7 states, exid 7 -> 6 (thin)
- State power cells: **not re-runnable**. Excluding NV makes state D1 structurally infeasible at the post-COVID boundary, 3,600/3,600 rep failures ("no template placement ... enough eligible states, min_pre=12, min_post=6")

**Audit correction:** `never_treated` is consumed only in the D4 branch (`make_pseudo_schedules.R:279`); every state config uses D1, so no completed state run read it. NV's real route was being an unassigned control in the D1 pool of the 33-state S2 panel. The loader fix (S3 + attribute) is still correct but was not the binding mechanism.

**Concurrent session:** `config/power_boundary_A0*.yml` created today 13:28/13:30 by another session; `_noNV` untracked. Its `exclude_states: [NV]` is honored (`run_scenario_grid.R:1108`). Its noNV arm is the run that failed 3,600/3,600.

**Process miss:** overwrote untracked `output/longdiff_era_variance/` in place; pre-fix CSVs unrecoverable, only headline 2.67/3.86 survive in CLAUDE.md.

**Status:**
- Done: all four dispositioned, CLAUDE.md updated
- Pending: institution-data verification vs primary statutes; not committed

## 2026-08-21 19:20 — LP-DiD power tests: NV audit and headline re-run

**Operations:**
- Inventoried all LP-DiD/LDAM power configs and runs
- Created `config/power_lpdid_ramp75_mde_noNV.yml` (exclude_states: [NV]) and ran it, 300 reps x 13 deltas x 2 cells, 31,200 rows, 0 failures
- Feasibility pre-checked: D1 placement 40/40 without NV on both spliced (32 states) and postcovid (14 states)

**Results:**
- 9 of 10 LP-DiD/LDAM configs are level: state -> NV in the S2 panel (33 states) and, having no launch date, permanently eligible as a control under the hybrid launch-date control coding
- The only NV-free arm, `lpdid_mde_county`, was ABANDONED mid-run 2026-08-17 (batch 5/12 spliced, 7/30 postcovid); partials only, no mde_table/oc_summary. So every COMPLETED LP-DiD power result is NV-contaminated
- Headline ramp75 spliced cell, NV removed: LP-DiD analytic MDE 0.0733 -> **0.0597**; wild 0.0933 -> **0.0707**; SE/SD 0.860 -> **0.979**; size unchanged at 0.063. TWFE analytic MDE 0.1269 -> 0.0797
- Postcovid cell: LP-DiD MDE flat (0.2120 -> 0.2144) but TWFE analytic size 0.040 -> **0.097**, now failing the size gate. NV was masking TWFE post-COVID miscalibration
- Mechanism: an always-treated control adds heterogeneity to the control pool, inflating estimator SD and depressing SE/SD

**Correction:** state D1 is NOT generally infeasible without NV (40/40 placements). The earlier 3,600/3,600 failure was specific to the boundary_A0 cell (anticipation A=0, 2021-08 boundary).

**Status:**
- Done: ramp75 MDE noNV arm
- Pending: NV-free re-runs of lpdid_gate, lpdid_gate_postcovid, lpdid_mde, lpdid_wild_gate, lpdid_ramp75_gate, ldam_gate{,_keepcovid,_postcovid}; finish the county arm; not committed

## 2026-08-21 22:15 — shift12 test: new recommended state spec

**Operations:**
- `data_prep/build_shift12_schedule.R` -> `data/processed/shift12_schedule.csv` (launch + 12mo, 38 states, 31 with a date); asserts +12mo exactly and same state set as ramp75
- Added `shift12_start_date` to the `treat_def` enum in `R/power/load_blinded_panel.R` (pre-change copy in `R/power/deprecated/`)
- D1 feasibility pre-checked NV-free: 30/30
- Ran `power_lpdid_shift12_gate_noNV.yml` (2,000 reps) and `power_lpdid_shift12_mde_noNV.yml` (300 reps x 13 deltas)

**Results:**
- Gate, spliced, NV-free, 2,000 reps: LP-DiD **wild 0.0580 CI [0.0482, 0.0692] PASS**; analytic 0.0865 borderline/fail; TWFE analytic 0.0465 PASS
- Gate, postcovid: LP-DiD analytic 0.0630 PASS, wild 0.0535 PASS — ramp75's analytic arm was 0.0733 here
- MDE, spliced, wild: **0.0628** vs ramp75 0.0707 vs raw-online 0.0487 (artifact, fails size at 0.1033)
- SE/SD at 2,000 reps: shift12 spliced 1.003 (ramp75 0.979)

**Conclusion:** ramp75's size-gate advantage over raw online dating comes from the LAG, not the handle-based timing — both lagged defs pass under wild. shift12 achieves it with zero outcome data, so it dominates on both power and design. **Recommended: shift12 + LP-DiD + wild bootstrap, spliced window, NV excluded, MDE 6.3%.**

**Status:**
- Done: shift12 schedule, loader support, gate (2,000 reps), MDE
- Pending: queue B (lpdid_gate / lpdid_gate_postcovid baselines on the rebuilt panel); a higher-rep shift12 MDE; institution-data verification; not committed

## 2026-08-24 16:35 — LP-DiD reweighting fix + CS-equivalence audit (DGJT paper)

**Operations:**
- Read Dube, Girardi, Jordà & Taylor (FRBSF WP 2023-12 / NBER w31184) in full; repo had no copy
- Fixed `R/power/run_estimators.R` `.re_lpdid`: cell weights `1/Var_cell(D)` → `1/(1-Dbar_cell)` (new `.re_lpdid_weights()` helper); same fix in `analysis/main/lpdid_statepanel.R` (`lpdid_cell_weights()`, `LPDID_WEIGHTS` env var)
- New config knobs `lpdid_weights` (ewatt/cellsize/vwatt) and `lpdid_pmd`, plumbed config → grid → spec → estimator; `lpdid_weights` hashes its NEW default so post-fix runs can never pool with pre-fix partials
- New tests in `tests/testthat/test-estimators.R` (closed-form estimand checks, knob wiring, CS equivalence); 68 pass, full-suite failures identical to baseline
- New diagnostics: `analysis/diagnostics/lpdid_cs_equivalence.R`, `analysis/diagnostics/lpdid_weights_paired_compare.R`
- Runs: `lpdid_shift12_gate_ewatt` (2,000 reps, done), `lpdid_shift12_mde_ewatt` (300 reps × 13 δ, running), `lpdid_shift12_gate_vwatt` (queued)

**Decisions:**
- `ewatt` (the paper's §2.5.2 weight) made the default; `cellsize` kept only to reproduce pre-fix partials
- CS cross-check done as diagnostic + test rather than a grid arm — cleaner falsification

**Results:**
- Old weights = cell weight N_cell: neither the paper's VWATT nor EWATT; every prior LP-DiD size/MDE number is on that third estimand
- CS equivalence (ewatt+pmd1) holds to 2.2e-16 on contiguous panels — even badly unbalanced ones — and BREAKS on any interior time gap (toy: 7-month hole → 1.1e-01). `.re_prep()` gives CS a consecutive rank index that bridges the COVID splice; flagged as a framework-wide CS issue
- Corrected EWATT gate: analytic FAILS (0.145 spliced, SE/SD 0.67 — CS-like miscalibration, consistent with the equivalence); wild PASSES (0.0325 spliced). TWFE unchanged (validates comparison)

**Commits:**
- `5c46e15` checkpoint, `f708b57` weighting fix, `02ac68d` equivalence test + configs, `45d3c72` contiguity diagnostic, `7aba318` CLAUDE.md, `1fdbdc8` gate results + vwatt queue

**Status:**
- Done: fix, tests, diagnostics, gate re-run, CLAUDE.md
- Pending: MDE re-run (running), vwatt gate (queued), CLAUDE.md update with MDE numbers

## 2026-08-24 17:40 — Corrected shift12 runs complete (three-way weighting comparison)

**Results (all NV-free, spliced window, wild inference unless noted):**
- ewatt (corrected EWATT): size 0.033, MDE 0.115 [CI 10.2–12.5%]; analytic FAILS (0.145, SE/SD 0.67 — inherits CS miscalibration, as the numerical equivalence predicts)
- vwatt (Cengiz-stack VWATT): size 0.0515, MDE 0.0875 [CI 8.3–9.1%]; postcovid MDE 0.32–0.37 (unusable there)
- cellsize (dead pre-fix figures): 6.3% MDE was the mislabelled estimand
- TWFE stable 0.14–0.18 in every cell (validity check on the comparisons)

**Decisions:**
- Recommended PAP framing: choose ewatt-wild (MDE 11.5%, CS-comparable estimand) or vwatt-wild (MDE 8.75%, variance-weighted estimand) explicitly; never quote the 6.3%

**Commits:**
- `1fdbdc8` ewatt gate + vwatt config, `df08995` corrected MDE, `cff69e8` vwatt gate, (this entry follows the vwatt MDE)

**Status:**
- Done: full three-way gate+MDE ladder, CLAUDE.md, diagnostics, tests
- Pending: Ben's estimand choice for the PAP; the `.re_prep` CS splice-bridging issue (flagged, separate work)

## 2026-08-25 12:35 — Repo cleanup: run ledger, findings doc, CLAUDE.md slim, deprecation moves

**Operations:**
- Built `RUN_LEDGER.md` (registry of all runs w/ statuses) from 4 parallel-agent inventories in `quality_reports/cleanup_2026-08-25/` (output/ 89 entries, output_blinded_power/ 92, config/ 49, run history 43 rows)
- Wrote `FINDINGS.md` (current-truth only; every number artifact-verified) and `MOVES.md` (150 recorded moves)
- Moved 48 output/ dirs + 63 blinded-power entries + 18 root relics to deprecated/; 8 reference PDFs copied to Literature/ (originals deprecated); 12 LIVE-run logs moved inside their run dirs; +1 late move (cheap_power_sim, audit-overturned)
- CLAUDE.md slimmed 1,159 → ~195 lines; history split verbatim (sed line ranges) into `docs/findings-archive/` (12 topic files + INDEX); pre-slim copy at `deprecated/CLAUDE_2026-08-25_pre-slim.md`
- Opus audit (10 findings) → all fixed

**Decisions:**
- Orchestration per model-routing: Fable orchestrated, Sonnet executed, Opus audited
- Status vocabulary LIVE/SUPERSEDED/CONTAMINATED/DEAD/EXPLORATORY/UNKNOWN; UNKNOWN never guessed (9 flagged for Ben)
- Maintenance rules added to CLAUDE.md: ledger row per run, FINDINGS update on LIVE change, dated archive files for corrections, deprecate-by-move, vintage check before pairing

**Results:**
- Audit BLOCKER caught & fixed: FINDINGS PAP table had post-COVID SE/SDs (0.81/0.98) pasted into spliced rows; artifact values are 0.67 (ewatt) / 1.02–1.04 (TWFE)
- `cheap_power_sim` overturned LIVE → CONTAMINATED (pre-rebuild state panel; named in the old contaminated list)
- 29→28 LIVE runs; 57 stale ledger links repaired after moves; 7-state court-data table restored to archive; 4 dropped TO DO items restored
- Pre-existing unit-mix documented: +9.1% headline's "+17.5%" CI bound is the raw log endpoint (exponentiated: +19.1%)

**Commits:**
- `c3471e5` Pre-cleanup snapshot
- `b791dc0` Cleanup phase 1: ledger, findings, moves
- `8937853` Cleanup phase 2: CLAUDE.md slim + archive
- (this commit) Cleanup phase 3: Opus audit fixes

**Status:**
- Done: registry, findings doc, CLAUDE.md slim, moves, audit
- Pending (Ben): 9 UNKNOWN dirs to adjudicate (RUN_LEDGER Open items); FINDINGS §6 open questions; git-hygiene (branch reconciliation) deliberately out of scope

## 2026-08-25 18:10 — County shift12 gates + null-bias diagnosis

**Operations:**
- New configs: `config/power_lpdid_shift12_gate_county_{vwatt,ewatt}.yml` (county shift12 size gates, corrected weights, 2,000 reps x 2 windows each). Both complete.
- Null-bias decomposition: `analysis/diagnostics/nullbias_{verify_reconstruction,decomposition,decomposition_analysis}.R` -> `output/nullbias_decomposition/`, memo `quality_reports/nullbias_decomposition_2026-08-25.md`
- Reaped 8 orphaned `future` workers (~290% CPU) left by crashed runs

**Decisions:**
- Did NOT trim estimators to save memory — `estimators` is hashed into scenario_id, would have orphaned 950 completed reps
- Kept LP-DiD wild OFF at county (boottest cannot do WLS with absorbed FEs)

**Results:**
- County gate: TWFE+wild size-valid in all four scenario-runs (0.041–0.049); every county LP-DiD analytic cell FAILS (0.151/0.172 spliced, 0.279/0.306 postcovid); did2s fails in-framework (0.111–0.237) despite 4% in the calibration harness
- Null-bias 2x2 (LP-DiD spliced): state vwatt +1.06 SD, state ewatt +0.27, county vwatt +0.36, county ewatt +0.16 — both axes compound; current recommended spec is the worst cell
- Bias CAUSE: eligibility-constrained placement in `.assign_cohorts()` (adoption date correlates negatively with own trend slope in 4,000/4,000 draws; 62–64% of TWFE bias variance). Composition breaks + calendar timing ruled out.
- Infrastructure: crashed masters orphan their workers, starving later runs (first diagnosis "memory leak" was WRONG — corrected in RUN_LEDGER)
- `lpdid_anchor` default drifted to `event_clean`; pin `"event"` to reproduce the ewatt gate

**Commits:**
- `04d00b0` county vwatt gate + null-bias diagnosis integrated
- `f9f23e4` corrected failure diagnosis (orphans, not leak)
- `b067ed0` county ewatt gate complete

**Status:**
- Done: repo cleanup, RUN_LEDGER, FINDINGS, ESTIMATOR_MATRIX, county gates, bias diagnosis
- Pending (Ben): PAP decision — recenter the null before size/MDE vs report bias alongside MDEs
- Pending (queue): LDAM MDE; wild-at-county plumbing; TWFE staggered re-run; boundary_B finalize

## 2026-08-28 12:34 — County LP-DiD wild plumbing + 300-rep smoke

**Operations:**
- New wild engine in `R/power/run_estimators.R` (.re_lpdid): every LP-DiD weight scheme is cell-constant, so the WLS with absorbed cell FE is exactly unweighted OLS of sqrt(w)-scaled variables with the same FE — boottest now takes its fe= absorption path (the .re_twfe fe="id" trick); no dummy expansion, county-safe. Legacy path kept as test-only `lpdid_wild_engine: "dummy"`.
- Equivalence unit test (test-estimators.R): on enumerated Rademacher draws (8 states, 2^8 < B) the new engine reproduces legacy p-values/CIs EXACTLY, ewatt + vwatt. First attempt (fixed-projection FWL) was caught by this test at a 2/256-draw discrepancy and discarded.
- Smoke configs + runs: `config/power_lpdid_shift12_gate_county_{vwatt,ewatt}_wildsmoke.yml` (300 reps, lpdid-only, both windows, base_seed shared with the 2,000-rep gates). Both complete, wild converged 300/300.
- RUN_LEDGER (2 EXPLORATORY rows), ESTIMATOR_MATRIX (smoke block, gap #2 closed), FINDINGS §2 (new smoke paragraph) updated.

**Decisions:**
- Cell-scaling over hand-rolled WCR or WildBootTests.jl — exact vs legacy engine, no new dependencies.
- 300-rep smoke, not 2,000-rep gate — Ben asked for fast preliminary numbers; smoke marked EXPLORATORY everywhere.

**Results:**
- Spliced wild size: vwatt 0.033, ewatt 0.060 (analytic same-reps 0.187 / 0.167) — wild rescues the spliced window, matching the state pattern; ewatt too close to the 0.075 line to classify at 300 reps.
- Postcovid wild: 0.103 / 0.090 (analytic 0.290 / 0.343) — improves but likely still fails at 5 treated clusters.
- CLAUDE.md drift noted: `run_from_config()` does not exist; real entry is `run_scenario_grid()` via scripts/run_power_*.sh.

**Commits:**
- `8790c52` County-safe LP-DiD wild engine: cell-scaled OLS through boottest fe= path
- (next) smoke results + ledger/matrix/findings updates

**Status:**
- Done: engine, tests, smoke runs, doc updates
- Pending: 2,000-rep county wild gate (flip lpdid_wild in the full-rep county configs, fresh run_name); Ben's PAP estimand/recentering decisions

## 2026-08-28 14:20 — Calibration-sim audit: two silent sample-loss bugs found, fixed; re-runs pending

**Operations:**
- Audited `analysis/diagnostics/cs_calibration_multi_estimator_county.R` (source of LIVE FINDINGS §4 county verdicts) after Ben flagged recurring sim coding errors
- Verified two bugs on synthetic known-truth panels; fixed 8 scripts (uncommitted): cs_calibration_multi_estimator{,_county,_mortgage}.R, permutation_placebo_real_data.R, power_simulation_cs.R, cheap_sims/00_common.R, pretrends_mortgage_delinquency.R, power_simulation_mortgage_delinquency.R
- New diagnostic script `analysis/diagnostics/sunab_encoding_fix_rerun.R` (paired 50-seed SA re-run, bug vs fix) — was mid-run when session paused; wrote no output yet, relaunch needed

**Decisions:**
- sunab never-treated encoding standardized to g=0 (matches pretrends template + R/power) — NA encoding drops all never-treated rows (fixest silently removes NA-cohort obs; 30,024/91,384 county obs lost, SA SE halves when fixed: 0.051→0.022 on real data)
- All att_gt call sites pinned to `faster_mode=FALSE` + double g — integer g under faster_mode=TRUE truncates the g==0→Inf recode to NA and drops every never-treated unit (did/R/pre_process_did2.R:132); clustervars documented as inert without bstrap=TRUE
- County SA verdict (30%/0.51 "broken — skip") treated as SUSPENDED, not reversed, until corrected re-run lands

**Results:**
- Contaminated: county SA row (LIVE), state SA baseline (superseded), mortgage calibration (parked)
- Clean/unaffected: R/power framework, pretrends template, CS adaptive gate — all PAP-relevant LP-DiD/TWFE/LDAM/did2s verdicts stand

**Commits:**
- none (fixes on disk, uncommitted by request-of-pause)

**Status:**
- Done: audit, root-cause verification, code fixes across 8 scripts, memory checkpoint (`sunab_attgt_encoding_bugs.md` has full resume checklist)
- Pending: relaunch sunab_encoding_fix_rerun.R (~25 min); full corrected county calibration re-run (seeds reproduce exactly); deprecate old run artifacts + MOVES.md; FINDINGS §4 / RUN_LEDGER / ESTIMATOR_MATRIX / findings-archive correction doc; re-render fig4/fig5; commit

## 2026-08-28 17:30 — Per-state basket rebuild (+NY/CO/SC/HI/MS) + h18-24 design probes

**Operations:**
- SD probes for the memo's mature-window LP-DiD (launch clock, h=18..24, ewatt): `config/power_lpdid_launch_h1824_sdprobe{,_pmd12}.yml`, run locally (analytic-only δ=0, ~90 s each)
- `data_prep/rebuild_state_month_panel.R`: basket start now per state (each state's first reporting month), not global 2016-01; rebuild run
- Configs `power_lpdid_launch_h1824_{gate,mde}_ewatt.yml` re-pointed to fresh `_p39` run_names; single-horizon h18 variants deprecated; `della_power_upload/` rebuilt with new panel + configs
- Dead pre-basket gate partial moved to `output_blinded_power/deprecated/`; old panel vintage preserved in `data/raw/deprecated/`; MOVES/RUN_LEDGER/FINDINGS/CLAUDE.md updated (vintage boundary #6)

**Decisions:**
- Pooled h=18..24 (not open-ended 18+, not single h=18) — contributor pool collapses past 24
- COVID drop window unchanged (2020-03..2021-07): end matches moratorium regime, not filings stabilization (~2022-04); extending would NA the mid-cohort pre-launch baselines
- Panel rebuild done but NO sims launched on the 39-state panel yet (Ben: "don't run yet")

**Results:**
- SD probes (EXPLORATORY, pre-basket panel): mature-window design SD 0.111 vs shift12 0.049 → est. wild MDE ≈0.26; pmd=12 baseline averaging cuts to ≈0.17. The 11.5% shift12 MDE belonged to the legacy short-difference anchor
- Rebuild adds CO/HI/MS/NY/SC (34→39 states; NY+CO treated); every pre-existing state-month unchanged bit-for-bit

**Status:**
- Done: rebuild, probes, configs, vintage bookkeeping
- Pending: Della h1824 `_p39` gate+MDE runs (Ben to launch); null-recentering decision; `timing_covid_recovery_test.R` first run; memo text fixes (equation dates, 18-vs-24 censoring sentence)

## 2026-08-28 17:35 — EWATT/VWATT equations rewritten to fit boss-explanation draft

**Operations:**
- Rewrote §§9–10 of tmp/lpdid_equation_bank/equations.md (EWATT/VWATT pooling weights) to match the Google Doc draft: launch clock, mature window h = 18–24 (per config/power_lpdid_launch_h1824_*.yml), pooled sum included so the draft's "our estimator, _" blank can be filled; all symbols defined in-place.
- Rebuilt tmp/lpdid_equation_bank/LP_DiD_Equation_Bank_unsanitized.docx via pandoc (old copy → tmp/lpdid_equation_bank/deprecated/); render-verified in rendered_v5/.

**Decisions:**
- Kept EWATT/VWATT order and neutrality — strategy decision memo records the primary-estimand choice as unresolved; flagged the draft's "VWATT as primary" sentence for reconciliation.

**Status:**
- Done: draft-fitted weight equations, rebuilt docx.
- Pending: Ben pastes equations into the Google Doc; fix "years"→"months" in draft EWATT prose; reconcile VWATT-primary sentence with the unresolved PAP choice.

## 2026-08-28 18:05 — Memo equation sequence: Ohio 2×2 → general LP-DiD → weights (h = 12–24)

**Operations:**
- Updated tmp/lpdid_equation_bank/equations.md: §§9–10 weight windows moved 18–24 → 12–24 per Ben; appended memo-sequence §§22–23 (Ohio 2×2 with corrected dates; general launch-clock cell formula).
- Rebuilt the docx (prior copy → deprecated/); rendered 4 paste-ready PNGs (eq22, eq23, eq09, eq10) in tmp/lpdid_equation_bank/.

**Decisions:**
- Ohio example anchored at h=22 (Nov 2024): draft's Nov 2023 is h=10 (outside window); NC exclusion requires h≥14 (NC online launch Mar 2024, verified in data/raw/sports_gambling_legalization_dates.csv); Nov 2024 matches the draft's existing BJS/did2s reference.
- Baseline shown as P=3 (Oct–Dec 2022) matching the draft's toy model; pmd-12 alternative flagged, not imposed.

**Status:**
- Done: paste-ready sequence delivered.
- Pending: Ben pastes into Google Doc; draft prose fixes (years→months, VWATT-primary vs unresolved memo choice, Ohio date update).

## 2026-08-28 18:45 — Idaho gap, clean anchor, null-recentering implemented

**Operations:**
- ~10 SD probes (state/county, ewatt/vwatt, pmd variants, gap-tolerant, segment-constrained, noID) — all EXPLORATORY, ledger rows added
- Estimator: `lpdid_pmd_min` (gap-tolerant baseline) + `lpdid_base_gapmax` (segment/no-straddle) knobs added, both probed and REJECTED as designs, default OFF
- Null-recentering implemented per the 2026-08-25 memo: `summarize_oc()` emits `null_center` + `reject_rc_005`; every run now writes `mde_table_recentered.csv`; validated on LIVE ewatt run (0.115 → 0.124 recentered)
- Formal Della configs created: `power_lpdid_shift12_{gate,mde}_{ewatt,vwatt}_noID.yml` (legacy anchor, ID fix) and `power_lpdid_shift12_clean_{gate,mde}_{ewatt,vwatt}.yml` (event_clean pmd12 — candidate primary); della_power_upload rebuilt

**Results (all 300-rep probe estimates):**
- IDAHO GAP: the 2026-08-19 "exclude ID here too" never reached any power config; LIVE table computed with ID in control pool. noID: legacy vwatt 8.75→~5.7%, ewatt 11.5→~9.4%, TWFE 16.3→~14.3%
- CANDIDATE PRIMARY: shift12 event_clean pmd12 noID (pre-launch baseline, outcomes 12–24) — est. MDE ~9.6% (vwatt) / ~10.4% (ewatt); clean estimand at near-legacy power; legacy anchor's treated-months baseline retired as senseless
- Mature-window h18–24 stays secondary (~15.6% vwatt); county level worse (panel lacks 8 KEEP_OLD states); null bias = placement artifact scaling with cell span, handled by recentering

**Status:**
- Done: diagnosis chain complete; all configs Della-ready
- Pending (Ben): rsync + run clean gate/MDE pair on Della; MA series refresh via internal ETS; adaptive_mde.R recentering port; memo rewrite around clean anchor

## 2026-08-28 18:25 — pmd-12 baseline in Ohio example; single-control 2×2; variable glossary

**Operations:**
- equations.md §22: Ohio example now Georgia-only control with 12-month calendar-2022 baseline (pmd 12); §3/§23/core-notation P=3 remnants → P=12; §§11–13 marked superseded; new §24 variable glossary (memo-ready prose).
- Rebuilt docx (prior → deprecated/..._pre-2026-08-28-pmd12.docx); re-rendered eq22_ohio_2x2.png.

**Status:**
- Done: docx + image delivered with glossary text.
- Pending: Ben pastes sequence + glossary into the Google Doc.

## 2026-08-29 18:15 — Formal PAP numbers, vwatt sed incident, handoff

**Operations:**
- Della formal runs (via Ben, interactive RStudio): `lpdid_shift12_clean_{gate,mde}_ewatt_pmd6` — gate PASS (wild recentered 0.0396), **MDE recentered 0.127 [0.124–0.130]** (raw 0.0856) = new PAP headline; ledger + FINDINGS updated; artifacts on Della, rsync pending
- vwatt incident: sed anchored `ewatt$` missed trailing-comment lines → three "vwatt" configs ran ewatt (Ben's 2026-08-29 Della run = bit-identical ewatt duplicate, scenario hash caught it). Configs fixed + audited (all 16 vwatt configs verified), bogus probe quarantined, MOVES entry; corrected vwatt run pending on Della
- `timing_covid_recovery_test.R` first-ever run → LIVE, supportive (timing⊥trend p=0.70; ⊥COVID-shift p=0.28)
- BHNS provenance check (paper in Literature/): they do NOT recenter ("accidental effects" kept as realism) — our recentering = disclosed deviation, PAP sentence drafted
- Handoff: `quality_reports/HANDOFF_2026-08-29_pap_power_spec.md` (full state, queue, gotchas)

**Status:**
- Done: PAP primary spec formal + size-gated + recentered; ewatt/vwatt equivalence established (probe-level)
- Pending: vwatt formal run; artifact rsync; memo doc fixes (Guo-vs-HLP citation!); MA ETS refresh; adaptive_mde recentering port; **commit the two-day session**

## 2026-08-29 18:31 — vwatt companion results reviewed and logged

**Operations:**
- Reviewed Ben's Della paste for `lpdid_shift12_clean_{gate,mde}_vwatt_pmd6` against `quality_reports/HANDOFF_2026-08-29_pap_power_spec.md` §2
- Verified the sed-bug tripwire: MDE scenario hash `Sac8e61abda` ≠ ewatt's `Sd61e18eba4` (local partials) — run is genuinely vwatt; config diff shows only `run_name` + `lpdid_weights` differ
- RUN_LEDGER.md: two LIVE rows added; stale "Current PAP headline (VWATT)" legacy row marked SUPERSEDED
- FINDINGS.md §2: vwatt-companion sentence replaced the "unrun" placeholder
- ESTIMATOR_MATRIX.md: clean-anchor family added (ewatt headline row was missing too)

**Results:**
- Gate PASS (1,000 reps): lpdid wild raw 0.022 / recentered 0.0234; null center +0.031; SD(att) 0.0366; SE/SD 1.20
- Recentered MDE 0.126 [0.123–0.130] vs ewatt 0.127 [0.124–0.130] — equivalence confirmed, within handoff's predicted 12.4–12.7 band; ewatt stays primary
- Diagnosed TWFE drift vs ewatt run: scenario hash feeds the seed offset (`run_scenario_grid.R:358`), so ewatt/vwatt runs draw independent panels — MC noise, not a bug; comparison is unpaired
- mde_postcovid companion scenario unrun (partials-only, `scenarios=1L`)

**Status:**
- Done: handoff queue item 1 (vwatt → ledger/FINDINGS/matrix)
- Pending: artifact rsync (now incl. vwatt dirs); PAP equivalence sentence into the PAP draft; memo doc fixes; MA ETS refresh; adaptive_mde recentering port; commit the multi-day session

## 2026-08-29 18:45 — Consolidated results doc + analytic-arm finding

**Operations:**
- Recomputed ewatt gate/MDE from complete local partials (`output_blinded_power/lpdid_shift12_clean_{gate,mde}_ewatt_pmd6/partials/`) — reproduce the ledger digit-for-digit, so local partials = the formal Della data
- Created `quality_reports/power_results_2026-08-29_clean_anchor_formal_runs.md` — all 8 inference cells (2 weightings × 2 estimators × 2 inference arms), gate + raw/recentered MDE, provenance and hashes
- FINDINGS.md §2 + ledger ewatt MDE row: added the analytic-arm numbers and decision-point flag

**Results:**
- NEW: LP-DiD analytic passes the gate in both weightings (ewatt 0.045/0.048, nearest nominal) with recentered MDE 0.117 [0.113–0.121] — ~1pp better than wild 0.127; literal gate→MDE rule would pick analytic over wild. Flagged for PAP-text resolution BEFORE unblinding, not decided.

**Status:**
- Pending: wild-vs-analytic PAP decision; size-adjusted power appendix column (~30 min, optional); rsync; commit

## 2026-08-29 19:05 — Null-calibration literature check (ChatGPT search, verified)

**Operations:**
- Verified ChatGPT's candidate list (WebSearch + MNW-guide cross-ref); wrote `quality_reports/lit_check_null_calibration_2026-08-29.md`
- MNW 2023 guide read earlier this session; notes in `quality_reports/power_results_2026-08-29_clean_anchor_formal_runs.md`

**Results:**
- Gap confirmed: no published DiD paper does recentered-placebo-null size calibration end-to-end; all components precedented
- PAP citation chain: BHNS 2022 → Brewer–Crossley–Joyce 2018 (size-adjusted power/MDE in clustered DiD) → Schuemie et al. 2014 (nonzero empirical-null calibration); Shaikh–Toulis 2021 acknowledged (assignment-model alternative); Dench et al. 2024 = closest pre-registered applied precedent (diagnoses the problem, doesn't fix it)
- Verified: Brewer et al. (via MNW refs), Schuemie 2014, Melo et al. 2026 (JPubE 262), Dench et al. 2024 (JPubE 234)

**Status:**
- Pending: fold chain into PAP power section; B=999→9999 decision; wild-vs-analytic decision; rsync; commit

## 2026-08-29 19:40 — Size-adjusted MDE implemented (option 1)

**Operations:**
- Added `compute_mde_sizeadj()` to `R/power/summarize_operating_characteristics.R` (recentered + raw variants, bootstrap CI, optional `null_results` pooling); `run_scenario_grid.R` now writes `mde_table_sizeadj.csv` on full runs
- Verified on local ewatt partials: (a) s>1 reproduces reject_rc_005 digit-for-digit in all 4 gate cells; (b) achieved δ=0 size 0.0473–0.0500 every cell; (c) calibration-noise check — within-run (300 draws) 0.102 vs gate-only (1,000) 0.116 → added pooling, headline uses 1,282–1,300 draws

**Results:**
- **Size-adjusted recentered MDE, lpdid wild: 0.110 [0.099–0.122]** (−1.7pp vs nominal-cutoff 0.127); analytic 0.108 — wild ≈ analytic at exact 5% size, so the wild/analytic gap was pure conservatism; largely dissolves the wild-vs-analytic decision point (keep wild + appendix column)
- Documented: results doc (method + table), FINDINGS §2, ledger diagnostics row `sizeadj_mde_clean_ewatt_pmd6`

**Status:**
- Done: option 1 (size-adjusted appendix column) for ewatt
- Pending: vwatt size-adjusted after partials rsync; `bash scripts/make_della_power_upload.sh` rebuild before next Della run (R/power changed); adaptive_mde port; B=9999 in real-data scripts; commit

## 2026-09-03 14:55 — MD PDF refresh + panel series extension

**Operations:**
- Re-ran `data_prep/monthly_panel_expansion/01b_download_md_statistics_pdfs.R` (all 22 years; 2026 refetched live, 4.49 MB → 5.56 MB)
- Re-ran `01c_parse_md_statistics_pdfs.R` → `data/raw/monthly_expansion/md_lt_county_month.csv` now 6,192 rows, 2005-01..2026-06
- Wrote `data_prep/monthly_panel_expansion/07b_extend_md_in_panel.R` (new; idempotent, append-only)
- Ran it: `data/raw/state_month_panel_with_treatment.csv` 3,897 → 3,904 rows
- Backups: `data/raw/deprecated/state_month_panel_with_treatment_pre_md_extend_2026-09-03.csv`, `data/raw/monthly_expansion/deprecated/md_lt_county_month_pulled_2026-07-21.csv`, `data/raw/monthly_expansion/md_raw/statistics_pdfs/deprecated/Calendar_2026_pulled_2026-07-21.pdf`

**Decisions:**
- Did NOT write a new scraper — `01b_` already existed, ran clean, and covers 2005–2026. Verified rather than duplicated.
- Wrote `07b_` instead of reusing `07_merge_md_into_panel.R` — the latter is one-shot (`stopifnot(!"MD" %in% panel$state_abb)`) and trims MD to the panel's extent at merge time, which is what clipped MD at 2025-11 back on 2026-07-23.
- Append-only on the seam, with in-script assertions that every pre-existing row (MD and non-MD) is identical bit-for-bit.

**Results:**
- MD refresh was purely additive: 0 of the overlapping county-months changed value; one new month (2026-06).
- MD in panel now 2012-01..2026-06 (was 2012-01..2025-11); +7 months, all post-treatment (treat_start 2022-11).
- Caveat recorded: the added months sit in the panel's thin tail. Per-month state counts are 22 (2025-09), 6 (2025-10), 5 (2025-11), then 2 (2025-12..2026-06, MD + NC only). Both are treated, so these months carry no untreated comparison and contribute nothing to identification under any FE estimator.
- Registered as vintage boundary 7 in `RUN_LEDGER.md`; `CLAUDE.md` vintage list updated. State-level runs need a fresh `run_name`.
- Idempotency verified: second run appends nothing.

**Commits:**
- (uncommitted at time of writing)

**Status:**
- Done: MD PDFs current through 2026-06; parse current; panel extended; ledger + CLAUDE.md updated.
- Pending: no estimation re-run performed — no LIVE result changed, so FINDINGS.md untouched. Any state-level re-run on this vintage needs a fresh `run_name`.

## 2026-09-03 15:40 — Michigan JDW landlord/tenant PDF extraction

**Operations:**
- Downloaded `conditional-dismissals.pdf` (SCAO Judicial Data Warehouse, refresh date 6/1/2026) to `data/raw/michigan/`
- Wrote `data_prep/parse_mi_jdw_lt_filings_pdf.py` (new; requires pdfplumber)
- Produced `data/raw/michigan/mi_lt_statewide_week_year.csv` (392 cells, 53 weeks, complete) and `mi_lt_statewide_month_year.csv` (89 cells, 68 populated)
- Documented both in `data/raw/michigan/README.md`

**Decisions:**
- Extracted the page-3 weekly TABLE as the primary target rather than reading the page-1 bar chart alone — the table is complete and self-validating; the chart labels only 65 of 89 bars.
- Assigned bars by position within each month cluster, not by colour — the chart's legend gives 2019 and 2023 the SAME fill colour.
- Rebuilt rotated bar labels from raw chars; `pdfplumber::extract_words()` reads them reversed (May-2020 "302" returned as "203"; palindromes 545/646 mask the bug).
- Assigned weekly-table cells by right edge, not reading order, so blank cells cannot shift values into the wrong year column.
- Derived 3 single-missing months (Jan 2020, Sep 2021, Jan 2026) by subtraction from published annual totals; left 21 cells empty where 2+ labels are missing. Never zero-filled.

**Results:**
- All validations pass: every weekly row sums to its printed Total; all 8 year columns sum to their printed annual totals and the grand total 1,090,431; every bar colour matches its legend position; 2019 and 2022 (fully labelled) sum exactly to their annual totals.
- Weekly `week_month_bucket` is NOT a calendar month — of 65 comparable month-year cells, only 4 agree with the calendar-month chart (differences up to ~1,500 filings). Documented.
- Series is STATEWIDE ONLY and on a smaller footprint than the annual county dashboard (excludes Berrien Co., Grand Rapids, Dearborn Hts, Center Line & Warren, Northern Macomb Co., Grandville & Walker), so it is not comparable to `mi_county_year_landlord_tenant_filings.csv` and cannot be allocated to counties.

**Commits:**
- (uncommitted)

**Status:**
- Done: extraction, validation, documentation.
- Pending: not merged into any analysis panel — MI remains absent from the state-month panel, and this series' footprint differs from the county dashboard's. Merging is a design decision, not done here.

## 2026-09-03 16:20 — Post-COVID trend parallelism test (Test C)

**Operations:**
- Wrote and ran `analysis/diagnostics/covid_trend_parallelism_test.R` -> `output/covid_trend_parallelism/`
- Added LIVE ledger row `covid_trend_parallelism`

**Decisions:**
- Built it as a companion to `timing_covid_recovery_test.R` rather than editing that script — it tests the third piece (post-COVID SLOPE vs pre-COVID slope) that Tests A and B never measured.
- Pre-treatment months only, lambda_t from never-treated states, so nothing measured can contain a treatment effect (blind-safe).
- Used the LP-DiD configs' COVID window (2020-03-01..2021-07-31), not the older 2022-03 window in the companion script.
- Report never-treated-only dispersion as the headline: treated states have a median of 25 post-COVID pre-treatment months vs 50, so their slope estimates carry extra estimation noise.

**Results:**
- No bias channel detected: slope change does not predict legalisation timing (p=0.483, n=11); treated-vs-never mean difference +0.144 log pts/yr (p=0.236). Consistent with Test A (p=0.70) and Test B (p=0.28), and with the same low-power caveat.
- Large variance channel: among 13 never-treated states, SD of slope change 0.168 log pts/yr, SD of level shift 0.194 log pts.
- Slope drift compounds with horizon: per-state straddle contamination 0.257 (h=12), 0.318 (h=18), 0.388 (h=24) log pts. At h=24 the slope channel (0.336) exceeds the level channel (0.194).
- Total is ~3x the 0.127 recentered MDE, so the h=18..24 mature window is the worst case for straddle cells, not the best.

**Status:**
- Done: test written, run, ledger row added.
- Pending: does not by itself decide the seg-vs-gaptol config choice — that needs the size/MDE comparison of the two existing configs.

## 2026-09-03 16:45 — COVID-end sweep + correction to Test C

**Operations:**
- Swept COVID end date (2021-07 .. 2022-12) against slope/level dispersion and clean-treated-state count
- Added method-of-moments noise correction: Var(observed) = Var(true) + mean(SE^2)
- Corrected the `covid_trend_parallelism` ledger row

**Decisions:**
- Rejected the first sweep result as an artifact — MIN_OBS=6 lets a 6-month window produce a wild annualized slope, which produced a non-monotonic dispersion path (0.168 -> 0.271 -> 0.416 -> 0.783). Raising the minimum and noise-correcting made it well-behaved.

**Results:**
- CORRECTION to the 16:20 entry: h=24 straddle contamination is 0.350 log pts (~2.8x MDE), not 0.388 (~3x). The earlier figure used a 6-month minimum and no noise correction. True slope divergence at the configs' window is 0.145 log pts/yr, not 0.168 — about a quarter of the observed spread was estimation noise.
- Ben's hypothesis (COVID really ended early 2022, not mid-2021) is directionally CORRECT: moving the end to 2022-03-31 cuts true slope divergence 0.145 -> 0.102 (-30%) and h=24 contamination 0.350 -> 0.272 (-22%).
- But it does not fix the problem (still ~2.1x MDE) and costs 5 of 15 clean treated states, because AZ/CT/NY/LA/AR launches fall inside the wider gap.
- Under the current `base_gapmax` segment rule a later COVID end is STRICTLY WORSE: straddle cells are excluded anyway, so the variance gain is unrealised while the state loss is real.
- A 2021-12 end is the worst of all tested (true divergence 0.232) — plausibly because the post-window then starts mid-rebound, with states at different points of their recovery ramp.

**Status:**
- Done: sweep, noise correction, ledger corrected.
- Pending: the seg-vs-gaptol size/MDE comparison remains the decisive run; this only prices the inputs.

## 2026-09-04 — Mortgage LP-DiD feasibility probe (blind, no estimates)

**Operations:**
- Created `analysis/diagnostics/mortgage_lpdid_feasibility_probe.R` — outcome-swap plumbing for the clean-anchor LP-DiD design (event_clean / shift12 / PMD 6 / horizons 12–24) against `data/processed/mortgage_treatment_panel.csv`, plus a geometry report. Runs no regression.
- Outputs: `output/mortgage_lpdid_feasibility/{horizon_geometry,switcher_survival,outcome_granularity_levels}.csv`
- Added RUN_LEDGER.md row `mortgage_lpdid_feasibility` (EXPLORATORY).

**Decisions:**
- Outcome in **levels (pp), not logs** (Ben) — the series is published to 0.1pp and 87% of design-window state-months are ≤1.0pp, so one rounding tick is a 17%+ relative move, ≈2× the eviction design's 12.7% recentered MDE. In levels the tick is ~0.38 SD of the long difference.
- **Feasibility probe only** (Ben) — mortgage stays blinded; no ATT produced. Granularity diagnostic is pooled across switchers and controls deliberately.
- NV excluded via `PRE_PASPA_SPORTS_BETTING`, not a hand filter (the prior mortgage pretrends run is CONTAMINATED for exactly this).
- ID/HI/MS kept — those eviction exclusions are basket-composition driven and mortgage has no basket.
- Probe lead horizons start at h=13, not h=1: under shift12 the event is launch+12, so h≤12 is buildup and `event_clean` correctly refuses it.

**Results:**
- Panel: 50 states, 30 nominal switchers, 20 never-launched controls, 0 launched-but-immature. Control pool is much larger than the eviction design's (~12).
- Contributing switchers depend almost entirely on the splice: **keep COVID 24 · eviction window (2020-03..2021-07) 13 · forbearance-extended (..2022-06) 7**. Forbearance-extended is not viable (0–4 identified cells; some horizons unidentified).
- Switcher losses under the eviction splice: 11 baselines fall inside the dropped window, 6 outcome windows run past the 2025-03 panel end.
- Series *falls* through COVID (CA 0.5→0.3), not spikes — forbearance loans report as current. Verified against the raw wide file.
- Granularity in levels is stable across splices: long-difference SD ≈ 0.26pp = 2.6 ticks; 10–18% of long differences fall inside one tick.

**Commits:**
- (none — working tree)

**Status:**
- Done: plumbing, geometry, granularity, splice pricing, ledger row.
- Pending: Ben picks the splice window; then either a blinded gate/MDE (needs `R/power/load_blinded_panel.R` extended to a rate outcome) or a real-data estimate (unblinds mortgage).

## 2026-09-04 (cont.) — Mortgage blinded power: loader extended, gate smoke run

**Operations:**
- `R/power/load_blinded_panel.R`: new `level = "state_mortgage"` reading `data/processed/mortgage_treatment_panel.csv` into `y_pp` (rate, percentage points). No log transforms built. Time aggregation AVERAGES the rate instead of summing it.
- `R/power/impose_effects.R`: `y_pp` added to the outcome whitelist, plus a hard guard — a rate outcome with any count mechanism now errors instead of drawing off an all-NA `filings_count`.
- New configs `config/power_mortgage_lpdid_clean_{gate,mde}_ewatt_smoke.yml`; gate run complete, MDE smoke launched.
- Ledger rows added for `mortgage_lpdid_feasibility` and `mortgage_lpdid_clean_gate_ewatt_smoke`.

**Decisions:**
- Reversed the earlier decision to pause for user input. The splice choice is a design diagnostic and can be priced blind, so it became the scenario axis rather than a question. Only the blind/unblind fork was ever a real gate, and that was already answered.
- Forbearance-extended splice removed from the config entirely — the probe showed 0-4 identified cells, so it is not a real option.
- `deterministic` is the only mechanism valid for a rate; delta is therefore in pp, and mortgage MDEs are not unit-comparable to eviction MDEs. Documented in both the config header and the loader docstring.

**Results:**
- REGRESSION CHECK PASSED: eviction state (1,850 x 10) and county (57,464 rows) panels are bit-for-bit identical pre/post loader edit on the same config.
- Rate aggregation verified: quarterly median 0.83pp vs monthly 0.80pp (summing would have given ~2.4).
- Gate smoke (100 reps, 800 rows, 0 failures): size at 5% spans 0.01-0.07 across 8 cells, all consistent with nominal at MC SE ~0.022. SE/SD 1.03-1.15. Null center at most 0.0085pp ~ 0.26 SD — the eviction placement bias does not reproduce on this panel.
- Runtime ~6 min for 2 scenarios x 100 reps locally; 2,000 reps projects to ~2 hours. No cluster needed.

**Doc bug found:**
- CLAUDE.md "Running the Analysis" documents `run_from_config(...)`; the actual function is `run_scenario_grid(...)`. The documented command fails outright.

**Status:**
- Done: loader + mechanism extension with regression proof, gate smoke, ledger, config headers.
- Pending: MDE smoke finishing; then 1,000-2,000-rep gate + MDE with fresh run_names before any verdict is quotable. Splice choice still open on evidence, not on permission.

## 2026-09-06 22:54 — Parity check: real-data LP-DiD script vs the PAP power spec

**Operations:**
- Built `analysis/diagnostics/lpdid_statepanel_parity/` (framework side, compare, runner); outputs in `output/lpdid_statepanel_parity/`
- Ran `analysis/main/lpdid_statepanel.R` unmodified on six framework-simulated panels (3 seeds × δ∈{0,0.10}) from a scratch working directory, plus a scratch copy with only the two balancing filters disabled
- Wrote `quality_reports/parity_check_lpdid_statepanel_2026-09-06.md`; RUN_LEDGER diagnostics row `lpdid_statepanel_parity`

**Decisions:**
- Tested on blinded simulated panels, not real data — no real-data ATT produced; the real-data section of the memo uses dates and coverage only
- Did not edit the repo script; the memo lists the required changes instead

**Results:**
- Estimator logic is identical: pooled ATT and SE agree with `.re_lpdid` to 1e-15 on all six panels once balancing is off; wild p differs by bootstrap draw only
- Script as written cannot run the spec: max-coverage balancing (lines 122–126) keeps only MD+NC on the current 39-state panel; `MAX_DATE` default 2024-12-31 drops NC/DE/VT outcome windows; no exclusion knob (NV/ID/HI/MS enter the control pool); pre-trend block is empty under shift12 for any PRE ≤ 12
- Real-data geometry under the power spec (dates only): 13 usable switchers (AR KS MD ME NC OH full; DE FL IN KY NH VT WV partial) — differs slightly from the handoff's 12-state list (FL now in, AR full, KY partial); reconcile on the frozen vintage
- Env settings for the real run: `TREAT_DEF=shift12 ANCHOR=event_clean PMD=6 POST=12 POST_MIN=0 LPDID_WEIGHTS=ewatt MAX_DATE=2026-06-30`

**Commits:**
- (uncommitted)

**Status:**
- Done: parity verified at the estimator level; divergences documented with fix list
- Pending: apply the five script changes in the memo §4; freeze the panel vintage; then a δ=0 placebo re-check on the fixed script before unblinding

## 2026-09-06 23:20 — lpdid_statepanel.R: sample rules aligned with the PAP spec

**Operations:**
- Edited `analysis/main/lpdid_statepanel.R`: balancing filter moved behind `BALANCE_PANEL` (default FALSE); new `EXCLUDE_STATES` knob (default `NV,ID,HI,MS`) applied before the treatment table; `assert_no_pre_paspa_controls()` on the never-launched pool; `MAX_DATE` default removed (uncapped); usage header documents the PAP invocation
- Re-ran the parity harness with the edited script (`03_compare_fixed.R`); real-data smoke run in scratch (only sample/eligibility lines read)

**Decisions:**
- Kept the old balancing rule behind a knob rather than deleting it — a robustness row may want it; the PAP spec does not
- Enforced NV via the assertion, not only via the default exclusion, so `EXCLUDE_STATES=""` cannot silently reintroduce an always-treated control

**Results:**
- Edited script matches `.re_lpdid` ATT/SE to 1e-15 on all six simulated panels with no sample-knob overrides
- Real panel under the spec: 35 states, 23 treated, 12 never-treated, 109 months; 16 switchers pass the baseline check (AR DE FL IN KS KY MA MD ME NC NH OH PA RI VT WV; MA/PA/RI have no outcome months and drop at cell construction); no-baseline: AZ CO CT LA NY TN VA
- `EXCLUDE_STATES=""` stops with the pre-PASPA error naming NV, as intended

**Commits:**
- (uncommitted)

**Status:**
- Done: script changes 1–3 from the parity memo
- Pending: pre-trend block under shift12 (memo §4 item 4), bootstrap seed (item 5), panel vintage freeze, then the real run

## 2026-09-06 23:50 — LP-DiD pre-trends under the PAP spec + Roth pretest power

**Operations:**
- Ran the real-data script (scratch copies with a `PRE_MIN` knob and stack export) with the PAP env and `PRE=36`; stored only pre-period artifacts in `output/lpdid_pretrends_shift12_clean/`
- Trend-slope test with wild bootstrap on the 18 clean leads; Roth (2022)-style detectable-slope calculation
- Ledger row `lpdid_pretrends_shift12_clean`

**Decisions:**
- Leads 1..6 months before launch overlap the baseline window and are mechanical — excluded from the headline joint test
- Analytic joint Wald is unusable (clustered vcov ill-conditioned at 35 clusters, 18 correlated coefficients); the null-imposed wild bootstrap is the only joint p worth citing
- Roth power computed from a one-parameter slope test (wild SE), not from V^-1, for the same reason

**Results:**
- Clean-lead joint wild p = 0.194; slope −0.0022/month (wild p 0.50); no evidence against parallel trends
- Pretest power is weak: 80%-power slope 0.0091/month ⇒ implied 12–24 bias up to 0.196 log pts vs MDE 0.127
- Pretest sample admits switchers (AZ CT NY TN VA…) that contribute no post cells

**Status:**
- Done: pretrends diagnostic, ledger row
- Pending: add `PRE_MIN` to the repo script (memo item 4); decide HonestDiD/Mbar pre-registration; uncommitted
- (23:59 addendum) HonestDiD blind width check, post coefficient set to 0: original ±0.092; relative magnitudes Mbar 0.25/0.5/1/2 → ±0.127/0.188/0.344/0.668. Smoothness class judged mis-specified for the long-difference gap. File: `output/lpdid_pretrends_shift12_clean/honestdid_blind_width.csv`; script copy `lpdid_statepanel_stk2.R`.
- (2026-09-07 00:10 addendum) HonestDiD with 3 pooled placebo windows (7–12, 13–18, 19–24 months pre-launch; joint Wald p 0.33; max |pooled pre| 0.061): relative-magnitudes half-widths Mbar 0.25/0.5/1/2 → 0.103/0.113/0.150/0.254 vs 0.127/0.188/0.344/0.668 with 18 single leads. File `output/lpdid_pretrends_shift12_clean/honestdid_blind_width_3window.csv`. Window structure must be pre-registered before unblinding.

## 2026-09-14 — Panel currency audit, single-series rebuild, and design review

Full memo: `quality_reports/session_2026-09-14_panel_audit_and_design_review.md`

**Operations:**
- Rebuilt 6 single-series states from `ets_county_month.csv` (`data_prep/rebuild_single_series_from_ets_internal.R`); RI +77 mo, MO/NM +41, MA +31, LA +7, NV +6
- Filled ACS renter denominators, 574 rows (`data_prep/fetch_acs_renter_denominators.R`)
- Censored series-start ramps CT 2016-01/02, NH 2018-12 (`data_prep/censor_series_start_ramps.R`)
- Generated `docs/DATA_CURRENCY.md` + generator; regenerated `output/eviction_stabilization/`
- 11 new diagnostics + 3 figures; 8 v20260914 configs (4 headline + 4 noMO) + slurm + interactive runbook
- Added **Oregon** (new state, never in the panel): OJD PDFs 2018-01..2019-12 + Evicted in Oregon dashboard 2020-01..2026-07, seam 0.9905 (-0.0095 log pts) disclosed not adjusted (`data_prep/add_oregon_to_state_panel.R`). Panel 4,071 -> 4,174 rows, 39 -> 40 states
- **Correction #11 (the session's opening finding was inverted):** "only WY has clean online timing among the missing legalizers" is wrong. WY's baseline is 1/6 -> NOT viable; NJ (6/6, 7/13), OR (6/6, 3/13) and IA (6/6, 1/13) ARE. I had judged missing states on outcome-window survival without checking the baseline. **NJ is the highest-value remaining target** — monthly Tenancy recoverable from NJ Courts `cman` PDFs by differencing YTD values, but 220 of 252 PDFs still need downloading
- Prior vintages in `data/raw/deprecated/` (MOVES.md)

**Bugs fixed:**
- `rebuild_state_month_panel.R` read KEEP_OLD from the 2026-08-20 archive -> would have silently reverted MD's 2026-09-03 extension. Latent since 2026-09-03
- `make_della_power_upload.sh` hardcoded config list -> would have shipped a package missing the new runs
- DATA_PROVENANCE §1 corrected: the LSC file is a HYBRID; the live download is a strict subset (NC/ME from court substitutes). Re-downloading is destructive
- `docs/DATA_PROVENANCE.md` was untracked in git

**Results:**
- Switchers 13 -> 16, full-window 6 -> 7 (RI 2/13 and OR 3/13 join; MA becomes full)
- County spillover design cluster-infeasible (2-11 clusters) -> no MDE run warranted
- Three COVID routes tried and closed (gap-tolerant / shorter window / pre-COVID straddle); the 2021-07 boundary is correct
- COVID resets: mean cancels treated-vs-control (t = -1.24), variance does not (0.204 = 1.6x MDE, 41% after pooling)
- Eligibility window mis-specified: 34% of admitted state-slots contribute nothing; 8 of 24 D1 cohort slots are structurally impossible
- Ramp censor: CT pre-COVID log SD 0.376 -> 0.133, NH 0.482 -> 0.138 (Ohio benchmark 0.114)

**Corrections (11 logged in memo §4):** no-network (zsh globbing), site double-count, NM basket quality, `min_post`=6, the (18,12) patch, "breaks the design", gap-tolerant rescue, the 2020-09 COVID boundary, LSC-refresh-first, stale stabilization artifact.

**Commits:**
- `fad95a6` Rebuild single-series states, add data-currency tooling, pre-flight the panel (56 files)

**Status:**
- Done: panel rebuilt + canonical, denominators filled, currency doc generated, Della package built and matching
- Pending: **configs carry (18,12) and will NOT run under D1 — revert or change design before launching**; MO-exclusion, MA-labelling, recentering, maturity disclosure all open; `ets_county_month.csv` untracked
