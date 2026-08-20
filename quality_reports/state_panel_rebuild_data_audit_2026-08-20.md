# State Panel Rebuild Data Audit — 2026-08-20

## Scope and decision

This is a critique-only audit of the 2026-08-20 rebuild of
`data/raw/state_month_panel_with_treatment.csv` and its immediate derived Handle-50
panel. It does not audit or rerun the simulation results that still depend on the
old panel.

**Decision: MAJOR ISSUES — the mechanical double-add fix works, but the rebuilt
state panel is not yet safe for final state-level results.**

The rebuild removes the old county-plus-ETS addition for all 12 affected states,
not only Minnesota and Texas. The current canonical file has 3,978 rows, 39
states, and no duplicate `(state_abb, month_date)` keys. All 3,242 rows labeled
`county_download_sum` reproduce the county file's state-month filings, renter
sums, and reporting-row counts. All 736 carried rows reproduce the preserved
pre-fix panel. The raw county file itself has 120,725 rows, no exact duplicate
rows, and no duplicate `(fips, month)` keys.

However, the rebuild creates invalid finite eviction rates for six states, does
not control reporting-geography changes that contaminate the default log-count
outcome, and is not safely reproducible. The diagnostic and documentation also
overstate what was proven.

## Severity-ranked findings

### 1. Critical: zero denominators are converted into fabricated finite rates

At `data_prep/rebuild_state_month_panel.R:108-109`, the rebuild computes

```r
filings_count / pmax(renter_occupied_housing_units, 1) * 1000
```

For LA, MA, MO, NM, NV, and RI, all 404 ETS-only rows have
`renter_occupied_housing_units == 0`. In the preserved pre-fix panel their rate
was `NA`; the rebuild converts it to `filings_count * 1000`, producing finite
values as high as 6,934,000 filings per 1,000 renters. Because the values are
finite, downstream code that trusts an existing finite rate will not repair or
drop them. The rebuilt Handle-50 panel propagates 333 of these rows (Nevada is
excluded there).

**Why it matters:** every rate-outcome, rate heterogeneity, descriptive rate, or
rate-based sensitivity analysis can silently consume nonsense rather than fail.
This is a regression introduced by the rebuild and is not visible in the
old-versus-new comparison, which checks only `filings_count`.

**Required remediation:** set the rate to `NA_real_` unless the denominator is
finite and strictly positive. Add an invariant that no row with a nonpositive or
missing denominator may have a finite rate. Compare every analytical column—not
only filings—against the pre-fix file during rebuild QA.

### 2. Critical: state-month balance does not imply a stable reporting geography

At `data_prep/rebuild_state_month_panel.R:75-85`, each state-month is the sum of
whatever county rows happen to be present that month. No rule fixes the county
basket or rejects large composition changes. The main pretrends workflow then
checks only the number and common presence of state-month rows at
`analysis/pretrends/pretrends_statepanel_template.R:327-338` and
`:489-496`, while its default outcome is log filings count at `:514-516`.

The 25-state rebuilt pretrends sample therefore treats materially different
geographic baskets as a balanced panel. High-signal examples within the
2016–2024, COVID-excluded analysis horizon are:

| State/month | Reporting change | Denominator change | Analytical concern |
|---|---:|---:|---|
| TX, Jun 2024 | 11 to 9 counties | -48.3% | Harris and Bowie disappear; TX is a never-treated control |
| FL, Jan 2024 | 8 to 6 counties | -45.2% | Miami-Dade and Lee disappear one month after the Dec 2023 online treatment date |
| TN, Mar–Apr 2024 | 34 to 12 to 3 counties | -26.3%, then -24.9% | large artificial count shocks remain in a treated state |
| GA, Jun 2024 | 3 to 2 counties | -32.3% | Bibb disappears from a never-treated control |
| WV, Jan 2023 | 42 to 54 counties | +38.9% | basket expansion creates a positive count shock |
| UT, Nov 2023–Jan 2024 | 18 to 9 to 8 to 21 counties | irregular | filings collapse 711 to 49, then recover to 725; rate also moves by about -2.5 then +2.0 log points |

These are not missing state-months, so both coverage guards pass. In the current
headline sample, FL, TN, and other affected states are treated, while TX, GA,
UT, MN, and others are controls. The composition changes can therefore load
directly into event-time contrasts.

**Why it matters:** removing double addition does not make a varying partial-
county sum a comparable state outcome. The current post-rebuild ATT and pretrend
results cannot be called clean until this is addressed.

**Required remediation:** construct a fixed county basket within each estimation
window, or use a rate/offset design with valid denominators plus explicit basket
stability rules. At minimum, fail on large month-to-month denominator changes,
export added/dropped county lists, and exclude or censor known partial tail
months. Re-evaluate FL around December 2023 and TX/GA/UT as controls before
citing the rebuilt state result.

### 3. High: the rebuild is non-idempotent and can erase its only pre-fix evidence

The script reads the current canonical panel as `old` at
`data_prep/rebuild_state_month_panel.R:71-73`, uses that same object as the source
for all `KEEP_OLD` states at `:92-101`, and overwrites a fixed-name backup at
`:135-137`. The backup is ignored by Git (`deprecated/` in `.gitignore`). A
second run now would overwrite the true double-counted backup with the already
rebuilt panel, destroy the meaningful old-versus-new comparison, and make the
carried-state lineage circular.

**Required remediation:** make each source explicit and immutable. Refuse to
overwrite an existing pre-fix snapshot; record a SHA-256 checksum; read NH, WI,
MD, and ETS-only states from their actual source artifacts; write the canonical
panel atomically only after all assertions pass.

### 4. High: the audit script is stale after the fix and does not test its own label

`analysis/diagnostics/statepanel_double_count_audit.R:77-80` reads the current
canonical panel, not the preserved pre-fix panel. At `:89-96`, it calls every
county-plus-ETS overlap “double counted” without requiring the identity residual
to be near zero. If rerun now, it will inspect the corrected file yet still count
overlaps as `n_double_counted_months`. Its saved output already includes WI as
affected for 25 months even though WI has 0% exact identity and was not changed by
the rebuild.

The documentation's “916/916 exact” claim is also incorrect. The rebuild's own
changed-row counts sum to **891** exact added state-months across the 12 changed
states: DE/IN/MN/PA/VA (85 each), CT (73), AZ/OH/SC/TN/TX (69 each), and FL
(48). The extra 25 are the non-exact WI overlaps.

**Required remediation:** parameterize the diagnostic input and default it to an
immutable pre-fix snapshot; distinguish “source overlap” from “verified additive
construction”; require `abs(resid) < tolerance` for the latter; assert the
expected affected-state set and count. Regenerate documentation from the
verified table.

### 5. High: the “pure duplicate/statewide” proof uses ever-observed, not simultaneous, coverage

At `analysis/diagnostics/statepanel_double_count_audit.R:65-66`, coverage is the
number of counties observed at least once over the entire file. That statistic is
then divided by the state's county count and converted into a “county download
already statewide → PURE DUPLICATE” diagnosis at `:100-105`.

This does not establish statewide monthly coverage. Minnesota has all 87 counties
at some point, but only 18–75 in any one month (54–75 in the current headline
COVID-excluded window). Virginia reaches at most 123 of 133, and several other
states also have time-varying coverage. Moreover, the “100% exact identity” in
the output proves that the old panel equals `county + ETS`; it does not prove
that the county and ETS components measure identical geography. Their levels are
not equal in most states. For partial city-source states, the ETS aggregate both
overlaps some included counties and can add places absent from the county file.

**Required remediation:** report monthly coverage distributions and explicit
geography overlap. Do not label a source pure duplicate solely from ever-seen
coverage or from the algebraic construction of the old panel.

### 6. Medium: Maryland provenance is mislabeled

At `data_prep/rebuild_state_month_panel.R:100` and in the source table, Maryland
is labeled `md_socrata_warrant_petitions`. The actual repair states that the
active source is Maryland Judiciary monthly Landlord/Tenant complaint filings
parsed from annual-statistics PDFs and explicitly supersedes the Socrata
post-judgment warrant extract (`data_prep/monthly_panel_expansion/07_merge_md_into_panel.R:3-12`).

**Why it matters:** the two sources measure different stages of the eviction
process. The current values appear to have been preserved correctly, but the
metadata states the wrong estimand.

**Required remediation:** rename the provenance value to the actual Judiciary
LT-filings source and include source artifact/version fields.

### 7. Medium: rebuild QA compares only filings and therefore missed analytical regressions

The comparison at `data_prep/rebuild_state_month_panel.R:119-140` retains only
old and new filing counts. It does not compare renter denominators, rates,
treatment dates/coding, source labels, or reporting-count changes. This is why
the 404 newly fabricated finite rates can coexist with a clean-looking source
table.

**Required remediation:** produce field-level change counts and explicit
invariants for keys, filings, denominators, rates, treatment dates, source,
coverage, and missingness. Fail on an unexpected change rather than printing a
summary after the canonical file is already overwritten.

## Verified positives

- The fix covers the full 12-state exact-addition set, not only MN and TX.
- The current canonical state-month key is unique and all core values are
  finite/nonnegative; treatment dates are state-constant and match the repaired
  online schedule; `treated` is internally consistent with those dates.
- The county input has no duplicate county-month keys, so the new aggregation is
  not currently multiplying rows.
- The current Handle-50 panel has unique keys and, for all 3,790 retained rows,
  its filings, denominator, and rate fields match the rebuilt canonical panel.
  FL and NV are the only canonical states omitted, as intended by its exposure
  classification.

## Minimum release gate before trusting the rebuilt state panel

1. Correct the zero-denominator rate construction and rebuild immediate derived
   panels.
2. Replace the current state-month presence check with geography-composition QA;
   decide on a fixed-basket or valid-rate estimand.
3. Resolve/censor the 2023–2024 partial tails, especially FL, TN, TX, GA, and UT.
4. Make the rebuild and diagnostic immutable/idempotent and correct the 891-row
   documentation.
5. Correct Maryland provenance and add full-field change assertions.
6. Only then rerun and interpret state-level pretrends or state-level power work.

## Assumptions and exclusions

- This audit treats the intended grain as one comparable state-month outcome.
- It does not judge the still-unfixed simulation construction or simulation
  outputs, per the user's narrowed scope.
- It validates treatment-schedule consistency inside the repository but does not
  externally re-research each legalization date.
