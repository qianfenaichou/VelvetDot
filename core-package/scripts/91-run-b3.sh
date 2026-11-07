#!/usr/bin/env bash
# =============================================================================
# B3 / 基线链最小作业：只跑 perf_base_chain 一个用例（不走 20-run --full）
# 目的：产出 L_base_chain（VL=8、rdcycle 中位数、合并 ≥2000 样本）
# 机时：P3-full（单用例、短 walltime；不是全量 --full）
# 口径：默认用 perf_base_chain_min.bin（4 轮 × 500 = 2000 合并样本，CHAIN_MIN 口径）。
#       本用例 full 尺度（8 轮 × 2000=16000 样本）的 perf_base_chain.bin 在昆山单轮就要数分钟、
#       整套 >1 机时（实测 job 126749121 在 600s 内只走完 round 0），会吃掉整个 P3 预算；
#       需要 full 尺度时显式 IMG=.../perf_base_chain.bin 并给足 --time。
#       注意：本脚本与 perf_base_chain 的数字都是**内部自设口径**，不得写成「官方口径」
#         （用例头注 design/verify/cases/perf_base_chain.c:55-56）。
# 用法：sbatch -p kshcnormal -N 1 -n 8 --time=00:15:00 scripts/91-run-b3.sh
# 产物：results/difftest/b3/91-b3-<runid>.log
# 判据：日志含 `PERF_BASE_CHAIN verdict=ALL_OK`，且 `VDOT_METRIC L_base_chain <n>` 可解析
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法错误
# =============================================================================
set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
IMG="${IMG:-$CORE_DIR/test/bin/perf_base_chain_min.bin}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-600}"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺镜像：$IMG" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
OUT_DIR="$CORE_DIR/results/difftest/b3"
LOG="$OUT_DIR/91-b3-$RUN_ID.log"
mkdir -p "$OUT_DIR"
IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1 || true)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1 || true)"
# 头行把镜像/emu 的 md5 一起打出来（复核要求：日志必须自带 provenance，事后不再靠「另跑一次 md5sum」推定）。
# 历史日志（2026-11-04 之前）没有这两个字段，其 provenance 另见 results/difftest/b3/provenance/91-b3-provenance.txt。
echo "===== job=$SLURM_JOB_ID host=$(hostname) emu=$EMU emu_md5=${EMU_MD5:-NA} img=$IMG img_md5=${IMG_MD5:-NA} $(date '+%F %T') =====" | tee -a "$LOG"

timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG" --max-instr="$MAX_INSTR" >>"$LOG" 2>&1
rc=$?
echo "===== emu rc=$rc log=$LOG =====" | tee -a "$LOG"

grep -aE '^(PERF|VDOT_METRIC|PERF_BASE_CHAIN|HIT )' "$LOG" | tee -a "$LOG"

if grep -aq 'PERF_BASE_CHAIN verdict=ALL_OK' "$LOG" && grep -aqE '^VDOT_METRIC L_base_chain [0-9]+' "$LOG"; then
  echo "[OK] B3 用例达标（verdict=ALL_OK，L_base_chain 可解析）" | tee -a "$LOG"
  exit 0
fi
echo "[FAIL] B3 用例未达标（verdict 或 L_base_chain 缺失）" | tee -a "$LOG"
exit 1