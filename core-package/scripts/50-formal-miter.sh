#!/usr/bin/env bash
# =============================================================================
# 验证项：P2-2 形式验证（vdot_dp 组合 miter，DUT vs 位级金模型）
# 预计机时：0.75（1 机时 = 1 计算节点 × 1 小时；P2 合计 1.5，含 40-yosys-area.sh）
# 状态：已在昆山实跑（`results/formal/50-miter-*.json`，最新作业 `126751660` `status=通过`，正控 SUCCESS / 负控 FAIL）。
#       本行原写「未在任何节点执行」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 scripts/50-formal-miter.sh \
#          --miter rtl/formal/vdot_dp_miter_full.sv --dut VdotReduce --ref vdot_dp_spec
#   sbatch ... 50-formal-miter.sh --miter ... --dut VdotReduce --ref vdot_dp_spec --mutant <bug 版文件>
#   （负控用 --mutant 指向改动 1 bit 的 miter 副本，由实施阶段产出；本包不内置任何 vdot RTL）
#   sbatch ... 50-formal-miter.sh --self-check        # 只用内建微模块验证 yosys SAT 流程可判别
# 注：yosys 0.48 的 read_verilog 不剥单引号，路径参数一律不加引号（2026-11-01 实测 ERROR: Can't open input file `'/path''）。
# 判据：正向输出含 "SAT proof finished - no model found: SUCCESS!"；
#       --mutant 必须含 "model found: FAIL!"；--self-check 的坏例子必须 FAIL
# 报告口径：只证数据通路，不覆盖流水/发射/旁路（design/ALGORITHM.md §3.5）
# 产物：results/formal/50-miter-<runid>.log|json
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ITEM="P2-yosys-formal"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
MITER=""
DUT="${DUT:-VdotReduce}"
REF="${REF:-vdot_dp_spec}"
STROBE="${STROBE:-in_io_fireS1}"
TOP="miter"
MUTANT=""
SELF_CHECK=0
DRY_RUN=0
CRITERIA=()
STARTED_AT=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/formal"
LOG_FILE="$OUT_DIR/50-miter-$RUN_ID.log"
JSON_FILE="$OUT_DIR/50-miter-$RUN_ID.json"
BUDGET_ITEM="$ITEM"
readonly PURPOSE="形式 miter"

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
    printf '  "scope": "只证数据通路（vdot_dp），不覆盖流水/发射/旁路",\n'
    printf '  "miter": "%s",\n' "$(json_escape "${MITER:-内建 self-check}")"
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

# 运行一次 yosys SAT 等价判定
# $1 = 文件  $2 = DUT 模块名  $3 = 金模型模块名  $4 = 输出日志  $5 = 模式（seq|combo）
# 配方照 yosys 官方 tests/various/cellarray_array_connections.ys（miter 等价判定）：
#   read_verilog -formal -sv; hierarchy -check; proc; miter -equiv -make_assert -flatten A B miter; sat -verify -prove-asserts miter
# 实测要点（2026-11-01，yosys 0.48）：
#   · 手写 always @(*)/@(posedge) 的 assert 会生成 $check 单元，sat 要么报
#     「Failed to import cell …(type $check)」要么静默不导入（= 空绿），因此断言一律交给 miter 生成；
#   · read_verilog 的路径参数**不能加单引号**（0.48 不剥引号，会当成文件名）；
#   · VdotReduce 的输出口带 fireS1 寄存器 → 用 seq 模式：-DSYNTHESIS 去掉生成 RTL 的仿真初值/随机初值、
#     chformal -skip 1 跳过第一拍（两侧寄存器初值不受本设计控制）、并把 strobe 端口（miter 里叫
#     in_io_fireS1）在三拍内固定为 1，比较的就是「写过后」的值；
#   · combo 模式给纯组合内建微模块用（self-check），不需要 skip 也不需要 strobe。
run_sat() {
  local file="$1" dut="$2" ref="$3" outlog="$4" mode="${5:-seq}"
  local chain
  if [ "$mode" = "combo" ]; then
    chain="read_verilog -formal -sv -DSYNTHESIS $file; hierarchy -check; proc; miter -equiv -make_assert -flatten $dut $ref miter; sat -verify -prove-asserts miter"
  else
    chain="read_verilog -formal -sv -DSYNTHESIS $file; hierarchy -check; proc; miter -equiv -make_assert -flatten $dut $ref miter; chformal -skip 1; sat -verify -prove-asserts -seq 3 -set-at 1 $STROBE 1 -set-at 2 $STROBE 1 -set-at 3 $STROBE 1 miter"
  fi
  run yosys -l "$outlog" -p "$chain"
}

self_check() {
  log "== self-check：内建微模块验证 yosys SAT 流程能区分对/错（不涉及 vdot RTL）=="
  local d="$OUT_DIR/selfcheck-$RUN_ID"
  mkdir -p "$d"
  cat >"$d/flow_ok.v" <<'V'
module vdot_flow_ok(input [7:0] a, input [7:0] b, output [8:0] y);
  assign y = a + b;
endmodule
module vdot_flow_ref(input [7:0] a, input [7:0] b, output [8:0] y);
  assign y = a + b;
endmodule
V
  cat >"$d/flow_bug.v" <<'V'
module vdot_flow_bug(input [7:0] a, input [7:0] b, output [8:0] y);
  assign y = a + b + 9'd1;   // 故意注入 1 的偏差（应与 vdot_flow_ref 不等）
endmodule
V
  local ok_rc=0 bug_rc=0
  run_sat "$d/flow_ok.v" vdot_flow_ok vdot_flow_ref "$d/flow_ok.yosys.log" combo || ok_rc=$?
  cp "$d/flow_ok.v" "$d/flow_bug.v"  # 同一 dut，ref 换成注入偏差的版本
  cat >> "$d/flow_bug.v" <<'BUGV'
BUGV
  run_sat "$d/flow_bug.v" vdot_flow_ok vdot_flow_bug "$d/flow_bug.yosys.log" combo || bug_rc=$?
  local ok_hit=0 bug_hit=0
  grep -q 'no model found: SUCCESS' "$d/flow_ok.yosys.log" 2>/dev/null && ok_hit=1
  grep -q 'model found: FAIL' "$d/flow_bug.yosys.log" 2>/dev/null && bug_hit=1
  log "self-check：正确模块 SUCCESS=$ok_hit 坏模块 FAIL=$bug_hit（rc=$ok_rc/$bug_rc）"
  if [ "$ok_hit" = "1" ] && [ "$bug_hit" = "1" ]; then
    add_criterion "flow_selfcheck" "正确模块 SUCCESS 且坏模块 FAIL" "SUCCESS=$ok_hit FAIL=$bug_hit" "达标"
    return 0
  fi
  add_criterion "flow_selfcheck" "正确模块 SUCCESS 且坏模块 FAIL" "SUCCESS=$ok_hit FAIL=$bug_hit" "未达标"
  return 1
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --miter) MITER="${2:?--miter 需要参数}"; shift 2 ;;
      --top) TOP="${2:?--top 需要参数}"; shift 2 ;;
      --dut) DUT="${2:?--dut 需要参数}"; shift 2 ;;
      --ref) REF="${2:?--ref 需要参数}"; shift 2 ;;
      --strobe) STROBE="${2:?--strobe 需要参数}"; shift 2 ;;
      --mutant) MUTANT="${2:?--mutant 需要参数}"; shift 2 ;;
      --self-check) SELF_CHECK=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  if [ "$SELF_CHECK" = "1" ]; then
    # self-check 只是流程自检，产物在文件名与 item 上与正式 P2-2 证据隔离（防状态采集误采）
    ITEM="self-check"
    BUDGET_ITEM="P2-yosys-formal-selfcheck"
    LOG_FILE="$OUT_DIR/50-selfcheck-$RUN_ID.log"
    JSON_FILE="$OUT_DIR/50-selfcheck-$RUN_ID.json"
  fi
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR"
  log "===== $SCRIPT_NAME top=$TOP mutant=${MUTANT:-无} self_check=$SELF_CHECK ====="
  module_init

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] 形式验证属重计算，禁止在登录节点执行。提交：" >&2
    echo "  sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 ${SCRIPT_PATH} --miter <file> --top <top>" >&2
    exit 3
  fi
  if ! command -v yosys >/dev/null 2>&1; then
    add_criterion "tool_yosys" "yosys 可用" "MISSING（先跑 00-env-check.sh --install）" "未运行"
    write_json "未运行"; log "未运行：缺 yosys"; exit 2
  fi
  log "yosys=$(yosys -V 2>/dev/null | sed -n '1p')"

  local ok=0
  if [ "$SELF_CHECK" = "1" ]; then self_check || ok=1; fi

  if [ -z "$MITER" ]; then
    if [ "$SELF_CHECK" = "1" ]; then
      write_json "$( [ "$ok" = "0" ] && echo 通过 || echo 失败 )"
      exit "$ok"
    fi
    add_criterion "miter_input" "miter 文件齐备" "未给 --miter（RTL 未产出时属正常）" "未运行"
    write_json "未运行"; log "未运行：未给 --miter"; exit 2
  fi
  [ -f "$MITER" ] || {
    add_criterion "miter_input" "miter 文件齐备" "不存在：$MITER" "未运行"
    write_json "未运行"; log "未运行：miter 不存在"; exit 2
  }

  local mlog="$OUT_DIR/${TOP}.$RUN_ID.yosys.log"
  local rc=0
  run_sat "$MITER" "$DUT" "$REF" "$mlog" seq || rc=$?
  local hit=0
  grep -q 'no model found: SUCCESS' "$mlog" 2>/dev/null && hit=1
  log "正向 miter：rc=$rc SUCCESS=$hit（日志 $mlog）"
  if [ "$hit" = "1" ]; then
    add_criterion "miter_prove" "SAT proof finished - no model found: SUCCESS!" "SUCCESS" "达标"
  else
    add_criterion "miter_prove" "SAT proof finished - no model found: SUCCESS!" "未出现 SUCCESS（rc=$rc）" "未达标"
    ok=1
  fi

  if [ -n "$MUTANT" ]; then
    [ -f "$MUTANT" ] || {
      add_criterion "miter_mutant" "mutant 必须 FAIL" "不存在：$MUTANT" "未运行"
      ok=1
    }
    if [ -f "$MUTANT" ]; then
      local blog="$OUT_DIR/${TOP}.mutant.$RUN_ID.yosys.log" brc=0 bhit=0
      run_sat "$MUTANT" "$DUT" "$REF" "$blog" seq || brc=$?
      grep -q 'model found: FAIL' "$blog" 2>/dev/null && bhit=1
      log "负控 mutant：rc=$brc FAIL=$bhit（日志 $blog）"
      if [ "$bhit" = "1" ]; then
        add_criterion "miter_mutant" "负控必须报 model found: FAIL!" "FAIL" "达标"
      else
        add_criterion "miter_mutant" "负控必须报 model found: FAIL!" "未出现 FAIL（miter 可能空转）" "未达标"
        ok=1
      fi
    fi
  else
    # 无负控不得记通过（README 硬性规定）：正向 SUCCESS 照记，但整体不得是「通过」。
    add_criterion "miter_mutant" "负控 mutant 必须 FAIL（通过的必要条件）" "未提供 --mutant：正向 SUCCESS 不构成达标证据" "未运行"
    if [ "$ok" != "0" ]; then
      write_json "失败"
      log "失败：正向 miter 未达标，且缺 --mutant 负控"
      exit 1
    fi
    write_json "未运行"
    log "未运行：缺 --mutant 负控；正向结果只记入 criteria，不记通过"
    exit 2
  fi

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
