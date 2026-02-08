# Where to Find Your CS-DiD Outputs

## 📍 Quick Reference

All outputs are organized in the `output/` directory:

```
output/
├── csdid_debug/                    # Diagnostic outputs
│   ├── support_diagnostics_full.csv   # Full (g,t) support table (MAIN)
│   ├── instrumented_run.log           # Debug run log
│   └── test1/                          # Test outputs
│
├── example_csdid/                  # Example workflow outputs (if you ran it)
│   ├── figures/                        # All plots
│   ├── att_gt_estimates.csv           # ATT(g,t) table
│   ├── aggregate_effects.csv          # Aggregate effects
│   └── pretrends_test.csv             # Pre-trends test results
│
└── pretrends_evaluation/           # Your actual analysis outputs
    └── baseline/
        ├── event_study_coefs.csv
        ├── honestdid_sensitivity.csv
        └── ...
```

---

## 🔍 What Exists Right Now

Let me check what you currently have:

```bash
# See all CS-DiD related outputs
find output/ -type f \( -name "*csdid*" -o -name "*support*" -o -name "*att*" \) -ls

# See example outputs (if generated)
ls -lR output/example_csdid/
```

**Currently available:**
- ✅ `output/csdid_debug/support_diagnostics_full.csv` - Your actual data support table (875 rows)
- ✅ `output/csdid_debug/test1/att_gt_safe_support_diagnostics.csv` - Test data support table

---

## 🚀 Quick Start: Generate Outputs for YOUR Data

Instead of running the full example, let's create outputs with your actual gambling-eviction data:

### Step 1: Create a Simple Script

Create `scripts/run_csdid_fixed.R`:

```r
#!/usr/bin/env Rscript
# Simple script to run CS-DiD on your actual data

library(dplyr)
library(readr)
library(did)
library(ggplot2)

# Load patches
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")

# Load YOUR actual data (adjust path as needed)
# Option 1: If you have a prepared panel file
panel_data <- readr::read_csv("data/processed/your_panel_file.csv")

# Option 2: Or reconstruct from raw files (use code from debug_csdid.R)
# source("analysis/diagnostics/debug_csdid.R")  # Contains data loading functions

# Run preflight check
cat("\n=== PREFLIGHT CHECK ===\n")
check <- preflight_support_check(
  data = panel_data,
  idname = "id",           # Adjust column names
  tname = "year_month",    # Adjust column names
  gname = "first_treat",   # Adjust column names
  yname = "log_evictions", # Adjust column names
  control_group = "nevertreated"
)

# Save diagnostics
save_preflight_check(check, output_dir = "output/my_csdid", prefix = "gambling_eviction")

# Estimate CS-DiD
cat("\n=== CS-DID ESTIMATION ===\n")
result <- att_gt_safe(
  yname = "log_evictions",
  tname = "year_month",
  idname = "id",
  gname = "first_treat",
  data = panel_data,
  control_group = "nevertreated",
  est_method = "dr",      # Doubly robust
  panel = FALSE,           # Use repeated cross-sections for unbalanced
  clustervars = "state_id", # Adjust as needed
  bstrap = FALSE,          # Set TRUE for bootstrap (slower)
  fail_on_support_issues = FALSE,
  save_support_check = TRUE,
  support_check_dir = "output/my_csdid"
)

# Aggregate
cat("\n=== AGGREGATION ===\n")
agg_simple <- aggte_safe(result, type = "simple")
agg_dynamic <- aggte_safe(result, type = "dynamic")

cat(sprintf("\nOverall ATT: %.4f (SE: %.4f)\n",
            agg_simple$overall.att, agg_simple$overall.se))

# Create plots
cat("\n=== CREATING PLOTS ===\n")
dir.create("output/my_csdid/figures", showWarnings = FALSE, recursive = TRUE)

# Event study
p1 <- plot_event_study(result)
ggsave("output/my_csdid/figures/event_study.pdf", p1, width = 10, height = 6)

# Pre-trends (limit to reasonable number of periods)
p2_result <- plot_pretrends_test(result, pretreatment_periods = 12)
ggsave("output/my_csdid/figures/pretrends_test.pdf", p2_result$plot,
       width = 10, height = 6)

# Group dynamics
p3 <- plot_group_dynamics(result)
ggsave("output/my_csdid/figures/group_dynamics.pdf", p3, width = 10, height = 8)

# Support heatmap
p4 <- plot_support_heatmap(result)
ggsave("output/my_csdid/figures/support_heatmap.pdf", p4, width = 10, height = 6)

# Save results
saveRDS(result, "output/my_csdid/cs_result.rds")
saveRDS(agg_simple, "output/my_csdid/agg_simple.rds")
saveRDS(agg_dynamic, "output/my_csdid/agg_dynamic.rds")

# Export tables
write.csv(
  data.frame(
    group = result$group,
    time = result$t,
    att = result$att,
    se = result$se
  ),
  "output/my_csdid/att_gt_table.csv",
  row.names = FALSE
)

cat("\n✓ All outputs saved to output/my_csdid/\n")
```

### Step 2: Run It

```bash
Rscript scripts/run_csdid_fixed.R
```

### Step 3: Find Your Outputs

```bash
ls -lR output/my_csdid/
```

You'll get:
- `gambling_eviction_support_table.csv` - Support diagnostics
- `figures/event_study.pdf` - Main event study plot
- `figures/pretrends_test.pdf` - Pre-trends test
- `figures/group_dynamics.pdf` - Group-specific plots
- `figures/support_heatmap.pdf` - Support heatmap
- `att_gt_table.csv` - Full ATT(g,t) estimates
- `cs_result.rds` - Full results object

---

## 📊 Viewing Existing Diagnostics

You already have the support diagnostics from the instrumented debug run:

```r
# In R:
library(dplyr)

# Load existing support table
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")

# Summary
table(support$identifiable)
table(support$reason)

# View non-identifiable cells
non_id <- support[!support$identifiable, ]
head(non_id, 20)

# Summary stats
cat(sprintf("Total cells: %d\n", nrow(support)))
cat(sprintf("Identifiable: %d (%.1f%%)\n",
            sum(support$identifiable),
            100 * mean(support$identifiable)))
cat(sprintf("Non-identifiable: %d (%.1f%%)\n",
            sum(!support$identifiable),
            100 * mean(!support$identifiable)))
```

**This table is already publication-ready for your appendix!**

---

## 🎨 Creating Plots from Existing Results

If you already have `att_gt` results saved somewhere:

```r
source("patches/plot_csdid_pretrends.R")

# Load existing results
result <- readRDS("path/to/your/saved/result.rds")

# Create plots
p1 <- plot_event_study(result)
p2 <- plot_pretrends_test(result, pretreatment_periods = 12)  # Limit periods
p3 <- plot_group_dynamics(result)

# Save
ggsave("output/event_study.pdf", p1, width = 10, height = 6)
ggsave("output/pretrends.pdf", p2$plot, width = 10, height = 6)
```

---

## ❌ If You Get "File Not Found" Errors

**Problem**: The example workflow creates synthetic data, not your real data

**Solution**: Use the simple script above with your actual data files

**Or manually run just the instrumented debug** (which uses your real data):

```bash
Rscript patches/debug_csdid_instrumented.R > output/debug_run.log 2>&1
```

This will populate:
- `output/csdid_debug/support_diagnostics_full.csv`
- `output/csdid_debug/panel_cs.rds` (if you save it)

---

## 🔧 Troubleshooting

### "Cannot find data file"

Update the data loading section in your script:

```r
# Check what files you have
list.files("data/raw/")
list.files("data/processed/")

# Use the correct path
panel_data <- readr::read_csv("data/raw/combined_monthly_panel.csv")
# OR
panel_data <- readr::read_csv("data/processed/your_prepared_panel.csv")
```

### "Column not found"

Check your column names:

```r
names(panel_data)

# Then update the att_gt_safe() call with correct names
result <- att_gt_safe(
  yname = "your_outcome_column",
  tname = "your_time_column",
  idname = "your_id_column",
  gname = "your_treatment_column",
  ...
)
```

### "Example outputs empty"

The example workflow uses synthetic data. To get outputs with YOUR data:

1. Copy the simple script template above
2. Update data loading and column names
3. Run it
4. Check `output/my_csdid/`

---

## 📁 Recommended Output Structure

For your paper, organize like this:

```
output/
├── csdid_final/                    # Your final analysis
│   ├── figures/
│   │   ├── figure1_event_study.pdf
│   │   ├── figure2_pretrends.pdf
│   │   └── appendix_support_heatmap.pdf
│   ├── tables/
│   │   ├── table1_aggregate_effects.csv
│   │   ├── appendix_att_gt.csv
│   │   └── appendix_support_diagnostics.csv
│   └── results/
│       ├── cs_result_full.rds
│       └── agg_dynamic.rds
```

---

## ✅ Next Steps

1. **Check what you have**: `ls -lR output/csdid_debug/`
2. **Create simple script**: Use template above with your data
3. **Run it**: `Rscript scripts/run_csdid_fixed.R`
4. **Find outputs**: `ls -lR output/my_csdid/`
5. **Use for paper**: Copy to `output/csdid_final/`

---

**Need help?** The key file is:
- `output/csdid_debug/support_diagnostics_full.csv` ← This already exists and has your full support table!

Just view it to see which (g,t) cells are identifiable in your actual data.
