#!/usr/bin/env bash
# =============================================================================
# 验证项：P0-3 difftest 冒烟（vadd 回归 + vdot 定向）/ P3 difftest 全量 + 随机 + 基线三口径
# 预计机时：1.0（--smoke）/ 3.0（--full）（1 机时 = 1 计算节点 × 1 小时）
# 状态：已在昆山实跑（2026-11-03 起：`126676734` 30 例 `--full`、`126630485`/`126630806`/`126876081`/
#        `126877641`/`126884288` `--smoke` 等）；本行原写「未在任何节点执行」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   sbatch ... 20-run-difftest.sh --smoke      # manifest 中 vadd / vdot-pos / vdot-neg / vdot-bound / negative
#   sbatch ... 20-run-difftest.sh --full       # 全清单（含 vdot-matrix 不变量 / vdot-rand 随机 1024 组 / g0 防空绿反例）+ perf 三口径 + regression_delta
#   参数：--manifest FILE --emu FILE --ref-so FILE --max-instr N --timeout SEC --write-baseline --dry-run
#   --write-baseline：本模式全部用例执行后写 results/difftest/baseline.tsv（P0-3 建基线，--full 单遍对比免双跑）
# 判据：正例 HIT GOOD TRAP 且 ABORT=0 **且命中本用例的自检通过串**（防空绿，ALGORITHM §3.1；
#       vadd=MicroBench PASS / vdot-*=CASE <cid>: MATCH / vdot-matrix=MATRIX verdict=ALL_OK /
#       vdot-rand=RAND_SUMMARY groups=N mism=0 ab_bad=0）；
#       g0 类反例必须「GOOD TRAP + 自检 MISMATCH」＝被同一判据判负，记进 criteria[no_empty_green]；
#       negative 类必须出现 HIT CRITICAL ERROR（双侧一致的非法陷入）、
#       无失配串、无「未如期陷入非法指令」哨兵（2026-11-01 按 emu 实测语义修正）
#       选中用例必须全部执行（cases_all_ran）；--smoke 四类各 >= 1 例；reg_size_match
#       --full 追加：regression_delta == 0（与 results/difftest/baseline.tsv 比较）、三口径齐全
# 产物：results/difftest/20-<mode>-<runid>.log|json|cases.tsv、cases/<case>.<runid>.log
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly ITEM_SMOKE="P0-difftest-smoke"
readonly ITEM_FULL="P3-full"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
MODE="smoke"
MANIFEST=""
EMU_BIN=""
REF_SO=""
MAX_INSTR="${MAX_INSTR:-200000000}"
TIMEOUT_S="${TIMEOUT_S:-1800}"
DRY_RUN=0
CRITERIA=()
CASES=()
METRICS=()
METRIC_NAMES=()
STARTED_AT=""
ITEM="$ITEM_SMOKE"
PURPOSE="difftest 冒烟"
PERF_CASES=0
# T5 ΔL 三链（HARD-DESIGN.md:188）：从 perf 用例自报的 VDOT_METRIC 里取 L_vadd/L_vmacc/L_vdot。
L_VADD=""
L_VMACC=""
L_VDOT=""
SELECTED_TOTAL=0
EXECUTED_TOTAL=0
NOT_RUN_TOTAL=0
REG_SIZE_BAD=0
SELFCHK_REQ=0   # 带「自检通过串」要求的正例数（防空绿，ALGORITHM §3.1）
SELFCHK_OK=0    # 其中自检串命中的数量
G0_REQ=0        # G0 反例数（用例期望值被故意写错 1 bit）
G0_CAUGHT=0     # 被自检串判据抓出的 G0 数
CASE_TIMEOUT_S="$TIMEOUT_S"

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly RESULT_ROOT="$CORE_DIR/results/difftest"
# 产物路径在解析 --smoke/--full 之后按模式赋值（不能声明为 readonly）
LOG_FILE=""
JSON_FILE=""
CASES_TSV=""
WRITE_BASELINE=0
readonly CASES_DIR="$RESULT_ROOT/cases"

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
# 去控制字符（\r 来自 AM printf 的 CRLF；JSON 里出现裸 \r 会让整份结果不可解析，2026-11-02 实测踩到）
json_escape() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '; }
add_criterion() { CRITERIA+=("    {\"name\": \"$(json_escape "$1")\", \"expected\": \"$(json_escape "$2")\", \"actual\": \"$(json_escape "$3")\", \"status\": \"$(json_escape "$4")\"}"); }
add_case_json() { CASES+=("    {\"case_id\": \"$(json_escape "$1")\", \"class\": \"$(json_escape "$2")\", \"status\": \"$(json_escape "$3")\", \"good_trap\": \"$(json_escape "$4")\", \"abort\": \"$(json_escape "$5")\", \"log\": \"$(json_escape "$6")\"}"); }
add_metric_json() { METRICS+=("    {\"name\": \"$(json_escape "$1")\", \"value\": \"$(json_escape "$2")\", \"case_id\": \"$(json_escape "$3")\"}"); }
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

write_json() { # $1 status
  local status="$1" tmp="$JSON_FILE.tmp" i n
  mkdir -p "$RESULT_ROOT"
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
    printf '  "machine_hours_planned": %s,\n' "$( [ "$MODE" = "full" ] && echo 3.0 || echo 1.0 )"
    printf '  "mode": "%s",\n' "$MODE"
    # manifest 指纹（2026-11-03）：用例清单会随修复扩缩，历史 JSON 与当前清单的差集必须可机械判定，
    # 否则旧 run 的「20/20 达标」会被误当成当前 30 行清单的证据。sha256 覆盖内容，rows 覆盖行数。
    printf '  "manifest": {"path": "%s", "sha256": "%s", "rows": "%s"},\n' \
      "$(json_escape "${MANIFEST:-}")" \
      "$( [ -f "${MANIFEST:-}" ] && sha256sum "$MANIFEST" 2>/dev/null | cut -d' ' -f1 || echo "" )" \
      "$( [ -f "${MANIFEST:-}" ] && awk '!/^#/ && NF>=3' "$MANIFEST" | wc -l | tr -d ' ' || echo "" )"
    printf '  "regression_delta": "%s",\n' "${REGRESSION_DELTA:-未运行}"
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
    printf '  "metrics": [\n'
    n=${#METRICS[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${METRICS[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    # 防空绿判据的三个计数器（2026-11-06 补）：早先只把结论写进 criteria[no_empty_green].actual
    # 的文本里，JSON 顶层无字段 ⇒ 下游只能靠正则反推。这里把数值直接落进机读件。
    printf '  "counters": {"selfcheck_req": %s, "selfcheck_ok": %s, "g0_req": %s, "g0_caught": %s, "reg_size_bad": %s},\n' \
      "${SELFCHK_REQ:-0}" "${SELFCHK_OK:-0}" "${G0_REQ:-0}" "${G0_CAUGHT:-0}" "${REG_SIZE_BAD:-0}"
    printf '  "artifacts": ["%s", "%s"]\n' "$LOG_FILE" "$CASES_TSV"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  # 自检：结果 JSON 必须可被解析（裸控制字符会让整份证据不可读；2026-11-02 实测踩到 CR 问题）
  if command -v python3 >/dev/null 2>&1 \
     && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON_FILE" 2>/dev/null; then
    log "[ERROR] 结果 JSON 不可解析：$JSON_FILE（本次结果不可用于交付，先修脚本再重跑）"
  fi
  log "结果 JSON：$JSON_FILE"
}

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

fail_unrun() { # $1 原因
  add_criterion "preconditions" "前置齐备" "$1" "未运行"
  write_json "未运行"
  log "未运行：$1"
  exit 2
}

# 用例类是否属于本模式
# g0 必须参加 smoke：no_empty_green 判据要求 G0 反例被执行并被同一规则判负（G0_REQ>=1 且
# G0_CAUGHT>=1），而 G0_REQ 只在 run_case 走到 `cls = g0` 分支时才自增。c611d43 给 smoke 加
# no_empty_green 判据时白名单漏了 g0 ⇒ G0_REQ 恒 0 ⇒ 该判据结构性永记「未运行」⇒ 整个 smoke
# 永远到不了 status=通过。本行是 bug 修复（对齐判据设计意图），不是放宽判据。
class_selected() {
  local cls="$1"
  if [ "$MODE" = "full" ]; then return 0; fi
  case "$cls" in
    vadd|vdot-pos|vdot-neg|vdot-bound|vdot-mix|negative|g0) return 0 ;;
    *) return 1 ;;
  esac
}

# 每个类的「自检通过串」（ERE；空串＝该类无内嵌自检）。**一行一条 ERE，全部命中才算过**。
# 用途见 run_case 的正例分支：HIT GOOD TRAP 只说明程序跑到头，不说明结果对。
# perf 类也必须有硬判据：用例自己按数据算期望并打印 verdict；有 RAW 链的三例还要求日志
# 出现 `chain=OK`。**注意**：`perf_vadd`/`perf_vmacc` 的汇总行自身打印 `chain=%s`
# （`perf_vadd.c:182`、`perf_vmacc.c:184`），所以第二条 ERE 对这两例只是把该字段固定为 OK，
# 不构成独立于汇总的证据；只有 `perf_vdot` 的汇总行用 `raw=/alt=`（`perf_vdot.c:287`），
# `chain=OK` 才是来自独立链自检行（`perf_vdot.c:280` 的 `PERF T_kernel … chain=%s`）。
selfcheck_pattern() { # cls cid
  case "$1" in
    vadd)                         echo 'MicroBench PASS' ;;
    vdot-pos|vdot-neg|vdot-bound) echo "CASE $2: MATCH" ;;
    vdot-matrix)                  echo 'MATRIX verdict=ALL_OK' ;;
    vdot-mix)                     echo 'MIX verdict=ALL_OK' ;;
    vdot-rand)                    echo 'RAND_SUMMARY groups=[0-9]+ mism=0 ab_bad=0' ;;
    perf)
      # perf_base 无依赖链（只量背靠背吞吐），硬判据是 B1/B2 数值 + 数据可分辨性，
      # 由 `PERF_BASE verdict=ALL_OK` 汇总；其余三例额外要求 chain=OK。其独立性按例区分：
      # perf_vdot 的 chain=OK 来自独立行；perf_vadd/perf_vmacc 的 chain=OK 就在汇总行内。
      # perf_base_chain **不在** manifest.tsv（口径裁定：保持独立测量，不并入 30 例官方回归
      # 清单；）。本分支只为「万一被放进临时清单（如 results/manifest.b3.tsv）
      # 直接走 20-run 时」保留自检串，正常路径由 core-package/scripts/91-run-b3.sh 判负。
      # 其 verdict=ALL_OK 已把 12 项子判据（vl/链终值/轮次一致/长度可分辨/阶梯链/B3 可分辨）
      # 聚合在汇总行内，故只要求汇总行命中（不另加 chain=OK：该用例的链自检字段名是
      # chain_free/chain_free_alt，与其它三例的 chain= 不同名）。
      case "$2" in
        perf_vdot)  printf '%s\n' 'PERF_VDOT verdict=ALL_OK' 'chain=OK' ;;
        perf_base)  echo 'PERF_BASE verdict=ALL_OK' ;;
        perf_vadd)  printf '%s\n' 'PERF_VADD verdict=ALL_OK' 'chain=OK' ;;
        perf_vmacc) printf '%s\n' 'PERF_VMACC verdict=ALL_OK' 'chain=OK' ;;
        perf_base_chain) echo 'PERF_BASE_CHAIN verdict=ALL_OK' ;;
        *)          echo '' ;;
      esac ;;
    *)                            echo '' ;;
  esac
}

run_case() { # cid cls image extra
  local cid="$1" cls="$2" img="$3" extra="${4:-}"
  local clog="$CASES_DIR/${cid}.${RUN_ID}.log"
  local rc=0 good abort bad regbad
  if [ "$DRY_RUN" != "1" ]; then
    # shellcheck disable=SC2086
    timeout "$CASE_TIMEOUT_S" "$EMU_BIN" --diff "$REF_SO" -i "$img" --max-instr="$MAX_INSTR" $extra \
      >"$clog" 2>&1 || rc=$?
  fi
  good="$(grep -c 'HIT GOOD TRAP' "$clog" 2>/dev/null || true)"
  abort="$(grep -c 'ABORT' "$clog" 2>/dev/null || true)"
  bad="$(grep -c 'HIT BAD TRAP' "$clog" 2>/dev/null || true)"
  # NEMU ref.c:471-473：NEMU 与 DUT 的 state 大小不一致时打的报错串；
  # 出现即说明参照模型与 DUT 不配套（1400 B 口径，见 ALGORITHM.md:164）
  regbad="$(grep -c 'is configured with different states than DUT' "$clog" 2>/dev/null || true)"
  if [ "${regbad:-0}" -gt 0 ]; then REG_SIZE_BAD=$((REG_SIZE_BAD + 1)); fi
  local st
  if [ "$cls" = "negative" ]; then
    # 负向判据：
    # 自定义指令被判非法时，DUT 与 NEMU 双侧一致地进入 double-trap 路径，
    # difftest 对此打印的是 "HIT CRITICAL ERROR…" 然后 GOOD TRAP（traps.cpp:144-147），
    # **不会**出现 ABORT —— ABORT 只代表 DUT≠REF。所以判据改为三条同时成立：
    #   ① 出现 HIT CRITICAL ERROR（确实按非法指令陷入，且两端一致）
    #   ② 无任何失配串（"diff REF" / "Different operands"）且 ABORT=0
    #   ③ 用例哨兵串未出现（该串只在「指令没陷入非法、程序走到下一步」时才打印）
    local crit mismatch sentinel
    crit="$(grep -ac 'HIT CRITICAL ERROR' "$clog" 2>/dev/null || true)"
    mismatch="$(grep -acE 'diff REF|Different operands' "$clog" 2>/dev/null || true)"
    sentinel="$(grep -ac "${NEG_SENTINEL:-未如期陷入非法指令}" "$clog" 2>/dev/null || true)"
    if [ "${crit:-0}" -ge 1 ] && [ "${mismatch:-0}" = "0" ] && [ "${abort:-0}" = "0" ] \
       && [ "${sentinel:-0}" = "0" ]; then
      st="通过"
    else
      st="失败(负例未如期陷入或存在失配:CRIT=${crit:-0} MISMATCH=${mismatch:-0} SENTINEL=${sentinel:-0} ABORT=${abort:-0})"
    fi
  else
    if [ "$cls" = "g0" ]; then
      # G0 反例（ALGORITHM §3.1「harness 负向自检」）：用例的**期望值被故意写错 1 bit**，
      # 但 DUT 与 NEMU 仍然逐位一致 ⇒ 一定 HIT GOOD TRAP、一定没有 ABORT。
      # 所以它只能被「自检串」判据抓住：日志必须出现 "CASE <cid>: MISMATCH" 且不得出现 MATCH 串。
      # 本用例通过 = 证明本包的空绿防护（要求自检通过串）真的起作用。
      local gm ge
      gm="$(grep -acF "CASE ${cid}: MISMATCH" "$clog" 2>/dev/null || true)"
      ge="$(grep -acF "CASE ${cid}: MATCH" "$clog" 2>/dev/null || true)"
      G0_REQ=$((G0_REQ + 1))
      if [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" = "0" ] && [ "$gm" -ge 1 ] && [ "$ge" = "0" ]; then
        st="通过"; G0_CAUGHT=$((G0_CAUGHT + 1))
      else
        st="失败(空绿防护失效:GOOD=${good:-0} MISMATCH=${gm:-0} MATCH=${ge:-0} ABORT=${abort:-0})"
      fi
    else
      # 正例判据 = GOOD TRAP ∧ 无 ABORT/BAD ∧ 本用例的自检通过串在场。
      # 只有 GOOD TRAP 不构成通过：AM 里用例 return 非零也照样跑到结尾打 GOOD TRAP，
      # 那是「空绿」（ALGORITHM §3.1，由 g0 类用例做机械证明）。
      local vpat vpat_disp vhit vp vp_hit
      vpat="$(selfcheck_pattern "$cls" "$cid")"
      vhit=1
      vpat_disp=""
      if [ -n "$vpat" ]; then
        SELFCHK_REQ=$((SELFCHK_REQ + 1))
        # 一行一条 ERE：全部命中才算自检通过（空行忽略）。
        while IFS= read -r vp; do
          [ -n "$vp" ] || continue
          vpat_disp="${vpat_disp:+$vpat_disp && }$vp"
          vp_hit="$(grep -acE "$vp" "$clog" 2>/dev/null || true)"
          [ "${vp_hit:-0}" -ge 1 ] || vhit=0
        done <<< "$vpat"
      fi
      if [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" -eq 0 ] && [ "${bad:-0}" -eq 0 ] \
         && { [ -z "$vpat" ] || [ "${vhit:-0}" -ge 1 ]; }; then
        st="通过"
        [ -n "$vpat" ] && SELFCHK_OK=$((SELFCHK_OK + 1))
      elif [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" = "0" ] && [ -n "$vpat" ] && [ "${vhit:-0}" = "0" ]; then
        st="失败(自检未过:GOOD TRAP 但未命中自检通过串 /${vpat_disp:-$vpat}/)"
      else
        st="失败"
      fi
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$cid" "$cls" "$st" "${good:-0}" "${abort:-0}" "${bad:-0}" "$clog" >>"$CASES_TSV"
  add_case_json "$cid" "$cls" "$st" "${good:-0}" "${abort:-0}" "$clog"
  log "  case $cid [$cls] -> $st (GOOD=${good:-0} ABORT=${abort:-0} BAD=${bad:-0} rc=$rc)"

  if [ "$cls" = "perf" ]; then
    PERF_CASES=$((PERF_CASES + 1))
    # 三口径：用例程序需要打印 VDOT_METRIC <名字> <数值>（L_vdot / T_steady / T_kernel）
    # T5 三链：同时抓 L_vadd / L_vmacc 供 ΔL 判据用（HARD-DESIGN.md:188）
    local mname mval
    while read -r mname mval _; do
      [ -n "${mname:-}" ] || continue
      add_metric_json "$mname" "$mval" "$cid"
      METRIC_NAMES+=("$mname")
      case "$mname" in
        L_vadd)  L_VADD="$mval" ;;
        L_vmacc) L_VMACC="$mval" ;;
        L_vdot)  L_VDOT="$mval" ;;
      esac
      log "  metric $cid: $mname=$mval"
    done < <(grep -E '^VDOT_METRIC[[:space:]]+' "$clog" 2>/dev/null | sed 's/^VDOT_METRIC[[:space:]][[:space:]]*//' | tr -d '\r' || true)
  fi
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --smoke) MODE="smoke"; ITEM="$ITEM_SMOKE"; PURPOSE="difftest 冒烟"; shift ;;
      --full)  MODE="full";  ITEM="$ITEM_FULL";  PURPOSE="difftest 全量+随机+基线"; shift ;;
      --manifest) MANIFEST="${2:?--manifest 需要参数}"; shift 2 ;;
      --emu) EMU_BIN="${2:?--emu 需要参数}"; shift 2 ;;
      --ref-so) REF_SO="${2:?--ref-so 需要参数}"; shift 2 ;;
      --max-instr) MAX_INSTR="${2:?--max-instr 需要参数}"; shift 2 ;;
      --timeout) TIMEOUT_S="${2:?--timeout 需要参数}"; shift 2 ;;
      --write-baseline) WRITE_BASELINE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] difftest 属重计算，禁止在登录节点执行。" >&2
    echo "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=01:00:00 ${SCRIPT_PATH} --smoke" >&2
    exit 3
  fi

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  LOG_FILE="$RESULT_ROOT/20-$MODE-$RUN_ID.log"
  JSON_FILE="$RESULT_ROOT/20-$MODE-$RUN_ID.json"
  CASES_TSV="$RESULT_ROOT/20-$MODE-$RUN_ID.cases.tsv"
  guard_path "$CORE_DIR"; guard_path "$RESULT_ROOT"
  mkdir -p "$RESULT_ROOT" "$CASES_DIR" "$CORE_DIR/results/logs"
  : >"$CASES_TSV"
  log "===== $SCRIPT_NAME mode=$MODE max_instr=$MAX_INSTR timeout=${TIMEOUT_S}s ====="
  module_init

  local SRC_ROOT="${SRC_ROOT:-$CORE_DIR/src}"
  local NOOP_HOME="$SRC_ROOT/XiangShan"
  local NEMU_HOME="$SRC_ROOT/NEMU"
  [ -n "$EMU_BIN" ] || EMU_BIN="$NOOP_HOME/build/emu"
  [ -n "$REF_SO" ] || REF_SO="$NEMU_HOME/build/riscv64-nemu-interpreter-so"
  [ -n "$MANIFEST" ] || MANIFEST="$CORE_DIR/test/manifest.tsv"

  [ -x "$EMU_BIN" ] || fail_unrun "缺 emu 可执行文件：$EMU_BIN（先跑 10-build-emu.sh）"
  [ -f "$REF_SO" ] || fail_unrun "缺 NEMU ref .so：$REF_SO（先跑 10-build-emu.sh）"
  [ -f "$MANIFEST" ] || fail_unrun "缺用例清单：$MANIFEST（格式见 README §4；test/ 尚未产出）"

  # NEMU 扩展与向量寄存器参与比较
  local nm_hits
  nm_hits="$(nm -a "$REF_SO" 2>/dev/null | grep -cw exec_vdot || true)"
  if [ "${nm_hits:-0}" -ge 1 ]; then
    add_criterion "nm_exec_vdot" "nm 命中 exec_vdot >= 1 行" "命中 $nm_hits 行" "达标"
  else
    add_criterion "nm_exec_vdot" "nm 命中 exec_vdot >= 1 行" "命中 0 行（static inline 可能被内联；vdot 用例结果不可信）" "未达标"
  fi
  local header
  header="$(find "$NOOP_HOME/build" -name 'difftest-state.h' -print -quit 2>/dev/null || true)"
  if [ -n "$header" ] && grep -q 'CONFIG_DIFFTEST_ARCHVECREGSTATE' "$header" 2>/dev/null; then
    add_criterion "vec_reg_compare" "生成的 difftest-state.h 含 CONFIG_DIFFTEST_ARCHVECREGSTATE" "$header" "达标"
  else
    add_criterion "vec_reg_compare" "生成的 difftest-state.h 含 CONFIG_DIFFTEST_ARCHVECREGSTATE" "${header:-未找到 difftest-state.h}（向量寄存器可能不参与比较 → 空绿风险）" "未达标"
  fi

  local total=0 pass=0 fail=0
  local cid cls img extra

  # 第一遍：统计本模式选中的用例数（用于收紧单例 timeout 与 cases_all_ran）
  while read -r cid cls img extra || [ -n "${cid:-}" ]; do
    case "${cid:-}" in ''|'#'*) continue ;; esac
    class_selected "${cls:-}" || continue
    SELECTED_TOTAL=$((SELECTED_TOTAL + 1))
  done <"$MANIFEST"

  # 单例 timeout 收紧（B7）：min(TIMEOUT_S, job_time_left/剩余用例数)，避免作业被 Slurm 在时限处杀掉。
  # 作业剩余时间取 SLURM_JOB_END_TIME（epoch）——取不到就退回 TIMEOUT_S。
  local job_left=""
  if [ -n "${SLURM_JOB_END_TIME:-}" ]; then
    case "$SLURM_JOB_END_TIME" in
      *[!0-9]*) log "[WARN] SLURM_JOB_END_TIME=$SLURM_JOB_END_TIME 不是 epoch，跳过单例 timeout 收紧" ;;
      *) job_left=$(( SLURM_JOB_END_TIME - $(date +%s) )) ;;
    esac
  fi

  while read -r cid cls img extra || [ -n "${cid:-}" ]; do
    case "${cid:-}" in ''|'#'*) continue ;; esac
    class_selected "$cls" || continue
    if [ ! -f "$img" ]; then
      log "  [未运行] $cid：镜像不存在 $img"
      NOT_RUN_TOTAL=$((NOT_RUN_TOTAL + 1))
      total=$((total + 1))
      add_case_json "$cid" "$cls" "未运行(缺镜像)" "0" "0" ""
      printf '%s\t%s\t%s\t0\t0\t0\t\n' "$cid" "$cls" "未运行(缺镜像)" >>"$CASES_TSV"
      continue
    fi
    total=$((total + 1))
    EXECUTED_TOTAL=$((EXECUTED_TOTAL + 1))
    CASE_TIMEOUT_S="$TIMEOUT_S"
    if [ -n "$job_left" ] && [ "$job_left" -gt 0 ]; then
      local remaining_cases=$((SELECTED_TOTAL - EXECUTED_TOTAL + 1))
      local share=$((job_left / remaining_cases))
      if [ "$share" -lt "$CASE_TIMEOUT_S" ]; then CASE_TIMEOUT_S="$share"; fi
      [ "$CASE_TIMEOUT_S" -lt 1 ] && CASE_TIMEOUT_S=1
    fi
    run_case "$cid" "$cls" "$img" "${extra:-}"
    if [ -n "$job_left" ] && [ "$job_left" -gt 0 ]; then job_left=$((job_left - CASE_TIMEOUT_S)); fi
  done <"$MANIFEST"

  if [ "$total" -eq 0 ]; then
    add_criterion "cases_ran" "至少运行 1 个用例" "0 个（清单为空或本模式无选中用例）" "未运行"
    write_json "未运行"
    log "未运行：清单中没有可执行的用例"
    exit 2
  fi

  if [ "$NOT_RUN_TOTAL" -eq 0 ]; then
    add_criterion "cases_all_ran" "选中用例全部执行" "$EXECUTED_TOTAL/$SELECTED_TOTAL" "达标"
  else
    add_criterion "cases_all_ran" "选中用例全部执行" "$EXECUTED_TOTAL/$SELECTED_TOTAL（缺镜像 $NOT_RUN_TOTAL 个）" "未运行"
  fi

  pass="$(awk -F'\t' '$3=="通过"' "$CASES_TSV" | wc -l | tr -d ' ')"
  # 失败数只统计「已执行但未通过」：total 里含未运行用例，不能用 total-pass
  fail=$((EXECUTED_TOTAL - pass))
  if [ "$fail" -gt 0 ]; then
    add_criterion "cases_pass" "全部选中用例通过（$MODE）" "$pass/$total，失败 $fail（另 $NOT_RUN_TOTAL 个未运行）" "未达标"
  elif [ "$NOT_RUN_TOTAL" -gt 0 ]; then
    add_criterion "cases_pass" "全部选中用例通过（$MODE）" "$pass/$total（$NOT_RUN_TOTAL 个未运行）" "未运行"
  else
    add_criterion "cases_pass" "全部选中用例通过（$MODE）" "$pass/$total" "达标"
  fi

  # reg 尺寸一致（M10）：运行日志不含 NEMU ref.c:471-473 的 state 不一致报错串。
  # 1400 B 是 DUT/NEMU 配套的 state 大小口径（design/ALGORITHM.md:164）。
  if [ "$EXECUTED_TOTAL" -eq 0 ]; then
    add_criterion "reg_size_match" "日志不含 'is configured with different states than DUT'" "0 个用例执行，无法判定" "未运行"
  elif [ "$REG_SIZE_BAD" -eq 0 ]; then
    add_criterion "reg_size_match" "日志不含 'is configured with different states than DUT'" "0 次（1400 B 口径）" "达标"
  else
    add_criterion "reg_size_match" "日志不含 'is configured with different states than DUT'" "$REG_SIZE_BAD 个用例命中（DIFFTEST_REG_SIZE≠1400 B）" "未达标"
  fi

  # 防空绿（ALGORITHM §3.1 G0）：
  #   ① 每个正向用例除 GOOD TRAP 外，必须命中自己的「自检通过串」；
  #   ② manifest 里的 g0 反例（期望值故意错 1 bit、必然 GOOD TRAP）必须被 ① 同一条规则判负。
  # 只有 manifest 中确实存在 g0 类用例时，本判据才可能是「达标」；否则记「未运行」（不是通过）。
  if [ "$G0_REQ" -gt 0 ]; then
    if [ "$SELFCHK_OK" -eq "$SELFCHK_REQ" ] && [ "$SELFCHK_REQ" -gt 0 ] && [ "$G0_CAUGHT" -eq "$G0_REQ" ]; then
      add_criterion "no_empty_green" "正例带自检通过串，且 G0 反例被同一判据判负" "自检串 $SELFCHK_OK/$SELFCHK_REQ 命中；G0 捕获 $G0_CAUGHT/$G0_REQ（GOOD TRAP 但自检 MISMATCH）" "达标"
    else
      add_criterion "no_empty_green" "正例带自检通过串，且 G0 反例被同一判据判负" "自检串 $SELFCHK_OK/$SELFCHK_REQ 命中；G0 捕获 $G0_CAUGHT/$G0_REQ" "未达标"
    fi
  elif [ "$SELFCHK_REQ" -gt 0 ]; then
    add_criterion "no_empty_green" "正例带自检通过串，且 G0 反例被同一判据判负" "清单缺 g0 反例（自检串 $SELFCHK_OK/$SELFCHK_REQ 命中，但防护未被证伪过）" "未运行"
  else
    add_criterion "no_empty_green" "正例带自检通过串，且 G0 反例被同一判据判负" "本次没有带自检串的用例，也无法判定" "未运行"
  fi

  # --smoke 强制 vadd / vdot-pos / vdot-neg / vdot-bound 四类各至少 1 例（M5）
  if [ "$MODE" = "smoke" ]; then
    local need_cls miss_cls="" n_cls
    for need_cls in vadd vdot-pos vdot-neg vdot-bound; do
      n_cls="$(awk -F'\t' -v c="$need_cls" '$2==c && $3!="未运行(缺镜像)"{n++} END{print n+0}' "$CASES_TSV")"
      [ "$n_cls" -ge 1 ] || miss_cls="$miss_cls $need_cls"
    done
    if [ -z "$miss_cls" ]; then
      add_criterion "smoke_classes" "vadd/vdot-pos/vdot-neg/vdot-bound 各 >= 1 例" "四类齐备" "达标"
    else
      add_criterion "smoke_classes" "vadd/vdot-pos/vdot-neg/vdot-bound 各 >= 1 例" "缺类：$miss_cls" "未运行"
    fi
  fi

  # 三口径齐全（M10）：perf 用例必须打印 L_vdot / T_steady / T_kernel
  if [ "$PERF_CASES" -gt 0 ]; then
    local need_m miss_m="" have_m mn
    for need_m in L_vdot T_steady T_kernel; do
      have_m=0
      for mn in ${METRIC_NAMES[@]+"${METRIC_NAMES[@]}"}; do [ "$mn" = "$need_m" ] && have_m=1; done
      [ "$have_m" = "1" ] || miss_m="$miss_m $need_m"
    done
    if [ -z "$miss_m" ]; then
      add_criterion "metrics_three" "三口径 L_vdot/T_steady/T_kernel 均出现" "齐备" "达标"
    else
      add_criterion "metrics_three" "三口径 L_vdot/T_steady/T_kernel 均出现" "缺：$miss_m" "未达标"
    fi
  elif [ "$MODE" = "full" ]; then
    add_criterion "metrics_three" "三口径 L_vdot/T_steady/T_kernel 均出现" "没有任何 perf 用例执行" "未运行"
  fi

  # T5 ΔL 三链（HARD-DESIGN.md:188 的验收式）：L_vmacc==L_vdot、L_vmacc−L_vadd==1。
  # 三个数都来自用例自报的 VDOT_METRIC（perf_vdot/perf_vmacc/perf_vadd 的**中位数**，
  # 同一套「逐次 rdcycle、N=2000、去 16 次暖机」口径）；缺任一项记「未运行」，不记通过。
  if [ -n "$L_VADD" ] && [ -n "$L_VMACC" ] && [ -n "$L_VDOT" ]; then
    local dl_mv
    dl_mv=$((L_VMACC - L_VADD))
    if [ "$L_VMACC" -eq "$L_VDOT" ] && [ "$dl_mv" -eq 1 ]; then
      add_criterion "t5_delta_latency" "T5 ΔL：L_vmacc==L_vdot 且 L_vmacc-L_vadd==1" \
        "L_vadd=$L_VADD L_vmacc=$L_VMACC L_vdot=$L_VDOT (ΔL_mv=$dl_mv)" "达标"
    else
      add_criterion "t5_delta_latency" "T5 ΔL：L_vmacc==L_vdot 且 L_vmacc-L_vadd==1" \
        "L_vadd=$L_VADD L_vmacc=$L_VMACC L_vdot=$L_VDOT (ΔL_mv=$dl_mv；期望 0/1)" "未达标"
    fi
  elif [ "$MODE" = "full" ]; then
    add_criterion "t5_delta_latency" "T5 ΔL：L_vmacc==L_vdot 且 L_vmacc-L_vadd==1" \
      "未集齐三数（L_vadd=${L_VADD:-缺} L_vmacc=${L_VMACC:-缺} L_vdot=${L_VDOT:-缺}）" "未运行"
  fi

  # regression_delta（仅 --full；只有在全部选中用例都执行后才允许写基线，M5）
  REGRESSION_DELTA="未运行"
  if [ "$MODE" = "full" ]; then
    local baseline="$RESULT_ROOT/baseline.tsv"
    if [ "$NOT_RUN_TOTAL" -gt 0 ]; then
      add_criterion "regression_delta" "新增失败数 == 0" "有 $NOT_RUN_TOTAL 个用例未运行：不写基线、不比较" "未运行"
    elif [ -f "$baseline" ]; then
      # 失败状态带后缀（如 失败(自检未过:…) / 失败(空绿防护失效:…)），故用前缀匹配
      REGRESSION_DELTA="$(awk -F'\t' 'NR==FNR{b[$1]=$2; next} ($1 in b) && b[$1]=="通过" && $3 ~ /^失败/ {n++} END{print n+0}' "$baseline" "$CASES_TSV")"
      add_criterion "regression_delta" "新增失败数 == 0" "$REGRESSION_DELTA" "$( [ "$REGRESSION_DELTA" = "0" ] && echo 达标 || echo 未达标 )"
    else
      if [ "$DRY_RUN" = "1" ]; then
        add_criterion "regression_delta" "新增失败数 == 0" "基线缺失且 dry-run：不写基线（防空跑污染）" "未运行"
      else
        add_criterion "regression_delta" "新增失败数 == 0" "基线缺失：本次写入基线 $baseline" "未运行"
        awk -F'\t' '{print $1"\t"$3}' "$CASES_TSV" >"$baseline"
        log "已写回归基线：$baseline（首次 --full，无对比对象；建议先在 P0-3 用 --write-baseline 建基线）"
      fi
    fi
  fi

  # --write-baseline（P0-3 用）：全执行且非 dry-run 时写基线，供 --full 单遍对比（免双跑省机时）
  if [ "$WRITE_BASELINE" = "1" ] && [ "$MODE" != "full" ]; then
    local wbaseline="$RESULT_ROOT/baseline.tsv"
    if [ "$NOT_RUN_TOTAL" -gt 0 ]; then
      add_criterion "baseline_written" "全部用例执行后写基线" "有 $NOT_RUN_TOTAL 个未运行：不写基线" "未运行"
    elif [ "$DRY_RUN" = "1" ]; then
      add_criterion "baseline_written" "全部用例执行后写基线" "dry-run：不写基线（防空跑污染）" "未运行"
    elif [ -f "$wbaseline" ]; then
      add_criterion "baseline_written" "全部用例执行后写基线" "基线已存在（$wbaseline），不覆盖" "达标"
    else
      awk -F'\t' '{print $1"\t"$3}' "$CASES_TSV" >"$wbaseline"
      add_criterion "baseline_written" "全部用例执行后写基线" "已写 $wbaseline" "达标"
    fi
  fi

  local ok=0 unrun=0 c
  for c in ${CRITERIA[@]+"${CRITERIA[@]}"}; do
    case "$c" in *'"未达标"'*) ok=1 ;; esac
    case "$c" in *'"未运行"'*) unrun=1 ;; esac
  done
  if [ "$ok" = "0" ] && [ "$unrun" = "0" ]; then
    write_json "通过"
    log "判据：达标（$pass/$total）"
    exit 0
  fi
  if [ "$ok" = "0" ] && [ "$unrun" = "1" ]; then
    write_json "未运行"
    log "判据：存在未运行项（$pass/$total；未运行用例 $NOT_RUN_TOTAL 个），不得记通过"
    exit 2
  fi
  write_json "失败"
  log "判据：未达标（$pass/$total）"
  exit 1
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
trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
