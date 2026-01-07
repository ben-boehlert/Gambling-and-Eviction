# Synthetic DiD for Post-COVID Period: Feasibility Assessment

## What is Synthetic DiD?

**Synthetic Difference-in-Differences** (Arkhangelsky et al. 2021) combines:
- **Synthetic control**: Reweights control units to better match treated units pre-treatment
- **DiD**: Differences out time-invariant confounders and common trends

**Key advantage over standard DiD**: Does NOT require parallel trends assumption. Instead, it reweights control units to create better counterfactuals.

**Key advantage over synthetic control**: Can handle multiple treated units and staggered adoption (unlike traditional SC which needs single treated unit).

---

## Could You Use It for Post-COVID?

### Short Answer: **Possibly, but with important caveats**

---

## Feasibility Analysis for Your Data

### ✅ Strengths (Why It Might Work)

**1. Relaxes Parallel Trends**
- Your main problem: parallel trends violated post-COVID (t=-5.18, p<0.001)
- Synthetic DiD doesn't require parallel trends
- Instead, it assumes you can reweight controls to match treated pre-treatment trends

**2. Handles Staggered Adoption**
- You have staggered treatment (states adopt gambling at different times)
- Recent methods (Arkhangelsky et al. 2021; Ben-Michael et al. 2022) handle this
- `synthdid` R package supports staggered designs

**3. Sufficient Pre-Treatment Data**
- You have 2016-2020 (50 months) before COVID break
- Could use 2020-2021 as "pre-period" for post-COVID analysis
- Need at least 10-15 pre-treatment periods (you have enough)

**4. Reasonable Sample Size**
- 25 states total
- ~10-15 treated states
- ~10-15 control states (donor pool)
- This is on the margin but workable

---

### ⚠️ Challenges (Why It Might Not Work)

**1. Structural Break at COVID**
- Synthetic DiD assumes **stable relationship between treatment and controls**
- COVID fundamentally changed eviction dynamics:
  - Eviction moratoria (differential by state)
  - Economic shock (differential by industry composition)
  - Housing market changes
- If COVID affected treated/control states differently in ways unrelated to gambling, synthetic DiD will struggle

**2. Time-Varying Confounders**
- COVID created massive time-varying confounders:
  - State-specific moratoria policies
  - Differential economic recovery
  - Housing market divergence
- Synthetic DiD can't handle confounders that affect treated/control differently UNLESS they're in your covariates

**3. Small Donor Pool**
- Only ~10-15 never-treated states
- Some may be poor matches (e.g., ID has very different eviction rates)
- Limited flexibility for reweighting

**4. Treatment Timing**
- Many states adopted gambling BEFORE COVID (2019-2020)
- For these states, COVID occurs during treatment period
- Can't cleanly separate gambling effect from COVID effect

**5. Identifying Assumption Still Strong**
- Synthetic DiD assumes: weighted average of controls can match treated in ABSENCE of treatment
- With COVID structural break, this is dubious

---

## Implementation Approach (If You Proceed)

### Option A: Post-COVID Only Analysis

**Period**: 2021-2025 (post-COVID "new normal")

**Idea**:
- Treat COVID as a permanent regime shift
- Use 2021-2022 as "pre-treatment" baseline
- Analyze states that adopted gambling 2023+
- Construct synthetic controls from never-treated states in post-COVID era

**Pros**:
✓ Avoids mixing pre/post COVID dynamics
✓ Cleaner identification within stable regime
✓ Relevant to current policy

**Cons**:
✗ Very few late adopters (most states adopted pre-2023)
✗ Short post-treatment follow-up
✗ Small sample

**Feasibility**: **LOW** - not enough late adopters

---

### Option B: Synthetic DiD with COVID Controls

**Period**: 2016-2025 (full period)

**Idea**:
- Include COVID-period covariates in synthetic control matching:
  - Eviction moratoria strength/duration
  - Unemployment rate changes
  - Housing price changes
  - Rental assistance uptake
- Reweight controls to match treated on pre-COVID trends AND COVID exposure

**Implementation**:
```r
library(synthdid)

# Prepare data
panel_long <- panel_df %>%
  select(unit_id, month_date, outcome, state_abb) %>%
  # Add COVID covariates
  left_join(covid_covariates, by = c("state_abb", "month_date"))

# Add treatment indicator
panel_with_treat <- panel_long %>%
  left_join(treat_schedule, by = "unit_id")

# Convert to synthdid format
setup <- synthdid::panel.matrices(
  panel = panel_with_treat,
  unit = unit_id,
  time = month_date,
  outcome = outcome,
  treatment = treated
)

# Estimate with covariates
tau.sc <- synthdid_estimate(
  setup$Y,
  setup$N0,
  setup$T0,
  covariates = covid_covariates  # Key: include COVID controls
)
```

**Pros**:
✓ Uses full data
✓ Can control for observable COVID differences
✓ Established method

**Cons**:
✗ Requires good COVID covariate data
✗ May not capture all confounding
✗ Still assumes weighted average is valid counterfactual

**Feasibility**: **MEDIUM** - depends on covariate availability

---

### Option C: Separate Pre/Post COVID Analyses

**Approach**:
1. **Pre-COVID**: Standard DiD (what you're doing)
2. **Post-COVID**: Synthetic DiD with post-2021 data only

**Report both separately** with clear caveats about regime change.

**Pros**:
✓ Transparent about structural break
✓ Appropriate method for each period
✓ Shows robustness (or lack thereof)

**Cons**:
✗ Can't claim unified effect estimate
✗ Post-COVID analysis may be underpowered

**Feasibility**: **HIGH** - this is the safest approach

---

## My Recommendation

### **Don't use synthetic DiD for post-COVID. Stick with pre-COVID analysis.**

### Reasoning:

**1. Fundamental Identification Problem**
- COVID is not just a parallel trends violation
- It's a **structural break** that changed the eviction-gambling relationship
- Synthetic control can't fix this - it's not a weighting problem, it's that the data generating process changed

**2. Your Pre-COVID Analysis is Strong**
- Parallel trends hold (p=0.14)
- Type I error well-calibrated (12%)
- Clean identification
- Defensible

**3. Post-COVID Would Be Fragile**
- Even with synthetic control, you'd need to assume:
  - COVID affected treated/control states similarly (we know it didn't)
  - No omitted time-varying confounders
  - Weighted controls are valid counterfactual
- These are very strong assumptions post-COVID

**4. Power Simulation for Post-COVID Would Be Invalid**
- Power analysis assumes your identification strategy is valid
- If identification is questionable, power estimates are meaningless
- Better to have conservative power from small sample than optimistic power from invalid design

---

## What to Say in Your Paper/Grant

**Be transparent and turn limitation into strength:**

> "We conduct our power analysis using pre-COVID data (2016-2020) where parallel trends demonstrably hold (p=0.14). We do not extend the analysis to post-COVID data for two reasons. First, the COVID-19 pandemic created a structural break in eviction patterns, with differential eviction moratoria and economic shocks across states violating the parallel trends assumption (p<0.001). Second, while synthetic control methods can relax parallel trends, they cannot address fundamental regime changes where the relationship between treatment and outcome differs across periods. Our power estimates therefore conservatively reflect the pre-COVID context. Future work could examine post-pandemic effects once sufficient post-COVID data accumulate and the housing market stabilizes."

---

## Alternative: Descriptive Post-COVID Analysis

If you want to explore post-COVID data **without causal claims**:

**Approach**: Descriptive event study
- Show raw trends for treated vs control states post-2021
- Label as "descriptive" not "causal"
- Use to motivate future research

**Example**:
```r
# Descriptive post-COVID trends
post_covid_trends <- panel_df %>%
  filter(month_date >= "2021-01-01") %>%
  mutate(treated = !is.na(treat_date) & treat_date < "2021-01-01") %>%
  group_by(month_date, treated) %>%
  summarise(mean_outcome = mean(outcome, na.rm=TRUE))

# Plot with clear disclaimer
ggplot(post_covid_trends, aes(x=month_date, y=mean_outcome, color=treated)) +
  geom_line() +
  labs(
    title = "Post-COVID Eviction Trends (Descriptive Only)",
    subtitle = "Causal interpretation not warranted due to structural break",
    caption = "Treated = states with gambling before 2021"
  )
```

---

## Bottom Line

**For power simulation**: Use pre-COVID only (Option 1 from `covid_handling_options.md`)

**For post-COVID substantive analysis** (separate paper):
- Wait for more data (2026-2027) to see if new equilibrium emerges
- Use synthetic DiD IF you can construct rich COVID covariates
- More likely: use event study + heterogeneity analysis

**For current grant/paper**:
- Pre-COVID power analysis is the right choice
- Acknowledge limitation clearly
- Frame as conservative approach

---

## If You Still Want to Try Synthetic DiD

### Required Steps:

1. **Collect COVID covariates**:
   - State-level eviction moratoria dates/stringency
   - Monthly unemployment by state
   - Housing price indices
   - Rental assistance distribution

2. **Test balance**:
   - Check if synthetic weights achieve good pre-COVID balance
   - Plot treated vs synthetic control pre-COVID
   - If balance is poor, method won't work

3. **Placebo tests**:
   - Assign fake treatment to never-treated states
   - Check if method finds null effects
   - If you get false positives, identification is weak

4. **Report honestly**:
   - Show balance diagnostics
   - Acknowledge structural break limitation
   - Present as exploratory, not definitive

### R Package:
```r
install.packages("synthdid")
library(synthdid)

# See vignette
vignette("synthdid")
```

### Papers to Read:
- Arkhangelsky et al. (2021, AER) - original synthetic DiD
- Ben-Michael et al. (2022, JASA) - augmented synthetic control
- Abadie (2021, JBES) - using synthetic controls review

---

## Summary Table: Approach Comparison

| Approach | Pros | Cons | Feasibility | Recommendation |
|----------|------|------|-------------|----------------|
| **Pre-COVID only** | Valid identification, clean | Small sample, limited period | HIGH | ⭐ USE THIS |
| **Synthetic DiD post-COVID** | Uses more data, relaxes PT | Structural break, weak ID | MEDIUM | ❌ Too risky |
| **COVID covariates + Synth DiD** | Controls COVID differences | Needs good covariates | MEDIUM | ⚠️ Only if strong covariates |
| **Separate pre/post** | Transparent, period-specific | No unified estimate | HIGH | ✓ For robustness |
| **Descriptive post-COVID** | Exploratory, no ID claims | Not causal | HIGH | ✓ For motivation |

---

**My final advice: Don't overthink this. Your pre-COVID analysis is solid. Use it. COVID broke everything - that's not a failure of your method, it's reality. Being conservative and transparent about this is a strength, not a weakness.**
