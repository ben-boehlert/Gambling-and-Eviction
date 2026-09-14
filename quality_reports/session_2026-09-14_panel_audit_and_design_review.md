# Session memo — 2026-09-14: panel currency audit, single-series rebuild, and design review

**Scope.** Started as "how much is left to gain from adding states?" and became a full audit of the
state panel's currency and provenance, a rebuild of six states, and a review of the clean-anchor
design's COVID handling. Several conclusions reached mid-session were later overturned by further
testing; §4 records those explicitly, because the wrong readings were acted on (configs patched)
before being corrected.

Vintage boundary established: **2026-09-14**. Every pre-existing gate / MDE / pretrends run is on
the superseded vintage.

---

## 1. Data changes

| Change | Detail |
|---|---|
| **Single-series rebuild** | LA MA MO NM NV RI rebuilt from `ets_county_month.csv` (Eviction Lab internal extract, supplied 2026-09-03). RI **+77 months**, MO/NM +41, MA +31, LA +7, NV +6. `data_prep/rebuild_single_series_from_ets_internal.R` |
| **ACS denominators** | 574 rows filled, B25003_003 county-level, ACS 2015–2024 with nearest-year fallback recorded per row. `data_prep/fetch_acs_renter_denominators.R` |
| **Series-start ramp censor** | CT 2016-01/02 and NH 2018-12 removed as incomplete-at-ingest. `data_prep/censor_series_start_ramps.R` |
| **Oregon added** | New state, never previously in the panel. OJD "Cases Filed" PDFs 2018-01..2019-12 + Evicted in Oregon dashboard 2020-01..2026-07. Seam measured on 12 overlapping months: **0.9905 (−0.0095 log pts)**, left unadjusted and disclosed. `data_prep/add_oregon_to_state_panel.R` |
| Net | Panel 3,904 → **4,174 rows**, 39 → **40 states**, one source per state, no dups, no NA filings |
| Prior vintages | Preserved in `data/raw/deprecated/`, recorded in MOVES.md |

**Switcher set: 13 → 16**, full-window **6 → 7**. RI joins (2/13), **MA becomes full-window**, OR joins (3/13).

---

## 2. Bugs found and fixed

1. **`rebuild_state_month_panel.R` was a latent revert-bomb.** It read KEEP_OLD rows from the
   2026-08-20 archive, so re-running it would have silently reverted MD's 2026-09-03 extension
   (2026-06 → 2025-11) and, after this session, RI. Fixed to read the current panel; archive is now
   the cold-build fallback only. Latent since 2026-09-03.
2. **`make_della_power_upload.sh` copies a hardcoded config list** and would have shipped a package
   missing every new run. Fixed.
3. **`DATA_PROVENANCE.md` was untracked in git** despite CLAUDE.md naming it the authority on data
   sources. Now committed.
4. **DATA_PROVENANCE §1 was wrong about the LSC file.** It claims a pristine LSC download. The live
   download is a **strict subset** of the local file (120,357 vs 124,325 rows) — NC (3,600 rows) and
   ME (368) come from court-source substitutes merged in; NC's match `nc_sume_county_month.csv`
   (NC AOC Summary Ejectment) at **100%**. Corrected. **Re-downloading would delete NC 2023-07..2026-06
   and demote a full-window switcher.**

---

## 3. Findings

### 3.1 Design capacity
- **Adding states is NOT as exhausted as this session first concluded — see correction #11.** The
  opening claim ("only WY has clean online timing; the rest are COVID-destroyed") was inverted. The
  binding constraint is the **6-month pre-launch baseline**, not the outcome window, and on that test:

  | State | Baseline survives | Outcome surviving | Verdict |
  |---|---|---|---|
  | **NJ** 2018-08 | **6/6** | **7/13** | **viable — equivalent to WV, a current switcher** |
  | **OR** 2019-10 | 6/6 | 3/13 | **ADDED this session** |
  | IA 2019-08 | 6/6 | 1/13 | viable but marginal |
  | DC 2020-05 | 4/6 | 10/13 | no baseline |
  | IL 2020-06 | 3/6 | 11/13 | no baseline |
  | **WY** 2021-09 | **1/6** | 13/13 | **NOT viable** — the opposite of the original claim |
  | MI 2021-01 | 0/6 | 13/13 | no baseline |
  | SD, WA | — | — | retail-only, not online switchers |

  Untapped controls remain AL, CA, NE only. **NJ is now the highest-value missing state.** Its monthly
  Tenancy-by-vicinage counts are recoverable from the NJ Courts `cman` PDFs by differencing YTD
  "Added" values (`data/raw/monthly_expansion/nj_raw/STEP1_FINDING.md`), but only **32 of 252 PDFs are
  on disk** — a real project, not a quick add.
- **County spillover design is cluster-infeasible.** 2 (strict) to 11 (permissive) usable state
  clusters vs 12 direct; 121 of 134 permissive counties in VA/OK/SC/KY. No MDE run warranted.
- **Annual data**: the current spec fails outright on annual spacing (`no identified (t, h) cells`).
  Gap-tolerant mode is the right lever but untested. Annual buys 23/28 clusters against 15/13, and
  `longdiff_2x2_pseudo` puts its MDE at 0.240 vs 0.127. Pursue as the pre-registered robustness
  check, not as a headline substitute.

### 3.2 Coverage and representativeness
- ACS renter coverage of the rebuilt baskets: **RI 92.5%, NM 87.9%, NV 75.6%, MO 45.5%, MA 19.8%,
  LA 13.2%**. `basket_share` counts counties and badly misrepresents NM (0.48 → 87.9% of renters).
- **MA is a full-window switcher covering 19.8% of Massachusetts renters** — it is Suffolk County /
  Boston. Label it accordingly in any results table.
- **MO covers 45.5% of its state's renters and its source never reports St. Louis County (29189) or
  Jackson County / Kansas City (29095)** — together 43.5% of MO's statewide filings, 29.3% of renters.
  Those counties exist locally only in the annual court panel (2003–2017, fiscal year) and in the
  Missouri Judiciary supplements (now published through 2023) — annual, so unusable here.
- **MO is control-eligible in 134 of 143 live cells (94%)**, up from 10 pre-rebuild, carrying ~8.4%
  of control mass (ME 14.2%, NC 16.7%). A non-representative Missouri now enters nearly every
  comparison. `_noMO` config variants created.

### 3.3 The COVID window — three routes tried, all closed
| Route | Result |
|---|---|
| Gap-tolerant baselines | Already tested and rejected (`..._gaptol`): SD 0.129 vs 0.108, δ=0 mean +0.081 |
| Shorter COVID window | **Worse**: SD(drift) 0.46 vs 0.173 current — admitting moratorium months into BASELINES is the damage |
| Pre-COVID straddle baselines | Rescues ~4 states (2 cleanly) at **101.5% of the MDE** in pooled contamination |

All three fail on one fact: **states recovered from COVID at wildly different rates, and any
comparison spanning the gap inherits that heterogeneity.** The 2021-07 boundary is right, for a
reason rarely stated — its job is keeping suppressed months **out of baselines**, not separating
clean months from dirty ones.

- **Do the resets cancel treated vs control?** The **mean** does (−0.083, SE 0.067, t = −1.24). The
  **variance** does not: cross-state SD 0.204 = 1.6× MDE, averaging to **41% of MDE** at 15 clusters.
  Treated states are twice as heterogeneous as never-treated (SD 0.228 vs 0.114).
- **Moratorium enforcement is unrelated to adoption timing** — four independent nulls (Tests A/B/C
  plus this session's `plateau_onset` test, re-run post-censor: p = 0.697, cor +0.138 p = 0.625).
- **⚠ But Callaway & Li (JoE 2023, lit-review T3) show pre-trend tests are underpowered EXACTLY under
  this contamination.** Every null above is weak evidence of cleanliness, not strong.

### 3.4 Market maturity (open, PAP-relevant)
Handle-calibrated curve (median **30 months to 80% of peak**, tau 18.6): month 12 = **50% of peak**,
18 = 64%, 24 = 74%. **The 12–24 outcome window tests a half-to-three-quarters-ramped effect**, so the
MDE in mature-market terms is larger than 12.7%. Worth stating explicitly rather than leaving implicit.

### 3.5 Simulation machinery
- **Eligibility window does not match the estimator.** `min_pre` is a SPAN check; the strict PMD=6
  baseline is a PRESENCE requirement. **251 of 748 admitted state-slots (34%) have no usable baseline
  and contribute nothing**, so `n_treated_clusters = 22` overstates the contributing count. No
  (min_pre, min_post) setting fixes this.
- **Root cause is the template: 8 of 24 D1 cohort slots have ZERO eligible states** because their
  baselines fall inside the COVID drop — a calendar property, not a coverage one. D1 asks the
  simulator to reproduce a 31-state / 24-cohort structure the real data cannot support.
- **D1 is feasible ONLY at (12,6)**; all 8 other grid cells fail 0/25, and `random_order` (≈4,000
  attempted arrangements) does not rescue (18,12). D4 places 15/15 but at 7 treated / 25 control.

### 3.6 Data quality
- **Series-start ramps**: CT 2016-01/02 (0.15/0.19 of norm), NH 2018-12 (0.20). Censored. Pre-COVID
  log SD **CT 0.376 → 0.133, NH 0.482 → 0.138**, both now at Ohio's clean 0.114. WI 2019-01 (0.56)
  assessed and left. Switcher set unchanged.
- **Retail-legal states sit in the never-treated control pool** — MT, ND, NM, WI. Defensible if the
  estimand is online-specific, but undisclosed.
- **5 LSC-stale states**: HI/ID/MS are excluded from every spec (staleness costs nothing); KS is a
  switcher whose own window is already 13/13; CO is control-only in 5% of cells. All five have
  identified sources, **all annual**. Low priority.

---

## 4. Corrections log — conclusions reached and then overturned

| # | What I concluded | What corrected it |
|---|---|---|
| 1 | "No network access" — handed the ACS pull and LSC refresh to Ben as homework | zsh glob-expanded the `?` in an unquoted URL. Network works; ran both myself |
| 2 | Overlapping sites (NEWORLEANS FCC/SCC, 3× LASVEGAS) risk a double count | They are complementary courts, never equal in any shared month. Summing is correct |
| 3 | MO and NM have "worse composition than anything in the panel" | True for MO (45.5% of renters). **False for NM** — 87.9% of renters, all metros. `basket_share` counts counties |
| 4 | `min_post = 6` is "6 months short" | **Wrong.** States contribute at whatever horizons they have; min_post=6 guarantees 7 of 13. Ben's correction |
| 5 | Fix is `min_pre: 18, min_post: 12`; patched 8 configs | Makes D1 infeasible, and for the wrong reason — the real issue is span-vs-presence and the impossible cohorts. **Configs still carry (18,12) and will not run under D1** |
| 6 | "The correction breaks the design" | Overstated. It breaks the SIMULATOR's ability to model the design; real-data estimates are untouched |
| 7 | Gap-tolerant baselines look like they dominate (22 switchers, COVID drop intact) | Already tested and rejected 2026-08-28. The rescue and the bias are the same mechanism |
| 8 | ~2020-09 is a defensible COVID boundary; "largest available improvement" | **Wrong measure.** Used month-level cross-state SD instead of baseline→outcome drift. Correct measure: shortening is 2.6× worse |
| 9 | Pull the LSC refresh first to avoid a second vintage boundary | The live download is a strict subset; refreshing is destructive |
| 10 | Used `stabilization_by_state.csv` without checking its vintage | It predated the ramp censor (CT `pre_sigma` 0.315 → 0.067). Regenerated; conclusion held |

| 11 | "Of 9 missing legalizers only **WY** has clean online timing; NJ/IA/OR are COVID-destroyed" — the session's opening finding | **Inverted.** WY's baseline is 1/6 (not viable); NJ 6/6+7/13, OR 6/6+3/13 and IA 6/6+1/13 ARE viable. Surfaced only when Ben asked to add Oregon, which then entered as a switcher. I had judged the missing states on outcome-window survival without checking the baseline — the very constraint this session later established as binding |

**Process note.** #11 is the costliest: it sat in the session's headline answer for the entire session. #4–#6 came from running feasibility probes before correctly deriving what the
estimator needs. #8 and #10 came from using a convenient measure / artifact without validating it
against the object of interest. Both are avoidable by deriving first and checking vintage first.

---

### 3.7 Comparison literature and the `_post2020` arm (added late in session)
Read from `Literature/`: **Hollenbeck** (2016-03..2023-06, credit bureau) keeps COVID and runs an OxCGRT
balance test — the same design as this session's moratorium test, same null. **Baker et al.**
(2018-08..2023-09, transaction data) keeps COVID with no test. **Goss & Mangrum** zero the omega weights
for pre-2020:Q1 cohorts and 2020:Q2, on TREATMENT-environment grounds. **None drops COVID months from the
outcome** — and all three use outcomes that were never administratively suppressed, unlike court filings.
That asymmetry is a positioning argument for the PAP, not just a caveat.

**Discard comparison:** G&M drop **8 of 31** online legalizers (26%); this design drops **15 of 31** (48%)
— 7 COVID-baseline, 6 missing data, 2 calendar edges. This design KEEPS 5 of the 8 G&M exclude
(WV RI IN OR NH), worth **14% of identifying variation and zero full-window switchers**.
`_post2020` config variants created accordingly; D1 stays feasible (20/20 at 28 states).

## 5. Open decisions (none resolved this session)

1. **Configs are patched to (18,12) and will not run under D1.** Revert to (12,6), or change the
   design (D4 / shrink the template / relax the estimator). **Blocks the Della run.**
2. **MO in or out of the control pool.** `_noMO` variants ready.
3. **MA labelling** — it is Boston, not Massachusetts.
4. **Recentering** — its premise (that the null bias is a placebo artifact) is unsupported; report
   raw and recentered, or pre-register one.
5. **Maturity attenuation** — disclose in the PAP.
6. **Retail-legal controls** — disclose.
7. **`ets_county_month.csv` is untracked** (1.7MB) and three rebuilt states depend on it.

---

## 6. Recommended next actions

1. Resolve decision 1, then launch the Della run (`run_clean_v20260914.slurm`, or the interactive
   `salloc` form — both prepared).
2. Re-run the gate and MDE **before** re-opening the pmd question: the rebuild's +2 switchers are the
   same gain pmd=3 would have bought, without its baseline-noise penalty.
3. Reconcile FINDINGS §2's 12-switcher list against `run_metadata.json` when the Della rsync lands
   (this session's rule yields 15; FL, AR/KY labels differ).
4. **Pursue NJ** — the highest-value missing state (6/6 baseline, 7/13 outcome, equivalent to WV).
   Path: parse the NJ Courts `cman` PDFs, differencing YTD "Added" values per vicinage; 220 of 252
   monthly PDFs still need downloading.
5. Consider a vintage stamp in each `output/` directory — §4 #10 was silent staleness in a derived
   artifact, and nothing currently tracks that.
