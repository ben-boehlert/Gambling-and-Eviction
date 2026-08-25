# Adoption Predictors: what exists, what must be acquired

**Date:** 2026-08-21
**Purpose:** support the asymmetric-predictability argument — adoption is
forecastable from gambling-policy institutions, and not from the outcome's own
history — with real data for each block.

**Standing constraint:** none of the missing blocks will be hand-keyed from
model memory. State casino legalization years, lottery start dates,
constitutional gambling clauses and legislature classifications are exactly the
kind of fact that is plausible-sounding and wrong at a rate that would poison a
50-observation regression. Each must come from a retrieved source in-session.
Entries below are acquisition *targets*; coverage and definitions are to be
verified on acquisition, not assumed from this table.

---

## Implemented, with real data

| Block | Variable | Source | Timing |
|---|---|---|---|
| Political ideology | `ideo_citizen`, `ideo_govt` | Berry–Ringquist–Fording–Hanson state ideology series, `Funding/Data/stateideology_v2018.xlsx` (1960–2017) | **1991 — genuinely pre-PASPA** |
| Region | Census 4-region | base R `state.region`; DC assigned to South | time-invariant |
| Macro / housing | mortgage 90+ delinquency level and crisis peak, log adult population | `data/raw/StateMortgagesPercent-*.csv`, `data/processed/state_adult_population_monthly.csv` | 2016–17 / 2009–10 / 2018-01 |
| Eviction history | `ev_level`, `ev_slope` | annual county court panel, 2009–2015 fixed basket | pre-repeal |

Script: `analysis/diagnostics/adoption_predictability_institutions.R`.
Shared CV machinery: `utils/cv_predictability.R` — the block comparison must use
one estimator, one fold scheme and one permutation null, or differences between
blocks are confounded by the evaluation method.

---

## Not implemented — acquisition targets, in priority order

Priority is by expected predictive weight per unit of acquisition effort.

| # | Block | Candidate source | Notes / risk |
|---|---|---|---|
| 1 | **Commercial casino structure** | American Gaming Association *State of the States*; Rockefeller Institute state gambling reports; state gaming commission enabling statutes | The single most likely strong predictor. Want *year of first commercial casino authorization* (pre-PASPA where it exists) plus a riverboat/racino/limited-stakes type code, not a binary |
| 2 | **Tribal gaming** | National Indian Gaming Commission gaming-operation lists; IGRA Class III compact records (BIA) | Distinct mechanism from commercial: tribal exclusivity compacts can *block* commercial expansion. Code compact existence and revenue-share exclusivity separately |
| 3 | **Constitutional / referendum barrier** | State constitution gambling clauses; NCSL ballot-measure database | Highest coding-judgement risk of any block. Needs a documented rubric (constitutional prohibition vs statutory silence vs mandatory referendum) and ideally two independent codings |
| 4 | **Lottery infrastructure** | NASPL; Census *State Government Finances* lottery revenue series | Lottery adoption year is a clean pre-PASPA diffusion variable and the Census series gives a continuous fiscal measure rather than a date |
| 5 | **Fiscal dependence on gaming** | Census *State Government Tax Collections* (amusements / pari-mutuel / lottery categories) | Take pre-PASPA share of own-source revenue. Continuous, comparable, and available far back — likely the best-measured block after ideology |
| 6 | **Legislature professionalism** | Squire index; NCSL full-time/part-time and session-length classification | Session structure plausibly drives *timing within a year*; expected to be the weakest block for the ever/never margin |

---

## The neighbour-legalization model is a different specification

Neighbouring-state legalization is **time-varying and endogenous** — a state's
neighbours legalize partly in response to the same regional pressure. It cannot
enter the cross-sectional models above without contaminating them.

Correct form: a **discrete-time hazard** (state × month, complement-log-log or
logit) with the fixed institutional block as time-invariant covariates and
`share of bordering states already live` as a time-varying covariate, states
exiting the risk set on adoption. `data/processed/county_adjacency_edges.csv`
already supports building the state adjacency matrix.

Two cautions. First, this is a diffusion model, not an identification test: a
strong neighbour effect makes timing *more* predictable but says nothing about
eviction. Second, if neighbour effects are strong, treatment timing is spatially
correlated, which matters for the DiD's clustering, not just for its selection
story.

---

## Degrees of freedom

There are **30 adopters among 50 states**. Eight blocks entered as individual
covariates would be 15–25 parameters — hopeless, and the observed in-sample /
cross-validated gap in the existing runs (in-sample AUC 0.78 against CV 0.64)
already shows what over-parameterisation costs here.

Enter each block as a small index or a 1–2 variable summary, compare blocks
rather than stacking them, and keep the permutation null. If a full model is
wanted, use penalized Cox (ridge) with the penalty chosen inside the CV folds,
never on the full sample.
