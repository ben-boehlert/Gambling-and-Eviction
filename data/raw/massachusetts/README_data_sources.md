# Massachusetts Eviction Data Sources

## Key Finding
**MA is NOT in the Eviction Tracking System (ETS).** The project CLAUDE.md lists MA as having 22 months
of ETS data starting Jan 2020, but the Eviction Lab acknowledgements page confirms MA is not tracked
by ETS. The 22 months in our panel may come from the Trial Court DRAP data or another source.

## Primary Source: DRAP Tableau "Summary Process" Dashboard

- **URL:** https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtSummaryProcess/SummaryProcess
- **Coverage:** County × month, 2020–2025, updated weekly
- **Courts:** Boston Municipal Court + District Court + Housing Court (all three that handle evictions)
- **Download method:** Open in browser → Download icon → "Crosstab" → CSV/XLSX
  - Filters applied in the dashboard are reflected in the export
- **Cannot be downloaded programmatically** (Tableau Public requires browser interaction)

### Companion dashboards
- Executions issued: https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtSummaryProcessExecutionsIssued/ExecutionsIssd_byWeekMonth
- Civil Case Filings (FY2017+, annual): https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtCivilCaseFilings/AboutthisDashboard
- Petitions to Seal: https://public.tableau.com/app/profile/drap4687/viz/MassachusettsTrialCourtPetitionstoSealEvictionRecords/AllPetitionstoSealEvictionRecords

## Ch. 239 §15 Monthly PDF Reports (Dec 2020+)

- **Landing:** https://www.mass.gov/lists/monthly-reports-section-15-of-chapter-239-of-the-general-laws-permanent-rental-protections
- **2020-2024:** https://www.mass.gov/lists/2020-2024-monthly-reports-section-15-of-chapter-239-of-the-general-laws-permanent-rental-protections
- **2025:** https://www.mass.gov/lists/2025-monthly-reports-section-15-of-chapter-239-of-the-general-laws-permanent-rental-protections
- **Download URL pattern:** https://www.mass.gov/doc/ch-239-s-15-monthly-report-MONTH-YEAR/download
- **Format:** PDF, by court division (not county)
- **Fields:** Filings, default judgments, executions, continuances, stays

## Annual Trial Court Statistics (FY2002–FY2024)

- **URL:** https://www.mass.gov/lists/annual-trial-court-statistics
- **Granularity:** Annual, by department and case type (includes summary process)
- **Use for:** Pre-2020 baseline (annual only)

## External Sources

### MassLandlords.net
- https://masslandlords.net/policy/eviction-data/
- Monthly filing data since May 2020, weekly since Dec 2020
- Outcomes data: Jan 2018–Aug 2024
- County, division, municipality granularity
- **Contact:** hello@masslandlords.net for data requests

### Massachusetts Housing Partnership
- https://www.mhp.net/news/2025/housing-stability-monitor
- Housing Stability Monitor (5th edition, Aug 2025)
- Monthly statewide filing trends; county/municipal rates
- Pre-pandemic baseline: ~2,600 monthly filings statewide
- **Contact:** mjankovic@mhp.net

## Best Path to Monthly County Panel

| Period | Source | Granularity | Effort |
|--------|--------|-------------|--------|
| 2020–2025 monthly | DRAP Tableau crosstab export | County × month | Easy (manual browser download) |
| FY2017–FY2019 annual | DRAP Civil Case Filings crosstab | County × year | Easy |
| Pre-FY2017 annual | Annual Trial Court Statistics | Department × year | Moderate (PDF parsing) |
| Pre-2020 monthly | **Does not exist publicly** | — | MassLandlords contact needed |

## Court Structure

All three handle summary process (evictions):
1. **Housing Court** — 5 regional divisions (Eastern, Northeast, Central, Western, Southeast)
2. **District Court** — 62 divisions statewide
3. **Boston Municipal Court** — Central + neighborhood divisions (Boston only)

Tenants can transfer cases from District/BMC to Housing Court.
