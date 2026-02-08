# Pre-Trends Evaluation: Modern Methods

**Generated**: 2026-01-18 00:24:12.830814
**Outcome**: log1p_filings_count
**Treatment**: Online gambling legalization

## Summary of Specifications

### Baseline [CAUTION]

- **TWFE F-test p-value**: 1e-04
- **Max pre-trend coefficient**: 0.1946
- **MDE (80% power)**: 0.0303
- **δ* (equivalence)**: NA

### No COVID [CAUTION]

- **TWFE F-test p-value**: 0
- **Max pre-trend coefficient**: 0.1155
- **MDE (80% power)**: 0.0151
- **δ* (equivalence)**: NA

### Pre-2020 Only [CAUTION]

- **TWFE F-test p-value**: 0
- **Max pre-trend coefficient**: 0.2035
- **MDE (80% power)**: 0.0072
- **δ* (equivalence)**: NA

### Narrow Window (±6 months) [CAUTION]

- **TWFE F-test p-value**: 0.0134
- **Max pre-trend coefficient**: 0.2011
- **MDE (80% power)**: 0.0596
- **δ* (equivalence)**: NA


## Interpretation Guide

Following Roth (2022), we do NOT condition on pre-trends tests. Instead:

1. **F-test**: Traditional joint test of pre-treatment coefficients = 0
   - Failing to reject does NOT prove parallel trends holds
   - Must assess power of the test

2. **MDE (Minimal Detectable Effect)**: Slope of linear violation detectable with 80% power
   - Small MDE (< 0.10): Test has good power
   - Large MDE (> 0.15): Test is underpowered, passing test is uninformative

3. **δ* (Equivalence Test)**: Smallest violation we can rule out
   - Small δ* (< 0.10): Strong evidence FOR parallel trends
   - Large δ* or NA: Weak evidence, cannot rule out violations

4. **HonestDiD**: Sensitivity analysis showing how results change with bounded violations
   - M=1: Post violations ≤ max pre violation
   - Robust conclusions should hold for M ≥ 1

## Assessment Criteria

- **STRONG**: F-test p > 0.10, MDE < 0.10, good power and equivalence evidence
- **MODERATE**: F-test p > 0.05, MDE < 0.15, some evidence for parallel trends
- **CAUTION**: High MDE or cannot rule out violations, pre-trends test uninformative

---

Full results saved to: output/pretrends_evaluation/
