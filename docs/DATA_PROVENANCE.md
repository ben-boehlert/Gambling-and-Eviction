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
> HI (2022-09), CO (2023-11), MS (2024-03), KS (2025-02) and ID (2025-05) is **upstream in LSC
> itself** and cannot be fixed by re-downloading.


This file supplies the outcome for **30 of the 39 states** in the state panel. Every
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

## 3. State panel — source per state (39 states)

> Per-state detail, including whether a series is the whole state or one city, is in
> **[STATE_SOURCES.md](STATE_SOURCES.md)**. Summary below.

From `data/processed/state_panel_rebuild_source_table.csv`, 2026-08-20 rebuild.

- **`county_download_fixed_basket` (30 states) → LSC CCDI.** AK AR AZ CO CT DE FL GA HI ID IN
  KS KY ME MN MS MT NC ND NY OH OK PA SC TN TX UT VA VT WV + GA/CO/HI/MS/NY/SC per-state
  baskets added 2026-08-28.
- **`ets_internal_county_2026-09-03` (6 states) → Eviction Lab internal county extract.** LA MA MO NM
  NV RI. **Replaced `ets_single_series_no_denominator` on 2026-09-14** (`data_prep/rebuild_single_series_from_ets_internal.R`); the prior vintage is in `data/raw/deprecated/`.
  Built by summing sites within a county-month — verified complementary, not nested: NEWORLEANS-FCC vs
  -SCC and the three LASVEGAS-* jurisdictions are never equal in any shared month. RI/MA/LA/NV report a
  constant county set (basket_share 1.00); **MO and NM do not** and use fixed baskets from 2020-01 at
  basket_share **0.34** and **0.48** — their levels are NOT statewide. Still carry **no renter
  denominator** (fill via `data_prep/fetch_acs_renter_denominators.R`, ACS B25003_003); rates are NA
  until then and must never be fabricated. Currency: [DATA_CURRENCY.md](DATA_CURRENCY.md).
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
  39 states.

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
