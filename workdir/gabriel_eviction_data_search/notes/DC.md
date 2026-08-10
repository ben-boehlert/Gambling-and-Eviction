# DC — Research Note

## Queries run
- "DC Superior Court landlord tenant filings statistics open data opendata.dc.gov"
- '"opendata.dc.gov" superior court cases landlord tenant dataset'
- '"DC Courts" statistics annual report landlord tenant filings'
- '"DC Courts" "data request" landlord tenant filings monthly eviction research'

## Candidate URLs considered
1. **https://portal-dc.tylertech.cloud/Portal** — DC Courts Odyssey portal (case-level lookup, no bulk). Required scraping source for recent research.
2. **https://www.dccourts.gov/about/organizational-performance/annual-reports** — DC Courts annual reports, narrative PDFs with aggregate LT filing counts (2016–2023). **WINNER (primary, such as it is).**
3. **https://www.dccourts.gov/superior-court/superior-court-divisions/civil-division/landlord-and-tenant** — Landlord-Tenant Branch description page (no data).
4. **https://ota.dc.gov/page/scheduled-evictions** — DC Office of the Tenant Advocate's monthly aggregate of *scheduled evictions* (different concept from filings).
5. **https://www.newamerica.org/future-land-housing/briefs/dc-eviction-filings-june-through-october-2025/** — 2025 brief documenting DC data access problem; used custom scraper.
6. **https://opendata.dc.gov/** — DC's open data portal; no court/eviction dataset surfaced in search.

## Why winner
DC does NOT publish bulk eviction data publicly. The only statewide official numbers come from the DC Courts Annual Reports (year-end aggregate filing counts, PDF narrative). The Odyssey portal provides per-case access but no bulk export. The New America / January Advisors brief explicitly documented this gap in 2025.

## Assessment
- **Finest frequency (public):** ANNUAL via DC Courts Annual Reports. MONTHLY for *scheduled evictions* via OTA (not filings).
- **Finest frequency (scrapable):** case-level (real-time) from the Odyssey portal, but only going back as far as the portal retains records (~several years).
- **Geographic level:** DC-wide (single jurisdiction). No intra-DC breakdown in any public source.
- **Coverage years:** 2016–2023 via annual reports; 2024 annual report not yet published as of search date.
- **Statewide:** YES (DC is a single court system)
- **Access method:** annual PDF (aggregate), Odyssey portal scrape (case-level), formal data request to DC Courts Office of Research (microdata), OTA monthly reports (scheduled evictions only).
- **Format:** PDF (annual), HTML portal (per-case), unknown (data request).
- **Estimated effort to acquire:** HARD for monthly filing counts. Requires either scraping Odyssey (legal/ToS review needed) or formal data request with application process.

## What a downstream analyst needs to do
For monthly DC filing counts, options ranked by feasibility:
1. **Request from DC Courts Office of Research** using Form A (Public). Multi-week turnaround; success not guaranteed.
2. **Partner with Eviction Lab** — they already have DC data in the national eviction database. Request their DC extract.
3. **Scrape Odyssey portal** — technically feasible (see January Advisors/New America), but review DC Courts ToS and portal rate limits before doing so.
4. **Extract annual totals from DC Courts Annual Reports 2016–2023** — easy but only annual frequency.

## Red flags
- No bulk eviction data is accessible publicly (explicit per 2025 New America brief).
- DC Courts Annual Reports are PDF narrative, not structured tables — may require manual extraction.
- OTA's "scheduled evictions" ≠ "filings" — different concept, don't confuse.
- DC is a single observation (one jurisdiction), so it contributes only 1 cluster to a state-panel analysis — marginal analytical value for the cost.
- COVID-era DC had extended eviction moratoria with eligibility complexity — counts during 2020–2022 may be atypical.

## Note for Gambling-and-Eviction
- DC legalized online sports betting May 2020 (GambetDC, DC Lottery monopoly; switched to FanDuel partnership 2024).
- DC is NOT in the ETS monthly panel.
- Given the single-cluster limitation and the access difficulty, DC is **low priority** for panel expansion. Better value as a descriptive case study or a qualitative supplement to the main state-panel analysis.
- If included, easiest path is Eviction Lab's DC extract (if available) or a targeted data request to DC Courts.
