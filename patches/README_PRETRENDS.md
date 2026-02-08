# CS-DiD Crash Fix & Pre-trends Analysis Tools

This directory contains patches and tools to fix the CS-DiD segfault issue and enable publishable, methodologically sound Callaway-Sant'Anna difference-in-differences estimation with comprehensive pre-trends analysis.

## 🎯 Quick Start

```r
# 1. Load patches
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")

# 2. Estimate CS-DiD safely
result <- att_gt_safe(
  yname = "outcome", tname = "time", idname = "id", gname = "first_treat",
  data = your_data, control_group = "nevertreated", panel = FALSE
)

# 3. Create pre-trends report
report <- create_pretrends_report(result,
                                  output_file = "output/pretrends_report.pdf")
```

Or run the complete example:

```bash
Rscript patches/EXAMPLE_FULL_WORKFLOW.R
```

---

## 📁 New Files for Pre-trends Analysis

| File | Purpose |
|------|---------|
| **`plot_csdid_pretrends.R`** | Comprehensive pre-trends visualization functions |
| **`EXAMPLE_FULL_WORKFLOW.R`** | Complete end-to-end workflow with pre-trends testing |

---

## 📊 Pre-trends Visualization Functions

### 1. `plot_event_study()`

Standard event study plot with pre-treatment window highlighted.

```r
p <- plot_event_study(result,
                      pretreatment_periods = 12,
                      posttreatment_periods = 24,
                      show_pretrend_window = TRUE)
```

**Features**:
- Confidence intervals (shaded ribbon)
- Pre-treatment periods marked with hollow circles
- Post-treatment periods marked with filled circles
- Highlighted pre-trend window
- Reference line at zero

### 2. `plot_pretrends_test()`

Formal hypothesis test for parallel trends with visualization.

```r
result <- plot_pretrends_test(att_gt_result, alpha = 0.05)
print(result$plot)
print(result$test_results)
```

**Features**:
- Individual t-tests for each pre-period
- Joint χ² test (Wald test) across all pre-periods
- Color-coded significance (blue = non-sig, red = sig)
- Automatic interpretation text
- Returns both plot and test statistics

**Test Results**:
```r
$joint_p              # p-value for joint test
$passes_pretrends     # TRUE if H0 not rejected
$individual_tests     # Data frame with per-period tests
```

### 3. `plot_group_dynamics()`

Separate event studies for each treatment group.

```r
p <- plot_group_dynamics(result,
                         max_groups = 6,
                         ncol = 2)
```

**Use case**: Check for treatment effect heterogeneity across groups

### 4. `plot_calendar_time()`

Treatment effects by calendar period (not event time).

```r
p <- plot_calendar_time(result)
```

**Use case**: Detect time-varying treatment effects or external shocks

### 5. `plot_support_heatmap()`

Visualize which (g,t) cells are identifiable.

```r
p <- plot_support_heatmap(result,
                          max_groups = 20,
                          max_periods = 50)
```

**Features**:
- Blue tiles = identifiable cells
- Gray tiles = non-identifiable cells
- Shows support structure at a glance

**Requires**: Must use `att_gt_safe()` (not regular `did::att_gt()`)

### 6. `create_pretrends_report()`

Generate comprehensive multi-panel PDF report.

```r
report <- create_pretrends_report(
  att_gt_result,
  output_file = "output/pretrends_report.pdf",
  alpha = 0.05
)
```

**Output**:
- Main event study
- Pre-trends test with interpretation
- Group-specific dynamics
- Calendar time effects
- Support heatmap (if available)
- All combined in single PDF

**Returns**:
```r
$event_study        # ggplot object
$pretrends_test     # ggplot object
$group_dynamics     # ggplot object
$calendar_time      # ggplot object
$support_heatmap    # ggplot object
$combined           # Combined patchwork plot
$test_results       # Pre-trends test statistics
```

---

## 🔬 Complete Workflow Example

See `EXAMPLE_FULL_WORKFLOW.R` for a fully documented example that includes:

1. ✅ Data loading and preparation
2. ✅ Preflight support check
3. ✅ Safe CS-DiD estimation
4. ✅ Result aggregation (simple, dynamic, group, calendar)
5. ✅ Pre-trends testing with formal hypothesis tests
6. ✅ Publication-ready plots
7. ✅ Exporting tables for paper
8. ✅ Cross-validation with Sun-Abraham and didimputation

**Run it**:
```bash
Rscript patches/EXAMPLE_FULL_WORKFLOW.R
```

**Output**: All tables and figures saved to `output/example_csdid/`

---

## 📈 Interpreting Pre-trends Tests

### Joint Hypothesis Test

**Null hypothesis (H₀)**: All pre-treatment ATT(g,t) = 0 (parallel trends hold)

**Test statistic**: χ²(k) where k = number of pre-treatment periods

**Decision rule**:
- If p ≥ α (typically 0.05): **Fail to reject H₀** → Parallel trends assumption supported ✓
- If p < α: **Reject H₀** → Parallel trends assumption violated ✗

### What to Do If Pre-trends Fail

1. **Specification changes**:
   - Add control variables
   - Restrict to more comparable units
   - Adjust pre-treatment window

2. **HonestDiD sensitivity analysis**:
   ```r
   # Use HonestDiD package
   library(HonestDiD)

   # Sensitivity analysis with bounded violations
   honest_result <- createSensitivityResults(
     betahat = agg_dynamic$att.egt,
     sigma = agg_dynamic$se.egt,
     ...
   )
   ```

3. **Alternative estimators**:
   - Try Sun-Abraham (`fixest::sunab`)
   - Try didimputation (Borusyak et al.)
   - Compare results across methods

4. **Transparent reporting**:
   - Report pre-trends test in paper
   - Acknowledge limitation in discussion
   - Provide robustness checks

---

## 📝 For Your Paper

### Reporting Pre-trends

**If pre-trends pass**:
> "We formally tested the parallel trends assumption using a joint Wald test across pre-treatment periods. The test failed to reject the null hypothesis of no pre-trends (χ²(10) = 12.45, p = 0.256), supporting the identifying assumption."

**If pre-trends fail**:
> "The joint test for pre-trends rejected the null hypothesis (χ²(10) = 25.38, p = 0.005), suggesting potential violations of parallel trends. As a robustness check, we implemented the HonestDiD approach (Rambachan & Roth, 2023) to bound treatment effects under plausible violations. Results are reported in Appendix Section X."

### Figure Captions

**Event Study**:
> "Figure 1: Event study estimates of treatment effects. Circles represent point estimates with 95% confidence intervals. Hollow circles indicate pre-treatment periods; filled circles indicate post-treatment periods. The shaded region highlights pre-treatment periods used to test the parallel trends assumption. The vertical dashed line marks the treatment date (t=0)."

**Pre-trends Test**:
> "Figure 2: Formal test of parallel trends assumption. Points show pre-treatment ATT estimates with 95% confidence intervals. Blue indicates non-significant estimates; red indicates significant estimates at the 5% level. The joint Wald test across all pre-treatment periods yields χ²(10) = 12.45, p = 0.256, failing to reject the null hypothesis of no pre-trends."

---

## 🎨 Customizing Plots

All plotting functions return ggplot objects, so you can customize them:

```r
library(ggplot2)

# Base plot
p <- plot_event_study(result)

# Customize
p_custom <- p +
  labs(title = "My Custom Title",
       subtitle = "Additional context") +
  theme_bw() +
  theme(
    text = element_text(family = "serif"),
    plot.title = element_text(size = 16, face = "bold")
  ) +
  scale_color_manual(values = c("blue", "red"))

# Save with high resolution
ggsave("output/custom_event_study.pdf", p_custom,
       width = 10, height = 6, dpi = 600)
```

---

## 🧪 Testing the Plotting Functions

```r
# Source patches
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")

# Create synthetic data for testing
set.seed(123)
test_data <- expand.grid(id = 1:20, time = 1:30) %>%
  mutate(
    first_treat = ifelse(id <= 10, 15, 0),
    y = rnorm(n()) + ifelse(time >= first_treat & first_treat > 0, 1, 0)
  )

# Estimate
result <- att_gt_safe(
  yname = "y", tname = "time", idname = "id", gname = "first_treat",
  data = test_data, control_group = "nevertreated", panel = FALSE
)

# Test each plot
p1 <- plot_event_study(result)
p2 <- plot_pretrends_test(result)$plot
p3 <- plot_group_dynamics(result)
p4 <- plot_calendar_time(result)
p5 <- plot_support_heatmap(result)

# View
print(p1)
print(p2)

# Or create full report
report <- create_pretrends_report(result,
                                  output_file = "output/test_report.pdf")
```

---

## 📦 Dependencies

The plotting functions require:

```r
# Core packages (required)
install.packages(c("ggplot2", "dplyr", "tidyr", "patchwork", "did"))

# Optional (for cross-validation in example workflow)
install.packages(c("fixest", "didimputation"))
```

---

## 🔗 See Also

- **`CSDID_FIX_IMPLEMENTATION.md`**: Technical documentation of the crash fix
- **`README.md`**: Overview of all patches in this directory
- **`test_att_gt_safe_regression.R`**: Regression tests for the fix
- **Original issue**: `analysis/CSDID_CRASH_ROOT_CAUSE.md`

---

**Last Updated**: 2026-01-19
**Author**: Ben Boehlert (with Claude/Anthropic)
