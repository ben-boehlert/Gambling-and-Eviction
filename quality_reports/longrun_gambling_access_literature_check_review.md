# Literature Review — librarian-critic
**Date:** 2026-08-20
**Score:** 40/100

## Issues Found

### 1. The substantive correction is right, and the primary-source descriptions are mostly accurate — no deduction

The memo correctly answers the user's objection. Its revised sentence—“The panel can estimate long-run launch-date effects for early adopters, and closely related papers routinely do so”—is much better than treating COVID as making the estimand unavailable. The central distinction is also correct: the papers supply precedent for **estimating** long-horizon effects under additional counterfactual-trend structure; they do not transfer identification credibility automatically to eviction filings.

Checks against the local primary PDFs support the principal factual claims:

- Baker et al. use 230,171 households and about 4.9 million household-quarter observations, retain COVID, include household and year-quarter fixed effects plus income and stimulus controls, use BJS for event-time dynamics, and follow effects through four years. The memo correctly distinguishes the BJS dynamics from the separate post-treatment linear-trend result implying a decline exceeding $144 by four years.
- Hollenbeck, Larsen, and Proserpio use March 2016–June 2023 UC-CCP data, aggregate to county-quarter cells, estimate CS event studies from eight quarters before through sixteen quarters after, and retain COVID while running matching, economic-control, border, and Oxford-policy checks. The memo's 27% credit-card and 25% auto-delinquency magnitudes match the body and Table 4; the manuscript's introduction reverses those two percentages, so the final literature summary should cite Table 4/body rather than the inconsistent introductory sentence.
- Goss and Mangrum use 2018:Q1–2025:Q3 data, a −6 to +12-quarter event window, and explicitly set aggregation weights to zero for pre-2020 own-legalization cohorts and parameters falling in 2020:Q2. Their delayed credit results and continuing betting-market maturation are represented accurately.
- Guo, Peng, and Meyerhoefer are correctly characterized as the direct did2s precedent: January 2021–October 2023 HPS data, nine treated and fifteen control states, a Gardner two-stage estimator, a primary one-year event study, and a supplemental three-season analysis for the five 2021 cohorts.
- McCarthy, Taylor, and Wilbur are accurately described as GSC rather than DiD and as a shorter-horizon pandemic-robustness precedent.

The recommendation to show horizon-specific did2s and LP-DiD estimates, rather than relying on a pooled all-post ATT, is well supported by these papers.

### 2. “Restrict the pandemic-sensitive identifying variation” is slightly too strong for Goss–Mangrum — moderate

The memo later states the implementation correctly, but the bottom-line categorization risks implying that Goss and Mangrum remove the affected observations or comparisons. Their paper says the pre-2020 cohort parameters “are still estimated in the ETWFE regressions” and only receive zero weights in the reported event-study and DD aggregations; likewise, 2020:Q2 parameters are excluded from the preferred aggregates. This changes the reported target population and event-time composition, but it is not the same as purging 2020:Q2 from the underlying estimation sample or nuisance fixed effects. The user-facing conclusion should call this a **target-estimand/aggregation restriction**, not a complete identification repair.

No separate numerical deduction is taken because the paper-by-paper section already makes this distinction.

### 3. Missing comparison of treatment-level inference — high severity, −10 (scope too narrow)

The memo compares estimands and COVID adjustments but not the inferential unit, even though this is central to whether these papers make the eviction design credible. Legalization varies at the state level. The primary papers use materially different procedures:

- Baker et al. double-cluster by individual and state-by-year-quarter, not by state over time.
- Hollenbeck et al. cluster county-level estimates by county even though treatment changes at the state level.
- Goss–Mangrum cluster at a state-by-treatment-cohort level.
- Guo et al. cluster by state.

Millions of household or individual records do not create millions of independent policy shocks. The audit should therefore warn that the apparent precision in the microdata papers is not direct evidence that a 24-state eviction design will have credible long-horizon inference. It should connect this issue to Bertrand, Duflo, and Mullainathan (2004), *How Much Should We Trust Differences-in-Differences Estimates?*; Conley and Taber (2011), *Inference with “Difference in Differences” with a Small Number of Policy Changes*; and Cameron, Gelbach, and Miller (2008), *Bootstrap-Based Improvements for Inference with Clustered Errors*. This omission matters for both did2s and LP-DiD and is the main substantive coverage gap.

### 4. The applied precedent is entirely provisional — high severity, −10

More than half of the application literature is unpublished; in fact, all five full application papers reviewed are working papers or staff reports. The memo should replace “substantial applied precedent” with “multiple recent working-paper precedents” and explicitly note version risk. This does not invalidate the designs, but it weakens any appeal to publication as validation. The recency coverage itself is excellent and receives no deduction.

### 5. Proximity scores reverse the required scale — medium severity, −5

The memo declares “5 = directly competes; 1 = background,” whereas the discovery workflow requires **1 = directly competes** and **5 = tangential/background**. The rankings are internally consistent under the memo's reversed convention, but inconsistent with the project's required scale and therefore unsafe to merge into the master literature review without recoding.

### 6. BibTeX entries are missing — high severity, −35

The deliverable includes no BibTeX entries for the seven cited items that function as reviewed papers: Baker et al.; Hollenbeck, Larsen, and Proserpio; Goss and Mangrum; Guo, Peng, and Meyerhoefer; McCarthy, Taylor, and Wilbur; Dube, Girardi, Jordà, and Taylor; and Arnesen and Matsuzawa. Under the stated rubric this is −5 per paper. This is an artifact-completeness failure, not a source-accuracy failure; the links and titles are otherwise sufficient for the immediate user response.

### 7. Frontier/gap identification and recency are adequate — no deduction

Although there is no separately labeled frontier map, the memo clearly identifies the relevant frontier: direct did2s precedent exists only in a post-acute-COVID sample; no reviewed sports-gambling application uses LP-DiD; cross-COVID long-horizon estimates require outcome-specific defenses; and Goss–Mangrum change the target population by excluding early cohorts from preferred aggregation. That is enough gap identification for this targeted question. No recent-paper deduction is warranted.

## Score Breakdown
- Starting: 100
- Scope too narrow: missing treatment-level/small-cluster inference comparison: −10
- Over-reliance on unpublished working papers (>50%): −10
- Proximity scores inconsistent with the required scale: −5
- Missing BibTeX entries for seven reviewed papers: −35
- **Final: 40/100**

## Disposition

The substantive answer is usable now: the user's pushback is correct, and the project can estimate long-run access effects with did2s and LP-DiD while stating that the identifying assumption crosses COVID. Before treating this as a complete literature-review artifact, the Librarian should add treatment-level inference comparisons, recode proximity scores, label the application evidence as provisional working-paper precedent, and supply BibTeX entries. The most important wording correction is that COVID changes the required assumption and target-population choices; it does not make long-run access effects unavailable.
