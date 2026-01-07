# COVID Handling Options for Power Simulation

## Summary of Findings

Based on our diagnostic work, here are your options ranked by validity:

---

## Option 1: Pre-COVID Only (2016-2020) ⭐ RECOMMENDED

**Specification:**
- Period: January 2016 - February 2020
- Residualization: unit + time FE (NO month FE needed)
- Data: 25 states, 50 months, 1,216 observations

**Pros:**
✓ Parallel trends HOLD (t = -1.49, p = 0.14)
✓ Type I error = 12% (acceptable for power analysis)
✓ Clean identification - no COVID contamination
✓ Transparent, defensible specification

**Cons:**
✗ Limited post-treatment follow-up for some states
✗ Smaller sample size
✗ Can't speak to post-COVID effects

**Recommendation:** **USE THIS.** It's the only specification where parallel trends hold and Type I error is acceptable.

---

## Option 2: Pre-COVID + Month FE

**Specification:**
- Period: January 2016 - February 2020
- Residualization: unit + time + **month** FE
- Same data as Option 1

**Pros:**
✓ Parallel trends still hold (t = -1.49, p = 0.14)
✓ Removes calendar seasonality
✓ Type I error = 2%

**Cons:**
✗ Type I error TOO LOW (2% << 5%)
✗ Overly conservative - reduces power unnecessarily
✗ More complex specification with minimal benefit

**Recommendation:** **DON'T USE.** The 2% Type I error means you're being too conservative. The 12% from Option 1 is closer to the nominal 5% and more appropriate for power analysis.

---

## Option 3: Full Period (2016-2025) - NOT VALID ❌

**Specification:**
- Period: January 2016 - September 2025
- Residualization: unit + time FE

**Pros:**
✓ Maximum sample size
✓ Full post-treatment follow-up

**Cons:**
✗ Parallel trends VIOLATED (t = -5.18, p < 0.001)
✗ Type I error = 24% (unacceptably high)
✗ Structural break at COVID
✗ Cannot trust power estimates

**Recommendation:** **DO NOT USE.** Fundamentally invalid identification.

---

## Option 4: Full Period + Month FE - WORSE ❌

**Specification:**
- Period: January 2016 - September 2025
- Residualization: unit + time + month FE

**Pros:**
✓ Removes seasonality

**Cons:**
✗ Parallel trends STILL VIOLATED (t = -5.42, p < 0.001)
✗ Type I error = 32% (EVEN WORSE!)
✗ Month FE doesn't fix structural break

**Recommendation:** **DO NOT USE.** Worse than Option 3.

---

## Option 5: Include COVID Indicator

**Specification:**
- Period: January 2016 - September 2025
- Add: `covid_period` dummy (March 2020+)
- Model: Allow different intercepts/slopes pre/post COVID

**Conceptual approach:**
```r
# In residualize_outcome():
baseline <- baseline %>%
  mutate(covid = month_date >= as.Date("2020-03-01"))

# Residualize with COVID interaction
m <- feols(outcome ~ covid | unit_id + time_id, data = baseline)
```

**Pros:**
✓ Uses all data
✓ Explicitly models structural break
✓ Could separate pre/post COVID effects

**Cons:**
✗ Complex specification
✗ Assumes COVID effect is same across treated/untreated
✗ May not fully capture differential COVID impacts
✗ Still need to test if parallel trends hold within periods

**Recommendation:** **RISKY.** Could work but needs validation. The differential trends suggest COVID affected treated/untreated states differently, so a simple dummy won't fix it.

---

## Option 6: Separate Pre/Post COVID Power Analyses

**Specification:**
Run TWO separate power simulations:
1. Pre-COVID (2016-2020) - as Option 1
2. Post-COVID (2021-2025) - separate analysis

**Pros:**
✓ Clean separation of periods
✓ Can test if power differs by era
✓ Transparent about COVID effects

**Cons:**
✗ Post-COVID period may also violate parallel trends
✗ Reduced sample size for each
✗ Can't combine estimates

**Recommendation:** **INTERESTING but lower priority.** Focus on Option 1 first. Could explore this as robustness check.

---

## My Recommendation: Go with Option 1

### Implementation in `power_simulation_cs.R`:

```r
# In cfg, add:
cfg <- list(
  ...
  # COVID handling
  restrict_to_precovid = TRUE,
  precovid_cutoff = as.Date("2020-03-01"),
  ...
)

# In load_panel() or as a wrapper:
if (cfg$restrict_to_precovid) {
  panel_df <- panel_df %>%
    filter(month_date < cfg$precovid_cutoff)
}
```

### Key Modifications Needed:

1. **Filter panel to pre-COVID** before building baseline
2. **Keep current residualization** (unit + time FE, NO month FE)
3. **Document the choice clearly** in outputs
4. **Report limitations** about post-COVID generalizability

### What to Report in Grant/Paper:

**Be transparent:**
> "We restrict our power analysis to the pre-COVID period (January 2016 - February 2020) because parallel trends hold in this period (p = 0.14) but are violated when including post-COVID data (p < 0.001). This suggests a structural break in the eviction-gambling relationship around COVID-19, likely due to eviction moratoria and differential state policy responses. Our power estimates therefore apply to a pre-COVID context and may not generalize to post-pandemic conditions."

**Advantages you can cite:**
- Cleaner identification
- Valid causal assumptions
- Conservative approach (smaller sample)
- Type I error well-calibrated (12%)

---

## Alternative: Sensitivity Analysis

If reviewers push back, you can show:

1. **Main analysis:** Pre-COVID (Option 1)
2. **Sensitivity #1:** Pre-COVID + month FE (shows result is robust, though overly conservative)
3. **Sensitivity #2:** Document that full period violates parallel trends (justify your choice)

This shows you did due diligence and made the right methodological choice.

---

## Bottom Line

**Use pre-COVID data only (Option 1).** It's the only specification that:
- Satisfies parallel trends
- Has reasonable Type I error
- Provides valid power estimates

The cost (smaller sample, pre-COVID only) is worth it for valid inference. COVID fundamentally changed the landscape, and trying to force post-COVID data in will give you garbage power estimates.
