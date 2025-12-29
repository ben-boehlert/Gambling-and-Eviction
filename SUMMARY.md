# Fixed Sun-Abraham & DiD Analysis - Summary

## What Was Fixed

### Problems in "Weird SA.R":
1. **Date parsing error**: Used incorrect format string for ETS month data (`"Jan-20"` format)
2. **Never-treated coding error**: Used `max_ym + 1L` instead of `0L` for `sunab()`
3. **Critical bug: `isTRUE()` in vectorized context**: This was causing ALL units to be marked as never-treated
4. **Missing proper aggregation**: Monthly data from different sources wasn't cleanly aggregated into a single panel

### Key Fixes Applied:
1. **Fixed date parsing**: Changed to `lubridate::my()` which correctly handles "Jan-20" format
2. **Fixed never-treated coding**: Use `0L` for never-treated units (required by `fixest::sunab()`)
3. **Fixed boolean logic**: Changed `isTRUE(has_online)` to `has_online == TRUE` for vectorized operations
4. **Ensured type consistency**: Made sure `g_online` and `ym` are both integers
5. **Proper data aggregation**: Aggregated ETS site-level data to state-month level for clean panel

## Results

### Analysis Completed Successfully:

**County-Month Panel (LSC Data, 2016-2025)**
- Sun-Abraham event study estimation completed
- 116,531 observations across 1,380 counties and 117 months
- 13 treated cohorts identified (states that legalized online gambling)
- Weighted by renter-occupied housing units
- Standard errors clustered at state level

### Key Findings from Sun-Abraham:
- **Pre-treatment periods (before month 0)**: Mixed evidence of pre-trends
- **Treatment effect at month 0**: -0.049 (SE: 0.023, p=0.043)
- **Post-treatment periods (months 1-36)**: Generally positive and significant effects
  - Month 16: +0.363 (p < 0.001) ***
  - Month 18: +0.316 (p < 0.001) ***
  - Month 26: +0.368 (p < 0.001) ***
- **Later periods (months 57+)**: Effects become negative and less precise

### Output Files Generated:
- `Fixed_SA_DiD.R` - Clean, working analysis script
- `SA_county_month.jpeg` - Event study plot for county-month panel
- `did_output_fixed.log` - Full analysis output log

## Data Structure

### Panels Created:

1. **County-Month Panel** (Main Analysis)
   - Source: LSC `monthly_county_data_download.csv`
   - Time span: 2016-01 to 2025-09 (117 months)
   - Units: 1,384 counties across 32 states
   - Treatment variable: Online gambling legalization date
   - Outcome: log(eviction filings + 1)

2. **State-Month Panel (ETS Sites)**
   - Source: `all_sites_monthly_2020_2021.csv` aggregated to state-month
   - Time span: 2020-01 to 2025-11 (71 months)
   - Units: 20 states
   - Aggregated 493 sites per state on average

3. **State-Month Panel (ETS AllStates)**
   - Source: `allstates_monthly_2020_2021.csv`
   - Time span: 2020-01 to 2025-11 (71 months)
   - Units: 10 states

### Treatment Cohorts (Online Gambling Legalization):
| State | Legalization Month (ym code) | Calendar Date |
|-------|------------------------------|---------------|
| New Jersey | 24224 | Aug 2018 |
| West Virginia | 24224 | Aug 2018 |
| Pennsylvania | 24233 | May 2019 |
| Iowa | 24236 | Aug 2019 |
| Indiana | 24238 | Oct 2019 |
| New Hampshire | 24240 | Dec 2019 |
| Colorado | 24245 | May 2020 |
| Tennessee | 24251 | Nov 2020 |
| Virginia | 24253 | Jan 2021 |
| Arizona | 24261 | Sep 2021 |
| Connecticut | 24262 | Oct 2021 |
| New York | 24265 | Jan 2022 |
| Arkansas | 24267 | Mar 2022 |
| Kansas | 24273 | Sep 2022 |
| Ohio | 24277 | Jan 2023 |

## Next Steps

To run your typical DiD estimators:
1. Use `Fixed_SA_DiD.R` as your base script
2. The script includes placeholders for:
   - Callaway-Sant'Anna (needs data.frame conversion for `did` package)
   - Borusyak-Jaravel-Spiess imputation
   - Standard TWFE for comparison

## Technical Notes

- **Weights**: County-month panel weighted by renter-occupied housing units
- **Clustering**: Standard errors clustered at state level (policy varies at state level)
- **Fixed effects**: County + time fixed effects
- **Reference periods**: Periods -1 and -2 (omitted as baseline)
- **Sample**: Balanced panel after dropping 4 singleton observations
