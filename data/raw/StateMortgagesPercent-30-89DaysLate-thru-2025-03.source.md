# StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv

- **Source:** CFPB Mortgage Performance Trends, state file, percent of mortgages 30–89 days delinquent.
- **URL:** https://files.consumerfinance.gov/data/mortgage-performance/downloads/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv
- **Retrieved:** 2026-09-29 (curl, generic user agent). 45,873 bytes.
- **SHA-256:** `0d5d705041bb4b3551a30d124b85c8220729569f7a7145a3f1bc8dc4bb887df8`
- **Grain / coverage:** wide format `RegionType,Name,FIPSCode,YYYY-MM…`; national + 51 state rows (incl. DC); 2008-01 → 2025-03. Same layout as the 90+ file (`StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv`), whose own provenance is still undocumented in DATA_PROVENANCE.md.
- **Caveats:** values rounded to 0.1pp (100% of 2016+ state-months on the 0.1 grid); minimum 0.3; median 1.5 (1.4 since 2022-06), about 2.3x the 90+ rate.
