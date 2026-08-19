# County CS MDE — Adaptive Search Production Report

**Date:** 2026-08-19 (overnight run)
**Run:** `output_blinded_power/county_cs_adaptive/` (config
`config/power_county_cs_adaptive.yml`; scenario
`S53c7f22747_headline_county_nb_step` — county / S2 / D1 panel-template /
count_nb / step / y_log1p / notyettreated; `cs_safe_patches: true`,
`cs_faster_mode: false`; 250 reps; base_seed 20260723)
**Machinery:** `R/power/adaptive_mde.R` (adaptive/sequential grid, every cell a
genuine full estimate — built and validated tonight per
`quality_reports/plans/2026-08-19_adaptive-cs-mde-search.md` after the
2026-08-18 review barred shift-mode synthesis for the headline CS MDE)

---

## Bottom line

**The two bootstrap inference arms are SIZE-VALID but NOT calibrated
(SE/SD ≈ 1.74, 95–97% coverage at nominal 95%, and a biased point estimate);
analytic inference fails outright (61.2% size, 39% coverage). For both
size-valid arms the power curve is FLAT — power ≈ size at every evaluated
effect, including a 22% effect (δ = 0.20) at full replication. The verdict is
`never_crosses_target`: no defensible finite MDE can be extrapolated from
this design; the design has essentially no power against any effect on the
pre-registered grid.** In real-world terms, the boot arm's mean 95% CI is
≈ 1.85 log points wide — roughly **[−60%, +150%] in filings** — so CS with
size-valid inference cannot detect any policy-plausible eviction effect at
county level and is not usable as the headline estimator. (Do not read this
as "the MDE sits a little above 0.20.")

## 1. Size gate (δ = 0, 250 replications, zero estimation failures per arm)

| Arm | Rejection @ nominal 5% | Wilson 95% CI | Gate [2.5%, 10%] | Verdict |
|---|---|---|---|---|
| analytic | 153/250 = **61.2%** | [55.0%, 67.0%] | outside (above) | **FAIL** |
| boot (genuine multiplier) | 11/250 = **4.4%** | [2.5%, 7.7%] | inside | **PASS** |
| boot_t (t on bootstrap SE) | 8/250 = **3.2%** | [1.6%, 6.2%] | inside | **PASS** |
| jack (CV3) | — not run at county — | — | — | untested |

Failure-rate criterion (≤5%): all arms 0% failures — pass. The gate is the
**size criterion of design §14 plus its failure-rate criterion only**; §14's
coverage, bias, and fragility criteria were not implemented by this run, and
the fragility criterion is structurally unmet (single sample S2, single
mechanism count_nb) — see caveats.

Notable reversal vs state level: at state, the multiplier bootstrap
over-rejected badly (boot 24.5%, boot_t 23.0%,
`data/output/cs_cv3_calibration/state/`); at county both bootstrap arms are
inside the gate. County aggregation calibrates CS bootstrap *size* here, the
same direction in which it rescued did2s/didimputation.

## 2. Adaptive MDE search (surviving arms: boot, boot_t)

Search path (grid-index bisection): δ = 0.06 → 0.15 → 0.20, all decisively
below the 0.80 power target; 0.20 (grid max) topped up to the full 250 reps
per the prespecified boundary rule. **Verdict: `never_crosses_target` for
both arms.** No bracket exists, so no MDE point estimate or bootstrap CI is
reported (NA by construction).

Coverage of the grid: δ ∈ {0, 0.20} were estimated at the full 250 reps;
δ ∈ {0.06, 0.15} at 25 reps each (decisively below target); the remaining
7 of 10 positive grid points were never estimated. The never-crosses verdict
extends to them **by monotonicity of the power curve in δ** — an assumption,
well supported by the observed flatness (4–8% everywhere) but not verified
point-by-point.

Power at nominal 5%, by δ (achieved replications in parentheses):

| δ | boot | boot_t | analytic (disqualified) |
|---|---|---|---|
| 0 (250) | 4.4% | 3.2% | 61.2% |
| 0.06 (25) | 8.0% | 4.0% | 80.0% |
| 0.15 (25) | 4.0% | 4.0% | 88.0% |
| 0.20 (250) | **7.2%** [4.6%, 11.1%] | **4.8%** [2.8%, 8.2%] | 90.4% |

Power ≈ size on the entire grid: even a 22% imposed eviction effect
(δ = 0.20 on log1p) is undetectable by calibrated CS inference at county.
The adaptive design evaluated 550 (rep, δ) cells instead of the 2,750 a
brute-force grid needs (5×), with the size gate and the grid-max bound at
full replication.

## 3. Why: the SE mechanics

From `oc_summary.csv` (simple estimand, δ ∈ {0, 0.20} at 250 reps):

- Monte-Carlo SD of the CS ATT: **0.34** (log points) — the design's true
  sampling noise.
- analytic mean SE: 0.079 → **SE/SD = 0.23** (SEs ~4× too small; coverage
  39%) → the 61% false-positive rate.
- boot / boot_t mean SE: ~0.59 → **SE/SD ≈ 1.74** (SEs ~74% too large;
  coverage 95–97%; mean CI width 1.9–2.4 log points). Size lands inside the
  gate, but the intervals are so wide that nothing on the grid rejects.

So neither miscalibration direction yields usable inference: analytic is
invalid (its 39% coverage independently trips §14 criterion 2, the more
damning statistic beyond the 61.2% size); bootstrap is size-valid but
degenerate (a CI ~2 log points wide — [−60%, +150%] in filings — on an
outcome whose plausible effects are ≤ 0.2). Note the asymmetry with the
CV3 jackknife exclusion: `jack` was excluded partly for state-level
over-coverage (0.5% rejection), yet the two reported arms are ALSO
conservative — in interval width rather than rejection rate. The exclusion
stands on compute cost alone; a county CV3 arm would at best deliver the
same kind of uninformative-but-valid bound the boot arms already supply.

## 4. Additional findings that must accompany any use of these numbers

1. **CS point estimates are biased upward under the null on this design
   cell:** mean ATT at δ = 0 is **+0.101** (SD 0.342, n = 250; t ≈ 4.7
   against 0), where the truth is unambiguously 0 — at δ = 0 the
   equal-weighted and group-size-weighted truths coincide, so the unresolved
   truth-weighting caveat does NOT apply to this number. It is a genuine
   property of CS under D1 pseudo-assignment with not-yet-treated controls
   on this cell (and mode-specific: measured under `faster_mode = FALSE`).
   δ > 0 bias columns are NOT reported: they are contaminated by the
   truth-weighting mismatch (2026-08-18 review finding 3, unresolved) and,
   at δ ∈ {0.06, 0.15}, rest on 25 reps. **The bias strengthens the verdict
   rather than undermining it**: the imposed effects are positive and the
   test two-sided, so a +0.10 upward bias adds to the signal and inflates
   power — and power still never approaches 0.80. It does mean the δ = 0
   rejection rate is size under a location-shifted null, so the gate pass is
   weaker evidence than the number alone suggests, and this cell must not be
   reused for any point-estimate claim.
2. **`faster_mode` caveat (§16a, unresolved):** this run used
   `faster_mode = FALSE` (the only mode that estimates on this design); the
   two modes return materially different ATTs on identical data, so CS point
   estimates from this framework remain provisional.
3. **Truth-weighting caveat (2026-08-18 review, finding 3, unresolved):**
   `truth` at δ > 0 is an equal-weighted mean over treated cells, not
   `aggte`'s group-size weights; δ > 0 `bias`/`coverage` columns inherit
   that. Rejection rates and the MDE verdict do not use `truth`.
4. **The gate is permissive, not proof of calibration:** with n = 250 and a
   point-estimate rule, an arm with true size 11% passes with probability
   ≈ 0.3. boot's 4.4% has Wilson CI [2.5%, 7.7%] — consistent with nominal,
   but an arm near the top of the gate would produce MDEs understated
   relative to nominal 5%.
5. **Scope:** this outcome is "the two calibrated CS arms cannot detect
   ≤ 22% effects at county," established on ONE design cell (S2 sample,
   count_nb mechanism, step shape). The CV3 jackknife (`jack`) was **never
   run at county** (prespecified exclusion on compute cost, ~30 att_gt fits
   per rep; state-level evidence 0.5% rejection — over-coverage — was
   supporting, not decisive). A conservative CV3 arm would, at best, deliver
   a valid MDE *upper* bound, which the boot arms already supply in kind.

## 5. Implication for the pre-analysis plan's estimator-selection rule

Under the pre-registered decision rule (size gate → MDE comparison among
survivors), CS at county enters the comparison via its size-valid bootstrap
arms with a **flat power curve and no finite MDE on the pre-registered
grid** — against the calibrated county did2s arm (Type I 4.1%, SE/SD 0.96 in
the corrected-design smoke; MDE in low single digits per the cheap/primary
runs). CS is eliminated on power among size-valid arms, not on size. The PAP
can now state this from genuine full estimates rather than
shifted/synthesized ones. Scope: this is established on ONE design cell
(county / S2 / D1-panel / count_nb / step / not-yet-treated); §14's
fragility criterion (robustness across samples and mechanisms) is
structurally unmet by a single-cell run and any PAP use must say so in the
body, not a footnote.

## 6. Validation provenance (progressive gates, all passed before this run)

1. Decision-core unit tests (Wilson/classification/bisection/top-up/boundary
   verdicts/anomaly) — `tests/testthat/test-adaptive-mde.R`.
2. Full 12-file suite green (multiple times tonight; last after final fixes).
3. Mock end-to-end with a known power curve: recovers the analytic crossing,
   bracket (0.08, 0.10); interrupted-resume reproduces the one-shot result.
4. Cell bit-identity adaptive vs brute force under mocks AND on the real
   state CS estimator (gate 6: 130 visited cells, 16,980 rows, att/se/p/CI/
   truth all exact matches, including genuine bootstrap p-values; identical
   verdicts). `output_blinded_power/_amde_state_check_adaptive/`.
5. County smoke (plumbing + cost: ~28 s per county CS cell).
6. Independent Opus statistical review (2026-08-19), two passes: design
   review before the county search, production-gate review of the final
   result ("no unresolved CRITICAL/MAJOR blocks publication", with framing
   requirements incorporated above). All MAJOR findings were fixed or
   prespecified in Amendment 1 BEFORE the county search phase began —
   provenance: Amendment 1 is in commit `980b201`; the first county search
   cell (δ = 0.06) was appended at 02:20:30 per
   `county_cs_adaptive_run.log`.

**Incidents (both recovered, no statistical impact):** one furrr worker crash
mid-batch (checkpoint design dropped only the torn batch); one resume-key
format bug (padded formatC keys) that discarded 675 deterministic cells,
which were recomputed bit-identically — fixed with normalized keys, a
refuse-to-discard guard, and regression tests.

## 7. Files

- `size_gate.csv`, `mde_adaptive.csv`, `oc_summary.csv`,
  `run_metadata.json`, `adaptive_state_S53c7f22747_….json`,
  `partials/S53c7f22747_….csv` (62,766 result rows; 550 cells)
- Logs: `output_blinded_power/county_cs_adaptive_run{,2,3_finalize}.log`;
  narrative: `quality_reports/adaptive_sim_overnight_log.md`
- The pre-existing `output_blinded_power/county_cs/` (shift-mode partial)
  was never touched.
