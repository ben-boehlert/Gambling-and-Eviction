# Illinois court eviction filings

## Source

The files in this directory are extracted from the Illinois Courts'
[2022–2025 Circuit Court Statistical Dashboard][dashboard], a public
Microsoft Power BI report. The Illinois Courts [dashboard landing page][landing]
states that these statistics come from quarterly reports submitted by circuit
court clerks and that published figures remain subject to review and revision.

Run the extractor from the repository root:

```bash
Rscript data_prep/pull_il_powerbi_eviction_filings.R
```

The script queries the Power BI semantic model directly. It does not scrape
screen text or automate filter clicks.

## Measure

The extraction applies both of the following source-data filters:

- `CASE_CATEGORY = "EVICTION"`
- `CASE_STATUS = "New Filed"`

`filings_count` is therefore the number of newly filed eviction cases reported
by each county in each calendar quarter. It is an aggregate case count, not
case-level microdata and not an executed-eviction measure.

## Files

- `il_county_quarter_eviction_filings.csv`: one row per Illinois
  county-quarter, including reported zeros and county FIPS codes. The
  `data_status` and `source_note` fields preserve reporting caveats.
- `il_state_quarter_eviction_filings.csv`: statewide reported sums plus counts
  of expected, reporting, and projected counties.

## Coverage and comparability

The current dashboard exposes 2022–2025 data. Illinois Courts provides a
separate 2018–2021 dashboard because the case-status and case-category
definitions changed in 2022. The older dashboard does **not** expose
`EVICTION` as a distinct case category, so the extractor intentionally does
not create a pre-2022 series from another civil category.

This distinction matters for the gambling-and-eviction project: the extracted
series begins after Illinois launched online sports betting, so it cannot by
itself provide Illinois pre-treatment observations for a DiD design.

## Source-specific data-quality flags

The dashboard's Information page identifies three relevant limitations, which
the county file encodes:

- Kankakee County's 2024 Q3 and Q4 statistics are projections based on
  historical quarterly totals (`data_status = "projected"`).
- Kankakee County's 2025 data are unavailable. Although the Power BI model
  returns zeros, the extractor codes these four values as missing
  (`data_status = "unavailable"`) so they cannot be mistaken for true zeros.
- Cook County's 2023 filing and closing counts may show variances associated
  with a case-management-system transition
  (`data_status = "reported_system_transition"`).

[dashboard]: https://app.powerbigov.us/view?r=eyJrIjoiMThmYmQxZTEtYWQxMi00NDliLTliNTEtYTQ4MzYzZDJjZTNkIiwidCI6ImRjNjQxZWU0LTViNWQtNDlhMC04ZmY0LTdhYWZjNjExOGE0MiJ9
[landing]: https://www.illinoiscourts.gov/courts/circuit-court/illinois-circuit-court-statistical-reports/
