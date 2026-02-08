# CS-DiD Package Fixes

## Overview

During power analysis development, we discovered critical issues in the `did` package's Callaway-Sant'Anna (CS-DiD) implementation that affected statistical inference and estimation reliability.

## Issues Discovered

1. **P-value computation bug** - Incorrect test statistic used, causing 0% rejection rate under the null hypothesis
2. **Unbalanced panel handling** - IPW estimator failed with unbalanced panels (missing observations)
3. **Estimation method selection** - Bootstrap and regression estimator incompatibility causing errors
4. **Allow unbalanced option** - Package didn't properly handle the allow_unbalanced_panel parameter

## Patches

### FIX_cs_pvalue_computation.patch
Corrects the p-value calculation to use proper two-sided t-test. The original implementation used `pnorm()` for one-sided test when it should use two-sided testing.

### FIX_cs_simulation_est_method.patch
Fixes estimation method selection logic to prevent incompatible combinations of bootstrap and regression estimators.

### FIX_unbalanced_panel.patch
Adds proper handling for unbalanced panels in the IPW estimator, preventing crashes when observations are missing.

### FIX_allow_unbalanced.patch
Alternative solution for unbalanced panel handling through the allow_unbalanced_panel parameter.

## Usage

**Note:** These patches are **for reference and reproducibility purposes only**.

Our main analysis uses TWFE (Two-Way Fixed Effects) methods rather than CS-DiD due to these discovered issues. The TWFE implementation in the `fixest` package is robust and well-tested.

If you need to apply a patch for research purposes:

```bash
# From repository root
cd /path/to/did/package/source
git apply /path/to/Gambling-and-Eviction/patches/FIX_cs_pvalue_computation.patch
```

## Full Documentation

For complete details including:
- Problem diagnosis and root cause analysis
- Testing methodology and verification
- Why TWFE is preferred for this analysis
- Performance comparisons

See: [docs/methodology/CS_DID_PVALUE_FIX.md](../docs/methodology/CS_DID_PVALUE_FIX.md)

## Research Process

The diagnostic files showing how these issues were discovered and resolved are preserved in:
- `archive/diagnostics/cs_did/` - Debugging process documentation
- `archive/diagnostics/se_spike/` - Standard error spike investigation
- `archive/diagnostics/implementation_notes/` - Implementation insights

This documentation demonstrates the rigorous methodological investigation conducted during the research.
