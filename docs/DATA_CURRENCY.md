# Data Currency

**Generated 2026-09-14 by `data_prep/make_data_currency_doc.R` — do not hand-edit.**
Regenerate after any panel rebuild or source refresh. Source of truth: `data/raw/state_month_panel_with_treatment.csv`.

Companion docs: [DATA_PROVENANCE.md](DATA_PROVENANCE.md) (who collected what, and whether that is verified)
and [STATE_SOURCES.md](STATE_SOURCES.md) (per-state scope — whole state vs county basket vs single city).

## How to read this

- **Stale** = months between the series' last month and 2026-09. `aging` at 15+, `STALE` at 24+.
- **Max gap** = longest interior hole in months, *excluding* the COVID drop window (2020-03 – 2021-07).
- **Basket** = `basket_share`, the fraction of the state's reporting counties held in the fixed basket.
  `THIN-BASKET` flags anything below 0.90 — those states' LEVELS are not statewide and must not be read as such.
- **Denominator** = whether `renter_occupied_housing_units` is populated. The headline outcome is
  `y_log1p = log1p(filings_count)` (counts), so a missing denominator blocks only the `y_lograte`
  sensitivity arm, not the main analysis.
- **Role** = status under the clean-anchor rule (6-month pre-launch baseline, outcomes 12–24 months
  post-launch, COVID window dropped, ex NV/ID/HI/MS). Necessary but not sufficient — a cell also needs a
  surviving not-yet-treated control.

## By source

| Source | States | Median stale (mo) | Latest month | How to refresh |
|---|---:|---:|---|---|
| `county_download_fixed_basket` | 30 | 12 | 2026-06 | Download a fresh `monthly_county_data_download.csv` from civilcourtdata.lsc.gov, then `Rscript data_prep/rebuild_state_month_panel.R` |
| `wi_court_source_repair_2026-07-23` | 1 | 11 | 2025-10 | Re-download the WI Dept. of Administration series |
| `nh_court_source_repair_2026-07-23` | 1 | 10 | 2025-11 | Request an updated extract from the NH Judicial Branch |
| `ets_internal_county_2026-09-03` | 6 | 3.5 | 2026-06 | Obtain a newer Eviction Lab internal extract, replace `ets_county_month.csv`, then `Rscript data_prep/rebuild_single_series_from_ets_internal.R` |
| `md_judiciary_lt_complaint_filings` | 1 | 3 | 2026-06 | Pull new monthly PDFs from the MD Judiciary statistics page into `data/raw/monthly_expansion/md_raw/`, then re-run the MD extraction |
| `or_ojd_plus_evictedinoregon_2026-09-14` | 1 | 2 | 2026-07 | NA |

## By state — stalest first

| State | Source | Span | Months | Stale (mo) | Max gap | Counties | Basket | Denom | Role | Flag |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|
| HI | county_download_fixed_basket | 2020-01–2022-09 | 33 | **48** | -- | 4 | 1.00 | yes | excluded | STALE |
| CO | county_download_fixed_basket | 2019-01–2023-11 | 57 | **34** | -- | 15 | 1.00 | yes | not a switcher | STALE |
| MS | county_download_fixed_basket | 2016-01–2024-03 | 99 | **30** | -- | 1 | 1.00 | yes | excluded | STALE |
| AZ | county_download_fixed_basket | 2016-01–2025-02 | 110 | **19** | -- | 2 | 1.00 | yes | not a switcher | aging |
| KS | county_download_fixed_basket | 2016-01–2025-02 | 110 | **19** | -- | 1 | 1.00 | yes | **switcher (full)** | aging |
| FL | county_download_fixed_basket | 2016-01–2025-04 | 112 | **17** | -- | 6 | 1.00 | yes | switcher (partial 5/13) | aging |
| GA | county_download_fixed_basket | 2016-01–2025-04 | 112 | **17** | -- | 2 | 1.00 | yes | control (no online date) | aging |
| ID | county_download_fixed_basket | 2016-01–2025-05 | 113 | **16** | -- | 1 | 1.00 | yes | excluded | aging |
| ND | county_download_fixed_basket | 2016-01–2025-05 | 113 | **16** | -- | 6 | 1.00 | yes | control (no online date) | aging |
| OH | county_download_fixed_basket | 2016-01–2025-06 | 114 | **15** | -- | 4 | 1.00 | yes | **switcher (full)** | aging |
| CT | county_download_fixed_basket | 2016-03–2025-07 | 111 | **14** | -- | 6 | 1.00 | yes | not a switcher |  |
| WV | county_download_fixed_basket | 2016-01–2025-08 | 112 | **13** | 1 | 25 | 1.00 | yes | switcher (partial 7/13) |  |
| AK | county_download_fixed_basket | 2016-01–2025-09 | 116 | **12** | -- | 5 | 1.00 | yes | control (no online date) |  |
| AR | county_download_fixed_basket | 2016-01–2025-09 | 114 | **12** | -- | 12 | 1.00 | yes | **switcher (full)** |  |
| DE | county_download_fixed_basket | 2016-01–2025-09 | 115 | **12** | -- | 3 | 1.00 | yes | switcher (partial 9/13) |  |
| IN | county_download_fixed_basket | 2016-01–2025-09 | 113 | **12** | -- | 59 | 1.00 | yes | switcher (partial 3/13) |  |
| KY | county_download_fixed_basket | 2016-01–2025-09 | 110 | **12** | 1 | 45 | 1.00 | yes | switcher (partial 12/13) |  |
| MN | county_download_fixed_basket | 2016-01–2025-09 | 100 | **12** | 1 | 22 | 1.00 | yes | control (no online date) |  |
| MT | county_download_fixed_basket | 2016-01–2025-09 | 116 | **12** | -- | 6 | 1.00 | yes | control (no online date) |  |
| NY | county_download_fixed_basket | 2019-01–2025-09 | 68 | **12** | -- | 53 | 1.00 | yes | not a switcher |  |
| OK | county_download_fixed_basket | 2016-01–2025-09 | 113 | **12** | -- | 33 | 1.00 | yes | control (no online date) |  |
| PA | county_download_fixed_basket | 2016-01–2025-09 | 110 | **12** | -- | 58 | 1.00 | yes | not a switcher |  |
| SC | county_download_fixed_basket | 2018-08–2025-09 | 85 | **12** | -- | 45 | 1.00 | yes | control (no online date) |  |
| TN | county_download_fixed_basket | 2016-01–2025-09 | 117 | **12** | -- | 3 | 1.00 | yes | not a switcher |  |
| TX | county_download_fixed_basket | 2016-01–2025-09 | 117 | **12** | -- | 8 | 1.00 | yes | control (no online date) |  |
| UT | county_download_fixed_basket | 2016-01–2025-09 | 117 | **12** | -- | 6 | 1.00 | yes | control (no online date) |  |
| VA | county_download_fixed_basket | 2016-01–2025-09 | 102 | **12** | 1 | 87 | 1.00 | yes | not a switcher |  |
| VT | county_download_fixed_basket | 2016-01–2025-09 | 105 | **12** | -- | 9 | 1.00 | yes | switcher (partial 9/13) |  |
| WI | wi_court_source_repair_2026-07-23 | 2019-01–2025-10 | 81 | **11** | 1 | -- | -- | yes | control (no online date) |  |
| ME | county_download_fixed_basket | 2016-01–2025-11 | 119 | **10** | -- | 16 | 1.00 | yes | **switcher (full)** |  |
| NH | nh_court_source_repair_2026-07-23 | 2019-01–2025-11 | 83 | **10** | -- | -- | -- | yes | switcher (partial 5/13) |  |
| LA | ets_internal_county_2026-09-03 | 2019-01–2026-03 | 85 | **6** | -- | 1 | 1.00 | yes | not a switcher |  |
| NV | ets_internal_county_2026-09-03 | 2016-01–2026-05 | 125 | **4** | -- | 1 | 1.00 | yes | excluded |  |
| RI | ets_internal_county_2026-09-03 | 2015-06–2026-05 | 130 | **4** | -- | 4 | 1.00 | yes | switcher (partial 2/13) |  |
| MA | ets_internal_county_2026-09-03 | 2020-01–2026-06 | 78 | **3** | -- | 1 | 1.00 | yes | **switcher (full)** |  |
| MD | md_judiciary_lt_complaint_filings | 2012-01–2026-06 | 174 | **3** | -- | -- | -- | yes | **switcher (full)** |  |
| MO | ets_internal_county_2026-09-03 | 2020-01–2026-06 | 78 | **3** | -- | 29 | 0.34 | yes | not a switcher | THIN-BASKET |
| NC | county_download_fixed_basket | 2016-01–2026-06 | 126 | **3** | -- | 100 | 1.00 | yes | **switcher (full)** |  |
| NM | ets_internal_county_2026-09-03 | 2020-01–2026-06 | 78 | **3** | -- | 14 | 0.48 | yes | control (no online date) | THIN-BASKET |
| OR | or_ojd_plus_evictedinoregon_2026-09-14 | 2018-01–2026-07 | 103 | **2** | -- | -- | -- | yes | switcher (partial 3/13) |  |

## Known limits of this table

- It reports what the panel *contains*, not whether the upstream source has newer data. A state can look
  current and still be behind its provider.
- `basket_share` is computed against counties observed **in this panel**, not against all counties in the
  state. A state whose provider only ever covered 3 counties shows 1.00.
- Staleness is measured against today's date, so this file's numbers drift until it is regenerated.
