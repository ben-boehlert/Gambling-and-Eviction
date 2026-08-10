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
