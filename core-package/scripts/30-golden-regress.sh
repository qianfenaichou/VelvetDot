#!/usr/bin/env bash
# =============================================================================
# 验证项：P1 金模型回归（1142 cases，算法 A/B/C 交叉）
# 预计机时：0.1（1 机时 = 1 计算节点 × 1 小时）；纯 Python，秒级
# 状态：待跑 —— 本包只设计与落位，本脚本未在昆山执行过
# 分区：kshcnormal（CPU）。本项也可在登录节点跑（--local），因为只有秒级 Python 计算；
#       JSON 的 platform 会如实记 login-node，不冒充计算节点证据
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   sbatch -p kshcnormal -N 1 -n 2 --time=00:06:00 scripts/30-golden-regress.sh
#   bash scripts/30-golden-regress.sh --local      # 登录节点允许（纯 Python，秒级）
#   参数：--local --verify-dir DIR --dry-run
# 判据：verify/vdot_model_test.py 退出码 0 且 stdout 含 "ALL TESTS PASSED (1142 cases)"
# 产物：results/golden/30-golden-<runid>.log|json
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P1-golden"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
VERIFY_DIR="${CORE_DIR}/verify"
LOCAL_OK=0
DRY_RUN=0
CRITERIA=()
STARTED_AT=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/golden"
readonly LOG_FILE="$OUT_DIR/30-golden-$RUN_ID.log"
readonly JSON_FILE="$OUT_DIR/30-golden-$RUN_ID.json"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="金模型回归"

# 期望的用例数：1142（1142 = 旧 1132 + 新增 10；vdot_model_test.py 实测同值）
readonly EXPECTED_CASES="1142"

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
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

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
    printf '  "machine_hours_planned": 0.1,\n'
    printf '  "verify_dir": "%s",\n' "$(json_escape "$VERIFY_DIR")"
    printf '  "criteria": [\n'
    n=${#CRITERIA[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CRITERIA[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "artifacts": ["%s"]\n' "$LOG_FILE"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  log "结果 JSON：$JSON_FILE"
}

module_init() {
  # 只加载 python：金模型不需要编译器；gcc/cmake 加载会在旧节点上拖慢启动
  if ! type module >/dev/null 2>&1; then
    local f
    for f in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
      if [ -r "$f" ]; then . "$f"; break; fi
    done
  fi
  if type module >/dev/null 2>&1; then
    set +u
    module load apps/python/3.8.13 || log "[WARN] module load apps/python/3.8.13 失败（将用默认 python3）"
    set -u
  fi
  hash -r
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --local) LOCAL_OK=1; shift ;;
      --verify-dir) VERIFY_DIR="${2:?--verify-dir 需要参数}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ] && [ "$LOCAL_OK" != "1" ]; then
    echo "[FATAL] 未在作业内。本项虽轻，默认仍要求走调度器；确需在登录节点跑请显式加 --local。" >&2
    exit 3
  fi

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR"
  log "===== $SCRIPT_NAME verify_dir=$VERIFY_DIR local=$LOCAL_OK dry_run=$DRY_RUN ====="
  module_init
  log "python3=$(command -v python3) $(python3 -V 2>&1 | sed -n '1p')"

  [ -f "$VERIFY_DIR/vdot_model.py" ] || {
    add_criterion "golden_files" "verify/vdot_model.py 与 vdot_model_test.py 存在" "缺 vdot_model.py" "未运行"
    write_json "未运行"; log "未运行：缺金模型文件"; exit 2; }
  [ -f "$VERIFY_DIR/vdot_model_test.py" ] || {
    add_criterion "golden_files" "verify/vdot_model.py 与 vdot_model_test.py 存在" "缺 vdot_model_test.py" "未运行"
    write_json "未运行"; log "未运行：缺测试文件"; exit 2; }
  add_criterion "golden_files" "verify/ 三件存在" "$VERIFY_DIR" "达标"

  local out rc=0
  log "== 运行 python3 vdot_model_test.py =="
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] python3 $VERIFY_DIR/vdot_model_test.py"
    out="(dry-run)"
  else
    out="$(python3 "$VERIFY_DIR/vdot_model_test.py" 2>&1)" || rc=$?
    printf '%s\n' "$out" | tee -a "$LOG_FILE"
  fi

  if [ "$rc" = "0" ]; then
    add_criterion "model_test_exit" "退出码 0" "rc=0" "达标"
  else
    add_criterion "model_test_exit" "退出码 0" "rc=$rc" "未达标"
  fi

  local line cases
  line="$(printf '%s\n' "$out" | grep -E 'ALL TESTS PASSED \([0-9]+ cases\)' | tail -n 1 || true)"
  cases="$(printf '%s' "$line" | sed -n 's/.*(\([0-9][0-9]*\) cases).*/\1/p')"
  if [ -n "${cases:-}" ]; then
    add_criterion "all_tests_passed" "stdout 含 ALL TESTS PASSED ($EXPECTED_CASES cases)" "$line" "达标"
    if [ "$cases" = "$EXPECTED_CASES" ]; then
      add_criterion "case_count" "用例数 = $EXPECTED_CASES" "$cases" "达标"
    else
      add_criterion "case_count" "用例数 = $EXPECTED_CASES" "$cases" "未达标"
    fi
  else
    add_criterion "all_tests_passed" "stdout 含 ALL TESTS PASSED ($EXPECTED_CASES cases)" "未匹配（rc=$rc）" "未达标"
    add_criterion "case_count" "用例数 = $EXPECTED_CASES" "未能解析" "未达标"
  fi

  local ok=0 c
  for c in ${CRITERIA[@]+"${CRITERIA[@]}"}; do
    case "$c" in *'"未达标"'*) ok=1 ;; esac
  done
  if [ "$ok" = "0" ]; then
    write_json "通过"; log "判据：金模型回归达标"; exit 0
  fi
  write_json "失败"; log "判据：金模型回归未达标"; exit 1
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
