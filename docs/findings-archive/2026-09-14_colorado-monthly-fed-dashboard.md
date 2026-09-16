# Correction — Colorado has a MONTHLY public FED filings dashboard (2026-09-14)

**What was wrong.** The 2026-09-14 LSC-stale-states audit (FINDINGS.md §6) stated that all five
stale states' alternative sources are "annual or fiscal-year, so none can extend the MONTHLY
panel." That is wrong for **CO**. The audit noted the existence of the public dashboard at
<https://www.coloradojudicial.gov/eviction-filings> but characterized it only as the Denver-County-Court
fix to the Annual Statistical Reports. It was never opened.

**What the dashboard actually is** (inspected live 2026-09-14; Power BI Gov embed
`app.powerbigov.us/view?r=eyJrIjoiY2U5YTA2MzEtZGU5Ni00M2U1LTgxZDAtMGM1YTZmOWFjMmJiIi...`,
7 report pages, "Data as of: 9/6/2026"):

- Page 5 of 7, **"Residential Eviction Filings by Case File Date — Does not include Denver County Court"**
  ("Case Filings" tab). Visuals: *New Eviction Filings by Month* (Case File Month × Case File Year)
  and *New Eviction Filings by District*. Slicers: District Number, Court Location, Filing Month,
  Filing Calendar Year.
- **Granularity: monthly, by filing (case file) date.** **Window: 2022-01 → 2026-08** (Case File Year
  slicer = 2022/2023/2024/2025/2026). The dashboard notes page says the Case Filing tab "show[s]
  filing trends over the past five years" — i.e. it is a rolling five-year window, not an archive.
- Annual totals read off the page: 2022 **36,736**; 2023 **39,149**; 2024 **44,933**; 2025 **46,579**;
  2026 YTD **31,958**.
- Geography is **judicial district**, not county. The district axis runs 1, 3, 4, …, 22 — **District 2
  (Denver) is absent**, consistent with the title and with the notes page. Denver County Court data is
  requested separately (coradatarequests@denvercountycourt.org).
- Pages 1–4 and the map are a **different universe**: "Residential Eviction Data by **Closure** Date",
  Closure Calendar Year 2024/2025/2026 only (SB24-064 scope: cases closed on or after 2024-07-01),
  133,508 closed cases. Those pages carry a "When was the complaint filed?" month × year chart, but it
  is conditioned on closure in 2024–2026 and is therefore a selected sample — not a filings series.
- Pages 1–4 fields are **scraped from pleadings**, with a published average scraping confidence of
  93.37 over 414,506 documents. The Case Filings tab is case-header data, not scraped.

**Why it still does not rescue CO for this project.**

1. **No pre-period.** CO legalized 2020-05 (`sports_gambling_legalization_dates.csv`: first/online/retail
   all 2020-05-01). A series that starts 2022-01 has **zero** pre-treatment months for CO, so CO cannot
   be a switcher on this source. Its onset is also inside the COVID drop window (2020-03→2021-07).
2. **Scope break.** The panel's CO series is the LSC CCDI 15-county fixed basket
   (`county_download_fixed_basket`, 2019-01→2023-11, 57 months, basket_share 1). The dashboard is
   all judicial districts **except Denver**. Splicing the two violates the one-consistent-source-per-state
   rule and would change geographic scope mid-series — the same defect flagged for RI/MO/NM in the
   2026-09-14 single-series rebuild.
3. **No overlap worth validating on.** Panel ends 2023-11; dashboard starts 2022-01, so there are
   23 overlapping months — enough for a scope-difference check (basket vs non-Denver districts), not
   enough to justify a source switch.

**Extraction feasibility, if it is ever wanted.** No "Export data" affordance is exposed on the
visuals (filter + focus icons only). Point values are reachable through the accessibility layer —
Power BI labels only the focused point (`"Case File Month Name January. Case File Year 2022.
Total Filings 2799."`), so a scrape needs keyboard traversal of the series, or replaying the
report's `POST /explore/querydata` call. ~56 state-level month × year points; district-level
would be ~21× that.

**Net.** The "all annual" claim in FINDINGS.md §6 is corrected to "all annual **except CO**, whose
monthly dashboard still cannot extend the panel." The audit's bottom line — that refreshing the five
LSC-stale states is low priority — is unchanged.

---

## Addendum (same day) — the Denver hole is in BOTH sources, and Denver's attorney flags are not usable

Prompted by a Court-Location = "Denver Cty - County Court" screenshot (`CO Court Website.png`, repo root).

**1. Denver appears only on the closure-date pages, never in the filings series.**
Filtering Court Location to Denver County Court returns **32,895 Total Closed Cases** (24.6% of the
133,508 statewide closed total) on the "Residential Eviction Data by Closure Date" pages. There is
**no Denver row anywhere on the Case Filings tab**: its district axis runs 1, 3, 4, …, 22, and
**District 2 (Denver) is absent entirely** — not zero, absent. Denver District Court contributes no
FED volume because Denver's evictions are heard in Denver County Court, which the Judicial Branch
site states is "administered separately than the state courts" and which sends the Department data
only for the SB24-064 closed-case feed. So Denver's monthly filing volume is not recoverable from
this dashboard at all: the closure-date pages that do contain Denver are closure-keyed and start at
cases closed 2024-07-01.

**2. The same hole exists in our own CO series — verified, not inferred.**
`data/raw/monthly_county_data_download.csv` carries **62 of Colorado's 64 counties**. The two absent
are **Denver (08031)** and Hinsdale (08053, ~114 renters). Our 15-county fixed basket
(540k renters) is drawn from those 62; the 62 listed counties total 615,595 renters. **Denver — the
state's largest renter county — is missing from the LSC CCDI feed for the same structural reason it
is missing from the state filings tab.** This is a standing caveat on every CO number in the panel,
independent of the staleness issue, and it is not visible in `docs/STATE_SOURCES.md`, which reports
CO as "15 of 64" without flagging which county the biggest omission is.

**3. Denver's attorney-representation figures are internally inconsistent — do not cite them.**
With Court Location = Denver County Court: plaintiff represented **31,836 Yes / 1,059 No (96.78%)**,
defendant represented **31,843 Yes / 1,052 No (96.80%)**. Both splits sum to exactly 32,895 — the case
count — and differ from each other by 7 cases. Statewide the same two questions sum to **135,911**
(plaintiff) and **174,154** (defendant), neither equal to the 133,508 case count, i.e. non-Denver rows
are counted **per party** while Denver rows are counted **per case** with what behaves like a single
shared attorney-involvement indicator. A 96.8% defendant representation rate is also implausible on
its face against the 19.63% statewide figure. Treat the Denver attorney flags as an artifact of the
merged feed, not a measurement. (Consistent with the notes page: Denver County Court data "is sent to
the Department and is not included in document scraping.")

**4. Tooltips do expose exact monthly values.** Hovering the monthly line chart returns e.g.
`June: 2022 3229, 2023 1862, 2024 2894, 2025 3542, 2026 3912` — so a hover-based scrape of the
state-level (ex-Denver) monthly series is straightforward if it is ever wanted.
