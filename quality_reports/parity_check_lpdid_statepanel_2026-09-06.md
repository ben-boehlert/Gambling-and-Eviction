# Parity check: `analysis/main/lpdid_statepanel.R` vs the PAP power spec

**Date:** 2026-09-06
**Question:** If the real-data script is run with the headline PAP settings, does it estimate the same thing the blinded power framework simulated?
**Reference spec:** `config/power_lpdid_shift12_clean_mde_ewatt_pmd6.yml` — LP-DiD, `event_clean` anchor on shift12, PMD 6 pre-launch baseline, horizons 0..12 from the event (= months 12–24 after launch), EWATT, wild cluster bootstrap, COVID drop 2020-03..2021-07, `exclude_states: [NV, ID, HI, MS]`, S2 sample (no balancing), panel floor 2016-01.
**Framework estimator:** `.re_lpdid()` in `R/power/run_estimators.R`.
**Blindness:** no real-data treatment estimate was produced. The empirical test runs on simulated panels from the blinded framework; the real-data part of this memo uses dates and coverage only.

## Verdict

The estimator logic is identical. The script's sample construction is not, and as written it would run the PAP spec on the wrong panel. Three settings and two code changes are needed before the real run (see §4).

## 1. Empirical test (simulated panels, no real outcomes)

Harness: `analysis/diagnostics/lpdid_statepanel_parity/`. Step 1 builds panels exactly as the framework does for the headline config (`load_blinded_panel` S2/drop, exclusions, `make_pseudo_schedule` D1 panel-template, `impose_effect` count_nb/step) for three seeds × δ ∈ {0, 0.10}, runs `run_estimator(..., "lpdid")` with the config's spec, and writes each simulated panel out in the real panel's CSV shape. Step 2 runs the repo script, byte-for-byte, on those CSVs from a scratch working directory with

```
TREAT_DEF=shift12 ANCHOR=event_clean PMD=6 POST=12 POST_MIN=0 LPDID_WEIGHTS=ewatt MAX_DATE=2030-12-31 BOOT_REPS=999
```

twice: the unmodified script ("as-is") and a scratch copy with only the two balancing filters at lines 123 and 126 disabled ("no-balance").

| seed | δ | framework ATT | script ATT, no-balance | diff | framework SE | script SE | diff | script ATT, as-is |
|---|---|---|---|---|---|---|---|---|
| 101 | 0 | 0.04407 | 0.04407 | 1e-16 | 0.03738 | 0.03738 | 0 | 0.2376 |
| 101 | 0.10 | 0.14862 | 0.14862 | 1e-16 | 0.03761 | 0.03761 | 0 | 0.3353 |
| 202 | 0 | 0.00240 | 0.00240 | 1e-15 | 0.03703 | 0.03703 | 0 | 0.0083 |
| 202 | 0.10 | 0.10927 | 0.10927 | 1e-15 | 0.03557 | 0.03557 | 0 | 0.1451 |
| 303 | 0 | 0.05849 | 0.05849 | 3e-16 | 0.04502 | 0.04502 | 0 | crash |
| 303 | 0.10 | 0.16096 | 0.16096 | 3e-16 | 0.04233 | 0.04233 | 0 | crash |

Wild p-values (script vs framework, no-balance): 0.321/0.309, 0.003/0.004, 0.960/0.960, 0.031/0.028, 0.237/0.227, 0.004/0.005 — bootstrap noise only (different draws, B = 999 both). Analytic p differs at the third decimal because the script reports fixest's default t(G−1) while the framework uses t(n_clusters−1) on the same SE; same object.

Full table: `output/lpdid_statepanel_parity/parity_comparison.csv`. Framework rows: `framework_results.csv`. Script logs per run: `s*/log_{asis,nobalance}.txt`.

**Reading.** With balancing off, the pooled ATT and SE agree to machine precision on all six panels. The cell construction (event × launch × horizon), the strict PMD baseline, the launch-gated clean-control rule, the EWATT weights, the cell-FE WLS, and the state-clustered vcov are the same estimator. As-is, the script's max-coverage filter kept 4 of 33 states (all pseudo-treated, zero never-treated) and crashed on one seed.

## 2. Code-level comparison (every knob)

| Element | Framework (`.re_lpdid`, loader, grid) | Script (`lpdid_statepanel.R`) | Parity |
|---|---|---|---|
| Treatment event | `shift12_start_date` from `data/processed/shift12_schedule.csv` | `online_start_date + 12 months` (line 146) | OK — verified equal for all 38 schedule rows |
| Control gating | `pseudo_launch` (launch is absorbing; unlaunched through event+h) | `g_launch = online start` (line 247) | OK |
| Anchor / baseline | event_clean; mean of PMD calendar months before launch, NA if any absent | same (lines 186–189, 250) | OK |
| Horizons | `lpdid_hmin 0`, `lpdid_post 12` (config defaults) | `POST_MIN`, `POST` env | OK only if `POST=12 POST_MIN=0` (script defaults 0..18) |
| PMD | 6 | `PMD` env (default 3) | OK only if `PMD=6` |
| Weights | ewatt, `1/(1−Dbar_cell)` | identical function (line 284) | OK |
| Regression | `feols(dy ~ D_treat \| cell, weights = rw, cluster = state)` | identical (line 385) | OK |
| Wild bootstrap | boottest, Rademacher, B 999, fwl engine (sqrt-w scaled OLS, `fe=cell`) | boottest on the WLS fit, dummy-expanded FE, B 9999 | OK (engines proven equivalent in `test-estimators.R`; different draws) |
| COVID window | 2020-03-01..2021-07-31 | same defaults (lines 109–110) | OK |
| Panel floor | 2016-01-01 | `MIN_DATE` default 2016-01-01 | OK |
| Panel end | none | `MAX_DATE` default **2024-12-31** | **BREAK** — drops NC, DE, VT outcome windows entirely and truncates OH/KY/ME/WV (§3) |
| Sample | S2: every state with its own coverage, no balancing | keeps only states at the **maximum** month count, then common months (lines 122–126) | **BREAK** — on the current 39-state panel only MD and NC survive (109 months); the panel is unbalanced by design since the 2026-08-28 per-state basket rebuild |
| Exclusions | `exclude_states: [NV, ID, HI, MS]` before schedule derivation | no knob; NV (54 months, no schedule row) enters as a never-treated control | **BREAK** — always-treated NV in the control pool, plus ID/HI/MS |
| Pre-treatment leads | not estimated by `.re_lpdid` | `PRE` leads at event−h, skipped when ≥ launch | **EMPTY** under shift12: every lead h ≤ 12 lands in the buildup and is dropped, so the joint pre-trend block reports 0 coefficients (confirmed in every harness log). h in 13..18 would overlap the baseline window itself. |
| Gap-tolerant / segment baseline | `lpdid_pmd_min`, `lpdid_base_gapmax` — both OFF in the spec | `DROP_STRADDLING` (default FALSE) | OK for the spec; the two rescue knobs have no script counterpart, which is fine because the PAP rejected them |
| Straddle handling | strict baseline → a window touching the gap is NA | same | OK |

## 3. Real-data design geometry under each setting (dates and coverage only)

Computed from `data/raw/state_month_panel_with_treatment.csv` (vintage 7, 2026-09-03) and the online schedule; no outcome values used.

**Script defaults (MAX_DATE 2024-12-31, no exclusions, before the balancing filter):** 10 usable switchers — full 13 horizons: AR KS MD; partial: FL(1) IN(3) KY(4) ME(2) NH(5) OH(12) WV(7). Baseline-eligible but no outcome months at all: DE MA NC PA RI VT. Never-treated pool includes NV, ID, HI, MS.

**Power spec (no end cap, ex NV/ID/HI/MS):** 13 usable switchers — full: AR KS MD ME NC OH; partial: DE(9) FL(5) IN(3) KY(12) NH(5) VT(9) WV(7). No baseline (touches the COVID gap): AZ CO CT LA NY TN VA, plus MO (series ends 2023-01). Never-treated pool: AK GA MN MT ND NM OK SC TX UT WI.

Then the balancing filter removes everything except MD and NC, so the script as written cannot run the spec on real data at all.

Two things to reconcile against the handoff's contributor list (12 switchers: KS MD OH KY ME NC full; NH IN DE VT WV AR partial): FL now contributes 5 horizons (2023-12 launch; series runs to 2025-04), AR is full-window, and KY is one horizon short. The handoff list predates the MD extension and may have used the capped panel; the PAP should cite the geometry above, recomputed on the frozen vintage.

Note for the PAP text, not a parity break: five retail-only states (MT, ND, NM, WI, and MS before exclusion) sit in the never-treated pool because the treatment is online launch. The framework treats them the same way. The blinded sims saw less of their post-retail data than the real run will (blindness truncation at first launch − 6), so their control contribution is larger in the real run.

## 4. Required before the real run

Settings (environment variables, no code change):

```bash
TREAT_DEF=shift12 ANCHOR=event_clean PMD=6 POST=12 POST_MIN=0 LPDID_WEIGHTS=ewatt MAX_DATE=2026-06-30 Rscript analysis/main/lpdid_statepanel.R
```

Code changes to `analysis/main/lpdid_statepanel.R` — **items 1–3 APPLIED 2026-09-06 (same session)**: `BALANCE_PANEL` knob (default FALSE, old filter retained behind it), `EXCLUDE_STATES` knob (default `NV,ID,HI,MS`) plus `assert_no_pre_paspa_controls()` on the never-launched pool, `MAX_DATE` uncapped by default. Re-verified: the edited script reproduces the framework ATT/SE to 1e-15 on all six panels with no env override of the sample knobs (`output/lpdid_statepanel_parity/parity_comparison_fixed_script.csv`); a real-data smoke run in a scratch directory reports 35 states, 16 baseline-eligible switchers, and the NV assertion stops the run when `EXCLUDE_STATES=""`. Items 4–5 remain open:

1. Replace the max-coverage balancing filter (lines 122–126) with the framework's rule: keep every state with its own coverage. If a balanced variant is wanted for a robustness table, make it an explicit knob defaulting OFF.
2. Add an `EXCLUDE_STATES` knob (default `NV,ID,HI,MS` for the PAP spec) applied before `treat_tbl` is built, and call `assert_no_pre_paspa_controls()` on the control pool as `CLAUDE.md` requires.
3. Raise the `MAX_DATE` default, or drop the cap, so the frozen panel's tail is used. Freeze the vintage first (RUN_LEDGER boundary 7 or later).
4. Decide what the pre-trend block should do under shift12. Options: raise `PRE` to ≥ 19 so leads fall strictly before the 6-month baseline window, or rely on the separate pretrends pipeline and suppress the empty block. As is, the joint test silently reports k = 0.
5. Optional: set a seed before the pooled `boottest()` so the wild p is reproducible, and log fixest's t-df choice.

Not tested here: vwatt (script has the knob; same weights function), county level, the gap-tolerant baseline paths, and the per-horizon event study / window-era pools (same `build_h`, so they inherit parity, but only the pooled 0..12 ATT was compared).
