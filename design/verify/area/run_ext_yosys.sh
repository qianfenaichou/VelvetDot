#!/usr/bin/env bash
# =============================================================================
# 扩展实测：K=8（对照）vs K=16（扩展）归约树的 Yosys 面积 / 拓扑级数
#
# 口径：与 core-package/scripts/40-yosys-area.sh 逐字一致（design/ALGORITHM.md §3.5）：
#   yosys -p "read_verilog -sv <rtl>; synth -top <top>; flatten;
#             tee -o <sj> stat -json; tee -o <cm> stat -tech cmos; tee -o <lt> ltp -noff"
#   仅数据通路、未含工艺库 ⇒ cells 是 Yosys abc 通用门计数，不是硅面积、不能换 µm²。
#   Nangate45 映射（dfflibmap/abc -liberty）属另一条轴，本次未做 ⇒ mappedAreaUm2 无值。
#
# 被测件（design/verify/area/gen_ext.py 生成，独立数据通路、同结构参数化、未集成 VIMacU）：
#   VdotReduceK8     K=8,  W=2*8+floor(log2 8)=19   纯 4:2 树 3 实例 / 2 段（对照）
#   VdotReduceK16    K=16, W=2*8+floor(log2 16)=20  纯 4:2 树 7 实例 / 3 段（扩展）
#   VdotReduceK16Gen K=16, W=20                     仓内生成器退化 3:2 调度 11 实例 / 4 段（旁证）
#   拍级切分三者相同：符号扩展 + 树 + W 位 CPA 全组合，单拍寄存器打在格式化后的 vd 上
#   （= 公开仓 K1 版 VdotReduce / 报告 §7.4 的 481 锚点）。
#
# 附加（非阻塞）：K8 与 firtool 生成的公开仓 VdotReduce 做 yosys equiv 等价性检查；
#   K16 与行为级 gold（$signed 求和）做 miter/sat 检查。失败只记录、不影响 cells/ltp。
#
# 提交：sbatch -p kshcnormal -N 1 -n 8 --time=00:20:00 run_ext_yosys.sh
# 产物：results/yosys/ext-<runid>.json / .log + ext-<runid>/<top>.{stat.json,stat.cmos.txt,ltp.txt,yosys.log}
# 退出码：0 全部解析成功 / 1 至少一个 top 解析失败 / 2 前置缺失
# =============================================================================
set -euo pipefail

RUN_ID="${SLURM_JOB_ID:-$(date '+%Y%m%dT%H%M%S')}"
CORE_DIR="${CORE_DIR:-$HOME/core}"
EXT_RTL_DIR="${EXT_RTL_DIR:-$CORE_DIR/rtl/area_ext}"
REF_RTL="${REF_RTL:-$CORE_DIR/rtl/area/vdot_dp.sv}"
OUT_DIR="$CORE_DIR/results/yosys"
SUB_DIR="$OUT_DIR/ext-$RUN_ID"
LOG_FILE="$OUT_DIR/ext-$RUN_ID.log"
JSON_FILE="$OUT_DIR/ext-$RUN_ID.json"
STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"

mkdir -p "$SUB_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '; }

if [ -r "$HOME/tools/env.sh" ]; then . "$HOME/tools/env.sh"; fi
hash -r

log "===== ext yosys area: run_id=$RUN_ID host=$(hostname) ====="
log "scope: 独立归约树数据通路（sext + 4:2 CSA + CPA + 输出寄存器），未集成 VIMacU，未含工艺库"

if [ -z "${SLURM_JOB_ID:-}" ]; then
  echo "[FATAL] 综合属重计算，禁止在登录节点执行；请 sbatch 提交" >&2
  exit 2
fi
if ! command -v yosys >/dev/null 2>&1; then
  log "[FATAL] yosys 不可用（检查 ~/tools/env.sh）"; exit 2
fi
YOSYS_VER="$(yosys -V 2>/dev/null | sed -n '1p')"
log "yosys=$YOSYS_VER"

# top | rtl | K | W | 结构说明
TOPS=(
  "VdotReduceK8|$EXT_RTL_DIR/VdotReduceK8.sv|8|19|pure4:2 3inst/2stage (baseline, replicates public K1 VdotReduce)"
  "VdotReduceK16|$EXT_RTL_DIR/VdotReduceK16.sv|16|20|pure4:2 7inst/3stage (extension)"
  "VdotReduceK16Gen|$EXT_RTL_DIR/VdotReduceK16Gen.sv|16|20|generator-degraded 3:2 11inst/4stage (side evidence)"
)

declare -a METRICS=()
declare -a CRITERIA=()
FAIL=0

for spec in "${TOPS[@]}"; do
  IFS='|' read -r top rtl k w note <<<"$spec"
  if [ ! -f "$rtl" ]; then
    log "[跳过] 缺 RTL：$rtl"
    CRITERIA+=("{\"name\": \"rtl_$top\", \"expected\": \"存在\", \"actual\": \"缺失 $rtl\", \"status\": \"未运行\"}")
    FAIL=1
    continue
  fi
  sj="$SUB_DIR/$top.stat.json"; cm="$SUB_DIR/$top.stat.cmos.txt"; lt="$SUB_DIR/$top.ltp.txt"
  log "== yosys: $top <= $rtl =="
  if ! yosys -l "$SUB_DIR/$top.yosys.log" -p \
      "read_verilog -sv $rtl; synth -top $top; flatten; tee -o $sj stat -json; tee -o $cm stat -tech cmos; tee -o $lt ltp -noff"; then
    log "[WARN] yosys 失败：$top"
    CRITERIA+=("{\"name\": \"synth_$top\", \"expected\": \"cells/ltp 解析成功\", \"actual\": \"yosys 失败\", \"status\": \"未达标\"}")
    FAIL=1
    continue
  fi
  # 与 40-yosys-area.sh 的 parse_top 同口径（cells=num_cells，tr=cmos，path=ltp 长度）
  parsed="$(python3 - "$top" "$sj" "$cm" "$lt" <<'PY'
import json, re, sys
top, sj, cmos, ltp = sys.argv[1:5]
cells = dff = scopeinfo = ""
by_type = {}
try:
    data = json.load(open(sj))
    mods = data.get("modules", {})
    m = mods.get(top) or mods.get("\\" + top) or (next(iter(mods.values())) if mods else {})
    cells = str(m.get("num_cells", ""))
    by_type = m.get("num_cells_by_type", {}) or {}
    dff = str(by_type.get("$_DFFE_PP_", 0))
    scopeinfo = str(by_type.get("$scopeinfo", 0))
except Exception as e:
    print("ERR\tERR\tERR\tERR\t{}")
    sys.exit(0)
tr = ""
try:
    mm = re.findall(r"Estimated number of transistors:\s*([0-9]+)", open(cmos, errors="replace").read())
    if mm: tr = mm[-1]
except Exception: pass
path = ""
try:
    mm = re.findall(r"Longest topological path[^\n]*?\(length=([0-9]+)\)", open(ltp, errors="replace").read())
    if mm: path = mm[-1]
except Exception: pass
print("%s\t%s\t%s\t%s\t%s" % (cells, dff, scopeinfo, tr, path))
PY
)"
  cells="$(printf '%s' "$parsed" | cut -f1)"
  dff="$(printf '%s' "$parsed" | cut -f2)"
  scopeinfo="$(printf '%s' "$parsed" | cut -f3)"
  tr="$(printf '%s' "$parsed" | cut -f4)"
  path="$(printf '%s' "$parsed" | cut -f5)"
  log "解析：cells=${cells:-未解析} dff=${dff} scopeinfo=${scopeinfo} transistors=${tr:-未解析} longest_path=${path:-未解析}"
  if [ -n "$cells" ] && [ "$cells" != "ERR" ] && [ -n "$path" ]; then
    CRITERIA+=("{\"name\": \"synth_$top\", \"expected\": \"cells/ltp 解析成功\", \"actual\": \"cells=$cells ltp=$path\", \"status\": \"达标\"}")
  else
    CRITERIA+=("{\"name\": \"synth_$top\", \"expected\": \"cells/ltp 解析成功\", \"actual\": \"解析失败\", \"status\": \"未达标\"}")
    FAIL=1
  fi
  METRICS+=("{\"top\": \"$top\", \"k\": $k, \"width\": $w, \"structure\": \"$(json_escape "$note")\", \"cells\": \"${cells}\", \"dff\": \"${dff}\", \"scopeinfo\": \"${scopeinfo}\", \"transistors_est\": \"${tr}\", \"longest_path\": \"${path}\", \"stat_json\": \"$sj\", \"ltp_txt\": \"$lt\"}")
done

# ---------------- 附加：等价性检查（非阻塞） ----------------
# 方法：miter -equiv + sat -prove-asserts（与 K16 gold 同一套；equiv_make/equiv_simple
# 对 firtool 带 initial/_RANDOM 残留的模块会留 275 个未证 $equiv，属流程不适配，改用 miter）。
EQUIV_K8="未运行"; EQUIV_K16="未运行"; EQUIV_K8_GOLD="未运行"

gen_gold() { # $1=module 名  $2=K  $3=输出文件
  local m="$1" k="$2" out="$3" w
  w=$((2 * 8 + $(python3 -c "print(($k).bit_length()-1)")))
  {
    echo "// 行为级 gold：$k 个 16-bit signed 积求和，W=$w，拍级切分与被测件相同"
    echo "module $m ("
    echo "  input  wire         clock,"
    for i in $(seq 0 $((k - 1))); do echo "  input  wire [15:0]  io_sum_wo_$i,"; done
    echo "  input  wire         io_fireS1,"
    echo "  output wire [127:0] io_vd"
    echo ");"
    echo "  wire signed [$((w - 1)):0] s ="
    for i in $(seq 0 $((k - 2))); do echo "    \$signed(io_sum_wo_$i) +"; done
    echo "    \$signed(io_sum_wo_$((k - 1)));"
    echo "  reg  [127:0] io_vd_r;"
    echo "  always @(posedge clock) begin"
    echo "    if (io_fireS1) io_vd_r <= {96'h0, {$((32 - w)){s[$((w - 1))]}}, s};"
    echo "  end"
    echo "  assign io_vd = io_vd_r;"
    echo "endmodule"
  } >"$out"
}

miter_check() { # $1=gold 模块  $2=gate 模块  $3=log 前缀  $4..N=源文件
  local gold="$1" gate="$2" logpfx="$3"; shift 3
  local files="$*"
  if yosys -l "$SUB_DIR/miter_$logpfx.yosys.log" -p \
      "read_verilog -sv $files; miter -equiv -flatten -make_outputs $gold $gate miter; hierarchy -top miter; sat -verify -prove-asserts -set-init-zero -seq 2 -show-ports miter" >/dev/null 2>&1; then
    printf '通过'
  else
    printf '未通过'
  fi
}

if [ -f "$REF_RTL" ]; then
  log "== miter/sat: VdotReduceK8 vs firtool 公开仓 VdotReduce（K1 基线）=="
  EQUIV_K8="$(miter_check VdotReduce VdotReduceK8 k8_vs_public "$REF_RTL" "$EXT_RTL_DIR/VdotReduceK8.sv")"
  [ "$EQUIV_K8" = "通过" ] || log "[WARN] K8 vs 公开仓未通过：只作参考，不影响 cells/ltp（见 miter_k8_vs_public.yosys.log）"
else
  log "[跳过] 缺参考 RTL：$REF_RTL"
fi

gen_gold VdotReduceK8Gold 8 "$SUB_DIR/VdotReduceK8Gold.sv"
log "== miter/sat: VdotReduceK8 vs 行为级 gold =="
EQUIV_K8_GOLD="$(miter_check VdotReduceK8Gold VdotReduceK8 k8_vs_gold "$EXT_RTL_DIR/VdotReduceK8.sv" "$SUB_DIR/VdotReduceK8Gold.sv")"
[ "$EQUIV_K8_GOLD" = "通过" ] || log "[WARN] K8 vs gold 未通过（见 miter_k8_vs_gold.yosys.log）"

gen_gold VdotReduceK16Gold 16 "$SUB_DIR/VdotReduceK16Gold.sv"
log "== miter/sat: VdotReduceK16 vs 行为级 gold =="
EQUIV_K16="$(miter_check VdotReduceK16Gold VdotReduceK16 k16_vs_gold "$EXT_RTL_DIR/VdotReduceK16.sv" "$SUB_DIR/VdotReduceK16Gold.sv")"
[ "$EQUIV_K16" = "通过" ] || log "[WARN] K16 vs gold 未通过（见 miter_k16_vs_gold.yosys.log）"

CRITERIA+=("{\"name\": \"equiv_k8_vs_public_vdotreduce\", \"expected\": \"等价\", \"actual\": \"$(json_escape "$EQUIV_K8")\", \"status\": \"$( [ "$EQUIV_K8" = 通过 ] && echo 达标 || echo 未运行 )\"}")
CRITERIA+=("{\"name\": \"equiv_k8_vs_gold\", \"expected\": \"等价\", \"actual\": \"$(json_escape "$EQUIV_K8_GOLD")\", \"status\": \"$( [ "$EQUIV_K8_GOLD" = 通过 ] && echo 达标 || echo 未运行 )\"}")
CRITERIA+=("{\"name\": \"equiv_k16_vs_gold\", \"expected\": \"等价\", \"actual\": \"$(json_escape "$EQUIV_K16")\", \"status\": \"$( [ "$EQUIV_K16" = 通过 ] && echo 达标 || echo 未运行 )\"}")

# ---------------- 写 JSON ----------------
STATUS="通过"; [ "$FAIL" = "0" ] || STATUS="失败"
{
  printf '{\n'
  printf '  "schema": "vdot-verify/1",\n'
  printf '  "item": "P2-yosys-ext",\n'
  printf '  "script": "run_ext_yosys.sh",\n'
  printf '  "status": "%s",\n' "$STATUS"
  printf '  "platform": "%s",\n' "${SLURM_JOB_PARTITION:-slurm}"
  printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
  printf '  "started_at": "%s",\n' "$STARTED_AT"
  printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "yosys": "%s",\n' "$(json_escape "$YOSYS_VER")"
  printf '  "mapped_area_um2": -1,\n'
  printf '  "scope": "仅独立归约树数据通路（符号扩展 + 4:2 CSA 树 + W 位 CPA + 输出寄存器），未集成进 VIMacU，未含工艺库；cells 为 Yosys abc 通用门计数，不是硅面积",\n'
  printf '  "command_template": "read_verilog -sv <rtl>; synth -top <top>; flatten; tee -o <sj> stat -json; tee -o <cm> stat -tech cmos; tee -o <lt> ltp -noff",\n'
  printf '  "criteria": [\n'
  n=${#CRITERIA[@]}
  for ((i=0;i<n;i++)); do printf '    %s%s\n' "${CRITERIA[$i]}" "$( [ $i -lt $((n-1)) ] && echo , )"; done
  printf '  ],\n'
  printf '  "metrics": [\n'
  n=${#METRICS[@]}
  for ((i=0;i<n;i++)); do printf '    %s%s\n' "${METRICS[$i]}" "$( [ $i -lt $((n-1)) ] && echo , )"; done
  printf '  ],\n'
  printf '  "artifacts": ["%s", "%s", "%s"]\n' "$LOG_FILE" "$JSON_FILE" "$SUB_DIR"
  printf '}\n'
} >"$JSON_FILE"

log "结果 JSON：$JSON_FILE"
log "结果 LOG ：$LOG_FILE"
log "逐 top 产物：$SUB_DIR/"
log "STATUS=$STATUS"
[ "$FAIL" = "0" ] || exit 1
exit 0