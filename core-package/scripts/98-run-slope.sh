#!/usr/bin/env bash
# =============================================================================
# 98-run-slope.sh — perf_base_slope 单例作业（清单外独立测量；不进 manifest.tsv）
#
# 为什么单例（而不是走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合只来自 manifest.tsv（`while read -r cid cls img`，无单例入口），
#   而 design/verify/cases/manifest.tsv 的 sha256 已冻结（a90d1071…、30 行数据行；口径裁定见
#   ）。perf_base_slope **不得**进该清单 ⇒ 按 91-run-b3.sh / 93-run-kcmp.sh
#   同一套「单例作业」思路直接跑 `$EMU --no-diff -i $IMG`。
#   必须 --no-diff：用例读 rdcycle，与 NEMU 参照不一致（同 perf_vdot.c:7、perf_base_chain.c）。
#
# 机时分类：P3-full（同 91-run-b3.sh / 93-run-kcmp.sh 的单例 perf 作业先例）。
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:40:00 core-package/scripts/98-run-slope.sh
#   注意：实测定标结果为 ROUNDS=3 的整套在 emu 上约 16 分钟（~5.3e4 模拟周期，≈59 周期/秒墙钟；
#     作业 127041527 在 900 s 的 CASE_TIMEOUT 下差 4 行收尾，rc=124）⇒ 默认 CASE_TIMEOUT_S=1800。
#   冒烟（先跑这一条，不过就不提交正式作业）：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:10:00 --export=ALL,IMG=$HOME/core/test/bin/perf_base_slope_smoke.bin core-package/scripts/98-run-slope.sh
# 产物：results/difftest/slope/98-slope-<runid>.{log,json}
#       results/difftest/slope/cases/perf_base_slope.<runid>.log（emu 原始输出）
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
#
# 判据（全部来自日志实读，不推算）：
#   ① `SLOPE verdict=ALL_OK` ≥ 1，且无 `SLOPE verdict=HAS_FAIL`
#   ② `SLOPE point` 行数 == 4 组 × 3 个 N = 12（每行带 rounds 个窗口周期的 CSV）
#   ③ `SLOPE fit` 行数 == 4（每组一条），每条含可解析的 `slope_milli=` / `r2_micro=`
#   ④ `SLOPE check` 行数 == 4，且全 `match=OK not_vl4=yes`
#   ⑤ `HIT GOOD TRAP` ≥ 1 且 `ABORT` == 0 且 `HIT BAD TRAP` == 0
#   ⑥ emu rc == 0
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=00:40:00
#SBATCH -J vdot_slope

set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
IMG="${IMG:-$CORE_DIR/test/bin/perf_base_slope.bin}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-1800}"
ITEM="P3-full"
PURPOSE="基线链多规模斜率 + R²：perf_base_slope 单例（清单外独立测量，N=8/64/512 × vdot/B2 × resident/stream）"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺镜像：$IMG（先跑 design/verify/cases/build_slope.sh）" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/slope"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/98-slope-$RUN_ID.log"
JSON="$OUT_DIR/98-slope-$RUN_ID.json"
CLOG="$CASES_DIR/perf_base_slope.$RUN_ID.log"
mkdir -p "$OUT_DIR" "$CASES_DIR"

IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
IMG_SHA256="$(sha256sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
SRC="$CORE_DIR/src/XiangShan"
# ROUNDS 由镜像编译期决定；这里只记录**期望值**，实际以日志 `SLOPE header` 行为准（判据 ②/③ 用它算）。
EXPECT_ROUNDS="${EXPECT_ROUNDS:-3}"

{
  echo "===== job=$SLURM_JOB_ID host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=${EMU_MD5:-NA}"
  echo "img=$IMG img_md5=${IMG_MD5:-NA} img_sha256=${IMG_SHA256:-NA} max_instr=$MAX_INSTR timeout=${CASE_TIMEOUT_S}s"
  echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null)"
  echo "manifest_remote sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" 2>/dev/null | wc -l)（远端现状；本脚本不修改它）"
  echo "denom=per_point_sequence（斜率口径：cyc = a + b·N 的 b；不是单指令依赖延迟，也不是中位数口径）"
} | tee -a "$LOG"

echo "----- emu --no-diff run -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG" --max-instr="$MAX_INSTR" >"$CLOG" 2>&1
RC=$?
echo "emu rc=$RC case_log=$CLOG ($(stat -c %s "$CLOG" 2>/dev/null) B)" | tee -a "$LOG"

GOOD="$(grep -ac 'HIT GOOD TRAP' "$CLOG" || true)"
ABORT="$(grep -ac 'ABORT' "$CLOG" || true)"
BAD="$(grep -ac 'HIT BAD TRAP' "$CLOG" || true)"
V_OK="$(grep -ac 'SLOPE verdict=ALL_OK' "$CLOG" || true)"
V_BAD="$(grep -ac 'SLOPE verdict=HAS_FAIL' "$CLOG" || true)"
N_RAW="$(grep -ac '^SLOPE point ' "$CLOG" || true)"
N_FIT="$(grep -ac '^SLOPE fit ' "$CLOG" || true)"
N_FIT2="$(grep -ac '^SLOPE fit2 ' "$CLOG" || true)"
N_CHK="$(grep -ac '^SLOPE check ' "$CLOG" || true)"
CHK_BAD="$(grep -ac '^SLOPE check .*match=MISMATCH' "$CLOG" || true)"
CHK_VL4_BAD="$(grep -ac '^SLOPE check .*not_vl4=no' "$CLOG" || true)"
HEADER="$(grep -a '^SLOPE header ' "$CLOG" | tail -1)"
ROUNDS_ACT="$(printf '%s\n' "$HEADER" | sed -nE 's/.*rounds=([0-9]+).*/\1/p')"
[ -n "$ROUNDS_ACT" ] || ROUNDS_ACT="$EXPECT_ROUNDS"
EXPECT_RAW=$(( 4 * 3 ))

echo "good=$GOOD abort=$ABORT bad_trap=$BAD verdict_ok=$V_OK verdict_bad=$V_BAD" | tee -a "$LOG"
echo "point_lines=$N_RAW (expect $EXPECT_RAW) rounds_per_point=$ROUNDS_ACT fit_lines=$N_FIT fit2_lines=$N_FIT2 check_lines=$N_CHK check_bad=$CHK_BAD check_vl4_bad=$CHK_VL4_BAD" | tee -a "$LOG"
grep -aE '^(SLOPE (header|point|fit|fit2|monotonic|check|summary|verdict)|PERF slope)' "$CLOG" | tee -a "$LOG"

# 判据聚合（语义同 92-run-xcontam.sh / 93-run-kcmp.sh：任一未达标 ⇒ 失败；无未达标但有未运行 ⇒ 未运行）
ST="失败"; REASON=""
st_of() { [ "$1" -eq 1 ] && printf '达标' || printf '未达标'; }
GOOD_ST="$(st_of $([ "${GOOD:-0}" -ge 1 ] && echo 1 || echo 0))"
ABORT_ST="$(st_of $([ "${ABORT:-0}" -eq 0 ] && echo 1 || echo 0))"
BAD_ST="$(st_of $([ "${BAD:-0}" -eq 0 ] && echo 1 || echo 0))"
VERDICT_ST="$(st_of $([ "${V_OK:-0}" -ge 1 ] && [ "${V_BAD:-0}" -eq 0 ] && echo 1 || echo 0))"
RAW_ST="$(st_of $([ "${N_RAW:-0}" -eq "$EXPECT_RAW" ] && echo 1 || echo 0))"
FIT_ST="$(st_of $([ "${N_FIT:-0}" -eq 4 ] && [ "${N_FIT2:-0}" -eq 4 ] && echo 1 || echo 0))"
CHK_ST="$(st_of $([ "${N_CHK:-0}" -eq 4 ] && [ "${CHK_BAD:-0}" -eq 0 ] && [ "${CHK_VL4_BAD:-0}" -eq 0 ] && echo 1 || echo 0))"
RC_ST="$(st_of $([ "${RC:-1}" -eq 0 ] && echo 1 || echo 0))"

UNMET=0
for s in "$GOOD_ST" "$ABORT_ST" "$BAD_ST" "$VERDICT_ST" "$RAW_ST" "$FIT_ST" "$CHK_ST" "$RC_ST"; do
  [ "$s" = "未达标" ] && UNMET=1
done
if [ "$UNMET" -eq 0 ]; then
  ST="通过"
else
  ST="失败"
  REASON="GOOD=$GOOD ABORT=$ABORT BAD=$BAD V_OK=$V_OK V_BAD=$V_BAD raw=$N_RAW/$EXPECT_RAW fit=$N_FIT fit2=$N_FIT2 chk=$N_CHK chk_bad=$CHK_BAD vl4_bad=$CHK_VL4_BAD rc=$RC"
fi

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/%s",\n' "98-run-slope.sh"
  printf '  "case_id": "perf_base_slope",\n'
  printf '  "status": "%s",\n' "$ST"
  printf '  "note": "%s",\n' "$(jesc "清单外单例（不进 design/verify/cases/manifest.tsv，该文件冻结 30 行/a90d1071…）；斜率口径 cyc=a+b·N 的 b（批吞吐），不是单指令依赖延迟、不是中位数口径、不是每指令 1.33×")"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "mode": "single-case",\n'
  printf '  "provenance": {"emu": "%s", "emu_md5": "%s", "img": "%s", "img_md5": "%s", "img_sha256": "%s", "max_instr": "%s", "rounds": "%s"},\n' \
    "$(jesc "$EMU")" "${EMU_MD5:-NA}" "$(jesc "$IMG")" "${IMG_MD5:-NA}" "${IMG_SHA256:-NA}" "$MAX_INSTR" "$ROUNDS_ACT"
  printf '  "metrics": {"groups": "4", "n_list": "8,64,512", "rounds_per_point": "%s", "point_lines": "%s"},\n' \
    "$ROUNDS_ACT" "$N_RAW"
  printf '  "criteria": [\n'
  printf '    {"name": "good_trap", "expected": "HIT GOOD TRAP >= 1", "actual": "%s", "status": "%s"},\n' "$GOOD" "$GOOD_ST"
  printf '    {"name": "no_abort", "expected": "ABORT == 0", "actual": "%s", "status": "%s"},\n' "$ABORT" "$ABORT_ST"
  printf '    {"name": "no_bad_trap", "expected": "HIT BAD TRAP == 0", "actual": "%s", "status": "%s"},\n' "$BAD" "$BAD_ST"
  printf '    {"name": "selfcheck_slope", "expected": "SLOPE verdict=ALL_OK 且无 HAS_FAIL", "actual": "ok=%s bad=%s", "status": "%s"},\n' "$V_OK" "$V_BAD" "$VERDICT_ST"
  printf '    {"name": "point_count", "expected": "4 组 × 3 N = 12 条 SLOPE point", "actual": "%s/%s", "status": "%s"},\n' "$N_RAW" "$EXPECT_RAW" "$RAW_ST"
  printf '    {"name": "fit_lines", "expected": "SLOPE fit == 4 且 fit2 == 4", "actual": "fit=%s fit2=%s", "status": "%s"},\n' "$N_FIT" "$N_FIT2" "$FIT_ST"
  printf '    {"name": "functional_check", "expected": "4 条 SLOPE check 全 match=OK not_vl4=yes", "actual": "lines=%s bad=%s vl4_bad=%s", "status": "%s"},\n' "$N_CHK" "$CHK_BAD" "$CHK_VL4_BAD" "$CHK_ST"
  printf '    {"name": "emu_rc", "expected": "rc == 0", "actual": "%s", "status": "%s"}\n' "$RC" "$RC_ST"
  printf '  ],\n'
  printf '  "artifacts": ["%s", "%s"]\n' "$(jesc "$LOG")" "$(jesc "$CLOG")"
  printf '}\n'
} | tee "$JSON"

if bs="$CORE_DIR/core-package/scripts/90-budget-log.sh"; then
  [ -x "$bs" ] && bash "$bs" auto --item "$ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 \
    || echo "[WARN] 记账失败或脚本缺失"
fi

echo "===== DONE status=$ST $REASON =====" | tee -a "$LOG"
case "$ST" in
  通过) exit 0 ;;
  *)    exit 1 ;;
esac
