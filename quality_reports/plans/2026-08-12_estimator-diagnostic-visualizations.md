# Plan: Estimator-diagnostic visualizations (singleton cohorts, BJS global PT, calibration)

**Status:** APPROVED (autonomous session; user request 2026-08-12)
**Orchestration:** Fable orchestrates + judges; coder subagents (sonnet) implement.

## Goal

A figure set that *shows* (not tables) why each estimator struggles on this design:

1. **Fig 1 — Cohort structure timeline.** Panel coverage Gantt (state × month), online
   legalization dates marked, COVID window shaded. Every treated state is its own cohort
   (n = 1). Inset/companion: cohort-size distribution here vs Hollenbeck et al. (51 states,
   24 treated, multi-state cohorts).
2. **Fig 2 — What a singleton-cohort ATT(g,t) is.** Per-cohort raw event-study paths:
   each treated state's log(filings per 1k) minus never-treated mean, re-centered at g−1.
   Spaghetti of single-state paths = each colored line is an ENTIRE cohort estimate.
   Cross-cohort dispersion is single-state idiosyncratic noise — why CS/SunAb SEs are
   4–5× TWFE.
3. **Fig 3 — BJS/did2s global parallel trends.** Panel A: which observations the
   imputation-model fit uses for one late-adopting state (all pre-periods 2016→g,
   spanning the excised COVID break) vs CS's local base period g−1. Panel B: stylized
   simulation — small differential linear trend (local PT ≈ holds, global PT fails);
   BJS counterfactual extrapolates the full pre-period model and bias grows with event
   time; CS anchored at g−1 stays close. Labeled as simulation.
4. **Fig 4 — Calibration scoreboard.** Dot plots from calibration_summary.csv (state +
   county): Type I error vs 5% nominal; SE/SD vs 1.0.
5. **Fig 5 — Null distributions vs claimed SEs.** From sim_results.csv: per-estimator
   null ATT draws with ±1.96×mean(SE) band. SunAb/CS spread ≫ claimed SE (state);
   CS over-wide on county; did2s well-matched.

## Inputs (verified present)

- `data/raw/state_month_panel_with_treatment.csv` (state_abb, month_date, filings_per_1k_renters, …)
- `data/raw/sports_gambling_legalization_dates.csv` (REPAIRED 2026-08-10: ME/VT/KY/FL now treated — compute treated/never-treated from data, do NOT hardcode stale counts)
- `utils/eviction_treatment_schedule.R` (schedule loader + name→abb crosswalk)
- `data/output/cs_calibration_multi/{calibration_summary,sim_results}.csv` (state, 20 sims)
- `output/border_diagnostic/cs_calibration_multi_county/{calibration_summary,sim_results}.csv` (county, 50 sims)

## Outputs

- Scripts: `analysis/visualization/estimator_diagnostics/fig{1,2,3,4,5}_*.R`
- Figures: `figures/estimator_diagnostics/*.png` (also PDF)
- Conventions: tidyverse, `theme_set(theme_minimal())`, Okabe-Ito palette, relative
  paths, packages at top, `set.seed()` once where stochastic. Titles allowed (standalone
  diagnostic figures, not paper figures; paper versions would drop titles per INV-12).

## Dispatch

- Agent A (coder): Figs 1–2 (design-structure figures, real panel data)
- Agent B (coder): Fig 3 (BJS global-PT mechanics + simulation)
- Agent C (coder): Figs 4–5 (calibration-results figures)
- Fable: review outputs, iterate once if needed, present.
