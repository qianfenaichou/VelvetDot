#!/usr/bin/env bash
# =============================================================================
# 94-run-extra.sh — 扩容用例整套 difftest（走 manifest.extra.tsv，不碰 30 例主清单）
#
# 为什么需要这份（而不是直接走 20-run-difftest.sh）：
#   20-run-difftest.sh 的用例集合只来自 `--manifest` 指定的单一清单，而
#   `design/verify/cases/manifest.tsv`（30 行 / sha256 a90d1071…）是**官方回归口径的冻结件**，
#   扩容用例一律不得进该文件（口径同 perf_base_chain / vdot_xcontam 的「独立测量」裁定）。
#   本脚本按 91/92/93 的同一套「独立作业」思路复刻 20-run-difftest.sh 的 run_case 判据，
#   但**不修改** 20-run-difftest.sh 一个字。
#
# 判据（与 20-run-difftest.sh:222-300 逐条同构）：
#   正例（vdot-base / vdot-ov / vdot-pl）：HIT GOOD TRAP>=1 ∧ ABORT==0 ∧ BAD==0
#                                         ∧ 命中本用例自检串 `CASE <cid>: MATCH`
#   随机（vdot-rand10k）                ：同上 ∧ `RAND10K verdict=ALL_OK groups=10000 mism=0 model_bad=0 ab_bad=0`
#   G0 反例（g0）                       ：HIT GOOD TRAP>=1 ∧ ABORT==0 ∧ 出现 `CASE <cid>: MISMATCH`
#                                         ∧ **不得**出现 `CASE <cid>: MATCH`（防空绿机械证明）
#   负例（negative）                    ：HIT CRITICAL ERROR>=1 ∧ 无 `diff REF`/`Different operands`
#                                         ∧ ABORT==0 ∧ 无哨兵串「未如期陷入非法指令」
#   全局：reg_size_match（无 different-states 串）、nm_exec_vdot>=1、vec_reg_compare、
#         golden_crosscheck（extra_crosscheck.py == MATCH）、cases_all_ran
#
# 机时分类：P3-full（整套 difftest）。**如实记**：实跑前 `90-budget-log.sh summary` 已显示
#   P3-full 超自设预算（215%），本作业按授权执行，超支事实在 JSON 与报告里披露。
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 32 --time=02:30:00 core-package/scripts/94-run-extra.sh
#   参数：--manifest FILE --emu FILE --ref-so FILE --max-instr N --timeout SEC --rand-timeout SEC
#         --only <逗号分隔的 cid 或 cls>    只跑匹配行（冒烟用，仍按清单顺序）
#         --limit N                          只跑前 N 行（冒烟用）
#         --skip-crosscheck                  跳过金模型对拍（仅在缺 python3 的节点上）
#         --dry-run                          只打印将执行的命令
# 产物：results/difftest/extra/94-extra-<runid>.{log,json,cases.tsv}
#       results/difftest/extra/cases/<cid>.<runid>.log
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失） / 3 用法或环境错误
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 32
#SBATCH --time=02:30:00
#SBATCH -J vdot_extra129

set -uo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
CORE_DIR="${CORE_DIR:-$HOME/core}"
EMU="${EMU:-$CORE_DIR/src/XiangShan/build/emu}"
REF_SO="${REF_SO:-$CORE_DIR/src/NEMU/build/riscv64-nemu-interpreter-so}"
MANIFEST="${MANIFEST:-$CORE_DIR/test/manifest.extra.tsv}"
CROSSCHECK="${CROSSCHECK:-$CORE_DIR/verify/cases/extra_crosscheck.py}"
MAX_INSTR="${MAX_INSTR:-200000000}"
TIMEOUT_S="${TIMEOUT_S:-900}"
# 随机 10000 组是重计算用例：smoke 轮实测单例 900 s 不够（作业 127026020 的 vdot_rand10k
# rc=124 超时，见 results/difftest/extra/94-extra-20261106T134736.log 末段）。
# 给它单独的默认上限，不与普通定向用例共用 900 s。
RAND_TIMEOUT_S="${RAND_TIMEOUT_S:-5400}"
ONLY=""
LIMIT=0
SKIP_XCHECK=0
DRY_RUN=0
ITEM="P3-full"
PURPOSE="扩容用例整套 difftest（manifest.extra.tsv，独立作业；不改 30 例主清单）"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST="${2:?}"; shift 2 ;;
    --emu) EMU="${2:?}"; shift 2 ;;
    --ref-so) REF_SO="${2:?}"; shift 2 ;;
    --max-instr) MAX_INSTR="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT_S="${2:?}"; shift 2 ;;
    --rand-timeout) RAND_TIMEOUT_S="${2:?}"; shift 2 ;;
    --only) ONLY="${2:?}"; shift 2 ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --skip-crosscheck) SKIP_XCHECK=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
  esac
done

if [ -z "${SLURM_JOB_ID:-}" ] && [ "$DRY_RUN" != "1" ]; then
  echo "[FATAL] difftest 属重计算，禁止在登录节点执行。" >&2
  echo "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=02:30:00 ${BASH_SOURCE[0]}" >&2
  exit 3
fi

[ -r "$HOME/tools/env.sh" ] && . "$HOME/tools/env.sh"
[ -x "$EMU" ] || [ "$DRY_RUN" = "1" ] || { echo "[FATAL] 缺 emu：$EMU" >&2; exit 2; }
[ -f "$REF_SO" ] || [ "$DRY_RUN" = "1" ] || { echo "[FATAL] 缺 NEMU ref .so：$REF_SO" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "[FATAL] 缺清单：$MANIFEST" >&2; exit 2; }

RUN_ID="$(date '+%Y%m%dT%H%M%S')"
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
OUT_DIR="$CORE_DIR/results/difftest/extra"
CASES_DIR="$OUT_DIR/cases"
LOG="$OUT_DIR/94-extra-$RUN_ID.log"
JSON="$OUT_DIR/94-extra-$RUN_ID.json"
CASES_TSV="$OUT_DIR/94-extra-$RUN_ID.cases.tsv"
mkdir -p "$OUT_DIR" "$CASES_DIR"
: >"$CASES_TSV"

CRITERIA=()
add_criterion() { # name expected actual status
  CRITERIA+=("    {\"name\": \"$1\", \"expected\": \"$2\", \"actual\": \"$3\", \"status\": \"$4\"}")
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# 用例类是否本模式选中（--only 支持 cid 精确或 cls 通配）
selected() { # cid cls
  [ -z "$ONLY" ] && return 0
  local pat
  IFS=',' read -ra _pats <<<"$ONLY"
  for pat in "${_pats[@]}"; do
    [ "$1" = "$pat" ] && return 0
    [ "$2" = "$pat" ] && return 0
    case "$1" in $pat) return 0 ;; esac
  done
  return 1
}

selfcheck_pattern() { # cls cid
  case "$1" in
    vdot-base|vdot-ov|vdot-pl) echo "CASE $2: MATCH" ;;
    vdot-rand10k)              echo 'RAND10K verdict=ALL_OK groups=10000 mism=0 model_bad=0 ab_bad=0' ;;
    g0)                        echo "CASE $2: MISMATCH" ;;
    *)                         echo "" ;;
  esac
}
is_negative() { [ "$1" = "negative" ]; }
is_g0()       { [ "$1" = "g0" ]; }

# 先数一遍选中行（用于 cases_all_ran 与单例 timeout 收紧）
SELECTED=0
while IFS=$'\t' read -r cid cls img extra || [ -n "${cid:-}" ]; do
  case "${cid:-}" in ''|'#'*) continue ;; esac
  selected "$cid" "${cls:-}" || continue
  SELECTED=$((SELECTED + 1))
  [ "$LIMIT" -gt 0 ] && [ "$SELECTED" -ge "$LIMIT" ] && break
done <"$MANIFEST"
[ "$SELECTED" -gt 0 ] || { echo "[FATAL] --only=$ONLY 没有选中任何行" >&2; exit 3; }

{
  echo "===== job=${SLURM_JOB_ID:-dry-run} host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} $(date '+%F %T') ====="
  echo "emu=$EMU emu_md5=$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
  echo "ref_so=$REF_SO ref_md5=$(md5sum "$REF_SO" 2>/dev/null | cut -d' ' -f1)"
  echo "manifest=$MANIFEST sha256=$(sha256sum "$MANIFEST" | cut -d' ' -f1) selected=$SELECTED only=${ONLY:-<all>} limit=$LIMIT"
  # 措辞约束：只报主清单**现状**，不声称「未改动 = 冻结」
  echo "manifest_main sha256=$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1) rows=$(awk '!/^#/ && NF>=3' "$CORE_DIR/test/manifest.tsv" 2>/dev/null | wc -l)（远端主清单现状；本脚本不写入它）"
  echo "versions: xiangshan=$(git -C "$CORE_DIR/src/XiangShan" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$CORE_DIR/src/XiangShan/yunsuan" rev-parse --short HEAD 2>/dev/null) nemu=$(git -C "$CORE_DIR/src/NEMU" rev-parse --short HEAD 2>/dev/null)"
} | tee -a "$LOG"

# ---- 全局前置判据（与 20-run-difftest.sh 同口径）----
NM_HITS="$(nm -a "$REF_SO" 2>/dev/null | grep -cw exec_vdot || true)"
HDR="$(find "$CORE_DIR/src/XiangShan/build" -name 'difftest-state.h' -print -quit 2>/dev/null || true)"
VEC_OK=0
[ -n "$HDR" ] && grep -q 'CONFIG_DIFFTEST_ARCHVECREGSTATE' "$HDR" 2>/dev/null && VEC_OK=1
echo "nm_exec_vdot_hits=${NM_HITS:-0} difftest_state=$HDR vec_reg_compare=$VEC_OK" | tee -a "$LOG"

# ---- 金模型对拍（期望值来源复核；先跑，跑不动就记未运行）----
XCHECK_LINE="未运行（--skip-crosscheck）"
XCHECK_ST="未运行"
if [ "$SKIP_XCHECK" = "0" ]; then
  if [ -f "$CROSSCHECK" ]; then
    PY3=/public/software/apps/python/3.8.13/bin/python3
    [ -x "$PY3" ] || PY3="$(command -v python3 || true)"
    if [ -n "$PY3" ]; then
      # EXTRA_MANIFEST 让对拍脚本按**本次实际清单**校验行序（远端清单可能带绝对路径）
      XO="$(EXTRA_MANIFEST="$MANIFEST" "$PY3" -I "$CROSSCHECK" --quiet 2>&1)"; XR=$?
      XCHECK_LINE="$(printf '%s' "$XO" | grep -E 'EXTRA_CROSSCHECK verdict=' | tail -1)"
      printf '%s\n' "$XO" | tee -a "$LOG"
      [ "$XR" -eq 0 ] && XCHECK_ST="达标" || XCHECK_ST="未达标"
    else
      XCHECK_LINE="未运行（找不到 python3）"
    fi
  else
    XCHECK_LINE="未运行（缺 $CROSSCHECK）"
  fi
fi
echo "golden_crosscheck=$XCHECK_ST :: $XCHECK_LINE" | tee -a "$LOG"

# ---- 逐个用例 ----
TOTAL=0; PASS=0; NOTRUN=0; EXECUTED=0; REGBAD=0; SELFCHK_REQ=0; SELFCHK_OK=0
G0_REQ=0; G0_CAUGHT=0; NEG_REQ=0; NEG_OK=0
JOB_LEFT=""
if [ -n "${SLURM_JOB_END_TIME:-}" ]; then
  case "$SLURM_JOB_END_TIME" in
    *[!0-9]*) log "[WARN] SLURM_JOB_END_TIME=$SLURM_JOB_END_TIME 不是 epoch，跳过单例 timeout 收紧" ;;
    *) JOB_LEFT=$(( SLURM_JOB_END_TIME - $(date +%s) )) ;;
  esac
fi

while IFS=$'\t' read -r cid cls img extra || [ -n "${cid:-}" ]; do
  case "${cid:-}" in ''|'#'*) continue ;; esac
  selected "$cid" "${cls:-}" || continue
  [ "$LIMIT" -gt 0 ] && [ "$TOTAL" -ge "$LIMIT" ] && break
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$img" ]; then
    log "  [未运行] $cid：镜像不存在 $img"
    NOTRUN=$((NOTRUN + 1))
    printf '%s\t%s\t%s\t0\t0\t0\t\n' "$cid" "$cls" "未运行(缺镜像)" >>"$CASES_TSV"
    continue
  fi
  EXECUTED=$((EXECUTED + 1))
  clog="$CASES_DIR/${cid}.${RUN_ID}.log"
  # 单例 timeout：
  #   普通定向用例 = min(TIMEOUT_S, 剩余时间/剩余用例数)；
  #   随机 10000 组 = min(RAND_TIMEOUT_S, 剩余时间 - 60s 余量)。
  #   **不能**对随机类也除以「剩余用例数」：smoke 轮实测它单例就要 >900 s，
  #   按均分口径会被压到几十秒，必然 rc=124（作业 127026020 的实证）。
  if [ "$cls" = "vdot-rand10k" ]; then
    CTS="$RAND_TIMEOUT_S"
    if [ -n "$JOB_LEFT" ] && [ "$JOB_LEFT" -gt 60 ]; then
      [ $((JOB_LEFT - 60)) -lt "$CTS" ] && CTS=$((JOB_LEFT - 60))
    fi
  else
    CTS="$TIMEOUT_S"
    if [ -n "$JOB_LEFT" ] && [ "$JOB_LEFT" -gt 0 ]; then
      rem_left=$((SELECTED - EXECUTED + 1))
      share=$((JOB_LEFT / (rem_left > 0 ? rem_left : 1)))
      [ "$share" -lt "$CTS" ] && CTS="$share"
    fi
  fi
  [ "$CTS" -lt 1 ] && CTS=1
  rc=0
  if [ "$DRY_RUN" = "1" ]; then
    log "  [dry-run] timeout $CTS $EMU --diff $REF_SO -i $img --max-instr=$MAX_INSTR ${extra:-}"
    : >"$clog"
  else
    # shellcheck disable=SC2086
    timeout "$CTS" "$EMU" --diff "$REF_SO" -i "$img" --max-instr="$MAX_INSTR" ${extra:-} >"$clog" 2>&1 || rc=$?
  fi
  good="$(grep -ac 'HIT GOOD TRAP' "$clog" 2>/dev/null || true)"
  abort="$(grep -ac 'ABORT' "$clog" 2>/dev/null || true)"
  bad="$(grep -ac 'HIT BAD TRAP' "$clog" 2>/dev/null || true)"
  regbad="$(grep -ac 'is configured with different states than DUT' "$clog" 2>/dev/null || true)"
  [ "${regbad:-0}" -gt 0 ] && REGBAD=$((REGBAD + 1))

  if is_negative "$cls"; then
    crit="$(grep -ac 'HIT CRITICAL ERROR' "$clog" 2>/dev/null || true)"
    mism="$(grep -acE 'diff REF|Different operands' "$clog" 2>/dev/null || true)"
    sent="$(grep -ac '未如期陷入非法指令' "$clog" 2>/dev/null || true)"
    NEG_REQ=$((NEG_REQ + 1))
    if [ "${crit:-0}" -ge 1 ] && [ "${mism:-0}" = "0" ] && [ "${abort:-0}" = "0" ] && [ "${sent:-0}" = "0" ]; then
      st="通过"; NEG_OK=$((NEG_OK + 1))
    else
      st="失败(负例未如期陷入:CRIT=${crit:-0} MISMATCH=${mism:-0} SENTINEL=${sent:-0} ABORT=${abort:-0})"
    fi
  elif is_g0 "$cls"; then
    gm="$(grep -acF "CASE ${cid}: MISMATCH" "$clog" 2>/dev/null || true)"
    ge="$(grep -acF "CASE ${cid}: MATCH" "$clog" 2>/dev/null || true)"
    G0_REQ=$((G0_REQ + 1))
    if [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" = "0" ] && [ "$gm" -ge 1 ] && [ "$ge" = "0" ]; then
      st="通过"; G0_CAUGHT=$((G0_CAUGHT + 1))
    else
      st="失败(空绿防护失效:GOOD=${good:-0} MISMATCH=${gm:-0} MATCH=${ge:-0} ABORT=${abort:-0})"
    fi
  else
    vpat="$(selfcheck_pattern "$cls" "$cid")"
    vhit=1
    if [ -n "$vpat" ]; then
      SELFCHK_REQ=$((SELFCHK_REQ + 1))
      vp_hit="$(grep -acE "$vpat" "$clog" 2>/dev/null || true)"
      [ "${vp_hit:-0}" -ge 1 ] || vhit=0
    fi
    if [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" -eq 0 ] && [ "${bad:-0}" -eq 0 ] && [ "${vhit:-0}" = "1" ]; then
      st="通过"
      [ -n "$vpat" ] && SELFCHK_OK=$((SELFCHK_OK + 1))
    elif [ "${good:-0}" -ge 1 ] && [ "${abort:-0}" = "0" ] && [ -n "$vpat" ] && [ "${vhit:-0}" = "0" ]; then
      st="失败(自检未过:GOOD TRAP 但未命中 /$vpat/)"
    else
      st="失败"
    fi
  fi
  [ "$st" = "通过" ] && PASS=$((PASS + 1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$cid" "$cls" "$st" "${good:-0}" "${abort:-0}" "${bad:-0}" "$clog" >>"$CASES_TSV"
  log "  case $cid [$cls] -> $st (GOOD=${good:-0} ABORT=${abort:-0} BAD=${bad:-0} rc=$rc)"
  [ -n "$JOB_LEFT" ] && [ "$JOB_LEFT" -gt 0 ] && JOB_LEFT=$((JOB_LEFT - CTS))
done <"$MANIFEST"

# ---- 判据聚合 ----
if [ "$TOTAL" -eq 0 ]; then
  add_criterion "cases_ran" "至少运行 1 个用例" "0 个" "未运行"
elif [ "$NOTRUN" -eq 0 ]; then
  add_criterion "cases_all_ran" "选中用例全部执行" "$EXECUTED/$SELECTED" "达标"
else
  add_criterion "cases_all_ran" "选中用例全部执行" "$EXECUTED/$SELECTED（缺镜像 $NOTRUN 个）" "未运行"
fi

if [ "$EXECUTED" -gt 0 ] && [ "$PASS" -eq "$TOTAL" ] && [ "$NOTRUN" -eq 0 ]; then
  add_criterion "cases_pass" "全部选中用例通过" "$PASS/$TOTAL" "达标"
elif [ "$NOTRUN" -gt 0 ] && [ "$PASS" -eq "$EXECUTED" ]; then
  # 已执行的都过了，但有缺镜像：按全仓规则记「未运行」，不记通过
  add_criterion "cases_pass" "全部选中用例通过" "$PASS/$TOTAL（$NOTRUN 个未运行）" "未运行"
else
  add_criterion "cases_pass" "全部选中用例通过" "$PASS/$TOTAL，失败 $((EXECUTED - PASS))" "未达标"
fi

[ "$REGBAD" -eq 0 ] && add_criterion "reg_size_match" "无 different-states 串" "0 次（1400 B 口径）" "达标" \
                     || add_criterion "reg_size_match" "无 different-states 串" "$REGBAD 个用例命中" "未达标"
[ "${NM_HITS:-0}" -ge 1 ] && add_criterion "nm_exec_vdot" "nm 命中 exec_vdot >=1" "命中 $NM_HITS 行" "达标" \
                          || add_criterion "nm_exec_vdot" "nm 命中 exec_vdot >=1" "0 行" "未达标"
[ "$VEC_OK" = "1" ] && add_criterion "vec_reg_compare" "difftest-state.h 含 ARCHVECREGSTATE" "$HDR" "达标" \
                    || add_criterion "vec_reg_compare" "difftest-state.h 含 ARCHVECREGSTATE" "${HDR:-未找到}" "未达标"

if [ "$G0_REQ" -gt 0 ]; then
  if [ "$SELFCHK_OK" -eq "$SELFCHK_REQ" ] && [ "$G0_CAUGHT" -eq "$G0_REQ" ]; then
    add_criterion "no_empty_green" "正例自检串全命中且 G0 全捕获" \
      "自检串 $SELFCHK_OK/$SELFCHK_REQ；G0 捕获 $G0_CAUGHT/$G0_REQ" "达标"
  else
    add_criterion "no_empty_green" "正例自检串全命中且 G0 全捕获" \
      "自检串 $SELFCHK_OK/$SELFCHK_REQ；G0 捕获 $G0_CAUGHT/$G0_REQ" "未达标"
  fi
else
  add_criterion "no_empty_green" "正例自检串全命中且 G0 全捕获" "本清单无 g0 行" "未运行"
fi
if [ "$NEG_REQ" -gt 0 ]; then
  [ "$NEG_OK" -eq "$NEG_REQ" ] && add_criterion "negatives_illegal" "负例双侧一致陷入非法" "$NEG_OK/$NEG_REQ" "达标" \
                               || add_criterion "negatives_illegal" "负例双侧一致陷入非法" "$NEG_OK/$NEG_REQ" "未达标"
else
  add_criterion "negatives_illegal" "负例双侧一致陷入非法" "本次无负例" "未运行"
fi
add_criterion "golden_crosscheck" "extra_crosscheck.py == MATCH" "$XCHECK_LINE" "$XCHECK_ST"

# ---- 写 JSON ----
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
ST="失败"; UNMET=0; UNRUN=0
for c in "${CRITERIA[@]}"; do
  case "$c" in *'"未达标"'*) UNMET=1 ;; esac
  case "$c" in *'"未运行"'*) UNRUN=1 ;; esac
done
[ "$UNMET" -eq 0 ] && [ "$UNRUN" -eq 0 ] && ST="通过"
[ "$UNMET" -eq 0 ] && [ "$UNRUN" -eq 1 ] && ST="未运行"

{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "%s",\n' "$ITEM"
  printf '  "script": "scripts/%s",\n' "$SCRIPT_NAME"
  printf '  "status": "%s",\n' "$ST"
  printf '  "mode": "extra",\n'
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-login-node}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "host": "%s",\n' "$(hostname)"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "machine_hours_planned": 2.5,\n'
  printf '  "manifest": {"path": "%s", "sha256": "%s", "rows": "%s"},\n' \
    "$(jesc "$MANIFEST")" "$(sha256sum "$MANIFEST" | cut -d' ' -f1)" "$SELECTED"
  printf '  "manifest_main_sha256": "%s",\n' "$(sha256sum "$CORE_DIR/test/manifest.tsv" 2>/dev/null | cut -d' ' -f1)"
  printf '  "counters": {"selected": %s, "executed": %s, "pass": %s, "not_run": %s, "reg_size_bad": %s,\n' \
    "$SELECTED" "$EXECUTED" "$PASS" "$NOTRUN" "$REGBAD"
  printf '               "selfcheck_req": %s, "selfcheck_ok": %s, "g0_req": %s, "g0_caught": %s,\n' \
    "$SELFCHK_REQ" "$SELFCHK_OK" "$G0_REQ" "$G0_CAUGHT"
  printf '               "neg_req": %s, "neg_ok": %s},\n' "$NEG_REQ" "$NEG_OK"
  printf '  "criteria": [\n'
  n=${#CRITERIA[@]}
  for ((i = 0; i < n; i++)); do
    printf '%s' "${CRITERIA[$i]}"
    [ "$i" -lt $((n - 1)) ] && printf ',\n' || printf '\n'
  done
  printf '  ],\n'
  printf '  "artifacts": ["%s", "%s"]\n' "$(jesc "$LOG")" "$(jesc "$CASES_TSV")"
  printf '}\n'
} >"$JSON.tmp"
mv "$JSON.tmp" "$JSON"
if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON" 2>/dev/null; then
  log "[ERROR] 结果 JSON 不可解析：$JSON"
fi

# ---- 机时记账（一次作业只记一次，与 20-run-difftest.sh 的 trap 同口径）----
for bs in "$CORE_DIR/core-package/scripts/90-budget-log.sh" "$CORE_DIR/scripts/90-budget-log.sh"; do
  if [ -x "$bs" ] && [ -n "${SLURM_JOB_ID:-}" ]; then
    bash "$bs" auto --item "$ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || log "[WARN] 记账失败：$bs"
    break
  fi
done

log "判据：$ST（$PASS/$TOTAL；未运行 $NOTRUN）"
log "结果 JSON：$JSON"
case "$ST" in
  通过) exit 0 ;;
  未运行) exit 2 ;;
  *) exit 1 ;;
esac
