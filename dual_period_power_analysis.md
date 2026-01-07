# Dual-Period Power Analysis: Pre-COVID + Post-COVID

## Strategy: Two Separate Clean Analyses

Run **two independent power simulations**, excluding the COVID disruption period (March 2020 - June 2021):

1. **Pre-COVID**: January 2016 - February 2020
2. **Post-COVID**: July 2021 - September 2025

---

## Treatment Distribution by Period

### Pre-COVID Adopters (n=4)
- WV: August 2018
- PA: May 2019
- IN: October 2019
- NH: December 2019

### COVID Disruption (n=3) - **EXCLUDE from both analyses**
- CO: May 2020
- TN: November 2020
- VA: January 2021

### Post-COVID Adopters (n=6)
- AZ: September 2021
- CT: October 2021
- NY: January 2022
- AR: March 2022
- KS: September 2022
- OH: January 2023

---

## Why This Works Better Than Synthetic DiD

### ✅ Advantages

**1. Clean Identification in Each Period**
- Pre-COVID: Already validated (parallel trends hold, p=0.14)
- Post-COVID: New equilibrium after moratoria ended
- No need to model the structural break

**2. Sufficient Sample Sizes**
- Pre-COVID: 4 treated states, ~19 never-treated → adequate
- Post-COVID: 6 treated states, ~23 never-treated → good

**3. Adequate Time Windows**
- Pre-COVID: 50 months total (2016-01 to 2020-02)
- Post-COVID: 51 months total (2021-07 to 2025-09)
- Both support 12-month pre/post windows

**4. Answers Policy-Relevant Questions**
- Pre-COVID: "Would early gambling adoption affect evictions in normal times?"
- Post-COVID: "Does gambling affect evictions in current housing market?"
- Both are useful for different audiences

**5. Transparent and Defensible**
- Clear acknowledgment of regime change
- No forced assumptions about structural stability
- Conservative approach shows robustness (or lack thereof)

---

## Feasibility Check: Post-COVID Parallel Trends

**Critical Question**: Do parallel trends hold in post-COVID period?

Let me test this:

```r
# Filter to post-COVID
panel_post <- panel_df %>%
  filter(month_date >= as.Date("2021-07-01"))

# Exclude COVID-disruption adopters (CO, TN, VA)
panel_post_clean <- panel_post %>%
  filter(!(state_abb %in% c("CO", "TN", "VA")))

# Test parallel trends for post-COVID adopters
# Treated: AZ, CT, NY, AR, KS, OH (adopted 2021-07+)
# Control: Never treated + pre-COVID adopters (WV, PA, IN, NH treated before analysis period)
```

**Need to test**:
1. Do post-COVID treated states have parallel pre-trends to controls?
2. Is Type I error calibrated?
3. Are there sufficient pre-treatment periods for each state?

---

## Implementation Plan

### Step 1: Test Post-COVID Parallel Trends

Create `test_postcovid_parallel_trends.R`:

```r
#!/usr/bin/env Rscript
library(tidyverse)
library(lubridate)
library(fixest)

source("power_simulation_cs.R")

# Load full panel
panel_full <- load_panel(cfg)

# Filter to post-COVID period only
panel_post <- panel_full %>%
  filter(month_date >= as.Date("2021-07-01"))

# Get treatment schedule for POST-COVID period
# States that adopted 2021-07+ are "treated"
# Pre-COVID adopters + never-treated are "controls"
treat_dates <- panel_post %>%
  distinct(state_abb) %>%
  left_join(
    read_csv("sports_gambling_legalization_dates.csv") %>%
      select(state_abb, online_start_date) %>%
      mutate(
        treated_post_covid = online_start_date >= as.Date("2021-07-01"),
        control_post_covid = is.na(online_start_date) | online_start_date < as.Date("2021-07-01")
      ),
    by = "state_abb"
  )

# Build baseline (all states, pre-treatment for post-COVID adopters)
baseline_post <- panel_post %>%
  left_join(treat_dates, by = "state_abb") %>%
  # For pre-trends test, use only pre-treatment periods
  filter(
    # Never treated, OR
    control_post_covid |
    # Treated post-COVID but before their treatment date
    (treated_post_covid & month_date < online_start_date)
  )

# Residualize
baseline_resid <- baseline_post %>%
  group_by() %>%
  mutate(
    unit_id = as.integer(factor(state_abb)),
    time_id = as.integer(factor(month_date))
  ) %>%
  ungroup()

m <- feols(outcome ~ 1 | unit_id + time_id, data = baseline_resid)

baseline_resid <- baseline_resid %>%
  mutate(outcome_resid = resid(m) + mean(outcome, na.rm = TRUE))

# Test differential trends
pretrends_data <- baseline_resid %>%
  mutate(treated = treated_post_covid)

pretrends_model <- lm(outcome_resid ~ time_id * treated, data = pretrends_data)

interaction_coef <- summary(pretrends_model)$coefficients["time_id:treatedTRUE", ]

cat("=== Post-COVID Parallel Trends Test ===\n")
cat(sprintf("Differential trend coefficient: %.4f\n", interaction_coef["Estimate"]))
cat(sprintf("t-statistic: %.2f\n", interaction_coef["t value"]))
cat(sprintf("p-value: %.4f\n", interaction_coef["Pr(>|t|)"]))

if (interaction_coef["Pr(>|t|)"] > 0.05) {
  cat("\n✓ Parallel trends HOLD in post-COVID period\n")
} else {
  cat("\n✗ Parallel trends VIOLATED in post-COVID period\n")
}

# Plot
trend_plot_data <- pretrends_data %>%
  group_by(month_date, treated) %>%
  summarise(mean_outcome = mean(outcome_resid, na.rm = TRUE), .groups = "drop")

library(ggplot2)
p <- ggplot(trend_plot_data, aes(x = month_date, y = mean_outcome, color = treated)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  labs(
    title = "Post-COVID Pre-Treatment Trends (2021-07 onwards)",
    subtitle = "Residualized outcomes (unit + time FE removed)",
    x = "Month",
    y = "Eviction Filings per 1,000 Renters (residualized)",
    color = "Group"
  ) +
  scale_color_manual(
    values = c("TRUE" = "#E74C3C", "FALSE" = "#3498DB"),
    labels = c("TRUE" = "Post-COVID Adopters (AZ,CT,NY,AR,KS,OH)",
               "FALSE" = "Controls (never + pre-COVID adopters)")
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("postcovid_pretrends.png", p, width = 10, height = 6, dpi = 300)
cat("\nSaved: postcovid_pretrends.png\n")
```

### Step 2: Run Pre-COVID Power Simulation (Already Done)

Use existing `cfg_precovid.rds`:

```r
cfg_precovid <- readRDS("cfg_precovid.rds")
source("power_simulation_cs.R")
# Outputs: power_precovid_results.csv, power_precovid_curve.png
```

### Step 3: Create Post-COVID Configuration

Create `power_simulation_postcovid_config.R`:

```r
cfg_postcovid <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",

  # POST-COVID PERIOD
  restrict_to_postcovid = TRUE,
  postcovid_start = as.Date("2021-07-01"),

  # Exclude COVID-disruption adopters
  exclude_states = c("CO", "TN", "VA"),

  # Outcome
  outcome_preference = c(
    "filings_per_1k_renters",
    "filings_count_per_1k_renters",
    "filings_count"
  ),

  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date",

  # Simulation parameters
  n_sims = 500,
  effect_grid = seq(0, 3, by = 0.5),
  alpha = 0.05,
  power_target = 0.80,

  # State-level grid
  run_state_switcher_grid = TRUE,
  n_states_grid = c(15, 20, 25),
  n_switchers_grid = c(3, 5, 6),

  # Estimand
  estimand = "overall_att",
  target_h = 12,

  # Windows
  pre_len = 12,
  post_len = 12,

  # Effect shape
  effect_shape = "step",

  # Inference
  did_bstrap = TRUE,
  did_biters = 50,
  cluster_level = "state",

  # Output
  output_prefix = "power_postcovid",
  save_plots = TRUE,
  save_csv = TRUE
)

saveRDS(cfg_postcovid, "cfg_postcovid.rds")
```

### Step 4: Modify `load_panel()` to Support Post-COVID

Add to `power_simulation_cs.R`:

```r
load_panel <- function(cfg) {
  df <- switch(
    cfg$panel_choice,
    "counties" = prep_panel_counties(cfg),
    "states_from_counties" = prep_panel_states_from_counties(cfg),
    "states_ets" = prep_panel_states_ets(cfg),
    "sites_ets" = prep_panel_sites_ets(cfg),
    stop("cfg$panel_choice must be one of: counties, states_from_counties, states_ets, sites_ets")
  )

  # Optional: Restrict to pre-COVID period
  if (!is.null(cfg$restrict_to_precovid) && cfg$restrict_to_precovid) {
    cutoff <- if (!is.null(cfg$precovid_cutoff)) cfg$precovid_cutoff else as.Date("2020-03-01")
    df <- df %>% filter(month_date < cutoff)
    message(sprintf("Restricting panel to pre-COVID: before %s", cutoff))
  }

  # Optional: Restrict to post-COVID period
  if (!is.null(cfg$restrict_to_postcovid) && cfg$restrict_to_postcovid) {
    start_date <- if (!is.null(cfg$postcovid_start)) cfg$postcovid_start else as.Date("2021-07-01")
    df <- df %>% filter(month_date >= start_date)
    message(sprintf("Restricting panel to post-COVID: after %s", start_date))
  }

  # Optional: Exclude specific states
  if (!is.null(cfg$exclude_states)) {
    df <- df %>% filter(!(state_abb %in% cfg$exclude_states))
    message(sprintf("Excluding states: %s", paste(cfg$exclude_states, collapse = ", ")))
  }

  df
}
```

### Step 5: Run Post-COVID Power Simulation

```r
cfg <- readRDS("cfg_postcovid.rds")
source("power_simulation_cs.R")
# Outputs: power_postcovid_results.csv, power_postcovid_curve.png
```

---

## Expected Outputs

### Pre-COVID Analysis
- **Period**: 2016-01 to 2020-02 (50 months)
- **Treated states**: WV, PA, IN, NH (n=4)
- **Control states**: ~19 never-treated
- **Files**:
  - `power_precovid_results.csv`
  - `power_precovid_curve.png`
  - `precovid_traditional_pretrends.png` (already exists)

### Post-COVID Analysis
- **Period**: 2021-07 to 2025-09 (51 months)
- **Treated states**: AZ, CT, NY, AR, KS, OH (n=6)
- **Control states**: ~23 (never-treated + pre-COVID adopters)
- **Files**:
  - `power_postcovid_results.csv`
  - `power_postcovid_curve.png`
  - `postcovid_pretrends.png`

### Comparison Table
```
| Period      | Treated N | Control N | MDE | Power@2.0 | Type I Error |
|-------------|-----------|-----------|-----|-----------|--------------|
| Pre-COVID   | 4         | ~19       | TBD | TBD       | 12%          |
| Post-COVID  | 6         | ~23       | TBD | TBD       | TBD          |
```

---

## Interpretation Strategy

### If Both Periods Show Similar MDEs:
> "Power analysis conducted separately for pre-COVID (2016-2020) and post-COVID (2021-2025) periods reveals consistent minimum detectable effects of ~X filings per 1,000 renters. The consistency across structural regimes strengthens confidence in our design."

### If MDEs Differ:
> "Pre-COVID MDE: X. Post-COVID MDE: Y. The [higher/lower] post-COVID MDE reflects [sample size differences / higher variance in post-COVID housing market / etc.]. We report the conservative (larger) MDE of [max(X,Y)] for pre-analysis plan purposes."

### If Post-COVID Parallel Trends Fail:
> "Parallel trends hold in pre-COVID period (p=0.14) but not post-COVID (p=0.XX). We therefore rely on pre-COVID power estimates (MDE=X), acknowledging this is conservative as post-COVID data will eventually be incorporated pending validation of identification assumptions."

---

## Advantages Over Single-Period or Synthetic DiD

| Approach | Pre-COVID Only | Synthetic DiD | **Dual Period** |
|----------|----------------|---------------|-----------------|
| **Uses all clean data** | ✗ (loses 2021-2025) | ✓ | ✓ |
| **Valid identification** | ✓ | ? (depends on covariates) | ✓ (if post-COVID PT hold) |
| **Transparent** | ✓ | ✗ (complex weights) | ✓ |
| **Policy relevance** | Medium (outdated) | Medium | High (both eras) |
| **Robustness check** | ✗ (single estimate) | ✗ (single estimate) | ✓ (two estimates) |
| **Complexity** | Low | High | Medium |

---

## Potential Challenges

### 1. Post-COVID Parallel Trends May Fail
**Mitigation**:
- Test first (Step 1 above)
- If fail, report pre-COVID only
- At least you checked!

### 2. Shorter Treatment Windows
**Issue**:
- Some post-COVID adopters (OH: 2023-01) have limited post-treatment data
- May not meet 12-month post requirement for all states

**Mitigation**:
- Use `post_len = 9` for post-COVID (have data through 2025-09)
- Or wait until end of 2025 for more data
- Or use asymmetric windows (12 pre, 9 post)

### 3. Different Donor Pools
**Issue**:
- Pre-COVID controls: Never-treated states only
- Post-COVID controls: Never-treated + pre-COVID adopters

**Interpretation**:
- This is OK! Each analysis is internally consistent
- Document clearly
- Sensitivity: exclude pre-COVID adopters from post-COVID controls

---

## Bottom Line Recommendation

### ✅ **Yes, run dual-period analysis**

**Advantages**:
1. Uses all available clean data (2016-2020, 2021-2025)
2. Avoids COVID disruption (2020-03 to 2021-06)
3. Provides robustness check across regimes
4. More policy-relevant than pre-COVID alone
5. Simpler and more transparent than synthetic DiD

**First Step**: Run `test_postcovid_parallel_trends.R` to validate post-COVID identification

**If post-COVID PT hold**: Run both simulations, report both MDEs

**If post-COVID PT fail**: Fall back to pre-COVID only, but at least you checked

---

## Timeline

| Task | Time | Output |
|------|------|--------|
| Test post-COVID parallel trends | 15 min | `postcovid_pretrends.png` |
| Modify `load_panel()` for post-COVID | 10 min | Code update |
| Create `cfg_postcovid.rds` | 5 min | Config file |
| Run post-COVID diagnostics | 15 min | `check_report_postcovid.csv` |
| Run post-COVID power simulation | 2-4 hrs | Power curve, results |
| Create comparison table | 15 min | Summary doc |

**Total**: ~1 day (same as single-period, but with robustness!)

---

## Next Steps

1. **Create and run** `test_postcovid_parallel_trends.R`
2. **Check results**: Do parallel trends hold?
3. **If yes**: Proceed with dual-period approach
4. **If no**: Stick with pre-COVID only

Should I create the post-COVID parallel trends test script now?
