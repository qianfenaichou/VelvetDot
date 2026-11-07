#!/usr/bin/env bash
# =============================================================================
# 99-run-perf-repeat.sh — 四个 perf 用例的跨重复中位数/极差 + 预登记加速比口径
#
# 为什么需要这份：
#   stage3/3.3/report.md §1/§4.3 的加速比只有「每指令归一 1.33×」一个口径，但它的
#   分子 L_vdot 与分母 L_base_chain 分别来自不同的单次作业。本脚本对四个 perf 用例
#   做 4 次**独立 emu 进程**重复（每次都重新启动 emu、重新装载镜像），把跨重复的
#   中位数与极差落成机读 JSON；加速比口径在脚本与 perf-repeat.md 中**预登记**，
#   不因本轮结果改口径。
#
# 解析口径（与 20-run-difftest.sh:311-327 同一套）：
#   每个用例的 `^VDOT_METRIC <name> <value>` 行 → metrics；
#   `PERF <tag> : ...` / `PERF <tag>: ...` 汇总行原样保留 → raw_perf_lines（供复核）。
#   自检串沿用 20-run-difftest.sh:199-226：perf_vdot → PERF_VDOT verdict=ALL_OK；
#   perf_base → PERF_BASE verdict=ALL_OK；perf_vadd → PERF_VADD verdict=ALL_OK；
#   perf_vmacc → PERF_VMACC verdict=ALL_OK。
#
# 预登记加速比口径（在任何本轮数据产生前写定）：
#   speedup_per_instr = (L_base_chain / 3) / L_vdot
#   分母 = L_base_chain/3 = 16/3 ≈ 5.333 cyc/指令。L_base_chain=16 来自作业
#   `126762127`（full 尺度、8×2000=16000 合并样本中位数，日志
#   results/difftest/b3/91-b3-20261104T115624.log 的 `VDOT_METRIC L_base_chain 16`；
#   链 = vwmul.vv→vwadd.vx→vredsum.vs 三条串行指令，配置外提、循环内零 vsetvli）。
#   分子 = 本轮 L_vdot 的跨重复中位数。
#   预期 5.333/4 ≈ 1.33×（脚本整数打印口径 16/3→5，5/4=1.25×，同口径的保守舍入）。
#   **不采用**「内核 16/7≈2.29×」作为本报告的官方加速比口径：report §4.5 已明写
#   该数是「内核级动态拍数对比，不是延迟加速比、不是官方口径」，且它含配置/装载/读回，
#   不能回答官方 docx/02:61,66 要的 latency 对比。
#   若本轮 L_vdot 中位数不是 4，则按实测重算并如实报告，不把 1.33× 写死。
#
# 机时分类：P3-full（同 91/93/98 的单例 perf 作业先例）。
#
# 用法（必须经 Slurm，禁止登录节点跑 emu）：
#   sbatch -p kshcnormal -N 1 -n 8 --time=01:00:00 \
#     core-package/scripts/99-run-perf-repeat.sh \
#     --emu "$HOME/core/src/XiangShan/build/emu" \
#     --cases "$HOME/core/test/bin" \
#     --repeats 4 \
#     --out "$HOME/core/results/difftest/perf-repeat/99-perf-repeat-<runid>.json"
#   可选：--max-instr N（默认 200000000）--timeout-per-case SEC（默认 900）
#         --base-chain-cyc 16 --base-chain-instr 3（预登记分母，默认即上值）
# 产物：<out>（JSON）、<out 去 .json>.log（作业日志）、
#       <out 去 .json>.cases/<case>.r<k>.<runid>.log（16 份 emu 原始输出）、
#       <out 去 .json>.summary.tsv（中位数/极差表）
# 退出码：0 达标 / 1 未达标 / 2 前置缺失 / 3 用法或环境错误
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 8
#SBATCH --time=01:00:00
#SBATCH -J vdot_perf_rep

set -uo pipefail
export LC_ALL=C

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P3-full"
readonly PURPOSE="四 perf 用例 4 次重复：跨重复中位数/极差 + 预登记每指令加速比口径"

EMU="${EMU:-$HOME/core/src/XiangShan/build/emu}"
CASES_DIR="${CASES_DIR:-$HOME/core/test/bin}"
REPEATS="${REPEATS:-4}"
OUT="${OUT:-}"
MAX_INSTR="${MAX_INSTR:-200000000}"
CASE_TIMEOUT_S="${CASE_TIMEOUT_S:-900}"
BASE_CHAIN_CYC="${BASE_CHAIN_CYC:-16}"
BASE_CHAIN_INSTR="${BASE_CHAIN_INSTR:-3}"
CASES=(perf_vdot perf_base perf_vadd perf_vmacc)

usage() {
  sed -n '9,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --emu)               EMU="${2:?--emu 需要参数}"; shift 2 ;;
    --cases)             CASES_DIR="${2:?--cases 需要参数}"; shift 2 ;;
    --repeats)           REPEATS="${2:?--repeats 需要参数}"; shift 2 ;;
    --out)               OUT="${2:?--out 需要参数}"; shift 2 ;;
    --max-instr)         MAX_INSTR="${2:?--max-instr 需要参数}"; shift 2 ;;
    --timeout-per-case)  CASE_TIMEOUT_S="${2:?--timeout-per-case 需要参数}"; shift 2 ;;
    --base-chain-cyc)    BASE_CHAIN_CYC="${2:?--base-chain-cyc 需要参数}"; shift 2 ;;
    --base-chain-instr)  BASE_CHAIN_INSTR="${2:?--base-chain-instr 需要参数}"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
  esac
done

# 与其它 perf 单例脚本同一约定：emu 读 rdcycle，必须 --no-diff；重计算禁止登录节点。
if [ -z "${SLURM_JOB_ID:-}" ]; then
  echo "[FATAL] 禁止在登录节点跑 emu。请提交：" >&2
  echo "  sbatch -p kshcnormal -N 1 -n 8 --time=01:00:00 $SCRIPT_NAME --emu ... --cases ... --repeats 4 --out ..." >&2
  exit 3
fi

case "$REPEATS" in ''|*[!0-9]*) echo "[FATAL] --repeats 必须是正整数：$REPEATS" >&2; exit 3 ;; esac
[ "$REPEATS" -ge 1 ] || { echo "[FATAL] --repeats 必须 >= 1" >&2; exit 3; }
case "$BASE_CHAIN_CYC" in ''|*[!0-9]*) echo "[FATAL] --base-chain-cyc 必须是正整数：$BASE_CHAIN_CYC" >&2; exit 3 ;; esac
case "$BASE_CHAIN_INSTR" in ''|*[!0-9]*) echo "[FATAL] --base-chain-instr 必须是正整数：$BASE_CHAIN_INSTR" >&2; exit 3 ;; esac
[ "$BASE_CHAIN_INSTR" -ge 1 ] || { echo "[FATAL] --base-chain-instr 必须 >= 1" >&2; exit 3; }

# 计算节点默认环境缺 gcc-13.3.0 运行库（emu 报 GLIBCXX_3.4.32 not found）且 python3
# 不在 PATH；~/tools/env.sh 同时补 LD_LIBRARY_PATH 与 python3 路径（同 93/98 单例脚本）。
if [ -r "$HOME/tools/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/tools/env.sh"
  hash -r
else
  echo "[WARN] 缺 $HOME/tools/env.sh：emu 可能因 GLIBCXX 缺失无法启动" >&2
fi

[ -x "$EMU" ] || { echo "[FATAL] 缺 emu 可执行文件：$EMU" >&2; exit 2; }
[ -d "$CASES_DIR" ] || { echo "[FATAL] 缺用例目录：$CASES_DIR" >&2; exit 2; }
for c in "${CASES[@]}"; do
  [ -f "$CASES_DIR/$c.bin" ] || { echo "[FATAL] 缺镜像：$CASES_DIR/$c.bin" >&2; exit 2; }
done

if [ -z "$OUT" ]; then
  OUT="$HOME/core/results/difftest/perf-repeat/99-perf-repeat-$(date '+%Y%m%dT%H%M%S').json"
fi
case "$OUT" in
  *.json) ;;
  *) echo "[FATAL] --out 必须是 .json 路径：$OUT" >&2; exit 3 ;;
esac
OUT_DIR="$(dirname "$OUT")"
OUT_STEM="${OUT%.json}"
LOG="$OUT_STEM.log"
CASES_LOG_DIR="$OUT_STEM.cases"
mkdir -p "$OUT_DIR" "$CASES_LOG_DIR"

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
RUNS_TSV="$OUT_DIR/.99-perf-repeat.runs.$RUN_ID.tsv"
METRICS_TSV="$OUT_DIR/.99-perf-repeat.metrics.$RUN_ID.tsv"
PERF_TSV="$OUT_DIR/.99-perf-repeat.perf.$RUN_ID.tsv"
: >"$RUNS_TSV"; : >"$METRICS_TSV"; : >"$PERF_TSV"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

EMU_MD5="$(md5sum "$EMU" 2>/dev/null | cut -d' ' -f1)"
SRC="$HOME/core/src/XiangShan"

log "===== $SCRIPT_NAME job=${SLURM_JOB_ID:-NA} host=$(hostname) partition=${SLURM_JOB_PARTITION:-NA} ====="
log "emu=$EMU emu_md5=${EMU_MD5:-NA} max_instr=$MAX_INSTR timeout_per_case=${CASE_TIMEOUT_S}s"
log "repeats=$REPEATS cases=${CASES[*]} cases_dir=$CASES_DIR out=$OUT"
log "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo NA) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null || echo NA)"
log "caliber: speedup_per_instr=(L_base_chain/${BASE_CHAIN_INSTR})/L_vdot; L_base_chain=${BASE_CHAIN_CYC}（预登记，来源作业 126762127）"

# 镜像指纹：写入 JSON，保证「本轮用的就是这四个 bin」可机械核对。
IMG_MD5_TSV="$OUT_DIR/.99-perf-repeat.imgmd5.$RUN_ID.tsv"
: >"$IMG_MD5_TSV"
for c in "${CASES[@]}"; do
  printf '%s\t%s\n' "$c" "$(md5sum "$CASES_DIR/$c.bin" | cut -d' ' -f1)" >>"$IMG_MD5_TSV"
done
log "image md5: $(tr '\n' ' ' <"$IMG_MD5_TSV")"

for r in $(seq 1 "$REPEATS"); do
  for c in "${CASES[@]}"; do
    clog="$CASES_LOG_DIR/$c.r$r.$RUN_ID.log"
    rc=0
    t0=$SECONDS
    timeout "$CASE_TIMEOUT_S" "$EMU" --no-diff -i "$CASES_DIR/$c.bin" --max-instr="$MAX_INSTR" \
      >"$clog" 2>&1 || rc=$?
    elapsed=$((SECONDS - t0))

    good="$(grep -ac 'HIT GOOD TRAP' "$clog" 2>/dev/null || true)"
    abort="$(grep -ac 'ABORT' "$clog" 2>/dev/null || true)"
    bad="$(grep -ac 'HIT BAD TRAP' "$clog" 2>/dev/null || true)"
    case "$c" in
      perf_vdot)  vpat='PERF_VDOT verdict=ALL_OK' ;;
      perf_base)  vpat='PERF_BASE verdict=ALL_OK' ;;
      perf_vadd)  vpat='PERF_VADD verdict=ALL_OK' ;;
      perf_vmacc) vpat='PERF_VMACC verdict=ALL_OK' ;;
      *)          vpat='' ;;
    esac
    vok=0
    [ -n "$vpat" ] && vok="$(grep -acE "$vpat" "$clog" 2>/dev/null || true)"
    [ "${vok:-0}" -ge 1 ] && vok=1 || vok=0

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$r" "$c" "$rc" "${good:-0}" "${abort:-0}" "${bad:-0}" "$vok" "$clog" "$elapsed" >>"$RUNS_TSV"

    n_metric=0
    while read -r mname mval _; do
      [ -n "${mname:-}" ] || continue
      case "$mval" in ''|*[!0-9]*) continue ;; esac
      printf '%s\t%s\t%s\t%s\n' "$r" "$c" "$mname" "$mval" >>"$METRICS_TSV"
      n_metric=$((n_metric + 1))
    done < <(grep -aE '^VDOT_METRIC[[:space:]]+' "$clog" 2>/dev/null | sed 's/^VDOT_METRIC[[:space:]][[:space:]]*//' | tr -d '\r' || true)

    n_perf=0
    while IFS= read -r pline; do
      [ -n "${pline:-}" ] || continue
      ptag="$(printf '%s\n' "$pline" | sed -E 's/^PERF[_ ]+([A-Za-z0-9_]+).*/\1/')"
      printf '%s\t%s\t%s\t%s\n' "$r" "$c" "$ptag" "$pline" >>"$PERF_TSV"
      n_perf=$((n_perf + 1))
    done < <(grep -aE '^(PERF|PERF_[A-Z]+) ' "$clog" 2>/dev/null | tr -d '\r' || true)

    log "repeat=$r case=$c rc=$rc good=$good abort=$abort bad=$bad verdict_ok=$vok metrics=$n_metric perf_lines=$n_perf elapsed=${elapsed}s log=$clog"
  done
done

# JSON 组装 + 中位数/极差 + 预登记加速比（python3 只做算术与序列化；原始值全部来自 TSV）。
export PR_OUT="$OUT" PR_RUN_ID="$RUN_ID" PR_STARTED_AT="$STARTED_AT" \
       PR_EMU="$EMU" PR_EMU_MD5="${EMU_MD5:-NA}" PR_CASES_DIR="$CASES_DIR" \
       PR_REPEATS="$REPEATS" PR_MAX_INSTR="$MAX_INSTR" PR_BASE_CHAIN_CYC="$BASE_CHAIN_CYC" \
       PR_BASE_CHAIN_INSTR="$BASE_CHAIN_INSTR" PR_RUNS_TSV="$RUNS_TSV" \
       PR_METRICS_TSV="$METRICS_TSV" PR_PERF_TSV="$PERF_TSV" PR_IMGMD5_TSV="$IMG_MD5_TSV" \
       PR_LOG="$LOG" PR_CASES_LOG_DIR="$CASES_LOG_DIR" PR_JOB_ID="${SLURM_JOB_ID:-}" \
       PR_HOST="$(hostname)" PR_PARTITION="${SLURM_JOB_PARTITION:-slurm}" \
       PR_XS_HEAD="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo NA)" \
       PR_YS_HEAD="$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null || echo NA)"

python3 - <<'PY'
import json, os, sys

OUT = os.environ["PR_OUT"]
RUN_ID = os.environ["PR_RUN_ID"]
REPEATS = int(os.environ["PR_REPEATS"])
BASE_CYC = int(os.environ["PR_BASE_CHAIN_CYC"])
BASE_INSTR = int(os.environ["PR_BASE_CHAIN_INSTR"])
CASES = ["perf_vdot", "perf_base", "perf_vadd", "perf_vmacc"]
EXPECTED = {
    "perf_vdot":  ["L_vdot", "L_vdot_mean", "L_vdot_loop", "T_steady", "T_kernel"],
    "perf_base":  ["B1", "B2"],
    "perf_vadd":  ["L_vadd", "L_vadd_mean", "L_vadd_loop"],
    "perf_vmacc": ["L_vmacc", "L_vmacc_mean", "L_vmacc_loop"],
}


def read_tsv(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            rows.append(line.split("\t"))
    return rows


def num(x):
    """整数就输出 int，否则保留 6 位小数。"""
    if isinstance(x, float) and x.is_integer():
        return int(x)
    if isinstance(x, float):
        return round(x, 6)
    return x


runs = []
for row in read_tsv(os.environ["PR_RUNS_TSV"]):
    r, case, rc, good, abort, bad, vok, clog, elapsed = row
    runs.append({
        "repeat": int(r), "case": case, "rc": int(rc),
        "good_trap": int(good), "abort": int(abort), "bad_trap": int(bad),
        "verdict_all_ok": bool(int(vok)), "elapsed_s": int(elapsed), "log": clog,
    })

metrics = {}          # (repeat, case) -> {name: int}
metric_order = {}     # case -> [names in log order]
for row in read_tsv(os.environ["PR_METRICS_TSV"]):
    r, case, name, val = row[0], row[1], row[2], row[3]
    key = (int(r), case)
    metrics.setdefault(key, {})[name] = int(val)
    metric_order.setdefault(case, [])
    if name not in metric_order[case]:
        metric_order[case].append(name)

perf_lines = {}       # (repeat, case) -> [{"tag","line"}]
for row in read_tsv(os.environ["PR_PERF_TSV"]):
    r, case, tag, line = row[0], row[1], row[2], "\t".join(row[3:])
    perf_lines.setdefault((int(r), case), []).append({"tag": tag, "line": line})

imgmd5 = {}
for row in read_tsv(os.environ["PR_IMGMD5_TSV"]):
    imgmd5[row[0]] = row[1]

# 跨重复：同一 case 的同一 metric 取中位数与极差（偶数次取中间两数均值）。
summary = {}
for case in CASES:
    summary[case] = {}
    names = list(metric_order.get(case, []))
    for name in names:
        vals = [metrics[(r, case)][name] for r in range(1, REPEATS + 1)
                if name in metrics.get((r, case), {})]
        if not vals:
            continue
        sv = sorted(vals)
        n = len(sv)
        med = sv[n // 2] if n % 2 else (sv[n // 2 - 1] + sv[n // 2]) / 2.0
        summary[case][name] = {
            "values": vals, "n": n, "median": num(med),
            "min": sv[0], "max": sv[-1], "range": sv[-1] - sv[0],
        }

# 预登记加速比：每重复算一次 (L_base_chain/3)/L_vdot，再跨重复取中位数与极差。
denom = BASE_CYC / float(BASE_INSTR)
denom_int = BASE_CYC // BASE_INSTR
speedups, speed_ints, lv_list = [], [], []
for r in range(1, REPEATS + 1):
    lv = metrics.get((r, "perf_vdot"), {}).get("L_vdot")
    if lv:
        lv_list.append(lv)
        speedups.append(denom / lv)
        speed_ints.append(denom_int / float(lv))

def med_range(vals):
    if not vals:
        return None, None, None
    sv = sorted(vals)
    n = len(sv)
    med = sv[n // 2] if n % 2 else (sv[n // 2 - 1] + sv[n // 2]) / 2.0
    return med, sv[0], sv[-1]

sp_med, sp_min, sp_max = med_range(speedups)
si_med, si_min, si_max = med_range(speed_ints)

# 判据：测量有效性 + 与报告 §1 的 L_vdot=4 是否一致（后者是结果核对，不是有效性前提）。
criteria = []

def add(name, expected, actual, ok, unrun=False):
    criteria.append({
        "name": name, "expected": expected, "actual": actual,
        "status": "未运行" if unrun else ("达标" if ok else "未达标"),
    })

add("repeat_count", "repeats >= 4", str(REPEATS), REPEATS >= 4)
add("runs_total", "%d 次 emu 运行（4 用例 × %d 重复）" % (4 * REPEATS, REPEATS),
    str(len(runs)), len(runs) == 4 * REPEATS)
add("emu_rc_zero", "全部 rc == 0", "%d/%d" % (sum(1 for x in runs if x["rc"] == 0), len(runs)),
    all(x["rc"] == 0 for x in runs) and len(runs) == 4 * REPEATS)
add("good_trap", "全部 HIT GOOD TRAP >= 1", "%d/%d" % (sum(1 for x in runs if x["good_trap"] >= 1), len(runs)),
    all(x["good_trap"] >= 1 for x in runs) and len(runs) == 4 * REPEATS)
add("no_abort", "全部 ABORT == 0", "%d 次越界" % sum(1 for x in runs if x["abort"] != 0),
    all(x["abort"] == 0 for x in runs) and len(runs) == 4 * REPEATS)
add("no_bad_trap", "全部 HIT BAD TRAP == 0", "%d 次越界" % sum(1 for x in runs if x["bad_trap"] != 0),
    all(x["bad_trap"] == 0 for x in runs) and len(runs) == 4 * REPEATS)
vok_n = sum(1 for x in runs if x["verdict_all_ok"])
add("verdict_all_ok", "每用例 %d/%d 重复命中各自 ALL_OK 汇总行" % (REPEATS, REPEATS),
    "%d/%d" % (vok_n, len(runs)), vok_n == 4 * REPEATS and len(runs) == 4 * REPEATS)
missing = []
for r in range(1, REPEATS + 1):
    for case in CASES:
        have = metrics.get((r, case), {})
        for name in EXPECTED[case]:
            if name not in have:
                missing.append("r%d/%s/%s" % (r, case, name))
add("metrics_complete", "每重复的每个用例都含预期 VDOT_METRIC", "缺 %d 项%s" % (
    len(missing), (": " + ",".join(missing)) if missing else ""), not missing)
lv_med = summary.get("perf_vdot", {}).get("L_vdot", {}).get("median")
add("l_vdot_matches_report", "L_vdot 跨重复中位数 == report §1 的 4", str(lv_med), lv_med == 4)

status = "通过"
if any(c["status"] == "未达标" for c in criteria):
    status = "失败"
elif any(c["status"] == "未运行" for c in criteria):
    status = "未运行"

doc_runs = []
for x in runs:
    key = (x["repeat"], x["case"])
    doc_runs.append({
        "repeat": x["repeat"], "case": x["case"], "rc": x["rc"],
        "good_trap": x["good_trap"], "abort": x["abort"], "bad_trap": x["bad_trap"],
        "verdict_all_ok": x["verdict_all_ok"], "elapsed_s": x["elapsed_s"],
        "img": os.path.join(os.environ["PR_CASES_DIR"], x["case"] + ".bin"),
        "img_md5": imgmd5.get(x["case"], ""),
        "metrics": metrics.get(key, {}),
        "raw_perf_lines": perf_lines.get(key, []),
        "log": x["log"],
    })

doc = {
    "schema": "vdot-perf-repeat/1",
    "script": "scripts/" + "99-run-perf-repeat.sh",
    "item": "P3-full",
    "status": status,
    "note": "四个 perf 用例各跑 repeats 次独立 emu 进程；metrics 来自 ^VDOT_METRIC 行（同 20-run-difftest.sh:311-327）；中位数为跨重复统计，不是用例内单次中位数。",
    "platform": os.environ["PR_PARTITION"],
    "slurm_job_id": os.environ["PR_JOB_ID"],
    "host": os.environ["PR_HOST"],
    "started_at": os.environ["PR_STARTED_AT"],
    "ended_at": __import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds"),
    "run_id": RUN_ID,
    "provenance": {
        "emu": os.environ["PR_EMU"], "emu_md5": os.environ["PR_EMU_MD5"],
        "cases_dir": os.environ["PR_CASES_DIR"], "img_md5": imgmd5,
        "max_instr": os.environ["PR_MAX_INSTR"],
        "versions": {"xiangshan": os.environ["PR_XS_HEAD"], "yunsuan": os.environ["PR_YS_HEAD"]},
    },
    "caliber": {
        "name": "per_instr_normalized_latency",
        "status": "预登记（本轮数据产生前写定）",
        "formula": "speedup = (L_base_chain / %d) / L_vdot" % BASE_INSTR,
        "denominator": {
            "L_base_chain_cyc": BASE_CYC,
            "chain_instr": BASE_INSTR,
            "per_instr_cyc": round(denom, 6),
            "source": "作业 126762127（full 尺度 8×2000=16000 合并样本中位数）；results/difftest/b3/91-b3-20261104T115624.log 的 VDOT_METRIC L_base_chain 16；链=vwmul.vv→vwadd.vx→vredsum.vs（3 条串行）",
        },
        "numerator": {"metric": "L_vdot", "cross_repeat_median": lv_med, "values": lv_list},
        "primary": {
            "definition": "(L_base_chain/3) / L_vdot",
            "per_repeat": [round(x, 6) for x in speedups],
            "median": num(sp_med), "min": num(sp_min), "max": num(sp_max),
            "range": num(sp_max - sp_min) if speedups else None,
        },
        "integer_print": {
            "definition": "print(L_base_chain/3) = %d; %d / L_vdot" % (denom_int, denom_int),
            "per_repeat": [round(x, 6) for x in speed_ints],
            "median": num(si_med), "min": num(si_min), "max": num(si_max),
            "range": num(si_max - si_min) if speed_ints else None,
        },
        "not_used": {
            "name": "kernel_16_over_7",
            "value": 2.285714,
            "reason": "report §4.5 明写该数为内核级动态拍数对比，不是延迟加速比、不是官方口径；且含配置/装载/读回，不能回答 docx/02:61,66 的 latency 对比。本轮不采用为官方加速比口径。",
        },
        "limitations": [
            "每指令归一：分母 L_base_chain/3 把 3 条串行指令的链延迟平摊到每条指令；原始 16/4=4.0× 是「3 指令链 vs 单指令」的跨口径比值，不写成 latency 加速比。",
            "分母 L_base_chain=16 来自另一作业 126762127（同一 VimacCfg、同 VL=8、同计数法、配置外提），不是本轮 16 次运行测得的；本轮只重测分子 L_vdot。",
            "L_vdot 的 4 次重复中位数仍是 emu 的 rdcycle 模型周期，不是硅片延迟；4 次的极差只说明本批进程间离散，不构成置信区间。",
            "官方 docx/02:61,66 只要求「用已有向量指令组合实现基线 + latency 加速比分析」，未规定条数/统计口径；L_base_chain 的 3 条链与 16/3 归一是本包内部自设口径。",
            "报告级 ALGORITHM §3.4 要求「同配置再跑 >=5 次取中位数」；本批是 4 次，未达到该条，属于补充证据而非替代。",
            "所有用例均以 --no-diff 运行（emu 读 rdcycle，与 NEMU 参照不一致）；功能正确性由各自的 PERF_* verdict 自检承担，不是 difftest。",
        ],
    },
    "criteria": criteria,
    "summary": summary,
    "runs": doc_runs,
    "artifacts": {
        "log": os.environ["PR_LOG"],
        "case_logs_dir": os.environ["PR_CASES_LOG_DIR"],
        "summary_tsv": OUT[:-5] + ".summary.tsv",
    },
}

with open(OUT + ".tmp", "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(OUT + ".tmp", OUT)

# 中位数/极差表（人读 + 机读）
with open(OUT[:-5] + ".summary.tsv", "w", encoding="utf-8") as f:
    f.write("case\tmetric\tn\tvalues\tmedian\tmin\tmax\trange\n")
    for case in CASES:
        for name, s in summary.get(case, {}).items():
            f.write("%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n" % (
                case, name, s["n"], ",".join(str(v) for v in s["values"]),
                s["median"], s["min"], s["max"], s["range"]))

print("[summary] 跨重复中位数/极差（values 按重复顺序）")
for case in CASES:
    for name, s in summary.get(case, {}).items():
        print("  %-10s %-14s values=%s median=%s range=%s" % (
            case, name, ",".join(str(v) for v in s["values"]), s["median"], s["range"]))
print("[speedup] formula=(L_base_chain/%d)/L_vdot; L_base_chain=%d; per_repeat=%s; median=%s range=%s" % (
    BASE_INSTR, BASE_CYC, [round(x, 6) for x in speedups], num(sp_med), num(sp_max - sp_min) if speedups else None))
print("[speedup] integer_print=%d/L_vdot; per_repeat=%s; median=%s" % (
    denom_int, [round(x, 6) for x in speed_ints], num(si_med)))
print("[status] %s" % status)
for c in criteria:
    print("  [%s] %s: %s (expected: %s)" % (c["status"], c["name"], c["actual"], c["expected"]))
PY

if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT" 2>/dev/null; then
  log "[ERROR] 结果 JSON 不可解析：$OUT"
  exit 1
fi

STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$OUT" 2>/dev/null || echo 失败)"
log "结果 JSON：$OUT"
log "汇总 TSV：${OUT%.json}.summary.tsv"
log "===== DONE status=$STATUS ====="

# 机时记账（与 93/98 同一约定；脚本缺失不失败）
if bs="$HOME/core/core-package/scripts/90-budget-log.sh"; then
  [ -x "$bs" ] && bash "$bs" auto --item "$ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 \
    || log "[WARN] 记账失败或脚本缺失"
fi

case "$STATUS" in
  通过) exit 0 ;;
  未运行) exit 2 ;;
  *) exit 1 ;;
esac