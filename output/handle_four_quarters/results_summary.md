# Sports-Betting Handle Four Quarters After Online Launch

## Answer

The table reports cross-state descriptive distributions of total reported Handle. The median is the preferred interpretation of ‘typically’ because state market sizes are highly skewed.

| Definition | N | Median 3-month Handle | Median monthly Handle | Median % of fixed pre-2025 peak | Median ratio to launch block | Median ratio to first full quarter |
|---|---:|---:|---:|---:|---:|---:|
| All states; months 9-11; window ends by Dec. 2024 | 28 | $0.44 billion | $0.15 billion | 41.5% | 1.23x | n/a |
| All states; months 12-14; window ends by Dec. 2024 | 25 | $0.73 billion | $0.24 billion | 59.4% | 1.98x | n/a |
| All states; fourth full quarter; window ends by Dec. 2024 | 26 | $0.63 billion | $0.21 billion | 45.9% | 1.53x | 1.36x |
| All states; fourth full quarter; extended Handle follow-up | 29 | $0.54 billion | $0.18 billion | 50.5% | 1.45x | 1.37x |
| Exact post-COVID panel launch cohort; extended Handle follow-up | 7 | $0.39 billion | $0.13 billion | 74.4% | 1.11x | 1.37x |
| Exact post-COVID panel launch cohort; window ends by Dec. 2024 | 5 | $0.54 billion | $0.18 billion | 69.6% | 0.93x | 1.32x |

Full means, quartiles, and dollar-weighted aggregate ratios are in 
`summary_statistics.csv`. These are descriptive statistics; standard 
errors, significance levels, and causal interpretations are not applicable.

## Definitions

- Operational online launch is `online_start_date` in the project 
  schedule. 
  Its recorded month is event month 0.
- The fourth post-launch exposure block is event months 9-11.
- Event quarter +4 is event months 12-14.
- The fourth full calendar quarter begins nine months after the first full 
  calendar quarter following the launch quarter. Its event-month 
  composition 
  varies with the launch month.
- The fixed peak uses online-era observations only, is capped at December 2024, and excludes March 2020 through July 2021.
- Handle is total reported Handle. The source does not split online from 
  retail Handle, so each state's retail-versus-online launch sequence 
  remains flagged.

## Coverage and measurement flags

- Scheduled online-launch states excluded from at least one headline distribution: Delaware, Florida, Maine, Missouri, North Carolina, Vermont.
- Incomplete windows are excluded rather than prorated; see 
  `exclusion_audit.csv` and `state_coverage_flags.csv`.
- The exact post-COVID eviction-panel launch cohort contains eight states: Kansas, Maryland, Ohio, Kentucky, Maine, Florida, Delaware, Vermont. Florida has no Handle series, leaving seven with observed extended fourth-quarter Handle.
- No seasonal adjustment is applied. Each state's exact calendar-month 
  composition is stored in `state_window_metrics.csv`, and pooled month 
  shares 
  are in `seasonality_composition.csv`.
- Ratios to the launch block compare with event months 0-2. The calendar 
  output also reports the ratio to the first full calendar quarter; this 
  is the preferred calendar-quarter ramp comparison.
- A pre-2025 benchmark is deliberately fixed before 2025. Later-state 
  windows can exceed 100% of that historical peak without constituting an 
  error.

## Paper-to-code naming map

| Paper notation | Code name | Description |
|---|---|---|
| H_it | `handle` | Reported total state-month Handle |
| G_i | `online_launch_month` | Operational online launch month |
| e_it | `event_month` | Months since launch; launch month = 0 |
| H_i^(peak,<2025) | `pre_2025_peak_handle` | Pre-2025 peak |
| R_iw | `handle_pct_pre_2025_peak` | Window average as percent of peak |
| Q_i^(full) | `first_full_quarter_start` | First full quarter |
