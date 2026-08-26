> **PARTIALLY SUPERSEDED 2026-08-26.** The finding that placement is non-exchangeable stands, but the
> attribution to `.assign_cohorts()`'s scarcest-first ORDERING does not: randomizing the fill order moves the
> date/trend correlation by 0.006 (−0.196 → −0.190). The cause is the ELIGIBILITY STRUCTURE (common support is
> 7 states against 21 slots; strict exchangeable sampling fails 300/300). Consequently the memo's recommended
> fix — repair the placement rather than recenter — is withdrawn. See
> `quality_reports/placement_exchangeability_test_2026-08-26.md`.

# Null-bias decomposition: why the state-level D1 arms show +0.042 (vwatt) / +0.013 (ewatt) / +0.021–0.025 (twfe) at δ=0

**Date:** 2026-08-25
**Scope:** `lpdid_shift12_gate_vwatt` / `lpdid_shift12_gate_ewatt`, spliced-window scenario, state/S2/covid-drop/shift12/D1/panel-template, NV excluded, 2,000 reps each.
**Scripts:** [`analysis/diagnostics/nullbias_verify_reconstruction.R`](../analysis/diagnostics/nullbias_verify_reconstruction.R), [`analysis/diagnostics/nullbias_decomposition.R`](../analysis/diagnostics/nullbias_decomposition.R), [`analysis/diagnostics/nullbias_decomposition_analysis.R`](../analysis/diagnostics/nullbias_decomposition_analysis.R)
**Data:** [`output/nullbias_decomposition/`](../output/nullbias_decomposition/) (`verification_log.csv`, `rep_features_{vwatt,ewatt,combined}.csv`, `regression_summary.csv`, `regression_full_coefficients.csv`, `conditional_mean_contrasts.csv`, `decile_table_cor_date_trend.csv`)

---

## 1. Verification gate — PASSED

Reconstructed the exact D1 pseudo-schedule and δ=0 estimate for 5 reps (1, 2, 3, 500, 1999) of each arm, calling the framework's own `make_pseudo_schedule()` → `impose_effect()` → `run_estimator()` path with the `seed_rep` **recorded in the run's own partial CSV**. All 20 checks (5 reps × {twfe, lpdid} × {vwatt, ewatt}) matched the recorded `att` to **max |diff| = 2.8×10⁻¹⁷** (`output/nullbias_decomposition/verification_log.csv`).

One real discrepancy surfaced and was resolved before the gate passed: the `ewatt` partial (git rev `7aba318`, run 2026-08-24 15:55) was fit under `lpdid_anchor = "event"`, but the code's default has since moved to `"event_clean"` (git rev `df08995`, the later `vwatt` run). Reconstructing `ewatt` with today's default silently produced a *different* scenario id and a different LP-DiD fit. Fixed by pinning `lpdid_anchor = "event"` for the `ewatt` reconstruction, read directly from that run's own `run_metadata.json` rather than assumed from today's code. **Lesson for any future reconstruction off these partials: read the run's `run_metadata.json`, don't trust the current YAML/code defaults — this framework's un-hashed defaults have moved between the two runs being compared here.**

Given the exact match, the decomposition below is built on reconstructed schedules, not re-estimated data — every rep's `att` is the value already recorded in the partial CSV; only the pseudo-schedule (and features derived from it) is reconstructed.

## 2. Channel (a) — composition-break artifacts: **ruled out, not present in this data**

The task's channel (a) points at `data/processed/state_panel_coverage_qa.csv` and the FL/TX/TN/ID composition-churn narrative in `CLAUDE.md`. Checked directly:

- `state_panel_coverage_qa.csv` flags **zero states** with `composition_risk != "ok"` (25 states listed, all "ok", `min_basket_share = 1` for every one).
- The actual state panel the framework reads (`data/raw/state_month_panel_with_treatment.csv`, loaded via `load_blinded_panel()`) shows `basket_share == 1` for **all 4,641 rows, no exceptions** — not just for FL/TX/TN/ID. FL/TX/TN/ID specifically carry `panel_source = "county_download_fixed_basket"` with a **constant** `n_counties` (6 / 8 / 3 / 1 respectively) across every month in the panel.

**The composition churn CLAUDE.md describes at length was a property of an earlier, pre-rebuild panel. The panel this framework currently loads is already fixed-basket for every state.** There is no break left for pseudo-treatment placement to land on, so channel (a) cannot be contributing to the +0.042 bias in the *current* data, independent of where FL/TX/TN/ID happen to fall in the D1 draw.

That said, FL/TX/TN/ID are *not* irrelevant to the story: they are **pseudo-treated in every single one of 4,000 draws except at most one of the four being control** (`n_churn_states_treated` never drops below 3 of 4, mean 3.68/3.67; base rate under uniform assignment would be 4 × 21/32 ≈ 2.6). That over-representation is itself a symptom of channel (b) below (these four happen to be long-coverage, highly eligible states) — it just doesn't translate into bias here because the panel no longer has a break for it to exploit.

## 3. A structural fact about D1 that shapes everything else: calendar timing barely varies

Two candidate features — `sd_month_idx` (spread of pseudo-adoption dates across the 21 treated states) and `share_treated_after2023` — are **numerically constant across all 2,000 reps in each arm** (SD = 0 to machine precision; `share_treated_after2023` = 1/21 = 0.0476, every single rep). `com_month_idx` (the calendar center-of-mass of the pseudo-adoption dates) has SD = 0.81 months across 2,000 reps — it moves by at most ~2 months total.

Mechanism: `make_pseudo_schedule()`'s D1 path places the **fixed** real-cohort offsets at a randomly chosen anchor within `[0, slack]` (`R/power/make_pseudo_schedules.R:206-213`), then assigns states to the resulting fixed dates. On this panel window the anchor has almost no slack — so nearly every draw places the cohort *dates* in the same place. **Virtually all of the cross-rep randomness in D1 here is which states land in the (almost fixed) cohort slots, not when the cohorts occur.** This single fact is why the decomposition below points so decisively at channel (b) over (c): a generic timing-driven convex-trend effect (channel c) needs timing to vary to explain rep-to-rep bias variation, and it essentially doesn't.

## 4. Channel (b) — eligibility-constrained, non-exchangeable placement: **the dominant driver**

Built `cor_date_trend` = per-rep Pearson correlation, across the 21 pseudo-treated states, between each state's pseudo-adoption month index and that state's own real-panel trend slope (`lm(y_log1p ~ t)` fit once per state on the full covid-drop panel — a pure descriptive feature of the real data, not of any imposed effect). Also built `cor_date_coverage` (correlation between pseudo-adoption month and the state's own panel coverage length).

**`cor_date_trend` is negative in every one of 4,000 draws** (vwatt range −0.453 to +0.066, mean −0.190; ewatt range −0.463 to +0.075, mean −0.197). Under a truly exchangeable (uniform-random) state-to-cohort assignment this correlation would center on zero and vary in sign draw to draw. It never does. This is the fingerprint of `.assign_cohorts()`'s "fill the scarcest-eligible cohort first" rule (`R/power/make_pseudo_schedules.R:92-119`): cohorts near the panel's calendar edges have few eligible states (only long-coverage states satisfy `min_pre`/`min_post` there), so those edge dates are structurally forced onto a non-random subset of states — and that subset's trend slopes are not a random draw from all 21 treated states' slopes. This is placement failing to be exchangeable, exactly as channel (b) describes — a structural property of the assignment algorithm on this panel, not sampling noise.

### Regression results (`output/nullbias_decomposition/regression_summary.csv`, `..._full_coefficients.csv`)

Five features regressed on each target (`com_month_idx`, `cor_date_trend`, `cor_date_coverage`, `frac_postmonths_after2023`, `n_churn_states_treated`; `sd_month_idx`/`share_treated_after2023` dropped, zero variance):

| target | n | mean att | full-model R² | cor_date_trend r² (univariate) | cor_date_coverage r² | com_month_idx r² | n_churn_treated r² |
|---|---|---|---|---|---|---|---|
| vwatt: lpdid | 2000 | +0.0419 | **0.152** | 0.134 (β=−0.158, p<1e-63) | 0.0004 (ns) | 0.0035 | 0.0012 (ns) |
| vwatt: twfe | 2000 | +0.0207 | **0.619** | 0.557 (β=−0.438, p≈0) | 0.261 (β=+0.419, p<1e-132) | 0.0165 | 0.0001 (ns) |
| ewatt: lpdid | 2000 | +0.0132 | **0.061** | 0.059 (β=−0.125, p<1e-27) | 0.0032 | 0.0020 | 0.0017 |
| ewatt: twfe | 2000 | +0.0245 | **0.642** | 0.592 (β=−0.426, p≈0) | 0.244 (β=+0.397, p<1e-122) | 0.0281 | 0.0009 (ns) |

(`com_month_idx` and `frac_postmonths_after2023` have **identical** r² to 4 significant figures within every target — confirming §3: they are two functions of the same single "anchor position" degree of freedom, not independent channels.)

**TWFE's null bias is overwhelmingly explained by placement (b): 62–64% of rep-to-rep variance from `cor_date_trend` + `cor_date_coverage` alone.** LP-DiD is much less sensitive to the same mechanism (6–15% R²) but the direction and significance are identical, and the residual (85–94% unexplained for LP-DiD) is plausibly finer-grained identity heterogeneity within the same channel-(b) family (nonlinear trends, level differences) that a single linear correlation summary can't fully capture — not evidence for a separate mechanism. `n_churn_states_treated` (channel a, retained here as a direct test even though §2 shows no break exists to bias) is never robustly significant and, where marginally significant (twfe, p≈0.02–0.03), the coefficient (~0.003–0.004 log points per extra churn state treated) is two orders of magnitude too small to matter against the 0.021–0.042 average bias.

### Decile evidence (`decile_table_cor_date_trend.csv`) — the cleanest single result

Splitting reps into deciles of `cor_date_trend` (most-negative → least-negative) and reading off mean att:

| | decile 1 (most eligibility-skewed, mean cor ≈ −0.35) | decile 10 (least skewed, mean cor ≈ −0.03) | swing |
|---|---|---|---|
| vwatt lpdid | +0.066 | +0.007 | 0.059 (> the 0.042 average bias) |
| vwatt twfe | +0.074 | **−0.055** | 0.129 (~6× the 0.021 average bias; sign flips) |
| ewatt lpdid | +0.035 | **−0.009** | 0.044 (> the 0.013 average bias; sign flips) |
| ewatt twfe | +0.083 | **−0.052** | 0.135 (~5.5× the 0.025 average bias; sign flips) |

For three of the four targets the bias **changes sign** across the observed range of eligibility skew, and in all four the swing exceeds the arm's average bias. This is a self-contained result that does not require assuming any particular "unbiased baseline" value for `cor_date_trend`: draws that happen to be closer to exchangeable are close to unbiased (or even biased the other way for TWFE); draws where the eligibility constraint bites hardest carry most of the average +0.042/+0.021 figures quoted in the task.

## 5. Channel (c) — generic convex-trend × staggered-window effect: **cannot be the driver of rep-to-rep variation; cannot be fully excluded from a fixed baseline level**

The only feature that is a pure function of calendar timing regardless of *which* states are involved — `com_month_idx` (equivalently `frac_postmonths_after2023`) — explains at most 2.8% of variance (twfe) and as little as 0.2% (lpdid ewatt). Since §3 established that this timing dimension barely moves across reps to begin with, a channel-(c) mechanism could in principle still contribute a **constant, rep-invariant** level of bias that this regression cannot separate from the intercept (a fixed offset present in every rep is, by construction, invisible to a variance-explained decomposition). We cannot rule that residual possibility out with this data — doing so would require simulating a genuinely exchangeable placement (e.g., a D3/D4-style ablation) as a counterfactual, which was out of scope here. What the data does support is the narrower claim actually needed: **whatever channel (c) contributes, it is not what makes the bias vary rep to rep, or what makes some reps show ~2× the average bias and others show none or the reverse sign** — that variation tracks `cor_date_trend`/`cor_date_coverage` (channel b) closely and `com_month_idx` almost not at all.

## 6. Answer to the headline question, with magnitudes

**Primarily (b): eligibility-constrained, non-exchangeable D1 placement.** Composition-break artifacts (a) are not present in the current panel (§2) and contribute effectively zero. A generic convex-trend timing effect (c) cannot explain the *variation* in bias across reps (§5) because the one feature that would carry it barely varies. The feature that does carry the variation — the correlation between a treated state's pseudo-adoption date and its own real trend slope, which is *always negative* because `.assign_cohorts()`'s scarcest-cohort-first rule forces edge-of-panel cohort dates onto a non-random, long-coverage subset of states — explains 62–64% of TWFE's rep-to-rep bias variance and 6–15% of LP-DiD's, and moves both estimators' bias by more than the full reported average (§4 decile table), flipping the sign in 3 of 4 targets across the observed range.

## 7. What a fix looks like

- **Channel (a):** no action needed on the current panel (already fixed-basket); worth a one-line note that the composition-churn caveats elsewhere in `CLAUDE.md` referring to FL/TX/TN/ID no longer apply to `state_month_panel_with_treatment.csv` as currently built.
- **Channel (b), the real driver:** `.assign_cohorts()`'s eligibility rule is doing exactly what it's supposed to (feasibility), so the fix is not to change the placement algorithm but to **stop assuming δ=0 draws are unbiased when computing size/power**. Two options, not mutually exclusive:
  1. **Bias-correct the size gate and MDE**: recenter the δ=0 null distribution on its own empirical mean (+0.042 vwatt-lpdid, +0.021 twfe, etc.) before computing rejection rates, rather than testing against 0 — this is a direct, mechanical fix to the size-gate numbers already reported for this arm.
  2. **Report the bias as a function of realized eligibility skew** — e.g., stratify the size gate by `cor_date_trend` decile/tercile and flag that draws in the most eligibility-constrained stratum are the least trustworthy, rather than pooling all reps into one size figure.
- **What NOT to do:** don't reach for the churn-state censoring rule suggested in the task prompt (`state_panel_coverage_qa.csv` grades) — §2 shows there's nothing there to censor on the current panel; doing so would add a no-op filter while leaving the actual (eligibility) mechanism untouched.

## 8. What remains unexplained (say this honestly)

- **85–94% of LP-DiD's rep-to-rep bias variance is not explained by these 5 features.** LP-DiD's cell structure is far less sensitive to `cor_date_trend`/`cor_date_coverage` than TWFE's pooled estimator is, but the residual is large. Plausible unmodeled pieces: nonlinear (not just linear-slope) state trend heterogeneity, level differences between treated and control pools, and the specific *identity* of which states end up in which cohort beyond what a single correlation number captures. All of these are still within the channel-(b) family (state-identity-driven non-exchangeability) — nothing in the residual points toward channel (a) or (c) reasserting itself.
- **The level-vs-variance separation between (b) and (c) is not fully resolved** (§5) — a true counterfactual exchangeable-placement run (not attempted here) would be needed to cleanly assign the *baseline* bias level, as opposed to its *variation*, between the two channels.
- The `vwatt` and `ewatt` runs are **not rep-paired** (different `lpdid_weights` values are hashed into the scenario id, so `seed_rep` differs between the two arms even for the same `rep` number) — treated here as two independent 2,000-draw samples, which is why the two arms' qualitative agreement (same sign, same feature ranking, similar decile swings) is itself corroborating evidence rather than a guaranteed-identical replication.
