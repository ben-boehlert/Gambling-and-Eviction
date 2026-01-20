# 🎯 CS-DiD Outputs Summary

## What You Have RIGHT NOW

### ✅ Main Output: Support Diagnostics Table
**Location**: `output/csdid_debug/support_diagnostics_full.csv`
**Size**: 876 rows (875 (g,t) comparisons + header)
**Status**: ✅ **Ready for paper appendix**

**This file contains**:
- All 875 group×time cells from your gambling-eviction data
- For each cell: counts of treated/control × pre/post observations
- Identifiability status (TRUE/FALSE)
- Reason for non-identifiability

**View it**:
```r
library(dplyr)
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

# Summary
table(support$identifiable)
#  FALSE   TRUE
#    537    338

# This means:
# - 338 cells (38.6%) are identifiable
# - 537 cells (61.4%) are NOT identifiable due to missing post-treatment observations
```

---

## What the Patches Created

### 📁 Patch Files (in `patches/`)

**Core functionality**:
1. ✅ `preflight_support_check.R` - Checks support before estimation
2. ✅ `att_gt_safe.R` - Safe CS-DiD wrapper (prevents crashes)
3. ✅ `reg_did_rc_safe.R` - Patched DRDID function
4. ✅ `plot_csdid_pretrends.R` - Pre-trends visualization functions

**Documentation**:
5. ✅ `CSDID_FIX_IMPLEMENTATION.md` - Complete technical docs
6. ✅ `README_PRETRENDS.md` - Pre-trends plotting guide
7. ✅ `FIND_YOUR_OUTPUTS.md` - Guide to finding outputs

**Examples & Tests**:
8. ✅ `EXAMPLE_FULL_WORKFLOW.R` - Complete example (uses synthetic data)
9. ✅ `test_att_gt_safe_regression.R` - Regression tests
10. ✅ `debug_csdid_instrumented.R` - Diagnostic script (uses YOUR data)

---

## How to Generate Full Outputs

### Option 1: Quick - Just View Existing Diagnostics

You already have the support table. View it:

```r
library(dplyr)
library(ggplot2)

# Load support diagnostics
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

# Summary statistics
cat(sprintf("Total (g,t) cells: %d\n", nrow(support)))
cat(sprintf("Identifiable: %d (%.1f%%)\n",
            sum(support$identifiable),
            100*mean(support$identifiable)))
cat(sprintf("Non-identifiable: %d (%.1f%%)\n",
            sum(!support$identifiable),
            100*mean(!support$identifiable)))

# View reasons for non-identifiability
table(support$reason)

# Export for appendix
non_id_summary <- support %>%
  filter(!identifiable) %>%
  count(reason) %>%
  mutate(pct = 100 * n / sum(n))

write.csv(non_id_summary, "output/appendix_support_summary.csv", row.names = FALSE)
```

**This gives you Table A1 for your appendix!**

---

### Option 2: Run CS-DiD on Your Actual Data

**Step 1**: Check if you have prepared panel data:

```bash
ls -lh data/processed/
ls -lh data/raw/
```

**Step 2**: Create `scripts/run_my_csdid.R`:

```r
#!/usr/bin/env Rscript
library(dplyr)
library(readr)
library(did)

# Load patches
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")

# ========== ADJUST THESE LINES FOR YOUR DATA ==========

# Load your panel data (adjust path and column names)
panel_data <- readr::read_csv("data/raw/state_month_panel_with_treatment.csv")

# Or if you need to rebuild it, copy data loading code from:
# analysis/diagnostics/debug_csdid.R (lines 36-180)

# Specify your column names
id_col <- "state_abb"       # Unit identifier
time_col <- "year_month"    # Time period
group_col <- "first_treat"  # Treatment timing (0 = never treated)
outcome_col <- "log_evictions"  # Outcome variable

# ======================================================

cat("\n=== Running CS-DiD on YOUR data ===\n\n")

# Preflight check
check <- preflight_support_check(
  data = panel_data,
  idname = id_col,
  tname = time_col,
  gname = group_col,
  yname = outcome_col,
  control_group = "nevertreated"
)

save_preflight_check(check, "output/my_analysis", "my_data")

# Estimate CS-DiD safely
result <- att_gt_safe(
  yname = outcome_col,
  tname = time_col,
  idname = id_col,
  gname = group_col,
  data = panel_data,
  control_group = "nevertreated",
  est_method = "dr",
  panel = FALSE,
  bstrap = FALSE,
  fail_on_support_issues = FALSE,
  save_support_check = TRUE,
  support_check_dir = "output/my_analysis"
)

# Aggregate
agg_simple <- aggte_safe(result, type = "simple")
agg_dynamic <- aggte_safe(result, type = "dynamic")

# Create plots (limit pre-periods to avoid issues)
dir.create("output/my_analysis/figures", showWarnings = FALSE, recursive = TRUE)

p1 <- plot_event_study(result, pretreatment_periods = 12, posttreatment_periods = 24)
ggsave("output/my_analysis/figures/event_study.pdf", p1, width = 10, height = 6)

p2 <- plot_pretrends_test(result, pretreatment_periods = 12)
ggsave("output/my_analysis/figures/pretrends.pdf", p2$plot, width = 10, height = 6)

# Save results
saveRDS(result, "output/my_analysis/cs_result.rds")
saveRDS(list(simple = agg_simple, dynamic = agg_dynamic),
        "output/my_analysis/aggregates.rds")

# Export table
write.csv(
  data.frame(
    group = result$group,
    time = result$t,
    att = result$att,
    se = result$se,
    ci_lower = result$att - 1.96 * result$se,
    ci_upper = result$att + 1.96 * result$se
  ),
  "output/my_analysis/att_gt_table.csv",
  row.names = FALSE
)

cat("\n✓ All outputs saved to output/my_analysis/\n")
cat(sprintf("\nOverall ATT: %.4f (SE: %.4f)\n",
            agg_simple$overall.att, agg_simple$overall.se))
```

**Step 3**: Run it:

```bash
Rscript scripts/run_my_csdid.R
```

**Step 4**: Find your outputs:

```bash
ls -lR output/my_analysis/
```

You'll get:
- `figures/event_study.pdf`
- `figures/pretrends.pdf`
- `my_data_support_table.csv`
- `att_gt_table.csv`
- `cs_result.rds`

---

## For Your Paper

### Appendix Table A1: Support Diagnostics

**File**: `output/csdid_debug/support_diagnostics_full.csv` (already exists!)

**Create summary table**:

```r
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

# Summary for table
summary_table <- data.frame(
  Category = c("Total (g,t) cells",
               "Identifiable",
               "Non-identifiable"),
  Count = c(nrow(support),
            sum(support$identifiable),
            sum(!support$identifiable)),
  Percentage = c(100,
                 100 * mean(support$identifiable),
                 100 * mean(!support$identifiable))
)

print(summary_table)
#                 Category Count Percentage
# 1  Total (g,t) cells   875      100.0
# 2       Identifiable   338       38.6
# 3   Non-identifiable   537       61.4

# Reasons breakdown
reason_table <- support %>%
  filter(!identifiable) %>%
  count(reason) %>%
  arrange(desc(n))

print(reason_table)
#           reason   n
# 1 n_treat_post=0 537

# Save for LaTeX table
write.csv(summary_table, "output/appendix_table_a1_summary.csv", row.names = FALSE)
write.csv(reason_table, "output/appendix_table_a1_reasons.csv", row.names = FALSE)
```

### LaTeX Code for Appendix

```latex
\begin{table}[htbp]
\centering
\caption{CS-DiD Support Diagnostics}
\label{tab:support}
\begin{tabular}{lrr}
\toprule
Category & Count & Percentage \\
\midrule
Total (g,t) cells & 875 & 100.0\% \\
Identifiable & 338 & 38.6\% \\
Non-identifiable & 537 & 61.4\% \\
\bottomrule
\end{tabular}

\vspace{1em}

\begin{tablenotes}
\small
\item Notes: Non-identifiable cells lack sufficient observations due to treated units not observed in post-treatment periods (n\_treat\_post=0). These cells were excluded from CS-DiD estimation and returned NA. See support\_diagnostics\_full.csv for cell-by-cell breakdown.
\end{tablenotes}
\end{table}
```

---

## Files Created During This Session

### In `patches/` directory:

```
patches/
├── Core Implementation
│   ├── preflight_support_check.R          ✅ Support checking
│   ├── att_gt_safe.R                      ✅ Safe CS-DiD wrapper
│   ├── reg_did_rc_safe.R                  ✅ Patched DRDID
│   └── plot_csdid_pretrends.R             ✅ Plotting functions
│
├── Documentation
│   ├── CSDID_FIX_IMPLEMENTATION.md        ✅ Technical docs
│   ├── README_PRETRENDS.md                ✅ Plotting guide
│   └── FIND_YOUR_OUTPUTS.md               ✅ Output location guide
│
├── Examples & Tests
│   ├── EXAMPLE_FULL_WORKFLOW.R            ✅ Full example
│   ├── test_att_gt_safe_regression.R      ✅ Unit tests
│   └── debug_csdid_instrumented.R         ✅ Diagnostic script
│
└── README.md                               (pre-existing)
```

### In `output/` directory:

```
output/
├── csdid_debug/
│   ├── support_diagnostics_full.csv       ✅ YOUR SUPPORT TABLE (875 rows)
│   ├── instrumented_run.log               ✅ Debug log
│   └── test1/
│       └── att_gt_safe_support_diagnostics.csv  ✅ Test output
│
└── example_csdid/                         (created if you run example)
    ├── example_support_table.csv
    ├── example_summary.txt
    └── att_gt_safe_support_diagnostics.csv
```

---

## Quick Reference Commands

### View existing support table:
```r
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")
View(support)
```

### Run tests to verify everything works:
```bash
Rscript patches/test_att_gt_safe_regression.R
```

### Generate example outputs (synthetic data):
```bash
Rscript patches/EXAMPLE_FULL_WORKFLOW.R
```

### Run diagnostics on YOUR data:
```bash
Rscript patches/debug_csdid_instrumented.R
```

---

## ✅ What You Can Do Right Now

1. **View your support diagnostics** (already exists):
   ```r
   support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")
   ```

2. **Create Appendix Table A1** (from existing diagnostics):
   ```r
   # See LaTeX code above
   ```

3. **Run CS-DiD on your data** (create script from template above):
   ```bash
   Rscript scripts/run_my_csdid.R
   ```

4. **Read the documentation**:
   - `patches/CSDID_FIX_IMPLEMENTATION.md` - How the fix works
   - `patches/README_PRETRENDS.md` - How to create plots
   - `patches/FIND_YOUR_OUTPUTS.md` - Detailed guide

---

**Bottom line**: You have the support diagnostics table ready for your appendix. To get CS-DiD estimates and plots, create a simple script using your actual data (template provided above).
