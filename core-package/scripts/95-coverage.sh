#!/usr/bin/env bash
# =============================================================================
# 验证项：P4-coverage（内部编号；官方 12 项无「代码覆盖率」，对应评分项 = 可行性 10 分格的
#         「功能验证有效性」+ 3.1.2 协同仿真的量化补强，见早期统计 §1）
# 预计机时：1.0–2.0（EMU_COVERAGE=1 重建 ≤1.0 + 30 例覆盖运行 ≤2.0，含余量按 4.0 上限申请）
# 状态：**干跑已执行、覆盖作业未提交**：本地与昆山登录节点各跑过一次 `--dry-run`（30 例全记「未运行(dry-run)」，
#       见 stage3/3.1.2-difftest/coverage/evidence/95-dryrun-*）；真正覆盖作业因预算硬闸未放行而未提交（见下「预算闸」）
# 分区：kshcnormal（CPU）。不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印任何密钥文件
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 32 --time=04:00:00 \
#     core-package/scripts/95-coverage.sh --manifest ~/core/test/manifest.30.tsv \
#       --ref-so ~/core/src/NEMU/build/riscv64-nemu-interpreter-so --timeout 2400
#   参数：--manifest FILE  --ref-so FILE  --timeout SEC  --max-instr N
#         --expect-rows N（默认 30；远端 test/manifest.tsv 现为 31 行漂移件，**必须**用 30 行冻结件）
#         --jobs N（默认 nproc）  --emu-threads N（默认 8）  --jvm-xmx SIZE（默认 40G）
#         --skip-build（复用已带覆盖的 build/emu；只跑用例+合并）  --restore-emu（结束恢复非覆盖 emu）
#         --no-budget-guard（**危险**：跳过预算闸，仅在用户显式加预算后使用）
#         （2026-11-07 实跑：用户已授权突破自设 11.0 机时预算，按授权越过；判据记「已越过」而非「达标」，
#           总账超支事实由 90-budget-log.sh auto 如实入账，不改判据）  --dry-run
#   30 行冻结件生成（本地，先 make_manifest.sh 展开 @IMG_DIR@ 再回传）：
#     bash design/verify/cases/make_manifest.sh ~/core/test/bin > /tmp/manifest.30.tsv
#     scp /tmp/manifest.30.tsv kunshan:~/core/test/manifest.30.tsv
#
# 判据（任一不达标即 status=失败，未跑到即 status=未运行）：
#   1) build_emu_cov：make emu 退出码 0，且 build/emu 可执行
#   2) coverage_compiled：探针日志**不**含 "coverage is not enabled at compile time"（T5）
#   3) dat_count：每例一份 .coverage.dat，数量 == 执行用例数
#   4) cases_pass：复用 20-run 的自检串语义（GOOD TRAP ∧ 无 ABORT ∧ 自检通过串 / 负例 HIT CRITICAL ERROR）
#   5) coverage_report：merged.coverage/coverage_SimTop.log 非空
#   6) coverage_modules：AllCoverage 树含 VdotReduce / VIMac64b / VIMacU / VIMacSrcTypeModule
#   7) budget_guard：提交前 summary 退出码 0（合计 ≤10.6 机时且未动用缓冲）
#
# 产物：results/coverage/<runid>/{cases/<cid>.log, build/<cid>/build/*.coverage.dat,
#        merged.coverage/{*_annotated.sv,coverage_SimTop.log,*.coverage.dat},
#        95-coverage-<runid>.log|json, cases.tsv, vdot-structural.tsv}
# 退出码：0 达标 / 1 未达标 / 2 未运行（预算闸/前置缺失） / 3 用法或环境错误
#
# 上游坑位（编号沿用早期统计 §2.4）：
#   T1 改 EMU_COVERAGE=1 不触发重编 ⇒ 构建前必须 rm -rf build/verilator-compile build/emu
#   T2 vtransform.py 只认 .v，香山是 .sv ⇒ coverage_off 过滤无效，报告侧按模块过滤
#   T3 多 .dat 时默认 COVERAGE_DIR 会拼成多个词 ⇒ 显式传 COVERAGE_DATA/COVERAGE_DIR
#   T4 .dat 名只含秒级时间戳、不含用例名 ⇒ 每例独立 NOOP_HOME
#   T5 未开覆盖时 --dump-coverage 静默退化 ⇒ 必须 grep WARN + 数 .dat
#   T6 make coverage 的 NOOP_HOME 默认是 difftest 目录 ⇒ 显式传 DESIGN_DIR
#   T7 verilator_coverage 必须在 PATH ⇒ source ~/tools/env.sh
#   T8 mv 要求目标目录已存在 ⇒ 先断言 .dat 非空再调 make coverage
#   T9 不给 NOOP_HOME 时 `make -C difftest emu-mk` 的默认设计目录是 difftest 自身 ⇒ 去找
#      difftest/build/rtl/SimTop.sv ⇒ rc=2；必须 export NOOP_HOME（2026-11-07 作业 127113117 实测）
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P4-coverage"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
export CORE_DIR   # 预算闸与 EXIT trap 都会调 90-budget-log.sh；不导出会退回它自己的默认路径
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
SRC_ROOT="${SRC_ROOT:-$CORE_DIR/src}"
MANIFEST=""
REF_SO=""
EXPECT_ROWS=30
MAX_INSTR="${MAX_INSTR:-200000000}"
TIMEOUT_S="${TIMEOUT_S:-2400}"      # 覆盖插桩放大单例耗时；perf_vdot 基线 5 min，按 4× 留量
JOBS="$(nproc 2>/dev/null || echo 8)"
EMU_THREADS="${EMU_THREADS:-8}"
JVM_XMX="${JVM_XMX:-40G}"
SKIP_BUILD=0
RESTORE_EMU=0
BUDGET_GUARD=1
DRY_RUN=0
CRITERIA=()
CASES=()
STARTED_AT=""
# write_json 在读它们之前可能被 fail_unrun 调用（前置缺失），故先给默认值，避免 set -u 报未定义
DAT_COUNT=0
REPORT_LOG=""
MODULES_JSON=""
BUDGET_BYPASSED=0

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/coverage/$RUN_ID"
readonly LOG_FILE="$OUT_DIR/$SCRIPT_NAME-${RUN_ID}.log"
readonly JSON_FILE="$OUT_DIR/$SCRIPT_NAME-${RUN_ID}.json"
readonly CASES_DIR="$OUT_DIR/cases"
readonly CASES_TSV="$OUT_DIR/cases.tsv"
readonly PURPOSE="覆盖重建 + 30 例 --dump-coverage + statistics 合并"

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
add_case_json() { CASES+=("    {\"case_id\": \"$(json_escape "$1")\", \"class\": \"$(json_escape "$2")\", \"status\": \"$(json_escape "$3")\", \"dat\": \"$(json_escape "$4")\", \"log\": \"$(json_escape "$5")\"}"); }
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

write_json() { # $1 status
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
    printf '  "machine_hours_planned": 4.0,\n'
    printf '  "budget_guard_bypassed": %s,\n' "$( [ "${BUDGET_BYPASSED:-0}" = "1" ] && echo true || echo false )"
    printf '  "mode": "coverage",\n'
    printf '  "versions": {"xiangshan": "%s", "difftest": "%s", "verilator": "%s"},\n' \
      "$(json_escape "${XS_HEAD:-}")" "$(json_escape "${DF_HEAD:-}")" "$(json_escape "${VL_VER:-}")"
    printf '  "manifest": {"path": "%s", "sha256": "%s", "rows": "%s"},\n' \
      "$(json_escape "${MANIFEST:-}")" \
      "$( [ -f "${MANIFEST:-}" ] && sha256sum "$MANIFEST" 2>/dev/null | cut -d' ' -f1 || echo "" )" \
      "$( [ -f "${MANIFEST:-}" ] && awk '!/^#/ && NF>=3' "$MANIFEST" | wc -l | tr -d ' ' || echo "" )"
    printf '  "criteria": [\n'
    n=${#CRITERIA[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CRITERIA[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "cases": [\n'
    n=${#CASES[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CASES[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "coverage": {"run_dir": "%s", "dats": %s, "report": "%s", "modules": [%s]}\n' \
      "$(json_escape "$OUT_DIR")" "${DAT_COUNT:-0}" \
      "$(json_escape "${REPORT_LOG:-}")" "${MODULES_JSON:-}"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  if command -v python3 >/dev/null 2>&1 \
     && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON_FILE" 2>/dev/null; then
    log "[ERROR] 结果 JSON 不可解析：$JSON_FILE（本次结果不可用于交付，先修脚本再重跑）"
  fi
  log "结果 JSON：$JSON_FILE"
}

module_init() {
  if [ -r "$TOOLS_DIR/env.sh" ]; then . "$TOOLS_DIR/env.sh"; log "已 source $TOOLS_DIR/env.sh"; fi
  hash -r
}

fail_unrun() { # $1 原因
  add_criterion "preconditions" "前置齐备" "$1" "未运行"
  write_json "未运行"
  log "未运行：$1"
  exit 2
}

# 预算闸（B7 同口径，见 core-package/scripts/90-budget-log.sh: cmd_summary）：
# 合计（不含缓冲）>10.6 或缓冲被动用 ⇒ summary 退出码 1 ⇒ 覆盖重建会把总账推过自设 11.0 机时预算 ⇒ 不提交。
# （11.0 是 90-budget-log.sh:29 的 TOTAL_BUDGET 自设值；docx/*.md 无机时规定，不得写成「官方上限」。）
# 该闸放行条件：先在 90-budget-log.sh 里重估预算（或用户显式加预算）并用 --no-budget-guard 显式越过。
budget_gate() {
  local bl="$CORE_DIR/core-package/scripts/90-budget-log.sh" rc=0
  [ -x "$bl" ] || { log "[WARN] 缺 $bl：预算闸无法判定，记未运行"; return 2; }
  # summary 是**只读**记账查询（读 results/budget-log.tsv + results/*.json），不提交作业 ⇒
  # 即使 dry-run 也真跑，否则 dry-run 会假装预算充足（假绿）。CORE_DIR 已在脚本头部 export，
  # 子进程与 EXIT trap 读的是同一份账。
  bash "$bl" summary >"$OUT_DIR/budget-summary.txt" 2>&1 || rc=$?
  log "预算闸：90-budget-log.sh summary rc=$rc（明细 $OUT_DIR/budget-summary.txt）"
  if [ "$rc" != "0" ]; then
    log "预算闸拒绝：summary rc=$rc（合计超 10.6 机时 / 单项超支 50% / 缓冲被动用之一）"
    return 1
  fi
  return 0
}

probe_coverage() { # 覆盖开关自检（T5）；成功则把探针 .dat 移出报告范围
  local probe_home="$OUT_DIR/probe" plog="$OUT_DIR/probe.log" n
  mkdir -p "$probe_home/build"
  NOOP_HOME="$probe_home" timeout 900 "$EMU_BIN" --no-diff -i "$PROBE_IMG" -C 100 --dump-coverage \
    >"$plog" 2>&1 || true
  if grep -q 'coverage is not enabled at compile time' "$plog" 2>/dev/null; then
    add_criterion "coverage_compiled" "实测日志不含 coverage-not-enabled WARN" \
      "探针日志命中 WARN（VM_COVERAGE 未开）" "未达标"
    return 1
  fi
  n="$(find "$probe_home" -name '*.coverage.dat' -print 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -lt 1 ]; then
    add_criterion "coverage_compiled" "探针产出 >=1 个 .coverage.dat" "0 个（$plog）" "未达标"
    return 1
  fi
  add_criterion "coverage_compiled" "探针产出 >=1 个 .coverage.dat 且无 WARN" "$n 个 .dat" "达标"
  find "$probe_home" -name '*.coverage.dat' -delete 2>/dev/null || true
  return 0
}

# 自检通过串：与 20-run-difftest.sh 的 selfcheck_pattern() 同语义（覆盖率跑必须能复用同一判据，
# 否则覆盖率报告与 30/30 的功能结论会漂移）。**不要在这里加「更宽松」的串**。
selfcheck_pattern() { # cls cid
  case "$1" in
    vadd)                         echo 'MicroBench PASS' ;;
    vdot-pos|vdot-neg|vdot-bound) echo "CASE $2: MATCH" ;;
    vdot-matrix)                  echo 'MATRIX verdict=ALL_OK' ;;
    vdot-mix)                     echo 'MIX verdict=ALL_OK' ;;
    vdot-rand)                    echo 'RAND_SUMMARY groups=[0-9]+ mism=0 ab_bad=0' ;;
    g0)                           echo "CASE $2: MISMATCH" ;;
    perf)
      case "$2" in
        perf_vdot)  printf '%s\n' 'PERF_VDOT verdict=ALL_OK' 'chain=OK' ;;
        perf_base)  echo 'PERF_BASE verdict=ALL_OK' ;;
        perf_vadd)  printf '%s\n' 'PERF_VADD verdict=ALL_OK' 'chain=OK' ;;
        perf_vmacc) printf '%s\n' 'PERF_VMACC verdict=ALL_OK' 'chain=OK' ;;
        *)          echo '' ;;
      esac ;;
    *)                            echo '' ;;
  esac
}

count_hits() { # file pattern  -> 整数（文件缺失/无命中都返回 0，绝不返回空串）
  local f="$1" pat="$2" n
  [ -f "$f" ] || { printf '0'; return 0; }
  n="$(grep -acE "$pat" "$f" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

run_case() { # cid cls img extra
  local cid="$1" cls="$2" img="$3" extra="${4:-}"
  local chome="$OUT_DIR/build/$cid" clog="$CASES_DIR/${cid}.log"
  local rc=0 good abort bad crit mismatch sentinel dat st
  rm -rf "$chome"; mkdir -p "$chome/build"
  if [ "$DRY_RUN" != "1" ]; then
    # T4：每例独立 NOOP_HOME ⇒ .dat 落 $chome/build/<ts>.coverage.dat，天然按用例归属、不会同秒互覆盖
    # shellcheck disable=SC2086
    NOOP_HOME="$chome" timeout "$TIMEOUT_S" "$EMU_BIN" --diff "$REF_SO" -i "$img" \
      --max-instr="$MAX_INSTR" --dump-coverage $extra >"$clog" 2>&1 || rc=$?
  fi
  if [ "$DRY_RUN" = "1" ]; then
    # dry-run 不产生日志：记「未运行(dry-run)」，**不得**记失败或通过（未运行不是通过）
    printf '%s\t%s\t%s\t\t%s\n' "$cid" "$cls" "未运行(dry-run)" "$clog" >>"$CASES_TSV"
    add_case_json "$cid" "$cls" "未运行(dry-run)" "" "$clog"
    log "  case $cid [$cls] -> 未运行(dry-run)"
    return 0
  fi
  good="$(count_hits "$clog" 'HIT GOOD TRAP')"
  abort="$(count_hits "$clog" 'ABORT')"
  bad="$(count_hits "$clog" 'HIT BAD TRAP')"
  crit="$(count_hits "$clog" 'HIT CRITICAL ERROR')"
  dat="$(find "$chome" -name '*.coverage.dat' -print -quit 2>/dev/null || true)"
  if [ "$cls" = "negative" ]; then
    mismatch="$(count_hits "$clog" 'diff REF|Different operands')"
    sentinel="$(count_hits "$clog" '未如期陷入非法指令')"
    if [ "$crit" -ge 1 ] && [ "$mismatch" = "0" ] && [ "$abort" = "0" ] && [ "$sentinel" = "0" ]; then
      st="通过"
    else
      st="失败(负例:CRIT=$crit MISMATCH=$mismatch SENTINEL=$sentinel ABORT=$abort)"
    fi
  elif [ "$cls" = "g0" ]; then
    # G0 反例（ALGORITHM §3.1）：期望值被故意写错 1 bit，DUT 与 NEMU 仍逐位一致 ⇒ HIT GOOD TRAP、无 ABORT，
    # 只能被「自检串」判据抓住：日志必须有 "CASE <cid>: MISMATCH" 且不得有 "CASE <cid>: MATCH"。
    # 与 20-run-difftest.sh:267-276 同口径（此处不再要求 HIT CRITICAL ERROR——那是负例的判据）。
    local gmatch gmis
    gmatch="$(count_hits "$clog" "CASE ${cid}: MATCH")"
    gmis="$(count_hits "$clog" "CASE ${cid}: MISMATCH")"
    if [ "$good" -ge 1 ] && [ "$abort" = "0" ] && [ "$gmis" -ge 1 ] && [ "$gmatch" = "0" ]; then st="通过"
    else st="失败(空绿防护失效:GOOD=$good ABORT=$abort MISMATCH=$gmis MATCH=$gmatch)"; fi
  else
    local vp vhit=1 vpat
    vpat="$(selfcheck_pattern "$cls" "$cid")"
    if [ -n "$vpat" ]; then
      while IFS= read -r vp; do
        [ -n "$vp" ] || continue
        [ "$(count_hits "$clog" "$vp")" -ge 1 ] || vhit=0
      done <<< "$vpat"
    fi
    if [ "$good" -ge 1 ] && [ "$abort" -eq 0 ] && [ "$bad" -eq 0 ] \
       && { [ -z "$vpat" ] || [ "${vhit:-0}" -ge 1 ]; }; then st="通过"
    else st="失败(GOOD=$good ABORT=$abort BAD=$bad SELFCHK=${vhit:-n/a})"; fi
  fi
  if [ -z "$dat" ]; then st="$st/缺dat"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$cid" "$cls" "$st" "${dat:-}" "$clog" >>"$CASES_TSV"
  add_case_json "$cid" "$cls" "$st" "${dat:-}" "$clog"
  log "  case $cid [$cls] -> $st (GOOD=$good ABORT=$abort CRIT=$crit rc=$rc dat=${dat:-无})"
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --manifest) MANIFEST="${2:?--manifest 需要参数}"; shift 2 ;;
      --ref-so) REF_SO="${2:?--ref-so 需要参数}"; shift 2 ;;
      --expect-rows) EXPECT_ROWS="${2:?--expect-rows 需要参数}"; shift 2 ;;
      --timeout) TIMEOUT_S="${2:?--timeout 需要参数}"; shift 2 ;;
      --max-instr) MAX_INSTR="${2:?--max-instr 需要参数}"; shift 2 ;;
      --jobs) JOBS="${2:?--jobs 需要参数}"; shift 2 ;;
      --emu-threads) EMU_THREADS="${2:?--emu-threads 需要参数}"; shift 2 ;;
      --jvm-xmx) JVM_XMX="${2:?--jvm-xmx 需要参数}"; shift 2 ;;
      --skip-build) SKIP_BUILD=1; shift ;;
      --restore-emu) RESTORE_EMU=1; shift ;;
      --no-budget-guard) BUDGET_GUARD=0; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,41p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ] && [ "$DRY_RUN" != "1" ]; then
    echo "[FATAL] 覆盖率重建属重计算，禁止在登录节点执行。" >&2
    echo "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=04:00:00 ${SCRIPT_PATH} --manifest ~/core/test/manifest.30.tsv" >&2
    echo "        （dry-run 自检：SLURM_JOB_ID=fake bash ${SCRIPT_PATH} --dry-run ...）" >&2
    exit 3
  fi

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR" "$CASES_DIR"
  : >"$CASES_TSV"
  log "===== $SCRIPT_NAME run=$RUN_ID jobs=$JOBS emu_threads=$EMU_THREADS timeout=${TIMEOUT_S}s guard=$BUDGET_GUARD ====="
  module_init

  local NOOP_HOME="$SRC_ROOT/XiangShan"
  local NEMU_HOME="$SRC_ROOT/NEMU"
  # 必须 export：difftest/Makefile:18 `NOOP_HOME ?= $(abspath .)`，make -C difftest 时默认值 = difftest 目录，
  # 于是 emu-mk 去找 difftest/build/rtl/SimTop.sv 而不是 <NOOP_HOME>/build/rtl/SimTop.sv ⇒ 构建 rc=2
  # （2026-11-07 实跑 127113117 实测：`没有规则可制作目标 .../difftest/build/rtl/SimTop.sv`）。
  export NOOP_HOME NEMU_HOME
  EMU_BIN="$NOOP_HOME/build/emu"
  [ -n "$REF_SO" ] || REF_SO="$NEMU_HOME/build/riscv64-nemu-interpreter-so"
  [ -n "$MANIFEST" ] || MANIFEST="$CORE_DIR/test/manifest.tsv"
  PROBE_IMG="${PROBE_IMG:-$CORE_DIR/test/bin/microbench.bin}"

  [ -d "$NOOP_HOME" ] || fail_unrun "缺 XiangShan 源码树：$NOOP_HOME"
  [ -f "$MANIFEST" ] || fail_unrun "缺用例清单：$MANIFEST（先用 make_manifest.sh 展开 @IMG_DIR@）"
  [ -f "$REF_SO" ] || fail_unrun "缺 NEMU ref .so：$REF_SO"
  [ -f "$PROBE_IMG" ] || fail_unrun "缺探针镜像：$PROBE_IMG"

  # 清单行数闸：覆盖率报告与 30 例主清单一一对应。远端 test/manifest.tsv 现为 31 行漂移件
  # ，直接拿它会得到「31 例覆盖率」；用 --expect-rows 显式声明期望行数，
  # 不符即记未运行（防止用错误清单产出覆盖率数字）。
  local mrows=0
  mrows="$(awk '!/^#/ && NF>=3' "$MANIFEST" | wc -l | tr -d ' ')"
  if [ "$mrows" -ne "$EXPECT_ROWS" ]; then
    add_criterion "manifest_rows" "清单数据行 == $EXPECT_ROWS" "$mrows 行（$MANIFEST）" "未运行"
    fail_unrun "清单行数 $mrows ≠ 期望 $EXPECT_ROWS：请用 30 行冻结件（生成命令见脚本头注）"
  else
    add_criterion "manifest_rows" "清单数据行 == $EXPECT_ROWS" "$mrows 行" "达标"
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] 跳过 verilator_coverage 存在性检查（本机无 Verilator 也允许 dry-run 走完全程）"
  else
    command -v verilator_coverage >/dev/null 2>&1 || fail_unrun "verilator_coverage 不在 PATH（先 source ~/tools/env.sh）"
  fi

  # --- 预算闸（本脚本的最后一道门；不通过就不烧机时）
  if [ "$BUDGET_GUARD" = "1" ]; then
    local brc=0
    budget_gate || brc=$?
    if [ "$brc" = "1" ]; then
      add_criterion "budget_guard" "90-budget-log.sh summary rc=0" "rc=1（合计超 10.6 机时或缓冲被动用）" "未运行"
      fail_unrun "预算闸拒绝：先重估预算，或用户显式加预算后用 --no-budget-guard"
    elif [ "$brc" = "2" ]; then
      add_criterion "budget_guard" "90-budget-log.sh summary rc=0" "记账脚本不可读，无法判定" "未运行"
      fail_unrun "预算闸无法判定（缺 90-budget-log.sh）"
    else
      add_criterion "budget_guard" "90-budget-log.sh summary rc=0" "rc=0（合计 ≤10.6 机时、未动用缓冲）" "达标"
    fi
  else
    # 越过闸 ≠ 闸通过：状态记「已越过」，既不算达标也不污染总状态（否则全跑成功也会被记成「未运行」）。
    # 超支事实由 90-budget-log.sh auto 在 EXIT trap 里如实入账；JSON 顶层另给 budget_guard_bypassed。
    BUDGET_BYPASSED=1
    add_criterion "budget_guard" "90-budget-log.sh summary rc=0" \
      "已用 --no-budget-guard 显式越过（用户 2026-11-07 授权突破自设 11.0 机时预算；见票 T-coverage-structural-20261107）" "已越过"
    log "[WARN] --no-budget-guard：跳过预算闸（用户已授权），机时风险与超支事实由记账脚本承担"
  fi

  # --- 版本指纹（缺一项即「未运行」，不写「通过」）
  XS_HEAD="$(git --git-dir="$NOOP_HOME/.git" rev-parse --short HEAD 2>/dev/null || echo "")"
  DF_HEAD="$(git --git-dir="$NOOP_HOME/difftest/.git" rev-parse --short HEAD 2>/dev/null || echo "")"
  VL_VER="$(verilator --version 2>/dev/null | sed -n '1p' || echo "")"
  log "versions: xiangshan=${XS_HEAD:-缺} difftest=${DF_HEAD:-缺} verilator=${VL_VER:-缺}"

  # --- 0) 保全现有非覆盖 emu（回滚用）；T1：覆盖开关不触发重编，必须删 verilator-compile
  if [ "$SKIP_BUILD" = "1" ]; then
    [ -x "$EMU_BIN" ] || fail_unrun "--skip-build 但 $EMU_BIN 不存在"
    # 「复用」不是「未运行」：真实覆盖开关由下一步 probe_coverage（T5，零 WARN + ≥1 .dat）实测把关。
    # 若记未运行，会把一次完整跑成功的结果拖成 status=未运行（同 budget_guard 的坑）。
    add_criterion "build_emu_cov" "make emu EMU_COVERAGE=1 rc=0" "--skip-build：复用既有 build/emu（覆盖开关由 probe 实测把关）" "已复用"
    log "按 --skip-build 复用 $EMU_BIN（调用者自证其为覆盖构建）"
  else
    if [ -x "$EMU_BIN" ] && [ ! -e "$NOOP_HOME/build/emu.nocov" ]; then
      cp -L "$EMU_BIN" "$NOOP_HOME/build/emu.nocov" 2>/dev/null || log "[WARN] 保全非覆盖 emu 失败（回滚需 make emu 重建）"
    fi
    log "== 覆盖率重建：rm -rf build/verilator-compile build/emu（T1）=="
    run rm -rf "$NOOP_HOME/build/verilator-compile" "$NOOP_HOME/build/emu"
    local build_rc=0
    run make -C "$NOOP_HOME" emu -j"$JOBS" EMU_COVERAGE=1 EMU_THREADS="$EMU_THREADS" \
      JVM_XMX="$JVM_XMX" JVM_XSS=256m || build_rc=$?
    if [ "$DRY_RUN" = "1" ]; then
      add_criterion "build_emu_cov" "make emu EMU_COVERAGE=1 rc=0" "dry-run：未执行" "未运行"
    elif [ "$build_rc" = "0" ] && [ -x "$EMU_BIN" ]; then
      add_criterion "build_emu_cov" "make emu EMU_COVERAGE=1 rc=0 且 build/emu 可执行" "rc=0" "达标"
    else
      add_criterion "build_emu_cov" "make emu EMU_COVERAGE=1 rc=0 且 build/emu 可执行" "rc=$build_rc" "未达标"
      write_json "失败"; log "构建失败，停止"; exit 1
    fi
    # 版本指纹只对「自己构建出来的 emu」有意义
    EMU_SHA="$(sha256sum "$EMU_BIN" 2>/dev/null | cut -d' ' -f1 || echo "")"
    log "coverage emu sha256=${EMU_SHA:-缺}"
  fi

  # --- 1) 覆盖开关自检（T5）
  if [ "$DRY_RUN" = "1" ]; then
    add_criterion "coverage_compiled" "探针产出 >=1 个 .coverage.dat 且无 WARN" "dry-run：未执行" "未运行"
  else
    probe_coverage || { write_json "失败"; log "覆盖开关自检失败：--dump-coverage 被静默忽略"; exit 1; }
  fi

  # --- 2) 逐例覆盖运行（manifest 全选；不按 smoke 白名单裁剪，否则 vl=VLMAX/vta×vma/overlap 全落空）
  local total=0 pass=0 fail=0
  while IFS=$'\t' read -r cid cls img extra || [ -n "${cid:-}" ]; do
    case "${cid:-}" in ''|'#'*) continue ;; esac
    img="${img//@IMG_DIR@/$CORE_DIR/test/bin}"
    if [ ! -f "$img" ]; then
      log "  [未运行] $cid：镜像不存在 $img"
      printf '%s\t%s\t%s\t\t\n' "$cid" "$cls" "未运行(缺镜像)" >>"$CASES_TSV"
      add_case_json "$cid" "$cls" "未运行(缺镜像)" "" ""
      total=$((total + 1)); fail=$((fail + 1)); continue
    fi
    total=$((total + 1))
    run_case "$cid" "$cls" "$img" "${extra:-}"
    case "$(awk -F'\t' -v c="$cid" '$1==c{print $3}' "$CASES_TSV" | tail -1)" in
      通过) pass=$((pass + 1)) ;;
      *)    fail=$((fail + 1)) ;;
    esac
  done <"$MANIFEST"

  if [ "$total" -eq 0 ]; then
    add_criterion "cases_ran" "至少运行 1 个用例" "0 个（清单为空）" "未运行"
    write_json "未运行"; exit 2
  fi
  if [ "$DRY_RUN" = "1" ]; then
    # dry-run 只证明「命令拼装 + 判据路径」可走通，不产生任何功能结论
    add_criterion "cases_pass" "全部用例通过（复用 20-run 自检串语义）" \
      "dry-run：$total 个用例未执行（只打印命令）" "未运行"
    log "dry-run：用例未执行，本份 JSON 只能证明脚本可跑通，不得作为覆盖率证据"
    write_json "未运行"
    exit 2
  fi
  if [ "$fail" -eq 0 ]; then
    add_criterion "cases_pass" "全部用例通过（复用 20-run 自检串语义）" "$pass/$total" "达标"
  else
    add_criterion "cases_pass" "全部用例通过（复用 20-run 自检串语义）" "$pass/$total，失败 $fail" "未达标"
  fi

  # --- 3) 合并标注（T3/T6/T8：显式给 COVERAGE_DATA/COVERAGE_DIR/DESIGN_DIR）
  local dats rep_rc=0
  dats="$(find "$OUT_DIR/build" -name '*.coverage.dat' -print 2>/dev/null | sort || true)"
  DAT_COUNT="$(printf '%s\n' "$dats" | grep -c . || true)"
  if [ -z "$dats" ] || [ "$DAT_COUNT" = "0" ]; then
    add_criterion "dat_count" ".coverage.dat 数 == 执行用例数" "0 个" "未达标"
    REPORT_LOG=""; MODULES_JSON=""
    write_json "失败"; log "无 .dat，无法合并"; exit 1
  fi
  if [ "$DAT_COUNT" -eq "$total" ]; then
    add_criterion "dat_count" ".coverage.dat 数 == 执行用例数" "$DAT_COUNT/$total" "达标"
  else
    add_criterion "dat_count" ".coverage.dat 数 == 执行用例数" "$DAT_COUNT/$total（缺失见 cases.tsv 的 /缺dat）" "未达标"
  fi
  REPORT_LOG="$OUT_DIR/merged.coverage/coverage_SimTop.log"
  # shellcheck disable=SC2086
  run make -C "$NOOP_HOME/difftest" coverage COVERAGE_DATA="$dats" \
    COVERAGE_DIR="$OUT_DIR/merged.coverage" DESIGN_DIR="$NOOP_HOME" SIM_TOP=SimTop || rep_rc=$?
  if [ "$DRY_RUN" = "1" ]; then
    add_criterion "coverage_report" "coverage_SimTop.log 非空" "dry-run：未执行" "未运行"
    MODULES_JSON=""
  elif [ "$rep_rc" = "0" ] && [ -s "$REPORT_LOG" ]; then
    add_criterion "coverage_report" "coverage_SimTop.log 非空" "$(wc -l <"$REPORT_LOG" | tr -d ' ') 行" "达标"
    # 模块名单 = 早期统计 §4.4 的 4 个 vdot 模块（4/4 全部出现才达标）。
    # MODULES_JSON 必须是逗号分隔的合法 JSON 元素序列（旧实现用空格拼接，写出非法 JSON）。
    local mods="" m mod_cnt=0 mod_list="VdotReduce VIMac64b VIMacU VIMacSrcTypeModule"
    for m in $mod_list; do
      if grep -q -- "- $m\$" "$REPORT_LOG" 2>/dev/null; then
        mods="${mods:+$mods,}\"$m\""; mod_cnt=$((mod_cnt + 1))
      fi
    done
    MODULES_JSON="$mods"
    if [ "$mod_cnt" -eq 4 ]; then
      add_criterion "coverage_modules" "AllCoverage 含 4 个 vdot 模块（4/4）" "$mod_cnt/4：$MODULES_JSON" "达标"
    else
      add_criterion "coverage_modules" "AllCoverage 含 4 个 vdot 模块（4/4）" "$mod_cnt/4：${MODULES_JSON:-无}" "未达标"
    fi
    # 结构覆盖机读件（模块级 line/toggle）；生成器缺失只告警，不影响运行判据。
    # 候选路径：`~/core/stage3/…`（整包 rsync 时存在）→ 与 95 脚本同目录（单独上传 core-package 时）。
    local gen="" g
    for g in "$CORE_DIR/stage3/3.1.2-difftest/coverage/gen_hits.py" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gen_hits.py"; do
      if [ -f "$g" ]; then gen="$g"; break; fi
    done
    if command -v python3 >/dev/null 2>&1 && [ -n "$gen" ]; then
      # gen_hits.py:149 要求 --bins 目录里 .bin 与同名 .c 并存（静态事实从 .c 读）；
      # 整包同步时用 design/verify/cases，只有 test/bin 时退化为「仅二进制扫描」。
      local bins_dir="$CORE_DIR/design/verify/cases"
      [ -d "$bins_dir" ] || bins_dir="$CORE_DIR/test/bin"
      python3 -I "$gen" --manifest "$MANIFEST" --logs "$CASES_DIR" --log-suffix .log \
        --bins "$bins_dir" --out "$OUT_DIR" --statistics "$REPORT_LOG" \
        >>"$LOG_FILE" 2>&1 || log "[WARN] gen_hits.py 解析失败（结构覆盖 tsv 未产出）"
    else
      log "[WARN] 未找到 gen_hits.py：跳过结构覆盖解析（不伪造结构覆盖 tsv）"
    fi
  else
    add_criterion "coverage_report" "coverage_SimTop.log 非空" "rc=$rep_rc（$REPORT_LOG）" "未达标"
    add_criterion "coverage_modules" "AllCoverage 含 4 个 vdot 模块" "报告缺失，无法判定" "未运行"
    MODULES_JSON=""
  fi

  # --- 4) 恢复非覆盖 emu（可选；覆盖率 emu 慢 1.5–4×，不恢复会拖慢后续 difftest）
  if [ "$RESTORE_EMU" = "1" ] && [ "$SKIP_BUILD" != "1" ] && [ -x "$NOOP_HOME/build/emu.nocov" ]; then
    run mkdir -p "$NOOP_HOME/build/verilator-compile"
    run cp -L "$NOOP_HOME/build/emu.nocov" "$NOOP_HOME/build/verilator-compile/emu"
    run ln -sfn "$NOOP_HOME/build/verilator-compile/emu" "$NOOP_HOME/build/emu"
    log "已恢复非覆盖 emu（$NOOP_HOME/build/emu -> verilator-compile/emu）"
  fi

  local ok=0 unrun=0 c
  for c in ${CRITERIA[@]+"${CRITERIA[@]}"}; do
    case "$c" in *'"未达标"'*) ok=1 ;; esac
    case "$c" in *'"未运行"'*) unrun=1 ;; esac
  done
  if [ "$ok" = "0" ] && [ "$unrun" = "0" ]; then
    write_json "通过"; log "判据：达标（$pass/$total，dat=$DAT_COUNT）"; exit 0
  fi
  if [ "$ok" = "0" ]; then
    write_json "未运行"; log "判据：存在未运行项（$pass/$total），不得记通过"; exit 2
  fi
  write_json "失败"; log "判据：未达标（$pass/$total）"; exit 1
}

# 机时记账：90-budget-log.sh 的 BUDGET 表没有独立覆盖项，本脚本的消耗记在 P3-full 项下并写明 purpose
# （已知记账局限；若覆盖率转为常态回归，应先在
#  90-budget-log.sh 的 BUDGET 表里增列独立条目再记账，不要继续混记）。
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

trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item P3-full --purpose "P4-coverage 覆盖重建+30例（混记在 P3-full 项）" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
