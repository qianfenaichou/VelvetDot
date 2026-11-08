#!/usr/bin/env bash
# =============================================================================
# 96-run-dualchain.sh — 双链实验单例作业（清单外用例，独立测量）
#
# 为什么需要这份（而不是走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合**只来自 manifest.tsv**（`while read -r cid cls img extra`
#   逐行读，`class_selected` 只按 cls 过滤，没有「单例 cid」入口）。而
#   design/verify/cases/manifest.tsv 的 sha256 已冻结（a90d1071…、30 数据行；口径裁定见
#   同 perf_base_chain / perf_kernel_cmp 的「独立测量」先例），
#   vdot_dualchain **必须不进**该清单。⇒ 本脚本按 92-run-xcontam.sh 的同一套「单例作业」
#   思路，直接复刻 20-run-difftest.sh:226 的 run_case 调用形态：
#       timeout N  $EMU --no-diff -i $IMG --max-instr=N
#   （必须 --no-diff：用例读 rdcycle/mcycle，与 NEMU 参照不一致；同 perf_vdot.c:7）
#
# 一个作业跑**两个镜像**（同一份源码的两次编译，不是两次运行同一镜像）：
#   ① vdot_dualchain.bin     主镜像：八条链的差分中位数 + 16 条功能逐字节比对
#      + 三条同口径对照臂（M9 本项 vdot 依赖链 / M10 标准 RVV 五指令链 / M11 空循环 control，
#        复现外部公开材料的「N=0/64/256/1024、3 重复、4 点 OLS 斜率」口径）
#   ② vdot_dualchain_g0.bin  G0 反例（-DDC_G0=1）：期望被人为翻转 1 bit，
#      DUT/NEMU 仍逐位一致 ⇒ 必须 GOOD TRAP + 无 ABORT，但**必须**被用例内嵌自检判负
#      （`CASE vdot_dualchain_g0: MISMATCH`）。这是「本包的空绿防护真的起作用」的机械证明。
#
# 判据聚合语义与 20-run-difftest.sh:563-577 / 92-run-xcontam.sh 同构：
#   任一 criteria 记「未达标」⇒ status=失败（exit 1）；
#   无未达标但任一条记「未运行」⇒ status=未运行（exit 2；全仓规则「未运行不是通过」）。
#
# 机时分类：P3-full（同 91/93 的单例 perf 作业先例）。**记账由脚本末尾自动调用
# `90-budget-log.sh auto`**，不需要人工补录。
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:20:00 core-package/scripts/96-run-dualchain.sh
# 产物：
#   results/difftest/dualchain/96-dualchain-<runid>.{log,json}
#   results/difftest/dualchain/cases/vdot_dualchain.<runid>.log
#   results/difftest/dualchain/cases/vdot_dualchain_g0.<runid>.log
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=00:20:00
#SBATCH -J vdot_dualchain

set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
REF_SO="${REF_SO:-$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so}"
IMG="${IMG:-$CORE_DIR/test/bin/vdot_dualchain.bin}"
IMG_G0="${IMG_G0:-$CORE_DIR/test/bin/vdot_dualchain_g0.bin}"
CROSSCHECK="${CROSSCHECK:-$CORE_DIR/verify/cases/dualchain_check.py}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-900}"
ITEM="P3-full"
PURPOSE="双链实验：vdot→vdot 依赖间隔 + old_vd 机制归因（清单外独立测量）"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$REF_SO" ] || { echo "[FATAL] 缺 NEMU ref .so：$REF_SO" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺主镜像：$IMG" >&2; exit 2; }
[ -f "$IMG_G0" ] || { echo "[FATAL] 缺 G0 镜像：$IMG_G0" >&2; exit 2; }
[ -f "$CROSSCHECK" ] || { echo "[FATAL] 缺金模型复核脚本：$CROSSCHECK" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
# started_at 必须是**作业开始**的时刻，不是写 JSON 的时刻（同 92-run-xcontam.sh 的 provenance 约定）
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/dualchain"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/96-dualchain-$RUN_ID.log"
JSON="$OUT_DIR/96-dualchain-$RUN_ID.json"
CLOG="$CASES_DIR/vdot_dualchain.$RUN_ID.log"
GLOG="$CASES_DIR/vdot_dualchain_g0.$RUN_ID.log"
mkdir -p "$OUT_DIR" "$CASES_DIR"

IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
IMG_G0_MD5="$(md5sum "$IMG_G0" 2>/dev/null | cut -d' ' -f1)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
REF_MD5="$(md5sum "$REF_SO" 2>/dev/null | cut -d' ' -f1)"
SRC="$CORE_DIR/src/XiangShan"

{
  echo "===== job=$SLURM_JOB_ID host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=$EMU_MD5"
  echo "ref_so=$REF_SO ref_md5=$REF_MD5"
  echo "img=$IMG img_md5=$IMG_MD5"
  echo "img_g0=$IMG_G0 img_g0_md5=$IMG_G0_MD5"
  echo "max_instr=$MAX_INSTR timeout=${CASE_TIMEOUT_S}s"
  echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null) nemu=$(git -C "$CORE_DIR/src/NEMU" rev-parse --short HEAD 2>/dev/null)"
  # 措辞约束：只报**远端文件现状**，不得写成「未改动 = 冻结件」。
  echo "manifest_remote sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" 2>/dev/null | wc -l)（远端现状；本脚本不改动它；冻结件 design/verify/cases/manifest.tsv = a90d1071…/30 行数据行）"
  echo "independent_measure=yes（本用例不进 manifest.tsv；走单例作业路径）"
  echo "redline=只报我方实测 + 机制归因；竞品 7 cyc 引自其公开文档、未复跑，不构造跨队比较"
} | tee -a "$LOG"

# 与 20-run-difftest.sh 同两条前置判据
NM_HITS="$(nm -a "$REF_SO" 2>/dev/null | grep -cw exec_vdot || true)"
HDR="$(find "$SRC/build" -name 'difftest-state.h' -print -quit 2>/dev/null || true)"
VEC_OK=0
[ -n "$HDR" ] && grep -q 'CONFIG_DIFFTEST_ARCHVECREGSTATE' "$HDR" 2>/dev/null && VEC_OK=1
echo "nm_exec_vdot_hits=${NM_HITS:-0} difftest_state=$HDR vec_reg_compare=$VEC_OK" | tee -a "$LOG"

# ---------------------------------------------------------------------------
# ① 主镜像
# ---------------------------------------------------------------------------
echo "----- [1/2] emu --no-diff 主镜像 -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG" --max-instr="$MAX_INSTR" >"$CLOG" 2>&1
RC=$?
echo "emu rc=$RC case_log=$CLOG ($(stat -c %s "$CLOG" 2>/dev/null) B)" | tee -a "$LOG"

GOOD="$(grep -ac 'HIT GOOD TRAP' "$CLOG" || true)"
ABORT="$(grep -ac 'ABORT' "$CLOG" || true)"
BAD="$(grep -ac 'HIT BAD TRAP' "$CLOG" || true)"
MISMATCH="$(grep -acE 'diff REF|Different operands' "$CLOG" || true)"
REGBAD="$(grep -ac 'is configured with different states than DUT' "$CLOG" || true)"
VERDICT_OK="$(grep -ac 'DUALCHAIN verdict=ALL_OK' "$CLOG" || true)"
VERDICT_BAD="$(grep -ac 'DUALCHAIN verdict=HAS_FAIL' "$CLOG" || true)"
SETUP_BAD="$(grep -ac 'DUALCHAIN SETUP_BAD' "$CLOG" || true)"
echo "good=$GOOD abort=$ABORT bad_trap=$BAD mismatch=$MISMATCH reg_size_bad=$REGBAD" | tee -a "$LOG"
echo "verdict_all_ok=$VERDICT_OK verdict_has_fail=$VERDICT_BAD setup_bad=$SETUP_BAD" | tee -a "$LOG"

# 八条链的中位数：从日志原样摘出（不重算、不四舍五入）
echo "----- 八链中位数（日志原文）-----" | tee -a "$LOG"
grep -a '^DUALCHAIN M[0-9] dep ' "$CLOG" | tee -a "$LOG"
grep -a '^DUALCHAIN T_' "$CLOG" | tee -a "$LOG"
grep -a '^DUALCHAIN alt_lines ' "$CLOG" | tee -a "$LOG"
grep -a '^DUALCHAIN expected_sha256=' "$CLOG" | tee -a "$LOG"
# 同口径对照三臂（M9/M10/M11）：逐 N 中位数 + 4 点 OLS 斜率，日志原文摘出
echo "----- 同口径对照三臂（日志原文）-----" | tee -a "$LOG"
grep -a '^DUALCHAIN_G44 ' "$CLOG" | tee -a "$LOG"
G44_FITS="$(grep -acE '^DUALCHAIN_G44 M(9|10|11) fit ' "$CLOG" || true)"
G44_ONESTEP_OK="$(grep -acE '^DUALCHAIN_G44 M(9|10) one_step bytes_bad=0' "$CLOG" || true)"

# 期望值 ↔ 实测 逐行比对（金模型重算，不手抄；脚本 --check-log 自带 falsifiability 守卫）
XCHECK_RC=99; XCHECK_LINE="未运行"
PY3=/public/software/apps/python/3.8.13/bin/python3
[ -x "$PY3" ] || PY3="$(command -v python3 || true)"
if [ -n "${PY3:-}" ]; then
  XCHECK_OUT="$("$PY3" -I "$CROSSCHECK" --check-log "$CLOG" 2>&1)"; XCHECK_RC=$?
  XCHECK_LINE="$(printf '%s' "$XCHECK_OUT" | grep -E 'verdict=LOG_(MATCH|MISMATCH)' | tail -1)"
  echo "----- crosscheck rc=$XCHECK_RC -----" | tee -a "$LOG"
  printf '%s\n' "$XCHECK_OUT" | tee -a "$LOG"
else
  XCHECK_LINE="未运行（找不到 python3）"
fi

# ---------------------------------------------------------------------------
# ② G0 反例镜像
# ---------------------------------------------------------------------------
echo "----- [2/2] emu --no-diff G0 反例镜像 -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG_G0" --max-instr="$MAX_INSTR" >"$GLOG" 2>&1
GRC=$?
echo "g0 emu rc=$GRC case_log=$GLOG ($(stat -c %s "$GLOG" 2>/dev/null) B)" | tee -a "$LOG"
GGOOD="$(grep -ac 'HIT GOOD TRAP' "$GLOG" || true)"
GABORT="$(grep -ac 'ABORT' "$GLOG" || true)"
GCAUGHT="$(grep -acF 'CASE vdot_dualchain_g0: MISMATCH' "$GLOG" || true)"
GNOTCAUGHT="$(grep -acF 'CASE vdot_dualchain_g0: MATCH' "$GLOG" || true)"
echo "g0 good=$GGOOD abort=$GABORT caught=$GCAUGHT not_caught=$GNOTCAUGHT" | tee -a "$LOG"
grep -a 'CASE vdot_dualchain_g0' "$GLOG" | tee -a "$LOG"

# ---------------------------------------------------------------------------
# ③ 判据聚合（顺序与写进 JSON 的 criteria[] 一一对应）
# ---------------------------------------------------------------------------
ST="失败"
REASON=""
XCHECK_ST="未运行"
case "$XCHECK_LINE" in *LOG_MATCH*) XCHECK_ST="达标" ;; *LOG_MISMATCH*) XCHECK_ST="未达标" ;; esac
NM_ST="未达标";   [ "${NM_HITS:-0}" -ge 1 ] && NM_ST="达标"
VEC_ST="未达标";  [ "$VEC_OK" = "1" ] && VEC_ST="达标"
REG_ST="达标";    [ "${REGBAD:-0}" -gt 0 ] && REG_ST="未达标"
GOOD_ST="未达标"; [ "${GOOD:-0}" -ge 1 ] && GOOD_ST="达标"
ABORT_ST="未达标"; [ "${ABORT:-0}" -eq 0 ] && ABORT_ST="达标"
BAD_ST="未达标";  [ "${BAD:-0}" -eq 0 ] && BAD_ST="达标"
MIS_ST="未达标";  [ "${MISMATCH:-0}" -eq 0 ] && MIS_ST="达标"
SELF_ST="未达标"
[ "${VERDICT_OK:-0}" -ge 1 ] && [ "${VERDICT_BAD:-0}" -eq 0 ] && [ "${SETUP_BAD:-0}" -eq 0 ] && SELF_ST="达标"
RC_ST="未达标";   [ "${RC:-1}" -eq 0 ] && RC_ST="达标"
# G0：必须 GOOD TRAP + 无 ABORT + 被同一自检判负（MISMATCH 命中且 MATCH 不命中）
G0_ST="未达标"
[ "${GGOOD:-0}" -ge 1 ] && [ "${GABORT:-0}" -eq 0 ] && [ "${GCAUGHT:-0}" -ge 1 ] && [ "${GNOTCAUGHT:-0}" -eq 0 ] && G0_ST="达标"
# 同口径对照三臂：3 条 fit 行齐全（M9/M10/M11）且 M9/M10 的一步功能比对 bytes_bad=0
G44_ST="未达标"
[ "${G44_FITS:-0}" -ge 3 ] && [ "${G44_ONESTEP_OK:-0}" -ge 2 ] && G44_ST="达标"

ALL_ST=("$GOOD_ST" "$ABORT_ST" "$BAD_ST" "$MIS_ST" "$SELF_ST" "$G0_ST" "$G44_ST" "$REG_ST" "$NM_ST" "$VEC_ST" "$RC_ST" "$XCHECK_ST")
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
  REASON="GOOD=$GOOD ABORT=$ABORT BAD=$BAD MISMATCH=$MISMATCH VERDICT_OK=$VERDICT_OK VERDICT_BAD=$VERDICT_BAD SETUP_BAD=$SETUP_BAD rc=$RC g0=[good=$GGOOD abort=$GABORT caught=$GCAUGHT not_caught=$GNOTCAUGHT] g44=[fits=$G44_FITS one_step_ok=$G44_ONESTEP_OK st=$G44_ST] reg=$REG_ST nm=$NM_ST vec=$VEC_ST xcheck=$XCHECK_ST"
fi

# 八链中位数 → metrics[]（名称与日志 tag 同源，值由日志行解析，不重算）
# 注意：用例日志是 CRLF（emu 输出带 \r）⇒ 值里会混进 CR，写进 JSON 后使 JSON 非法。
# 2026-11-06 首轮实跑（作业 127043684）的 JSON 就是这样坏的：metrics 值形如 "9\r"。
# 这里统一 tr -d '\r'；行尾 CR 也一并去掉。
metric_rows() {
  grep -aE '^DUALCHAIN_METRIC (M[0-9]|T_samevd|T_diffvd)' "$CLOG" 2>/dev/null | tr -d '\r' | \
  while read -r _tag name value; do
    printf '    {"name": "%s", "value": "%s", "case_id": "vdot_dualchain"},\n' "$name" "$value"
  done
}

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/%s",\n' "$(basename "$0")"
  printf '  "case_id": "vdot_dualchain",\n'
  printf '  "status": "%s",\n' "$ST"
  printf '  "note": "%s",\n' "$(jesc "清单外单例（本脚本不改动远端 test/manifest.tsv，也不改冻结件 design/verify/cases/manifest.tsv = a90d1071…/30 数据行）：20-run-difftest.sh 无单例入口，按 92-run-xcontam.sh 先例直接复刻其 run_case 调用形态；一个作业跑主镜像 + G0 反例两个镜像")"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "machine_hours_planned": 0.1,\n'
  printf '  "mode": "single-case+negative-control",\n'
  printf '  "provenance": {"emu": "%s", "emu_md5": "%s", "ref_so": "%s", "ref_md5": "%s", "img": "%s", "img_md5": "%s", "img_g0": "%s", "img_g0_md5": "%s", "max_instr": "%s"},\n' \
    "$(jesc "$EMU")" "$EMU_MD5" "$(jesc "$REF_SO")" "$REF_MD5" "$(jesc "$IMG")" "$IMG_MD5" "$(jesc "$IMG_G0")" "$IMG_G0_MD5" "$MAX_INSTR"
  printf '  "criteria": [\n'
  printf '    {"name": "good_trap", "expected": "HIT GOOD TRAP >= 1", "actual": "%s", "status": "%s"},\n' "$GOOD" "$GOOD_ST"
  printf '    {"name": "no_abort", "expected": "ABORT == 0", "actual": "%s", "status": "%s"},\n' "$ABORT" "$ABORT_ST"
  printf '    {"name": "no_bad_trap", "expected": "HIT BAD TRAP == 0", "actual": "%s", "status": "%s"},\n' "$BAD" "$BAD_ST"
  printf '    {"name": "no_diff_mismatch", "expected": "diff REF/Different operands == 0", "actual": "%s", "status": "%s"},\n' "$MISMATCH" "$MIS_ST"
  printf '    {"name": "selfcheck_dualchain", "expected": "DUALCHAIN verdict=ALL_OK 且无 HAS_FAIL/SETUP_BAD", "actual": "all_ok=%s has_fail=%s setup_bad=%s", "status": "%s"},\n' "$VERDICT_OK" "$VERDICT_BAD" "$SETUP_BAD" "$SELF_ST"
  printf '    {"name": "g0_caught", "expected": "G0 镜像 GOOD TRAP 且 CASE vdot_dualchain_g0: MISMATCH（不得 MATCH）", "actual": "good=%s abort=%s caught=%s not_caught=%s", "status": "%s"},\n' "$GGOOD" "$GABORT" "$GCAUGHT" "$GNOTCAUGHT" "$G0_ST"
  printf '    {"name": "g44_same_quota_arms", "expected": "M9/M10/M11 fit 行 >=3 且 M9/M10 one_step bytes_bad=0", "actual": "fits=%s one_step_ok=%s", "status": "%s"},\n' "$G44_FITS" "$G44_ONESTEP_OK" "$G44_ST"
  printf '    {"name": "reg_size_match", "expected": "无 different states than DUT", "actual": "%s", "status": "%s"},\n' "$REGBAD" "$REG_ST"
  printf '    {"name": "nm_exec_vdot", "expected": "nm exec_vdot >= 1", "actual": "%s", "status": "%s"},\n' "${NM_HITS:-0}" "$NM_ST"
  printf '    {"name": "vec_reg_compare", "expected": "difftest-state.h 含 CONFIG_DIFFTEST_ARCHVECREGSTATE", "actual": "%s", "status": "%s"},\n' "$(jesc "$HDR")" "$VEC_ST"
  printf '    {"name": "emu_rc", "expected": "emu rc == 0", "actual": "%s", "status": "%s"},\n' "$RC" "$RC_ST"
  printf '    {"name": "golden_crosscheck", "expected": "DUALCHAIN_CROSSCHECK verdict=LOG_MATCH", "actual": "%s", "status": "%s"}\n' "$(jesc "$XCHECK_LINE")" "$XCHECK_ST"
  printf '  ],\n'
  printf '  "metrics": [\n'
  metric_rows | sed '$ s/,$//'
  printf '  ],\n'
  printf '  "artifacts": ["%s", "%s", "%s"]\n' "$(jesc "$LOG")" "$(jesc "$CLOG")" "$(jesc "$GLOG")"
  printf '}\n'
} | tee "$JSON"

# 机时记账（与本脚本同作业；90-budget-log.sh 的 auto 子命令读 SLURM_* 与 sacct）
if bs="$CORE_DIR/core-package/scripts/90-budget-log.sh"; then
  if [ -x "$bs" ]; then
    bash "$bs" auto --item "$ITEM" --purpose "$PURPOSE" || echo "[WARN] 记账失败"
  else
    echo "[WARN] 记账脚本不可执行：$bs"
  fi
else
  echo "[WARN] 记账脚本缺失：$bs"
fi

echo "===== DONE status=$ST $REASON =====" | tee -a "$LOG"
# 退出码与 status 一一对应（与 20-run-difftest.sh:578-581 同语义）：未运行不是通过
case "$ST" in
  通过)   exit 0 ;;
  未运行) exit 2 ;;
  *)      exit 1 ;;
esac
