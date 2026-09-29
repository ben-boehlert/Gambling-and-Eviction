# data/raw/covariates — sources

Retrieved 2026-09-29 by `data_prep/build_state_covariates_2019.R` (API caches; delete a file to refetch). All are public state-level aggregates. Grain: one value per state (50 + DC).

| File | Source | Notes |
|---|---|---|
| `realtytrac_2010_foreclosure_laws.csv` | RealtyTrac "Foreclosure Laws Comparison", Wayback snapshot 20101230105753 of realtytrac.com/foreclosure-laws/foreclosure-laws-comparison.asp — the source Mian, Sufi & Trebbi (2015; NBER w16685, Fig. 2) cite | Parsed from the table's judicial / non-judicial bullets, comment and process-period columns. 20 states are judicial-only; they match MST's Fig. 2 map exactly. MST's text says 21 — the 21st is not identifiable from the map (HI/AK/DC not shown). 2010 vintage: later law changes are not reflected |
| `acs2019_profile_state.json` | Census ACS 2019 5-year data profile API (DP02_0068PE, DP03_0062E, DP04_0046PE, DP05_0024PE, DP05_0038PE, DP05_0071PE) | Keyed request (CENSUS_API_KEY from ~/.Renviron; the key is not stored in the file) |
| `bls_laus_state_ur_sa_2019.json` | BLS public API v1, LAUS series LASST{fips}0000000000003 (SA unemployment rate), 2019 | 2019 mean of 12 months |
| `fhfa_hpi_po_state.txt` | FHFA purchase-only state HPI, fhfa.gov/hpi/download/quarterly_datasets/hpi_po_state.txt | Seasonally adjusted index used |
| `hmda2019_orig_by_loantype_state.json` | CFPB HMDA Data Browser aggregations API, 2019, actions_taken=1, loan_types 1-4 | ALL loan purposes (API allows two filters) — refinances included |

SHA-256:
```
cebd99e5b27a22bd32703ec84c64cf216025bb0ca3010dc217febb61241f2728  realtytrac_2010_foreclosure_laws.csv
9dc5d6549bb349fde8e07cc4bc8661dda5be879eabb03eee099887f4894a1415  acs2019_profile_state.json
72b2083cf5c02f3eb624b90b1805eb20245edb0c2844196ae3626930af0c4ae7  bls_laus_state_ur_sa_2019.json
b99be7b1f19b81069064466ec8e4ff4881de4d5beb1375f73a17f6427eb72b2a  fhfa_hpi_po_state.txt
8e6b23c2bc343d1aada5f48f6d0ec560b9b1c6d8d73020a115b350a38a0c031c  hmda2019_orig_by_loantype_state.json
```

`deprecated/` holds three failed first fetches (Census missing-key HTML, BLS response missing DC, HMDA error response) kept per the no-delete rule.
