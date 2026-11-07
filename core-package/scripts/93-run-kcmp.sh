#!/usr/bin/env bash
# =============================================================================
# 93-run-kcmp.sh — perf_kernel_cmp 单例独立测量（清单外；不进 manifest.tsv）
#
# 为什么需要这份（而不是走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合只来自 manifest.tsv（`while read -r cid cls img`
#   逐行读，无「单例 cid」入口）。design/verify/cases/manifest.tsv 的 sha256 已冻结
#   （a90d1071…、30 行数据行；口径裁定：独立测量，不并入 30 例回归清单），perf_kernel_cmp **不得**进该清单。
#   ⇒ 本脚本按 91-run-b3.sh 的同一套「单例作业」思路，直接跑
#        $EMU --no-diff -i $IMG --max-instr=N
#   （必须 --no-diff：用例读 mcycle/minstret，与 NEMU 参照不一致；同 perf_vdot.c:7）。
#
# 机时分类：P3-full（同 91-run-b3.sh 的单例 perf 作业先例）。
#
# 用法：sbatch -p kshcnormal -N 1 -n 8 --time=00:20:00 core-package/scripts/93-run-kcmp.sh
# 产物：results/difftest/kernel/93-kcmp-<runid>.log|json + cases/perf_kernel_cmp.<runid>.log
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
#
# 判据（全部来自日志实读，不推算）：
#   ① 日志含 `KERNEL_CMP verdict=ALL_OK`
#   ② 日志含 `KCMP base_instr=<n> base_cyc=<n> vdot_instr=<n> vdot_cyc=<n>` 四个字段可解析
#   ③ `HIT GOOD TRAP` >= 1 且 `ABORT` == 0
#   ④ 日志含 `KCMP static_xcheck` 行，且 `base=OK` 与 `vdot=OK` **同时**出现（静态↔动态交叉核对通过）。
#      实际格式（成功轮日志实读）：`KCMP static_xcheck static_base=18 measured_base=18 base=OK
#      static_vdot=11 measured_vdot=11 vdot=OK` —— **没有 `delta=` 字段**。旧头注写的
#      `… delta=OK` 正是作业 `126986221` 被判 `未运行` 的原因（`XCH_ST` 匹配了不存在的格式）；
#      本判据与 `XCH_ST` 段（见下 `static_xcheck` 注释与 `*base=OK*vdot=OK*` 分支）逐字一致。
#   ⑤ 无 `HAS_FAIL` / `MISMATCH` 判据行（除明确标注「未运行」的 static_xcheck）
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=00:20:00
#SBATCH -J vdot_kcmp

set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
IMG="${IMG:-$CORE_DIR/test/bin/perf_kernel_cmp.bin}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-900}"
ITEM="P3-full"
PURPOSE="内核级指令数/吞吐对比：perf_kernel_cmp 单例（清单外独立测量，分母=未融合 RVV 序列）"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺镜像：$IMG" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/kernel"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/93-kcmp-$RUN_ID.log"
JSON="$OUT_DIR/93-kcmp-$RUN_ID.json"
CLOG="$CASES_DIR/perf_kernel_cmp.$RUN_ID.log"
mkdir -p "$OUT_DIR" "$CASES_DIR"

IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
SRC="$CORE_DIR/src/XiangShan"

{
  echo "===== job=$SLURM_JOB_ID host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=${EMU_MD5:-NA}"
  echo "img=$IMG img_md5=${IMG_MD5:-NA} max_instr=$MAX_INSTR timeout=${CASE_TIMEOUT_S}s"
  echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null)"
  # 措辞约束：只报**远端文件现状**，不得写成「未改动 = 冻结件」。
  # 远端 test/manifest.tsv 实测 31 行（比冻结件 design/verify/cases/manifest.tsv 的 30 行
  # 多一行 perf_base_chain）；本脚本不改动该文件。
  echo "manifest_remote sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" 2>/dev/null | wc -l)（远端现状；本脚本不修改它）"
  echo "denom=unfused_rvv_seq（分母 = 未融合 RVV 序列；本用例只报指令数对比/吞吐对比）"
} | tee -a "$LOG"

echo "----- emu --no-diff run -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG" --max-instr="$MAX_INSTR" >"$CLOG" 2>&1
RC=$?
echo "emu rc=$RC case_log=$CLOG ($(stat -c %s "$CLOG" 2>/dev/null) B)" | tee -a "$LOG"

GOOD="$(grep -ac 'HIT GOOD TRAP' "$CLOG" || true)"
ABORT="$(grep -ac 'ABORT' "$CLOG" || true)"
BAD="$(grep -ac 'HIT BAD TRAP' "$CLOG" || true)"
VERDICT_OK="$(grep -ac 'KERNEL_CMP verdict=ALL_OK' "$CLOG" || true)"
VERDICT_BAD="$(grep -ac 'KERNEL_CMP verdict=HAS_FAIL' "$CLOG" || true)"
HASFAIL_LINES="$(grep -acE 'KCMP .*=MISMATCH|KCMP .*alt_differs=no' "$CLOG" || true)"
XCHECK="$(grep -a 'KCMP static_xcheck' "$CLOG" | tail -1)"
KCMP_LINE="$(grep -aE '^KCMP base_instr=[0-9]+ base_cyc=[0-9]+ vdot_instr=[0-9]+ vdot_cyc=[0-9]+' "$CLOG" | tail -1)"

echo "good=$GOOD abort=$ABORT bad_trap=$BAD verdict_all_ok=$VERDICT_OK has_fail=$VERDICT_BAD" | tee -a "$LOG"
grep -a '^KCMP ' "$CLOG" | tee -a "$LOG"
grep -a '^VDOT_METRIC ' "$CLOG" | tee -a "$LOG"

# 判据串四个字段逐个解析（缺一个即未达标；不做「大概齐」的字符串包含判定）
# 只认**以 `KCMP base_instr=` 开头**的那一行（`KCMP kernel_body base_instr=` 是校准后
# 的第二个口径，前缀不同、不参与本判据），避免把两个口径混起来。
PARSED="未运行"; KCMP_OK=0
BASE_INSTR=""; BASE_CYC=""; VDOT_INSTR=""; VDOT_CYC=""
if [ -n "$KCMP_LINE" ]; then
  for kv in $(printf '%s\n' "$KCMP_LINE" | sed -E 's/^KCMP //' | tr ' ' '\n' \
                | grep -E '^(base_instr|base_cyc|vdot_instr|vdot_cyc)=[0-9]+$'); do
    case "$kv" in
      base_instr=*) BASE_INSTR="${kv#*=}" ;;
      base_cyc=*)   BASE_CYC="${kv#*=}" ;;
      vdot_instr=*) VDOT_INSTR="${kv#*=}" ;;
      vdot_cyc=*)   VDOT_CYC="${kv#*=}" ;;
    esac
  done
  if [ -n "$BASE_INSTR" ] && [ -n "$BASE_CYC" ] && [ -n "$VDOT_INSTR" ] && [ -n "$VDOT_CYC" ] \
     && [ "$VDOT_INSTR" -ge 1 ] && [ "$VDOT_CYC" -ge 1 ]; then
    KCMP_OK=1
    PARSED="base_instr=$BASE_INSTR base_cyc=$BASE_CYC vdot_instr=$VDOT_INSTR vdot_cyc=$VDOT_CYC"
  fi
fi
echo "kcmp_fields=$PARSED" | tee -a "$LOG"

# 判据聚合（语义同 92-run-xcontam.sh：任一未达标 ⇒ 失败；无未达标但有未运行 ⇒ 未运行）
ST="失败"; REASON=""
GOOD_ST="未达标"; [ "${GOOD:-0}" -ge 1 ] && GOOD_ST="达标"
ABORT_ST="未达标"; [ "${ABORT:-0}" -eq 0 ] && ABORT_ST="达标"
BAD_ST="未达标";   [ "${BAD:-0}" -eq 0 ] && BAD_ST="达标"
SELF_ST="未达标";  [ "${VERDICT_OK:-0}" -ge 1 ] && [ "${VERDICT_BAD:-0}" -eq 0 ] && SELF_ST="达标"
FIELD_ST="未达标"; [ "$KCMP_OK" -eq 1 ] && FIELD_ST="达标"
MIS_ST="未达标";   [ "${HASFAIL_LINES:-0}" -eq 0 ] && MIS_ST="达标"
RC_ST="未达标";    [ "${RC:-1}" -eq 0 ] && RC_ST="达标"
# static_xcheck 有两种形态：
#   KCMP static_xcheck static_base=<s> measured_base=<m> base=<OK|MISMATCH> static_vdot=<s> measured_vdot=<m> vdot=<OK|MISMATCH>
#   KCMP static_xcheck 未运行（未注入 STATIC_N_BASE/STATIC_N_VDOT）
# 两个版本都必须 OK 才达标；任一 MISMATCH 即未达标；整行缺失/未注入记未运行。
XCH_ST="未运行"
if [ -n "$XCHECK" ]; then
  case "$XCHECK" in
    *未运行*) XCH_ST="未运行" ;;
    *)
      case "$XCHECK" in
        *base=OK*vdot=OK*) XCH_ST="达标" ;;
        *MISMATCH*)        XCH_ST="未达标" ;;
        *)                 XCH_ST="未运行" ;;
      esac ;;
  esac
fi

ALL_ST=("$GOOD_ST" "$ABORT_ST" "$BAD_ST" "$SELF_ST" "$FIELD_ST" "$MIS_ST" "$RC_ST" "$XCH_ST")
UNRUN=0; UNMET=0
for s in "${ALL_ST[@]}"; do
  [ "$s" = "未运行" ] && UNRUN=1
  [ "$s" = "未达标" ] && UNMET=1
done
if [ "$UNMET" -eq 0 ] && [ "$UNRUN" -eq 0 ]; then
  ST="通过"
elif [ "$UNMET" -eq 0 ]; then
  ST="未运行"; REASON="存在未运行项（static_xcheck 未注入）⇒ 按全仓规则不得记通过"
else
  ST="失败"
  REASON="GOOD=$GOOD ABORT=$ABORT BAD=$BAD VERDICT_OK=$VERDICT_OK HASFAIL=$HASFAIL_LINES rc=$RC fields=$FIELD_ST xcheck=$XCH_ST"
fi

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/%s",\n' "$(basename "$0")"
  printf '  "case_id": "perf_kernel_cmp",\n'
  printf '  "status": "%s",\n' "$ST"
  printf '  "note": "%s",\n' "$(jesc "清单外单例（不进 design/verify/cases/manifest.tsv，该文件冻结 30 行/a90d1071…）；只报指令数对比/吞吐对比，分母=未融合 RVV 序列")"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "machine_hours_planned": 0.1,\n'
  printf '  "mode": "single-case",\n'
  printf '  "provenance": {"emu": "%s", "emu_md5": "%s", "img": "%s", "img_md5": "%s", "max_instr": "%s"},\n' \
    "$(jesc "$EMU")" "${EMU_MD5:-NA}" "$(jesc "$IMG")" "${IMG_MD5:-NA}" "$MAX_INSTR"
  printf '  "metrics": {"base_instr": "%s", "base_cyc": "%s", "vdot_instr": "%s", "vdot_cyc": "%s", "denom": "unfused_rvv_seq"},\n' \
    "${BASE_INSTR:-}" "${BASE_CYC:-}" "${VDOT_INSTR:-}" "${VDOT_CYC:-}"
  printf '  "criteria": [\n'
  printf '    {"name": "good_trap", "expected": "HIT GOOD TRAP >= 1", "actual": "%s", "status": "%s"},\n' "$GOOD" "$GOOD_ST"
  printf '    {"name": "no_abort", "expected": "ABORT == 0", "actual": "%s", "status": "%s"},\n' "$ABORT" "$ABORT_ST"
  printf '    {"name": "no_bad_trap", "expected": "HIT BAD TRAP == 0", "actual": "%s", "status": "%s"},\n' "$BAD" "$BAD_ST"
  printf '    {"name": "selfcheck_kernel_cmp", "expected": "KERNEL_CMP verdict=ALL_OK", "actual": "hits=%s", "status": "%s"},\n' "$VERDICT_OK" "$SELF_ST"
  printf '    {"name": "kcmp_fields", "expected": "base_instr/base_cyc/vdot_instr/vdot_cyc 可解析", "actual": "%s", "status": "%s"},\n' "$(jesc "$PARSED")" "$FIELD_ST"
  printf '    {"name": "no_mismatch_line", "expected": "无 *=MISMATCH / alt_differs=no", "actual": "%s", "status": "%s"},\n' "$HASFAIL_LINES" "$MIS_ST"
  printf '    {"name": "emu_rc", "expected": "rc == 0", "actual": "%s", "status": "%s"},\n' "$RC" "$RC_ST"
  printf '    {"name": "static_xcheck", "expected": "KCMP static_xcheck … base=OK … vdot=OK", "actual": "%s", "status": "%s"}\n' "$(jesc "$XCHECK")" "$XCH_ST"
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
  通过)   exit 0 ;;
  未运行) exit 2 ;;
  *)      exit 1 ;;
esac
