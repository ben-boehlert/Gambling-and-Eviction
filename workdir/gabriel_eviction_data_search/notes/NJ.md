# NJ — Research Note

## Queries run

- "New Jersey Courts landlord tenant filings statistics monthly vicinage njcourts.gov"
- "njcourts.gov landlord tenant dashboard filings download excel vicinage"
- "njcourts.gov special civil annual report caseload landlord tenant filings 2024"

## Candidates considered

| URL | Verdict |
|---|---|
| https://www.njcourts.gov/public/statistics | **Winner** — official AOC stats hub with Tableau dashboards + PDF reports |
| https://www.njcourts.gov/self-help/landlord-tenant | Procedural / citizen-facing, not statistical |
| https://www.njcourts.gov/attorneys/directives/15-23 | Directive changing filing procedure (Aug 2023) — relevant as a series break indicator |
| https://www.njcourts.gov/notices/notice-and-order-transfer-certain-landlord-tenant-cases-essex-vicinage-...| Administrative transfer notice; documents cross-vicinage case movement |

## Why winner

`/public/statistics` is the only NJ Judiciary hub consolidating (a) monthly interactive dashboards with landlord-tenant filterable by vicinage and (b) monthly PDF "Court Management Statistics" with Special Civil Part breakouts. Court year runs July-June; dashboards update monthly.

## Preliminary assessment

| Dimension | Value |
|---|---|
| Finest frequency | Monthly |
| Geographic level | 15 vicinages (cover 21 counties) and statewide |
| Coverage years | July 2004 - June 2025 (PDF archive); dashboards cover multiple court years |
| Statewide vs partial | Statewide (all 15 vicinages, all L/T cases flow through Special Civil Part) |
| Access method | Tableau dashboard crosstab export + PDF download |
| Data format | XLSX/CSV via Tableau crosstab export; PDFs for historical |
| **estimated_effort_to_acquire** | **moderate** |

## What a downstream analyst needs to do

1. Navigate to the Tableau "Filings and Resolutions" dashboard, filter for Special Civil Part → Landlord/Tenant case type, select each vicinage × month cell, and export crosstab to CSV. Possibly scriptable via Tableau URL parameters but likely requires Selenium for a full panel.
2. Cross-walk 15 vicinages → 21 counties (vicinages are the native unit; a 1:1 county map is not always possible since some vicinages contain multiple counties).
3. For pre-dashboard history (before whatever year the current dashboard begins), parse monthly "Court Management Statistics" PDFs (Jul 2004-Jun 2025 available) — tabular extraction via `tabula` or similar.
4. Handle the Aug 2023 Directive 15-23 regime change (new LCIS requirement, conclusion of mandatory case management conferences) as a potential series break.

## Red flags

- No advertised CSV/API bulk endpoint — requires either dashboard scraping or PDF parsing.
- Vicinage-level, not county-level, reporting is the native granularity.
- 2023 procedural reforms may create comparability issues pre/post Aug 2023.
- COVID moratoria (NJ had particularly long eviction moratorium through Dec 2021 / ERA rollout) create large 2020-2022 anomaly — consistent with our existing COVID exclusion.
