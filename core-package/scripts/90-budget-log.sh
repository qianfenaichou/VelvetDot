#!/usr/bin/env bash
# =============================================================================
# 验证项：机时记账与预算约束（不占机时；所有作业结束时自动调用）
# 预计机时：0（纯文件记账 + 只读 sacct，不提交作业、不占计算资源）
# 预算：总 11.0 机时（1 机时 = 1 计算节点 × 1 小时，X86 32C / 126.5 GB）
#       P0-env 2.0 / P0-emu 3.0 / P0-difftest-smoke 1.0 / P1-golden 0.1
#       P2-yosys-formal 1.5 / P3-full 3.0 / buffer 0.4
# 状态：已在昆山实跑（`results/budget-log.tsv` 71 数据行；`auto` 由各作业 trap 调用）。
#       本行原写「未在昆山执行过」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。本脚本只读 sacct/环境变量，不提交作业；不写 --qos=
# 密钥：不读取、不打印任何密钥文件
# 用法：
#   bash 90-budget-log.sh record --item P0-emu --job 123456 --partition kshcnormal \
#        --cores 32 --elapsed 02:41:13 [--purpose "..."] [--nodes 1]
#   bash 90-budget-log.sh auto --item P0-emu [--purpose "..."]   # 作业内：读 SLURM_* 与 sacct
#   bash 90-budget-log.sh summary                               # 用量 vs 预算；超 50% / 总额 >10.6 / 动用缓冲 / P0 未通过却用 P2/P3 → 退出码 1
#   bash 90-budget-log.sh balance                               # 开跑前用 sacct 核余额
#   bash 90-budget-log.sh check-submit --item P0-emu --time 03:00:00   # 提交前核对 --time 上限不超预算/剩余
#   bash 90-budget-log.sh list
# 判据：summary 退出码 0（无单项超支 50%、总额不超 10.6、未动用缓冲，且 P0 未通过时不消耗 P2/P3）
# 产物：results/budget-log.tsv
# 退出码：0 合规 / 1 超支或挤占 / 2 无可读数据 / 3 用法错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
readonly TSV="$CORE_DIR/results/budget-log.tsv"
readonly TOTAL_BUDGET="11.0"

declare -A BUDGET=(
  [P0-env]=2.0
  [P0-emu]=3.0
  [P0-difftest-smoke]=1.0
  [P1-golden]=0.1
  [P2-yosys-formal]=1.5
  [P3-full]=3.0
  [buffer]=0.4
)

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { echo "[FATAL] $*" >&2; exit 3; }

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ensure_tsv() {
  guard_path "$CORE_DIR"
  mkdir -p "$(dirname "$TSV")"
  if [ ! -f "$TSV" ]; then
    printf '#time\tjob_id\tpartition\tcores\telapsed_s\tcore_hours\tnode_hours\titem\tpurpose\n' >"$TSV"
  fi
}

# 02:41:13 / 3-02:41:13 / 161:13 / 120 -> 秒
elapsed_to_sec() {
  local e="$1" d=0 h=0 m=0 s=0
  case "$e" in
    *-*) d="${e%%-*}"; e="${e#*-}" ;;
  esac
  case "$e" in
    *:*:*)
      h="${e%%:*}"; e="${e#*:}"
      m="${e%%:*}"; s="${e#*:}" ;;
    *:*)
      m="${e%%:*}"; s="${e#*:}" ;;
    '') echo 0; return 0 ;;
    *) s="$e" ;;
  esac
  printf '%s' $(( (10#${d:-0} * 86400) + (10#${h:-0} * 3600) + (10#${m:-0} * 60) + 10#${s:-0} ))
}

fmt_hours() { printf '%.3f' "$1"; }

cmd_record() {
  local item="" job="" partition="${SLURM_JOB_PARTITION:-unknown}" cores="${SLURM_CPUS_ON_NODE:-0}" \
        elapsed="" purpose="-" nodes="1"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item) item="${2:?--item 需要参数}"; shift 2 ;;
      --job) job="${2:?--job 需要参数}"; shift 2 ;;
      --partition) partition="${2:?--partition 需要参数}"; shift 2 ;;
      --cores) cores="${2:?--cores 需要参数}"; shift 2 ;;
      --elapsed) elapsed="${2:?--elapsed 需要参数}"; shift 2 ;;
      --purpose) purpose="${2:?--purpose 需要参数}"; shift 2 ;;
      --nodes) nodes="${2:?--nodes 需要参数}"; shift 2 ;;
      *) die "record: 未知参数 $1" ;;
    esac
  done
  [ -n "$item" ] || die "record: 缺 --item"
  [ -n "${BUDGET[$item]:-}" ] || die "record: 未知 item '$item'（允许：${!BUDGET[*]}）"
  [ -n "$elapsed" ] || die "record: 缺 --elapsed（HH:MM:SS）"

  local sec chours nhours
  sec="$(elapsed_to_sec "$elapsed")"
  chours="$(fmt_hours "$(awk -v s="$sec" -v c="$cores" 'BEGIN{printf "%.6f", s*c/3600}')")"
  nhours="$(fmt_hours "$(awk -v s="$sec" -v n="$nodes" 'BEGIN{printf "%.6f", s*n/3600}')")"
  ensure_tsv
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date '+%F %T')" "${job:-NA}" "$partition" "$cores" "$sec" "$chours" "$nhours" "$item" "$purpose" >>"$TSV"
  log "记账：item=$item job=${job:-NA} partition=$partition cores=$cores elapsed=${sec}s core_hours=$chours node_hours=$nhours"
}

cmd_auto() {
  local item="" purpose="-"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item) item="${2:?--item 需要参数}"; shift 2 ;;
      --purpose) purpose="${2:?--purpose 需要参数}"; shift 2 ;;
      *) die "auto: 未知参数 $1" ;;
    esac
  done
  [ -n "$item" ] || die "auto: 缺 --item"
  [ -n "${SLURM_JOB_ID:-}" ] || { log "auto: 不在作业内（无 SLURM_JOB_ID），跳过记账"; exit 0; }

  local elapsed="" cores="${SLURM_CPUS_ON_NODE:-0}"
  if command -v sacct >/dev/null 2>&1; then
    # Elapsed 形如 00:03:21；状态必须是终态才有 Elapsed
    elapsed="$(sacct -j "$SLURM_JOB_ID" --noheader --parsable2 --format=JobID,Elapsed,AllocCPUS 2>/dev/null \
      | awk -F'|' -v id="$SLURM_JOB_ID" '$1==id{print $2" "$3; exit}')"
    if [ -n "$elapsed" ]; then
      cores="${elapsed##* }"
      elapsed="${elapsed%% *}"
    fi
  fi
  if [ -z "$elapsed" ] || [ "$elapsed" = "Unknown" ]; then
    # 退路：用作业起始时间估算（SLURM_JOB_START_TIME 或 scontrol 的 StartTime 不可靠，用 shell 本地时间）
    local start="${SLURM_JOB_START_TIME:-}"
    if [ -n "$start" ] && date -d "$start" +%s >/dev/null 2>&1; then
      local now
      now="$(date +%s)"
      elapsed="$(awk -v s="$(date -d "$start" +%s)" -v n="$now" 'BEGIN{printf "%02d:%02d:%02d", (n-s)/3600, ((n-s)%3600)/60, (n-s)%60}')"
      log "auto: sacct 无终态记录，按 SLURM_JOB_START_TIME 估算 elapsed=$elapsed"
    else
      log "auto: 无法获得 elapsed（sacct 为空且无 SLURM_JOB_START_TIME），本次不记账"
      exit 2
    fi
  fi
  cmd_record --item "$item" --job "$SLURM_JOB_ID" --partition "${SLURM_JOB_PARTITION:-unknown}" \
             --cores "$cores" --elapsed "$elapsed" --purpose "$purpose"
}

cmd_summary() {
  [ -f "$TSV" ] || { log "summary: 无记账文件 $TSV（尚未消耗机时）"; exit 2; }
  log "== 机时预算 vs 用量（总预算 ${TOTAL_BUDGET} 机时）=="
  local item used budget ratio flag rc=0
  for item in P0-env P0-emu P0-difftest-smoke P1-golden P2-yosys-formal P3-full buffer; do
    budget="${BUDGET[$item]}"
    used="$(awk -F'\t' -v it="$item" '$8==it{s+=$7} END{printf "%.3f", s+0}' "$TSV")"
    ratio="$(awk -v u="$used" -v b="$budget" 'BEGIN{ if (b>0) printf "%.0f", 100*u/b; else print 0 }')"
    flag=""
    if awk -v u="$used" -v b="$budget" 'BEGIN{exit !(u > 1.5*b)}'; then
      flag="  <== 超支 50%，停下重估"
      rc=1
    fi
    printf '  %-20s 预算 %5s  已用 %7s  占比 %4s%%%s\n' "$item" "$budget" "$used" "$ratio" "$flag"
  done
  local total_used buffer_used
  total_used="$(awk -F'\t' 'NR>1 && $8!="buffer"{s+=$7} END{printf "%.3f", s+0}' "$TSV")"
  printf '  %-20s 预算 %5s  已用 %7s\n' "合计（不含缓冲）" "$(awk -v t="$TOTAL_BUDGET" 'BEGIN{printf "%.1f", t-0.4}')" "$total_used"

  # 总额硬闸（B7）：不含缓冲的合计 > 10.6 或缓冲被动用 → 退出码 1
  if awk -v u="$total_used" 'BEGIN{exit !(u > 10.6)}'; then
    log "[超支] 合计（不含缓冲）$total_used > 10.6 机时：停跑、重估"
    rc=1
  fi
  buffer_used="$(awk -F'\t' '$8=="buffer"{s+=$7} END{printf "%.3f", s+0}' "$TSV")"
  if awk -v u="$buffer_used" 'BEGIN{exit !(u > 0)}'; then
    log "[告警] 缓冲已被动用 $buffer_used 机时（合计预算 11.0 已进入重跑/排队损耗区）"
    rc=1
  fi

  # P0 是否完成：按 results/{env,emu,difftest}/*.json 的最新 status 判定，而不是按「已用机时 < 6.0」（M8）
  local p0_state p23_used
  p0_state="$(p0_completion_state || echo "无法判定（读 results/*.json 失败）")"
  p23_used="$(awk -F'\t' '$8=="P2-yosys-formal" || $8=="P3-full"{s+=$7} END{printf "%.3f", s+0}' "$TSV")"
  log "P0 完成状态（读 results/*.json 最新 status）：$p0_state"
  if [ "${p0_state#全部通过}" = "$p0_state" ] && awk -v x="$p23_used" 'BEGIN{exit !(x > 0)}'; then
    log "[告警] P0 未全部通过（$p0_state）却已消耗 P2/P3 ${p23_used} 机时：确认没有挤占 P0"
    rc=1
  fi
  exit "$rc"
}

# 读 results/{env,emu,difftest}/*.json，按 item 取最新一份的 status。
# 全部三项都「通过」时输出「全部通过」，否则输出明细（如「P0-env=通过 缺记录=P0-emu」）。
p0_completion_state() {
  command -v python3 >/dev/null 2>&1 || { echo "无 python3，未判定"; return 0; }
  python3 - "$CORE_DIR/results" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
dirs = [os.path.join(root, d) for d in ("env", "emu", "difftest")]
wanted = {"P0-env", "P0-emu", "P0-difftest-smoke"}
latest = {}
for d in dirs:
    for p in glob.glob(os.path.join(d, "*.json")):
        try:
            with open(p) as f:
                data = json.load(f)
        except Exception:
            continue
        item = data.get("item", "")
        if item not in wanted:
            continue
        mtime = os.path.getmtime(p)
        if item not in latest or mtime > latest[item][0]:
            latest[item] = (mtime, str(data.get("status", "")))
if not latest:
    print("无记录")
    sys.exit(0)
parts = ["%s=%s" % (k, latest[k][1]) for k in sorted(latest)]
if set(latest) == wanted and all(v[1] == "通过" for v in latest.values()):
    print("全部通过")
else:
    missing = wanted - set(latest)
    if missing:
        parts.append("缺记录=%s" % ",".join(sorted(missing)))
    print(" ".join(parts))
PY
}

cmd_check_submit() {
  local item="" t=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item) item="${2:?--item 需要参数}"; shift 2 ;;
      --time) t="${2:?--time 需要参数}"; shift 2 ;;
      *) die "check-submit: 未知参数 $1" ;;
    esac
  done
  [ -n "$item" ] || die "check-submit: 缺 --item"
  [ -n "${BUDGET[$item]:-}" ] || die "check-submit: 未知 item '$item'（允许：${!BUDGET[*]}）"
  [ -n "$t" ] || die "check-submit: 缺 --time（HH:MM:SS，与 sbatch --time 同格式）"
  local sec hours budget total_used remain
  sec="$(elapsed_to_sec "$t")"
  hours="$(fmt_hours "$(awk -v s="$sec" 'BEGIN{printf "%.6f", s/3600}')")"
  budget="${BUDGET[$item]}"
  log "check-submit：item=$item --time=$t（$hours 机时）预算 $budget 机时"
  local rc=0
  if awk -v h="$hours" -v b="$budget" 'BEGIN{exit !(h > b)}'; then
    log "[超支] --time 上限 $hours 机时 > 该项预算 $budget 机时：请把 --time 收到 ≤ $budget"
    rc=1
  fi
  if [ -f "$TSV" ]; then
    total_used="$(awk -F'\t' 'NR>1 && $8!="buffer"{s+=$7} END{printf "%.6f", s+0}' "$TSV")"
  else
    total_used="0"
  fi
  remain="$(awk -v t="$TOTAL_BUDGET" -v u="$total_used" 'BEGIN{printf "%.6f", t-0.4-u}')"
  log "check-submit：已用（不含缓冲）$total_used，剩余（不含缓冲）$remain 机时"
  if awk -v h="$hours" -v r="$remain" 'BEGIN{exit !(h > r)}'; then
    log "[超支] --time 上限 $hours 机时 > 剩余 $remain 机时：先重估预算再提交"
    rc=1
  fi
  [ "$rc" = "0" ] && log "check-submit：允许提交（注意 sbatch --time 是上限，实耗以 auto 记账为准）"
  exit "$rc"
}

cmd_balance() {
  log "== 开跑前核余额（11 机时 = 用户口径余量，平台预算口径）=="
  if ! command -v sacct >/dev/null 2>&1; then
    log "sacct 不可用：本机不是调度器节点。到昆山登录节点重跑本命令。"
    exit 2
  fi
  local since
  since="$(date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || echo 2026-10-01)"
  log "查询区间：$since 起；用户：${USER:-?}"
  # 用 awk 'NR<=40' 而不是 head：head 提前关闭管道会让 sacct 收到 SIGPIPE，
  # 在 set -o pipefail 下整条管道返回 141 并把脚本杀掉（M9）。
  if ! sacct -u "${USER:-}" -S "$since" --noheader --parsable2 \
        --format=JobID,JobName,Partition,Elapsed,AllocCPUS,State 2>/dev/null \
    | awk -F'|' 'BEGIN{print "  JobID|JobName|Partition|Elapsed|AllocCPUS|State"} NR<=40{print "  "$0}'; then
    log "[WARN] sacct 查询失败：无法核对余额"
    exit 2
  fi
  local n
  n="$(sacct -u "${USER:-}" -S "$since" --noheader --parsable2 --format=JobID 2>/dev/null | wc -l | tr -d ' ')" \
    || { log "[WARN] sacct 计数失败"; exit 2; }
  log "近 30 天作业记录数：$n（余额口径以用户/订单为准；本脚本不做换算，只提供原始记录）"
  log "提醒：华东密钥 2026-11-22 22:44 到期，到期前在官网重置并更新 ~/.ssh/scnet_key（平台提醒）"
  exit 0
}

cmd_list() {
  [ -f "$TSV" ] || { log "无记账文件 $TSV"; exit 2; }
  column -t -s $'\t' "$TSV" 2>/dev/null || cat "$TSV"
}

main() {
  [ "$#" -gt 0 ] || die "缺子命令（record | auto | summary | balance | list | check-submit）"
  local sub="$1"; shift
  case "$sub" in
    record) cmd_record "$@" ;;
    auto) cmd_auto "$@" ;;
    summary) cmd_summary ;;
    balance) cmd_balance ;;
    list) cmd_list ;;
    check-submit) cmd_check_submit "$@" ;;
    -h|--help) usage ;;
    *) die "未知子命令：$sub" ;;
  esac
}

main "$@"
