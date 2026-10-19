# Data Provenance — where every input actually comes from

**Created:** 2026-09-03. **Maintain with:** RUN_LEDGER.md (runs), FINDINGS.md (results), MOVES.md (relocations).

This file answers one question: *for any file in `data/raw/`, who collected it, from what,
and has that been verified?* It exists because the repo mislabelled its primary outcome
file for months (see §1), and because two state series disagree across sources by amounts
large enough to change a treatment effect (§4).

**Status legend**
- `VERIFIED-REPO` — origin documented in-repo with a URL, script, or session record (pointer given).
- `VERIFIED-SESSION` — established by direct comparison of the files themselves on 2026-09-03.
- `UNDOCUMENTED` — no provenance record exists in this repo. Do not cite the origin without checking.

---

## 1. The correction that prompted this file

`data/raw/monthly_county_data_download.csv` is **NOT Eviction Tracking System data.**
It is the **Legal Services Corporation Civil Court Data Initiative (LSC CCDI)** master
county-month file, downloaded from
`https://civilcourtdata.lsc.gov/downloads/monthly_county_data_download.csv`.

- Evidence: [SESSION_REPORT.md:7](../SESSION_REPORT.md) (2026-06-03, direct download, 120,358 rows,
  32 states + 2 territories, 2016-01 → 2025-09); `workdir/gabriel_eviction_data_search/findings_2026-04-27.md`
  confirms the local copy matches the live LSC download exactly (120,357 rows).
- Status: `VERIFIED-REPO` **for the LSC-sourced portion only — see the correction below.**

> **CORRECTION 2026-09-14: the local file is a HYBRID, not a pristine LSC download.**
> A fresh pull from the URL above returns **120,357 rows, max date 2025-09** — exactly the
> 2026-06-03 figure cited above. The local copy has **124,325 rows, max date 2026-06**. The live
> file is a **strict subset**: 0 keys exist only in the live download, while **3,968 keys exist
> only locally** — **NC 3,600** and **ME 368**.
>
> Those rows were merged in from the court-source substitutes in §3: NC's 12,600 rows match
> `data/raw/monthly_expansion/nc_sume_county_month.csv` (NC AOC Summary Ejectment, built by
> `data_prep/monthly_panel_expansion/09b_parse_nc_aoc_sume.R`) at **100%** on every overlapping
> key; LSC's own NC series stops at 2023-06 and ME's at 2023-12.
>
> **Consequences.** (1) **Re-downloading this file is destructive, not a refresh** — it would
> delete NC 2023-07→2026-06 and ME 2024-01→2025-11, and NC is a FULL-WINDOW SWITCHER whose
> entire outcome window (2025-03→2026-03) lives in the locally-added range. (2) Panel rows for
> NC and ME carry `panel_source = county_download_fixed_basket`, which §3 maps to "LSC CCDI" —
> **that label is wrong for NC (NC AOC) and for ME's tail (ME FED)**. (3) The staleness of
> HI (2022-09), CO (2023-11), MS (2024-03) and KS (2025-02) is **upstream in LSC
> itself** and cannot be fixed by re-downloading. (ID was on this list at 2025-05 until its
> 2026-09-14 swap to the Idaho Judicial Branch series, current to 2026-06.)

> **UPDATE 2026-09-17 (evening): the bulk download is stale, not just incomplete — and the
> local file now carries LSC-site months too.** LSC's bulk CSV at the URL above ends **2025-09
> for every state** (re-verified on a fresh 2026-09-17 pull), but each county's page at
> `civilcourtdata.lsc.gov/data/eviction/<state>/<county>/` ships its full monthly series as
> Gatsby static JSON (`/page-data/data/eviction/<state>/<county>/page-data.json`) through
> **2026-06**, with the same fields (`filings_count`, `percent_of_historical_average`).
> `data_prep/pull_lsc_site_county_month.R` scrapes all 1,461 county pages (sitemap-enumerated);
> the site emits a zero row for every unreported county-month, which the puller drops so the
> semantics match the bulk file. `data_prep/append_lsc_site_months.R` appends **only new
> (fips, month) keys after 2025-09** — 7,082 rows on 2026-09-17, every existing row
> byte-identical, renter denominators carried forward per county. LSC's revisions to shared
> history (1,112 keys; MN 590, CT 193, NY 169; median |rel| 4.5%) are written to
> `data/processed/lsc_site_revisions_2026-09-17.csv` and **deliberately not applied**. The
> local file is therefore **130,927 rows**: bulk LSC + NC AOC (3,600) + LSC-site 2025-10→2026-06
> (7,082). ME's court rows were removed from this file earlier the same day (Maine is spliced at
> the state-panel level). **To refresh LSC, run the two scripts; never overwrite the file with
> the bulk CSV.** Raw page JSON is cached (gitignored) under
> `data/raw/monthly_expansion/lsc_site/pages_<date>/`.


This file supplies the outcome for **29 of the 42 states** in the state panel. Every
description of it as "Eviction Tracking System" data is wrong — see §5 for the four places
that need fixing, one of which is PAP-facing.

The Eviction Lab (ETS) is a **separate** provider that appears in this repo through
different files (§2). Any comparison between `monthly_county_data_download.csv` and an
`ets_*` file is a comparison **between two organisations**, not two vintages of one source.

---

## 2. File-by-file origin

### Eviction outcomes — monthly

| File | Origin | Grain / coverage | Status |
|---|---|---|---|
| `monthly_county_data_download.csv` | **LSC CCDI**, `civilcourtdata.lsc.gov` | county-month, 2016-01→2025-09, 32 states + PR/VI | `VERIFIED-REPO` |
| `ets_county_month.csv` (repo root) | **Eviction Lab internal site-level extract**, supplied by colleague 2026-09-03 | county-month with `xsite` label; 68,040 rows, 55 sites, 25 states, 1999-03→2026-08; counts only, **no denominator** | `VERIFIED-SESSION` |
| `ets_merged/merged_ets_sites_monthly.csv`, `merged_ets_states_monthly.csv`, `merged_ets_combined.csv` | Eviction Lab site/state aggregates; built by `data_prep/merge_ets_data.R`, `merge_ets_combined.R` | site- or state-month, no county FIPS, no denominator | `VERIFIED-REPO` |
| `ets_merged/historical_ets_data_monthly.csv` | Eviction Lab site-month (`xsite`,`N`) | **Scope-inconsistent — do not use.** Its PHILADELPHIA and RICHMOND rows are ~2× the county-resolved value (2016-01: 3,692 vs 1,854; 4,708 vs 2,358); STLOUIS covers a wider geography than the STLOUIS site; CONNECTICUT is the whole state. | `VERIFIED-SESSION` |
| `combined_monthly_panel.csv` | Derived merge of the above | county-month | `VERIFIED-REPO` |

### Eviction outcomes — court-source substitutes (`data/raw/monthly_expansion/`)

Built where LSC/ETS coverage was absent or defective. Scripts in `data_prep/monthly_panel_expansion/`.

| State | Origin | Script | Status |
|---|---|---|---|
| MD | MD Judiciary annual statistics PDFs → monthly Landlord/Tenant **complaint** filings (supersedes the Socrata extract, which starts May 2023 and has ~0 MD pre-treatment months) | `01b_`/`01c_`/`07_merge_md_into_panel.R`; source page `mdcourts.gov/district/about` | `VERIFIED-REPO` |
| MD (superseded) | MD Open Data Socrata, `opendata.maryland.gov/.../mvqb-b4hf` | `01_pull_md_socrata.R` | `VERIFIED-REPO` |
| NH | NH Judicial Branch monthly Landlord/Tenant Writ filings. Replaced an ETS/LSC series that recorded post-2023-06 missing months as literal **zeros** (spurious −57% NH effect). Jan–Jun 2023 match exactly, confirming same series. | `06_repair_nh_from_court_source.R` | `VERIFIED-REPO` |
| ME | Maine Judicial Branch "15-Year Monthly FED Filing Trends". Same zero-fill defect after 2023-05. Court source does **not** match the old series on overlap (staler MEJIS vintage), so ME's series was **replaced wholesale**, not spliced (user decision 2026-07-23). | `07_repair_me_from_court_source.R`, `08_repair_me_in_county_files.R` | `VERIFIED-REPO` |
| WI | WI Dept. of Administration "Eviction Data Project" county-month (CCAP/WCCA), `doa.wi.gov` | `08a_`/`08b_`/`08c_` | `VERIFIED-REPO` |
| NC | NC AOC Civil Issue Filings/Order Results FY workbooks, `nccourts.gov` — the same reports behind ETS's NC series | `09a_`/`09b_`/`09c_` | `VERIFIED-REPO` |
| NJ | NJ Courts Special Civil Part dashboards / "gray" statistics PDFs | `03_`,`03b_`,`03c_` — **downloaded, never merged** | `VERIFIED-REPO` |
| IA | Iowa State Court Administration, written email request (`sca@iowacourts.gov`) — no public API | `04_pull_ia_email_request.R` — **pending** | `VERIFIED-REPO` |

### Eviction outcomes — annual

| File | Origin | Status |
|---|---|---|
| `county_court-issued_2000_2023_ben_update_5_12.csv`, `..._3_19_R.csv` | State-by-state court statistics, hand-compiled. **Per-state methodology (source URL, filing definition, court type, calendar type, known biases) is documented state-by-state in [`County Court Data Methodology Report.md`](../County%20Court%20Data%20Methodology%20Report.md).** Read that before using any state. | `VERIFIED-REPO` |
| `updated_county_issued_ANNUAL.xlsx` | Same family | `UNDOCUMENTED` |

CT example from that report: CT Judicial Branch Housing Session **and** Non-Housing Session
Summary Process reports (`jud.ct.gov/statistics/housing`), measure = "Summary Process
Filings: Added", counties assigned via a 15-courthouse crosswalk, fiscal year Jul–Jun.

### State-specific exploratory extracts

| Directory | Origin | Status |
|---|---|---|
| `illinois/` | Illinois Courts 2022–2025 Circuit Court Statistical Dashboard (Power BI); clerk-submitted quarterly reports, subject to revision | `VERIFIED-REPO` |
| `michigan/` | Michigan Courts Interactive Court Data Dashboard, `CASE_TYPE_CODE = LT`, "New Filings" | `VERIFIED-REPO` |
| `evicted_in_oregon/` | evictedinoregon.com (Lisa Bates, PSU) via Datawrapper CDN; underlying data Oregon Judicial Department circuit courts | `VERIFIED-REPO` |
| `massachusetts/` | MA Trial Court DRAP "Summary Process" Tableau dashboard | `VERIFIED-REPO` |
| `maryland/`, `ny_oca/` | MD Socrata; NY OCA index | `UNDOCUMENTED` (partial) |
| `ne_raw/` (via `data_prep/monthly_panel_expansion/10a`/`10b`) | Nebraska AOC, LB320/Neb. Rev. Stat. § 24-232 mandated "Eviction Proceedings Bi-Annual Data Report" (`nebraskajudicial.gov/administration/publications-reports`, category "Eviction Proceedings"). Statewide, **county-half-year** (not month), Jul 2021–Dec 2025, 9 periods. Five series per period: cases filed; tenants/landlords represented by counsel (closed cases; split into limited-scope "LRA" + full "Represented by Counsel" from **2023-H2** on — see the script header for why the old single column matches "Represented by Counsel," not the post-split Total); default restitution-of-premises orders; all restitution-of-premises orders entered. Not yet part of `state_month_panel_with_treatment.csv` (frequency mismatch; NE has no row in `sports_gambling_legalization_dates.csv` and reads as never-treated/control-eligible via `EVICTION_STATE_UNIVERSE`) — a candidate control state for the annual-panel TODO, not merged. **Verification:** every (period, table) cell's per-county sum reconciles exactly against the report's own printed Total row (45/45 cells; `ne_raw/ne_validation_report.csv`). 2 of 9 PDFs (Jul-Dec-2023, Jul-Dec-2025) are fully rasterized (no text layer); Jan-June-2024's text layer is independently corrupted (OCR-garbled footer, ~1/3 of several tables' values unreadable to `pdftools`) — those cells were hand-transcribed from the rendered page instead of parsed, each still checked against its printed Total. One documented source inconsistency, not an extraction artifact: 2024H1's addendum-corrected table (d) exceeds table (e) by 1 case for Buffalo and Webster, matching the addendum's own disclosed caveat ("this version will include a few more cases in other counties due to late entry"). **`restitution_orders_entered_default_closed` (table d) is not cross-county comparable** — Lancaster County (the state's 2nd largest) is nonzero in only 2 of 9 periods, which the 2024-H1 addendum text ties to clerk data-entry practice rather than case outcomes; prefer `cases_filed` (a) or `restitution_orders_entered_closed` (e) for cross-county work. Reports state a 3% margin of error. | `VERIFIED-SESSION` |

### Treatment and covariates

| File | Origin | Status |
|---|---|---|
| `sports_gambling_legalization_dates.csv` | **Upstream source not recorded anywhere in this repo.** In-repo history only: repaired 2026-08-10 (online dates added for DE/NC/KY/ME/FL/VT/MO). Never-legalizers have **no row** (ABSENT, not NA); NV absent because always-treated since 1949. | `UNDOCUMENTED` |
| `lsr_sports_betting_handle_revenue_by_state_month.csv` | Legal Sports Report, `legalsportsreport.com/sports-betting/states/revenue/`; retrieved 2026-08-14; full note + SHA-256 in the sidecar `.source.md`; audit via `scripts/audit_lsr_handle_data.R` | `VERIFIED-REPO` |
| `gambling_institutions/` | Secondary-source compilation (LotteryUSA; I. Nelson Rose "Pivotal Dates"), documented in its `SOURCES.md`, explicitly flagged **not publication-grade** | `VERIFIED-REPO` |
| `StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv` | **Not documented.** `docs/methodology/README_MORTGAGE_PRETRENDS.md` carries a literal `[Add data source]` placeholder in two places. Wide format `RegionType,Name,FIPSCode,YYYY-MM…`, national + state, 2008-01→2025-03. | `UNDOCUMENTED` |
| `county_adjacency_census.txt` | US Census county adjacency file (latin-1 encoded — read with `encoding="latin-1"`) | `VERIFIED-SESSION` |

### Derived panels

| File | Built by | Notes |
|---|---|---|
| `state_month_panel_with_treatment.csv` | `data_prep/rebuild_state_month_panel.R` | One consistent source per state; per-state provenance in §3 and in `data/processed/state_panel_rebuild_source_table.csv`; composition QA in `data/processed/state_panel_coverage_qa.csv` |
| `data/processed/shift12_schedule.csv` | `data_prep/build_shift12_schedule.R` | Launch + 12 months; blind to outcomes |

---

## 3. State panel — source per state (42 states)

> Per-state detail, including whether a series is the whole state or one city, is in
> **[STATE_SOURCES.md](STATE_SOURCES.md)**. Summary below.

From `data/processed/state_panel_rebuild_source_table.csv`, 2026-08-20 rebuild.

- **`county_download_fixed_basket` (29 states) → LSC CCDI.** AK AR AZ CO CT DE FL GA HI IN
| `StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv` | CFPB Mortgage Performance Trends (files.consumerfinance.gov), retrieved 2026-09-29; URL, SHA-256 and caveats in the sidecar `.source.md`. The same download path is the likely origin of the 90+ file, but that is not verified | `VERIFIED-SESSION` |
  KS KY ME MN MS MT NC ND NY OH OK PA SC TN TX UT VA VT WV + GA/CO/HI/MS/NY/SC per-state
| `covariates/` (RealtyTrac 2010 foreclosure regime, ACS 2019, BLS LAUS 2019, FHFA PO HPI, HMDA 2019) | Public APIs / Wayback, retrieved 2026-09-29 by `data_prep/build_state_covariates_2019.R` → `data/processed/state_covariates_2019.csv`. URLs, caveats and SHA-256 in `data/raw/covariates/SOURCES.md` | `VERIFIED-SESSION` |
  baskets added 2026-08-28. ID left this group on 2026-09-14 (next bullet).
- **`id_courts_a12_2026-09-14` (1 state) → Idaho Judicial Branch.** ID, swapped 2026-09-14 by
  `data_prep/add_id_to_state_panel.R` from `data/raw/idaho/id_state_month_a12.csv`, pulled by
  `data_prep/pull_id_powerbi_eviction_filings.R` from the public Case and Charge Data Power BI
  dashboard (`courtdata.idaho.gov/Charge`; case type A12 Unlawful Detainer/Eviction, event Filed,
  juveniles excluded). **All 44 counties**, 66 months 2021-01..2026-06, no gaps. Replaces the Twin
  Falls-only LSC basket (1 of 44 counties, 113 months), preserved verbatim at
  `data/raw/deprecated/id_twin_falls_lsc_series_pre_2026-09-14.csv`; the two are **not spliced**, so
  ID has no pre-2021 months. The dashboard is a rolling five-year window — archive every pull.
  Denominator: statewide ACS B25003_003 via `fetch_acs_renter_denominators.R`.
- **`ets_internal_county_2026-09-03` (6 states) → Eviction Lab internal county extract.** LA MA MO NM
  NV RI. **Replaced `ets_single_series_no_denominator` on 2026-09-14** (`data_prep/rebuild_single_series_from_ets_internal.R`); the prior vintage is in `data/raw/deprecated/`.
  Built by summing sites within a county-month — verified complementary, not nested: NEWORLEANS-FCC vs
  -SCC and the three LASVEGAS-* jurisdictions are never equal in any shared month. RI/MA/LA/NV report a
  constant county set (basket_share 1.00); **MO and NM do not** and use fixed baskets from 2020-01 at
  basket_share **0.34** and **0.48** — their levels are NOT statewide. **Denominators filled
  2026-09-14** by `data_prep/fetch_acs_renter_denominators.R` (ACS B25003_003, at the geography the
  numerator covers, with the ACS vintage recorded per row); the earlier "no renter denominator" note
  no longer holds. Currency: [DATA_CURRENCY.md](DATA_CURRENCY.md).
- **`ets_internal_county_wa_2026-09-14` (1 state) → Eviction Lab internal county extract.** WA, added
  2026-09-14 by `data_prep/add_wa_to_state_panel.R` from the same `ets_county_month.csv`. Its **only**
  WA site is `TACOMA` = **Pierce County (53053)**, so WA is one county wearing a state label —
  `n_counties` 1, `basket_share` 1, denominator = Pierce County renters (124k). 113 contiguous months
  2017-01..2026-05. No `online_start_date` (retail-only, Sep 2021), so WA is a never-treated control.
- **`mi_jdw_statewide_2026-09-03` (1 state) → Michigan Courts Judicial Data Warehouse.** MI, added
  2026-09-14 by `data_prep/add_mi_to_state_panel.R` from `conditional-dismissals.pdf`, parsed by
  `data_prep/parse_mi_jdw_lt_filings_pdf.py`. Statewide monthly Landlord/Tenant new filings **minus six
  jurisdictions the report excludes** (Berrien Co., Grand Rapids, Dearborn Hts, Center Line & Warren,
  N. Macomb Co., Grandville & Walker) — measured at **0.940** of the county dashboard's 2019 footprint,
  so the statewide ACS denominator understates the rate ~6%. No county values published →
  `n_counties`/`basket_share` NA. **68 of 89 months**: 21 are `unlabelled_in_source` and are omitted
  rows, never zero-filled; 3 are `derived_from_annual_total` (exact arithmetic). Complete 2019-01..2023-01.
- **Trailing partial-month censor (2026-09-14).** The Eviction Lab extract cuts each site at its own
  collection date, leaving a partial final month that the single-series rebuild carried into the panel.
  Removed: **NM 2026-06** (0.16 of its prior-6 median), **MO 2026-06** (0.26), **LA 2026-03** (0.31),
  **WA 2026-06** (0.38, dropped in its add script), **MA 2026-06** (0.53). NV and RI end a month earlier
  and are clean. Edit: `data_prep/censor_trailing_partial_months.R`. **Re-check after every extract refresh.**
- **Series-start ramp censor (2026-09-14).** Three leading months were removed as incomplete-at-ingest
  reporting, not real drops: **CT 2016-01 / 2016-02** (0.15 / 0.19 of their own seasonal norm, then
  straight to ~1.05) and **NH 2018-12** (0.20, then 1.18). CT now starts 2016-03 and NH 2019-01.
  Detection: `analysis/diagnostics/series_start_ramp_check.R`; edit: `data_prep/censor_series_start_ramps.R`.
  WI 2019-01 (0.56) was assessed and deliberately left in place.
- **`or_ojd_plus_evictedinoregon_2026-09-14` (1) → SPLICED, two Oregon sources.** OR. Pre-period
  2018-01..2019-12 from **Oregon Judicial Department "Cases Filed" PDFs** (statewide monthly Landlord
  Tenant); 2020-01..2026-07 from the **Evicted in Oregon dashboard** (Lisa Bates, Portland State;
  underlying OJD circuit-court records). Splice unavoidable — neither source spans OR's baseline and
  outcome. Seam measured on 12 overlapping months: dashboard/OJD median **0.9905** (−0.0095 log points),
  left unadjusted and disclosed. Circuit court only (13 counties' justice-court filings absent);
  statewide only. **The dashboard is MUTABLE** — Datawrapper chart `l8e1N`, captured version 94;
  the publisher revised Apr 2026 (2,308 → 2,319) between captures. Source README:
  `data/raw/evicted_in_oregon/README.md`. Status: `VERIFIED-SESSION`.
- **`md_judiciary_lt_complaint_filings` (1) → MD Judiciary PDFs.** MD.
- **`nh_court_source_repair_2026-07-23` (1) → NH Judicial Branch.** NH.
- **`wi_court_source_repair_2026-07-23` (1) → WI DOA.** WI.

Seams to remember: NY uses county sums from 2019-01 only (pre-2019 is a different-basket
ETS series). The pre-rebuild panel added LSC and Eviction Lab series **together** for 12
states including MN — that double count is fixed, and the corrupt vintage is preserved at
`data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv`.

---

## 4. Known cross-source conflicts

Established 2026-09-03 by comparing LSC CCDI against the Eviction Lab county file on
**matched county-months** (same counties, same months). Most states agree: DE, IN, OH, PA,
VA, SC, TN sit within 1–2% in both the pre-2020 and post-2020 eras; NY, TX, FL show a flat
2–5% offset with no break. Two states do not.

**Connecticut — unresolved, and it is a treated cluster (online Oct 2021).**
LSC runs ~1.29× below the Eviction Lab count and the wedge *moves*: flat 1.30 through
2017–2019, breaks at 2020-02, peaks ~3.1 in Apr–Jun 2020, holds 1.6–2.0 through 2021, then
decays (1.48 in 2022, 1.44 in 2023, 1.38 in 2024) and closes to ~1.0 by mid-2025.
- Not double counting: the three CT sites partition the state by county (BRIDGEPORT =
  Fairfield, HARTFORD = Hartford Co., CONNECTICUT = the other six; 31 stray county-months).
- Not court coverage: the shortfall is uniform across all eight counties, including the five
  with no housing session — so "LSC counts Housing Session only" is **ruled out**.
- **Adjudicated for the pre-COVID era by CT's own published statistics.** CT Judiciary
  summary process filings: 20,900 (2017), 19,978 (2018). Eviction Lab: 20,366 / 19,694
  (FY2018 matches to 0.3%). LSC: 16,001 / 15,192 — **23–24% below the state's own count.**
- Consequence: indexed to 2019 = 100, Eviction Lab puts CT at 120 in 2022 decaying to 94 by
  2025 H1; LSC puts CT flat at ~100 throughout. The two sources disagree about exactly the
  quantity a DiD estimates, across CT's whole post-treatment window.
- **Both repo copies of the annual court file stop at CT 2018**, so the 2020–2024 divergence
  is *not* adjudicated. The 2000–2025 court file at `~/Documents/Court Data/` (outside this
  repo) should settle it.
- Standing advice until resolved: do not treat either CT series as authoritative post-2019.

**Minnesota — resolved 2026-09-03** (source scope change confirmed with the file's author);
retained here only as the pattern to look for: agreement within 2% through 2019, then LSC
running 34–76% below the Eviction Lab count from 2020 on, widening through 2024, driven by
Hennepin and Ramsey — both inside the panel's fixed 22-county basket.

**Two file-level gotchas in `ets_county_month.csv`:**
- 175 rows carry `xcourtcofips = 00000` (all MINNESOTA site, 698 filings). Any join on FIPS
  silently drops them; this is the entire difference between a naive state sum and the
  file author's own totals.
- 4 junk rows dated 2027, 2099, 2100-02, 2100-03 (all OKLAHOMACITY, Cleveland Co.).
- Multi-court sites need **summing, not deduping**: LASVEGAS-{LASVEGAS,HENDERSON,NORTH LASVEGAS}
  are three township courts in Clark County; NEWORLEANS-{FCC,SCC} are two city courts in
  Orleans Parish.
- MA *is* in the Eviction Lab's internal collection (BOSTON site, Suffolk, 2020-01→2026-06),
  which resolves the open question in `data/raw/massachusetts/README_data_sources.md`.

---

## 5. Documentation errors to fix

Four files describe the LSC CCDI county file as Eviction Tracking System data:

- [`CLAUDE.md:79`](../CLAUDE.md)
- [`AGENTS.md:61`](../AGENTS.md)
- [`.claude/references/domain-profile.md:27`](../.claude/references/domain-profile.md)
- [`docs/methodology/PRE_ANALYSIS_PLAN_POWER_LANGUAGE.md:76`](methodology/PRE_ANALYSIS_PLAN_POWER_LANGUAGE.md) — **PAP-facing**: the
  pre-analysis plan currently names the wrong data provider for the primary outcome in 30 of
  42 states.

Also open: the mortgage delinquency source placeholder in
`docs/methodology/README_MORTGAGE_PRETRENDS.md` (two `[Add data source]` markers), and the
absent upstream record for `sports_gambling_legalization_dates.csv`.

---

## 6. Rules

1. Never describe a file's provider from memory or from its filename. Check this table.
2. A comparison between an `ets_*` file and `monthly_county_data_download.csv` is
   **LSC vs Eviction Lab**. Say which is which in any write-up.
3. One source per state, always — the 2026-08-20 rebuild rule. Adding the Eviction Lab
   county file to any state currently on LSC requires a fresh panel vintage and a new
   `run_name`; results cannot be paired rep-for-rep across that boundary.
4. When comparing two monthly files, check their **end dates first**. LSC ends 2025-09
   (CT 2025-07); the Eviction Lab file runs to 2026-08. Annual sums across that boundary
   compare twelve months against seven and manufacture divergence that is not there.
5. New source acquired → add a row here **and** a sidecar `.source.md` next to the file,
   following `lsr_sports_betting_handle_revenue_by_state_month.source.md` as the model
   (URL, retrieval date, grain, coverage, row count, SHA-256, known caveats).
