# Power Analysis Summary for Grant Application

## Bottom Line

**Question**: How much data do we need to detect an effect of sports gambling on evictions?

**Answer**: The power simulation will tell you the **Minimum Detectable Effect (MDE)** - the smallest effect you can reliably detect with your current sample size.

---

## What This Number Means

If the MDE is **2.1 filings per 1,000 renters**:

✅ **You CAN detect** effects of 2.1 or larger with 80% probability
❌ **You CANNOT reliably detect** effects smaller than 2.1

**Context**: Baseline eviction rate is ~14 filings per 1,000 renters, so MDE of 2.1 = 15% change.

---

## How the Simulation Works (Simple Version)

### Step 1: Use Your Real Data
- Actual eviction rates from 2016-2020 (pre-COVID) or 2021-2025 (post-COVID)
- ~25 states, ~50 months each

### Step 2: Add Fake Treatment Effects
- Pick random states to "treat"
- Add a fake effect (e.g., +2.0 filings per 1,000 renters after treatment)

### Step 3: Test If We Can Detect It
- Run the same statistical method you'll use in your actual study (Callaway-Sant'Anna DiD)
- Check: Did we correctly find the effect? (p-value < 0.05 = yes)

### Step 4: Repeat 500 Times
- Count how often we detect it
- If we detect it 82% of the time → power = 82%

### Step 5: Find the MDE
- Try different effect sizes: 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0
- The effect size where power = 80% is your **MDE**

---

## Why This Matters for Your Grant

Funders want to know:
1. **Can your study detect meaningful effects?** → Yes, if real effects are ≥ MDE
2. **Are you being realistic about power?** → Yes, simulation-based estimate using your real data
3. **Is your design appropriate?** → Yes, validated parallel trends + robust control group

---

## What You'll Get

### 1. Power Curve Plot
```
Power
1.0 |                              ●----●
    |                         ●---
0.8 | - - - - - - - - - ●----        ← MDE here
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

### 2. MDE Number
```
Minimum Detectable Effect: 2.1 filings per 1,000 renters
  (15% change from baseline of 14.0)
```

### 3. Grant-Ready Text
```
"Based on 500 Monte Carlo simulations, we have 80% power
to detect effects of 2.1 or larger eviction filings per
1,000 renter households using Callaway-Sant'Anna
difference-in-differences with never-treated controls."
```

---

## Key Design Choices (Already Built In)

### ✅ Conservative Control Group
- Uses **only never-treated states** as controls (Roth et al. 2023)
- More robust than using "not-yet-treated" states
- Gives you defensible power estimates

### ✅ Validated Parallel Trends
- Pre-COVID: p = 0.14 ✓
- Post-COVID: p = 0.13 ✓
- Both periods have valid identification

### ✅ Proper Inference
- State-level clustering
- Bootstrap standard errors (50 iterations for test, 199 for final)
- Accounts for serial correlation

### ✅ Real Data
- Uses your actual eviction data
- Actual treatment timing
- Actual variance structure

---

## How to Run It

### Quick Test (5 minutes)
```bash
Rscript run_quick_power_test.R
```
This runs 10 simulations to verify everything works.

### Full Version (2-3 hours)
```bash
# Edit simple_power_simulation.R:
config$n_sims = 500           # More simulations
config$n_bootstrap = 199      # More bootstrap iterations

# Then run:
Rscript simple_power_simulation.R
```

You'll get:
- `simple_power_results.csv` - detailed results
- `simple_power_results_plot.png` - power curve for grant
- MDE number printed to screen

---

## Interpreting Results

### If MDE = 2.0 (Good)
> "Our study is well-powered to detect moderate effects (MDE = 2.0 filings per 1,000, or 14% change from baseline). This is consistent with effect sizes found in related literature on consumer credit and housing stability."

### If MDE = 3.5 (Larger)
> "Our study is powered to detect effects of 3.5 filings per 1,000 renters (25% change from baseline). While this reflects our relatively small treated sample (4 states pre-COVID), the study will provide valuable evidence on whether sports gambling has large effects on eviction rates. Smaller effects may exist but would require larger samples or longer follow-up to detect."

### If MDE = 1.5 (Very Good)
> "Our study is well-powered to detect even modest effects (MDE = 1.5 filings per 1,000, or 11% change). The dual-period design (pre- and post-COVID) and staggered adoption timing provide strong identification and ample statistical power."

---

## Common Questions

### "Should I run pre-COVID or post-COVID?"

**Run both** and report the larger (more conservative) MDE.

- Pre-COVID: 4 treated states, 50 months
- Post-COVID: 6 treated states, 57 months

Expected: Post-COVID might have slightly lower MDE (more treated states) but higher variance (COVID aftermath).

### "What if reviewers ask about sample size?"

> "Our sample size (25 states, 50+ months) provides 80% power to detect effects of [MDE] or larger. This is appropriate for staggered policy adoption studies where sample size is determined by the number of states that adopted sports gambling, not by our design choices."

### "Can we increase power?"

Power depends on:
1. **Sample size** (fixed - you have the states you have)
2. **Effect size** (unknown - what you're trying to detect)
3. **Variance** (data-driven - measured from your data)
4. **Design** (staggered DiD is appropriate)

You **cannot** meaningfully increase power without:
- More states adopting gambling (not in your control)
- Longer follow-up period (wait for more data)
- Reduced measurement error (better data sources)

### "What about heterogeneity?"

The MDE is for the **average treatment effect**. You can still:
- Explore heterogeneity by state characteristics
- Look for effect modification
- Describe patterns even if p > 0.05

But you need the average effect to be at least MDE to have good power.

---

## For Your Grant (Copy-Paste Section)

### Sample Size Justification

> We conducted a simulation-based power analysis for our staggered difference-in-differences design using Callaway-Sant'Anna estimation with never-treated controls (Roth et al. 2023). The analysis uses our pre-COVID sample (2016-2020) comprising 4 treated states and 19 control states observed over 50 months, reflecting the natural variation in sports gambling legalization timing across states.
>
> Based on 500 Monte Carlo simulations that preserve the observed variance structure and treatment timing, we estimate 80% power to detect an effect of **[MDE]** eviction filings per 1,000 renter households at the 5% significance level (two-sided test). This represents a **[X]%** change from the baseline eviction rate of [baseline] filings per 1,000 renters.
>
> Type I error was well-calibrated at [X]%, confirming the validity of our identification strategy. These estimates are conservative as they (1) use only never-treated states as controls for maximum robustness, and (2) exclude post-COVID data (2021-2025) which includes 6 additional treated states and may provide supplementary power pending validation of identification assumptions.

### Figure Caption

> **Figure X. Statistical Power Analysis.** Estimated power to detect treatment effects of varying magnitudes using staggered difference-in-differences estimation with Callaway-Sant'Anna method and never-treated controls. Horizontal dashed line indicates 80% power threshold. Vertical line marks the minimum detectable effect (MDE) at 80% power. Based on 500 Monte Carlo simulations using pre-COVID data (2016-2020).

---

## Timeline

1. **Quick test** (5 min) - verify it works
2. **Full run** (2-3 hours) - get final MDE
3. **Write grant text** (15 min) - use template above
4. **Optional**: Run post-COVID separately for robustness

---

## Files You'll Use

- `simple_power_simulation.R` - main script (well-documented, ~300 lines)
- `SIMPLE_POWER_README.md` - detailed user guide
- `control_group_methodology.md` - explains "nevertreated" choice

**You understand everything in these files** - every step is explained in plain English.

---

## Bottom Line for Boss

**This gives you the number you need for the grant**: the minimum effect size you can detect with 80% power.

**It's defensible**:
- Uses your real data
- Uses the method you'll actually use (Callaway-Sant'Anna)
- Conservative control group choice (nevertreated)
- Validated parallel trends

**It's simple**: Each component is documented and testable.

**It's ready**: Run the quick test now, full version overnight, have results tomorrow morning.
