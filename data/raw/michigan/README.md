# Michigan court eviction filing data

## What the official dashboard provides

The Michigan Courts Interactive Court Data Dashboard reports county-level
caseload statistics. For eviction filings, the relevant definition is:

- `CASE_TYPE_CODE = LT`
- `CASE_TYPE_NAME = Landlord/Tenant Summary Proceedings`
- `ACTION_NAME = New Filings`

Although the date field is named `QTR_END_DATE`, the public model currently
returns one December 31 observation per year. It does not contain monthly
county observations. The extraction therefore produces an annual county panel:

- `mi_county_year_landlord_tenant_filings.csv`
- `mi_state_year_landlord_tenant_filings.csv`

Run from the project root:

```r
Rscript data_prep/pull_mi_powerbi_eviction_filings.R
```

The extractor queries the public Power BI model directly and assigns Michigan
county FIPS codes. County-year combinations omitted by Power BI are retained
with `filings_count = NA` and `data_status = not_returned_by_source`; they are
not treated as zero.

## Why there is no county-month file

Michigan Courts separately publishes a PDF created from a Judicial Data
Warehouse report with monthly and weekly statewide landlord/tenant filings.
That report does not publish county-level values and identifies multiple
excluded jurisdictions:

- Berrien County
- Grand Rapids
- Dearborn Heights
- Center Line and Warren
- Northern Macomb County
- Grandville and Walker

Consequently, it cannot be joined to the annual county dashboard or allocated
across counties without inventing data. A valid Michigan county-month panel
would require a direct data release from the State Court Administrative Office
Judicial Data Warehouse or a separately published county-level extract.

## Sources

- Michigan Courts Interactive Court Data Dashboard:
  https://www.courts.michigan.gov/publications/statistics-and-reports/interactive-court-data-dashboard/
- Current statewide landlord/tenant filing report:
  https://www.courts.michigan.gov/49bb33/siteassets/covid/covid-19/conditional-dismissals.pdf

---

## Statewide weekly / monthly series from the JDW PDF (added 2026-09-03)

Extracted by [`data_prep/parse_mi_jdw_lt_filings_pdf.py`](../../../data_prep/parse_mi_jdw_lt_filings_pdf.py)
from `conditional-dismissals.pdf` (archived alongside these files; source URL in
the Sources section above). Requires `pdfplumber`.

| File | Grain | Cells |
| ---- | ----- | ----- |
| `mi_lt_statewide_week_year.csv` | week-of-year x year, 2019-2026 | 392 (53 weeks; complete) |
| `mi_lt_statewide_month_year.csv` | calendar month x year, 2019-2026 | 89 (68 populated, 21 unavailable) |

**These are statewide only.** The PDF publishes no county values, and it covers a
SMALLER footprint than the annual county dashboard: it excludes Berrien Co.,
Grand Rapids, Dearborn Hts, Center Line & Warren, Northern Macomb Co., and
Grandville & Walker. The two products are therefore not comparable, and this
series cannot be allocated across counties. Data is preliminary and unvetted by
individual courts; the refresh week and the week prior may be incomplete.

### Two traps in the source document

1. **Years are bars, and one colour is reused.** The bar chart's legend gives
   2019 and 2023 the *same* fill colour. Colour cannot identify a series; the
   parser assigns bars by their order within each month cluster and uses the
   legend colour only as an assertion.
2. **The bar labels are rotated and read bottom-to-top.** `pdfplumber`'s
   `extract_words()` assembles them in reverse: the May-2020 label `302` comes
   back as `203`. Palindromic values (545, 646) hide the bug. The parser rebuilds
   every label from raw characters and never uses `extract_words()` for them.

On the weekly table, cells are assigned to years by their right edge, never by
reading order, because blank cells would otherwise shift later values into the
wrong year column.

### Validation (the parser aborts on any failure)

- Each weekly row's year cells sum to that row's printed Total.
- Each year column sums to its printed annual total, and to the grand total
  1,090,431.
- Each bar's fill colour matches the legend colour for its position.
- For 2019 and 2022 — the two years whose twelve months are all labelled — the
  monthly values sum exactly to that year's published annual total.

### `source` column in the monthly file

- `chart_label` (65 cells) — read from a printed bar label.
- `derived_from_annual_total` (3 cells) — Jan 2020, Sep 2021, Jan 2026. Power BI
  omitted exactly one month's label in those years, so the value is the published
  annual total minus the labelled months. Exact, not estimated.
- `unlabelled_in_source` (21 cells) — two or more labels missing that year
  (2023, 2024, 2025), so no value is recoverable. Left empty, never zero.

### Do not build monthly figures from the weekly file

`week_month_bucket` is the month label the source attaches to each week, not a
calendar month. Weeks straddle month boundaries: of the 65 month-year cells where
both products can be compared, only 4 agree, with differences up to ~1,500
filings. Use `mi_lt_statewide_month_year.csv` for calendar months.
