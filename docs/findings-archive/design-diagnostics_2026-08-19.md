> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### Time Aggregation Does NOT Fix CS; the COVID Splice Is What Breaks It (2026-08-19)

Tested directly: `config/power_time_agg_covid_gates.yml` (state/S2/D1-panel/count_nb,
delta=0, 300 reps, 13 cells) using the new `time_agg` axis (month/quarter/year) in
`load_blinded_panel()`. Memo: `quality_reports/time_agg_covid_calibration_memo_2026-08-19.md`.

- **Cohorts DO collapse as hypothesised** — 21 cohorts (max 2 states) monthly -> 17 (max 3)
  quarterly -> **7 cohorts (max 6 states) annually** — **but CS size does not follow**:
  spliced-window CS analytic 18.3% (month) -> 16.7% (quarter) -> **24.7% (year)**. The
  singleton-cohort story is NOT the binding constraint.
- **The COVID splice is the dominant factor.** On the clean post-COVID monthly window CS
  PASSES the size gate for the first time in this project: 5.0% analytic / 6.0% boot /
  3.3% boot_t, SE/SD 1.06-1.14. Every spliced cell fails for CS *and* did2s (26-42%),
  generalising the 2026-08-17 did2s splice-artifact finding to CS.
- **CS null bias is large and negative on post-COVID cells** (-0.20 monthly to -0.58
  annual) even where size passes — size-valid is not unbiased; report both.
- **Annual aggregation has a partial-period artifact:** the loader filters COVID months
  BEFORE aggregating, so annual 2020 = 2 months of filings and 2021 = 5. Use
  `complete_periods_only: true` to drop incomplete unit-periods — but note that on the
  SPLICED window this makes coarse aggregation **D1-infeasible** (quarter 1/5 placements,
  year 0/5, vs 5/5 with it off).
- **LP-DiD is incompatible with coarse aggregation: 0/300 convergence** at quarterly and
  annual (its lags run on calendar months by design); 300/300 monthly. Fix before any
  quarterly LP-DiD spec.
- **Speed:** CS costs 27.7 s/cell monthly, 3.4 s quarterly, 0.2 s annually (8-140x) — a
  reusable speedup even though calibration is unchanged.

### Binary 2x2 Long Difference: Pseudo-Treatment Power Verdict (2026-08-19)

The binary long difference — `tau = (Ybar^T_end - Ybar^C_end) - (Ybar^T_pre -
Ybar^C_pre)`, one common calendar, "online by 2022" as a binary group — is
powered as a **pseudo-treatment experiment in the pre-treatment era** (Black,
Hollingsworth, Nunes & Simon 2022), NOT by truncating each state at its own
legalization date. Truncating leaves 6 usable states at the real calendar;
shifting the whole experiment before 2018-06 (first-ever legalization) keeps
every state, because nothing is treated there. Full memo:
`quality_reports/longdiff_pseudo_treatment_memo_2026-08-19.md`.

- **Substrate switch is forced.** The ETS monthly untreated era is only
  2016-01..2018-05 = **29 months**, so a 24-month baseline + 12-month endpoint
  cannot fit disjointly, let alone at the real ~70-month distance. The
  **annual county court panel** (`data/raw/county_court-issued_2000_2023_ben_update_5_12.csv`)
  does: **CY2008+2009 -> CY2016 = 37 states, 1,549 counties, 72-month distance,
  22 online-ever / 15 never** — widths, distance, and counts all preserved.
  Watch the DC case mismatch ("District Of Columbia"); a case-sensitive join
  silently drops DC and changes the split.
- **MDE-80 = 0.241 log points (+27% in filings)** under randomization
  inference, 500 reps (`output/longdiff_2x2_pseudo/`). **This is a FLOOR** —
  measured in the calm pre-2018 era.
- **RI is exactly nominal (5.0%); CRVE FAILS the size gate** (7.8% main,
  **12.4%** on the 12-month-baseline variant, SE/SD 0.88). At 37 unbalanced
  clusters do not quote CRVE. WCB is fine (5.2%). Null bias -0.0008.
- **Real-era MDE is +20% to +80%** — a RANGE, not a point: the era-inflated
  pseudo route gives +77%, the corrected direct anchor +20-24%, and the two
  disagree because the ETS inputs are coverage-unstable (see below). **The 2x2 cannot detect the 7.5-10% effects the credit literature
  reports**, and is far weaker than LP-DiD spliced-state (MDE 8.1%). Keep it as
  a transparent descriptive contrast; do not make it the powered spec.
- **Type M is severe**: a significant estimate at delta = 0.05-0.10 overstates
  the truth by **2-4x**; at delta = 0.02 under CRVE, 28% of significant
  estimates have the WRONG SIGN.
- **Selection check passes**: eventual online legalizers show no pre-treatment
  divergence from never-legalizers (tau = -1.4%, RI p = 0.90;
  `analysis/diagnostics/longdiff_2x2_selection_placebo.R`).

### Era Variance: Pre-2018 Understates Post-COVID Noise by 2-4x (2026-08-19)

`analysis/diagnostics/longdiff_era_variance.R` -> `output/longdiff_era_variance/`.
sigma = SD across states of the state-level long difference (exactly what the
clustered SE is built from), windows slid over every feasible placement at
**matched geometry and matched distance**, on states untreated in BOTH eras.

- **Median post/pre sigma ratio 2.67** (range 1.8-5.2); 3.86 on the strict
  never-any-legalization set. Any pre-era MDE must be inflated accordingly.
- **IDAHO TRAP:** with ID included the raw comparison *inverts* (pre looks
  noisier). ID is the single most extreme state in **100%** of pre-era
  placements. CLAUDE.md already excludes ID from annual analyses; exclude it
  here too. Trimmed and MAD statistics were right all along.
- **Never-treated states are ~1.5-1.6x noisier than the full state set** in the
  pre era. The real control pool IS those states, so an all-states rehearsal
  understates noise on that count as well.
- **Real-calendar anchor — CONTAMINATED, revised down.** State panel gave
  sigma = 0.472 (MDE +56%), but **two states (TX, MN) carry nearly all of it
  and BOTH disagree with the county file** (TX: state panel +0.785 vs
  county-aggregated -0.493; MN: -0.715 vs -0.024; the other five agree
  exactly). A second artifact compounds it: reporting-county composition
  changes between windows (TX 12.8 -> 8.5 counties), and fixing the basket
  flips TX to +0.36. Corrected sigma **0.19-0.23 -> MDE-80 ~ +20% to +24%**.
  Era factor survives but shrinks: **2.36x** on a fixed basket vs 3.89 from the
  state panel at the same cell. **ACTION: reconcile the TX and MN state-panel
  series against `monthly_county_data_download.csv` before reporting any long
  difference.** Script: `analysis/diagnostics/longdiff_real_calendar_decomp.R`.
- **Averaging is nearly inert (Burlig-Preonas-Woerman confirmed).** Measured
  with the endpoint window's CENTRE fixed so averaging is separated from
  distance: in the post-COVID era a 12-month endpoint average cuts sigma by
  only **5-12%** vs the 71% independence would give. The 24-month baseline
  likewise buys ~nothing over 12 months (MDE 0.241 vs 0.246). Do not spend
  design freedom on window length.

