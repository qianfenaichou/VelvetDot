#!/usr/bin/env bash
# =============================================================================
# 验证项：2.2 RTL lint（Verilator --lint-only，vdot 相关生成 RTL 闭包）
# 预计机时：<0.05（单文件闭包，秒级；仍必须走计算节点——登录节点禁跑 verilator，
#           ）
# 状态：2026-11-04 新增（交付物 2.2 的「lint 通过」判据此前一直记「未运行：无 lint 工具链」；
#       实测昆山 `~/tools/verilator/bin/verilator`（5.053 devel）可用，因此补充本脚本）
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   sbatch -p kshcnormal -N 1 -n 4 --time=00:15:00 core-package/scripts/25-rtl-lint.sh \
#          --rtl-dir /public/home/$USER/core/src/XiangShan/build/rtl
#   参数：--rtl-dir DIR（默认 $CORE_DIR/src/XiangShan/build/rtl）
#         --timeout S（默认 600；单次 verilator 调用上限）
#         --dry-run
# 判据：verilator --lint-only 退出码 0 且输出中 `%Error` 计 0 行（warning 只统计不阻断；
#       -Wno-fatal 只把 warning 降级，**不掩盖 error**）
# 产物：results/lint/25-rtl-lint-<runid>.log|json
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

# sbatch 会把脚本复制成 slurm_script 再执行 ⇒ BASH_SOURCE 取不到原名，JSON 里固定写实名。
readonly SCRIPT_NAME="25-rtl-lint.sh"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P2-yosys-formal"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="2.2 RTL verilator lint"

CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
RTL_DIR="${RTL_DIR:-$CORE_DIR/src/XiangShan/build/rtl}"
LINT_TIMEOUT="${LINT_TIMEOUT:-600}"
DRY_RUN=0
CRITERIA=()
METRICS=()
STARTED_AT=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/lint"
readonly LOG_FILE="$OUT_DIR/25-rtl-lint-$RUN_ID.log"
readonly JSON_FILE="$OUT_DIR/25-rtl-lint-$RUN_ID.json"

# lint 目标（两个 top，各自闭包）：
#   ① VdotReduce（X-new）：自身 + 它实例化的两级 CSA（CSA_Nto2With3to2MainPipeline_5 →
#      CSA4to2_15）。VdotReduce 无 include/import（`grep -cE 'include|import'` = 0），三文件自洽。
#   ② VIMac64b（X15 端口改动位置：显式导出 `fireS1`）：实测 1 个 module、0 个子模块实例、
#      0 include/import ⇒ 单文件自洽，可直接 lint。
readonly LINT_GROUPS=(
  "VdotReduce:VdotReduce.sv,CSA_Nto2With3to2MainPipeline_5.sv,CSA4to2_15.sv"
  "VIMac64b:VIMac64b.sv"
)

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
json_escape() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '; }
add_criterion() { CRITERIA+=("    {\"name\": \"$(json_escape "$1")\", \"expected\": \"$(json_escape "$2")\", \"actual\": \"$(json_escape "$3")\", \"status\": \"$(json_escape "$4")\"}"); }
add_metrics() { METRICS+=("    $1"); }
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

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

write_json() { # status reason extra...
  local status="$1"; shift
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
    printf '  "tool": {"verilator": "%s"},\n' "$(json_escape "${VERILATOR_VER:-}")"
    printf '  "rtl_dir": "%s",\n' "$(json_escape "$RTL_DIR")"
    printf '  "criteria": [\n'
    local i=0 n=${#CRITERIA[@]}
    for c in "${CRITERIA[@]:-}"; do
      i=$((i + 1))
      printf '%s%s\n' "$c" "$( [ "$i" -lt "$n" ] && echo , )"
    done
    printf '  ],\n'
    printf '  "metrics": [\n'
    i=0; n=${#METRICS[@]}
    for c in "${METRICS[@]:-}"; do
      i=$((i + 1))
      printf '%s%s\n' "$c" "$( [ "$i" -lt "$n" ] && echo , )"
    done
    printf '  ]\n}\n'
  } >"$JSON_FILE.tmp"
  mv "$JSON_FILE.tmp" "$JSON_FILE"
}

usage() { sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --rtl-dir) RTL_DIR="${2:?--rtl-dir 需要参数}"; shift 2 ;;
      --timeout) LINT_TIMEOUT="${2:?--timeout 需要参数}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] verilator 属重计算，禁止在登录节点执行。" >&2
    echo "        提交：sbatch -p kshcnormal -N 1 -n 4 --time=00:15:00 ${SCRIPT_PATH}" >&2
    exit 3
  fi

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR"
  [ -r "$TOOLS_DIR/env.sh" ] && . "$TOOLS_DIR/env.sh" >/dev/null 2>&1 || true
  hash -r
  log "===== $SCRIPT_NAME job=$SLURM_JOB_ID host=$(hostname) ====="

  if [ "$DRY_RUN" != "1" ] && ! command -v verilator >/dev/null 2>&1; then
    log "[FATAL] PATH 上没有 verilator（先 source $TOOLS_DIR/env.sh；昆山装的是 ~/tools/verilator）"
    exit 2
  fi
  VERILATOR_VER="$(verilator --version 2>/dev/null | sed -n '1p')"
  log "verilator=$VERILATOR_VER rtl_dir=$RTL_DIR"

  [ -d "$RTL_DIR" ] || { log "[FATAL] 缺 RTL 目录：$RTL_DIR"; exit 2; }
  add_criterion "verilator_available" "PATH 上有 verilator（~/tools/verilator）" "$VERILATOR_VER" "达标"

  local grp top flist files f out rc errs warns total_errs=0 total_warns=0 grp_fail=0
  local -a _names
  for grp in "${LINT_GROUPS[@]}"; do
    top="${grp%%:*}"
    flist="${grp#*:}"
    files=()
    IFS=',' read -r -a _names <<<"$flist"
    for f in "${_names[@]}"; do
      [ -f "$RTL_DIR/$f" ] || { log "[FATAL] 缺 RTL 文件：$RTL_DIR/$f（top=$top）"; exit 2; }
      files+=("$RTL_DIR/$f")
    done
    log "lint 闭包（top=$top，${#files[@]} 个文件）：${_names[*]}"
    add_criterion "lint_files_present:$top" "闭包文件存在" "${_names[*]}" "达标"

    out="$OUT_DIR/25-verilator-$top-$RUN_ID.log"; rc=0
    log "== verilator --lint-only -Wno-fatal --top-module $top =="
    if [ "$DRY_RUN" = "1" ]; then
      log "[dry-run] verilator --lint-only -Wno-fatal --top-module $top ${files[*]}"
    else
      timeout "$LINT_TIMEOUT" verilator --lint-only -Wno-fatal --top-module "$top" \
        "${files[@]}" >"$out" 2>&1 || rc=$?
    fi
    errs="$(grep -c '%Error' "$out" 2>/dev/null || true)"; errs="${errs:-0}"
    warns="$(grep -c '%Warning' "$out" 2>/dev/null || true)"; warns="${warns:-0}"
    total_errs=$((total_errs + errs)); total_warns=$((total_warns + warns))
    log "top=$top verilator rc=$rc %Error=$errs %Warning=$warns 输出=$out"
    if [ "$rc" != "0" ] || [ "$errs" -gt 0 ]; then
      grp_fail=1
      log "---- $top verilator 输出（首 60 行）----"
      sed -n '1,60p' "$out" | tee -a "$LOG_FILE" | sed 's/^/  /'
    fi
    add_metrics "{\"top\": \"$(json_escape "$top")\", \"rc\": \"$rc\", \"errors\": \"$errs\", \"warnings\": \"$warns\", \"raw_log\": \"$(json_escape "$out")\"}"
  done

  if [ "$DRY_RUN" = "1" ]; then
    write_json "未运行" "reason=dry-run"
    log "dry-run：未判定"
    exit 2
  fi
  add_criterion "lint_exit0" "两个 top 的 verilator --lint-only 均退出码 0" "失败组数=$grp_fail" "$( [ "$grp_fail" = "0" ] && echo 达标 || echo 未达标 )"
  add_criterion "lint_no_error" "输出 %Error 合计 0 行" "%Error=$total_errs" "$( [ "$total_errs" = "0" ] && echo 达标 || echo 未达标 )"
  if [ "$grp_fail" != "0" ] || [ "$total_errs" -gt 0 ]; then
    write_json "失败" "reason=lint-nonzero" "error_total=$total_errs"
    log "[FAIL] lint 未达标（%Error=$total_errs）"
    exit 1
  fi
  write_json "通过" "limit=lint-only(no elaboration/sim)" "warning_total=$total_warns"
  log "[OK] lint 达标：两个 top 全部 rc=0 %Error=0 %Warning 合计=$total_warns"
  exit 0
}

trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$BUDGET_ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
