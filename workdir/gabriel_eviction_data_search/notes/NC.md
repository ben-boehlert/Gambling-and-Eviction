# NC — Research Note

## Queries run

- "North Carolina AOC summary ejectment caseload monthly county nccourts.gov statistics"
- "data.nccourts.gov dataset download summary ejectment civil case filings county"
- "nccourts.gov civil overall caseload summary ejectment monthly Excel download"
- "nccourts.gov statistical caseload report ASJ summary ejectment annual fiscal year county Excel"

## Candidates considered

| URL | Verdict |
|---|---|
| https://www.nccourts.gov/about/data-and-statistics | **Winner — primary landing** for NC AOC statistical publications |
| https://data.nccourts.gov/pages/dashboard/ | **Winner — interactive dashboard** with civil issue breakout (SUME) |
| https://data.nccourts.gov/explore/dataset/caseload-inventory/ | Caseload inventory dataset (fiscal year, county) |
| https://data.nccourts.gov/explore/dataset/caseload-ranked-event/ | Civil issue type rankings — SUME explicitly tracked |
| https://data.nccourts.gov/explore/dataset/caseload-disposition/ | Disposition-focused companion dataset |
| https://www.nccourts.gov/documents/publications/civil-overall-caseload-activity-report | PDF — civil filed/pending/disposed by county, fiscal year |
| https://www.nccourts.gov/documents/publications/civil-issue-filingsorder-results | PDF — civil issue (SUME) by county |
| https://www.nccourts.gov/documents/publications/north-carolina-courts-statistical-and-operational-reports | Historical archive, fiscal-year granularity |

## Why winner

The `data.nccourts.gov` OpenDataSoft portal is the modern canonical source and exposes CSV/JSON/API access. SUME is an explicit civil issue category. The Case Statistics Dashboard has a dedicated Civil section with summary ejectment filed/disposed/pending. The PDFs in `nccourts.gov/about/data-and-statistics` provide longer historical reach.

## Preliminary assessment

| Dimension | Value |
|---|---|
| Finest frequency | Fiscal year (July 1 - June 30) in public portal. MONTHLY county-level Excel files exist per the project's existing CLAUDE.md, but are not advertised on the dashboard — likely from a predecessor "Civil Overall Caseload Activity Report" monthly series |
| Geographic level | County (100 counties) + statewide |
| Coverage years | FY2019-20 through FY2023-24 confirmed in public portal; statistical archive goes back further |
| Statewide vs partial | Statewide — all 100 counties |
| Access method | OpenDataSoft CSV/JSON/API; PDFs |
| Data format | CSV, XLSX, JSON, ODS via OpenDataSoft |
| **estimated_effort_to_acquire** | **easy** (fiscal year); **moderate** (monthly — requires locating the predecessor Excel series or direct AOC contact) |

## What a downstream analyst needs to do

1. **For fiscal-year county panel:** query `caseload-ranked-event` dataset via OpenDataSoft API filtering on civil_issue == "Summary Ejectment" (code SUME). Export CSV. Aggregate to county × fiscal-year.
2. **For monthly county panel (preferred for DiD timing):**
   - Check whether the existing repo's NC monthly data at `data/raw/monthly_county_data_download.csv` already covers this; the project CLAUDE.md notes "NC has monthly breakdowns in source files (and NC is already in the ETS panel)."
   - Otherwise, contact NC AOC Research, Policy, and Planning Division (research@nccourts.org) — they historically produce a monthly "Civil Overall Caseload Activity Report" in Excel with SUME broken out by county.
3. Convert fiscal years → calendar months if using dashboard data (e.g., FY2020 = July 2019 - June 2020).
4. Note that SUME in NC is a SMALL CLAIMS (Magistrate) filing — appeals go to District Court. Counts should reflect initial small-claims filings for consistency with other states' "filings" measures.

## Red flags

- **Fiscal year is the default granularity in the modern dashboard.** Monthly data exists (per project memory) but is not a first-class product. Confirm availability.
- New eCourts system rolled out to NC pilot counties starting 2023 (Harnett, Lee, Johnston, Wake, Mecklenburg later) — may create discontinuities or data-model changes in the caseload statistics.
- SUME counts only the initial small-claims magistrate filing; appeals to District Court (CVM/CVD case types) are separate and not always counted. Typical eviction studies use the initial filing.
- NC is NOT one of the states missing from the project's ETS panel — it is in the panel. So this scouting note is most useful as a CROSS-VALIDATION source against ETS rather than as new coverage.
