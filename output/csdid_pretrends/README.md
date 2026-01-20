# Event Study Analysis Results

**Last Updated:** January 19, 2026

This directory contains results from the event study analysis of gambling legalization's effect on eviction rates.

---

## 📊 Quick Start: Key Files

### Main Summary (START HERE)
- **[FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md)** - Complete analysis results, interpretation, and recommendations

### Technical Comparisons
- **[ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md)** - Detailed comparison of TWFE vs. Sun-Abraham vs. HAC
- **[diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md)** - Standard error issues and solutions

---

## 🔑 Key Findings

### 1. Standard Errors Are Inflated (8x)
- Test rejects null only 0.6% of time (should be 5%)
- Can only detect effects > 83%
- Root cause: High autocorrelation (AR = 0.82) + 32 clusters

### 2. Parallel Trends Violated
- Sun-Abraham: χ²(11) = 53.14, p < 0.0001
- Multiple significant pre-treatment deviations
- **Causal interpretation questionable**

### 3. Contradictory Estimator Results
- TWFE: Clean pre-trends, no treatment effects
- Sun-Abraham: Violated pre-trends, some negative effects
- Sun-Abraham more credible for staggered adoption

---

## 📁 Directory Structure

```
output/csdid_pretrends/
├── README.md                           # This file
├── FINAL_RESULTS_SUMMARY.md           # Main results (READ FIRST)
├── ESTIMATOR_COMPARISON.md            # Technical comparison
│
├── figures/
│   ├── event_study.pdf                # TWFE event study plot
│   ├── event_study.png
│   ├── event_study_sun_abraham.pdf    # Sun-Abraham plot
│   └── event_study_sun_abraham.png
│
├── diagnostics/
│   ├── RECOMMENDATIONS.md             # SE solutions
│   ├── sunab_filtered.pdf            # Sun-Abraham (cleaned)
│   ├── sunab_se_diagnosis.pdf        # SE diagnostic plot
│   ├── cohort_support_heatmap.pdf    # Data coverage viz
│   ├── test_size_verification.csv    # Proof SEs are inflated
│   ├── sunab_support_check.csv       # Support analysis
│   └── cohort_summary.csv            # Cohort information
│
├── event_study_results.csv           # TWFE coefficients
├── sun_abraham_results.csv           # Sun-Abraham coefficients
└── sun_abraham_results_filtered.csv  # Sun-Abraham (SE < 100)
```

---

## 📈 Results by Estimator

### TWFE (Two-Way Fixed Effects)
- **Pre-trends:** p = 0.9998 (parallel trends supported)
- **Treatment effects:** None significant
- **Problem:** Standard errors inflated 8x, cannot detect effects < 83%
- **Conclusion:** Not reliable due to SE issues

### Sun-Abraham (2021)
- **Pre-trends:** p < 0.0001 (parallel trends VIOLATED)
- **Treatment effects:** 9/24 periods significant, mostly negative
- **Average effect:** -7.3% reduction in log evictions
- **Problem:** Some numerical instability (6 event times have SE > 100)
- **Conclusion:** More appropriate for staggered adoption, but parallel trends violation is concerning

### HAC Standard Errors (Not Yet Run)
- **Script:** `scripts/event_study_with_hac.R`
- **Purpose:** Correct TWFE SEs for autocorrelation
- **Expected:** SEs shrink 20-40%, some effects may emerge

---

## ⚠️ Critical Limitations

1. **Parallel Trends Violated**
   - Cannot interpret results as causal
   - Treated states had different pre-trends than controls
   - Need alternative identification strategy

2. **Low Statistical Power**
   - Minimum detectable effect: 83%
   - Power for 20% effect: 13.3%
   - Cannot rule out economically meaningful effects

3. **Treatment Effect Heterogeneity**
   - 17 different treatment cohorts
   - Effects likely vary across states and time
   - Average may mask important variation

---

## 🔧 Next Steps

### Immediate (Priority)
1. Run `Rscript scripts/event_study_with_hac.R` for corrected SEs
2. Investigate which cohorts drive parallel trends violations
3. Create cohort-specific event study plots

### Short-term (For Paper)
1. Report all three estimators with full caveats
2. Present power analysis (MDE = 83%)
3. Discuss parallel trends violation openly
4. Frame as exploratory, not definitive

### Long-term (For Robustness)
1. Get county-level data (more clusters → more power)
2. Try synthetic control method (handles pre-trends)
3. Implement pre-trend adjustment (Rambachan & Roth 2023)
4. Investigate heterogeneity by state/gambling type

---

## 📚 References

- **Sun & Abraham (2021)** - "Estimating Dynamic Treatment Effects in Event Studies with Heterogeneous Treatment Effects"
- **Rambachan & Roth (2023)** - "A More Credible Approach to Parallel Trends"
- **Goodman-Bacon (2021)** - "Difference-in-differences with variation in treatment timing"

---

## 🤝 Questions?

See the detailed summaries:
1. [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) - Full results and interpretation
2. [ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md) - Technical details on why estimators differ
3. [diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md) - How to fix standard error issues

All analysis scripts are in `scripts/` directory at the project root.
