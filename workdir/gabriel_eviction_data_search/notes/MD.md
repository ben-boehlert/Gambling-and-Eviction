# MD — Research Note

## Queries run

- "Maryland Judiciary District Court landlord tenant statistical abstract mdcourts.gov case statistics"
- "Maryland District Court eviction dashboard FPR failure to pay rent monthly county opendata.maryland.gov"
- "Maryland District Court Landlord/Tenant Case Activity Report monthly county"

## Candidates considered

| URL | Verdict |
|---|---|
| https://opendata.maryland.gov/Housing/District-Court-of-Maryland-Eviction-Case-Data/mvqb-b4hf | **Winner** — event-level dataset, 2023-present, county+ granularity, Socrata API |
| https://www.mdcourts.gov/dashboard/about | MD Judiciary Data Dashboard — phased MDEC rollout; L/T dispositions only FY25+ |
| https://www.mdcourts.gov/publications/annualreports | Annual Statistical Abstracts (PDFs) — longer history, coarser |
| https://www.courts.state.md.us/district/about | District Court about page — references L/T Case Activity Report |
| District Court of Maryland Landlord/Tenant Case Activity Report | Manual monthly compilation — longer history, used by MD itself as internal reporting |

## Why winner

The Socrata dataset is the richest public source: 662K event-level records with case number, county, location, case type, event date, event type, and evicted date. Bulk CSV/API download. Updates roughly monthly. 2022 MD statute mandates its existence.

## Preliminary assessment

| Dimension | Value |
|---|---|
| Finest frequency | Daily (event-level dates) — aggregate to month/county trivially |
| Geographic level | County (23 counties + Baltimore City) + District Court location |
| Coverage years | Jan 2023 - Feb 2026 (statute-mandated start date 2023-01-01) |
| Statewide vs partial | Statewide — all 12 judicial districts / 33 court locations |
| Access method | Socrata CSV bulk + API (JSON/OData) + one-click download |
| Data format | CSV, JSON, XML via Socrata |
| **estimated_effort_to_acquire** | **trivial** (2023+); **moderate** (pre-2023 cross-reference) |

## What a downstream analyst needs to do

1. `wget` or API query the full CSV from Socrata (single request, ~50 MB).
2. Filter Event Type == petition filing, aggregate by (County, year, month) → done.
3. For the 2016-2022 period NOT covered by the Socrata dataset, either:
   - Extract monthly L/T Case Activity Report PDFs from the Maryland Judiciary Annual Statistical Abstracts (longer history, manually compiled, different methodology — MD explicitly warns the two sources do not match).
   - FOIA the AOC's internal monthly reporting data if higher fidelity needed.
4. Decide how to treat the "Failure to Pay Rent" vs "Tenant Holding Over" vs other case types — FPR dominates (96%) but researchers may want to aggregate all or use FPR-only.

## Red flags

- **Pre-2023 gap.** The Socrata dataset starts 2023-01-01. For a 2016-present panel you need to stitch in monthly L/T Activity Reports from PDFs, which use different methodology (manual compilation by jurisdiction, sheriff-reported executions in some counties). Maryland Judiciary explicitly warns the two sources do not match.
- Clerk data entry lag — recent months may undercount; evictions trickle in on subsequent reports.
- MDEC (e-courts) rollout was phased across counties; coverage completeness may differ by county in early 2023.
- MD is online-gambling treated (Nov 2022) → Socrata dataset starts ~2 months post-treatment. Pre-treatment period entirely relies on the older L/T Activity Report series.
