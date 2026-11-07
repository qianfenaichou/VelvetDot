#!/usr/bin/env bash
# =============================================================================
# R13 专项单例 difftest：vdot_xcontam（清单外用例，独立测量）
#
# 为什么需要这份（而不是直接走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合**只来自 manifest.tsv**（`while read -r cid cls img extra`
#   逐行读，`class_selected` 只按 cls 过滤，没有任何「单例 cid」入口）。而
#   design/verify/cases/manifest.tsv 的 sha256 已冻结（本地 a90d1071…、30 行；口径裁定
#   同 perf_base_chain 的「独立测量」先例），
#   vdot_xcontam 必须**不进**该清单。⇒ 本脚本按 91-run-b3.sh 的同一套「单例作业」思路，
#   直接复刻 20-run-difftest.sh:226 的 run_case 调用形态：
#       timeout N  $EMU --diff $REF_SO -i $IMG --max-instr=N
#   判据也随之复刻（正例 = HIT GOOD TRAP ∧ ABORT=0 ∧ 自检通过串在场 ∧ reg_size 一致）。
#
# 机时分类：P0-difftest-smoke（先例 126630806「R13 vdot_mix smoke(6例清单)」）。
#
# 用法：sbatch -p kshcnormal -N 1 -n 8 --time=00:20:00 core-package/scripts/92-run-xcontam.sh
# 产物：results/difftest/r13/92-xcontam-<runid>.log|json + cases/vdot_xcontam.<runid>.log
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=00:20:00
#SBATCH -J vdot_xcontam_r13

set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
REF_SO="${REF_SO:-$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so}"
IMG="${IMG:-$CORE_DIR/test/bin/vdot_xcontam.bin}"
CROSSCHECK="${CROSSCHECK:-$CORE_DIR/verify/cases/xcontam_crosscheck.py}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-900}"
ITEM="P0-difftest-smoke"
PURPOSE="R13 专项：vdot_xcontam 单例 difftest（清单外独立测量）"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$REF_SO" ] || { echo "[FATAL] 缺 NEMU ref .so：$REF_SO" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺镜像：$IMG" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
# started_at 必须是**作业开始**的时刻，不是写 JSON 的时刻（早先版本在写 JSON 时才取 date，
# 与日志头的 09:12:21 差 3 分钟，provenance 语义错位）。因此这里在跑 emu 之前取值并固定。
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/r13"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/92-xcontam-$RUN_ID.log"
JSON="$OUT_DIR/92-xcontam-$RUN_ID.json"
CLOG="$CASES_DIR/vdot_xcontam.$RUN_ID.log"
mkdir -p "$OUT_DIR" "$CASES_DIR"

IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
REF_MD5="$(md5sum "$REF_SO" 2>/dev/null | cut -d' ' -f1)"
SRC="$CORE_DIR/src/XiangShan"

{
  echo "===== job=$SLURM_JOB_ID host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=$EMU_MD5"
  echo "ref_so=$REF_SO ref_md5=$REF_MD5"
  echo "img=$IMG img_md5=$IMG_MD5 max_instr=$MAX_INSTR timeout=${CASE_TIMEOUT_S}s"
  echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null) nemu=$(git -C "$CORE_DIR/src/NEMU" rev-parse --short HEAD 2>/dev/null)"
  # 措辞约束：本行只报**远端文件现状**，不得写成「未改动 = 冻结件」。远端 test/manifest.tsv
  # 实测 31 行 / 413b5796…（比冻结件 design/verify/cases/manifest.tsv 的 30 行 / a90d1071…
  # 多一行 perf_base_chain），本次未改动该文件，但两者**不是同一份**。
  echo "manifest_remote sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" | wc -l)（远端现状；冻结件 design/verify/cases/manifest.tsv = a90d1071…/30 行，本脚本不改动远端该文件）"
} | tee -a "$LOG"

# 与 20-run-difftest.sh 同两条前置判据
NM_HITS="$(nm -a "$REF_SO" 2>/dev/null | grep -cw exec_vdot || true)"
HDR="$(find "$SRC/build" -name 'difftest-state.h' -print -quit 2>/dev/null || true)"
VEC_OK=0
[ -n "$HDR" ] && grep -q 'CONFIG_DIFFTEST_ARCHVECREGSTATE' "$HDR" 2>/dev/null && VEC_OK=1
echo "nm_exec_vdot_hits=${NM_HITS:-0} difftest_state=$HDR vec_reg_compare=$VEC_OK" | tee -a "$LOG"

echo "----- emu --diff run -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --diff "$REF_SO" -i "$IMG" --max-instr="$MAX_INSTR" >"$CLOG" 2>&1
RC=$?
echo "emu rc=$RC case_log=$CLOG ($(stat -c %s "$CLOG" 2>/dev/null) B)" | tee -a "$LOG"

GOOD="$(grep -ac 'HIT GOOD TRAP' "$CLOG" || true)"
ABORT="$(grep -ac 'ABORT' "$CLOG" || true)"
BAD="$(grep -ac 'HIT BAD TRAP' "$CLOG" || true)"
MISMATCH="$(grep -acE 'diff REF|Different operands' "$CLOG" || true)"
REGBAD="$(grep -ac 'is configured with different states than DUT' "$CLOG" || true)"
VERDICT_OK="$(grep -ac 'XCONTAM verdict=ALL_OK fails=0' "$CLOG" || true)"
VERDICT_BAD="$(grep -ac 'XCONTAM verdict=HAS_FAIL' "$CLOG" || true)"
SETUP_BAD="$(grep -ac 'XCONTAM SETUP_BAD' "$CLOG" || true)"
echo "good=$GOOD abort=$ABORT bad_trap=$BAD mismatch=$MISMATCH reg_size_bad=$REGBAD" | tee -a "$LOG"
echo "xcontam_verdict_all_ok=$VERDICT_OK has_fail=$VERDICT_BAD setup_bad=$SETUP_BAD" | tee -a "$LOG"
grep -a 'XCONTAM' "$CLOG" | tee -a "$LOG"

# 金模型 ↔ 用例日志逐行比对（同一脚本的 --check-log；金模型值不手抄）
XCHECK_RC=99; XCHECK_LINE="未运行"
if [ -f "$CROSSCHECK" ]; then
  PY3=/public/software/apps/python/3.8.13/bin/python3
  [ -x "$PY3" ] || PY3="$(command -v python3 || true)"
  if [ -n "$PY3" ]; then
    XCHECK_OUT="$("$PY3" -I "$CROSSCHECK" --check-log "$CLOG" 2>&1)"; XCHECK_RC=$?
    XCHECK_LINE="$(printf '%s' "$XCHECK_OUT" | grep -E 'verdict=LOG_(MATCH|MISMATCH)' | tail -1)"
    echo "----- crosscheck rc=$XCHECK_RC -----" | tee -a "$LOG"
    printf '%s\n' "$XCHECK_OUT" | tee -a "$LOG"
  else
    XCHECK_LINE="未运行（找不到 python3）"
  fi
else
  XCHECK_LINE="未运行（缺 $CROSSCHECK）"
fi

# ---- 判据聚合（复刻 20-run-difftest.sh 正例口径 + 本用例自检串）----
# 聚合语义与 20-run-difftest.sh:563-577 **逐条同构**：任一条 criteria 记「未达标」⇒ status=失败
# （exit 1）；无未达标但任一条记「未运行」⇒ status=未运行（exit 2，全仓规则「未运行不是通过」）。
# 早先版本只判 8 个日志计数、把 reg_size_match / nm_exec_vdot / vec_reg_compare /
# golden_crosscheck 四条 criteria 排除在 ST 之外 ⇒ status=通过 可与「criteria 未达标」并存（已修）。
ST="失败"
REASON=""
XCHECK_ST="未运行"
case "$XCHECK_LINE" in *LOG_MATCH*) XCHECK_ST="达标" ;; *LOG_MISMATCH*) XCHECK_ST="未达标" ;; esac
NM_ST="未达标"; [ "${NM_HITS:-0}" -ge 1 ] && NM_ST="达标"
VEC_ST="未达标"; [ "$VEC_OK" = "1" ] && VEC_ST="达标"
REG_ST="达标"; [ "${REGBAD:-0}" -gt 0 ] && REG_ST="未达标"

# 判据聚合（顺序与下面写进 JSON 的 criteria[] 一一对应，共 9 条；另加 emu 退出码 RC 一条，
# 它不写进 criteria[] 但同样参与聚合——emu 非 0 说明跑崩了，不能记通过）
GOOD_ST="未达标"; [ "${GOOD:-0}" -ge 1 ] && GOOD_ST="达标"
ABORT_ST="未达标"; [ "${ABORT:-0}" -eq 0 ] && ABORT_ST="达标"
BAD_ST="未达标";   [ "${BAD:-0}" -eq 0 ] && BAD_ST="达标"
MIS_ST="未达标";   [ "${MISMATCH:-0}" -eq 0 ] && MIS_ST="达标"
SELF_ST="未达标";  [ "${VERDICT_OK:-0}" -ge 1 ] && [ "${VERDICT_BAD:-0}" -eq 0 ] && SELF_ST="达标"
RC_ST="未达标";    [ "${RC:-1}" -eq 0 ] && RC_ST="达标"
ALL_ST=("$GOOD_ST" "$ABORT_ST" "$BAD_ST" "$MIS_ST" "$SELF_ST" "$REG_ST" "$NM_ST" "$VEC_ST" "$RC_ST" "$XCHECK_ST")
UNRUN=0; UNMET=0
for s in "${ALL_ST[@]}"; do
  [ "$s" = "未运行" ] && UNRUN=1
  [ "$s" = "未达标" ] && UNMET=1
done
if [ "$UNMET" -eq 0 ] && [ "$UNRUN" -eq 0 ]; then
  ST="通过"
elif [ "$UNMET" -eq 0 ]; then
  ST="未运行"; REASON="存在未运行项（golden_crosscheck 等）⇒ 按全仓规则不得记通过"
else
  ST="失败"
  REASON="GOOD=$GOOD ABORT=$ABORT BAD=$BAD MISMATCH=$MISMATCH VERDICT_OK=$VERDICT_OK VERDICT_BAD=$VERDICT_BAD SETUP_BAD=$SETUP_BAD rc=$RC reg=$REG_ST nm=$NM_ST vec=$VEC_ST xcheck=$XCHECK_ST"
fi

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/%s",\n' "$(basename "$0")"
  printf '  "case_id": "vdot_xcontam",\n'
  printf '  "status": "%s",\n' "$ST"
  printf '  "note": "%s",\n' "$(jesc "清单外单例（本脚本不改动远端 test/manifest.tsv，该文件当前为 31 行/413b5796…，比冻结件 design/verify/cases/manifest.tsv 的 30 行/a90d1071… 多一行 perf_base_chain）：20-run-difftest.sh 无单例入口，按 91-run-b3.sh 先例直接复刻其 run_case 调用形态")"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "machine_hours_planned": 0.1,\n'
  printf '  "mode": "single-case",\n'
  printf '  "provenance": {"emu": "%s", "emu_md5": "%s", "ref_so": "%s", "ref_md5": "%s", "img": "%s", "img_md5": "%s", "max_instr": "%s"},\n' \
    "$(jesc "$EMU")" "$EMU_MD5" "$(jesc "$REF_SO")" "$REF_MD5" "$(jesc "$IMG")" "$IMG_MD5" "$MAX_INSTR"
  printf '  "criteria": [\n'
  printf '    {"name": "good_trap", "expected": "HIT GOOD TRAP >= 1", "actual": "%s", "status": "%s"},\n' "$GOOD" "$GOOD_ST"
  printf '    {"name": "no_abort", "expected": "ABORT == 0", "actual": "%s", "status": "%s"},\n' "$ABORT" "$ABORT_ST"
  printf '    {"name": "no_bad_trap", "expected": "HIT BAD TRAP == 0", "actual": "%s", "status": "%s"},\n' "$BAD" "$BAD_ST"
  printf '    {"name": "no_diff_mismatch", "expected": "diff REF/Different operands == 0", "actual": "%s", "status": "%s"},\n' "$MISMATCH" "$MIS_ST"
  printf '    {"name": "selfcheck_xcontam", "expected": "XCONTAM verdict=ALL_OK fails=0", "actual": "hits=%s", "status": "%s"},\n' "$VERDICT_OK" "$SELF_ST"
  printf '    {"name": "reg_size_match", "expected": "无 different states than DUT", "actual": "%s", "status": "%s"},\n' "$REGBAD" "$REG_ST"
  printf '    {"name": "nm_exec_vdot", "expected": "nm exec_vdot >= 1", "actual": "%s", "status": "%s"},\n' "${NM_HITS:-0}" "$NM_ST"
  printf '    {"name": "vec_reg_compare", "expected": "difftest-state.h 含 CONFIG_DIFFTEST_ARCHVECREGSTATE", "actual": "%s", "status": "%s"},\n' "$(jesc "$HDR")" "$VEC_ST"
  printf '    {"name": "golden_crosscheck", "expected": "XCONTAM_CROSSCHECK verdict=LOG_MATCH", "actual": "%s", "status": "%s"}\n' "$(jesc "$XCHECK_LINE")" "$XCHECK_ST"
  printf '  ],\n'
  printf '  "artifacts": ["%s", "%s"]\n' "$(jesc "$LOG")" "$(jesc "$CLOG")"
  printf '}\n'
} | tee "$JSON"

if bs="$CORE_DIR/core-package/scripts/90-budget-log.sh"; then
  [ -x "$bs" ] && bash "$bs" auto --item "$ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 \
    || echo "[WARN] 记账失败或脚本缺失"
fi

echo "===== DONE status=$ST $REASON =====" | tee -a "$LOG"
# 退出码与 status 一一对应（与 20-run-difftest.sh:578-581 同语义）：未运行不是通过，且不可与失败混淆
case "$ST" in
  通过)   exit 0 ;;
  未运行) exit 2 ;;
  *)      exit 1 ;;
esac
