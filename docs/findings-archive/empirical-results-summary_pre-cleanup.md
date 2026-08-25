> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

## Empirical Results Summary

### Eviction Filings (Primary Outcome)

**UPDATED 2026-07-23 (post NH + ME court-source repairs).** NH (commit 84678a6) and ME (this session) were repaired from their state judicial-branch sources after both were found to carry a late-2023 zero-fill artifact; ME is now included as a never-treated control. Numbers below are the current repaired-panel pretrends run (`output/pretrends_statepanel_me_included`).

- **Panel**: 26 states (12 treated, 14 never-treated), 12 cohorts, 91 months (2016–2024, excl. COVID), 2,366 obs
- **CS-DiD pretrends**: Parallel trends NOT rejected (Holm min p = 1.0, both analytic and bootstrap)
- **Sun-Abraham pretrends**: NO LONGER rejects after the repairs (joint Holm min p = 0.357) — the prior rejection was partly driven by the NH/ME data artifacts
- **Overall ATT (CS-DiD)**: +0.011 log points (SE = 0.163 analytic, 0.162 bootstrap) — **not statistically significant** (was −0.225 pre-repair; the shift is mostly the NH −57% artifact removal)
- **Interpretation**: No detectable effect of online gambling legalization on eviction filings
- **TWFE power**: 80% power to detect 5% effect (MDE = 5 log points) — **unchanged by ME inclusion** (power 0.828 with ME vs 0.835 without at 5%; 38-state raw panel). Adding one never-treated control does not move the MDE. **Not double-count contaminated** (county-sourced outcome — see the state-panel section), but the saved run is 2026-07-23 and uses the PRE-repair schedule (16 never-treated, incl. ME/VT/KY/FL): re-run before citing.
- **Prior spec (pre-repair, for reference)**: 24 states (14 treated, 10 never-treated), overall ATT −0.225, SunAb rejected pre-trends

### Mortgage Delinquency (Alternative Outcome)

- **Panel**: 51 states (24 treated, 27 never-treated), 18 cohorts, 91 months (2016–2024, excl. COVID), 4,641 obs
- **CS-DiD pretrends**: Parallel trends NOT rejected (Holm min p = 1.0)
- **Sun-Abraham pretrends**: Rejects (same long-horizon trend issue — secular post-financial-crisis decline)
- **Overall ATT (CS-DiD)**: +0.030 percentage points (SE = 0.043) — **not statistically significant**
- **Interpretation**: No detectable effect on mortgage delinquency rates
- **Script**: `analysis/pretrends/pretrends_mortgage_delinquency.R`, run via `scripts/run_pretrends_mortgage.sh`

### Related Literature: Hollenbeck, Larsen & Proserpio (2025)

- Uses individual-level UC Consumer Credit Panel (~7M people), Callaway & Sant'Anna estimator
- Same treatment variation as our project (state-level online gambling legalization dates)
- Finds significant effects of **online** gambling access on: credit scores (−2.75 points), bankruptcy (+10%), collections (+7.5%), auto loan delinquency (+20%)
- **No effect** on credit card delinquency
- Effects appear ~2 years post-legalization, concentrated among subprime borrowers
- Key differences from our project:
  - **Data**: individual-level credit records for all 50 states + DC vs. aggregate state-level eviction data for 24 states
  - **Clusters**: 51 state clusters (24 treated) vs. our 24 (11 treated) — roughly 2x our design
  - **CS works for them** because they have more clusters, not because of individual vs. aggregate data (treatment is at state level for both; clustering is at state level for both)
  - **Implication**: their 7.5-10% individual credit effects may not aggregate into detectable state-level eviction effects — eviction is a more extreme margin with additional attenuation steps

### Gambling Market Maturation (Handle Quintile Timing)

Analysis of how quickly state gambling markets reach their peak monthly Handle (33 states, June 2018–Oct 2025). Measures months from a state's first Handle data to first reaching each quintile of that state's peak month.

| Quintile | Mean (mo) | Median (mo) | SD   | Min | Max |
| -------- | --------- | ----------- | ---- | --- | --- |
| 20%      | 4.8       | 1.9         | 8.5  | 0   | 38  |
| 40%      | 10.3      | 8.0         | 12.1 | 0   | 48  |
| 60%      | 16.9      | 14.0        | 14.9 | 0   | 52  |
| 80%      | 29.3      | 30.0        | 17.5 | 0   | 65  |
| 100%     | 46.3      | 46.0        | 19.6 | 0   | 78  |

- Most states reach 20% of peak within 2 months (median), though retail-first states like Arkansas take ~38 months
- 80% of peak takes ~2.5 years on average (median 30 months)
- Peak reached at ~3.8 years on average, ranging 0–78 months
- States launching with online immediately (Ohio, North Carolina, Kansas) hit high quintiles in month 1; retail-first states (Arkansas, Oregon) take years
- Relevant for gambling intensity heterogeneity: post-treatment handle maturation varies widely, so first-year handle may not capture steady-state intensity
- Script: `analysis/exploratory/quintile_timing_analysis.R`

### Support Structure

- Raw ETS panel: 38 states (Maine repaired 2026-07-23 and re-included; formerly excluded for data quality)
- Balanced panel: pretrends ~26 states (ME included); the CS calibration script still hardcodes `EXCLUDE_STATES=c("ME")` and reports 24 states until re-run
- 11 treated states, each in its own cohort (singleton cohorts)
- 13 never-treated states
- 15–18 treatment groups in unbalanced panel (depending on treatment definition: online, retail, first)
- 875 total (g,t) cells; only 338 identifiable (38.6%) in unbalanced panel

### Power Analysis Results

- **TWFE without COVID**: 80% power to detect 5% effect (MDE = 5 log points). Well-calibrated: SE/SD = 1.14, Type I error = 1-5%. Outcome is county-sourced, so this is NOT double-count contaminated; it IS on the pre-2026-08-10 schedule and needs a re-run (see the state-panel section).
- **TWFE with COVID**: 80% power to detect 8% effect (MDE = 8 log points)
- **Heterogeneity-robust estimators (CS, SunAb)**: MDE ≈ 20-25% (4-5x noisier). Not useful for detecting plausible effect sizes.
- **No formal power simulation exists for mortgage delinquency** (the mortgage panel has 51 states so power is likely better than evictions)

