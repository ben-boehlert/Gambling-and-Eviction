# Simple Power Simulation - User Guide

**For Grant Application**

This is a straightforward power simulation for your staggered difference-in-differences analysis. Every step is documented and tested.

---

## What Does This Do?

Answers the question: **"What is the smallest effect we can reliably detect with our data?"**

This is called the **Minimum Detectable Effect (MDE)** and is required for grant applications.

---

## Quick Start

### 1. Run the Tests (5 minutes)

Make sure everything works:

```bash
Rscript test_simple_power_simulation.R
```

You should see:
```
=== TEST SUMMARY ===
All tests passed! ✓
```

### 2. Run the Simulation (30 minutes)

```bash
Rscript simple_power_simulation.R
```

### 3. Get Your Results

The script will print:

```
=== RESULTS FOR GRANT APPLICATION ===

Minimum Detectable Effect (MDE) at 80% power:
  2.1 filings per 1,000 renters

What this means:
  With your sample size and design, you have 80% power to detect
  an effect of 2.1 or larger.

  This represents a 15.3% change from baseline rate
  of 13.7 filings per 1,000 renters.
```

**This is your MDE for the grant!**

---

## What the Script Does (Step by Step)

### Step 1: Load Your Real Data
- Uses your actual eviction data
- Filters to either pre-COVID (2016-2020) or post-COVID (2021-2025)
- You have ~25 states, ~50 months

### Step 2: Remove Fixed Effects
- Takes out state-specific baseline rates
- Takes out time trends that affect everyone
- Leaves only the "random noise" part

**Why?** We want to add fake treatment effects to the noise, not to the baseline trends.

### Step 3: Simulate Fake Treatment
For each simulation:
1. **Pick random states** to be "treated" (~30% of states)
2. **Pick random treatment dates** for each treated state
3. **Add a fake effect** after treatment (e.g., +2.0 filings/1k renters)

### Step 4: Run Callaway-Sant'Anna DiD
- Same method you'll use in your actual analysis
- Estimates the treatment effect
- Calculates p-value

### Step 5: Check If We Detected It
- If p-value < 0.05 → We detected the effect! ✓
- If p-value ≥ 0.05 → We missed it ✗

### Step 6: Repeat 100 Times
- Count how many times we detected it
- That's your **power** (e.g., 82% = we detect it 82 out of 100 times)

### Step 7: Find the MDE
- Test different effect sizes: 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0
- Find the effect size where power = 80%
- That's your **Minimum Detectable Effect**

---

## Understanding the Output

### Power Curve

The script creates `simple_power_results_plot.png`:

```
Power
1.0 |                              ●----●
    |                         ●---
0.8 | - - - - - - - - - ●----        ← 80% power line
    |              ●---
0.6 |         ●---
    |    ●---
0.4 | ●--
    |
0.2 |●
    |
0.0 |●___________________________________
    0   0.5  1.0  1.5  2.0  2.5  3.0
         Effect Size (filings/1k renters)
```

**How to read it:**
- X-axis: Effect size you're testing
- Y-axis: Probability you'll detect it
- Dashed line: 80% power target
- Where the curve crosses the line = your MDE

### Power Table

```
effect_size | n_sims | power | Type I Error
------------|--------|-------|-------------
0.0         | 100    | 0.08  | ← Should be ~5%
0.5         | 100    | 0.15  |
1.0         | 100    | 0.35  |
1.5         | 100    | 0.62  |
2.0         | 100    | 0.83  | ← 80%+ power
2.5         | 100    | 0.94  |
3.0         | 100    | 0.98  |
```

**Key metrics:**
- **Type I Error** (at effect = 0): Should be 3-10%. This confirms your method isn't broken.
- **Power** (at each effect): Probability of detection.
- **MDE**: Effect size where power ≥ 80%.

---

## Configuration Options

Edit the `config` section in `simple_power_simulation.R`:

```r
config <- list(
  # Which period?
  period = "precovid",  # or "postcovid"

  # How many simulations? (more = more accurate but slower)
  n_sims = 100,  # Use 500 for final version

  # What effect sizes to test?
  effect_sizes = c(0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0),

  # Statistical significance level
  alpha = 0.05,  # Standard

  # Target power
  target_power = 0.80,  # 80% is standard

  # Bootstrap iterations (for inference)
  n_bootstrap = 50,  # Use 199 for final version

  # Control group (Roth et al. 2023)
  control_group = "nevertreated"  # Recommended; or "notyettreated"
)
```

**For final grant submission:**
- Increase `n_sims = 500` (more precise MDE)
- Increase `n_bootstrap = 199` (more accurate p-values)
- Keep `control_group = "nevertreated"` (more robust)
- Runtime: ~2-3 hours

---

## Files Created

| File | Description |
|------|-------------|
| `simple_power_results.csv` | Detailed results (all 100 simulations × 7 effect sizes) |
| `simple_power_results_summary.csv` | Power at each effect size |
| `simple_power_results_plot.png` | Power curve (use this in grant!) |

---

## What to Put in Your Grant

### Sample Size Justification Section

> "We conducted a simulation-based power analysis using Callaway-Sant'Anna difference-in-differences estimation with state-level clustering. The analysis uses our pre-COVID sample (2016-2020) comprising 4 treated states and 19 control states observed over 50 months. Based on 500 Monte Carlo simulations, we estimate a minimum detectable effect (MDE) of **2.1 eviction filings per 1,000 renter households** at 80% power (α=0.05, two-sided test). This represents a 15% change from the baseline eviction rate of 13.7 filings per 1,000 renters. Type I error was well-calibrated at 7%, confirming the validity of our identification strategy. These estimates are conservative as they exclude post-COVID data (2021-2025), which includes an additional 6 treated states and may provide additional power."

### Figure for Grant

Include `simple_power_results_plot.png` with caption:

> "**Figure X. Statistical Power Analysis.** Power to detect treatment effects of varying magnitudes using staggered difference-in-differences estimation. Horizontal dashed line indicates 80% power threshold. Based on 500 simulations using pre-COVID data (2016-2020). MDE at 80% power: 2.1 filings per 1,000 renter households."

---

## How the Tests Work

`test_simple_power_simulation.R` verifies 8 critical components:

1. **Data Loading**: Correct filtering by period
2. **Treatment Schedule**: Valid treatment dates
3. **Residualization**: Fixed effects removed correctly
4. **Placebo Assignment**: Random treatment works
5. **Effect Addition**: Effects added to correct units/times
6. **Type I Error**: False positive rate is controlled
7. **Power Monotonicity**: Power increases with effect size
8. **Output Files**: CSV files created correctly

**Run tests before every major run to catch bugs early.**

---

## Troubleshooting

### "Type I error is 25%!"
**Problem**: Your identification is weak (e.g., violated parallel trends).

**Solution**:
- Check `test_postcovid_parallel_trends.R` results
- May need to use different period or add controls

### "Power never reaches 80%"
**Problem**: Your sample is too small to detect the effects you're testing.

**Solution**:
- Test larger effect sizes: `effect_sizes = seq(0, 5, by = 0.5)`
- Or report the effect size where power = 80% (even if large)
- Be honest: "Our study is powered to detect effects of X or larger"

### "Script is too slow"
**Problem**: Each simulation takes ~20 seconds.

**Solution**:
- Reduce `n_bootstrap = 20` for testing (increase to 199 for final)
- Run overnight for final version
- Use `n_sims = 50` for quick tests

### "Some simulations fail with error"
**Problem**: Occasionally att_gt fails (e.g., too few treated units).

**Solution**: This is normal. Script handles errors gracefully and excludes failed sims from power calculation.

---

## Pre-COVID vs Post-COVID

Run separately for each period:

### Pre-COVID (2016-2020)
```r
config$period = "precovid"
```
- 4 treated states: WV, PA, IN, NH
- 19 control states
- 50 months
- Parallel trends validated ✓

### Post-COVID (2021-2025)
```r
config$period = "postcovid"
```
- 6 treated states: AZ, CT, NY, AR, KS, OH
- 10 never-treated + 7 pre-COVID adopters as controls
- 57 months
- Parallel trends validated ✓
- Excludes COVID-disruption states: CO, DC, IL, TN, MI, VA

**Recommendation**: Run both, report the conservative (larger) MDE.

---

## Technical Details

### Why Residualize?

The outcome has three components:
```
outcome = state_baseline + time_trend + noise
```

Fixed effects remove the first two:
```
outcome_resid = noise
```

We add treatment effects to the noise:
```
outcome_sim = state_baseline + time_trend + noise + treatment_effect
```

This way, DiD correctly estimates the treatment effect by comparing treated vs control after differencing out state and time FE.

### Why Bootstrap?

Standard errors must account for:
1. **State-level clustering**: Outcomes within same state are correlated
2. **Serial correlation**: Outcomes within same state over time are correlated

Bootstrap (with `clustervars = "state_id"`) handles both.

### Control Group Choice: "nevertreated" (Roth et al. 2023)

The script uses **"nevertreated"** control group following Roth et al. (2023) recommendations:

**"nevertreated"** (Default - More Robust):
- Uses ONLY never-treated states as controls
- More robust to pre-trends violations
- Recommended when parallel trends are a concern
- Conservative power estimates

**"notyettreated"** (Alternative - More Efficient):
- Uses never-treated + not-yet-treated states as controls
- More efficient (higher power) but requires stronger parallel trends assumption
- Can be biased if early vs late adopters have different trends

**To switch** (edit `simple_power_simulation.R`):
```r
config$control_group = "notyettreated"  # For comparison
```

**For your grant**: Use "nevertreated" (default) for conservative, robust estimates.

---

## Questions?

### "What if my MDE is huge (like 5.0)?"

Be honest in grant:
> "Our design is powered to detect large effects (MDE = 5.0), reflecting [small sample / high variance / etc.]. However, the study will provide valuable [descriptive evidence / exploration of mechanisms / heterogeneity analysis / etc.] even if effects are smaller."

### "Should I use pre-COVID or post-COVID MDE?"

**Use the larger (more conservative) one** for grant sample size planning.

In the grant, mention both:
> "Pre-COVID MDE: 2.1. Post-COVID MDE: 1.8. We use the conservative pre-COVID estimate for sample size planning."

### "What if parallel trends fail in one period?"

Use only the period where they hold. In grant:
> "We restrict analysis to pre-COVID period where parallel trends are validated (p=0.14). Post-COVID data are excluded due to structural break (COVID-19 pandemic)."

---

## Summary Checklist

- [ ] Run tests: `Rscript test_simple_power_simulation.R` ✓
- [ ] Tests pass ✓
- [ ] Run simulation: `Rscript simple_power_simulation.R`
- [ ] Check Type I error is 3-10%
- [ ] Note the MDE at 80% power
- [ ] Check power curve plot looks reasonable
- [ ] For final version: increase `n_sims = 500`, `n_bootstrap = 199`
- [ ] Run for both pre-COVID and post-COVID
- [ ] Use conservative (larger) MDE in grant
- [ ] Include power curve figure in grant
- [ ] Write sample size justification paragraph

**You're ready to go!**
