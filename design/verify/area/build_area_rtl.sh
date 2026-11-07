#!/usr/bin/env bash
# 为 core-package/scripts/40-yosys-area.sh 准备两块「同口径数据通路」RTL：
#   vdot_dp.sv   ← 生成 RTL 的 VdotReduce 闭包（sext19 + 4:2 树 + 19 位 CPA + 格式化）
#   vmac_only.sv ← 生成 RTL 的 VIMac64b 闭包（既有乘法累加整路，作为面积对照分母）
# 用法：bash design/verify/area/build_area_rtl.sh [NOOP_HOME] [输出目录]
#   默认 NOOP_HOME=$HOME/core/src/XiangShan，输出 $NOOP_HOME/../rtl/area
set -euo pipefail

NOOP="${1:-${NOOP_HOME:-$HOME/core/src/XiangShan}}"
RTL_DIR="$NOOP/build/rtl"
OUT_DIR="${2:-$NOOP/../rtl/area}"
mkdir -p "$OUT_DIR"
[ -d "$RTL_DIR" ] || { echo "[FATAL] 缺 $RTL_DIR（先 make emu / make verilog）"; exit 3; }

closure() { # $1 = 顶层模块名  $2 = 输出文件
  local top="$1" out="$2"
  [ -f "$RTL_DIR/$top.sv" ] || { echo "[FATAL] 缺 $RTL_DIR/$top.sv"; exit 3; }
  declare -A SEEN=()
  local QUEUE=("$top")
  while [ "${#QUEUE[@]}" -gt 0 ]; do
    local mod="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}")
    [ -n "${SEEN[$mod]:-}" ] && continue
    local file="$RTL_DIR/$mod.sv"
    [ -f "$file" ] || { echo "[WARN] 无 $mod.sv（内联/原语），跳过"; continue; }
    SEEN[$mod]=1
    while read -r dep; do
      [ -z "$dep" ] && continue
      [ -n "${SEEN[$dep]:-}" ] && continue
      [ -f "$RTL_DIR/$dep.sv" ] && QUEUE+=("$dep")
    done < <(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$file" \
             | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//' \
             | grep -vE '^(module|wire|reg|logic|assign|always|initial|input|output|begin|end|if|else|for|case|casex|casez|endcase|localparam|parameter|typedef|function|task|generate|endgenerate|posedge|negedge|assert|assume|cover|else|return)$' \
             | sort -u)
  done
  { echo "// $top 闭包（由 design/verify/area/build_area_rtl.sh 从 build/rtl 拼接，勿手改）"
    for m in "${!SEEN[@]}"; do cat "$RTL_DIR/$m.sv"; echo; done; } > "$out"
  echo "-> $out  top=$top  模块数=${#SEEN[@]}  行数=$(wc -l < "$out")"
}

closure VdotReduce "$OUT_DIR/vdot_dp.sv"
closure VIMac64b   "$OUT_DIR/vmac_only.sv"

echo
echo "下一步（计算节点，面积口径见 design/ALGORITHM.md §3.5：仅数据通路、无工艺库）："
echo "  sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 core-package/scripts/40-yosys-area.sh \\"
echo "    --vdot-rtl $OUT_DIR/vdot_dp.sv --vdot-top VdotReduce \\"
echo "    --vmac-rtl $OUT_DIR/vmac_only.sv --vmac-top VIMac64b"
