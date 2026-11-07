#!/usr/bin/env bash
# =============================================================================
# 97-run-llm.sh — LLM 算子级基准（Q8_0 attention QK 点积）单例独立测量
#
# 为什么需要这份（而不是走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合只来自 manifest.tsv（逐行读 cid/cls/img，无「单例 cid」入口）。
#   design/verify/cases/manifest.tsv 的 sha256 已冻结（a90d1071…、30 行数据行；口径裁定见
#   （口径纪律：独立测量，不并入 30 例回归清单），
#   perf_llm_attn **不得**进该清单。⇒ 本脚本按 93-run-kcmp.sh 的同一套「单例作业」思路，
#   直接跑 `$EMU --no-diff -i $IMG --max-instr=N`（必须 --no-diff：用例读 mcycle/minstret，
#   与 NEMU 参照不一致）。
#
# 口径约定（本脚本的所有输出与后续引用都必须遵守）：
#   · 只报「指令数对比 / 拍数对比 / 内核吞吐对比」；**不是延迟加速比、不是官方口径、不是端到端 token/s**。
#   · 主分母固定为 `unfused_rvv_seq`；`vwmacc_rvv_seq` 只作敏感性参考，两者**不合并、不相除**。
#   · 比值一律写成裸比值 `N_base/N_vdot`、`C_base/C_vdot`；不写「加速比」。
#   · 数字全部来自日志实读（`VDOT_METRIC`、`LLM_ATTN point/fit` 行）；无日志即记「未运行」。
#   · emu ≠ 硅：`mcycle`/`cycleCnt` 是 Verilator 仿真周期，引用时必须注明。
#
# 机时分类：P3-full（同 93-run-kcmp.sh 的单例 perf 作业先例）。
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:30:00 core-package/scripts/97-run-llm.sh
# 产物：
#   results/difftest/llm/97-llm-<runid>.log|json
#   results/difftest/llm/cases/perf_llm_attn.<runid>.log（正常镜像）
#   results/difftest/llm/cases/perf_llm_attn_g0.<runid>.log（G0 镜像）
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
#
# 判据（全部来自日志实读，不推算）：
#   ① 正常镜像：`LLM_ATTN verdict=ALL_OK` 命中 ≥1，且无 `LLM_ATTN verdict=HAS_FAIL`
#   ② G0 镜像：`LLM_ATTN verdict=HAS_FAIL` 命中 ≥1，且无 `ALL_OK`（否则 harness 作废）
#   ③ `HIT GOOD TRAP` ≥1（两个镜像都要求），`ABORT` == 0、`HIT BAD TRAP` == 0
#   ④ `LLM_ATTN static_xcheck`：base/macc/vdot 三个 `=OK` 同时出现（静态↔动态交叉核对）
#   ⑤ 指标行可解析：LLM_base_instr / LLM_macc_instr / LLM_vdot_instr 三条（≥1）
#   ⑥ 无 `=MISMATCH` 判据行、无 `alt_differs=no`
#   ⑦ 两个镜像的 emu 退出码都为 0
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=00:30:00
#SBATCH -J vdot_llm_attn

set -uo pipefail

CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
IMG="${IMG:-$CORE_DIR/test/bin/llm_attn.bin}"
G0="${G0:-$CORE_DIR/test/bin/llm_attn_g0.bin}"
MAX_INSTR="${MAX_INSTR:-400000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-1200}"
ITEM="P3-full"
PURPOSE="LLM 算子级基准：Q8_0/INT8 attention QK 点积三臂对照（单例，清单外独立测量，分母=unfused_rvv_seq）"

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 禁止在登录节点跑 emu" >&2; exit 3; }
if [ -r "$HOME/tools/env.sh" ]; then . "$HOME/tools/env.sh"; fi
[ -x "$EMU" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$IMG" ] || { echo "[FATAL] 缺镜像：$IMG" >&2; exit 2; }
[ -f "$G0" ]  || { echo "[FATAL] 缺 G0 镜像：$G0" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/llm"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/97-llm-$RUN_ID.log"
JSON="$OUT_DIR/97-llm-$RUN_ID.json"
CLOG="$CASES_DIR/perf_llm_attn.$RUN_ID.log"
GLOG="$CASES_DIR/perf_llm_attn_g0.$RUN_ID.log"
mkdir -p "$OUT_DIR" "$CASES_DIR"

IMG_MD5="$(md5sum "$IMG" 2>/dev/null | cut -d' ' -f1)"
G0_MD5="$(md5sum "$G0" 2>/dev/null | cut -d' ' -f1)"
EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
SRC="$CORE_DIR/src/XiangShan"

{
  echo "===== job=$SLURM_JOB_ID host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=${EMU_MD5:-NA}"
  echo "img=$IMG img_md5=${IMG_MD5:-NA} g0=$G0 g0_md5=${G0_MD5:-NA} max_instr=$MAX_INSTR timeout=${CASE_TIMEOUT_S}s"
  echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null)"
  echo "manifest_remote sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" 2>/dev/null | wc -l)（远端现状；本脚本不修改它）"
  echo "denom=unfused_rvv_seq（主分母）；vwmacc_rvv_seq 只作敏感性；emu≠硅（Verilator 仿真周期）"
} | tee -a "$LOG"

echo "----- normal image: emu --no-diff -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$IMG" --max-instr="$MAX_INSTR" >"$CLOG" 2>&1
RC_IMG=$?
echo "emu(normal) rc=$RC_IMG case_log=$CLOG ($(stat -c %s "$CLOG" 2>/dev/null) B)" | tee -a "$LOG"

echo "----- G0 image: emu --no-diff -----" | tee -a "$LOG"
timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$G0" --max-instr="$MAX_INSTR" >"$GLOG" 2>&1
RC_G0=$?
echo "emu(g0) rc=$RC_G0 case_log=$GLOG ($(stat -c %s "$GLOG" 2>/dev/null) B)" | tee -a "$LOG"

# 计数一律单文件 + awk 求和：`grep -c a b` 会输出 "a:0\nb:0"，不是纯数字
# （2026-11-06 作业 127039889 实测：ABORT/BAD 判据因此被误判「未达标」）。
GOOD_IMG="$(grep -ac 'HIT GOOD TRAP' "$CLOG" || true)"
GOOD_G0="$(grep -ac 'HIT GOOD TRAP' "$GLOG" || true)"
ABORT="$( { grep -ac 'ABORT' "$CLOG" || true; } | awk '{s+=$1} END{print s+0}')"
ABORT="$((ABORT + $( { grep -ac 'ABORT' "$GLOG" || true; } | awk '{s+=$1} END{print s+0}')))"
BAD="$( { grep -ac 'HIT BAD TRAP' "$CLOG" || true; } | awk '{s+=$1} END{print s+0}')"
BAD="$((BAD + $( { grep -ac 'HIT BAD TRAP' "$GLOG" || true; } | awk '{s+=$1} END{print s+0}')))"
OK_IMG="$(grep -ac 'LLM_ATTN verdict=ALL_OK' "$CLOG" || true)"
FAIL_IMG="$(grep -ac 'LLM_ATTN verdict=HAS_FAIL' "$CLOG" || true)"
OK_G0="$(grep -ac 'LLM_ATTN verdict=ALL_OK' "$GLOG" || true)"
FAIL_G0="$(grep -ac 'LLM_ATTN verdict=HAS_FAIL' "$GLOG" || true)"
HASFAIL_LINES="$(grep -acE 'LLM_ATTN .*=MISMATCH|LLM_ATTN .*alt_differs=no' "$CLOG" || true)"
XCHECK="$(grep -a 'LLM_ATTN static_xcheck' "$CLOG" | tail -1)"
VERDICT_LINE="$(grep -a '^LLM_ATTN verdict=' "$CLOG" | tail -1)"
G0_VERDICT_LINE="$(grep -a '^LLM_ATTN verdict=' "$GLOG" | tail -1)"

echo "normal: good=$GOOD_IMG abort=$ABORT bad_trap=$BAD all_ok=$OK_IMG has_fail=$FAIL_IMG" | tee -a "$LOG"
echo "g0    : good=$GOOD_G0 all_ok=$OK_G0 has_fail=$FAIL_G0（G0 必须 only HAS_FAIL）" | tee -a "$LOG"
grep -a '^LLM_ATTN ' "$CLOG" | tee -a "$LOG"
echo "----- G0 镜像日志行（只筛判据行） -----" | tee -a "$LOG"
grep -a '^LLM_ATTN ' "$GLOG" | tee -a "$LOG"
grep -a '^VDOT_METRIC ' "$CLOG" | tee -a "$LOG"

# 指标解析：只认 `^VDOT_METRIC LLM_*` 的三条 instr 字段
# 注意：emu 日志行尾带 CR（CRLF）⇒ awk 取到的字段尾部有 \r，`[ "$x" -ge 1 ]` 会报错、
# 判据被误判「未达标」。所有解析值统一 `tr -d '\r'`（2026-11-06 作业 127049777 实测）。
rd() { tr -d '\r'; }
BASE_INSTR="$(awk '/^VDOT_METRIC LLM_base_instr /{print $3; exit}' "$CLOG" | rd)"
MACC_INSTR="$(awk '/^VDOT_METRIC LLM_macc_instr /{print $3; exit}' "$CLOG" | rd)"
VDOT_INSTR="$(awk '/^VDOT_METRIC LLM_vdot_instr /{print $3; exit}' "$CLOG" | rd)"
BASE_SN="$(awk '/^VDOT_METRIC LLM_base_slope_num /{print $3; exit}' "$CLOG" | rd)"
BASE_SD="$(awk '/^VDOT_METRIC LLM_base_slope_den /{print $3; exit}' "$CLOG" | rd)"
MACC_SN="$(awk '/^VDOT_METRIC LLM_macc_slope_num /{print $3; exit}' "$CLOG" | rd)"
MACC_SD="$(awk '/^VDOT_METRIC LLM_macc_slope_den /{print $3; exit}' "$CLOG" | rd)"
VDOT_SN="$(awk '/^VDOT_METRIC LLM_vdot_slope_num /{print $3; exit}' "$CLOG" | rd)"
VDOT_SD="$(awk '/^VDOT_METRIC LLM_vdot_slope_den /{print $3; exit}' "$CLOG" | rd)"
DOTS_ARM="$(awk '/^VDOT_METRIC LLM_dots_per_arm /{print $3; exit}' "$CLOG" | rd)"

# R² 由 A/B/C 现算（镜像内不算：A² 超 int64，且 __int128 除法要 libgcc 的 __divti3，裸机 AM 没有）。
# 复算式与报告一致：R² = A²/(B·C)；斜率 = A/B；每 score 周期 = 64·A/B。
# 这里用 python3 的大整数（精确到 1e-12），输出 r2_ppm（×1e6）与 slope_milli（×1e3）。
# 从 fit 行解析 A/B/C（三臂各一行），R² = A²/(B·C)
read -r BASE_A BASE_B BASE_C <<<"$(awk '/^LLM_ATTN fit arm=base /{for(i=1;i<=NF;i++){if($i ~ /^A=/){a=substr($i,3)} if($i ~ /^B=/){b=substr($i,3)} if($i ~ /^C=/){c=substr($i,3)}}} END{print a, b, c}' "$CLOG" | rd)"
read -r MACC_A MACC_B MACC_C <<<"$(awk '/^LLM_ATTN fit arm=macc /{for(i=1;i<=NF;i++){if($i ~ /^A=/){a=substr($i,3)} if($i ~ /^B=/){b=substr($i,3)} if($i ~ /^C=/){c=substr($i,3)}}} END{print a, b, c}' "$CLOG" | rd)"
read -r VDOT_A VDOT_B VDOT_C <<<"$(awk '/^LLM_ATTN fit arm=vdot /{for(i=1;i<=NF;i++){if($i ~ /^A=/){a=substr($i,3)} if($i ~ /^B=/){b=substr($i,3)} if($i ~ /^C=/){c=substr($i,3)}}} END{print a, b, c}' "$CLOG" | rd)"
R2_LINE="$(python3 - "$BASE_A" "$BASE_B" "$BASE_C" "$MACC_A" "$MACC_B" "$MACC_C" "$VDOT_A" "$VDOT_B" "$VDOT_C" <<'PYEOF' 2>/dev/null || echo "NA"
import sys
v = sys.argv[1:]
def ppm(a, b, c):
    try:
        a, b, c = int(a), int(b), int(c)
    except Exception:
        return "NA"
    if b == 0 or c == 0:
        return "NA"
    return "%d" % ((a * a * 1000000) // (b * c))
def milli(a, b):
    try:
        a, b = int(a), int(b)
    except Exception:
        return "NA"
    return "NA" if b == 0 else "%d" % ((a * 1000) // b)
print("base_r2_ppm=%s macc_r2_ppm=%s vdot_r2_ppm=%s base_slope_milli=%s macc_slope_milli=%s vdot_slope_milli=%s"
      % (ppm(v[0], v[1], v[2]), ppm(v[3], v[4], v[5]), ppm(v[6], v[7], v[8]),
         milli(v[0], v[1]), milli(v[3], v[4]), milli(v[6], v[7])))
PYEOF
)"
BASE_R2="$(printf '%s\n' "$R2_LINE" | sed -nE 's/.*base_r2_ppm=([^ ]+).*/\1/p')"
MACC_R2="$(printf '%s\n' "$R2_LINE" | sed -nE 's/.*macc_r2_ppm=([^ ]+).*/\1/p')"
VDOT_R2="$(printf '%s\n' "$R2_LINE" | sed -nE 's/.*vdot_r2_ppm=([^ ]+).*/\1/p')"

FIELDS_OK=0
if [ -n "$BASE_INSTR" ] && [ -n "$MACC_INSTR" ] && [ -n "$VDOT_INSTR" ] \
   && [ "$BASE_INSTR" -ge 1 ] 2>/dev/null && [ "$MACC_INSTR" -ge 1 ] 2>/dev/null \
   && [ "$VDOT_INSTR" -ge 1 ] 2>/dev/null; then FIELDS_OK=1; fi
echo "llm_fields base_instr=${BASE_INSTR:-NA} macc_instr=${MACC_INSTR:-NA} vdot_instr=${VDOT_INSTR:-NA} dots_per_arm=${DOTS_ARM:-NA}" | tee -a "$LOG"
echo "llm_fit base=${BASE_SN:-NA}/${BASE_SD:-NA} macc=${MACC_SN:-NA}/${MACC_SD:-NA} vdot=${VDOT_SN:-NA}/${VDOT_SD:-NA}" | tee -a "$LOG"
echo "llm_r2 $R2_LINE（由 A/B/C 现算；A² 超 int64，故不在镜像内算）" | tee -a "$LOG"
echo "llm_fit_abc base=${BASE_A:-NA}/${BASE_B:-NA}/${BASE_C:-NA} macc=${MACC_A:-NA}/${MACC_B:-NA}/${MACC_C:-NA} vdot=${VDOT_A:-NA}/${VDOT_B:-NA}/${VDOT_C:-NA}" | tee -a "$LOG"

# 判据聚合（语义同 93-run-kcmp.sh：任一未达标 ⇒ 失败；无未达标但有未运行 ⇒ 未运行）
ST="失败"; REASON=""
IMG_ST="未达标";  [ "${OK_IMG:-0}" -ge 1 ] && [ "${FAIL_IMG:-0}" -eq 0 ] && IMG_ST="达标"
G0_ST="未达标";   [ "${FAIL_G0:-0}" -ge 1 ] && [ "${OK_G0:-0}" -eq 0 ] && G0_ST="达标"
GOOD_ST="未达标"; [ "${GOOD_IMG:-0}" -ge 1 ] && [ "${GOOD_G0:-0}" -ge 1 ] && GOOD_ST="达标"
ABORT_ST="未达标"; [ "${ABORT:-0}" -eq 0 ] && ABORT_ST="达标"
BAD_ST="未达标";  [ "${BAD:-0}" -eq 0 ] && BAD_ST="达标"
FIELD_ST="未达标"; [ "$FIELDS_OK" -eq 1 ] && FIELD_ST="达标"
MIS_ST="未达标";  [ "${HASFAIL_LINES:-0}" -eq 0 ] && MIS_ST="达标"
RC_ST="未达标";   [ "${RC_IMG:-1}" -eq 0 ] && [ "${RC_G0:-1}" -eq 0 ] && RC_ST="达标"
XCH_ST="未运行"
if [ -n "$XCHECK" ]; then
  case "$XCHECK" in
    *未运行*) XCH_ST="未运行" ;;
    *)
      case "$XCHECK" in
        *base=OK*macc=OK*vdot=OK*) XCH_ST="达标" ;;
        *MISMATCH*)                XCH_ST="未达标" ;;
        *)                         XCH_ST="未运行" ;;
      esac ;;
  esac
fi

ALL_ST=("$IMG_ST" "$G0_ST" "$GOOD_ST" "$ABORT_ST" "$BAD_ST" "$FIELD_ST" "$MIS_ST" "$RC_ST" "$XCH_ST")
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
  REASON="normal(ok=$OK_IMG fail=$FAIL_IMG) g0(ok=$OK_G0 fail=$FAIL_G0) good=$GOOD_IMG/$GOOD_G0 abort=$ABORT bad=$BAD fields=$FIELD_ST hasfail=$HASFAIL_LINES rc=$RC_IMG/$RC_G0 xcheck=$XCH_ST"
fi

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/97-run-llm.sh",\n'
  printf '  "case_id": "perf_llm_attn",\n'
  printf '  "status": "%s",\n' "$ST"
  printf '  "note": "%s",\n' "$(jesc "清单外单例（不进 design/verify/cases/manifest.tsv，该文件冻结 30 行/a90d1071…）；只报指令数对比/拍数对比/内核吞吐对比，主分母=unfused_rvv_seq，vwmacc_rvv_seq 只作敏感性；emu≠硅")"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "machine_hours_planned": 0.5,\n'
  printf '  "mode": "single-case",\n'
  printf '  "provenance": {"emu": "%s", "emu_md5": "%s", "img": "%s", "img_md5": "%s", "g0": "%s", "g0_md5": "%s", "max_instr": "%s"},\n' \
    "$(jesc "$EMU")" "${EMU_MD5:-NA}" "$(jesc "$IMG")" "${IMG_MD5:-NA}" "$(jesc "$G0")" "${G0_MD5:-NA}" "$MAX_INSTR"
  printf '  "metrics": {"base_instr": "%s", "macc_instr": "%s", "vdot_instr": "%s", "base_slope_num": "%s", "base_slope_den": "%s", "macc_slope_num": "%s", "macc_slope_den": "%s", "vdot_slope_num": "%s", "vdot_slope_den": "%s", "base_r2_ppm": "%s", "macc_r2_ppm": "%s", "vdot_r2_ppm": "%s", "dots_per_arm": "%s", "denom": "unfused_rvv_seq"},\n' \
    "${BASE_INSTR:-}" "${MACC_INSTR:-}" "${VDOT_INSTR:-}" "${BASE_SN:-}" "${BASE_SD:-}" "${MACC_SN:-}" "${MACC_SD:-}" "${VDOT_SN:-}" "${VDOT_SD:-}" "${BASE_R2:-}" "${MACC_R2:-}" "${VDOT_R2:-}" "${DOTS_ARM:-}"
  printf '  "criteria": [\n'
  printf '    {"name": "normal_all_ok", "expected": "LLM_ATTN verdict=ALL_OK >=1 且 HAS_FAIL == 0", "actual": "ok=%s fail=%s", "status": "%s"},\n' "$OK_IMG" "$FAIL_IMG" "$IMG_ST"
  printf '    {"name": "g0_has_fail", "expected": "G0: HAS_FAIL >=1 且 ALL_OK == 0", "actual": "ok=%s fail=%s", "status": "%s"},\n' "$OK_G0" "$FAIL_G0" "$G0_ST"
  printf '    {"name": "good_trap", "expected": "两个镜像 HIT GOOD TRAP >= 1", "actual": "normal=%s g0=%s", "status": "%s"},\n' "$GOOD_IMG" "$GOOD_G0" "$GOOD_ST"
  printf '    {"name": "no_abort", "expected": "ABORT == 0", "actual": "%s", "status": "%s"},\n' "$ABORT" "$ABORT_ST"
  printf '    {"name": "no_bad_trap", "expected": "HIT BAD TRAP == 0", "actual": "%s", "status": "%s"},\n' "$BAD" "$BAD_ST"
  printf '    {"name": "llm_fields", "expected": "LLM_{base,macc,vdot}_instr 可解析且 >=1", "actual": "base=%s macc=%s vdot=%s", "status": "%s"},\n' "${BASE_INSTR:-NA}" "${MACC_INSTR:-NA}" "${VDOT_INSTR:-NA}" "$FIELD_ST"
  printf '    {"name": "no_mismatch_line", "expected": "无 *=MISMATCH / alt_differs=no", "actual": "%s", "status": "%s"},\n' "$HASFAIL_LINES" "$MIS_ST"
  printf '    {"name": "emu_rc", "expected": "rc == 0（两个镜像）", "actual": "normal=%s g0=%s", "status": "%s"},\n' "$RC_IMG" "$RC_G0" "$RC_ST"
  printf '    {"name": "static_xcheck", "expected": "LLM_ATTN static_xcheck … base=OK … macc=OK … vdot=OK", "actual": "%s", "status": "%s"}\n' "$(jesc "$XCHECK")" "$XCH_ST"
  printf '  ],\n'
  printf '  "verdict_line": "%s",\n' "$(jesc "$VERDICT_LINE")"
  printf '  "g0_verdict_line": "%s",\n' "$(jesc "$G0_VERDICT_LINE")"
  printf '  "artifacts": ["%s", "%s", "%s"]\n' "$(jesc "$LOG")" "$(jesc "$CLOG")" "$(jesc "$GLOG")"
  printf '}\n'
} >"$JSON"
cat "$JSON" | tee -a "$LOG"

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
