# Eviction Code Fixes (2026-03-19)

## Scope

This change set fixes the active eviction analysis workflows that were using the wrong treatment timing or producing misleading output.

I did **not** edit any raw data files. The fixes are all in code and runner configuration.

Primary targets:

- `analysis/pretrends/pretrends_statepanel_template.R`
- `analysis/main/dose_response_iv.R`
- `scripts/run_pretrends_statepanel.sh`
- `scripts/run_dose_response_iv.sh`
- `utils/eviction_treatment_schedule.R` (new shared helper)

I did **not** spend time cleaning up older/stale launchers beyond the active eviction scripts above.

## What Changed

### 1. Canonical eviction treatment timing now comes from the legalization file

New helper:

- `utils/eviction_treatment_schedule.R`

What it does:

- Loads a state-level treatment schedule from `data/raw/sports_gambling_legalization_dates.csv`
- Defaults to `online_start_date`
- Supports an explicit fallback to panel-embedded treatment timing via `TREAT_SOURCE=panel`
- Returns a canonical `state_abb` / `treat_start` table for downstream joins

Why:

- The active eviction workflows were reading `treat_start` directly from `data/raw/state_month_panel_with_treatment.csv`, which reflects older panel-embedded timing rather than the intended online schedule.

Relevant code:

- `utils/eviction_treatment_schedule.R:10-105`

### 2. Eviction pretrends now use the canonical treatment schedule

File:

- `analysis/pretrends/pretrends_statepanel_template.R`

Changes:

- Added the shared treatment helper import at `:34`
- Added `TREAT_SOURCE`, `TREAT_FILE`, and `TREAT_DATE_COL` config at `:96-99`
- Stopped using panel-embedded `treat_start` as the main treatment source
- Added a comparison between file-based treatment dates and embedded panel dates, with mismatches logged at `:264-288`
- Stored treatment metadata in `panel_summary.csv` and README output

Why:

- This makes the live eviction pretrends pipeline match the intended estimand: online legalization by default.

Relevant code:

- `analysis/pretrends/pretrends_statepanel_template.R:214-291`
- `analysis/pretrends/pretrends_statepanel_template.R:333-341`
- `analysis/pretrends/pretrends_statepanel_template.R:1173-1185`

### 3. Bootstrap CS event-study confidence intervals now actually use the bootstrap critical value

File:

- `analysis/pretrends/pretrends_statepanel_template.R`

Changes:

- Replaced hard-coded normal `1.96 * se` interval construction with `crit_val * se` when a valid bootstrap critical value is available
- Falls back to the normal critical value only if `crit_val` is missing/nonpositive

Why:

- The previous code labeled the output as bootstrap but wrote normal-approximation confidence intervals to `event_study_cs_bootstrap.csv`.

Relevant code:

- `analysis/pretrends/pretrends_statepanel_template.R:668-684`

### 4. Dose-response IV now uses the same canonical treatment definition

File:

- `analysis/main/dose_response_iv.R`

Changes:

- Added the shared treatment helper import at `:31`
- Added `TREAT_SOURCE`, `TREAT_FILE`, and `TREAT_DATE_COL` config at `:90-94`
- Replaced direct reliance on panel `treat_start` with file-based treatment resolution at `:184-216`
- Logged any state-level disagreement between the legalization file and the panel-embedded treatment dates

Why:

- This keeps the eviction IV workflow aligned with the same online legalization definition as the pretrends pipeline.

Relevant code:

- `analysis/main/dose_response_iv.R:158-216`

### 5. Dose-response handle/revenue no longer silently turn post-launch missing values into zero

File:

- `analysis/main/dose_response_iv.R`

Changes:

- Reworked handle/revenue imputation so zeros are only used when the quantity is structurally zero:
  - never-treated states
  - pre-treatment months
  - months before the first observed handle date for a treated state
- Post-launch missing handle/revenue values are now kept as `NA`
- Added logging for post-launch missing handle observations that continuous/IV specs will drop

Why:

- The old code claimed to keep post-launch gaps as missing, but then immediately `coalesce()`d them to zero.

Relevant code:

- `analysis/main/dose_response_iv.R:247-342`

### 6. Dose-response specifications now run on the corrected analysis sample

File:

- `analysis/main/dose_response_iv.R`

Changes:

- Built an `analysis_panel` that excludes treated states with no handle data
- Switched the reduced form, OLS, IV, first stage, event study, LOO, and sub-period models to run on `analysis_panel`
- Expanded panel summary and README output to report:
  - full merged panel size
  - dose-response sample size
  - treatment source metadata
  - excluded treated no-handle states
  - post-launch missing-handle counts

Why:

- The script previously said those states were excluded but actually retained them with zero-filled post-treatment handle.

Relevant code:

- `analysis/main/dose_response_iv.R:323-404`
- `analysis/main/dose_response_iv.R:464-509`
- `analysis/main/dose_response_iv.R:600-665`
- `analysis/main/dose_response_iv.R:720-829`
- `analysis/main/dose_response_iv.R:843-898`

### 7. Dose-response descriptive summaries now respect missing-handle logic

File:

- `analysis/main/dose_response_iv.R`

Changes:

- Restricted descriptive handle summaries and histograms to finite `handle_per_1k`

Why:

- Once post-launch missing handle stays `NA`, descriptive summaries need to avoid turning the top-line mean/median into `NA`.

Relevant code:

- `analysis/main/dose_response_iv.R:363-404`

### 8. Runner defaults now match the intended treatment source and COVID exclusion window

Files:

- `scripts/run_pretrends_statepanel.sh`
- `scripts/run_dose_response_iv.sh`

Changes:

- Added runner-level exports for:
  - `TREAT_SOURCE`
  - `TREAT_FILE`
  - `TREAT_DATE_COL`
- Updated default `NO_COVID` drop window from `2020-03-01` through `2022-03-31` to `2020-03-01` through `2021-07-31`
- Printed the treatment configuration in the shell banner

Why:

- The old runner default over-dropped the sample and no longer reproduced the documented 91-month no-COVID panel.

Relevant code:

- `scripts/run_pretrends_statepanel.sh:22-45`
- `scripts/run_pretrends_statepanel.sh:85-95`
- `scripts/run_dose_response_iv.sh:21-42`
- `scripts/run_dose_response_iv.sh:62-76`

## Verification

### Syntax / shell checks

Passed:

- `Rscript -e "parse(file='analysis/pretrends/pretrends_statepanel_template.R'); parse(file='analysis/main/dose_response_iv.R'); parse(file='utils/eviction_treatment_schedule.R')"`
- `bash -n scripts/run_pretrends_statepanel.sh`
- `bash -n scripts/run_dose_response_iv.sh`

### Pretrends verification run

Command:

- `OUT_DIR=/tmp/pretrends_eviction_fix_test CS_BITERS=19 bash scripts/run_pretrends_statepanel.sh`

Confirmed from `/tmp/pretrends_eviction_fix_test/run_log.txt`:

- Treatment source is `file`
- Treatment date column is `online_start_date`
- Default COVID drop window is `2020-03-01` to `2021-07-31`
- Sample is back to `24 states`, `91 months`, `2184 obs`
- The script logs treatment mismatches versus embedded panel dates

Confirmed from `/tmp/pretrends_eviction_fix_test/event_study_cs_bootstrap.csv`:

- `ci_lo` / `ci_hi` now use the stored `crit_val` rather than `1.96`

### Dose-response verification runs

Commands:

- `OUT_DIR=/tmp/dose_response_iv_fix_test bash scripts/run_dose_response_iv.sh`
- `OUT_DIR=/tmp/dose_response_iv_fix_test2 LOO=FALSE SUBPERIOD=FALSE bash scripts/run_dose_response_iv.sh`

Confirmed from `/tmp/dose_response_iv_fix_test/run_log.txt`:

- Treatment source is `file`
- Treatment date column is `online_start_date`
- The script logs 14 states where embedded panel treatment dates disagree with the legalization file
- The corrected default no-COVID window is applied
- The full merged panel and the dose-response sample are reported separately

Confirmed from `/tmp/dose_response_iv_fix_test2/run_log.txt`:

- Post-treatment handle descriptive summaries are finite after the missing-handle fix

## Resulting Behavior

- The main eviction pretrends workflow now defaults to online legalization timing, not the stale panel-embedded treatment dates.
- The default no-COVID pretrends sample is back to the documented 91-month window.
- The bootstrap CS event-study CSV now has intervals consistent with the bootstrap critical value.
- The dose-response IV script now treats post-launch missing handle as missing rather than zero.
- The dose-response README/panel summary now document the actual treatment source and analysis sample.

## Remaining Notes

- I did not rewrite older/stale scripts outside the active eviction workflows above.
- I did not modify raw data files or committed output directories in the repo as part of verification; verification runs were written to `/tmp/...`.
