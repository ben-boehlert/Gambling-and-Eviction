# Monthly Panel Expansion — MD + NJ + OR + IA

Pipeline to add monthly state-level eviction data for **Maryland, New Jersey,
Oregon, and Iowa** to the existing ETS/LSC monthly panel. Motivated by the
singleton-cohort problem in the current 24-state CS-DiD panel (see
`/CLAUDE.md` → "Heterogeneity-Robust Estimator Calibration"): adding these
four states (each with a distinct online-gambling legalization date) may
break singleton cohorts and meaningfully improve power.

## Status at a glance

| State | Data source                          | Can automate?   | Status    |
|-------|--------------------------------------|-----------------|-----------|
| MD    | MD Open Data Portal (Socrata API)    | Yes (httr2)     | **Extracted** — but with critical pre-treatment gap (see below) |
| NJ    | NJ Courts Tableau / OPRA request     | No              | Pending — file OPRA |
| OR    | Evicted in Oregon (PSU) Tableau      | No              | Pending — email request or manual download |
| IA    | Iowa SCA email request               | No              | Pending — email SCA |

Only MD has an open API. NJ/OR/IA all require either a records request, a
researcher data-share, or manual export from a Tableau dashboard.

## ⚠ Critical finding for MD

The Socrata dataset **effectively starts May 2023** for `warrant_petitions`
(the filings analog) and **late 2022** for `evictions_executed`. MD's online
gambling legalization date is **2022-11-30**. This means:

- **`warrant_petitions`: ~0 pre-treatment months** (starts 6 months AFTER
  MD treatment)
- **`evictions_executed`: ~1 pre-treatment month** (starts Oct 2022 with
  sparse pre-Nov 2022 coverage)

**MD cannot be used as a treated state in CS-DiD with this data alone** —
you need pre-period observations to estimate the counterfactual. Two paths
to rescue MD:

1. Scrape archived MD Judiciary monthly Landlord/Tenant Case Activity
   Reports (PDFs, 2017–2021). Separate ~1–2 day project with `tabulizer`.
2. Use MD only as a **never-treated control donor** — but that's
   backwards given MD's late treatment. Better to drop MD until historical
   PDFs are merged in.

Bottom line: **MD data IS pulled and saved, but should be excluded from
the main CS-DiD analysis unless historical PDFs are added.** The script
produces the output for inspection and future use.

## Run order

```r
# 1. Maryland — fully automated
source("data_prep/monthly_panel_expansion/01_pull_md_socrata.R")

# 2-4. NJ / OR / IA — run after you've obtained the raw files
#                     (scripts will stub empty CSVs in the meantime)
source("data_prep/monthly_panel_expansion/02_pull_or_evictedinoregon.R")
source("data_prep/monthly_panel_expansion/03_pull_nj_courts.R")
source("data_prep/monthly_panel_expansion/04_pull_ia_email_request.R")

# 5. Merge into expanded state-month panel
source("data_prep/monthly_panel_expansion/05_merge_expanded_panel.R")
```

NJ Courts statistics PDFs can be downloaded separately before parsing:

```bash
Rscript data_prep/monthly_panel_expansion/03c_download_nj_statistics_pdfs.R
```

By default this tries `cman<YYMM>.pdf` and `gray<YYMM>.pdf` from January
2016 through the current month, first on the live NJ Courts site and then
through Wayback. Outputs go to
`data/raw/monthly_expansion/nj_raw/statistics_pdfs/`, with an audit manifest
at `data/raw/monthly_expansion/nj_raw/nj_statistics_pdf_manifest.csv`.

Useful narrower run:

```bash
NJ_STATS_START_YM=2024-01 NJ_STATS_END_YM=2025-12 NJ_STATS_PREFIXES=cman \
  Rscript data_prep/monthly_panel_expansion/03c_download_nj_statistics_pdfs.R
```

## Important measurement caveats

### Maryland
The Socrata dataset records **events on warrants of restitution** (landlord
filings for warrants, plus eviction executions). This is a LATER-STAGE
measure than the ETS/LSC "eviction filings" variable. Two options:

- `warrant_petitions` — landlord petitions a warrant after judgment
  (proxy for filings that reach judgment)
- `evictions_executed` — sheriff/constable actually evicts tenant

Script 01 produces both; the merge (script 05) defaults to
`warrant_petitions`. You may want to run the main analysis on both to
check robustness. **MD-vs-ETS comparability is not perfect** — plan to
discuss this in any write-up.

Coverage: Jan 2023–present. No historical pre-2023 data via this API.

### New Jersey
NJ reports at the **vicinage** level, not county. Crosswalk is in
`nj_vicinage_county_xwalk.csv`. Some vicinages cover 2–3 counties, so
county-level analysis requires allocation rules (population-weighted share
of renter-occupied units is standard). For state-month analysis this is
moot.

### Oregon
OR data covers **~90% of evictions** (circuit courts only; 13 counties
have justice/municipal court filings that are NOT captured). Coverage
starts 2017.

### Iowa
IA courts are unified, so SCA can produce the full panel from one query.
No major caveats expected once data is received.

## Treatment dates (online legalization)

| State | Online start |
|-------|--------------|
| NJ    | 2018-08      |
| IA    | 2019-08      |
| OR    | 2019-10      |
| MD    | 2022-11      |

Note: IA's 2019-08 matches an existing ETS-panel treated state's cohort,
which helps break the singleton-cohort problem. NJ/OR/MD each have unique
dates that WON'T collapse singletons unless other Eviction Lab states
happen to share them.

## What this adds to power

Current balanced panel: 24 states (11 treated, 13 never-treated), all 11
treated cohorts singleton. See `CLAUDE.md` → "Cohort structure".

If all four states come through clean, the balanced panel becomes
**28 states (15 treated, 13 never-treated)** with IA joining an existing
2019-08 cohort (first non-singleton cohort). Rough expectation, based on
Hollenbeck et al. (2025) achieving workable CS-DiD at 51 clusters/24
treated: a 4-state expansion won't fully fix the calibration problem but
should meaningfully reduce the SE/SD ratio (currently 0.67 for CS
analytic).

After merging, re-run:
```r
source("analysis/diagnostics/cs_calibration_multi_estimator.R")
```
on the expanded panel to confirm whether het-robust estimators become
usable.

## Known limitations and honest notes

1. **MD margin mismatch**: MD measures post-judgment warrants, ETS measures
   filings at complaint. If effects operate on early-stage filings only,
   MD won't pick them up.
2. **MD pre-2023 gap**: No historical Socrata data. Can be partially
   filled from archived PDF monthly Landlord/Tenant Case Activity Reports
   (2017–2022), but that's a separate scraping project.
3. **OR justice-court undercoverage**: 13 counties missing non-circuit
   filings. State-level totals will be slightly biased low, but
   proportionally, so a state-month DiD should be fine as long as the
   undercoverage is stable over time (likely).
4. **NJ vicinage ≠ county**: For state-level analysis, no issue. For any
   county-level robustness, requires allocation.
5. **Lead time**: OPRA (NJ) and SCA (IA) typically 2–6 weeks. Plan
   accordingly.

## References
- MD Open Data: https://opendata.maryland.gov/Housing/District-Court-of-Maryland-Eviction-Case-Data/mvqb-b4hf
- Evicted in Oregon: https://www.evictedinoregon.com/data-tables
- NJ Courts OPRA: https://www.njcourts.gov/public/opra
- Iowa SCA: https://www.iowacourts.gov/
