# IL — Research Note

## Queries run
- "Illinois AOIC annual statistical summary landlord tenant eviction filings by county"
- '"Illinois Courts" statistical summary PDF "forcible" OR "eviction" filings county 2023'
- "Illinois circuit court statistical dashboard Power BI eviction county filings"
- 'Cook County "landlord tenant" OR eviction filings data download open data portal monthly'

## Candidate URLs considered
1. **https://www.illinoiscourts.gov/courts/circuit-court/illinois-circuit-court-statistical-reports/** — AOIC circuit court statistical reports landing page with Power BI dashboards (2018–2021 and 2022–2025). **WINNER (primary).**
2. **https://app.powerbigov.us/view?r=eyJrIjoiZGE3NzljYmItYTBmZC00OGI2LTliYTgtYzY5ZjI0N2U0MWYxIi...** — "Statewide Landlord Tenant Eviction Dashboard" (Power BI gov tenant). Appears in search but not linked from AOIC reports page directly. Secondary.
3. **2023 Annual Report Statistical Summary PDF** — https://ilcourtsaudio.blob.core.windows.net/antilles-resources/resources/2e8fe39f-d040-47ee-a2b5-d53880fccb19/2023%20Annual%20Report%20Statistical%20Summary.pdf
4. **https://eviction.lcbh.org/data** — Chicago Evictions (LCBH) Cook County dashboard, monthly, 2010–present. Not government-sourced but compiled from circuit court records.
5. **https://evictionresearch.net/illinois/** — UC Berkeley + Legal Aid Chicago, Cook County only, 2012–2022.

## Why winner
AOIC is the state judiciary's Administrative Office, publishes quarterly (by county) + annual statistical summaries, and hosts Power BI dashboards. It is the official, statewide, government source.

## Assessment
- **Finest frequency:** QUARTERLY at county level (AOIC); MONTHLY for Cook County via LCBH or Cook County Circuit Court dashboard
- **Geographic level:** county (102 IL counties)
- **Coverage years:** 2018–present (AOIC dashboards); pre-2018 requires digging older PDFs
- **Statewide:** YES for AOIC
- **Access method:** Power BI dashboard (with in-app export) + PDF annual reports
- **Format:** dashboard (Power BI tiles; raw CSV available via dashboard export button); PDF for annual narrative summaries
- **Estimated effort to acquire:** MODERATE — Power BI dashboards allow export but require navigating the UI; no public CSV endpoint; may need to scrape dashboard or request CSV from AOIC.

## What a downstream analyst needs to do
1. Open the 2022–2025 AOIC Power BI dashboard, navigate to Civil caseload, filter to Eviction case type.
2. Export each county-quarter slice to CSV using Power BI's export-data feature.
3. Alternatively, extract tables from the PDF Annual Statistical Summaries (2018–present).
4. For Cook County monthly data, use LCBH's Chicago Evictions portal or request monthly tabulations from the Circuit Court of Cook County Clerk.
5. Merge to build a county-quarter (and partial county-month for Cook) panel.
6. Note: IL law seals eviction records filed during COVID (Mar 2020–?), which may affect counts in that window.

## Red flags
- Power BI dashboards are not always friendly to bulk export; may require scraping DAX queries or manual clicking.
- Eviction case type was renamed from "Forcible Entry and Detainer" to "Eviction" in 2018 statute — schema continuity check needed for pre-2018.
- COVID-era record sealing law may depress visible filing counts in 2020–2022.
- Cook County has its own data flow (separate from AOIC); LCBH appears to be the most complete Cook County monthly source.
- "Statewide Landlord Tenant Eviction Dashboard" URL found in search but unclear ownership (may be AOIC, may be a partner org) — needs verification.

## Note for Gambling-and-Eviction
- IL is NOT in the ETS monthly panel.
- IL legalized online sports betting March 2020 (online launch was right at COVID onset, which complicates pretrends).
- AOIC quarterly data (2018–present) gives ~8 pre-treatment quarters (2018Q1–2019Q4) and ~24 post-treatment quarters — adequate for a quarterly state-panel analysis.
- Adding IL to the analysis at quarterly (not monthly) frequency is the realistic route.
