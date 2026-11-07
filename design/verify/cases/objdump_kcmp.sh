#!/usr/bin/env bash
# =============================================================================
# objdump_kcmp.sh — perf_kernel_cmp 两版本内核段的**静态指令数**逐条计数
#
# 口径（本脚本为该口径的出处，引用数字必须同时写明这四条）：
#   ① 计数范围 = `[<base_kernel>, kcmp_base_end)` 与 `[<vdot_kernel>, kcmp_vdot_end)`，
#      即 C 源里两个 asm 文本自身的指令。**不含** gcc 在 asm 之后补的 `sext.w`/`ret`，
#      **不含** C 运行时/AM 库/调用方循环。⇒ 与用例的动态计时窗**严格同口径**
#      （动态窗口也只包住同一段 asm 文本；见 perf_kernel_cmp.c 的 measure_point()，`:304`）。
#   ② 编译 = AM 的 `riscv64-xs` app（`-O2`，MARCH 含 `_v`），交叉链
#      `riscv64-unknown-elf-{gcc,objdump}` 14.2.0 / binutils 2.42。
#   ③ 逐条列表**全量入库**（不抽样、不省略）。
#   ④ 比值只写 `N_base/N_vdot`（裸比值），**不写「加速比」**；
#      分母 = 未融合 RVV 序列。
#
# 另给出「计算段」口径（N_base_compute / N_vdot_compute）：
#   两版本共用同一段装载/配置前导与读回后缀，用**归一化 diff**（剥掉地址与机器码，
#   只留助记符+操作数）求差集：
#     仅 base 有的行数 = 计算段里被 vdot 一条顶替掉的那些指令
#     仅 vdot 有的行数 = 1（就是 vdot 那一条）
#   归一化里把 `vmv.x.s a0,vN` 的来源寄存器换成 vSRC：两版本各自读自己的结果寄存器
#   （base 读 v10、vdot 读 v3），那是同一角色的指令、不是「多了一条」。
#   该口径**只作解释用**，不替代 ① 的全段口径（全段才是实测口径）。
#
# 注（实测发现，必须写明）：`vwadd.vx v6, v4, zero` 被 binutils 2.42 反汇编成
#   `vwcvt.x.x.v v6, v4`。这是 RVV 1.0 对「vwadd.vx 且 rs1=x0」的**正式别名**
#   （整数 widen 转换），**机器码完全相同**，不是编错了指令。
#
# 用法：
#   AM_HOME=/path/to/nexus-am bash design/verify/cases/objdump_kcmp.sh [输出目录]
#   bash design/verify/cases/objdump_kcmp.sh --elf <elf> [输出目录]   # 只数，不构建
# 产物：<out>/kcmp_static_base.txt（逐条）
#       <out>/kcmp_static_vdot.txt（逐条）
#       <out>/kcmp_static_summary.txt（N_base / N_vdot / 比值 / 归一化差集）
#       <out>/perf_kernel_cmp.elf（构建模式下，计数所依据的 ELF）
# 退出码：0 计数完成 / 2 前置缺失或符号未命中 / 3 用法错误
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
SRC="$HERE/perf_kernel_cmp.c"

GIVEN_ELF=""
if [ "${1:-}" = "--elf" ]; then
  GIVEN_ELF="${2:?--elf 需要路径}"; shift 2
fi
OUT="${1:-$ROOT/results/difftest/kernel}"

command -v "${CC_PREFIX}objdump" >/dev/null || { echo "[FATAL] ${CC_PREFIX}objdump 不在 PATH" >&2; exit 2; }
mkdir -p "$OUT"

if [ -n "$GIVEN_ELF" ]; then
  ELF="$GIVEN_ELF"
  [ -f "$ELF" ] || { echo "[FATAL] 缺 ELF：$ELF" >&2; exit 2; }
else
  AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
  [ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
  command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
  APP="$AM_HOME/apps/kcmp_static"
  rm -rf "$APP"; mkdir -p "$APP"
  cp "$SRC" "$APP/main.c"
  printf 'NAME = kcmp_static\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' >"$APP/Makefile"
  if ! make -s -C "$APP" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
        CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image; then
    echo "[FATAL] 构建失败（源 $SRC）" >&2; exit 2
  fi
  ELF="$APP/build/kcmp_static-riscv64-xs.elf"
  cp "$ELF" "$OUT/perf_kernel_cmp.elf"
fi

DUMP="$OUT/kcmp_objdump_full.txt"
"${CC_PREFIX}objdump" -d "$ELF" >"$DUMP" 2>&1

# 从 [<sym>, <end>) 抽出指令行。标签行 `000000008000012a <base_kernel>:` 不匹配
# `^[[:space:]]*[0-9a-f]+:`（它以地址+空格+`<` 开头），故不会被误计。
extract() { # $1=起始符号 $2=结束符号
  awk -v s="<$1>:" -v e="<$2>:" '
    index($0, s) && /^[0-9a-f]+ / { inside=1; next }
    inside && index($0, e) { inside=0; exit }
    inside && /^[[:space:]]*[0-9a-f]+:/ { print }
  ' "$DUMP"
}

# 归一化：剥掉「地址: 机器码」前缀与 `# 注释`，只留助记符与操作数。
# 另把 `la` 展开产生的 PC 相对立即数（`auipc tN,0x2` / `addi tN,tN,1122`）的
# 数字部分换成 IMM —— 两个符号在 ELF 里的地址不同，立即数必然不同，
# 但那是**同一段装载序列**，不换掉会让差集把共用前导误算成「仅 base 有」。
normalize() {
  sed -E 's/#.*$//' \
    | sed -E 's/^[[:space:]]*[0-9a-f]+:[[:space:]]+[0-9a-f]+[[:space:]]+//' \
    | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' \
    | sed -E 's/^(auipc [a-z0-9]+),0x[0-9a-f]+$/\1,IMM/' \
    | sed -E 's/^(addi [a-z0-9]+,(t[0-9]|a[0-9]|s[0-9]+|sp|ra)),[0-9]+$/\1,IMM/' \
    | sed -E 's/^(vmv\.x\.s a0),v[0-9]+$/\1,vSRC/' \
    | grep -v '^$' || true
}

extract base_kernel kcmp_base_end >"$OUT/kcmp_static_base.txt"
extract vdot_kernel kcmp_vdot_end >"$OUT/kcmp_static_vdot.txt"

N_BASE="$(grep -c . "$OUT/kcmp_static_base.txt" || true)"
N_VDOT="$(grep -c . "$OUT/kcmp_static_vdot.txt" || true)"
[ "${N_BASE:-0}" -ge 1 ] || { echo "[FATAL] base 段计数为 0（符号/标签未命中）" >&2; exit 2; }
[ "${N_VDOT:-0}" -ge 1 ] || { echo "[FATAL] vdot 段计数为 0（符号/标签未命中）" >&2; exit 2; }

normalize <"$OUT/kcmp_static_base.txt" >"$OUT/kcmp_static_base.norm.txt"
normalize <"$OUT/kcmp_static_vdot.txt" >"$OUT/kcmp_static_vdot.norm.txt"
DIFF="$OUT/kcmp_static_diff.txt"
diff "$OUT/kcmp_static_base.norm.txt" "$OUT/kcmp_static_vdot.norm.txt" >"$DIFF" 2>&1 || true

ONLY_BASE="$(grep -c '^<' "$DIFF" || true)"
ONLY_VDOT="$(grep -c '^>' "$DIFF" || true)"

ELF_SHA="$(sha256sum "$ELF" | cut -d' ' -f1)"
{
  echo "# kcmp 静态指令数（口径见 design/verify/cases/objdump_kcmp.sh 头注）"
  echo "date=$(date '+%F %T')"
  echo "source=$SRC"
  echo "source_sha256=$(sha256sum "$SRC" | cut -d' ' -f1)"
  echo "elf=$ELF"
  echo "elf_sha256=$ELF_SHA"
  echo "toolchain=$("${CC_PREFIX}gcc" --version | head -1)"
  echo "objdump=$("${CC_PREFIX}objdump" --version | head -1)"
  echo "march=$MARCH"
  echo "range_base=base_kernel..kcmp_base_end"
  echo "range_vdot=vdot_kernel..kcmp_vdot_end"
  echo "N_base=$N_BASE"
  echo "N_vdot=$N_VDOT"
  echo "N_diff=$((N_BASE - N_VDOT))"
  echo "ratio=N_base/N_vdot=$(awk -v a="$N_BASE" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}')"
  echo "N_base_compute_only=$ONLY_BASE   # 归一化差集里仅 base 有的行数（被 vdot 顶替掉的指令数）"
  echo "N_vdot_compute_only=$ONLY_VDOT   # 归一化差集里仅 vdot 有的行数（应为 1：vdot 那一条）"
  echo "compute_ratio=$ONLY_BASE/$ONLY_VDOT=$(awk -v a="$ONLY_BASE" -v b="$ONLY_VDOT" 'BEGIN{printf "%.3f", a/b}')"
  echo "denom=unfused_rvv_seq（分母是未融合 RVV 序列）"
  echo "note=vwadd.vx 且 rs1=x0 被反汇编为 vwcvt.x.x.v（RVV 1.0 正式别名，机器码相同）"
  echo "--- 逐条（base，$N_BASE 条）---"
  cat "$OUT/kcmp_static_base.txt"
  echo "--- 逐条（vdot，$N_VDOT 条）---"
  cat "$OUT/kcmp_static_vdot.txt"
  echo "--- 归一化 diff（< = 仅 base 有，> = 仅 vdot 有）---"
  cat "$DIFF"
} >"$OUT/kcmp_static_summary.txt"

echo "N_base=$N_BASE N_vdot=$N_VDOT diff=$((N_BASE - N_VDOT)) ratio=$(awk -v a="$N_BASE" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}') compute_only=${ONLY_BASE}/${ONLY_VDOT}"
echo "产物：$OUT/kcmp_static_{base,vdot,summary}.txt + kcmp_static_diff.txt"
exit 0
