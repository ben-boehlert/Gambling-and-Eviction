# NJ + OR Eviction Data Verification

Follow-up to [eviction_data_inventory.md](eviction_data_inventory.md) — the first-pass inventory overstated public bulk-download availability for NJ and OR. This document records what was verified by direct fetch in May 2026 and revises the verdicts accordingly.

---

## Q1. Does a public NJ endpoint expose Special Civil Part LT filings at county × month?

**No** — not as a free, bulk-downloadable file.

**Probed URL:** https://www.njcourts.gov/public/statistics (fetched).

**What it returns:** A page of links to PDF reports (Court Management Statistics, Civil Statistics, Municipal Court Statistics) and interactive dashboards (Filings and Resolutions, Backlog). The fetch confirmed verbatim: *"None found"* for landlord-tenant or Special Civil Part-specific statistical resources, and *"No CSV, Excel, or direct download links identified."* The Filings and Resolutions Dashboard has case-type radio buttons and county filters, but exposes data only via interactive click-through — no underlying JSON or CSV endpoint is documented on the page.

**Paid alternative:** https://www.njcourts.gov/sites/default/files/attorneys/ecourts/civil-report-descripts-record-layout.pdf (fetched and read, 8 pages). The Superior Court Clerk's Office sells data products via the Automated Case Management System (ACMS):

- **PAC0600** — ACMS Cases File by Docket Type, including LT docket: text file, CD-ROM media, **weekly/monthly**, parameters by docket type and date range, data 1995–present. Cost: "Contact the Superior Court Clerk's Office for an estimate."
- **PAC0600 LT — Special Civil Part Landlord Tenant Reports** — case-level (Venue, Docket #, Filed Date, Defendant): text file, **e-mail delivery**, weekly, current week only. Also a paid Clerk product.
- **PAE0602 — Landlord/Tenant Report** — listed in the report catalog with separate record layout.

These products yield case-level data (which can be aggregated to county × month or finer), but require a paid subscription via the Superior Court Clerk's Office and explicitly state: *"The Judiciary does not engage in custom programming for private interests"* (Court Rule 1:38). They are not bulk web downloads.

## Q2. NJ bulk download — supported, or interactive-only?

**Free public:** interactive-only via the Filings and Resolutions Dashboard, plus annual/court-year PDFs. No free file containing all counties × all months in a single download.

**Paid:** bulk CD-ROM / e-mail delivery of weekly/monthly case-level files from the Clerk's Office. Bulk in the sense of "all cases in a date range," but billed and shipped on physical media or by recurring e-mail, not a public URL.

## Q3. Does evictedinoregon.com or evictionresearch.net/oregon publish a directly downloadable monthly × county CSV?

**Yes — direct CSVs are served by Datawrapper, the embed provider behind every "Get the Data" button.**

**Concrete download URL (verified by `curl`, HTTP 200, 1,344 bytes):**

```
https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv
```

First two lines of the response (county × month eviction filings, statewide row + 26 counties):

```
        Total   May  Jun  Jul  Aug  Sep  Oct  Nov  Dec  Jan  Feb  Mar  Apr
Oregon  29033   2322 2258 2592 2521 2455 2660 1884 2574 2750 2241 2468 2308
```

**How the URL was found.** The evictedinoregon.com/data-tables page embeds Datawrapper visualizations rather than its own download infrastructure. Inspecting the raw HTML (via `curl -sL https://www.evictedinoregon.com/data-tables`) surfaced seven `<script src="https://datawrapper.dwcdn.net/{chart_id}/embed.js">` tags. Each chart's data is served at `https://datawrapper.dwcdn.net/{chart_id}/{version}/dataset.csv`, where `version` is discoverable by fetching `https://datawrapper.dwcdn.net/{chart_id}/` and reading the iframe `url=` parameter.

**All seven monthly tables on the page** (chart IDs from the embed.js src attributes):

| Chart ID | Topic | CSV URL pattern |
|----------|-------|-----------------|
| 0Ofed | Eviction cases filed (statewide + 26 counties × month, past 12 months) | `https://datawrapper.dwcdn.net/0Ofed/{v}/dataset.csv` |
| cbJjQ | Annual rate of eviction cases filed per 100 rental units | `https://datawrapper.dwcdn.net/cbJjQ/{v}/dataset.csv` |
| EbhgM | Reason for eviction on termination notices | `https://datawrapper.dwcdn.net/EbhgM/{v}/dataset.csv` |
| T51yH | Disparities in legal representation | `https://datawrapper.dwcdn.net/T51yH/{v}/dataset.csv` |
| lyn6N | Cases ending in default judgment of eviction | `https://datawrapper.dwcdn.net/lyn6N/{v}/dataset.csv` |
| YTFNI | Cases using stipulated agreement | `https://datawrapper.dwcdn.net/YTFNI/{v}/dataset.csv` |
| wEBS1 | Legal outcomes in eviction cases | `https://datawrapper.dwcdn.net/wEBS1/{v}/dataset.csv` |

`{v}` is currently `25` for chart 0Ofed; the version increments as the Evicted in Oregon team updates each table. The blue year-tabs on the live page presumably point at additional chart IDs for historical years (2019–prior) — those can be enumerated by re-fetching the HTML and listing all Datawrapper embeds (the seven above cover only the default "Most Recent" view).

**Other URLs probed:**

1. https://www.evictedinoregon.com/data-availability (fetched). Prose describing project sources; no download URLs.
2. https://evictionresearch.net/oregon/ (fetched). Renders Evicted in Oregon data in charts only; one Q1 2024 PDF report; no data files.
3. https://datawrapper.dwcdn.net/0Ofed/dataset.csv (fetched, **HTTP 404**) — confirms the version segment is required; unversioned path does not work.

## Q4. Finest granularity verifiably bulk-downloadable today (free, public, single file)

| State | Free public bulk | Paid / interactive options |
|-------|------------------|----------------------------|
| **NJ** | **Statewide × court-year** (Civil Statistics PDFs); county-level requires either dashboard clicks or buying the Clerk's ACMS extract | Case-level via ACMS PAC0600 (CD, weekly/monthly, 1995–present, paid); current-week LT case list via PAC0600 LT (email, paid) |
| **OR** | **County × month** (statewide + 26 counties), latest 12 months — direct CSV at `https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv` (verified, HTTP 200, 1,344 bytes). Historical years available via the year-tab Datawrapper charts on evictedinoregon.com/data-tables (chart IDs discoverable by re-fetching the page HTML and grepping for `datawrapper.dwcdn.net`). | Annual statewide PDFs from OJD (`/about/Documents/YYYY_CasesFiled.pdf`) trivially bulk-downloadable but coarser |

---

## Implications for the project

- **NJ verdict downgrades** from EASY to **MEDIUM-HARD**. The publicly downloadable free granularity is statewide × court-year. County × month requires either (a) a paid Clerk's Office subscription or (b) manual extraction from the Filings and Resolutions Dashboard, neither of which is the "easy public scrape" the prior inventory implied. The existing project file at `Court Data/county_court-issued_2000_2025_ben_update_3_19.csv` (21 NJ counties, 2013–2025 annual) likely came from the Clerk's Office and is the best NJ source currently in hand.
- **OR verdict stays EASY — no asterisk needed.** Monthly × county FED data is directly downloadable as a CSV from the Datawrapper CDN that powers evictedinoregon.com (verified URL: `https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv`). A plain `curl` works; no browser rendering required. The data covers Oregon statewide + 26 circuit-court counties for the rolling latest 12 months; historical years live behind sibling Datawrapper chart IDs on the same page and can be enumerated by a one-time HTML scrape of evictedinoregon.com/data-tables.

## Verification log

URLs fetched in this session for this verification round:

1. https://www.njcourts.gov/public/statistics — re-fetched; confirms no LT-specific or bulk-download endpoint.
2. https://www.evictedinoregon.com/data-availability — fetched; describes resources without exposing URLs.
3. https://www.evictedinoregon.com/data-tables — fetched; confirms per-table "Get the Data" download mechanism, JS-rendered URL.
4. https://evictionresearch.net/oregon/ — fetched; rendered charts only, one Q1 2024 PDF report; no data files.
5. https://www.njcourts.gov/courts/civil/special-civil — fetched; HTTP 404 (URL is wrong; no LT statistics page exists at this path).
6. https://www.njcourts.gov/sites/default/files/attorneys/ecourts/civil-report-descripts-record-layout.pdf — fetched and read pages 1–8; full description of paid ACMS Civil Reports including PAC0600 LT.
7. https://www.evictedinoregon.com/data-tables — re-fetched raw HTML via `curl`; grep surfaced seven Datawrapper chart embeds (chart IDs: 0Ofed, cbJjQ, EbhgM, T51yH, lyn6N, YTFNI, wEBS1).
8. https://datawrapper.dwcdn.net/0Ofed/dataset.csv — `curl` returned HTTP 404; confirms unversioned path is not the data endpoint.
9. https://datawrapper.dwcdn.net/0Ofed/ — `curl` returned a 241-byte HTML iframe redirect to `/0Ofed/25/`, revealing the version segment.
10. https://datawrapper.dwcdn.net/0Ofed/25/dataset.csv — `curl` returned HTTP 200, 1,344 bytes, tab-separated content: header row (Total, May, Jun, ..., Apr) plus 27 data rows (Oregon statewide + 26 counties). Confirmed direct bulk download of county × month FED filings.
