# Event Study Analysis - Quick Reference Card

**Analysis:** Gambling Legalization → Eviction Rates
**Date:** January 19, 2026
**Read Full Results:** [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md)

---

## 📊 Data

- **18 treated states** (17 cohorts, staggered 2018-2023)
- **13 never-treated control states**
- **Event window:** -12 to +24 months
- **Outcome:** log(evictions per 1,000 renters)

---

## 🎯 Bottom Line

### What We Know
✅ Standard errors are inflated by ~8x (can only detect effects > 83%)
✅ Sun-Abraham reveals parallel trends violations
✅ No evidence of large (> 80%) increases in evictions

### What We DON'T Know
❌ Cannot conclude "no effect" (underpowered)
❌ Cannot claim causal effects (parallel trends violated)
❌ Cannot rule out 10-50% effects

### Honest Conclusion
> "No detectable large effect, but parallel trends violations and low power prevent causal conclusions. Consistent with null, small effects, or effects masked by pre-existing differential trends."

---

## 📉 Results Summary

| Estimator | Pre-trends | Treatment Effects | Reliability |
|-----------|------------|-------------------|-------------|
| **TWFE** | ✓ Pass (p=0.9998) | None significant | ❌ SEs inflated 8x |
| **Sun-Abraham** | ✗ Fail (p<0.0001) | 9/24 significant (negative) | ⚠️ Best available, but pre-trends violated |
| **HAC** | Not run yet | TBD | 🔄 Should fix TWFE SEs |

---

## ⚠️ Three Critical Issues

### 1. Standard Errors Too Large (TWFE)
- **Evidence:** Test rejects null 0.6% of time (should be 5%)
- **Cause:** AR(1) = 0.82 + 32 clusters → SE formula over-corrects
- **Impact:** MDE = 83%, power for 20% effect = 13.3%
- **Fix:** Use HAC standard errors → reduce SEs by 20-40%

### 2. Parallel Trends Violated (Sun-Abraham)
- **Evidence:** χ²(11) = 53.14, p < 0.0001
- **Details:** 4 of 11 pre-periods significantly different from zero
- **Impact:** Cannot interpret post-treatment effects as causal
- **Fix:** Synthetic control, pre-trend adjustment, or triple-differences

### 3. Sun-Abraham Numerical Issues
- **Evidence:** 6 event times have SE > 1000
- **Cause:** Only 17-19 observations at those specific cohort × time cells
- **Impact:** These estimates are artifacts, must be excluded
- **Fix:** Use filtered results (SE < 100)

---

## 📈 Treatment Effect Estimates

### TWFE (Not Reliable)
- All 24 post-treatment periods: not significant
- Average effect: ≈ 0
- **Problem:** Cannot detect anything < 83%

### Sun-Abraham (More Credible, But...)
- 9 of 24 periods significant (37.5%)
- Average effect: -0.073 (7.3% reduction)
- Notable: t=0 shows -54% reduction (p<0.05)
- **Problem:** Parallel trends violated → not causal

---

## 🔧 Immediate Action Items

1. **Run HAC analysis** (Priority 1)
   ```bash
   Rscript scripts/event_study_with_hac.R
   ```
   Corrects TWFE standard errors for autocorrelation

2. **Investigate pre-trends** (Priority 2)
   - Which cohorts drive violations?
   - Can we exclude problematic cohorts?
   - Try synthetic control instead

3. **Report transparently** (Priority 3)
   - Show all three estimators
   - Report MDE = 83%
   - Discuss parallel trends violation
   - Don't overclaim

---

## 📂 Key Files

### Start Here
- `FINAL_RESULTS_SUMMARY.md` - Complete results (15 pages)
- `ESTIMATOR_COMPARISON.md` - Technical comparison (8 pages)

### Main Figures
- `figures/event_study.pdf` - TWFE plot
- `figures/event_study_sun_abraham.pdf` - Sun-Abraham plot
- `diagnostics/sunab_filtered.pdf` - Sun-Abraham (cleaned)

### Data Files
- `event_study_results.csv` - TWFE coefficients
- `sun_abraham_results.csv` - Sun-Abraham coefficients
- `sun_abraham_results_filtered.csv` - Sun-Abraham (SE < 100)

### Diagnostics
- `diagnostics/test_size_verification.csv` - Proof SEs inflated
- `diagnostics/sunab_support_check.csv` - Support analysis
- `diagnostics/cohort_summary.csv` - Cohort info

---

## 🎓 For Your Paper

### What to Report
1. ✅ All three estimators (TWFE, Sun-Abraham, HAC)
2. ✅ Pre-trends test results (show violation)
3. ✅ Power analysis (MDE = 83%)
4. ✅ Limitations (parallel trends, low power)

### What NOT to Claim
1. ❌ "Gambling has no effect on evictions"
2. ❌ "Gambling reduces evictions" (not causal)
3. ❌ "The effect is zero" (cannot rule out 10-50%)

### Recommended Framing
> "We examine the effect of gambling legalization on eviction rates using state-level panel data with staggered adoption. While we find no evidence of large effects, violations of the parallel trends assumption and limited statistical power (MDE = 83%) prevent definitive causal conclusions. Results are consistent with null effects, small effects below our detection threshold, or effects confounded by differential pre-existing trends."

---

## 💡 Next Steps

### Short-term (This Week)
- [ ] Run HAC standard errors analysis
- [ ] Create cohort-specific event study plots
- [ ] Identify which cohorts violate parallel trends

### Medium-term (For Paper Revision)
- [ ] Implement synthetic control method
- [ ] Try Rambachan & Roth (2023) pre-trend adjustment
- [ ] Add time-varying controls (unemployment, housing costs)

### Long-term (Follow-up Paper)
- [ ] Obtain county-level eviction data
- [ ] Achieve adequate power (1000+ clusters)
- [ ] Investigate heterogeneity (state type, gambling type)
- [ ] Use triple-differences or other robust designs

---

## 🤔 Common Questions

**Q: Why do TWFE and Sun-Abraham disagree?**
A: TWFE has negative weighting bias with staggered adoption. Sun-Abraham properly accounts for treatment timing heterogeneity. Trust Sun-Abraham.

**Q: Can I use the TWFE results?**
A: No, not until you fix the SEs with HAC correction. Even then, Sun-Abraham is preferred for staggered adoption.

**Q: What does "parallel trends violated" mean?**
A: Treated and control states were on different trajectories even before treatment. Can't attribute post-treatment differences to gambling.

**Q: Can I just drop the problematic pre-periods?**
A: No. The violation indicates systematic differences, not just noise. Need a different identification strategy.

**Q: Should I use Sun-Abraham with the large SEs or TWFE?**
A: Use Sun-Abraham *filtered* (SE < 100) for point estimates, but report that parallel trends are violated. Don't make strong causal claims.

**Q: What's the MDE and why does it matter?**
A: Minimum Detectable Effect = 83%. You can only detect huge effects. Anything smaller looks like "zero" in your data even if it exists.

---

**For detailed explanations, see:** [FINAL_RESULTS_SUMMARY.md](FINAL_RESULTS_SUMMARY.md)
