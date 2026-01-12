# Troubleshooting R Fatal Errors

## Quick Fix: Use the SAFE Version

I've created a safer version that avoids common crash causes:

```r
source("test_basic.R")  # Run this first to test your environment
source("eviction_power_analysis_SAFE.R")  # Then run this
```

## Common Causes of R Fatal Errors

### 1. **String Concatenation Issue (FIXED)**
The original scripts used `%+%` which doesn't exist in base R.
- **Fixed in**: All scripts now use `cat(..., sep = "")` instead

### 2. **Package Loading Issues**
Some packages can cause crashes if not installed properly:

```r
# Install packages one at a time:
install.packages("tidyverse")
install.packages("fixest")
install.packages("lubridate")

# Only install if you need wild bootstrap (optional):
install.packages("fwildclusterboot")  # This one can be problematic
```

### 3. **Memory Issues**
Large datasets + loops can crash R. The SAFE version:
- Uses fewer iterations by default
- Avoids loading unnecessary packages
- Includes progress messages

### 4. **File Path Issues**
Make sure you're in the right directory:

```r
# Check current directory
getwd()

# Should show: /Users/bb1806/Documents/eviction_gambling

# If not:
setwd("/Users/bb1806/Documents/eviction_gambling")
```

### 5. **CSV Reading Issues**
If CSV files have encoding problems:

```r
# Try reading with explicit encoding
county_monthly <- read_csv(
  "monthly_county_data_download.csv",
  locale = locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
```

## Step-by-Step Safe Execution

### Step 1: Test Environment
```r
source("test_basic.R")
```

If this crashes, you have a package installation problem. Reinstall packages.

### Step 2: Data Preparation (SAFE Version)
```r
source("eviction_power_analysis_SAFE.R")
```

This will:
- Load and merge data
- Create analysis panel
- Calibrate error process
- Save workspace

### Step 3: Check Results
```r
# Load saved workspace
load("eviction_power_workspace_SAFE.RData")

# Check what was created
ls()

# Inspect analysis panel
head(analysis_panel)
summary(analysis_panel$outcome)
```

## What to Do if R Still Crashes

### Option A: Run in RStudio
RStudio is more stable than R CLI:
1. Open RStudio
2. File → Open File → test_basic.R
3. Click "Source" button

### Option B: Run Line-by-Line
Don't use `source()`. Instead:
1. Open the .R file in a text editor
2. Copy one section at a time
3. Paste into R console
4. Watch for errors

### Option C: Reduce Data Size
Test with a subset:

```r
# In eviction_power_analysis_SAFE.R, add after loading data:
county_monthly <- county_monthly %>%
  filter(state_fips %in% c("06", "36", "48"))  # CA, NY, TX only
```

## Removed Dependencies to Prevent Crashes

The SAFE version does NOT load:
- `boot` package (moving-block bootstrap simplified)
- `fwildclusterboot` (wild bootstrap optional)
- `here` package (not needed)
- `future`/`future.apply` (parallelization removed)

## If All Else Fails

Contact me with:
1. The exact error message
2. Output from `sessionInfo()`
3. R version: `R.version.string`
4. Which line crashed (if known)

## Alternative: Use Simpler Approach

If you just need basic power calculations without full simulation:

```r
# Analytical MDE calculation (no simulation)
# Based on Burlig et al. Equation 2

P <- 0.5  # Proportion treated
J <- 30   # Number of states
m <- 6    # Pre-periods
r <- 6    # Post-periods
sigma2 <- 5  # Variance (estimate from data)
alpha <- 0.05
power <- 0.80

# Simplified variance (assuming no serial correlation)
variance <- (1 / (P * (1 - P) * J)) * ((m + r) / (m * r)) * sigma2
se <- sqrt(variance)

# MDE calculation
t_alpha <- qt(1 - alpha/2, J - 1)
t_power <- qt(power, J - 1)
mde <- (t_alpha + t_power) * se

cat(sprintf("MDE = %.3f\n", mde))
```

This bypasses all simulation and gives you a quick power estimate.
