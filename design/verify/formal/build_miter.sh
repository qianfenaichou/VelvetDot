#!/usr/bin/env bash
# 拼接 vdot 数据通路 miter（正向 + 负控变异体），供 core-package/scripts/50-formal-miter.sh 跑 yosys SAT。
#
# 用法：bash design/verify/formal/build_miter.sh [NOOP_HOME] [输出目录]
#   NOOP_HOME 默认 $NOOP_HOME 或 $HOME/core/src/XiangShan；输出目录默认 $NOOP_HOME/../rtl/formal
# 产物：
#   <out>/vdot_dp_miter_full.sv      top=vdot_dp_miter（正向）
#   <out>/vdot_dp_miter_bug_full.sv  top=vdot_dp_miter（同一 top 名，内部金模型带注入缺陷，供 --mutant）
set -euo pipefail

NOOP="${1:-${NOOP_HOME:-$HOME/core/src/XiangShan}}"
RTL_DIR="$NOOP/build/rtl"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${2:-$NOOP/../rtl/formal}"
mkdir -p "$OUT_DIR"

[ -d "$RTL_DIR" ] || { echo "[FATAL] 缺生成 RTL 目录：$RTL_DIR（先跑 make emu 或 make verilog）"; exit 3; }
[ -f "$RTL_DIR/VdotReduce.sv" ] || { echo "[FATAL] 缺 $RTL_DIR/VdotReduce.sv"; exit 3; }

# 1) 从 VdotReduce 出发求模块闭包（build/rtl 每个模块一个同名 .sv）
declare -A SEEN=()
QUEUE=(VdotReduce)
while [ "${#QUEUE[@]}" -gt 0 ]; do
  mod="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}")
  [ -n "${SEEN[$mod]:-}" ] && continue
  file="$RTL_DIR/$mod.sv"
  [ -f "$file" ] || { echo "[WARN] 无 $mod.sv（内联或原语），跳过"; continue; }
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

if [ "${#SEEN[@]}" -lt 2 ]; then
  echo "[FATAL] 闭包仅 ${#SEEN[@]} 个模块，实例化解析可能失效（期望含 CSA 树子模块）"
  exit 3
fi
echo "+ DUT 闭包：${#SEEN[@]} 个模块 → ${!SEEN[*]}"

dut_tmp="$(mktemp)"
for m in "${!SEEN[@]}"; do cat "$RTL_DIR/$m.sv"; echo; done > "$dut_tmp"

# 2) 正向：DUT 闭包 + 正确金模型（yosys miter 自己建顶层）
{ echo "// 由 design/verify/formal/build_miter.sh 拼接：VdotReduce 闭包 + 正确金模型 vdot_dp_spec"
  cat "$dut_tmp"
  sed -n '/^module vdot_dp_spec(/,/^endmodule/p' "$HERE/vdot_dp_spec.sv"; } > "$OUT_DIR/vdot_dp_miter_full.sv"

# 3) 负控：同一 DUT 闭包 + 带缺陷金模型（lane3 零扩展）
{ echo "// 由 build_miter.sh 拼接：VdotReduce 闭包 + 负控金模型 vdot_dp_spec_bug（应判 FAIL）"
  cat "$dut_tmp"
  sed -n '/^module vdot_dp_spec_bug(/,/^endmodule/p' "$HERE/vdot_dp_spec.sv" | sed 's/^module vdot_dp_spec_bug(/module vdot_dp_spec(/'; } > "$OUT_DIR/vdot_dp_miter_bug_full.sv"
rm -f "$dut_tmp"

for f in "$OUT_DIR/vdot_dp_miter_full.sv" "$OUT_DIR/vdot_dp_miter_bug_full.sv"; do
  echo "-> $f ($(wc -l < "$f") 行, $(stat -c%s "$f") 字节)"
done
grep -c "^module " "$OUT_DIR/vdot_dp_miter_full.sv" | sed 's/^/正向 module 数=/'
echo "下一步（计算节点；顶层由 yosys miter -equiv 生成）："
echo "  sbatch -p kshcnormal -N 1 -n 8 --time=00:45:00 core-package/scripts/50-formal-miter.sh \\"
echo "    --miter $OUT_DIR/vdot_dp_miter_full.sv --top vdot_dp_miter \\"
echo "    --mutant $OUT_DIR/vdot_dp_miter_bug_full.sv"
