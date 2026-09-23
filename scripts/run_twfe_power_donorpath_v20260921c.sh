#!/usr/bin/env bash
# Pass-3 launcher: code-review fixes (wild seeding, Q3 yhat<-0, DF_CORRECT,
# wild_failed reporting, EXCLUDE_STATES) + WA/MN exclusion sensitivity.
# See quality_reports/plans/2026-09-21_twfe_donorpath_power_sim.md, "## Pass 3".
#
# Does NOT touch pass-1 (_v20260921/) or pass-2 (_v20260921b/) outputs.
# All outputs go to output/twfe_power_donorpath_v20260921c/.
#
# Runs are grouped into STAGE 1 (wild-bootstrap-bearing, slower) and STAGE 2
# (analytic-only, fast) so each `bash` invocation finishes comfortably inside
# a single foreground call.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_BASE="output/twfe_power_donorpath_v20260921c"
mkdir -p "$OUT_BASE"
N_WORKERS="${N_WORKERS:-6}"
SEED=20260921
MN_REASON="MN -- eviction filings incompletely observed in public court records owing to expungement (Minnesota Management and Budget, Evaluation of Emergency Assistance in Minnesota, May 2026, PDF p. 39: expunged since 2020 -- 3.7% of judgments, 26.8% of settled, 50.3% of dismissed); LSC's own refresh revised MN history downward in 99% of 590 revised county-months."
WA_REASON="WA -- Eviction Resolution Pilot Program, mandatory pre-filing dispute resolution for nonpayment cases 2021-11-01..2023-06-30 (SB 5160); Pierce County filings average 167/month under it and 290/month in the year after."
WA_MN_REASON="$WA_REASON | $MN_REASON"

STAGE="${1:-all}"   # all | 1 | 2

run_stage1() {
echo "=== STAGE 1 (wild-bearing): all_states, no_wa_mn, no_wa_mn/s1_rescaled ==="

echo "--- [1a] all_states: main, unscaled, 2000 sims + 1000 wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=2000 RUN_WILD=TRUE N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" SEED=$SEED EXCLUDE_STATES=none OUT_DIR="$OUT_BASE/start202206/all_states" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [1b] no_wa_mn: main, unscaled, EXCLUDE_STATES=WA,MN, 2000 sims + 1000 wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=2000 RUN_WILD=TRUE N_WILD_SIMS=1000 WILD_B=999 \
  EXCLUDE_STATES=WA,MN EXCLUDE_REASON="$WA_MN_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_wa_mn" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [1c] no_wa_mn/s1_rescaled: RESCALE_DONORS=TRUE, 2000 sims + 1000 wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=TRUE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 MIN_DONOR_OWN_OBS=12 N_SIMS=2000 RUN_WILD=TRUE N_WILD_SIMS=1000 WILD_B=999 \
  EXCLUDE_STATES=WA,MN EXCLUDE_REASON="$WA_MN_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_wa_mn/s1_rescaled" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== STAGE 1 DONE ==="
}

run_stage2() {
echo "=== STAGE 2 (analytic-only, fast): df_correct, loo, no_wa, no_mn, q3_keep_already_treated ==="

echo "--- [2a] no_wa_mn/df_correct: DF_CORRECT=TRUE, 2000 sims, no wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 DF_CORRECT=TRUE N_SIMS=2000 RUN_WILD=FALSE \
  EXCLUDE_STATES=WA,MN EXCLUDE_REASON="$WA_MN_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_wa_mn/df_correct" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [2b] no_wa_mn/loo: leave-one-eligible-donor-out, 400 sims/donor, no wild ---"
SCENARIO=start202206 RUN_MODE=loo RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 LOO_N_SIMS=400 N_SIMS=2000 RUN_WILD=FALSE \
  EXCLUDE_STATES=WA,MN EXCLUDE_REASON="$WA_MN_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_wa_mn/loo" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [2c] no_wa: EXCLUDE_STATES=WA, 2000 sims, no wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=2000 RUN_WILD=FALSE \
  EXCLUDE_STATES=WA EXCLUDE_REASON="$WA_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_wa" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [2d] no_mn: EXCLUDE_STATES=MN, 2000 sims, no wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=2000 RUN_WILD=FALSE \
  EXCLUDE_STATES=MN EXCLUDE_REASON="$MN_REASON" \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/no_mn" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "--- [2e] all_states/q3_keep_already_treated: DROP_ALREADY_TREATED=FALSE, 1000 sims, no wild ---"
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=FALSE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=1000 RUN_WILD=FALSE \
  N_WORKERS="$N_WORKERS" SEED=$SEED EXCLUDE_STATES=none OUT_DIR="$OUT_BASE/start202206/all_states/q3_keep_already_treated" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== STAGE 2 DONE ==="
}

case "$STAGE" in
  1) run_stage1 ;;
  2) run_stage2 ;;
  all) run_stage1; run_stage2 ;;
  *) echo "Usage: $0 [1|2|all]"; exit 1 ;;
esac

echo "=== ALL REQUESTED STAGES DONE. Outputs in $OUT_BASE ==="
