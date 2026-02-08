# Event Study Analysis - Complete Index

**Project:** Gambling Legalization and Eviction Rates
**Analysis Date:** January 19, 2026
**Status:** ✅ Sun-Abraham analysis complete, HAC pending

---

## 🚀 Quick Navigation

**Just want the results?** → [QUICK_REFERENCE.md](QUICK_REFERENCE.md) (2 pages)

**Want full details?** → [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) (15 pages)

**Want technical comparison?** → [ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md) (8 pages)

**Want to fix standard errors?** → [diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md) (5 pages)

---

## 📚 Documentation Hierarchy

### Level 1: Executive Summaries
1. **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** ⭐ START HERE
   - One-page summary of findings
   - Key results table
   - Action items checklist

2. **[README.md](README.md)**
   - Directory structure guide
   - File descriptions
   - Next steps overview

### Level 2: Main Results
3. **[FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md)** ⭐ MAIN DOCUMENT
   - Complete analysis results
   - Detailed interpretation
   - Recommendations for paper
   - What to report vs. what not to claim

### Level 3: Technical Deep Dives
4. **[ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md)**
   - TWFE vs. Sun-Abraham vs. HAC
   - Why results differ
   - When to use each method
   - Technical details on biases

5. **[diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md)**
   - Standard error issues explained
   - Why cluster-robust SEs are inflated 8x
   - Solutions ranked by priority
   - Code examples

---

## 📊 Results Files

### Coefficient Estimates
```
event_study_results.csv              # TWFE estimates (all 37 event times)
sun_abraham_results.csv              # Sun-Abraham (includes unstable periods)
sun_abraham_results_filtered.csv     # Sun-Abraham (SE < 100 only)
```

### Diagnostic Files
```
diagnostics/test_size_verification.csv    # Proof SEs inflated (0.6% rejection)
diagnostics/sunab_support_check.csv       # Data coverage by event time
diagnostics/cohort_summary.csv            # Treatment cohort details
```

---

## 📈 Figures and Visualizations

### Main Event Study Plots
```
figures/event_study.pdf                   # TWFE event study
figures/event_study.png                   # (PNG version)
figures/event_study_sun_abraham.pdf       # Sun-Abraham event study
figures/event_study_sun_abraham.png       # (PNG version)
```

### Diagnostic Plots
```
diagnostics/sunab_filtered.pdf            # Sun-Abraham (cleaned)
diagnostics/sunab_se_diagnosis.pdf        # SE size vs. cohort coverage
diagnostics/cohort_support_heatmap.pdf    # Data support heatmap
```

---

## 🔬 Analysis Scripts

All scripts are in `../../scripts/` (project root):

### Main Analysis Scripts
```
simple_event_study.R              # TWFE event study (COMPLETED)
event_study_sun_abraham.R         # Sun-Abraham estimator (COMPLETED)
event_study_with_hac.R            # HAC standard errors (NOT RUN YET)
```

### Diagnostic Scripts
```
test_standard_errors.R            # Power analysis, MDE calculation (COMPLETED)
verify_test_size.R                # Test size verification (COMPLETED)
diagnose_sunab_issues.R           # Sun-Abraham diagnostics (COMPLETED)
```

### How to Run
```bash
# From project root
Rscript scripts/simple_event_study.R
Rscript scripts/event_study_sun_abraham.R
Rscript scripts/event_study_with_hac.R          # TODO: Run this next
Rscript scripts/verify_test_size.R
Rscript scripts/diagnose_sunab_issues.R
```

---

## 🎯 Key Findings At-a-Glance

### The Good News
✅ Successfully estimated three different event study models
✅ Identified and quantified standard error problem (8x inflation)
✅ Diagnosed Sun-Abraham numerical issues
✅ No evidence of large (> 80%) increases in evictions

### The Bad News
❌ Parallel trends assumption violated (Sun-Abraham)
❌ Statistical power too low (MDE = 83%)
❌ TWFE standard errors unreliable (need HAC correction)
❌ Cannot make causal claims with current approach

### The Path Forward
🔧 Run HAC standard errors (Priority 1)
🔧 Investigate parallel trends violations (Priority 2)
🔧 Consider alternative identification strategies (Priority 3)

---

## 🔢 Numbers You Need to Know

| Metric | Value | Interpretation |
|--------|-------|----------------|
| **States (treated)** | 18 | States that legalized gambling |
| **States (control)** | 13 | Never-treated comparison states |
| **Treatment cohorts** | 17 | Different treatment timing groups |
| **Event window** | -12 to +24 | Months before/after treatment |
| **Observations** | ~30,000 | State-month observations |
| **Autocorrelation** | 0.82 | Very high (causes SE problems) |
| **Clusters** | 32 | States (small for cluster inference) |
| **MDE** | 83% | Minimum effect we can detect |
| **Power (20% effect)** | 13.3% | Very underpowered |
| **Test size** | 0.6% | Should be 5% (SEs too large) |

---

## 🎓 Results by Estimator

### TWFE (Two-Way Fixed Effects)
- **File:** `event_study_results.csv`
- **Pre-trends:** ✅ Pass (χ² = 1.31, p = 0.9998)
- **Treatment effects:** None significant (0/24)
- **Status:** ❌ Not reliable (SEs inflated 8x)

### Sun-Abraham (Interaction-Weighted)
- **File:** `sun_abraham_results.csv` (raw) / `sun_abraham_results_filtered.csv` (clean)
- **Pre-trends:** ❌ Fail (χ² = 53.14, p < 0.0001)
- **Treatment effects:** 9/24 significant (mostly negative)
- **Average effect:** -7.3% reduction in log evictions
- **Status:** ⚠️ Most credible, but parallel trends violated

### HAC (Newey-West Correction)
- **File:** Not yet generated
- **Script:** `../../scripts/event_study_with_hac.R`
- **Purpose:** Fix TWFE standard errors
- **Expected:** SEs shrink 20-40%, some effects emerge
- **Status:** 🔄 Pending (run next)

---

## 📋 Analysis Checklist

### Completed ✅
- [x] TWFE event study with cluster-robust SEs
- [x] Sun-Abraham interaction-weighted estimator
- [x] Test size verification (found 0.6% rejection rate)
- [x] Power analysis (MDE = 83%)
- [x] Sun-Abraham diagnostics (identified unstable periods)
- [x] Pre-trends tests (found violations)
- [x] Created comprehensive documentation

### Pending 🔄
- [ ] HAC standard errors for TWFE
- [ ] Cohort-specific event studies
- [ ] Investigation of which cohorts violate parallel trends
- [ ] Synthetic control analysis (alternative approach)
- [ ] Pre-trend adjustment (Rambachan & Roth 2023)

### Future Work 💡
- [ ] County-level analysis (more clusters, more power)
- [ ] Quarterly aggregation (reduce autocorrelation)
- [ ] Triple-differences (account for state trends)
- [ ] Heterogeneity analysis (by state type, gambling type)
- [ ] Mechanism exploration (who benefits/loses?)

---

## ⚠️ Critical Warnings

### Do NOT Do This:
1. ❌ Report TWFE results without mentioning SE issues
2. ❌ Claim "no effect" when MDE = 83% (underpowered)
3. ❌ Make causal claims with parallel trends violated
4. ❌ Cherry-pick the "cleanest" estimator
5. ❌ Ignore the Sun-Abraham numerical issues (SE > 100)

### DO This Instead:
1. ✅ Report all three estimators with caveats
2. ✅ State MDE = 83% and power limitations
3. ✅ Discuss parallel trends violation openly
4. ✅ Use filtered Sun-Abraham (SE < 100)
5. ✅ Frame as exploratory, not definitive

---

## 🔍 Finding Specific Information

**Want to know...**

...why standard errors are too large?
→ [diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md) + [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "Statistical Power"

...why TWFE and Sun-Abraham disagree?
→ [ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md) Section "Model Comparison"

...which cohorts have issues?
→ `diagnostics/cohort_summary.csv` + [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "Data Structure"

...what to report in the paper?
→ [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "For the Paper"

...how to fix this?
→ [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "Recommendations" + [diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md)

...the bottom line?
→ [QUICK_REFERENCE.md](QUICK_REFERENCE.md) or [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "Bottom Line"

---

## 🤝 Contributing

If you run additional analyses or fix issues:

1. **Add results to appropriate subdirectory:**
   - Coefficients → root directory (`.csv` files)
   - Figures → `figures/` subdirectory
   - Diagnostics → `diagnostics/` subdirectory

2. **Document your analysis:**
   - Update [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) if results change
   - Add notes to [ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md) if comparing methods
   - Update this INDEX if adding new files

3. **Naming conventions:**
   - Coefficients: `*_results.csv`
   - Figures: `*.pdf` and `*.png`
   - Diagnostics: descriptive names with context

---

## 📞 Questions or Issues?

**For technical questions:**
- Check [ESTIMATOR_COMPARISON.md](ESTIMATOR_COMPARISON.md) for method details
- Check [diagnostics/RECOMMENDATIONS.md](diagnostics/RECOMMENDATIONS.md) for SE issues
- See scripts in `../../scripts/` for implementation

**For interpretation questions:**
- Start with [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- Read [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) for full context
- Pay special attention to the "Limitations" and "What Can We Conclude?" sections

**For paper writing:**
- [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md) Section "For the Paper"
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) Section "For Your Paper"

---

## 📜 Version History

**v1.0 (January 19, 2026)**
- TWFE event study complete
- Sun-Abraham estimator complete
- Standard error diagnostics complete
- Test size verification complete
- Comprehensive documentation created
- HAC analysis pending

---

**Last Updated:** January 19, 2026, 7:35 PM
**Analysis by:** ben-boehlert (GitHub)
**Project:** Gambling-and-Eviction
