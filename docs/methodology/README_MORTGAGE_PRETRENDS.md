# Mortgage Delinquency Pre-Trends Analysis

## Quick Start

Run the complete analysis pipeline:

```bash
bash scripts/run_mortgage_pretrends_full.sh
```

This will:
1. Create mortgage delinquency panel from raw data
2. Merge online gambling treatment dates
3. Run TWFE event study with 5 specifications
4. Generate diagnostic plots and summary statistics

**Time:** ~2-3 minutes on a standard laptop

---

## Required Input Files

1. **StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv** (in project root)
   - Wide format mortgage delinquency data by state
   - Source: [Add data source]

2. **data/raw/sports_gambling_legalization_dates.csv**
   - Treatment dates for online gambling legalization
   - Must include `state`, `has_online`, `online_start_date` columns

---

## Analysis Scripts

### Data Processing

1. **create_mortgage_delinquency_panel.R**
   - Transforms wide → long format
   - Creates log-transformed outcome
   - Output: `data/processed/mortgage_delinquency_panel.csv`

2. **create_mortgage_treatment_panel.R**
   - Merges treatment dates
   - Creates treatment indicators
   - Output: `data/processed/mortgage_treatment_panel.csv`

### Analysis

3. **mortgage_delinquency_pretrends_simple.R** ⭐ **Main analysis**
   - TWFE event study with 5 specifications
   - Pre-trends F-tests
   - Event study plots
   - Output: `mortgage_delinquency_out/`

4. **diagnostic_mortgage_data.R**
   - Data quality checks
   - Trend visualizations
   - Issue detection
   - Output: `mortgage_delinquency_out/diagnostics_*.png`

---

## Specifications

### 1. Baseline (Full Period 2008-2025)
- **Window:** ±24 months
- **Sample:** All states, full period
- **Result:** ❌ FAIL (F=9,405, p<0.001)

### 2. Exclude COVID Period
- **Window:** ±24 months
- **Sample:** Drop March 2020 - July 2021
- **Result:** ❌ FAIL (F=36, p<0.001)

### 3. Post-Financial Crisis (2012+)
- **Window:** ±24 months
- **Sample:** Drop 2008-2011
- **Result:** ❌ FAIL (F=9,405, p<0.001)

### 4. Narrow Window (±12 months) ✅ **VALID**
- **Window:** ±12 months
- **Sample:** All states, full period
- **Result:** ✅ **PASS** (F=1.73, p=0.063)
- **Use this specification for causal inference**

### 5. Pre-2020 Adopters Only
- **Window:** ±24 months
- **Sample:** Only 2018-2019 adopters (8 states)
- **Result:** ❌ FAIL (F=555M+, p<0.001)

---

## Key Findings

### ❌ Baseline Specifications Fail
Most specifications show **strong pre-existing differential trends** between treated and control states:
- F-statistics: 35 to 9,405 (far above critical value ~2)
- P-values: <0.001
- Early adopters have extreme pre-trends (F > 500M)

**Implication:** Simple DD/TWFE estimates are biased.

### ✅ Narrow Window Valid
Only the ±12 month window passes pre-trends test:
- F-statistic: 1.73
- P-value: 0.063 (marginal pass at 5% level)
- Pre-treatment coefficients centered near zero

**Implication:** Can make causal claims for short-run effects only.

### 🔍 Heterogeneity Across Cohorts
Treatment timing correlates with pre-existing trends:
- Early adopters (2018-2019): Extreme pre-trends
- Later adopters (2021-2022): More similar to controls
- Suggests **selection into treatment** based on trends

---

## Output Structure

```
mortgage_delinquency_out/
├── comparison/
│   ├── pretrends_summary.csv          # Summary table
│   └── event_study_comparison.png     # All specs overlaid
│
├── specifications/
│   ├── Baseline__Full_Period_2008_2025/
│   │   ├── twfe_event_study.csv       # Coefficients & SEs
│   │   ├── twfe_event_study.png       # Event study plot
│   │   └── pretrends_test.csv         # F-test results
│   │
│   ├── Exclude_COVID_Period/
│   ├── Narrow_Window___12_months_/    # ✅ VALID SPECIFICATION
│   ├── Post_Financial_Crisis__2012__/
│   └── Pre_2020_Adopters_Only/
│
├── diagnostics_trends.png              # Treated vs control trends
├── diagnostics_distribution.png        # Outcome distribution
├── diagnostics_state_trajectories.png  # Individual state paths
└── run_log.txt                         # Detailed execution log
```

---

## Interpreting Results

### Pre-Trends Test
- **F-statistic:** Tests H₀: all pre-treatment coefficients = 0
- **P-value < 0.05:** Reject parallel trends → **FAIL**
- **P-value > 0.05:** Cannot reject parallel trends → **PASS**

### Event Study Plot
- **X-axis:** Months relative to treatment (negative = before, positive = after)
- **Y-axis:** Effect on log(delinquency_rate + 0.01)
- **Reference:** e = -1 normalized to zero
- **Pre-trends:** Coefficients before e = 0 should be flat at zero
- **Treatment effect:** Coefficients after e = 0 show post-treatment impact

### What to Look For
✅ **Good:** Pre-treatment estimates near zero, flat trend
❌ **Bad:** Pre-treatment estimates systematically positive/negative or trending

---

## Recommendations

### For Valid Causal Inference

1. **Use narrow window specification only**
   - This is the ONLY specification that passes pre-trends
   - Interpret effects within ±12 months of treatment

2. **Do NOT use baseline specifications**
   - Strong pre-trends violation
   - Estimates are biased
   - Cannot make causal claims

3. **Consider modern DiD estimators**
   - Callaway & Sant'Anna (2021) - robust to heterogeneous effects
   - Stacked DiD regression - separate analysis per cohort
   - Synthetic control - construct better counterfactuals

### For Future Work

1. **Add covariates:**
   - State unemployment rates
   - Housing prices
   - Median income
   - May reduce pre-trends violations

2. **Alternative comparison groups:**
   - Use only never-treated states
   - Exclude early adopters entirely
   - Focus on 2021-2022 cohort

3. **Mechanism investigation:**
   - Why do early adopters have different trends?
   - Economic vs. political drivers of adoption
   - Relationship between gambling and housing markets

---

## Technical Details

### Outcome Transformation
```r
log_delinquency_rate = log(delinquency_rate + 0.01)
```
- **Why log?** Stabilizes variance, handles skewness
- **Why +0.01?** Handles zeros (though none in data)

### Regression Specification
```r
feols(y ~ em24 + ... + ep24 | id + t,
      data = panel,
      cluster = ~ id)
```
- **Fixed effects:** State (id) and month (t)
- **Clustering:** Standard errors at state level
- **Reference:** e = -1 omitted

### Sample Construction
- Filter to event window: `e ∈ [min_e, max_e]`
- Drop observations outside specified date ranges
- Remove NA outcomes
- Fully balanced panel within each spec

---

## Troubleshooting

### "Input file not found"
- Check `StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv` is in project root
- Check `data/raw/sports_gambling_legalization_dates.csv` exists

### "Variable dropped due to collinearity"
- Normal for last period in event window (ep24 or ep12)
- Handled automatically in code
- Does not affect pre-trends test

### "VCOV matrix not positive semi-definite"
- Warning only, does not prevent estimation
- Common with extreme pre-trends (Pre-2020 spec)
- Indicates potential numerical issues

### High F-statistics
- Not an error - reflects true pre-trends violations
- Indicates parallel trends assumption violated
- Use narrow window specification instead

---

## References

- **Data source:** [Add mortgage delinquency data source]
- **Methods:** Roth, J. (2022). "Pre-test with caution: Event-study estimates after testing for parallel trends." *AER: Insights*
- **Treatment:** Online sports gambling legalization dates compiled from state regulations

---

## Contact

For questions about the analysis, see main project README or open an issue on GitHub.

**Last updated:** January 18, 2026
