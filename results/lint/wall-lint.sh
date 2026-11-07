#!/usr/bin/env bash
# 2.2 lint 第三档：verilator --lint-only -Wall（打开告警集合，不带 -Wno-fatal）
set -uo pipefail
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
hash -r
RTL=$(ls -d "$HOME"/core/src/*/build/rtl 2>/dev/null | head -1)
OUT="$HOME/core/results/lint"
mkdir -p "$OUT"
TS=$(date '+%Y%m%dT%H%M%S')
LOG="$OUT/25-wall-lint-$TS.log"
echo "===== job=${SLURM_JOB_ID:-} host=$(hostname) rtl=$RTL $(date '+%F %T') =====" | tee -a "$LOG"
verilator --version 2>&1 | head -1 | tee -a "$LOG"
echo "CMD: verilator --lint-only -Wall --top-module <top> <files>" | tee -a "$LOG"
run() {
  local top="$1"; shift
  local f rc errs warns
  f="$OUT/25-wall-$top-$TS.log"
  timeout 300 verilator --lint-only -Wall --top-module "$top" "$@" >"$f" 2>&1
  rc=$?
  errs=$(grep -c '%Error' "$f" || true)
  warns=$(grep -c '%Warning' "$f" || true)
  echo "top=$top rc=$rc %Error=${errs} %Warning=${warns} raw=$f lines=$(wc -l <"$f")" | tee -a "$LOG"
  sed -n '1,60p' "$f" | sed 's/^/  | /' | tee -a "$LOG"
}
run VdotReduce "$RTL/VdotReduce.sv" "$RTL/CSA_Nto2With3to2MainPipeline_5.sv" "$RTL/CSA4to2_15.sv"
run VIMac64b "$RTL/VIMac64b.sv"
echo "===== done =====" | tee -a "$LOG"
