# Data Currency

**Generated 2026-10-19 by `data_prep/make_data_currency_doc.R` — do not hand-edit.**
Regenerate after any panel rebuild or source refresh. Source of truth: `data/raw/state_month_panel_with_treatment.csv`.

Companion docs: [DATA_PROVENANCE.md](DATA_PROVENANCE.md) (who collected what, and whether that is verified)
and [STATE_SOURCES.md](STATE_SOURCES.md) (per-state scope — whole state vs county basket vs single city).

## How to read this

- **Stale** = months between the series' last month and 2026-10. `aging` at 15+, `STALE` at 24+.
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
| `wi_court_source_repair_2026-07-23` | 1 | 12 | 2025-10 | Re-download the WI Dept. of Administration series |
| `nh_court_source_repair_2026-07-23` | 1 | 11 | 2025-11 | Request an updated extract from the NH Judicial Branch |
| `ets_internal_county_2026-09-03` | 6 | 5 | 2026-05 | Obtain a newer Eviction Lab internal extract, replace `ets_county_month.csv`, then `Rscript data_prep/rebuild_single_series_from_ets_internal.R` |
| `ets_internal_county_wa_2026-09-14` | 1 | 5 | 2026-05 | Obtain a newer Eviction Lab internal extract, replace `ets_county_month.csv`, then `Rscript data_prep/add_wa_to_state_panel.R` |
| `mi_jdw_statewide_2026-09-03` | 1 | 5 | 2026-05 | Re-download `conditional-dismissals.pdf` from courts.michigan.gov, run `python3 data_prep/parse_mi_jdw_lt_filings_pdf.py`, then `Rscript data_prep/add_mi_to_state_panel.R` |
| `county_download_fixed_basket` | 29 | 4 | 2026-08 | Download a fresh `monthly_county_data_download.csv` from civilcourtdata.lsc.gov, then `Rscript data_prep/rebuild_state_month_panel.R` |
| `id_courts_a12_2026-09-14` | 1 | 4 | 2026-06 | `Rscript data_prep/pull_id_powerbi_eviction_filings.R`, then `Rscript data_prep/add_id_to_state_panel.R` (the ID dashboard is a rolling five-year window) |
| `md_judiciary_lt_complaint_filings` | 1 | 4 | 2026-06 | Pull new monthly PDFs from the MD Judiciary statistics page into `data/raw/monthly_expansion/md_raw/`, then re-run the MD extraction |
| `or_ojd_plus_evictedinoregon_2026-09-14` | 1 | 3 | 2026-07 | Re-export the Evicted in Oregon dashboard (mutable -- the publisher revises it), then `Rscript data_prep/add_oregon_to_state_panel.R` |

## By state — stalest first

| State | Source | Span | Months | Stale (mo) | Max gap | Counties | Basket | Denom | Role | Flag |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|
| HI | county_download_fixed_basket | 2020-01–2022-09 | 33 | **49** | -- | 4 | 1.00 | yes | excluded | STALE |
| CO | county_download_fixed_basket | 2019-01–2023-09 | 55 | **37** | -- | 15 | 1.00 | yes | not a switcher | STALE |
| MS | county_download_fixed_basket | 2016-01–2024-03 | 99 | **31** | -- | 1 | 1.00 | yes | excluded | STALE |
| AZ | county_download_fixed_basket | 2016-01–2025-02 | 110 | **20** | -- | 2 | 1.00 | yes | not a switcher | aging |
| KS | county_download_fixed_basket | 2016-01–2025-02 | 110 | **20** | -- | 1 | 1.00 | yes | **switcher (full)** | aging |
| FL | county_download_fixed_basket | 2016-01–2025-04 | 112 | **18** | -- | 6 | 1.00 | yes | switcher (partial 5/13) | aging |
| GA | county_download_fixed_basket | 2016-01–2025-04 | 111 | **18** | 1 | 2 | 1.00 | yes | control (no online date) | aging |
| ND | county_download_fixed_basket | 2016-01–2025-05 | 113 | **17** | -- | 6 | 1.00 | yes | control (no online date) | aging |
| OH | county_download_fixed_basket | 2016-01–2025-05 | 113 | **17** | -- | 4 | 1.00 | yes | **switcher (full)** | aging |
| WI | wi_court_source_repair_2026-07-23 | 2019-01–2025-10 | 81 | **12** | 1 | -- | -- | yes | control (no online date) |  |
| MT | county_download_fixed_basket | 2016-01–2025-11 | 118 | **11** | -- | 6 | 1.00 | yes | control (no online date) |  |
| NH | nh_court_source_repair_2026-07-23 | 2019-01–2025-11 | 83 | **11** | -- | -- | -- | yes | switcher (partial 5/13) |  |
| TX | county_download_fixed_basket | 2016-01–2025-12 | 120 | **10** | -- | 8 | 1.00 | yes | control (no online date) |  |
| LA | ets_internal_county_2026-09-03 | 2019-01–2026-02 | 84 | **8** | -- | 1 | 1.00 | yes | not a switcher |  |
| CT | county_download_fixed_basket | 2016-03–2026-05 | 119 | **5** | 2 | 6 | 1.00 | yes | not a switcher |  |
| MA | ets_internal_county_2026-09-03 | 2020-01–2026-05 | 77 | **5** | -- | 1 | 1.00 | yes | **switcher (full)** |  |
| MI | mi_jdw_statewide_2026-09-03 | 2019-01–2026-05 | 68 | **5** | 8 | -- | -- | yes | not a switcher |  |
| MO | ets_internal_county_2026-09-03 | 2020-01–2026-05 | 77 | **5** | -- | 29 | 0.34 | yes | not a switcher | THIN-BASKET |
| NM | ets_internal_county_2026-09-03 | 2020-01–2026-05 | 77 | **5** | -- | 14 | 0.48 | yes | control (no online date) | THIN-BASKET |
| NV | ets_internal_county_2026-09-03 | 2016-01–2026-05 | 125 | **5** | -- | 1 | 1.00 | yes | excluded |  |
| RI | ets_internal_county_2026-09-03 | 2015-06–2026-05 | 130 | **5** | -- | 4 | 1.00 | yes | switcher (partial 2/13) |  |
| UT | county_download_fixed_basket | 2016-01–2026-05 | 123 | **5** | 2 | 6 | 1.00 | yes | control (no online date) |  |
| VA | county_download_fixed_basket | 2016-01–2026-05 | 109 | **5** | 1 | 87 | 1.00 | yes | not a switcher |  |
| WA | ets_internal_county_wa_2026-09-14 | 2017-01–2026-05 | 113 | **5** | -- | 1 | 1.00 | yes | control (no online date) |  |
| AK | county_download_fixed_basket | 2016-01–2026-06 | 125 | **4** | -- | 5 | 1.00 | yes | control (no online date) |  |
| AR | county_download_fixed_basket | 2016-01–2026-06 | 122 | **4** | 1 | 12 | 1.00 | yes | **switcher (full)** |  |
| DE | county_download_fixed_basket | 2016-01–2026-06 | 124 | **4** | -- | 3 | 1.00 | yes | **switcher (full)** |  |
| ID | id_courts_a12_2026-09-14 | 2021-01–2026-06 | 66 | **4** | -- | 44 | 1.00 | yes | excluded |  |
| IN | county_download_fixed_basket | 2016-01–2026-06 | 121 | **4** | 1 | 59 | 1.00 | yes | switcher (partial 3/13) |  |
| KY | county_download_fixed_basket | 2016-01–2026-06 | 118 | **4** | 1 | 45 | 1.00 | yes | switcher (partial 12/13) |  |
| MD | md_judiciary_lt_complaint_filings | 2012-01–2026-06 | 174 | **4** | -- | -- | -- | yes | **switcher (full)** |  |
| MN | county_download_fixed_basket | 2016-01–2026-06 | 106 | **4** | 2 | 22 | 1.00 | yes | control (no online date) |  |
| NC | county_download_fixed_basket | 2016-01–2026-06 | 126 | **4** | -- | 100 | 1.00 | yes | **switcher (full)** |  |
| NY | county_download_fixed_basket | 2019-01–2026-06 | 77 | **4** | -- | 53 | 1.00 | yes | not a switcher |  |
| OK | county_download_fixed_basket | 2016-01–2026-06 | 122 | **4** | -- | 33 | 1.00 | yes | control (no online date) |  |
| PA | county_download_fixed_basket | 2016-01–2026-06 | 119 | **4** | -- | 58 | 1.00 | yes | not a switcher |  |
| SC | county_download_fixed_basket | 2018-08–2026-06 | 94 | **4** | -- | 45 | 1.00 | yes | control (no online date) |  |
| TN | county_download_fixed_basket | 2016-01–2026-06 | 126 | **4** | -- | 3 | 1.00 | yes | not a switcher |  |
| VT | county_download_fixed_basket | 2016-01–2026-06 | 114 | **4** | -- | 9 | 1.00 | yes | **switcher (full)** |  |
| WV | county_download_fixed_basket | 2016-01–2026-06 | 119 | **4** | 1 | 25 | 1.00 | yes | switcher (partial 7/13) |  |
| OR | or_ojd_plus_evictedinoregon_2026-09-14 | 2018-01–2026-07 | 103 | **3** | -- | -- | -- | yes | switcher (partial 3/13) |  |
| ME | county_download_fixed_basket | 2016-01–2026-08 | 128 | **2** | -- | 16 | 1.00 | yes | **switcher (full)** |  |

## Known limits of this table

- It reports what the panel *contains*, not whether the upstream source has newer data. A state can look
  current and still be behind its provider.
- `basket_share` is computed against counties observed **in this panel**, not against all counties in the
  state. A state whose provider only ever covered 3 counties shows 1.00.
- Staleness is measured against today's date, so this file's numbers drift until it is regenerated.
