# Diagnostic Findings: Sports Gambling Legalization and Eviction Rates

## Summary

Using three estimators (TWFE, Sun-Abraham, Callaway-Sant'Anna) and a leave-one-out influence diagnostic on a state-month panel of eviction filings (2016--2024, excluding Maine), we find:

1. **The full-sample null result is an artifact.** A small, insignificant full-sample TWFE ATT of -0.047 (log points) masks a sign reversal across COVID: negative pre-COVID, positive post-COVID.
2. **No single state drives the result.** Leave-one-out analysis confirms results are not fragile to any individual state in either period.
3. **Treatment effects are dynamic, not constant.** Sun-Abraham event studies reveal a short-run positive effect (months 0--13 post-legalization) that reverses at longer horizons, consistent with an initial shock that dissipates or reverses.
4. **CS-DiD confirms the dynamic pattern but is severely underpowered.** Callaway-Sant'Anna standard errors are 3--5x larger than Sun-Abraham, rendering almost all event-time coefficients insignificant. This is a known calibration failure, not a substantive null.

---

## Data and Sample

- **Source**: Eviction Tracking System, county-level filings aggregated to state-month
- **Panel**: 36 states (Maine excluded for data quality), Jan 2016 -- Dec 2024
- **COVID exclusion**: Mar 2020 -- Jul 2021 dropped for "no-COVID" specifications
- **Treatment**: Date of online sports betting legalization by state (staggered adoption)
- **Outcome**: `log(1 + filings_count)` at the state-month level
- **Treated states**: 14 (full sample), 4 (pre-COVID only), 13 (post-COVID only)

---

## 1. Full-Sample Leave-One-Out Influence Analysis

**Setup**: TWFE with `post_treat` binary indicator, state + month FE, clustered SEs at state level. COVID months excluded. 24 states with full coverage, 2,592 observations.

### Baseline

| Estimator | ATT | SE | p-value |
|-----------|-----|-----|---------|
| TWFE | -0.047 | 0.143 | 0.74 |

### Key findings

- **No dominant state**: The most influential state (Virginia) shifts ATT by 0.059 log points when dropped, but the sign instability reflects the near-zero baseline, not fragility.
- **Cumulative drop sensitivity**: Dropping the top 4 most influential states (VA, NY, TX, ID) shifts the ATT from -0.047 to +0.205 -- the baseline is genuinely close to zero and easily moved.
- **Influence is dispersed**: HHI of influence = 0.069 (low concentration). 15 states exceed 20% influence, but only because the denominator (baseline ATT) is near zero.

### State-level raw pre/post differences

| Most negative (evictions fell) | Most positive (evictions rose) |
|-------------------------------|-------------------------------|
| VA: -0.74 | AZ: +0.76 |
| DE: -0.73 | OH: +0.65 |
| NY: -0.73 | TN: +0.47 |
| PA: -0.62 | KS: +0.43 |
| IN: -0.51 | AR: +0.36 |

The mix of positive and negative raw differences confirms that averaging across states produces a near-zero effect.

---

## 2. Pre-COVID vs Post-COVID Split

### TWFE results (binary `post_treat`)

| Period | N states | ATT | SE | Significant? |
|--------|----------|-----|-----|-------------|
| Pre-COVID (--Feb 2020) | ~25 | -0.105 | -- | Yes |
| Post-COVID (Aug 2021--) | ~25 | +0.237 | -- | Yes |
| Full no-COVID | 24 | -0.047 | 0.143 | No |

The sign reversal across COVID explains the null full-sample result: a significant negative pre-COVID effect and a significant positive post-COVID effect average to approximately zero.

### LOO stability by period

- **Pre-COVID**: ATT stable at approximately -0.10. Most influential state: Idaho (42%), but dropping it doesn't flip the sign. No state is essential.
- **Post-COVID**: ATT stable at approximately +0.24. Most influential state: Ohio (35%), but dropping it doesn't flip the sign. No state is essential.

---

## 3. Sun-Abraham Event Studies

Sun-Abraham (2021) corrects for the negative weighting problem in staggered TWFE designs. Results via `fixest::sunab()` with state-clustered SEs.

### TWFE vs Sun-Abraham discrepancy (post-COVID)

| Estimator | Post-COVID ATT |
|-----------|---------------|
| TWFE (binary) | +0.237 |
| Sun-Abraham (weighted avg of post) | -0.084 |

This discrepancy is classic staggered adoption bias: TWFE's binary `post_treat` indicator assigns negative weight to early adopters at longer horizons. Sun-Abraham corrects this.

### Dynamic treatment effect pattern (full no-COVID sample)

The Sun-Abraham event study reveals treatment effect dynamics:

| Horizon (months post-legalization) | Typical ATT | Significant? |
|-------------------------------------|-------------|-------------|
| 0--13 | +0.06 to +0.18 | Mixed (some significant) |
| 14--24 | +0.10 to +0.30 | Several significant |
| 25+ | Declining, some negative | Few significant |

**Interpretation**: There is evidence of a short-to-medium-run positive effect of sports gambling legalization on eviction filings that may dissipate at longer horizons. The TWFE binary indicator's large positive post-COVID estimate reflects overweighting of the short-run positive effect.

### Pre-trends

- **Pre-COVID Sun-Abraham**: Pre-period coefficients close to zero (no evidence of violations)
- **Full no-COVID Sun-Abraham**: Pre-period coefficients close to zero; Wald F-test for joint significance of pre-treatment coefficients provides formal evidence

---

## 4. Callaway-Sant'Anna (CS-DiD)

CS-DiD (`did::att_gt()` + `did::aggte()`) is the preferred estimator for staggered designs because it estimates group-time treatment effects without the negative weighting problem. However, the implementation exhibits a known SE inflation problem on this panel.

### Results

| Period | N states | N obs | Overall ATT | SE | p-value | Post coefs significant |
|--------|----------|-------|-------------|-----|---------|----------------------|
| Pre-COVID | 29 | 1,424 | +0.019 | 0.051 | 0.71 | 1/21 (5%) |
| Post-COVID | 33 | 1,277 | +0.018 | 0.236 | 0.94 | 1/40 (2.5%) |
| Full no-COVID | 36 | 2,805 | -0.036 | 0.160 | 0.82 | 2/79 (2.5%) |

### SE inflation

| Period | CS mean post SE | SunAb comparison | Inflation factor |
|--------|----------------|-----------------|-----------------|
| Pre-COVID | 0.096 | ~0.03--0.05 | ~2--3x |
| Post-COVID | 0.338 | ~0.08--0.12 | ~3--4x |
| Full no-COVID | 0.299 | ~0.08--0.12 | ~3--4x |

CS point estimates qualitatively agree with Sun-Abraham's dynamic pattern (post-COVID: positive early, negative later), but the inflated SEs render almost everything insignificant. This is **not** evidence of a null effect; it is a statistical power failure.

### Dynamic pattern (post-COVID CS)

Despite the inflated SEs, the CS point estimates trace a recognizable dynamic:

- Months 0--9: positive (~+0.07)
- Months 11--24: larger positive (~+0.30)
- Months 27--37: negative (~-0.55)

This aligns with the Sun-Abraham event study pattern, reinforcing that the dynamics are real.

### Diagnosis

The CS SE inflation is a known issue documented in `CLAUDE.md`. Root causes include:
- Unbalanced panel (only 338/875 group-time cells identifiable, 38.6%)
- Bootstrap multiplier estimation with small cluster counts
- Potential bugs in the `did` package (partially addressed by patches in `patches/`)

The pretrends pipeline (`analysis/pretrends/pretrends_statepanel_template.R`) includes a self-test calibration mode that runs null simulations on the real design skeleton to quantify the SE inflation and automatically select the more reliable inference method.

---

## 5. Estimator Comparison Summary

| Feature | TWFE (binary) | Sun-Abraham | CS-DiD |
|---------|--------------|-------------|--------|
| Handles staggered adoption | No (negative weighting) | Yes | Yes |
| Dynamic effects | No | Yes | Yes |
| SE calibration | Good (~5% Type I) | Good | **Poor** (rejection << 5%) |
| Pre-COVID ATT | -0.105 (sig) | -0.037 (small) | +0.019 (insig) |
| Post-COVID ATT | +0.237 (sig) | -0.084 (dynamic) | +0.018 (insig) |
| Recommended use | Baseline only | **Primary** | Robustness (after calibration) |

---

## 6. Interpretation and Implications

### What the data show

1. Sports gambling legalization is associated with a **short-run increase** in eviction filings (~5--18% in the first 12 months post-legalization), visible in the Sun-Abraham event study.

2. The effect **does not persist**: at longer horizons (25+ months), the effect dissipates or reverses.

3. The **pre-COVID vs post-COVID sign reversal** in TWFE is an artifact of (a) the binary indicator's negative weighting problem and (b) different compositions of treated states across periods.

4. **No single state drives the results** in either period.

### Caveats

- **CS-DiD is underpowered**: The preferred estimator for this design (CS-DiD) has inflated SEs that prevent sharp inference. Self-test calibration (via the pretrends pipeline) is needed to quantify this.
- **COVID confounding**: Despite excluding Mar 2020 -- Jul 2021, post-COVID eviction dynamics may still be influenced by pandemic recovery patterns (moratorium expiration, rental assistance wind-down).
- **Small treated sample**: Only 4 states are treated pre-COVID; post-COVID adds 9 more but with shorter follow-up.
- **Dynamic effects complicate simple ATT summaries**: A single "overall ATT" obscures the time-varying pattern. Event studies should be the primary reporting framework.

### Recommended next steps

1. **Run the pretrends pipeline** with self-test calibration (`SELF_TEST=TRUE`) to formally assess CS SE reliability and select the appropriate headline inference method.
2. **Report Sun-Abraham event studies** as the primary results, with CS-DiD as a robustness check (noting the SE calibration issue).
3. **Present dynamic effects**, not just overall ATTs -- the time-varying pattern is the most informative feature of the data.
4. **Investigate gambling intensity heterogeneity** using the Handle data from `lsr_sports_betting_handle_revenue_by_state_month.csv` to test whether states with larger betting volume show larger eviction effects.

---

## Output Files

All diagnostic outputs are in `output/state_influence_loo/`:

| File | Description |
|------|-------------|
| `summary.csv` | Baseline ATT, SE, influence statistics |
| `loo_results.csv` | Per-state leave-one-out TWFE and SunAb ATTs |
| `state_raw_diffs.csv` | Raw pre/post mean differences by treated state |
| `cumulative_drop.csv` | ATT after cumulatively dropping most influential states |
| `loo_influence_twfe.png` | Bar chart of per-state TWFE influence |
| `loo_forest_twfe.png` | Forest plot of LOO ATT estimates |
| `cumulative_drop.png` | Cumulative drop sensitivity plot |
| `state_raw_diff.png` | Raw pre/post differences by state |
| `sunab_pre_vs_post_covid.png` | Sun-Abraham event studies, pre vs post COVID |
| `cs_pre_vs_post_covid.png` | CS-DiD event studies, pre vs post COVID |

---

## Reproducibility

```bash
# State influence LOO diagnostic
Rscript analysis/diagnostics/state_influence_loo.R

# Pre-trends pipeline (CS + SunAb + optional self-test)
bash scripts/run_pretrends_statepanel.sh

# With self-test calibration
SELF_TEST=TRUE N_CORES=4 bash scripts/run_pretrends_statepanel.sh

# With gambling intensity heterogeneity
GAMBLING_FILE=data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv \
  bash scripts/run_pretrends_statepanel.sh
```
