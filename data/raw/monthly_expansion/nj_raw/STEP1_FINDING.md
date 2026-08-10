# NJ Step-1 Finding: What's actually in the cman / gray PDFs

**Date:** 2026-06-03
**Files inspected:** `cman2306.pdf` (FY23 Court Management Statistics, 65 pp), `cman2511.pdf` (Nov 2025 monthly, 65 pp), `gray2306.pdf` (FY23 Civil Statistics, 93 pp)
**Question:** Do these PDFs contain monthly Special Civil Part Landlord-Tenant filings by vicinage / county, removing the need to build a parser or file OPRA?

## Verdict: NO — none of the on-disk PDFs gives monthly Tenancy by vicinage directly.

But the cman series DOES make it recoverable by differencing YTD values. And the FY summaries we already have on disk already deliver annual Tenancy by vicinage for FY16–FY24 with no extra work.

## What each PDF actually contains

### `cman` — Court Management Statistics

Two report types share the same 65-page template:
- **Monthly issue** (e.g., `cman2511.pdf` = "November 2025"): YTD-through-month figures
- **Annual issue** (e.g., `cman2306.pdf` = "June 2023" = end of FY23): FY-total figures

Both contain:
1. **Page 7 — Monthly Clearance Summary**. One page, one month, all 21 vicinages × case category. The Special Civil column is **aggregate** (Auto + Contract + Other + Small Claims + Tenancy combined). Not useful for tenancy alone.
2. **Pages 8–49 — County Profiles** (one 2-page spread per vicinage). The Caseload Profile table on each has a **Tenancy** line with columns:
   `Added | Resolved | (clearance) | (clearance %) | (inventory) | (inv %) | (backlog) | (bl %) | Active Pending | Backlog/100 Monthly Filings`
   "Added" = cumulative filings **from the start of the fiscal year (July 1) through the reporting month**.

So:
- `cman2306.pdf` line `Tenancy 7,569 …` → 7,569 Tenancy filings in Bergen, FY23 total.
- `cman2511.pdf` line `Tenancy 1,562 …` → 1,562 Tenancy filings in Atlantic for July–November 2025 cumulative.

**Implication for monthly:** Monthly Tenancy by vicinage = `cman[YYMM].Added` − `cman[YY(MM−1)].Added`, with July's value standing alone. This is recoverable — but only if we have every monthly PDF.

### `gray` — Civil Statistics (DEAD END for Tenancy)

The `gray` series is about Superior Court Civil Division (Tracks 1–4: contracts, torts, malpractice, etc.). "Special Civil Part" is a **separate court** and is **not** covered. "Tenancy" appears once in the entire 93-page `gray2306.pdf`, only in the abbreviations list as a member of "Other Track 1." No Tenancy-specific table exists. The `gray` series is irrelevant to this project — stop downloading them.

## What's recoverable from on-disk PDFs right now

We already have these FY-end issues (full-FY YTD = annual totals):

| PDF | Fiscal year | Tenancy filings per vicinage available? |
|-----|-------------|----------------------------------------|
| cman1606 | FY16 (Jul 2015 – Jun 2016) | yes |
| cman1706 | FY17 | yes |
| cman1806 | FY18 | yes |
| cman1906 | FY19 | yes |
| cman2006 | FY20 | yes |
| cman2106 | FY21 | yes |
| cman2206 | FY22 | yes |
| cman2306 | FY23 | yes |
| cman2406 | FY24 | yes |

→ **Parse-once, get 9 years of annual Tenancy × 21 vicinages = 189 county-year observations.** This is roughly what the project already has via other annual sources, but on a federally-consistent vicinage definition.

Plus odd months we have: cman2307, cman2407, cman2408, cman2503, cman2504, cman2506, cman2511, cman2601, cman2604 — 9 monthly issues. Not enough to build a continuous monthly series, but enough to validate that the YTD-differencing logic works against the FY total.

## The monthly cman path is mostly blocked

Probed Wayback Machine for the missing 109 monthly cman URLs. Direct CDX queries return empty:
```
curl 'https://web.archive.org/cdx/search/cdx?url=njcourts.gov/*cman*.pdf&output=json&filter=statuscode:200' → []
```
The live site rotates `cman[YYMM].pdf` each month, overwriting the previous month. Wayback did not capture this rotation for most months. The 220 misses in `nj_statistics_pdf_manifest.csv` aren't a bug — those PDFs are genuinely unrecoverable from public archives.

Probed both URL patterns (live and Wayback) for cman2103.pdf as a representative test: 404 on live (both `/sites/default/files/cman2103.pdf` and `/sites/default/files/public/statistics/cman2103.pdf`), empty on Wayback CDX (full hostname and wildcard).

## Recommended next steps (updated from earlier 4-step plan)

1. **Parse the 9 FY cman PDFs we have → annual Tenancy by vicinage 2016–2024.** Write `03d_parse_nj_cman_fy.R`. ~1–2 hours. The per-vicinage Caseload Profile pages have a stable layout; `tabulizer::extract_tables()` should work. Output: `data/raw/monthly_expansion/nj_raw/nj_tenancy_fy_vicinage.csv` with columns `vicinage, fy, tenancy_filings_added, tenancy_resolved`.
2. **File OPRA in parallel.** This is the only real path to monthly. Draft text:
   > "Pursuant to N.J.S.A. 47:1A-1 et seq., I request the following public records from the Administrative Office of the Courts: For each calendar month from January 2016 through the most recent month available, the count of new Special Civil Part Landlord-Tenant filings, broken out by vicinage (or by county). The data exists in the Automated Case Management System and is the same data underlying the PAC0600 LT Court Report. CSV, Excel, or any electronic format is acceptable."
   Submit at `https://www.njcourts.gov/public/opra`. 30-day statutory clock; AOC has fulfilled comparable academic requests before.
3. **Stop investing in `gray` PDFs.** Series is irrelevant to Tenancy. Delete or skip in `03c`.
4. **Stop investing in monthly cman PDF acquisition via Wayback.** 109 misses are real misses, not a retry-rate-limit problem.
5. **Optional fallback while OPRA pends:** ask DCA for the data underlying the Statewide Landlord Tenant Eviction Dashboard (Power BI). Annual on the dashboard but underlying records are monthly. Email `landlordtenant@dca.nj.gov`.

## Net read on NJ for the gambling project

- **Annual NJ by vicinage 2016–2024** can ship today from PDFs already on disk. Treat the FY data as monthly's interim substitute and use it in robustness checks alongside the existing 24-state ETS panel.
- **Monthly NJ by vicinage** is OPRA-or-nothing. The PDF route is mostly closed and the EAP route is hostile. Estimated time to clean monthly NJ panel: 4–8 weeks (OPRA turnaround + parsing).
- Given that DE, IN, and PA are now newly reachable via LSC CCDI for the treated set, the marginal value of pushing harder on NJ has decreased — NJ was already partially in ETS for the post-2020 period. The annual-only contribution from FY parsing is probably enough for now.
