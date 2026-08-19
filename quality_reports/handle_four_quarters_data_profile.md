# Data profile: Handle four full quarters after online launch

**Audit date:** 2026-08-14  
**Scope:** Descriptive data audit only. No causal model was estimated.  
**Recommended definition:** The fourth complete calendar quarter after the
operational online-launch quarter, with the launch quarter omitted as a
transition quarter.

## Bottom line

For the comparison that is consistent with the **April 2022--December 2024
balanced eviction panel**, five post-COVID online adopters have a fourth full
quarter observed by the study cutoff: **Kansas, Maryland, Ohio, Kentucky, and
Maine**. Across those states, the median fourth-quarter Handle is:

- **$536.5 million over three months**;
- **$178.85 million per month**; and
- **69.6% of the state's fixed pre-2025, online-era, non-COVID monthly peak**.

This is the clean number to pair with an eviction design ending in December
2024. The sample is only five states, so it should be presented as a descriptive
first-stage fact rather than a stable population parameter.

If later Handle observations through May 2026 are allowed while the denominator
remains frozen at its pre-2025 value, Delaware and Vermont can also be included.
The seven-state median then falls to **$393.4 million per quarter**, **$131.14
million per month**, and **74.4% of the frozen peak**. This mixed-window statistic
is reproducible but is not aligned with the eviction outcome cutoff.

## Definition and denominator

Let the launch quarter be the calendar quarter containing the project's
`online_start_date`. Because the source records launch only to the month and
launch-quarter exposure varies across states, the recommended construction is:

1. omit the launch quarter as a transition quarter;
2. call the next calendar quarter the first full quarter; and
3. define the fourth full quarter as the quarter beginning 12 months after the
   start of the launch quarter.

The denominator is the maximum positive monthly Handle from the operational
online-launch month through December 2024, excluding March 2020--July 2021. This
matches the project Handle-50 calibration convention: **online-era,
non-COVID, and capped before 2025**. The numerator is the average of all three
reported months in the fourth full quarter; incomplete quarters are not
prorated.

“Four quarters after legalization” is otherwise ambiguous:

| Interpretation | Event-month content | All-state median quarter Handle | Median share of peak |
|---|---|---:|---:|
| Fourth post-launch three-month block | Months 9--11 | $447.3m | 43.5% |
| Fourth full calendar quarter | Varies by launch month | $536.5m | 50.5% |
| Event quarter +4 | Months 12--14 | $729.3m | 62.8% |

The full-calendar-quarter definition is preferred because it maps directly to
non-overlapping quarterly eviction outcomes and does not combine different
calendar months within a state-quarter. It is also the rule already recommended
in the quarterly strategy memo.

## Source profile and integrity checks

| Source | Grain and coverage | Key audit result |
|---|---|---|
| LSR Handle CSV | 2,270 unique state-month rows; 35 states; June 2018--May 2026 | No duplicate state-month keys; Handle is total reported Handle |
| Legalization schedule | 38 state rows; 31 online dates | 30 online launches occur by December 2024 |
| Raw eviction panel | 4,120 unique state-month rows; 39 states | Post-COVID exact balance yields 30 states x 33 months |

For all 29 scheduled online states with Handle data and launches by December
2024, the first online-era Handle observation is in the recorded operational
launch month. Thus the launch-month joins have zero observed lags and no
pre-launch leakage after applying the online-era filter.

Florida is the sole scheduled online state launched by the cutoff with no LSR
Handle series. It must remain missing in Handle summaries and must not be coded
as zero or as an untreated state. Nebraska and Nevada appear in LSR but not in
the schedule; Nevada is a pre-sample market, and neither enters this online-date
descriptive universe. Retail-only Handle states likewise do not enter.

## All eligible online states

Using the latest Handle file, all 29 non-Florida online states launched by
December 2024 have three reported months in their fourth full quarter. This
count includes Delaware, Vermont, and North Carolina, whose relevant quarter is
2025Q1. Across the 29 states:

| Statistic | Median | Interquartile range |
|---|---:|---:|
| Three-month Handle | $536.5m | $100.0m--$1.357b |
| Average monthly Handle | $178.85m | $33.33m--$452.31m |
| Share of fixed pre-2025 peak | 50.5% | 33.1%--71.2% |
| Ratio to first full-quarter total | 1.37x | 1.09x--1.81x |

If the fourth quarter itself must also end by December 2024, the all-state
sample is 26 states: the median is **$629.9 million per quarter**, **$209.95
million per month**, and **45.9% of peak**. The three excluded late windows are
Delaware, Vermont, and North Carolina; Florida remains absent for missing
Handle.

## Balanced post-COVID eviction-panel cohorts

Applying the exact panel construction to `state_month_panel_with_treatment.csv`
gives 30 states observed in every month from April 2022 through December 2024.
Eight of those states adopt online betting in that interval:

| State | Online launch | Fourth full quarter | Handle status by study cutoff |
|---|---:|---:|---|
| Kansas | 2022-09 | 2023Q3 | Complete |
| Maryland | 2022-11 | 2023Q4 | Complete |
| Ohio | 2023-01 | 2024Q1 | Complete |
| Kentucky | 2023-09 | 2024Q3 | Complete |
| Maine | 2023-11 | 2024Q4 | Complete |
| Florida | 2023-12 | 2024Q4 | No LSR Handle series |
| Delaware | 2024-01 | 2025Q1 | After eviction-study cutoff |
| Vermont | 2024-01 | 2025Q1 | After eviction-study cutoff |

Massachusetts and North Carolina are post-COVID online adopters but do not enter
the exact balanced panel: each has only 20 and 15 of the required 33 eviction
months, respectively.

The five cutoff-aligned complete cases have a fourth-quarter interquartile range
of **$393.4 million--$1.594 billion** and a peak-share interquartile range of
**59.3%--83.0%**. Their median fourth-quarter total is about **1.32 times** their
first full-quarter total.

## Retail and measurement limitations

The LSR field is **total state Handle**. It does not separate retail from online
Handle. Thirteen of the 29 complete all-state cases legally had retail betting
before online launch; 12 have 176 raw pre-online Handle rows totaling about
$2.00 billion. Those rows must be excluded from online-era peaks and ramp-up
windows. In this snapshot they do not change which month is the corrected
non-COVID peak, but retaining them would make the definition conceptually wrong
and fragile to future revisions.

COVID exclusion matters for Rhode Island: its raw maximum is November 2020,
inside the excluded interval, while its project-consistent non-COVID peak is
January 2023. A peak calculation that merely caps at December 2024, without the
online-era and COVID filters, is therefore not project-consistent.

The dollar medians also conflate market maturation with state population.
Percent-of-state-peak is better for describing ramp-up, but it uses a future
within-window benchmark and is descriptive only. Neither measure identifies a
causal effect of an additional dollar of betting.

## Data-quality judgment

- **High severity, high confidence:** Florida has no Handle series. Treating it
  as zero or untreated would misclassify exposure.
- **High severity, high confidence:** A seven-state post-COVID median uses 2025
  Handle for Delaware and Vermont while the outcome panel ends in 2024. Use the
  five-state cutoff-aligned statistic for design discussion.
- **Medium severity, high confidence:** Total Handle mixes retail and online
  channels for retail-before-online states.
- **Medium severity, high confidence:** A naive pre-2025 peak that does not
  exclude COVID gives Rhode Island the wrong denominator.
- **Low severity, high confidence:** The online launch-month join itself is
  clean for every scheduled state with Handle data.

## Reproduction formula

The audit used only the three raw files named above. State-month keys were
checked for uniqueness; dates were converted to month starts; the legalization
schedule was joined by full state name; all Handle observations before the
online launch were removed; peaks were restricted to positive, non-COVID
online-era months through December 2024; and quarters were retained only when
all three component months were observed. Cross-state summaries use medians
because absolute Handle is strongly right-skewed.
