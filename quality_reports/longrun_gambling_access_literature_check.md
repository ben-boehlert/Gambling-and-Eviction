# Targeted literature check: long-run sports-gambling access, COVID, did2s, and LP-DiD

**Date:** 2026-08-20  
**Scope:** Targeted verification of the directly related papers named in the request and the principal adjacent papers already collected in `Literature/` and `docs/literature_review_2026-07_estimation_strategy.md`. This is not a new exhaustive literature review. Proximity uses the project scale requested here: **5 = directly competes; 1 = background**.

## Bottom line

The correction to the prior assessment is important: **there is substantial applied precedent for estimating effects two to four years after sports-betting access.** Baker et al. estimate dynamic effects through four years; Hollenbeck, Larsen, and Proserpio (HLP) report through sixteen quarters; and Goss and Mangrum report through twelve quarters. All find that either betting intensity or downstream financial harm grows or appears with delay. Thus, this eviction project should not dismiss a long-run access estimand merely because COVID lies between launch and mature exposure.

However, those papers do not offer a design that makes COVID irrelevant. They take one of three approaches:

1. **Cross COVID and impose a common/conditional counterfactual-trend model:** Baker et al. use year-quarter fixed effects plus household income and stimulus controls; HLP use contemporaneous untreated comparisons and separately examine COVID-policy balance.
2. **Restrict the pandemic-sensitive identifying variation:** Goss and Mangrum omit pre-2020 legalization cohorts from their preferred aggregation and zero-weight 2020:Q2; Guo et al. start their estimation sample in January 2021.
3. **Model differential pandemic paths and run explicit pandemic exclusions:** McCarthy, Taylor, and Wilbur use interactive factors plus unemployment, mobility, cases, and deaths, then exclude pandemic-launch states and, separately, March–December 2020.

The genuine precedent is therefore: **estimate and report long-run launch-date effects, display event-time dynamics rather than only a pooled ATT, and defend COVID with design-specific restrictions and sensitivity analyses.** The precedent does **not** establish that a full-panel did2s regression with only state and month fixed effects is automatically credible in the eviction panel. None of the directly related papers reviewed uses LP-DiD, and the one directly related did2s paper avoids the acute pre-/post-COVID bridge.

## Paper-by-paper verification

### Baker et al. (2024), *Gambling Away Stability: Sports Betting's Impact on Vulnerable Households*

**Proximity: 5/5.** Same online-sports-betting launch variation and household financial-distress mechanisms closest to eviction. The paper uses a transaction-level financial aggregator collapsed to a panel of 230,171 households and about 4.9 million household-quarter observations, with underlying coverage from 2012:Q4 through 2023:Q3. It studies all 26 online launches from August 2018 through September 2023. The main static specification is household-level TWFE DiD with household and year-quarter fixed effects, quarterly household income and stimulus payments, and up to four years before and after launch; treated units are dropped after that window and not reused as controls. Dynamic effects are estimated with Borusyak-Jaravel-Spiess (BJS) imputation, with CS and Sun-Abraham shown as alternatives. Betting deposits stabilize near $60 per household-quarter after three years; net investment falls noticeably after two to three years, and a post-treatment trend implies a decline exceeding $144 per quarter by four years.

- **Treatment timing:** First date online betting can actually be placed.
- **Long-run construction:** BJS event-time coefficients and a treatment-by-post-treatment linear trend, through four years.
- **COVID handling:** The main sample retains COVID. National/common shocks are absorbed by year-quarter effects; household income and stimulus payments are controlled. No pandemic window is dropped in the primary estimates.
- **Do comparisons cross COVID?** Yes. The four-year windows for the 2018–2019 cohorts necessarily cross 2020, and later cohorts also compare pandemic/post-pandemic periods.
- **Identifying assumption:** In the absence of legalization, financial outcomes for about-to-legalize households would have evolved like outcomes for not-yet/never-legalized households, conditional on the fixed effects and controls. The paper checks pretrends; that is evidence about, not a substitute for, this assumption.
- **What it supports here:** A launch-date event study can legitimately target two-to-four-year access effects even when Handle ramps slowly. It also shows why a pooled post-launch ATT may obscure maturation. It is precedent for crossing COVID under an additive conditional-trends model, not proof that state-specific eviction-court disruptions satisfy that model.

Primary source: [NBER Working Paper 33108](https://www.nber.org/papers/w33108) (paper Sections 4–6 and Figures 4–5).

### Hollenbeck, Larsen, and Proserpio (February 2026), *The Financial Consequences of Legalized Sports Gambling*

**Proximity: 5/5.** Same policy and downstream severe-credit outcomes using the UC Consumer Credit Panel. The February 22, 2026 manuscript (SSRN last revised February 24) contains 4.38 million individuals and 90 million individual-quarter records from March 2016 through June 2023, aggregated to weighted county-quarter cells for estimation. It uses Callaway-Sant'Anna (CS) with never- and not-yet-treated comparisons for (i) General Access and (ii) retail-to-online transitions. Event studies cover eight pre-treatment and sixteen post-treatment quarters. Retail-to-online access lowers credit scores about 12 points and raises bankruptcy roughly 25%, collections roughly 9%, credit-card delinquency roughly 27%, and auto delinquency roughly 25%; bankruptcy effects appear after about two years.

- **Treatment timing:** General Access begins with first reported revenue from any legal channel; Retail-to-Online begins with statewide online availability among retail-first states.
- **Long-run construction:** CS group-time effects aggregated into event-time effects through sixteen quarters.
- **COVID handling:** COVID is retained. The authors acknowledge many online launches occurred around COVID; they examine pretreatment observables, matching, unemployment/poverty controls, and event studies of Oxford COVID economic-support, government-response, and stringency indices. They report no policy-index differential coincident with treatment.
- **Do comparisons cross COVID?** Yes. The 2018–2021 cohorts and four-year event windows span the pandemic. COVID is assessed, not removed.
- **Identifying assumption:** Conditional parallel trends between treated counties and contemporaneous not-yet/never-treated counties for each treatment definition, plus no anticipation. The retail-to-online event study has visible nonzero pre-period differences in the unmatched sample, which the authors address with coarsened exact matching.
- **What it supports here:** Delayed severe financial outcomes are a substantively plausible launch-date estimand. It is precedent for defending cross-COVID comparisons with contemporaneous controls and pandemic-policy diagnostics. It does not validate the eviction panel's parallel-trend assumption, and it is not precedent for did2s or LP-DiD.

Primary source: [SSRN 4903302](https://ssrn.com/abstract=4903302) (paper Sections 3.2–5 and Appendix C).

### Goss and Mangrum (2026), *Sports Betting Across Borders: Spatial Spillovers, Credit Distress, and Fiscal Externalities*

**Proximity: 5/5.** Same mobile-betting policy and credit distress, with explicit attention to contaminated control states. The paper uses an Earnest Analytics county-quarter spending panel from 2018:Q1 through 2025:Q3 (1,690 balanced counties) and the New York Fed Consumer Credit Panel aggregated to county/ZIP-quarter cells. It estimates spillover-extended ETWFE with fully saturated treatment-cohort-by-event-time effects, county and quarter fixed effects, and a preferred event window from six quarters before through twelve quarters after treatment. Sportsbook spending per person grows to roughly $40 per quarter after three years without saturating; delinquency begins rising after about one year and reaches about 0.5 percentage point after three years, while median credit scores fall about one point.

- **Treatment timing:** First quarter of mobile legalization, jointly modeled with first cross-border spillover exposure.
- **Long-run construction:** Cohort-event-time ETWFE parameters aggregated to direct and spillover event studies through twelve quarters.
- **COVID handling:** The preferred aggregation sets weights to zero for cohorts legalizing before 2020:Q1 and for parameters corresponding to 2020:Q2. Unrestricted versions are reported in the appendix. Quarter effects absorb common shocks.
- **Do comparisons cross COVID?** Some preferred long-horizon comparisons do: post-2020 cohorts followed for three years span the pandemic/recovery period. But the design deliberately does **not** use mature outcomes of the early pre-pandemic cohorts in the preferred aggregate.
- **Identifying assumption:** In the absence of own-state and neighboring-state exposure, outcomes follow parallel trends conditional on fixed effects; no anticipation; outcomes do not depend on future policy timing; and spillover “immunity” after own-state legalization.
- **What it supports here:** This is the clearest precedent that market maturation and delayed financial distress are central outcomes, and that pandemic-sensitive cohorts can be restricted rather than abandoning long horizons. It also cautions that never-treated border counties may be partially treated. It does not solve the early-adopter mature-effect problem: its preferred estimate explicitly omits those early cohorts.

Primary source: [Federal Reserve Bank of New York Staff Report 1184](https://www.newyorkfed.org/research/staff_reports/sr1184) (paper Sections 3–5 and Online Appendix A.4).

### Guo, Peng, and Meyerhoefer (2026), *Wagering the Bread Money: Sports Betting Legalization and Food Sufficiency*

**Proximity: 4/5.** Same policy, a near-housing-hardship outcome, and the strongest direct precedent for **did2s**. The primary data are repeated cross-sections from the January 2021–October 2023 Household Pulse Survey, with 301,406 working-age non-college observations. Nine states legalizing jointly online/retail in 2021–2023 are compared with fifteen never-treated states. Gardner did2s fits state and survey-wave effects on untreated (not-yet plus never-treated) observations and then estimates the treatment effect from residualized outcomes. The paper finds a 1.7 percentage-point reduction in food sufficiency (2.1% relative to baseline; 10.5% scaled to active bettors). The primary event study spans one year; a supplementary three-year display for 2021 cohorts shows harm recurring during three NFL seasons rather than a monotonic mature-market effect.

- **Treatment timing:** Operational joint online-and-retail legalization, verified against statutes and other launch sources.
- **Long-run construction:** did2s dynamic event-time indicators; primary one-year window, supplementary three-year seasonal analysis.
- **COVID handling:** The authors explicitly exclude pre-2021 HPS waves to mitigate the independent pandemic shock. The baseline retains 2021–2023 and uses state and survey-wave effects; a robustness model adds unemployment, COVID hospitalization and mortality, and SNAP-emergency-allotment expiration. A DDD with college graduates is another pandemic-confounding check.
- **Do comparisons cross COVID?** They occur during the pandemic/recovery but do not bridge a pre-pandemic baseline to post-pandemic outcomes, because the estimation sample begins in January 2021.
- **Identifying assumption:** Absent legalization, treated and control states would have had the same changes in food sufficiency; did2s additionally requires the additive state-plus-wave untreated-outcome model to be correctly specified (or the conditional extension when controls are added).
- **What it supports here:** Direct precedent for did2s with singleton/small treated cohorts and state-clustered inference. More specifically, it supports a post-acute-COVID did2s design. It does **not** supply precedent for estimating early adopters' three-to-four-year effects by joining 2018–2019 baselines to 2022–2024 eviction outcomes.

Primary source: [NBER Working Paper 35305](https://www.nber.org/papers/w35305) (paper Sections 2.2–3.2 and Appendix D).

### McCarthy, Taylor, and Wilbur (2026), *Online Market Launch and the Distribution of Gambling Risk*

**Proximity: 4/5.** Same online launch and direct observation of betting intensity, but an alternative estimator and shorter maximum horizon. The paper uses monthly financial-panel data for 1.2 million individuals in 11 treated and 12 never-treated states from 2019–2023. Generalized Synthetic Control (GSC) estimates state-specific counterfactuals using interactive latent factors, state/time fixed effects, and never-treated states. Dynamic effects are shown from month −20 to +20; most treated states have at least nineteen post-launch months. Spending jumps on impact and remains elevated; the income-adjusted high-risk share settles around a 0.76 percentage-point increase after month 13.

- **Treatment timing:** First calendar month of legal online wagering.
- **Long-run construction:** State-month GSC treatment effects averaged by event month through about twenty months.
- **COVID handling:** Main GSC controls for state unemployment, six Google-mobility series, COVID cases, and COVID deaths. Robustness checks exclude Colorado, Illinois, Tennessee, and Virginia (pandemic-onset launches), and separately remove March–December 2020 and shift affected treatment dates to January 2021.
- **Do comparisons cross COVID?** Yes in the main model; the dedicated exclusions show the results are not driven only by pandemic-launch states or the initial COVID interval.
- **Identifying assumption:** Untreated outcomes follow the estimated interactive-factor structure; treated-state factor loadings learned pre-treatment remain valid post-treatment, conditional on observables; no treatment anticipation.
- **What it supports here:** Strong evidence that pandemic-era long-run access effects can be studied if differential paths are modeled and pandemic exclusions are explicit. It is not did2s/LP-DiD precedent and its roughly twenty-month horizon is shorter than the mature early-cohort horizon in the eviction project.

Primary source: [SSRN 4856684](https://ssrn.com/abstract=4856684) (paper Sections 4–7 and Web Appendices E7–E8).

## What the precedent genuinely implies for did2s and LP-DiD here

### did2s

The literature supports **including a long-run did2s specification**, but with an important qualification. Guo et al. provide direct same-policy precedent for did2s, yet they begin in January 2021 and therefore avoid fitting one state effect across the pre-pandemic and post-pandemic regimes. Baker et al. provide precedent for four-year cross-COVID dynamics, but with BJS rather than did2s and with year-quarter effects, income, and stimulus controls. Accordingly, a full-span did2s result in this project is a defensible research object, but its credibility rests on defending the additive untreated-outcome model against state-specific moratoria, court closures, reporting interruptions, and backlog recovery. Citation to the gambling literature alone cannot discharge that burden.

The strongest substantive lesson from Baker, HLP, and Goss–Mangrum is that **a pooled all-post-period ATT is not enough**. When exposure and financial harms grow after launch, the project should show horizon-specific effects and the Handle attained by contributing cohorts. Otherwise, early ramp-up observations can dominate the average even if the eventual launch effect is larger.

### LP-DiD

None of the targeted directly related gambling papers reviewed here uses LP-DiD. Its support is methodological rather than same-application precedent. Dube et al.'s estimator targets a separate treatment effect at each horizon using switchers and controls kept “clean” through that horizon, and it can condition on covariates. For an early adopter at a three-year horizon, however, the long outcome change still runs from the pre-launch baseline across COVID. LP-DiD replaces a single global full-panel restriction with a **cohort-and-horizon-specific parallel-change assumption**; it does not make a state-specific pandemic shock vanish.

Thus LP-DiD is especially useful for making the identifying comparisons and horizon-specific support transparent, but a mature-effect coefficient for West Virginia, Pennsylvania, or Indiana remains a cross-COVID comparison. The directly related papers establish that such a comparison is common and publishable when explicitly defended. They do not establish that it is automatically valid.

Method source: [Dube, Girardi, Jordà, and Taylor, “A Local Projections Approach to Difference-in-Differences,” JAE / NBER 31184](https://www.nber.org/papers/w31184).

## Precise revised conclusion for the eviction project

The earlier statement that mature-market effects “cannot cleanly be identified” without crossing COVID was too categorical. A better statement is:

> The panel can estimate long-run launch-date effects for early adopters, and closely related papers routinely do so. Those estimates necessarily rely on a counterfactual-trend assumption across the COVID disruption. COVID therefore changes the strength and content of the identifying assumption; it does not make the estimand unavailable.

For positioning, the project can legitimately present long-horizon did2s and LP-DiD estimates as estimates of access as implemented, including market maturation. Their credibility should be reported separately from short-run, non-straddling estimates. Agreement across the two would be informative because they organize the comparisons differently, but it would not by itself rule out common state-specific COVID confounding.

## Nearby paper that is not strong precedent for the long-run estimand

Arnesen and Matsuzawa's sports-betting/IPV paper spans 2011–2022 and includes an exclusion of 2020 as a robustness check, but its causal object is whether legal betting amplifies the immediate effect of an unexpected NFL upset loss on Sunday IPV—not the cumulative effect of years of access. It is therefore substantively relevant but not a useful precedent for a mature-market eviction event study. [Primary working-paper version](https://cheps.sdsu.edu/_resources/docs/working-papers/cheps-wp-20251001.pdf). **Proximity: 3/5.**
