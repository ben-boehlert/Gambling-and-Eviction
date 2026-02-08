# CS-DiD Pre-Trends Analysis - Summary

## Status: CS-DiD Estimation Failed

The CS-DiD estimation encountered errors due to data structure issues:
- 64.1% of (g,t) cells are non-identifiable (n_treat_post=0)
- Too many small treatment groups (17 groups from 19 treated states)  
- Singular matrix errors in estimation

## What We Have

### ✅ Support Diagnostics (Complete)

**Files**:
- `pretrends_analysis_support_table.csv` - Full (g,t) support table (1044 rows)
- `pretrends_analysis_non_identifiable.csv` - Non-identifiable cells
- `pretrends_analysis_summary.txt` - Summary statistics
- `att_gt_safe_support_diagnostics.csv` - Duplicate support diagnostics

**Key Findings**:
- Total (g,t) cells: 1044
- Identifiable: 375 (35.9%)
- Non-identifiable: 669 (64.1%)
- Primary reason: treated units not observed post-treatment

### ❌ CS-DiD Estimates (Not Generated)

The estimation failed with error:
```
An unexpected error occurred, normally associated with a singular matrix 
due to not enough control units.
```

**Attempted estimators**:
1. Doubly-robust (DR) - Segfaulted (fastglm issue)
2. Inverse probability weighting (IPW) - Singular matrix
3. Regression (reg) - Singular matrix

## Why CS-DiD Failed

### Issue 1: Too Many Treatment Groups

With 19 treated states and 17 treatment groups:
- Very few states per group (many single-state groups)
- Not enough variation for robust estimation
- Warning message: "small groups in your dataset"

### Issue 2: Limited Post-Treatment Data

579 cells (55.4% of total) are non-identifiable because `n_treat_post=0`:
- Treated units drop out after treatment
- Event window [-12, +24] months is too long for later-treated states
- Data ends in 2025-09, but treatments continue through 2023-01

### Issue 3: Control Group Size

Only 12 never-treated states:
- Not enough controls for 17 treatment groups
- Some periods have very few control observations
- Causes singular matrices in propensity score estimation

## Recommendations

### Option 1: Simplify Treatment Structure

**Collapse treatment groups**:
```r
# Instead of 17 groups, create 3-4 treatment cohorts
panel_data <- panel_data %>%
  mutate(
    first_treat_collapsed = case_when(
      first_treat >= 201806 & first_treat < 201912 ~ 201806,  # Early adopters
      first_treat >= 201912 & first_treat < 202101 ~ 201912,  # Mid adopters
      first_treat >= 202101 ~ 202101,                         # Late adopters
      TRUE ~ 0
    )
  )
```

This reduces degrees of freedom and increases sample size per group.

### Option 2: Shorten Event Study Window

**Use [-6, +12] instead of [-12, +24]**:
```r
panel_filtered <- panel_data %>%
  filter(first_treat == 0 | (event_time >= -6 & event_time <= 12))
```

This increases identifiable cells for later-treated states.

### Option 3: Use Alternative Estimator

**Sun-Abraham or Borusyak et al.**:
```r
library(fixest)

# Sun-Abraham
result_sa <- feols(
  log_evictions ~ sunab(first_treat, year_month) | state_id + year_month,
  data = panel_data,
  cluster = ~state_id
)

# Event study plot
iplot(result_sa, xlim = c(-12, 24))
```

These estimators handle unbalanced panels better.

### Option 4: County-Level Analysis

Instead of aggregating to state level, use county-level data directly:
- More observations per (g,t) cell
- More variation
- Better identification

**Trade-off**: More computational burden, potential spatial correlation issues.

## Next Steps

1. **Review treatment structure**: Are all 17 groups necessary?
2. **Check data coverage**: Why do treated units drop out?
3. **Consider alternatives**: Sun-Abraham, Borusyak, or TWFE with unit/time FE
4. **Diagnostic plots**: Even without estimates, plot raw trends by treatment timing

## Files You Have

Location: `output/csdid_pretrends/`

- ✅ `pretrends_analysis_support_table.csv` - (g,t) support diagnostics
- ✅ `pretrends_analysis_summary.txt` - Summary statistics
- ✅ `att_gt_safe_support_diagnostics.csv` - Support check output
- ❌ No CS-DiD estimates (estimation failed)
- ❌ No pre-trends plots (requires estimates)

## View Support Diagnostics

```r
library(dplyr)

support <- read.csv("output/csdid_pretrends/pretrends_analysis_support_table.csv")

# Summary
table(support$identifiable)
table(support$reason)

# Which groups have problems?
support %>%
  group_by(g) %>%
  summarise(
    n_cells = n(),
    n_identifiable = sum(identifiable),
    pct_identifiable = 100 * mean(identifiable)
  ) %>%
  arrange(pct_identifiable)
```

## Bottom Line

The CS-DiD estimation cannot proceed with the current data structure:
- Too many treatment groups for available controls
- Too many non-identifiable cells (64.1%)
- Data limitations prevent robust estimation

**Recommendation**: Simplify treatment structure (collapse groups) OR use alternative estimator (Sun-Abraham).

---

**Generated**: 2026-01-19
**Data**: Gambling and Evictions, state-month panel
**Event window**: [-12, +24] months
**Sample**: 31 states, 1980 observations
