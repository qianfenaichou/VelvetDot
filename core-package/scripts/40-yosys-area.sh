#!/usr/bin/env bash
# =============================================================================
# 验证项：P2-1 Yosys 面积/级数（vmac-only 与 vdot 两版用同一段脚本对比）
# 预计机时：0.75（1 机时 = 1 计算节点 × 1 小时；P2 合计 1.5，含 50-formal-miter.sh）
# 状态：已在昆山实跑（`results/yosys/40-area-*.json`，最新作业 `126752216` `status=通过`）。
#       本行原写「未在任何节点执行」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/40-yosys-area.sh \
#          --vdot-rtl rtl/area/vdot_dp.sv --vdot-top vdot_dp \
#          --vmac-rtl rtl/area/vmac_only.sv --vmac-top vimac64b_only
#   bash scripts/40-yosys-area.sh --self-test     # 只测解析器（不需要 yosys/RTL）
# 注：yosys 0.48 的 read_verilog 不剥单引号，路径参数一律不加引号（2026-11-01 实测 ERROR: Can't open input file `'/path''）。
# 判据：两版各产出 cells / 晶体管估算 / ltp -noff 最长路径级数，并生成同口径对比表
# 报告口径：仅对数据通路模块综合，未含 VIMacU 其余部分，未含工艺库（design/ALGORITHM.md §3.5）
# 产物：results/yosys/40-area-<runid>.log|json|md、<top>.stat.json、<top>.stat.cmos.txt、<top>.ltp.txt
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ITEM="P2-yosys-formal"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
VDOT_RTL=""
VDOT_TOP="vdot_dp"
VMAC_RTL=""
VMAC_TOP="vimac64b_only"
SELF_TEST=0
DRY_RUN=0
CRITERIA=()
METRICS=()
STARTED_AT=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/yosys"
LOG_FILE="$OUT_DIR/40-area-$RUN_ID.log"
JSON_FILE="$OUT_DIR/40-area-$RUN_ID.json"
MD_FILE="$OUT_DIR/40-area-$RUN_ID.md"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="Yosys 面积/级数"

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '; }
add_criterion() { CRITERIA+=("    {\"name\": \"$(json_escape "$1")\", \"expected\": \"$(json_escape "$2")\", \"actual\": \"$(json_escape "$3")\", \"status\": \"$(json_escape "$4")\"}"); }
add_metrics() { METRICS+=("    {\"top\": \"$(json_escape "$1")\", \"cells\": \"$(json_escape "$2")\", \"transistors_est\": \"$(json_escape "$3")\", \"longest_path\": \"$(json_escape "$4")\", \"stat_json\": \"$(json_escape "$5")\", \"ltp_txt\": \"$(json_escape "$6")\"}"); }
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

module_init() {
  if ! type module >/dev/null 2>&1; then
    local f
    for f in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
      if [ -r "$f" ]; then . "$f"; break; fi
    done
  fi
  if type module >/dev/null 2>&1; then
    set +u
    module load compiler/gcc/13.3.0 || log "[WARN] module load compiler/gcc/13.3.0 失败"
    module load compiler/cmake/3.25.0 || log "[WARN] module load compiler/cmake/3.25.0 失败"
    module load apps/python/3.8.13 || log "[WARN] module load apps/python/3.8.13 失败"
    set -u
  else
    log "[WARN] module 命令不可用：跳过 module load"
  fi
  if [ -r "$TOOLS_DIR/env.sh" ]; then . "$TOOLS_DIR/env.sh"; log "已 source $TOOLS_DIR/env.sh"; fi
  hash -r
}

write_json() { # status
  local status="$1" tmp="$JSON_FILE.tmp" i n
  mkdir -p "$OUT_DIR"
  {
    printf '{\n'
    printf '  "schema": "vdot-verify/1",\n'
    printf '  "item": "%s",\n' "$ITEM"
    printf '  "script": "scripts/%s",\n' "$SCRIPT_NAME"
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "platform": "%s",\n' "$( [ -n "${SLURM_JOB_ID:-}" ] && echo "${SLURM_JOB_PARTITION:-slurm}" || echo "login-node" )"
    printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
    printf '  "started_at": "%s",\n' "$STARTED_AT"
    printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
    printf '  "machine_hours_planned": 0.75,\n'
    printf '  "mode": "%s",\n' "$( [ "$SELF_TEST" = "1" ] && echo self-test || echo area )"
    printf '  "scope": "仅 vdot 数据通路模块，未含 VIMacU 其余部分，未含工艺库",\n'
    printf '  "criteria": [\n'
    n=${#CRITERIA[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CRITERIA[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "metrics": [\n'
    n=${#METRICS[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${METRICS[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "artifacts": ["%s", "%s"]\n' "$LOG_FILE" "$MD_FILE"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  log "结果 JSON：$JSON_FILE"
}

# 解析 yosys 产物（纯 Python 只读 JSON，不参与综合）
parse_top() { # $1 top  $2 stat_json  $3 cmos_txt  $4 ltp_txt  -> stdout "cells<TAB>transistors<TAB>path"
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, re, sys
top, sj, cmos, ltp = sys.argv[1:5]
cells = ""
try:
    with open(sj) as f:
        data = json.load(f)
    mods = data.get("modules", {})
    m = mods.get(top) or (next(iter(mods.values())) if mods else {})
    cells = str(m.get("num_cells", ""))
except Exception:
    cells = ""
tr = ""
try:
    txt = open(cmos, errors="replace").read()
    mm = re.findall(r"Estimated number of transistors:\s*([0-9]+)", txt)
    if mm:
        tr = mm[-1]
except Exception:
    tr = ""
path = ""
try:
    txt = open(ltp, errors="replace").read()
    mm = re.findall(r"Longest topological path[^\n]*?\(length=([0-9]+)\)", txt)
    if mm:
        path = mm[-1]
except Exception:
    path = ""
print("%s\t%s\t%s" % (cells, tr, path))
PY
}

synthesize() { # $1 rtl  $2 top  $3 prefix
  local rtl="$1" top="$2" prefix="$3"
  [ -f "$rtl" ] || { log "[跳过] 缺 RTL：$rtl"; return 1; }
  local sj="$OUT_DIR/${prefix}.stat.json" cm="$OUT_DIR/${prefix}.stat.cmos.txt" lt="$OUT_DIR/${prefix}.ltp.txt"
  log "== yosys: $top <= $rtl =="
  # 命令顺序固定取自 design/ALGORITHM.md §3.5：synth -> flatten -> stat -json -> ltp -noff
  run yosys -l "$OUT_DIR/${prefix}.yosys.log" -p \
    "read_verilog -sv $rtl; synth -top $top; flatten; tee -o $sj stat -json; tee -o $cm stat -tech cmos; tee -o $lt ltp -noff" \
    || { log "[WARN] yosys 失败：$top"; return 1; }
  local parsed cells tr path
  parsed="$(parse_top "$top" "$sj" "$cm" "$lt")"
  cells="$(printf '%s' "$parsed" | cut -f1)"
  tr="$(printf '%s' "$parsed" | cut -f2)"
  path="$(printf '%s' "$parsed" | cut -f3)"
  log "解析：cells=${cells:-未解析} transistors=${tr:-未解析} longest_path=${path:-未解析}"
  add_metrics "$top" "${cells:-未解析}" "${tr:-未解析}" "${path:-未解析}" "$sj" "$lt"
  if [ -n "$cells" ] && [ -n "$tr" ] && [ -n "$path" ]; then return 0; fi
  return 1
}

self_test() {
  log "== self-test：解析器夹具（不调用 yosys）=="
  local d="$OUT_DIR/selftest-$RUN_ID"
  mkdir -p "$d"
  cat >"$d/stat.json" <<'JSON'
{"modules": {"demo_top": {"num_cells": 123, "num_cells_by_type": {"AND": 100, "XOR": 23}}}}
JSON
  cat >"$d/cmos.txt" <<'TXT'
=== demo_top ===
Estimated number of transistors: 1750
TXT
  cat >"$d/ltp.txt" <<'TXT'
Longest topological path in demo_top (length=17)
TXT
  local parsed cells tr path
  parsed="$(parse_top demo_top "$d/stat.json" "$d/cmos.txt" "$d/ltp.txt")"
  cells="$(printf '%s' "$parsed" | cut -f1)"
  tr="$(printf '%s' "$parsed" | cut -f2)"
  path="$(printf '%s' "$parsed" | cut -f3)"
  log "selftest 解析：cells=$cells transistors=$tr path=$path（期望 123 / 1750 / 17）"
  if [ "$cells" = "123" ] && [ "$tr" = "1750" ] && [ "$path" = "17" ]; then
    add_criterion "parser_selftest" "解析 123 / 1750 / 17" "$cells / $tr / $path" "达标"
    write_json "通过"
    log "self-test 通过：产物是 P2-yosys-selftest，不是 P2-1 面积证据"
    exit 0
  fi
  add_criterion "parser_selftest" "解析 123 / 1750 / 17" "$cells / $tr / $path" "未达标"
  write_json "失败"
  exit 1
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --vdot-rtl) VDOT_RTL="${2:?--vdot-rtl 需要参数}"; shift 2 ;;
      --vdot-top) VDOT_TOP="${2:?--vdot-top 需要参数}"; shift 2 ;;
      --vmac-rtl) VMAC_RTL="${2:?--vmac-rtl 需要参数}"; shift 2 ;;
      --vmac-top) VMAC_TOP="${2:?--vmac-top 需要参数}"; shift 2 ;;
      --self-test) SELF_TEST=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  # --self-test 只验证解析器，绝不能冒充 P2-1 面积证据：独立 item 与独立文件名（M6）
  if [ "$SELF_TEST" = "1" ]; then
    ITEM="P2-yosys-selftest"
    LOG_FILE="$OUT_DIR/40-selftest-$RUN_ID.log"
    JSON_FILE="$OUT_DIR/40-selftest-$RUN_ID.json"
    MD_FILE="$OUT_DIR/40-selftest-$RUN_ID.md"
  fi
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR"
  METRICS=()
  log "===== $SCRIPT_NAME dry_run=$DRY_RUN self_test=$SELF_TEST ====="
  module_init

  if [ "$SELF_TEST" = "1" ]; then self_test; fi

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] 综合属重计算，禁止在登录节点执行。提交：" >&2
    echo "  sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 ${SCRIPT_PATH} --vdot-rtl ... --vmac-rtl ..." >&2
    exit 3
  fi
  if ! command -v yosys >/dev/null 2>&1; then
    add_criterion "tool_yosys" "yosys 可用" "MISSING（先跑 00-env-check.sh --install）" "未运行"
    write_json "未运行"; log "未运行：缺 yosys"; exit 2
  fi
  log "yosys=$(yosys -V 2>/dev/null | sed -n '1p')"
  add_criterion "tool_yosys" "yosys 可用" "$(yosys -V 2>/dev/null | sed -n '1p')" "达标"

  if [ ! -f "$VDOT_RTL" ] || [ ! -f "$VMAC_RTL" ]; then
    add_criterion "rtl_inputs" "vdot 与 vmac-only 两版 RTL 齐备" \
      "vdot=${VDOT_RTL:-未给} vmac=${VMAC_RTL:-未给}（RTL 未产出时属正常）" "未运行"
    write_json "未运行"; log "未运行：缺 RTL 输入"; exit 2
  fi

  local ok=0
  synthesize "$VMAC_RTL" "$VMAC_TOP" "vmac_only" || ok=1
  synthesize "$VDOT_RTL" "$VDOT_TOP" "vdot" || ok=1
  if [ "$ok" = "0" ]; then
    add_criterion "two_tops" "两版均产出 cells/transistors/longest_path" "vmac_only + $VDOT_TOP" "达标"
  else
    add_criterion "two_tops" "两版均产出 cells/transistors/longest_path" "至少一版解析失败" "未达标"
  fi

  # 对比表（Markdown）
  {
    echo "| top | cells | 晶体管估算（stat -tech cmos） | 最长拓扑路径（ltp -noff） |"
    echo "|---|---|---|---|"
    local m
    for m in ${METRICS[@]+"${METRICS[@]}"}; do
      printf '%s\n' "$m" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read().strip().rstrip(","))
print("| %s | %s | %s | %s |" % (d["top"], d["cells"], d["transistors_est"], d["longest_path"]))
'
    done
  } >"$MD_FILE"
  log "对比表：$MD_FILE"

  local c
  for c in ${CRITERIA[@]+"${CRITERIA[@]}"}; do
    case "$c" in *'"未达标"'*|*'"未运行"'*) ok=1 ;; esac
  done
  if [ "$ok" = "0" ]; then write_json "通过"; log "判据：达标"; exit 0; fi
  write_json "失败"; log "判据：未达标"; exit 1
}

# 机时记账脚本定位：昆山实际落位是 $CORE_DIR/core-package/scripts/（验证包整体在 ~/core/core-package/，
# 平台落位实测），**$CORE_DIR/scripts/ 并不存在** ⇒ 旧 trap 的
# `[ -x "$CORE_DIR/scripts/90-budget-log.sh" ]` 恒为假 ⇒ auto 记账从未落盘。
# 依次兼容三种布局：core-package/scripts/（昆山实际）→ scripts/（扁平/文档口径）→ 与本脚本同目录（随包同发）。
budget_log_script() {
  local c here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for c in "$CORE_DIR/core-package/scripts/90-budget-log.sh" \
           "$CORE_DIR/scripts/90-budget-log.sh" \
           "$here/90-budget-log.sh"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# 一次作业只记一次账：父脚本（30-hello-nodeip.sh）已按同一 job_id 记过时，子脚本跳过（record 不去重）。
trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$BUDGET_ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
