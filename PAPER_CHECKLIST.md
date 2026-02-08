# CS-DiD Paper Submission Checklist

Use this checklist to ensure all CS-DiD materials are ready for your paper submission.

---

## ✅ Data & Analysis Files

### Core Patches
- [ ] `patches/preflight_support_check.R` exists and loads without errors
- [ ] `patches/att_gt_safe.R` exists and loads without errors
- [ ] `patches/reg_did_rc_safe.R` exists and loads without errors
- [ ] `patches/plot_csdid_pretrends.R` exists and loads without errors

**Verification**:
```r
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")
# Should load without errors
```

### Support Diagnostics
- [ ] `output/csdid_debug/support_diagnostics_full.csv` exists (875 rows)
- [ ] `output/csdid_plots/summary_statistics.csv` exists
- [ ] `output/csdid_plots/non_identifiable_reasons.csv` exists

**Verification**:
```r
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")
nrow(support)  # Should be 875
table(support$identifiable)
#  FALSE   TRUE
#    537    338
```

### Plots
- [ ] `output/csdid_plots/support_heatmap.pdf` exists
- [ ] `output/csdid_plots/identifiability_by_event_time.pdf` exists
- [ ] `output/csdid_plots/identifiability_by_group.pdf` exists
- [ ] `output/csdid_plots/cell_counts_distribution.pdf` exists

**Verification**:
```bash
ls -lh output/csdid_plots/*.pdf
# Should show 4 PDF files
```

---

## 📝 Paper Components

### Methods Section
- [ ] Mention Callaway-Sant'Anna (2021) estimator
- [ ] State total number of (g,t) cells (875)
- [ ] Report identifiable cells: 338 (38.6%)
- [ ] Report non-identifiable cells: 537 (61.4%)
- [ ] Explain primary reason: treated units not observed post-treatment
- [ ] Reference Appendix Table A1 for full diagnostics

**Suggested text** (in `FINAL_DELIVERABLES_SUMMARY.md`):
```
We employed the Callaway and Sant'Anna (2021) doubly-robust difference-in-differences
estimator to estimate group-time average treatment effects ATT(g,t) for all 875
group×time cells. Due to the unbalanced panel structure and limited post-treatment
observation windows for later-treated states, 537 cells (61.4%) were non-identifiable
primarily because treated units were not observed in certain post-treatment periods.
These cells were excluded from estimation and are documented in Appendix Table A1.
Our final estimates are based on 338 identifiable cells (38.6%) with complete support.
```

### Results Section
- [ ] Report overall ATT from `aggte(type="simple")`
- [ ] Discuss event study results from `aggte(type="dynamic")`
- [ ] Include event study figure in main text or appendix
- [ ] Interpret pre-trends (should be close to zero pre-treatment)
- [ ] Discuss treatment effect dynamics post-treatment

### Appendix A: CS-DiD Diagnostics

#### Table A1: Support Diagnostics Summary
- [ ] Create table with three rows:
  - Total (g,t) cells: 875 (100.0%)
  - Identifiable: 338 (38.6%)
  - Non-identifiable: 537 (61.4%)
- [ ] Add note about `n_treat_post=0` as primary reason
- [ ] Mention full cell-by-cell diagnostics available in online appendix

**Data source**: `output/csdid_plots/summary_statistics.csv`

#### Figure A1: Support Heatmap
- [ ] Include `output/csdid_plots/support_heatmap.pdf`
- [ ] Caption: "Identifiability status of CS-DiD (g,t) cells. Blue cells are identifiable with complete support; gray cells lack sufficient observations for estimation."

#### Figure A2: Identifiability by Event Time
- [ ] Include `output/csdid_plots/identifiability_by_event_time.pdf`
- [ ] Caption: "Percentage of (g,t) cells that are identifiable at each event time. Identifiability declines at later event times as treated units drop out."

#### Figure A3: Identifiability by Treatment Group
- [ ] Include `output/csdid_plots/identifiability_by_group.pdf`
- [ ] Caption: "Percentage of time periods where each treatment group is identifiable. Later-treated groups have fewer identifiable periods due to limited post-treatment windows."

### Online Appendix
- [ ] Include full support table: `output/csdid_debug/support_diagnostics_full.csv`
- [ ] Add column descriptions:
  - `g`: Treatment group (first treatment time)
  - `t`: Calendar time period
  - `n_treat_pre`: Number of treated units pre-treatment
  - `n_treat_post`: Number of treated units post-treatment
  - `n_control_pre`: Number of control units pre-treatment
  - `n_control_post`: Number of control units post-treatment
  - `identifiable`: Whether cell has complete support
  - `reason`: Reason for non-identifiability (if applicable)

---

## 🔬 Robustness Checks

### Pre-trends Test
- [ ] Report joint test p-value for pre-treatment periods
- [ ] If p-value < 0.05, acknowledge potential pre-trends violation
- [ ] Consider alternative specifications or shorter pre-period

**Code**:
```r
source("patches/plot_csdid_pretrends.R")
result <- readRDS("output/my_analysis/cs_result.rds")
pretrends <- plot_pretrends_test(result, pretreatment_periods = 12)
pretrends$test_results  # Shows joint test p-value
```

### Sensitivity Analysis
- [ ] Consider Sun-Abraham estimator as robustness check
- [ ] Consider Borusyak et al. (didimputation) as alternative
- [ ] Report if results are qualitatively similar

**Code**:
```r
# Sun-Abraham (requires fixest)
library(fixest)
sa_result <- feols(log_evictions ~ sunab(first_treat, year_month) | state_id + year_month,
                   data = panel_data, cluster = ~state_id)

# Borusyak et al. (didimputation)
library(didimputation)
bi_result <- did_imputation(panel_data, i = "state_id", t = "year_month",
                            g = "first_treat", y = "log_evictions",
                            horizon = TRUE)
```

### Alternative Specifications
- [ ] Test different control groups (if applicable)
- [ ] Test different outcome transformations (log vs levels)
- [ ] Test different event study windows
- [ ] Test with/without covariates

---

## 🧪 Code Verification

### Regression Tests
- [ ] Run regression tests to verify patches work correctly

**Command**:
```bash
Rscript patches/test_att_gt_safe_regression.R
```

**Expected output**: All 3 tests pass
- Test 1: Unbalanced panel with `n_treat_post=0` → no crash, NA flagged
- Test 2: Unbalanced panel with `n_control_post=0` → no crash, NA flagged
- Test 3: Balanced panel → all cells estimated

### Reproduce Support Diagnostics
- [ ] Regenerate support diagnostics to ensure reproducibility

**Command**:
```bash
Rscript scripts/generate_support_plots.R
```

**Expected output**: 4 plots regenerated in `output/csdid_plots/`

---

## 📊 Data Reporting

### Sample Description
- [ ] Report total number of states: 37 (excluding Maine)
- [ ] Report number of treated states: 16
- [ ] Report number of never-treated control states: 21
- [ ] Report number of treatment groups: 15
- [ ] Report event study window: [-12, +24] months
- [ ] Report time period coverage (earliest to latest year_month)
- [ ] Report total observations in analysis sample

**Data source**: `CSDID_STATE_COUNT.txt` and your panel data

### Treatment Timing
- [ ] Include table or figure showing treatment timing by state
- [ ] Report range of first treatment times
- [ ] Note any clusters in treatment timing

**Data source**: `data/raw/sports_gambling_legalization_dates.csv`

---

## 🔍 Code Availability

### For Replication Package
- [ ] Include all patch files in `patches/` directory
- [ ] Include `scripts/generate_support_plots.R`
- [ ] Include data preparation scripts
- [ ] Include analysis scripts that use `att_gt_safe()`
- [ ] Include README explaining how to use patches
- [ ] Document R package versions used

**Key files to include**:
```
replication_package/
├── patches/
│   ├── preflight_support_check.R
│   ├── att_gt_safe.R
│   ├── reg_did_rc_safe.R
│   └── plot_csdid_pretrends.R
├── scripts/
│   ├── 01_data_preparation.R
│   ├── 02_run_csdid.R
│   └── 03_generate_plots.R
├── data/
│   └── (your cleaned data)
├── README.md
└── sessionInfo.txt
```

### Session Info
- [ ] Record R version and package versions

**Command**:
```r
sessionInfo()
writeLines(capture.output(sessionInfo()), "replication_package/sessionInfo.txt")
```

---

## 📚 Citations

### Required Citations
- [ ] Callaway, Brantly, and Pedro H.C. Sant'Anna. "Difference-in-differences with multiple time periods." Journal of Econometrics 225.2 (2021): 200-230.
- [ ] Sant'Anna, Pedro HC, and Jun Zhao. "Doubly robust difference-in-differences estimators." Journal of Econometrics 219.1 (2020): 101-122.

### Optional Citations (if using for robustness)
- [ ] Sun, Liyang, and Sarah Abraham. "Estimating dynamic treatment effects in event studies with heterogeneous treatment effects." Journal of Econometrics 225.2 (2021): 175-199.
- [ ] Borusyak, Kirill, Xavier Jaravel, and Jann Spiess. "Revisiting event study designs: Robust and efficient estimation." arXiv preprint arXiv:2108.12419 (2021).

---

## ✅ Final Checks

### Before Submission
- [ ] All code runs without errors
- [ ] All figures have captions
- [ ] All tables have notes
- [ ] Support diagnostics match reported numbers
- [ ] Event study plots show clear pre-trends
- [ ] Treatment effects are interpretable magnitudes
- [ ] Standard errors are reasonable (not too small/large)
- [ ] All files referenced in paper exist
- [ ] Replication package is complete
- [ ] README explains how to reproduce results

### Documentation Review
- [ ] Read `FINAL_DELIVERABLES_SUMMARY.md` for overview
- [ ] Check `QUICK_START.md` for quick reference
- [ ] Review `patches/CSDID_FIX_IMPLEMENTATION.md` for technical details
- [ ] Verify plots in `output/csdid_plots/` are publication-quality

---

## 🎯 Key Numbers to Double-Check

Before submission, verify these numbers are consistent throughout your paper:

| Item | Expected Value | Location to Check |
|------|----------------|-------------------|
| Total states | 37 | `CSDID_STATE_COUNT.txt` |
| Treated states | 16 | Same |
| Control states | 21 | Same |
| Treatment groups | 15 | Same |
| Total (g,t) cells | 875 | `support_diagnostics_full.csv` |
| Identifiable cells | 338 (38.6%) | Same |
| Non-identifiable cells | 537 (61.4%) | Same |
| Event study window | [-12, +24] | Your analysis script |

**Verification command**:
```r
support <- read.csv("output/csdid_debug/support_diagnostics_full.csv")
cat(sprintf("Total cells: %d\n", nrow(support)))
cat(sprintf("Identifiable: %d (%.1f%%)\n",
            sum(support$identifiable),
            100*mean(support$identifiable)))
cat(sprintf("Non-identifiable: %d (%.1f%%)\n",
            sum(!support$identifiable),
            100*mean(!support$identifiable)))
```

---

## 🚀 Ready to Submit?

Once all boxes are checked:
- [ ] Final proofreading of methods and results sections
- [ ] All co-authors have reviewed CS-DiD methodology
- [ ] Replication package tested by independent party (if possible)
- [ ] All supplementary materials uploaded
- [ ] Cover letter mentions methodological rigor of CS-DiD implementation

**You're ready to submit!** 🎉

---

**Generated**: 2026-01-19
**Project**: Gambling and Eviction CS-DiD Analysis
