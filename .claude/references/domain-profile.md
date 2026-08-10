# Domain Profile — Sports Gambling Legalization and Eviction

Solo-authored replication package + analysis. Tests whether state online sports-gambling legalization affected county-level eviction filings using staggered DiD. **Headline: well-powered null on evictions** (TWFE MDE = 5 log points, ATT = −0.225, p = NS). Methodological side-finding: heterogeneity-robust estimators (CS-DiD, Sun-Abraham, didimputation, did2s) are 4–5× noisier than TWFE on this design due to singleton cohorts (11 treated states, each its own legalization date).

## Field

**Primary:** Public Economics / Urban Economics
**Adjacent subfields:** Behavioral / Health Economics (gambling), Industrial Organization (online betting), Methodology (staggered DiD calibration)

---

## Target Journals (ranked by tier)

| Tier | Journals |
|------|----------|
| Top field | AEJ:Applied, AEJ:Policy, JOLE, JHR |
| Strong field | JUE, JHE, J Risk and Uncertainty, JPubE |
| Methods | J Econometrics, J Applied Econometrics (for staggered-DiD calibration finding) |
| Specialty | Housing Policy Debate, J Gambling Studies |

---

## Common Data Sources

| Dataset | Type | Access | Notes |
|---------|------|--------|-------|
| Eviction Tracking System (ETS) county-month panel 2016–2025 | Constructed | Public (Eviction Lab) | Primary outcome; 38 states; 24 after balancing + COVID drop. Maine excluded |
| State sports gambling legalization dates | Hand-coded | Public | Online vs retail vs first-effective-date variants |
| LSR sports betting handle/revenue by state-month (June 2018–) | Industry | Public, scraped | Post-treatment intensity (Handle, Revenue, Hold, Taxes); 34 states |
| State-month mortgage delinquency 90+ days late | Aggregate | Public | Alternative outcome; 51 states + DC |
| Court Data (county-year filings) for 7 non-ETS gambling states | Hand-collected | Public, varied | NJ, IA, OR, IL, MI, WY, MD — annual only |

---

## Common Identification Strategies

| Strategy | Typical Application | Key Assumption to Defend |
|----------|---------------------|--------------------------|
| TWFE staggered DiD with state clustering | Primary spec | Common pre-trends; small Goodman-Bacon (2021) bias for null result |
| Callaway-Sant'Anna ATT(g,t) + analytic + bootstrap inference | Heterogeneity-robust robustness | Conditional parallel trends; **CS-DiD over-rejects (14% under null) on this design due to singleton cohorts** |
| Sun-Abraham event study with `fixest::sunab()` | Same | Same; SA also miscalibrated (21% under null) |
| Roth (2022) power + Rambachan-Roth (2023) `HonestDiD` bounds | Pre-trend defense | Uniform pre-trend slope is meaningful null |
| Hartman-Hidalgo equivalence test | Positive evidence FOR parallel trends | Provides smallest δ* that can be ruled out |

---

## Field Conventions

- **Cluster at state level** (treatment varies at state level — county data does NOT improve power)
- **Drop COVID period** (2020-03 to 2022-03) — pre-COVID parallel trends are clean
- **Maine excluded** for data quality; Idaho excluded from annual analyses
- **Balance to common months** (83 months → 24 states surviving)
- **Multi-estimator calibration** — never report a CS-DiD result without disclosing the SE/SD ratio + null rejection rate from a self-test
- **Heterogeneity-robust MDE = 4–5× TWFE MDE** on this design — disclose explicitly
- **Frame null as a bound**: "no evidence of effects above 5%" not "gambling does not cause evictions"
- Compare to **Hollenbeck, Larsen & Proserpio (2025)** — 51 vs 24 clusters explains why CS works for them

---

## Notation Conventions

| Symbol | Meaning | Anti-pattern |
|--------|---------|--------------|
| Effect (%) | Effect on filings expressed as log points (e.g., 5 log points ≈ 5%) | Don't conflate log point and percentage point |
| Cohort | All states with the same first-treatment month | Singleton per state on this design (11 cohorts) |
| MDE | Minimum detectable effect (80% power, α=0.05) | Disclose which estimator: TWFE 5%, CS ~25% |
| SE/SD ratio | Calibration metric (1 = well-calibrated) | TWFE 1.14, CS 0.67, SA 0.58 |

---

## Seminal References

| Paper | Why It Matters |
|-------|----------------|
| Callaway & Sant'Anna (2021, JEcon) | CS-DiD estimator |
| Sun & Abraham (2021, JEcon) | SA event-study estimator |
| Goodman-Bacon (2021, JEcon) | TWFE decomposition |
| Borusyak, Jaravel & Spiess (2024, REStud) | didimputation |
| Gardner (2022) | did2s two-stage estimator |
| Roth (2022, AER:Insights) | Power analysis for pre-trend tests |
| Rambachan & Roth (2023, REStud) | `HonestDiD` sensitivity bounds |
| Hartman & Hidalgo (2018) | Equivalence testing for parallel trends |
| Bertrand, Duflo & Mullainathan (2004, QJE) | Cluster-robust SE in DiD |
| **Hollenbeck, Larsen & Proserpio (2025)** | Same treatment, individual-level credit panel; 51 clusters; finds significant credit effects |
| Burlig, Preonas & Woerman (2020) | Simulation-based power for panel designs |
| Black, Galdo, Bond & Gilbert (2022) | Simulation power for complex DiD/DDD |

---

## Theoretical Foundational References

| Topic | Anchor references |
|-------|-------------------|
| Staggered DiD identification | Goodman-Bacon (2021); Callaway & Sant'Anna (2021); Sun & Abraham (2021); de Chaisemartin & d'Haultfoeuille (2020) |
| Pre-trend inference | Roth (2022); Rambachan & Roth (2023); Roth, Sant'Anna, Bilinski & Poe (2023, REStat) |
| Cluster-robust + serial correlation | Bertrand, Duflo & Mullainathan (2004); Burlig, Preonas & Woerman (2020) |

---

## Paper Author Team

| Author | Foundational on |
|--------|-----------------|
| Boehlert | Sole author |

---

## Field-Specific Referee Concerns

- **"Null vs underpowered?"** — TWFE MDE = 5% is well-powered; framing is "ruled out >5% effect, can't rule out 1–2%"
- **"Why TWFE if it has Goodman-Bacon bias?"** — TWFE is well-calibrated on this design (SE/SD = 1.14); for a null, GB bias of zero ≈ zero. CS/SA over-reject due to singleton cohorts
- **"Why not aggregate to state-year and use Hollenbeck et al's panel?"** — power constraint is at the state level (cluster count), not within-state
- **"Anticipation effects?"** — pre-trends clean (Holm min p = 1.0 for CS); SA flags long-horizon trends not near-treatment violations
- **"Why ETS-only?"** — court data is annual not monthly; 7 additional gambling states are court-only
- **"Eviction is downstream — should expect attenuation"** — disclose; the more extreme margin
- **"Should the calibration finding be the main paper instead?"** — possible re-frame; methodological contribution may have higher leverage

---

## Quality Tolerance Thresholds

| Quantity | Tolerance | Rationale |
|----------|-----------|-----------|
| Point estimates (log points) | 1e-3 | Reported to 3 decimals |
| Standard errors | 1e-3 | Bootstrap variability with biters=199 |
| Calibration metrics (SE/SD, rejection rate) | 0.01 | 100 null sims |
| Power simulation MDE | 0.5% | Discrete grid in simulation |
| Cohort counts | exact | 11 treated states, must reproduce |
