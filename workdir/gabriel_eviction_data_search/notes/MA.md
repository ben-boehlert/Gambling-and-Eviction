# MA — Research Note

## Queries run

- "Massachusetts Trial Court Housing Court summary process filings statistics mass.gov"
- "mass.gov residential summary process dashboard monthly county eviction data 2024 2025"
- "public.tableau.com Massachusetts summary process eviction dashboard trial court"

## Candidates considered

| URL | Verdict |
|---|---|
| https://www.mass.gov/info-details/civil-court-reports-and-dashboards | **Winner — primary landing** for state judiciary civil data |
| https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtSummaryProcess/SummaryProcess | **Winner — Tableau dashboard**, county × month 2020-2025, weekly updates |
| https://www.mass.gov/doc/ch-239-s-15-monthly-report-november-2025/download | Monthly PDF (statutory), court-dept × month, Jan 2024+ |
| https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtSummaryProcessExecutionsIssued/... | Executions issued dashboard (complement — evictions actually carried out) |
| https://masslandlords.net/policy/eviction-data/ | Third-party compilation — mirrors state data, useful as cross-check |
| https://www.mass.gov/lists/trial-court-statistics-for-fiscal-year-2023 | FY stats 2002-2023 — annual, broad case types |

## Why winner

The Tableau "Summary Process" dashboard IS the closest thing to a bulk data feed: residential summary process filings 2020-2025 by year, month, county, with crosstab export to XLSX/CSV. The Ch. 239 s. 15 monthly PDF reports are the authoritative complement (statutorily mandated) but are court-department, not county, and start Jan 2024.

## Preliminary assessment

| Dimension | Value |
|---|---|
| Finest frequency | Monthly (Tableau dashboard); also weekly visible on executions dashboard |
| Geographic level | County (14 counties); court department (3) on PDF |
| Coverage years | 2020-2025 at county×month (Tableau); 2002-2023 FY totals; 2024+ for statutory monthly PDF |
| Statewide vs partial | Statewide — all three departments (District, Housing, Boston Municipal) included |
| Access method | Tableau crosstab export (CSV/XLSX); PDF for monthly statutory report |
| Data format | XLSX/CSV from Tableau |
| **estimated_effort_to_acquire** | **easy** (2020+); **moderate** (2016-2019 requires FY stats + backing out) |

## What a downstream analyst needs to do

1. Open Tableau Summary Process dashboard → download crosstab → save as CSV for county × month 2020-present.
2. For 2016-2019, use the FY trial court statistics pages (each year's "Trial Court Statistics for Fiscal Year YYYY" list page), extract annual totals by case type, and allocate to months using a reasonable seasonality pattern — or better, request monthly data from Dept of Research and Planning (drap4687 is their Tableau handle; `research@jud.state.ma.us` is the public research address).
3. Decide venue treatment: MA has three overlapping trial court departments (District, Housing, Boston Municipal) all hearing summary process. Tableau dashboard sums across departments; if you want only Housing Court (some researchers prefer this since Housing Court specializes), you'd need FY stats or a FOIA.
4. Handle executions vs filings distinction — MA tracks both, and the project's CLAUDE.md already flags this as a pipeline-point issue.

## Red flags

- **Pre-2020 monthly data not publicly gridded.** Our gambling-legalization treatment dates in MA are 2022 (retail) / 2023 (online) — so post-treatment 2020-2025 coverage is strong, but pre-treatment monthly county panel for 2016-2019 requires FOIA or custom extraction.
- Overlapping court departments complicate dedup. Researcher must decide policy: unique case ID join, sum across depts, or single-dept filter.
- Tableau is JS-heavy — automated scraping requires Selenium or Tableau API.
- Eviction moratorium period (Apr 2020 - Oct 2020, with extensions) creates sharp COVID discontinuity — consistent with project's COVID exclusion 2020-03 through 2022-03.
