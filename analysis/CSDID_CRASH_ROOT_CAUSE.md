# Callaway-Sant'Anna DiD Crash: Root Cause Analysis

## Executive Summary

**Problem:** The `did` package crashes with a segfault when attempting to estimate Callaway-Sant'Anna (2021) difference-in-differences on the gambling-eviction panel data.

**Root Cause:** The `did` package internally uses `fastglm` for propensity score estimation, which calls a C++ function `colMax_dense()` that has memory access bugs when handling unbalanced panels with sparse group-time cells.

**Status:** CS-DiD is **DISABLED** in the analysis pipeline. Alternative estimators (TWFE, Sun-Abraham, didimputation) are used instead.

---

## Technical Details

### 1. The Crash Chain

```
did::att_gt()
  ↓
[propensity score estimation]
  ↓
fastglm::fastglm() (for logistic regression)
  ↓
colMax_dense() (C++ function)
  ↓
SEGFAULT (memory access violation)
```

### 2. Why All `est_method` Options Fail

All three estimation methods in `did::att_gt()` compute propensity scores using `fastglm`:

| `est_method` | Description | Uses `fastglm`? |
|--------------|-------------|-----------------|
| `"reg"` | Outcome regression | ✅ Yes (for PS) |
| `"ipw"` | Inverse probability weighting | ✅ Yes (primary) |
| `"dr"` | Doubly robust | ✅ Yes (for PS) |

**Key insight:** Even `est_method="reg"` (outcome regression) crashes because it still estimates propensity scores internally.

### 3. Why This Data Triggers the Bug

**Panel Structure:**
- **37 event times** (e = -12 to +24 months relative to treatment)
- **~31 states** (excluding Maine)
- **Staggered adoption:** 7 treatment cohorts between 2018-2023
- **Unbalanced panel:** Not all states observed in all periods due to:
  - COVID exclusions (2020-03 to 2021-05)
  - States entering/exiting the sample
  - Data availability gaps

**The Problem:**
```
Expected observations (balanced): 37 × 31 = 1,147
Actual observations (unbalanced): < 1,147
```

With staggered adoption + unbalanced panel:
- Some **group × time cells have very few observations** (< 5)
- Some cells may have **zero observations**
- `colMax_dense()` tries to compute column maxima on empty/sparse matrices
- Memory access violation → **SEGFAULT**

### 4. Evidence from Debug Scripts

**Location:** `debug_csdid.R:166-170`
```r
expected_obs <- length(all_states) * length(all_times)
actual_obs <- nrow(panel)

if (actual_obs < expected_obs) {
  cat("PANEL IS UNBALANCED - this may cause issues with did package\n\n")
}
```

**Location:** `evaluate_pretrends_modern_methods.R:673-679`
```r
log_msg("  DISABLED: CS-DiD causing segfault even with est_method='reg'")
log_msg("  Issue: All est_methods (reg/ipw/dr) use fastglm for propensity scores")
log_msg("  Root cause: fastglm's colMax_dense() crashes on this data structure")
log_msg("  Attempted fix: est_method='reg' still calls fastglm internally")
log_msg("  Solution: Either fix data structure or use balanced panel")
```

---

## Attempted Fixes (All Failed)

### ❌ Fix 1: Use `est_method="reg"`
**Reasoning:** Avoid IPW, use outcome regression only
**Result:** Still crashes (PS estimation happens internally)

### ❌ Fix 2: Use `panel=FALSE` (repeated cross-sections)
**Reasoning:** Treat as repeated cross-sections, not panel
**Result:** Still crashes (same PS estimation issue)

### ❌ Fix 3: Balance the panel with NA filling
**Reasoning:** Create complete state × time grid
**Result:** Different errors (NA handling issues in `did` package)

### ❌ Fix 4: Reduce to minimal cohorts
**Reasoning:** Use only 2 treatment cohorts + never-treated
**Result:** Still crashes (even minimal samples hit the bug)

---

## Why This Is Hard to Fix

1. **Can't avoid `fastglm`:** It's hardcoded in the `did` package internals
2. **Can't use `panel=TRUE`:** Requires perfectly balanced panel (every unit in every period)
3. **Can't easily fix `fastglm`:** The bug is in compiled C++ code (`colMax_dense()`)
4. **Balancing panel introduces bias:** Imputing missing outcomes changes estimates
5. **Restricting sample changes research question:** Loses staggered adoption variation

---

## Solutions (In Priority Order)

### ✅ Solution 1: Use Alternative Estimators (CURRENT APPROACH)

**Implemented:**
- **TWFE (baseline):** Works, but biased with heterogeneous treatment effects
- **HonestDiD (Rambachan & Roth 2023):** Sensitivity analysis on TWFE
- **Sun-Abraham (2021):** Interaction-weighted estimator via `fixest::sunab()`
- **didimputation (Borusyak et al. 2024):** Imputation estimator

**Advantages:**
- ✅ All methods handle unbalanced panels
- ✅ No segfault issues
- ✅ Robust inference available
- ✅ Well-documented and maintained

**Code Location:** `evaluate_pretrends_modern_methods.R:442-616`

### 🔄 Solution 2: Create Perfectly Balanced Panel

**Approach:**
```r
# Fill all state × time combinations
panel_balanced <- expand.grid(
  state_abb = all_states,
  year = all_times
) %>%
  left_join(panel_raw, by = c("state_abb", "year")) %>%
  # Handle missing outcomes somehow
  mutate(y = coalesce(y, ???))
```

**Challenges:**
- ❌ How to handle missing outcomes? (imputation biases estimates)
- ❌ Loses information (forces balanced structure)
- ❌ May still fail if some cells have all NA

### ⏳ Solution 3: Wait for Bug Fix

**Status:** Open issue (not tracked yet)

**Options:**
- Wait for `fastglm` maintainers to fix `colMax_dense()`
- Wait for `did` package to switch to different backend (e.g., `glm2`, `speedglm`)
- Switch to `didimputation` or `did2s` packages (don't use `fastglm`)

### 🔬 Solution 4: Manual CS-DiD Implementation

**Approach:** Implement CS-DiD estimator manually without `fastglm` dependency

**Challenges:**
- ⚠️ Time-intensive
- ⚠️ Hard to get standard errors right
- ⚠️ Reinventing the wheel

---

## Current Workaround (TWFE + Alternatives)

### Primary Analysis
**Method:** Two-way fixed effects (TWFE)
**File:** `evaluate_pretrends_modern_methods.R:226-402`
**Limitations:** Biased with heterogeneous treatment effects

### Robustness Checks
1. **HonestDiD:** Sensitivity analysis assuming bounded parallel trends violations
2. **Sun-Abraham:** Interaction-weighted estimator (unbiased under het. effects)
3. **didimputation:** Imputation-based estimator (handles staggered adoption)

### What's Missing
- ❌ CS-DiD group-time average treatment effects
- ❌ CS-DiD event study plots
- ❌ CS-DiD aggregation methods (simple, dynamic, group, calendar)

---

## Related Files

### Main Analysis Scripts
- `evaluate_pretrends_modern_methods.R:664-729` — CS-DiD implementation (DISABLED)
- `evaluate_pretrends_modern_methods.R:442-616` — Alternative estimators (ACTIVE)

### Debug Scripts
- `debug_csdid.R` — Tests CS-DiD with various configurations
- `debug_fastglm.R` — Tests `fastglm` edge cases directly
- `debug_cs_null_size.R` — Tests CS-DiD null rejection rates
- `debug_cs_size_audit.R` — Audits CS-DiD statistical properties

### Documentation
- `README_MORTGAGE_PRETRENDS.md` — Pre-trends diagnostics results
- `CSDID_CRASH_ROOT_CAUSE.md` — This file

---

## References

### Papers
- Callaway, B., & Sant'Anna, P. H. (2021). Difference-in-differences with multiple time periods. *Journal of Econometrics*, 225(2), 200-230.
- Sun, L., & Abraham, S. (2021). Estimating dynamic treatment effects in event studies with heterogeneous treatment effects. *Journal of Econometrics*, 225(2), 175-199.
- Borusyak, K., Jaravel, X., & Spiess, J. (2024). Revisiting event study designs: Robust and efficient estimation. *Review of Economic Studies* (forthcoming).

### Software
- R package `did`: https://github.com/bcallaway11/did
- R package `fastglm`: https://github.com/jaredhuling/fastglm
- R package `fixest`: https://github.com/lrberge/fixest
- R package `didimputation`: https://github.com/kylebutts/didimputation

---

## Debugging Timeline

1. **Initial crash:** CS-DiD segfault with default settings
2. **Attempt 1:** Switch to `est_method="reg"` → Still crashes
3. **Attempt 2:** Switch to `panel=FALSE` → Still crashes
4. **Investigation:** Discovered all methods use `fastglm` internally
5. **Root cause:** `colMax_dense()` bug in `fastglm` C++ code
6. **Workaround:** Disable CS-DiD, use alternative estimators
7. **Current status:** TWFE + HonestDiD + Sun-Abraham working correctly

---

## Lessons Learned

1. **Unbalanced panels are common in real-world data** (COVID, data gaps, staggered entry)
2. **Some DiD packages assume balanced panels** (even when docs say otherwise)
3. **C++ dependencies can introduce hard-to-debug crashes** (segfaults, not R errors)
4. **Multiple DiD estimators are needed** (no single "best" method)
5. **Robustness checks are essential** (cross-validate with multiple packages)

---

## Recommendations

### For This Project
✅ **Continue with current approach:** TWFE + HonestDiD + Sun-Abraham
✅ **Report all three methods:** Shows robustness
✅ **Acknowledge CS-DiD limitation in paper:** Transparency about methods

### For Future Projects
- ⚠️ Test CS-DiD early with real data structure (not just toy examples)
- ⚠️ Have backup estimators ready (Sun-Abraham, didimputation)
- ⚠️ Document panel balance issues upfront
- ⚠️ Consider `fixest::sunab()` as first choice (handles everything)

---

**Last Updated:** 2026-01-19
**Status:** CS-DiD remains disabled; alternative estimators functioning correctly
