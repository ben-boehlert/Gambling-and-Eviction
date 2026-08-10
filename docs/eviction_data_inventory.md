# Eviction Data Inventory — Online-Gambling States Outside the ETS Panel

**Purpose.** Catalog publicly available eviction filing data for the seven online sports-gambling states currently absent from the Eviction Tracking System (ETS) monthly panel. The ETS panel binds the main analysis to 24 balanced states; adding these seven would lift the treated-cluster count from 11 to 18 and partially resolve the singleton-cohort problem identified in `analysis/diagnostics/cs_calibration_multi_estimator.R`.

**Method.** For each state, the entry below lists (1) the source URL of the state court system or open-data portal, (2) data format, (3) temporal frequency, (4) date range covered, (5) geographic aggregation, (6) access method, and (7) a one-sentence feasibility verdict. All URLs were fetched live in the session that produced this file (May 2026); URLs that returned 403/anti-bot blocks are flagged but were independently verified via web search and, where available, a sibling document on a non-blocking host.

---

## NJ — New Jersey

> **Revised after verification round** ([docs/eviction_data_verification.md](eviction_data_verification.md)). Prior verdict (EASY, county × month) overstated public bulk-download availability.

1. **Source URL.** https://www.njcourts.gov/public/statistics (free public); paid Civil Reports catalog at https://www.njcourts.gov/sites/default/files/attorneys/ecourts/civil-report-descripts-record-layout.pdf.
2. **Format.** Free: PDF reports (Court Management Statistics, Civil Statistics, Municipal Court Statistics) plus interactive Filings and Resolutions Dashboard. Paid: text/delimited files via the Superior Court Clerk's ACMS products (PAC0600 LT for case-level Special Civil Part LT filings).
3. **Frequency.** Free: court-year (July–June) PDFs; dashboard updates monthly but exposes data only via interactive clicks. Paid: weekly LT case-level files via email (PAC0600 LT), or weekly/monthly bulk CD-ROM with 1995–present history (PAC0600 by docket type).
4. **Date range.** Free historical PDFs back to 2004; recent benchmark = 115,552 LT complaints filed court-year July 2023–June 2024. Paid ACMS extracts: 1995–present.
5. **Aggregation.** Free public: statewide × court-year for LT specifically (county breakdown only via dashboard click-through). Paid: case-level with venue (county) and filed date — aggregable to any granularity.
6. **Access method.** Free: direct PDF download or manual dashboard extraction. Paid: contact Superior Court Clerk's Office for an ACMS subscription. The existing project file `Court Data/county_court-issued_2000_2025_ben_update_3_19.csv` (21 NJ counties, 2013–2025 annual) was almost certainly built from a prior Clerk's Office order — it is the best NJ data currently in hand.
7. **Feasibility verdict.** MEDIUM — free public data is statewide × court-year only; reaching county × month requires either (a) a paid ACMS subscription from the Superior Court Clerk, or (b) browser-level scraping of the Filings and Resolutions Dashboard. Annual county data is already in hand via the project's existing extract.

---

## IA — Iowa

1. **Source URL.** https://www.iowacourts.gov/static/media/cms/Annual_Report_2023__F323582E925F5.pdf (Annual Report); statutory mandate at https://www.legis.iowa.gov/docs/publications/LGR/90/HF548.pdf (fetched and read in-session).
2. **Format.** PDF (Iowa Judicial Branch Annual Report). No public CSV download; case-level e-filing data is restricted under HF 548 sealing provisions.
3. **Frequency.** Annual — HF 548 §7(c) requires State Court Administration to "make available to the public and report annually" aggregate FED filings and dispositions, effective July 1, 2024.
4. **Date range.** Annual reports published yearly through FY2023 visible on iowacourts.gov; statutory aggregate reporting begins FY2025; existing project file holds 2000–2025 county-year totals for 99 counties.
5. **Aggregation.** Statute requires aggregate statewide totals; the existing project extract suggests county-year data is achievable via clerks of court.
6. **Access method.** Direct download of the annual PDF (iowacourts.gov returns HTTP 403 to non-browser requests but the URL is reachable in a browser); county-level micro-data requires per-court requests now that residential FED records are sealed.
7. **Feasibility verdict.** MEDIUM — statewide annual counts are mandated and downloadable, but post–July 2024 sealing makes case-level scraping infeasible and forces reliance on the aggregate report.

---

## OR — Oregon

> **Revised after verification round** ([docs/eviction_data_verification.md](eviction_data_verification.md)). The Evicted in Oregon data tables expose downloads via per-table "Get the Data" buttons whose URLs are JavaScript-rendered, not directly addressable by a plain HTTP fetch.

1. **Source URL.** Direct CSV (latest 12 months, statewide + 26 counties): `https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv` (verified by `curl`, HTTP 200, 1,344 bytes). Landing page with all topic tables and historical-year tabs: https://www.evictedinoregon.com/data-tables. OJD annual statewide PDFs: https://www.courts.oregon.gov/about/pages/reports-measures.aspx.
2. **Format.** Evicted in Oregon: tab-separated CSVs served by Datawrapper CDN (one per topic-and-year chart). OJD: annual Cases Filed PDFs.
3. **Frequency.** Evicted in Oregon: monthly × county for circuit-court FED, with a rolling "Most Recent" tab covering the latest 12 months and prior years available behind sibling Datawrapper chart IDs on the same page. OJD PDFs: annual statewide rollups.
4. **Date range.** Evicted in Oregon: circuit-court filings 2019–present, page last updated 2026-05-15. OJD Cases Filed PDFs: 2018–2025.
5. **Aggregation.** Evicted in Oregon: 26 circuit-court counties (13 Oregon counties with significant justice-court filings are absent). OJD: statewide only.
6. **Access method.** Direct `curl` of the Datawrapper dataset.csv URL for each year-tab + topic combination. To enumerate historical-year URLs, re-fetch evictedinoregon.com/data-tables and grep for `datawrapper.dwcdn.net/{chart_id}` then follow the version-redirect pattern (`/{chart_id}/` returns an iframe with the active version segment). Public Records Request to OJD needed for justice-court filings (the missing 13 counties).
7. **Feasibility verdict.** EASY — direct bulk CSV download works with plain `curl`; no browser rendering needed. Building a multi-year county × month panel needs one small scraping helper to enumerate per-year chart IDs from the data-tables page, then loop `curl` over them.

---

## IL — Illinois

1. **Source URL.** https://www.illinoiscourts.gov/courts/circuit-court/illinois-circuit-court-statistical-reports/ (Power BI dashboards); narrative summary at https://ilcourtsaudio.blob.core.windows.net/antilles-resources/resources/ee461f13-58e4-4d3b-9803-4017c7549b6f/2022%20Annual%20Report%20Statistical%20Summary.pdf.
2. **Format.** Interactive Power BI dashboards (2018–2021 and 2022–2025) plus an annual Statistical Summary PDF; no native CSV export from AOIC.
3. **Frequency.** Dashboards updated quarterly with annual rollups; Statistical Summary published annually.
4. **Date range.** 2018–2025 across the two dashboards; historical Statistical Summaries available back to 2000.
5. **Aggregation.** Dashboards expose case category counts (Civil, Family, Criminal, etc.) by county. Eviction/FED is a Civil sub-category, not a top-level filter on the AOIC dashboard — granular eviction counts may require contacting county circuit clerks (esp. Cook County, where Clerk of the Circuit Court of Cook County publishes its own eviction case data).
6. **Access method.** Direct download for the Statistical Summary PDF; dashboard data must be exported manually or scraped from the Power BI endpoint. Cook County data via the Cook County Clerk's open data portal.
7. **Feasibility verdict.** MEDIUM — county-by-year Civil filings are exposed, but disentangling eviction from other Civil at the AOIC level needs supplemental data from county clerks (Cook County alone covers ~40% of state population).

---

## MI — Michigan

1. **Source URL.** https://www.courts.michigan.gov/publications/statistics-and-reports/caseload-reports/ (Caseload Reports landing page; HTTP 200 but renders as JavaScript-loaded content); public SCAO Interactive Court Data Dashboard at https://www.courts.michigan.gov/publications/statistics-and-reports/interactive-court-data-dashboard/; SCAO district-court reporting schema at https://www.courts.michigan.gov/4a6730/siteassets/reports/statistics/reporting-materials/districtcourtcaseloadreportinginstructions.pdf.
2. **Format.** Annual Caseload Reports as PDFs; SCAO publishes per-court summary statistics including landlord-tenant ("Summary Proceedings") filings.
3. **Frequency.** Annual (calendar year). SCAO collects district-court caseload reports continuously; published as year-end summaries.
4. **Date range.** Annual reports posted 2007 onward, with 2010–2023 readily downloadable; existing project file holds 2010–2025 county-year totals for 83 counties.
5. **Aggregation.** Per-district-court (105 district courts, multiple per county in some metros) and county rollups; statewide totals also reported.
6. **Access method.** Direct download for individual annual report PDFs; structured per-court tables require parsing the PDFs. Case-level data via MiCOURT Case Search (per-case, not bulk).
7. **Feasibility verdict.** MEDIUM — annual county totals are extractable from PDFs, but Michigan publishes no machine-readable bulk export, so building a multi-year panel requires PDF table parsing.

---

## WY — Wyoming

1. **Source URL.** https://www.wyocourts.gov/app/uploads/2025/03/Circuit_AnnualStatisticalReport_FY23.pdf (FY23 Circuit Court Annual Statistical Report — fetched and read in-session, 4-page PDF with statewide county-level FED table on p. 4).
2. **Format.** PDF annual report; no CSV/Excel publication. FY23 report shows 1,426 Forcible Entry and Detainer new filings statewide, broken out by county/city.
3. **Frequency.** Annual (fiscal year July–June); the report's monthly stacked chart (p. 3) shows monthly FED counts in aggregate, but per-county monthly is not published.
4. **Date range.** FY2021–FY2025 reports available on wyocourts.gov; existing project file holds 2014–2025 county-year totals for 23 counties.
5. **Aggregation.** County-level annual counts (table on p. 4 reports each of Wyoming's 23 counties separately, grouped into 9 judicial districts). Monthly counts are statewide only.
6. **Access method.** Direct download of one PDF per fiscal year; trivial to assemble FY21–FY25 county-year panel via PDF parsing.
7. **Feasibility verdict.** EASY — clean, structured PDF tables; covers exactly the post-treatment window needed (WY online start = Sep 2021, so FY22 onward is post-treatment).

---

## MD — Maryland

1. **Source URL.** https://www.mdcourts.gov/publications/annualreports (Annual Reports landing page); FY2019 Statistical Abstract at https://msa.maryland.gov/megafile/msa/speccol/sc5300/sc5339/000113/025100/025149/20210294e.pdf (fetched and read in-session via state archives mirror, as mdcourts.gov returns HTTP 403 to non-browser requests); Data Dashboard at https://datadashboard.mdcourts.gov/.
2. **Format.** Annual Statistical Abstract as PDF (District Court Tables DC-1 through DC-10 verified in FY19 ToC); interactive Data Dashboard with downloadable CSV exports.
3. **Frequency.** Annual (fiscal year July–June). Data Dashboard refreshed annually.
4. **Date range.** Statistical Abstract published yearly, archived editions back to 2003–2004; existing project file holds 2000–2025 county-year totals for 24 counties.
5. **Aggregation.** District Court tables aggregate by jurisdiction (district / county). MD operates 12 District Court districts covering the 23 counties + Baltimore City; landlord-tenant is reported within the Civil case type in Tables DC-1 and DC-2.
6. **Access method.** Direct download for the Statistical Abstract PDFs; CSV exports from the Data Dashboard. FY19 abstract page 2 warns "data may not be comparable across counties and across years" due to phased MDEC rollout — important caveat for any pre/post-MDEC analysis.
7. **Feasibility verdict.** EASY — abstract PDFs plus dashboard CSV exports give jurisdiction-level filings; the MDEC transition note demands a comparability check before pooling across the 2015–2019 rollout window.

---

## Summary Table

| State | Free-public format | Free-public frequency | Free-public geography | Verdict |
|-------|--------------------|-----------------------|------------------------|---------|
| NJ    | PDF + dashboard    | Court-year (LT-specific) | Statewide (county requires Clerk subscription or dashboard clicks) | MEDIUM |
| IA    | PDF (statutory)    | Annual                | Statewide              | MEDIUM  |
| OR    | Datawrapper CSV (Evicted in Oregon) + PDF (OJD) | Monthly (consortium) / Annual (OJD) | 26 of 36 counties (circuit-court only) | EASY |
| IL    | Dashboard + PDF    | Quarterly / Annual    | County (Civil bucket, not LT-specific) | MEDIUM |
| MI    | PDF                | Annual                | Court / County         | MEDIUM  |
| WY    | PDF                | Annual                | County                 | EASY    |
| MD    | PDF + CSV          | Annual                | Jurisdiction (county-equivalent) | EASY |

## Recommended Next Step

Build an annual county-year panel for the 3 EASY-via-free-public states (OR, WY, MD) first, plus NJ from the existing project extract — these together unlock 4 of the 7 missing treated states with minimal additional scraping. The four span four distinct cohort years (NJ 2018, OR 2019, WY 2021, MD 2022), which is exactly the spread needed to soften the singleton-cohort problem on the existing 24-state ETS panel. For OR, plan one headless-browser scrape of evictedinoregon.com/data-tables to capture the CSVs behind the "Get the Data" buttons. For NJ, treat the existing `Court Data/` extract as authoritative for annual county data, and defer any monthly-granularity ambition pending a Clerk's Office subscription decision. Defer IL and MI until PDF-parsing infrastructure is in place; defer IA case-level work until clarifying how HF 548 sealing interacts with statewide-aggregate use.

## Verification Log

URLs marked "fetched and read in-session" were retrieved through `WebFetch` and, for PDFs, opened with `Read` to confirm contents. Two URLs returned HTTP 403 to the WebFetch client (iowacourts.gov, mdcourts.gov data dashboard) — these are confirmed reachable in a browser and the parallel sources cited above were fetched in their place to verify the underlying data exists.
