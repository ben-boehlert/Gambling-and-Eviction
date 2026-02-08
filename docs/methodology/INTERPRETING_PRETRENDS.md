# Interpreting Pre-Trends Test Results

A practical guide to understanding your pre-trends diagnostics output.

## Quick Diagnostic Checklist

Start by checking these files in order:

### 1. `diagnostic_summary.csv`
**What to look for:**
- ✅ "CS-DiD completed" = "Yes"
- ✅ "TWFE completed" = "Yes" (if RUN_TWFE_ES=TRUE)
- ⚠️ If either shows "FAILED", check `run_pretrends.log` for details

### 2. `cohort_sizes.csv`
**What to look for:**
- `n_units`: How many states in each treatment cohort
  - ⚠️ Cohorts with < 3 units may cause singularity issues
- `n_pre_periods`: How many pre-treatment periods available
  - ⚠️ Cohorts with < 2 pre-periods can't estimate leads

**Example:**
```csv
g,n_units,first_period,n_pre_periods
24235,5,24192,43    # Good: 5 units, 43 pre-periods
24277,1,24192,85    # Warning: only 1 unit (may fail)
24262,3,24260,2     # Warning: only 2 pre-periods
```

### 3. `cs_pretrends_joint_test.csv`
**What to look for:**
```csv
ok,method,n_leads,wald,df,p_value
TRUE,chi-square Wald using aggte vcov,24,18.34,24,0.784
```

**Interpretation:**
- `ok = TRUE`: Test successfully computed
- `n_leads`: Number of pre-treatment periods tested (e.g., 24 months)
- `wald`: Test statistic (higher = more evidence against null)
- `p_value`: **THIS IS THE KEY NUMBER**

**Decision rule:**
- **p > 0.05**: ✅ **Fail to reject** → No evidence against parallel trends (GOOD)
- **p < 0.05**: ⚠️ **Reject** → Evidence of pre-trends (CONCERN)

### 4. `cs_event_study.csv` and `.png`
**What to look for:**

In the CSV, focus on pre-treatment rows (`e < 0`):
```csv
e,att,se,z,p,lo,hi
-24,0.0123,0.0456,0.27,0.787,-0.077,0.102
-23,-0.0089,0.0445,-0.20,0.842,-0.096,0.078
...
-1,0.0234,0.0512,0.46,0.648,-0.077,0.124   # Reference period
0,0.1456,0.0534,2.73,0.006,0.041,0.250     # Treatment begins
```

**Visual inspection (from PNG plot):**
- ✅ Pre-treatment coefficients should **hover around zero**
- ✅ Confidence intervals should **cross zero**
- ⚠️ Systematic upward/downward slope is **concerning**
- ✅ Post-treatment jump indicates treatment effect

### 5. `twfe_pretrends_joint_test.csv` (if available)
Similar interpretation to CS-DiD test:
```csv
ok,method,n_leads,f_stat,df1,df2,p_value
TRUE,F-test on pre-treatment coefficients,24,0.89,24,2547,0.615
```

- **p > 0.05**: ✅ No evidence against parallel trends
- **p < 0.05**: ⚠️ Evidence of pre-trends

## Common Scenarios

### Scenario 1: Clean Pre-Trends ✅
**Results:**
- CS-DiD joint test: p = 0.784
- TWFE F-test: p = 0.615
- Visual: Pre-treatment coefficients scattered around zero

**Interpretation:**
- **Strong support** for parallel trends assumption
- Proceed with DiD analysis confidently
- Report: "Joint test fails to reject parallel trends (p = 0.78)"

---

### Scenario 2: Borderline Pre-Trends ⚠️
**Results:**
- CS-DiD joint test: p = 0.08
- TWFE F-test: p = 0.12
- Visual: Slight upward trend but noisy

**Interpretation:**
- **Weak evidence** against parallel trends
- Not statistically significant at α = 0.05, but close
- Consider:
  1. Adjusting for time-varying covariates
  2. Restricting to shorter pre-period
  3. Reporting with caveat about borderline trends

---

### Scenario 3: Clear Pre-Trends Violation ❌
**Results:**
- CS-DiD joint test: p = 0.003
- TWFE F-test: p = 0.001
- Visual: Strong monotonic trend pre-treatment

**Interpretation:**
- **Strong evidence** against parallel trends
- Parallel trends assumption likely violated
- Options:
  1. **Add covariates**: Control for confounders
  2. **Alternative estimator**: Synthetic control, matching
  3. **Different specification**: Change outcome transformation
  4. **Acknowledge limitation**: Report with strong caveats

---

### Scenario 4: CS-DiD and TWFE Disagree
**Results:**
- CS-DiD joint test: p = 0.45 ✅
- TWFE F-test: p = 0.02 ❌
- Visual: CS plot looks good, TWFE shows trend

**Interpretation:**
- **Trust CS-DiD** (more robust to heterogeneity)
- TWFE may be picking up treatment effect heterogeneity
- This is evidence that TWFE would be biased
- Report CS-DiD results as primary

---

## Red Flags to Watch For

### 🚩 Systematic Pre-Trend
**Visual**: Clear slope (upward or downward) before treatment
**Statistical**: Low p-value (< 0.05)
**Action**: Don't proceed with standard DiD without adjustment

### 🚩 Very Few Pre-Periods
**Check**: `cohort_sizes.csv` shows many cohorts with `n_pre_periods < 5`
**Problem**: Not enough data to test pre-trends
**Action**: Consider grouping cohorts or using alternative window

### 🚩 Massive Treatment Effect Heterogeneity
**Check**: CS-DiD and TWFE give wildly different estimates
**Visual**: TWFE plot shows strong pre-trend, CS-DiD doesn't
**Problem**: TWFE is contaminated by heterogeneity
**Action**: Rely exclusively on CS-DiD, mention TWFE is biased

### 🚩 Single Large Lead Coefficient
**Visual**: One pre-treatment coefficient is huge, others are zero
**Check**: Is that coefficient statistically significant?
**Problem**: Could be spurious or early anticipation effect
**Action**: Investigate that specific period, consider robustness checks

## Reporting in Papers

### If Pre-Trends Pass (p > 0.05):

> "We test the parallel trends assumption using the method of Callaway and Sant'Anna (2021). A joint Wald test of the null hypothesis that all pre-treatment ATTs equal zero fails to reject (χ² = 18.34, df = 24, p = 0.78). Figure X displays the event-study estimates, showing no systematic pre-treatment trend."

### If Pre-Trends Fail (p < 0.05):

> "A joint test of pre-treatment coefficients rejects the null of parallel trends (χ² = 45.67, df = 24, p = 0.003), suggesting potential confounding. To address this, we [add covariates / use alternative specification / acknowledge as limitation]."

### If Borderline (0.05 < p < 0.10):

> "A joint test of pre-treatment coefficients yields p = 0.08, providing weak evidence against parallel trends. Visual inspection (Figure X) reveals [describe pattern]. We proceed with caution and interpret results as [suggestive / preliminary / requiring validation]."

## Next Steps After Pre-Trends Testing

### ✅ If Pre-Trends Pass:
1. Proceed with main DiD analysis
2. Report CS-DiD estimates as primary results
3. Include event-study plot in paper
4. Report joint test results in text or table notes

### ⚠️ If Pre-Trends Fail:
1. **Investigate**: What's driving the pre-trend?
   - Time-varying confounders?
   - Anticipation effects?
   - Misspecification of timing?

2. **Adjust specification**:
   - Add time-varying controls
   - Use different outcome transformation
   - Restrict to subset of cohorts

3. **Alternative estimators**:
   - Synthetic control method
   - Matching estimators
   - Instrumental variables

4. **Sensitivity analysis**:
   - Drop problematic cohorts
   - Restrict event window
   - Use different control group

## File Reference Guide

| File | Purpose | Key Info |
|------|---------|----------|
| `diagnostic_summary.csv` | High-level status | Did things run? |
| `panel_summary.csv` | Sample description | N states, periods, observations |
| `cohort_sizes.csv` | Cohort diagnostics | Which cohorts are small/problematic? |
| `cs_event_study.csv` | CS-DiD estimates | ATT by event time |
| `cs_event_study.png` | CS-DiD plot | Visual pre-trends check |
| `cs_pretrends_joint_test.csv` | **Main test result** | **p-value for parallel trends** |
| `twfe_event_study.csv` | TWFE estimates | Comparison to CS-DiD |
| `twfe_pretrends_joint_test.csv` | TWFE test | Alternative test statistic |
| `run_pretrends.log` | Detailed log | Warnings, diagnostics, metadata |

## Questions?

Common questions and where to find answers:

**Q: Do my pre-trends look good?**
→ Check `cs_pretrends_joint_test.csv` p-value and `cs_event_study.png`

**Q: Why are some event times missing?**
→ Check `support_by_event_time.csv` for sample size at each event time

**Q: Why do CS-DiD and TWFE differ?**
→ Treatment effect heterogeneity (this is expected, trust CS-DiD)

**Q: What if some cohorts failed?**
→ Check `cohort_sizes.csv` and `run_pretrends.log` for details

**Q: Should I worry about warnings?**
→ Check the troubleshooting section in README_PRETRENDS.md
