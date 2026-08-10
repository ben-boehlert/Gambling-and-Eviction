# Literature Review & Estimation Strategy Reassessment — July 2026

**Date:** 2026-07-23
**Trigger:** 11 papers added to `Literature/`; full review against the current estimation strategy (did2s headline on pre-COVID cohorts excl. NH = +9.1%, CI [−0.1%, +17.5%]; TWFE robustness; CS/SunAb shelved after calibration failure; COVID window dropped; never-treated states as controls).

**Papers reviewed:** Baker/Callaway/Cunningham/Goodman-Bacon/Sant'Anna practitioner's guide (2025); Abadie/Angrist/Frandsen/Pischke "Harvesting DiD" (NBER 34550); Athey/Imbens/Qu/Viviano TROP (2025); Callaway & Li (JoE 2023); Hollenbeck/Larsen/Proserpio (Feb 2026 version vs. Apr 2025); Goss & Mangrum (NY Fed SR 1184); McCarthy/Taylor/Wilbur (2026); Guo/Peng/Meyerhoefer (NBER 35305); Baker et al. "Gambling Away Stability" (NBER 33108); Walker & Evans (2025); Arnesen & Matsuzawa (2024).

---

## Verdict: the core architecture survives, and is now much better defended

1. **did2s headline has direct published precedent on the same treatment variation.** Guo/Peng/Meyerhoefer (NBER 35305, June 2026) study sports-betting legalization → food sufficiency with 9 treated / 15 never-treated states (singleton cohorts) and use **Gardner (2022) did2s as their headline estimator**, with BJS as point-estimate robustness, TWFE comparison, MacKinnon–Webb wild cluster bootstrap, and randomization inference (200 placebo date assignments). They explicitly reject Stata CSDID citing **Deb, Norton, Wooldridge & Zabel (NBER 34331, 2025)**: CSDID's aggregation partially weights by last-pre-period observations and "can induce bias in the overall ATT except in perfectly balanced panels." They also note BJS's conservative inference *requires ≥2 treated states per period* — broken by singleton cohorts — which is a citable articulation of our own didimputation failures.

2. **Our calibration-based estimator selection is exactly the Athey/Imbens/Qu/Viviano "preferred strategy."** TROP's abstract: researchers should "use simulations closely matched to the data they are interested in… to investigate which estimators work well in their particular setting." Our `cs_calibration_multi_estimator*.R` pipeline is this. Cite them as methodological validation.

3. **The CS/Sun-Abraham miscalibration now has a published mechanism.** AAFP (NBER 34550, pp. 30–42): with few states contributing to long-horizon cells, high leverage → residual variance shortfall → clustered SEs biased downward; even 48 clusters are badly biased at long leads/lags. Our 11 singleton cohorts are the extreme case. Cite this as the *theoretical explanation* for our Monte Carlo results, plus Deb et al. (2025) as an independent implementation critique. Also: none of the three applied peer papers uses CS as headline anymore (GSC, did2s, TWFE+BJS respectively) — revealed practice has moved.

4. **Both methodological camps, from opposite directions, endorse our ordering.** Baker et al. guide: imputation-family estimator as headline, TWFE only as check ("we do not recommend using [TWFE]"). AAFP: TWFE ≈ BJS agreement in their divorce demo means "heterogeneity need not be fatal" — the same TWFE ≈ did2s agreement pattern we find at county level, which we can present as evidence heterogeneity bias is small in our design.

---

## New threats (in order of importance)

### T1. Control-group contamination via border spillovers (Goss & Mangrum) — biggest substantive threat
Mobile geolocation checks *location*, not residency: residents of non-legal states register across the border and keep betting. Missouri (never-treated at the time) had ~$348M/yr of cross-border sportsbook spend. Quantified spillovers (ETWFE + Fiorini et al. spillover extension, county-quarter): betting spend spillover ≈14% of direct effect; **overall delinquency spillover ≈58% of direct**; under-40 delinquency spillover *exceeds* direct. Decay to ~zero by 60 miles.

**Implication:** our 13 never-treated control states are partially treated → **the +9.1% did2s estimate is attenuated toward zero; it is a lower bound.** This flips part of our framing: not just "we can't rule out small effects," but "the true effect plausibly exceeds the point estimate."

**Action:** replicate their distance design on our county panel — population-weighted distance from county to nearest legal-state border; robustness spec using only >60-mile counties in control states as clean controls; optionally a spillover-indicator spec (15-mile threshold). Their thresholds are directly portable.

### T2. Retail-betting contamination inside "never-treated" states (Hollenbeck's revision motivates this)
Hollenbeck et al. abandoned their "Online Access" treatment because mixed control baselines (some retail, some nothing) were uninterpretable; their Feb 2026 version uses retail-to-online transitions vs. retail-only controls. **Audit our 13 never-treated states for retail-only sports betting (e.g., MT, MS, WA-style on-premises online)** and either exclude, flag, or run a robustness spec. Same logic as T1: partial treatment of controls attenuates.

### T3. Post-COVID backlog contamination (Callaway & Li logic)
Their formal point: DiD fails when units differ in the *state of a nonlinear path-dependent process* (their case: SIRD dynamics). Direct analogue: state-specific eviction-moratorium **backlogs unwinding at different rates** (moratorium length, diversion programs, court capacity). Dropping 2020-03–2022-03 removes the acute window but does not guarantee post-window periods are clean — especially for cohorts treated near reopening. This is a plausible mechanical story for the NH artifact. They also show **pre-trend tests are underpowered exactly under this contamination** (clean pretrends coexist with analytically-known violations in their sims).

**Action:** (i) balance check on eviction levels/trends at window re-entry (mid-2022) across treated/control; (ii) robustness excluding cohorts treated within ~6–12 months of reopening; (iii) consider a backlog-proxy adjustment (their "adjusted regression DiD" template) if imbalance appears.

### T4. Pre-trends non-rejection is weak armor (all three methods papers converge)
Baker et al.: low power, don't condition on pretests, use Rambachan–Roth magnitude bounds. AAFP: clustered pretest statistics are themselves downward-biased at long horizons with few clusters (sup-t test Type I ≈15% even at 48 clusters). Callaway & Li: underpowered precisely when contamination exists.

**Action:** make **HonestDiD (Rambachan–Roth) sensitivity bounds** a first-class output of the headline pipeline (we have `analysis/diagnostics/honestdid_sensitivity.R` / `honestdid_levels.R` — promote, don't just diagnose). And per the Walker–Evans critique of Hollenbeck (pre-trends validated on full sample, headline from a subset): **re-run pre-trends on the exact did2s estimation subsample** (pre-COVID cohorts excl. NH), not the full 24-state panel.

### T5. Functional form (AAFP "Dysfunctional Forms")
"TWFE identification strategies are inherently transformation-dependent." Our +9.1% is in log points; parallel trends in logs and levels are mutually exclusive assumptions. **Action:** run the headline spec in levels (`filings_per_1k_renters`) and report both.

### T6. Aggregate calibration may mask horizon-specific SE deflation (AAFP leverage argument applied to ourselves)
Our Type I error checks are aggregate. Even for did2s, far-event-time SEs may be deflated when single states identify those cells. **Action:** AAFP Figure-5-style exercise — under the null DGP, plot simulated sampling SD vs. mean clustered SE *by event time* for did2s and TWFE.

---

## Estimator additions (cheap → expensive)

| Estimator | Verdict | Rationale |
|---|---|---|
| **GSC (Xu 2017) via `gsynth`** | **Add as robustness** | Purpose-built for few treated units + singleton adoption dates (per-state counterfactuals, no cohort aggregation). McCarthy et al. used it on an 11-treated/12-control state-month design nearly identical to ours, with Li–Sonnier factor-robust inference, and showed CS/SA/TWFE point estimates agree while SA/CS SEs are 2–5× larger — matching our calibration pattern. Run it through our calibration harness first. |
| **SDID via `synthdid`** | Add if cheap | One of TROP paper's two fallback recommendations; existing CRAN package. Caveat: doesn't extend naturally to staggered adoption — per-cohort aggregation needed. |
| **Randomization inference** (placebo legalization dates, ≥200 draws) | **Add** | Guo et al. template; sidesteps cluster-count problems entirely; cheap. |
| **TROP** | Skip / future work | No software (would require coding nuclear-norm regression + LOOCV + bootstrap from scratch); their own Fig. 3 shows the edge over TWFE is smallest in the few-treated regime; bootstrap needs growing number of treated units. |
| **Calibration DGP upgrade** | Consider | Our null sims use a simple DGP on the real skeleton; TROP's template fits a low-rank factor model + AR-correlated residuals + confounded placebo assignment (their Eq. 6–8). Would make the calibration harness more convincing. |

---

## Effect-size plausibility chain (for the write-up)

Launch → **$27–75/month per bettor**, growing 2–4 years post (McCarthy; Baker 33108), concentrated in low-income/low-savings households (IGER effect 4–5× higher for low-income tercile; constrained households bet 32%+ more of income) → **overdrafts ↑, CC debt +8% for low-savings, CC payments −$890/qtr** (Baker 33108) → **difficulty paying usual expenses +7.7%; food sufficiency −2.1% ITT (−10.5% among bettors); behind on rent −2.4 pp (−3.0%)** (Guo, Table A11 — *the single best external anchor for evictions*).

+9.1% on eviction *filings* sits at the aggressive end of this chain but within it: filings are a flow response concentrated among exactly the marginal households shown to be harmed, and all three applied papers find effects **growing over 2–4 years** — so our pooled ATT likely understates the mature-market effect. Report event-study horizons, not just the pooled number. Add a Walker–Evans-proof back-of-envelope: share of renters betting × share with losses large enough to trigger nonpayment × filing hazard.

Also usable: Arnesen–Matsuzawa's SUTVA argument (cross-border contamination attenuates → estimates are lower bounds) — now quantitatively backed by Goss & Mangrum.

## Mechanism checks worth adding
- **Online vs. retail-only contrast** (Arnesen–Matsuzawa Table 4 found effects *entirely* from mobile): we already use `online_start_date`; add the retail-only contrast as a mechanism check.
- **Negative-weight diagnostics on TWFE** (they computed weights explicitly and found none negative; cleaner than gesturing at Goodman-Bacon). Already on our TO DO as the Goodman-Bacon decomposition.
- **First-stage verification of treatment dates** against LSR handle spikes at launch (Baker 33108 practice).
- **Placebo outcomes**: non-L/T civil case types as placebo court outcomes (McCarthy's placebo-category idea ported to court data).

---

## Stale facts to fix in CLAUDE.md (Hollenbeck Feb 2026 vs. our Apr 2025-based summary)
1. **The credit-card delinquency null is gone**: Feb 2026 finds **+27%*** (0.006, SE 0.001) for online access. Our comparison narrative cites the old null.
2. Treatment redefined to **Retail-to-Online** (28 retail states; retail→online transition vs. retail-only controls); effects much larger: credit score **−12.0** (was −2.7), bankruptcy ~+25% (was ~+10%), collections ~+9%, auto delinquency ~+25%.
3. They cluster at the **county** level despite state-level treatment, with no calibration diagnostics — our state-clustered, calibration-tested inference is more defensible (differentiation point; also don't benchmark our SEs against theirs).
4. Larsen moved USC → HBS. No journal/R&R indications in either draft.
5. Literature tension worth citing: Goss & Mangrum find **no** bankruptcy/foreclosure effect (point estimates negative), contradicting Hollenbeck's +25% bankruptcy — the severe-distress margin (where eviction lives) is unsettled.

## Notes on Walker & Evans (industry-funded critique)
Funded by "Quackenbos FTW," which suggested the topic; Walker has a pro-industry publication history. The specific econometric points are referee-grade, though: (i) pre-trends on the estimation subsample (→ T4 action); (ii) macro controls / differential income growth (we should state what state-level controls we do/don't use and why); (iii) magnitude plausibility (→ chain above); (iv) don't round "borderline significant, CI crosses zero" up to a confident causal claim in public-facing framing. We are immune to their gambling-expenditure-measurement critiques (DFS/iGaming/offshore contamination) because our treatment is the legal event and outcome is court records, not deposits.

---

## Priority queue
**Tier 1 (do before any new headline claims):**
1. Border-spillover robustness (>60-mile clean controls; distance data build) — T1
2. Audit never-treated states for retail-only betting — T2
3. Pre-trends + HonestDiD on the exact estimation subsample — T4
4. Levels spec of the headline — T5
5. CLAUDE.md Hollenbeck update

**Tier 2:**
6. GSC via `gsynth` (through calibration harness first), maybe SDID
7. Randomization inference with placebo dates
8. Horizon-specific SE calibration (AAFP Fig. 5 exercise)
9. Event-study horizon reporting; online-vs-retail mechanism check

**Tier 3:**
10. Post-COVID backlog balance checks; reopening-adjacent cohort exclusion — T3
11. Magnitude back-of-envelope for the paper text
12. Calibration DGP upgrade (factor model + AR residuals)
13. TWFE weight diagnostics / Goodman-Bacon (existing TO DO)
