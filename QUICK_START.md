# Quick Start Guide - Power Analysis

## Step 1: Install Packages (Run Once)

```r
source("INSTALL_PACKAGES.R")
```

This installs all required packages, including `fwildclusterboot` from r-universe.

## Step 2: Run Analysis

### Option A: Full Analysis (Recommended)
```r
source("RUN_ALL_ANALYSES.R")
```

### Option B: Minimal Version (If packages fail)
```r
source("RUN_MINIMAL.R")
```

That's it!

---

## What if RUN_SAFE.R also crashes?

### Option 1: Diagnose the problem
```r
source("diagnose_crash.R")
```

This will tell you exactly which package is causing the crash.

### Option 2: Run step-by-step

```r
# Step 1: Test packages
library(fixest)      # If this crashes, reinstall: install.packages("fixest")
library(lubridate)   # If this crashes, reinstall: install.packages("lubridate")

# Step 2: Load data
county_data <- read.csv("monthly_county_data_download.csv")
print(head(county_data))  # Should show first 6 rows

# Step 3: If steps 1-2 work, run the analysis
source("power_analysis_NO_TIDYVERSE.R")
```

### Option 3: Absolute minimum (if everything fails)

If R crashes on ANY script, try this minimal version:

```r
# This uses ONLY base R - no packages at all
df <- read.csv("monthly_county_data_download.csv")
print(nrow(df))  # Should print number of rows

# If this works, your data is fine
# If this crashes, your CSV file is corrupted
```

---

## File Guide

| File | Purpose | When to use |
|------|---------|-------------|
| `RUN_SAFE.R` | One-command runner | **START HERE** |
| `diagnose_crash.R` | Find crash cause | If RUN_SAFE crashes |
| `power_analysis_NO_TIDYVERSE.R` | Main analysis (base R) | If you want to run manually |
| `test_basic.R` | Simple environment test | Quick check |
| `TROUBLESHOOTING.md` | Full troubleshooting guide | Deep dive |

---

## Expected Output

After running `RUN_SAFE.R`, you should see:

```
Analysis panel: 1234 observations, 45 states
Date range: 2018-01-01 to 2023-12-01

CALIBRATING ERROR PROCESS...
Mean residual variance (sigma^2): 2.3456

RUNNING SIMPLE POWER SIMULATION...
Effect size: 0.0 ... Power: 5.0%   <- Should be ~5% (Type I error)
Effect size: 1.0 ... Power: 15.2%
Effect size: 2.0 ... Power: 34.7%
Effect size: 3.0 ... Power: 58.1%
Effect size: 4.0 ... Power: 78.9%
Effect size: 5.0 ... Power: 91.3%

MDE at 80% power: 4.12 filings per 1,000 renters
```

The key result is the **MDE** (Minimum Detectable Effect).

---

## What the MDE means

If MDE = 4.12 filings per 1,000 renters:
- You can detect effects of 4+ filings per 1,000 with 80% power
- Smaller effects (<4) will have lower power
- At 50 states × 12 months = you have good power for moderate effects

---

## Next Steps After Running

```r
# View results
results <- read.csv("power_results_base_r.csv")
print(results)

# Create a simple plot
plot(results$effect_size, results$power,
     type = "b", pch = 19,
     xlab = "Effect Size (filings per 1,000)",
     ylab = "Statistical Power",
     main = "Power Curve")
abline(h = 0.80, lty = 2, col = "red")
```

---

## Still Having Issues?

1. **Check R version**: Type `version` in R console
   - Need R ≥ 4.0.0

2. **Check working directory**:
   ```r
   getwd()  # Should show /Users/bb1806/Documents/eviction_gambling
   ```

3. **Reinstall packages**:
   ```r
   install.packages(c("fixest", "lubridate"))
   ```

4. **Contact**: Provide the output from `sessionInfo()`
