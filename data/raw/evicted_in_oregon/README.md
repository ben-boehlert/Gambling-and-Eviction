# Evicted in Oregon — Datawrapper extracts (May 2026)

Source: https://www.evictedinoregon.com/ (data by Lisa Bates, Portland State University; underlying data from Oregon Judicial Department circuit-court records).

## Files

- **`oregon_statewide_monthly_2020_2026.tsv`** — Statewide circuit-court eviction filings by month, Jan 2020 through Jul 2026 (78 monthly rows). Refreshed 2026-09-14 from Datawrapper chart `l8e1N`, version 94. The publisher revised Apr 2026 from 2,308 to 2,319; dashboard data are mutable.
  - Direct URL: https://datawrapper.dwcdn.net/l8e1N/91/dataset.csv
  - Format: tab-separated, columns `Month` (MM/DD/YYYY, always 1st of month), `Total`.

- **`oregon_county_monthly_latest12mo.tsv`** — County × month circuit-court eviction filings for the most-recent rolling 12 months (Aug 2025 – Jul 2026). 30 counties plus Oregon statewide total. Refreshed 2026-09-14 from Datawrapper chart `0Ofed`, version 33. An asterisk denotes a county where justice-court filings are also possible.
  - Direct URL: https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv
  - Format: tab-separated, columns are months (May–Apr), rows are county names.

## What is NOT here

- **Historical county × month data (2020-01 through prior to the current rolling window).** The data-tables page exposes only the latest-12-month version of the county × month view; prior years are presumably behind year-tabs that load different Datawrapper chart IDs via JavaScript, and those chart IDs are not in the static HTML. To assemble a full county × month × year panel covering 2020–2026, options are:
  1. Visit the data-tables page in a browser, click each year tab, and capture the embed chart_id from devtools, then `curl` each one's `dataset.csv`.
  2. Email the Evicted in Oregon team for a clean export of the underlying county-monthly dataset.
  3. File a Public Records Request with the Oregon Judicial Department for case-level FED filings.
- **Justice court filings** for the 13 Oregon counties absent from the circuit-court data (Baker, Clackamas, Douglas, Gilliam, Grant, Harney, Linn, Malheur, Marion, Morrow, Sherman, Tillamook, Wheeler).
- **Pre-2020 data.** Evicted in Oregon's series begins Jan 2020. For Oregon's online gambling treatment date of October 2019, there is essentially no pre-treatment window from this source alone.

## Official Oregon Judicial Department pre-period PDFs

`../monthly_expansion/or_raw/ojd_cases_filed_pdfs/` contains OJD's official
`2018CasesFiled.pdf` and `2019CasesFiled.pdf`, downloaded on 2026-09-14 from
the OJD statistics site. Unlike the Evicted in Oregon dashboard, each PDF has
monthly `Landlord Tenant` counts: statewide on page 1 and circuit-court rows
on subsequent pages. The usable untreated period is all of 2018 and January
through September 2019; Oregon online sports betting began in October 2019.
The tidy statewide transcription is at
`../monthly_expansion/or_raw/or_ojd_lt_state_month_2018_2020.csv`. These
counts have not yet been merged into an analysis panel. Reconcile the 2020
OJD and dashboard definitions before doing so.

## Versioning

Datawrapper URLs include a version segment that increments each time the chart is republished. The values above are valid as of May 2026; re-resolve by fetching `https://datawrapper.dwcdn.net/{chart_id}/` and reading the iframe redirect target.
