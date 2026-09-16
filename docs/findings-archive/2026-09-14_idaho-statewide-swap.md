# Idaho swapped to the statewide Idaho Judicial Branch series (2026-09-14; documented 2026-09-16)

**Panel: 42 states, 4,351 → 4,304 rows.** Idaho's Twin Falls-only LSC basket was replaced by a
statewide 44-county series (`data_prep/add_id_to_state_panel.R`, 15:12 on 2026-09-14). This is the
last step of the single 2026-09-14 vintage boundary (RUN_LEDGER.md, boundary 8). It was done in a
session concurrent with the WA/MI addition and reached STATE_SOURCES.md and DATA_CURRENCY.md, but not
CLAUDE.md, the ledger, FINDINGS.md or DATA_PROVENANCE.md until 2026-09-16, when it was also committed.

## What changed

| | Before | After |
|---|---|---|
| Source | LSC CCDI county download, fixed basket | Idaho Judicial Branch Case and Charge Data dashboard (Power BI, `courtdata.idaho.gov/Charge`) |
| Geography | Twin Falls County only — the one ID county clearing the fixed-basket rule (1 of 44, 10,312 renters) | All 44 counties |
| Definition | LSC eviction filings | Case type A12 Unlawful Detainer/Eviction, event **Filed**, juveniles excluded |
| Span | 2016-01..2025-05, 113 months | 2021-01..2026-06, 66 months, no interior gaps |
| Mean filings / month | 13.6 | 255.7 |
| `panel_source` | `county_download_fixed_basket` | `id_courts_a12_2026-09-14` |
| Denominator | 10,312 (Twin Falls) | Statewide ACS B25003_003, 186k–199k by ACS year (`fetch_acs_renter_denominators.R`) |
| Treatment | none | none — ID never legalized sports betting and has no schedule row (never-legalizer, unlike NV's always-treated absence) |

Puller: `data_prep/pull_id_powerbi_eviction_filings.R` (needs network). Output archived in
`data/raw/idaho/` (`id_state_month_a12.csv`, `id_county_month_a12.csv`, `id_pull_manifest.csv`).
Pre-swap panel: `data/raw/deprecated/state_month_panel_with_treatment_pre_id_statewide_2026-09-14.csv`.
Twin Falls series preserved verbatim: `data/raw/deprecated/id_twin_falls_lsc_series_pre_2026-09-14.csv`.

## Why it is a scope change AND a shortening, on purpose

The two series measure the same thing over different geography — the puller checks that Twin Falls
alone reproduces the LSC annual totals (2021–2024: 129/138/156/180 vs 129/138/155/180). Splicing the
1-county years onto the 44-county years inside one state column would be exactly the silent scope
break that contaminated RI/MO/NM before the 2026-09-14 single-series rebuild. The dashboard is a
**rolling five-year window** (CY2021..CY2025 plus FY2022..FY2026 as of the pull), so pre-2021 cannot
be retrieved from it and each January drops another year. Pre-2021 county-month Idaho needs a data
request to the Judicial Branch. Archive every pull; the source forgets.

## What it buys

- Idaho's volatility falls from rank 2 of 39 (SD of month-over-month log change 0.542) to about the
  panel median (0.165 vs 0.148), which is why ID sat on every `exclude_states` list.
- The post-COVID scenario (months after 2021-07) is covered in full with seven months to spare, so
  ID is usable in `mde_postcovid`. It remains unusable in `mde_spliced`, which needs 2016–2020.
- DATA_CURRENCY.md role: `excluded` (the clean-anchor rule excludes NV/ID/HI/MS by name). That
  exclusion predates the swap and was motivated by the Twin Falls noise; revisit it.

## The rebuild re-run that undid the ramp censor

`rebuild_state_month_panel.R` was re-run at 15:17 the same day to add ID, MI, WA and OR to
`KEEP_OLD` (without that, any rebuild silently reverts ID to Twin Falls and deletes MI/WA/OR —
confirmed: 4,304 → 4,020 rows, exit status 0). The re-run itself had a second silent effect: the
LSC states are rebuilt from the raw download, so **CT 2016-01 and 2016-02 — removed by
`censor_series_start_ramps.R` earlier that day — came back**. The panel sat at 4,306 rows until
2026-09-16, when the censor was re-applied (4,304) and the rebuild was changed to re-apply the
ramp-censor list itself. No blinded-power run executed on the 4,306-row file (no `v20260914`
output exists), so nothing is contaminated.

Invariants, restated:
- Every state whose series does not come from `monthly_county_data_download.csv` must be in
  `KEEP_OLD`, added in the same commit as its `add_*_to_state_panel.R` script.
- The ramp-censor list in `rebuild_state_month_panel.R` must match `CENSOR` in
  `censor_series_start_ramps.R`.
- `data/processed/state_panel_coverage_qa.csv` is written by the rebuild **before** the censor and
  still shows CT at 113 months; read spans off DATA_CURRENCY.md, not off that file.
