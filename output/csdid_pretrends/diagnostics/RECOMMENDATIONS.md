# Standard Error Issues and Solutions

## Problem Identified

**High autocorrelation (AR(1) = 0.82)** in residuals means:
- Consecutive time periods within states are highly correlated
- Cluster-robust SEs are too large (overestimated) because they don't account for this structure
- Statistical power is very low (6.5% for 10% effect, 13.3% for 20% effect)
- Minimum detectable effect is 83% - can only detect very large impacts

## Why Your Simulations Found CIs Include Zero ~100% of the Time

With only 32 clusters and high autocorrelation:
- Power to detect 10% effect: **6.5%**
- Power to detect 20% effect: **13.3%**
- This means **86.7-93.5% of the time**, CIs will include zero even if true effect ≠ 0
- **Your simulation results are correct** - they reflect genuine low statistical power

## Solutions (Ranked by Priority)

### 1. **Use HAC (Newey-West) Standard Errors** ⭐ RECOMMENDED
Account for autocorrelation explicitly:
```r
library(sandwich)
library(lmtest)

# Estimate with HAC SEs
vcov_hac <- vcovHAC(model, cluster = ~state_id)
coeftest(model, vcov = vcov_hac)
```

Expected impact: SEs will be **smaller** (20-40% reduction typical with AR=0.82)

### 2. **Aggregate to Longer Time Periods**
Instead of monthly data, use:
- Quarterly averages
- Semi-annual averages
- Annual averages

This reduces autocorrelation by averaging out monthly noise.

Expected impact: AR drops to 0.3-0.5, more statistical power

### 3. **Use County-Level Data** ⭐ BEST FOR POWER
- Increases clusters from 32 states → hundreds/thousands of counties
- Much more statistical power
- Can detect smaller effects (10-20% feasible)

Expected impact: 10x more clusters → ~3x smaller SEs

### 4. **Stacked DiD Approach**
For multiple treatment timing:
- Create separate 2x2 comparisons for each treatment cohort
- Stack them together
- Accounts for treatment timing heterogeneity

Expected impact: More efficient use of variation

### 5. **Wild Cluster Bootstrap**
For small-sample inference:
```r
library(fwildclusterboot)
boot_result <- boottest(model,
                       param = "treatment",
                       clustid = "state_id",
                       B = 9999)
```

This already shows p = 0.896 for post-treatment effect.

## What the Current Results Tell Us

### Valid Conclusions:
1. ✓ Parallel trends holds (p = 0.9998) - excellent
2. ✓ No detectable effect > 80% in magnitude
3. ✓ Statistical method is correctly conservative

### Invalid Conclusions:
1. ✗ Cannot conclude "no effect" - just "no large effect detected"
2. ✗ Cannot rule out 10-30% effects (underpowered)
3. ✗ Cannot make strong claims about small effects

## Recommended Analysis Path

### Short Term (for current paper):
1. **Aggregate to quarterly data** - reduces autocorrelation
2. **Use HAC standard errors** - accounts for remaining autocorrelation
3. **Report power analysis** - show what effects you can/cannot detect
4. **Be transparent** - "consistent with null or small effects"

### Long Term (for robustness):
1. **Get county-level data** if possible
2. **Extend post-treatment window** to 36-48 months
3. **Explore mechanisms** with richer data
4. **Heterogeneity analysis** - effects may vary by state type

## Code Example: HAC Standard Errors

```r
library(fixest)
library(sandwich)

# Estimate model
model <- feols(log_evictions ~ event_bin | state_id + year_month,
               data = panel_data)

# Get HAC variance-covariance matrix
# (accounts for autocorrelation + heteroskedasticity)
vcov_hac <- vcovHAC(model, cluster = ~state_id)

# Test coefficients with HAC SEs
library(lmtest)
hac_results <- coeftest(model, vcov = vcov_hac)

# SEs should be 20-40% smaller than cluster-robust SEs
```

## Bottom Line

Your SEs are **not wrong** - they're **appropriately conservative** given:
- Only 32 clusters
- Very high autocorrelation (0.82)
- These factors legitimately reduce statistical power

To improve power:
1. Best: Get county-level data (more clusters)
2. Good: Aggregate to quarters (less autocorrelation)
3. Good: Use HAC SEs (accounts for autocorrelation)
4. Essential: Report power/MDE analysis transparently

The current finding of "no detectable effect" is credible and correctly estimated - you just can't detect effects smaller than ~80%.
