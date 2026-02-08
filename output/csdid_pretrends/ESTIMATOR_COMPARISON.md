# Event Study Estimator Comparison

## Summary of Results Across Three Approaches

This document compares three different estimators for the gambling-eviction event study:
1. **TWFE (Two-Way Fixed Effects)** - Standard approach
2. **Sun-Abraham (2021)** - Interaction-weighted estimator
3. **HAC Standard Errors** - TWFE with Newey-West autocorrelation correction

---

## Key Findings by Estimator

### 1. TWFE (Standard Two-Way Fixed Effects)

**Pre-trends Test:**
- χ²(11) = 1.31, p = 0.9998
- ✓ **Parallel trends STRONGLY supported**

**Treatment Effects:**
- No significant post-treatment effects detected
- Average effect: close to zero
- Interpretation: No detectable impact of gambling legalization on evictions

**Concerns:**
- With staggered adoption (17 treatment cohorts), TWFE may suffer from:
  - Negative weighting bias (Goodman-Bacon decomposition)
  - Treatment effect heterogeneity issues
- Test size verification shows rejection rate of only 0.6% (should be 5%)
  - **Standard errors are inflated by ~8x**
  - High autocorrelation (AR = 0.82) not properly accounted for

---

### 2. Sun-Abraham (Interaction-Weighted Estimator)

**Pre-trends Test:**
- χ²(11) = 53.14, p < 0.0001
- ✗ **Parallel trends VIOLATED**

**Treatment Effects:**
- 9 out of 24 post-treatment periods significant (37.5%)
- Average effect: -0.073 (7.3% reduction in log evictions)
- Range: [-0.78, 1.47]

**Significant Pre-Treatment Periods:**
- t = -11: coef = -0.67, SE = 0.16 ✓
- t = -10: coef = -0.61, SE = 0.22 ✓
- t = -3: coef = -0.50, SE = 0.19 ✓
- t = -2: coef = -0.80, SE = 0.30 ✓

**Significant Post-Treatment Periods:**
- t = 0: coef = -0.78, SE = 0.25 ✓
- t = 3: coef = -0.48, SE = 0.17 ✓
- t = 13-16: consistently negative and significant
- t = 18: coef = -0.37, SE = 0.15 ✓

**Concerns:**
- Some extremely large standard errors at specific time points:
  - t = -12: SE = 1632.02 (!!!)
  - t = -9: SE = 1536.04
  - t = -7: SE = 1536.00
  - t = 1: SE = 1374.37
  - t = 4: SE = 2748.66
  - t = 6: SE = 1374.40

  **This suggests estimation issues at these specific periods**, likely due to:
  - Very few treated cohorts at these event times
  - Insufficient overlap in treatment timing
  - Near-singularity in the interaction-weighted estimator

**Advantages:**
- Properly accounts for staggered treatment timing
- Avoids negative weighting problems in TWFE
- More appropriate for 17 treatment cohorts

---

### 3. HAC Standard Errors (Newey-West Correction)

**Purpose:** Account for high autocorrelation (AR = 0.82) in residuals

**Expected Results:**
- SEs should be 20-40% smaller than cluster-robust SEs
- Pre-trends test should be more powerful
- Post-treatment effects might become significant

**Status:** Script created but needs to be run to generate results

---

## Critical Issues Identified

### Issue 1: Standard Error Inflation in TWFE

**Evidence:**
- Permutation test: 0.6% rejection rate (should be 5%)
- Placebo dates: 0.0% rejection rate (should be 5%)
- Simulated DGP: 7.4% rejection rate

**Root Cause:**
- Cluster-robust SEs with only 32 clusters + AR(1) = 0.82
- The SE formula over-corrects, inflating SEs by ~8x
- This explains why simulations "always find zero effect"

**Impact:**
- Minimum detectable effect: 83%
- Power to detect 10% effect: 6.5%
- Power to detect 20% effect: 13.3%
- Cannot rule out economically meaningful effects < 80%

---

### Issue 2: Sun-Abraham Estimation Problems

**Evidence:**
- Massive standard errors (1000+) at specific event times
- These are not genuine - they indicate numerical issues

**Likely Causes:**
1. **Insufficient support**: Some event times have very few cohorts
2. **Cohort imbalance**: 17 cohorts spread across many periods
3. **Identification issues**: Certain (cohort, time) cells have weak identification

**Event times with issues:**
- Pre-period: -12, -9, -7
- Post-period: 1, 4, 6

These periods likely have:
- Only 1-2 cohorts providing identification
- Near-perfect collinearity with fixed effects
- Insufficient never-treated comparison units at those times

---

### Issue 3: Contradictory Pre-trends Results

| Estimator | Pre-trends p-value | Conclusion |
|-----------|-------------------|------------|
| TWFE | 0.9998 | Parallel trends supported |
| Sun-Abraham | < 0.0001 | Parallel trends violated |

**Explanation:**
- TWFE averages across all cohorts with potentially problematic weights
- Sun-Abraham properly weights by cohort, revealing violations
- The "clean" TWFE pre-trends may be **masking cohort-specific violations**

**Implication:**
- Sun-Abraham's rejection of parallel trends is more credible
- Different treatment cohorts may have different pre-trends
- This violates the parallel trends assumption needed for causal inference

---

## Recommendations

### Immediate Actions

1. **Investigate Sun-Abraham Outliers**
   - Identify which cohorts are driving the large SEs
   - Check data support at each (cohort, event_time) cell
   - Consider restricting to event times with adequate support

2. **Run HAC Standard Errors Analysis**
   ```bash
   Rscript scripts/event_study_with_hac.R
   ```
   - This will show if TWFE results become significant with proper SEs
   - Expected: some post-treatment effects may emerge

3. **Cohort-Specific Analysis**
   - Examine pre-trends separately for each treatment cohort
   - Identify which cohorts violate parallel trends
   - Consider excluding problematic cohorts

### Analysis Improvements

4. **Aggregate to Quarterly Data**
   - Reduces autocorrelation from 0.82 to ~0.3-0.5
   - Improves statistical power
   - More stable Sun-Abraham estimates

5. **Stacked DiD**
   - Create clean 2x2 comparisons for each cohort
   - Avoids issues with staggered adoption
   - More transparent identification

6. **Pre-trends Visualization**
   - Plot cohort-specific event studies
   - Show which cohorts drive the parallel trends violation
   - Help identify if violations are systematic or isolated

### Reporting Strategy

7. **Transparent Power Analysis**
   - Report MDE = 83% with current approach
   - State that effects < 80% cannot be detected
   - Frame results as "consistent with null or small effects"

8. **Report Multiple Estimators**
   - Show TWFE, Sun-Abraham, and HAC results side-by-side
   - Discuss why they differ
   - Be honest about limitations of each approach

9. **Focus on Robust Findings**
   - If HAC shows effects, report those as more credible
   - If Sun-Abraham shows violations, take that seriously
   - Don't cherry-pick the "cleanest" results

---

## Technical Details

### Sun-Abraham Large SE Interpretation

Standard errors > 1000 indicate:
- Near-singular variance-covariance matrix
- Extremely weak identification
- These estimates should be **excluded from analysis**

**Solution:** Filter results before interpretation:
```r
results_clean <- results %>%
  filter(se < 100)  # Remove numerical artifacts
```

### TWFE vs Sun-Abraham Differences

**When they agree:**
- Both approaches give similar results
- Staggered adoption is not causing major bias
- Safe to use either estimator

**When they disagree:**
- Sun-Abraham is generally more reliable
- TWFE may have negative weighting bias
- Treatment effects likely heterogeneous across cohorts

**In this case:** They disagree dramatically on both pre-trends and treatment effects, suggesting:
1. Significant treatment timing heterogeneity
2. TWFE is averaging in a misleading way
3. Parallel trends may not hold for all cohorts

---

## Next Steps

1. Run `scripts/event_study_with_hac.R` to get corrected TWFE results
2. Create cohort-specific event study plots
3. Investigate which cohorts drive Sun-Abraham's pre-trends violation
4. Consider aggregating to quarters and re-running all analyses
5. If parallel trends fail, consider:
   - Triple-differences approach
   - Synthetic control methods
   - Changes-in-changes estimator
   - Honest pre-trends adjustment (Rambachan & Roth 2023)

---

## Bottom Line

**Current Status:**
- TWFE shows clean pre-trends but has inflated SEs (unusable for inference)
- Sun-Abraham shows parallel trends violations + some treatment effects
- HAC correction needed to get accurate TWFE inference

**Most Credible Finding:**
- Parallel trends are violated (per Sun-Abraham)
- This undermines the causal interpretation of the event study
- Results should be reported with strong caveats

**Path Forward:**
1. Fix SE issues with HAC correction
2. Investigate and address parallel trends violations
3. Consider alternative identification strategies
4. Be transparent about power limitations (MDE = 83%)
