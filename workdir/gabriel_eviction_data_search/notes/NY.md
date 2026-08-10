# NY — Research Note

## Queries run
- "NY OCA Monthly Activity Detail landlord tenant filings download nycourts.gov"
- "NY OCA housing data coalition XML files monthly landlord tenant five years download"

## Candidate URLs considered
1. **https://ww2.nycourts.gov/landlord-tenant-data-34621** — official OCA landlord-tenant data page with XML downloads. **WINNER (primary).**
2. **https://ww2.nycourts.gov/lt-evictions-33576** — Statewide Landlord-Tenant Eviction Dashboard, updated weekly. (Secondary / supplementary.)
3. **https://github.com/housing-data-coalition/oca** — HDC ETL that ingests the OCA XML and parses to CSV (NYC only). Useful as parser code; not a data source itself.
4. **https://github.com/nycdb/nycdb/wiki/Dataset:-OCA-Housing-Court-Records** — data dictionary for the OCA XML schema.

## Why winner
NYCOURTS.GOV hosts the official case-level XML feed, updated monthly, covering all local civil courts statewide (excluding Town & Village). This is the authoritative, statewide, case-level, government-published dataset — exactly what we want.

## Assessment
- **Finest frequency:** case-level with exact filing dates → can build daily or monthly
- **Geographic level:** case-level with court-of-filing identifier → maps to county
- **Coverage years:** rolling 5-year window (~2021–present as of April 2026)
- **Statewide:** YES (all local civil courts, excludes Town & Village justice courts)
- **Access method:** self-service XML download (no FOIL)
- **Format:** nested XML (HDC has published Python ETL to turn it into 11 relational CSVs)
- **Estimated effort to acquire:** EASY (download + run HDC's ETL or write a parser)

## What a downstream analyst needs to do
1. Download the XML bundle from nycourts.gov (one or more years per file).
2. Use the HDC ETL (github.com/housing-data-coalition/oca) or write an XML parser keyed to the NYCDB data dictionary.
3. Join filing events to court identifiers → county crosswalk.
4. Aggregate case-filing events to state-month counts.
5. For pre-2021 years, need to FOIL OCA for archived XML OR use HDC's historical archive (NYC only, extends back further).

## Red flags
- Rolling 5-year window means pre-2021 is not self-service — have to FOIL for deep historical data.
- Town & Village courts are excluded — some rural/suburban LT filings are missed. Size of this gap not documented; likely <5% statewide.
- Data is de-identified but this doesn't affect count construction.

## Note for Gambling-and-Eviction
NY is already in ETS. The OCA feed offers: (a) case-level granularity (could study case-outcome heterogeneity), (b) longer post-treatment coverage (NY legalized online sports betting Jan 2022, so 2022–present is available). For state-month aggregate filing counts, ETS is likely sufficient, but OCA is the backstop for validating ETS numbers and for filling any ETS coverage gaps.
