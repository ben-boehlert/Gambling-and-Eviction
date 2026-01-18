# Pre-Trends Analysis: Pre-COVID vs Post-COVID

Generated: 2026-01-17 14:04:34.260182

## Motivation

COVID-19 fundamentally changed eviction patterns. To assess whether parallel trends
violations are driven by the pandemic or by structural differences, we analyze
pre-trends separately for:

1. **Pre-COVID period (2012-2019)**: Clean period before pandemic
2. **Post-COVID period (2021-2024)**: After moratoria ended

## Results Summary

### Pre-COVID Analysis (2012-2019) [CAUTION]

- **F-test p-value**: 0
- **Max pre-trend**: 0.3053
- **RMS pre-trends**: 0.0859
- **MDE (80%)**: 0.0033

### Post-COVID Analysis (2021-2024) [CAUTION]

- **F-test p-value**: 0
- **Max pre-trend**: 0.3117
- **RMS pre-trends**: 0.1135
- **MDE (80%)**: 0.0159

### Pre-COVID Full Sample (2012-2019) [CAUTION]

- **F-test p-value**: 0
- **Max pre-trend**: 0.196
- **RMS pre-trends**: 0.0754
- **MDE (80%)**: 0.0048

### Post-COVID Full Sample (2021-2024) [CAUTION]

- **F-test p-value**: 0
- **Max pre-trend**: 0.2709
- **RMS pre-trends**: 0.1116
- **MDE (80%)**: 0.0134


## Interpretation

Compare Pre-COVID vs Post-COVID results:

- If pre-trends violations are similar in both periods → Structural issue
- If violations only in one period → Period-specific issue
- If Pre-COVID has good parallel trends → Focus on pre-2020 sample

## Next Steps

Based on results:
1. If Pre-COVID passes → Use 2012-2019 sample for identification
2. If both fail → Consider matching, synthetic control, or bounds
3. If Post-COVID passes → Focus on recent adoptions

---
Full results: output/pretrends_pre_post_covid/
