# MI — Research Note

## Queries run
- "Michigan SCAO State Court Administrative Office caseload statistics landlord tenant eviction filings data"
- "Michigan courts caseload report statistics district court landlord tenant annual report 2023"
- '"courts.michigan.gov" caseload report landlord tenant annual CSV data download'
- 'Michigan courts "caseload and caseflow management" landlord tenant monthly filings report'

## Candidate URLs considered
1. **https://www.courts.michigan.gov/publications/statistics-and-reports/caseload-reports/** — SCAO caseload reports landing page. **WINNER (primary).**
2. **https://www.courts.michigan.gov/publications/statistics-and-reports/caseload-reports/2023-caseload-reports/** — 2023 reports index (per-county PDF reports).
3. **https://www.courts.michigan.gov/publications/statistics-and-reports/interactive-court-data-dashboard/** — SCAO Interactive Court Data Dashboard; useful for public dashboard checks of incoming caseload and county/court filters, but not a machine-readable bulk export.
4. **https://poverty.umich.edu/research-funding-opportunities/data-tools/michigan-evictions/** — U. Michigan Poverty Solutions / Goodspeed et al., used SCAO/JDW microdata via research agreement. (Secondary / research precedent.)
5. **https://www.courts.michigan.gov/49f7cb/siteassets/reports/special-initiatives/justice-for-all/improving-evictions-in-michigan-report-and-recs.pdf** — Justice for All report using Michigan Judicial Data Warehouse (2010–2023).
6. **https://www.washtenaw.org/954/Landlord-Tenant-Filings** — Washtenaw County posts monthly LT filing counts.
7. **https://www.oakgov.com/government/courts/circuit-court/about/caseload-statistics** — Oakland County caseload stats.

## Why winner
SCAO is the state judiciary's administrative office. The caseload reports page is the only statewide, official, publicly-published source. No underlying microdata is posted (that lives in the restricted Judicial Data Warehouse).
The Interactive Court Data Dashboard is an official public SCAO view for checking incoming caseload by filters such as court/county, but it should be treated as a dashboard source rather than a downloadable statewide microdata file.

## Assessment
- **Finest frequency:** ANNUAL (SCAO). Monthly exists in the JDW but is not public.
- **Geographic level:** district court (one or more per county) — maps to county with a crosswalk
- **Coverage years:** 2016+ confirmed via SCAO caseload reports page
- **Statewide:** YES
- **Access method:** self-service PDF download per county
- **Format:** per-county PDF (one PDF per county per year; not machine-readable)
- **Estimated effort to acquire:** MODERATE-to-HARD for annual panel (need to parse ~83 county PDFs × ~9 years = ~750 PDFs); HARD for monthly panel (requires SCAO data-sharing agreement for JDW access).

## What a downstream analyst needs to do
1. **For annual panel:** scrape/extract LT filing counts from each county PDF in the SCAO caseload reports page, 2016–present. Write a parser targeting the "District Court — Civil" or "Summary Proceedings / Landlord-Tenant" table.
2. **For monthly panel:** apply for a data-sharing agreement with SCAO to access the Judicial Data Warehouse. U. Michigan Poverty Solutions has done this; so can other researchers. This is a months-long process.
3. **Supplement with big-county portals:** Washtenaw and Oakland publish monthly stats; 36th District Court (Detroit) likely has its own reporting. Could get monthly coverage for 3-5 large counties covering majority of LT volume without JDW.

## Red flags
- No machine-readable statewide file — all public data is PDF.
- JDW access requires a formal data-sharing agreement; sometimes limited to MI-affiliated researchers.
- Michigan has ~100 district courts (83 counties), so parsing is tedious.
- LT is DISTRICT court jurisdiction (not circuit), so "circuit court" reports will not have it.

## Note for Gambling-and-Eviction
- MI is NOT in the ETS monthly panel.
- MI already has ANNUAL county data in our project's compiled Court Data file (per CLAUDE.md).
- MI legalized online sports betting January 2021.
- Best routes:
  1. **Annual panel (cheap):** use existing Court Data annual file for MI, combine with ETS states aggregated to annual → robustness check.
  2. **Monthly panel (expensive):** apply for SCAO JDW data-sharing agreement; ~6–12 month timeline.
  3. **Big-county monthly (medium):** scrape Washtenaw, Oakland, and 36th District (Detroit) monthly LT filings for a 3-county treated-intensity subpanel.
