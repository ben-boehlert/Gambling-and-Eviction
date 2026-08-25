> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### PRETRENDS RE-RUN + LOTTERY-VINTAGE CONDITIONING (2026-08-21)

**The `+0.080` provisional headline is DEAD — it was a bug, not an estimate.** The
template's own comment (`analysis/pretrends/pretrends_statepanel_template.R:503`)
records that an INTEGER `g` column let `did::att_gt` truncate the never-treated
`Inf` recode to NA, silently dropping every never-treated state, and that this
"inflated the 2026-08-20 headline ATT from +0.029 to +0.080". Fresh runs confirm
it. Current baseline on the rebuilt panel, 26 states (17 treated, 9 never), 16
cohorts, 91 months, 2,366 obs:

| spec | CS ATT | SE | joint pre-trend p | mean abs pre-ATT | max abs pre-ATT |
|---|---|---|---|---|---|
| A unconditional | **+0.020** | 0.057 | 0.170 | 0.0285 | 0.0689 |
| C conditional, lottery BINARY | +0.048 | 0.055 | 0.914 | 0.0285 | 0.0648 |
| B conditional, lottery vintage CONTINUOUS | +0.136 | 0.128 | 0.449 | 0.0602 | 0.2308 |

Outputs: `output/pretrends_lottery_{A_baseline,B_conditional,C_binary}/`.

**Conditioning support added** to the pretrends template: `COVARIATES` (+
`COVARIATE_FILE`) env vars feed `did::att_gt(xformla=)` and, for Sun-Abraham,
covariate-by-period interactions `i(t, X)` (a time-invariant X is otherwise
absorbed by the unit FE). Pre-run copy in `analysis/pretrends/deprecated/`.

**Do NOT condition on lottery vintage as a CONTINUOUS covariate on this panel.**
The damage is not uniform — it is concentrated at e=-2 and e=-1, the event times
with the thinnest not-yet-treated control pools (e=-2 goes +0.021/SE 0.065 ->
-0.231/SE 0.242). Median SE inflation across the rest of the pre-window is only
1.19x. The BINARY indicator conditions stably: mean abs pre-ATT identical to
unconditional (0.0285), max slightly better, ATT +0.048 (SE 0.055). Classic
conditional-PT-with-thin-cells failure, not a reason to abandon conditioning.

**Substantive conclusion is unchanged across all three: no detectable effect.**

**Watch the Sun-Abraham coefficient mask.** `grepl("::")` also matches `i(t, X)`
interaction names (`t::<period>:<var>`), which would sweep 90 interaction
coefficients into the event study and corrupt every pre-trend test. The mask is
now `^[^:]+::-?[0-9]+$`.

