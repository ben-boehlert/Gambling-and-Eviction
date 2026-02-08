# Power Analysis - Quick Start Guide

## What You Need to Know

**Goal**: Get the Minimum Detectable Effect (MDE) for your grant application

**MDE**: The smallest effect you can reliably detect with 80% power

**What it tells your boss**: "We need [X] change in eviction rates to have an 80% chance of detecting it with our current sample size"

---

## Three Simple Steps

### Step 1: Quick Test (Running Now - 5 Minutes)

```bash
Rscript run_quick_power_test.R
```

**What this does**: Runs 10 simulations to verify everything works

**Output**: You'll see power estimates for 3 effect sizes

**What to check**:
- ✓ No errors
- ✓ Type I error (at effect = 0) is around 0-20%
- ✓ Power increases with effect size

### Step 2: Full Power Analysis (2-3 Hours)

Edit `simple_power_simulation.R`:
```r
config <- list(
  period = "precovid",      # or "postcovid" for comparison
  n_sims = 500,             # Change from 100 → 500
  effect_sizes = c(0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0),
  alpha = 0.05,
  target_power = 0.80,
  n_bootstrap = 199,        # Change from 50 → 199
  control_group = "nevertreated",
  output_file = "simple_power_results.csv"
)
```

Then run:
```bash
Rscript simple_power_simulation.R
```

### Step 3: Get Your MDE

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

**Write this number down!** It's what goes in your grant.

---

## What You Get

### 1. Power Curve Plot
File: `simple_power_results_plot.png`

Use this in your grant application!

### 2. Detailed Results
File: `simple_power_results.csv`

All simulation results (for reviewers if they ask)

### 3. Power Summary
File: `simple_power_results_summary.csv`

Power at each effect size tested

---

## For Your Grant Application

Copy this paragraph (fill in [brackets] with your numbers):

> We conducted a simulation-based power analysis using Callaway-Sant'Anna difference-in-differences estimation with never-treated controls (Roth et al. 2023). Based on 500 Monte Carlo simulations using our [pre-COVID/post-COVID] sample ([X] treated states, [Y] control states, [Z] months), we have 80% power to detect an effect of **[MDE]** eviction filings per 1,000 renter households at the 5% significance level (two-sided test). This represents a **[X]%** change from the baseline eviction rate. Type I error was well-calibrated at [X]%, confirming the validity of our identification strategy.

---

## Optional: Run Both Periods for Robustness

### Pre-COVID
```r
config$period = "precovid"
config$output_file = "power_precovid.csv"
```
Run, save MDE

### Post-COVID
```r
config$period = "postcovid"
config$output_file = "power_postcovid.csv"
```
Run, save MDE

### Report in Grant
> "Pre-COVID MDE: [X]. Post-COVID MDE: [Y]. We use the conservative (larger) estimate of [max(X,Y)] for sample size planning."

---

## Troubleshooting

### Error: "No never-treated group"
**Solution**: Already fixed in the code. Ensures at least 3 states remain never-treated.

### Power never reaches 80%
**Solution**: Test larger effect sizes. Edit:
```r
effect_sizes = c(0, 1, 2, 3, 4, 5, 6)
```

### Script too slow
**For testing**: Use `n_sims = 50` and `n_bootstrap = 20`
**For grant**: Use `n_sims = 500` and `n_bootstrap = 199`

---

## Files Reference

| File | Purpose | Read This? |
|------|---------|-----------|
| `simple_power_simulation.R` | Main script | Skim if curious |
| `SIMPLE_POWER_README.md` | Complete manual | If you have time |
| `POWER_ANALYSIS_SUMMARY.md` | Boss-friendly summary | ✓ YES |
| `QUICK_START_GUIDE.md` | This file | You're reading it |
| `control_group_methodology.md` | Why "nevertreated"? | If reviewer asks |

---

## Bottom Line

1. ✅ Quick test is running (5 min)
2. ⏳ Edit config for full run (2 min)
3. ⏳ Run full simulation (2-3 hours, can run overnight)
4. ⏳ Get MDE number (instant once #3 done)
5. ⏳ Write grant paragraph (5 min)

**Total active time**: ~10 minutes
**Total wait time**: 2-3 hours (run overnight)
**What you get**: The number you need for your grant
