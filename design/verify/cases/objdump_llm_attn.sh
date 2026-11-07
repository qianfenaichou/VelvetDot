#!/usr/bin/env bash
# =============================================================================
# objdump_llm_attn.sh — perf_llm_attn 三臂内核段的**静态指令数**逐条计数
#
# 口径（引用数字必须同时写明这四条）：
#   ① 计数范围 = `[<llm_base_begin>,<llm_base_end)` / `[<llm_macc_begin>,<llm_macc_end)` /
#      `[<llm_vdot_begin>,<llm_vdot_end)`，即 C 源里三个 asm 文本自身的指令。
#      **不含** gcc 在 asm 之后补的 `sext.w`/`ret`，不含 C 运行时/AM 库/调用方循环，
#      也不含 gcc 在函数入口给 "r" 约束操作数做的 `mv`（begin 标签在 asm 第一行）。
#      ⇒ 与动态计时窗**严格同口径**（动态窗口只包住同一段 asm 文本；见 perf_llm_attn.c `llm_point()`）。
#   ② 编译 = AM 的 `riscv64-xs` app（`-O2`，MARCH 含 `_v`）。
#   ③ 逐条列表**全量入库**（不抽样、不省略）。
#   ④ 比值只写 `N_base/N_vdot` 等**裸比值**，不写「加速比」；分母 = `unfused_rvv_seq`。
#
# 另给「计算段」口径（N_*_compute_only）：三臂共用同一段装载前导与读回后缀，
# 用**归一化 diff**（剥掉地址与机器码，只留助记符+操作数）求差集：
#   `unfused_rvv_seq` 与 `vdot_seq` 之间：仅 base 有的行 = 被 vdot 顶替的计算指令，仅 vdot 有的行 = vdot 那一条。
#   `vwmacc_rvv_seq` 与 `vdot_seq` 之间：同理。
#   该口径**只作解释用**，不替代 ① 的全段口径（全段才是实测口径）。
#
# 用法：
#   AM_HOME=/path/to/nexus-am bash design/verify/cases/objdump_llm_attn.sh [输出目录]
#   bash design/verify/cases/objdump_llm_attn.sh --elf <elf> [输出目录]   # 只数，不构建
# 产物：<out>/llm_attn_static_{base,macc,vdot}.txt（逐条）
#       <out>/llm_attn_static_summary.txt（N_* / 比值 / 归一化差集）
#       <out>/llm_attn_objdump_full.txt
# 退出码：0 计数完成 / 2 前置缺失或符号未命中 / 3 用法错误
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
# xpack riscv-none-elf-gcc 13.2.0 默认 mabi=ilp32（rv32）⇒ 必须显式给 -mabi=lp64d，
# 否则 cc1 报 `ABI requires '-march=rv32'`。与 core-package/scripts/62-wave-vdot.sh:113-115 同处置。
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt -mabi=lp64d}"
SRC="$HERE/perf_llm_attn.c"
HDR="$HERE/llm_attn_vectors.h"

GIVEN_ELF=""
if [ "${1:-}" = "--elf" ]; then
  GIVEN_ELF="${2:?--elf 需要路径}"; shift 2
fi
OUT="${1:-$ROOT/results/difftest/llm}"

command -v "${CC_PREFIX}objdump" >/dev/null || { echo "[FATAL] ${CC_PREFIX}objdump 不在 PATH" >&2; exit 2; }
mkdir -p "$OUT"

if [ -n "$GIVEN_ELF" ]; then
  ELF="$GIVEN_ELF"
  [ -f "$ELF" ] || { echo "[FATAL] 缺 ELF：$ELF" >&2; exit 2; }
else
  AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
  [ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
  [ -f "$HDR" ] || { echo "[FATAL] 缺头 $HDR（先跑 gen_llm_attn.py）" >&2; exit 2; }
  command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
  APP="$AM_HOME/apps/llm_attn_static"
  rm -rf "$APP"; mkdir -p "$APP/include"
  cp "$SRC" "$APP/main.c"
  cp "$HDR" "$APP/include/llm_attn_vectors.h"
  printf 'NAME = llm_attn_static\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' >"$APP/Makefile"
  if ! make -s -C "$APP" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
        CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image; then
    echo "[FATAL] 构建失败（源 $SRC）" >&2; exit 2
  fi
  ELF="$APP/build/llm_attn_static-riscv64-xs.elf"
  cp "$ELF" "$OUT/llm_attn.elf"
fi

DUMP="$OUT/llm_attn_objdump_full.txt"
"${CC_PREFIX}objdump" -d "$ELF" >"$DUMP" 2>&1

# 从 [<sym>, <end>) 抽指令行（标签行以地址+空格+`<` 开头，不匹配指令正则）
extract() {
  awk -v s="<$1>:" -v e="<$2>:" '
    index($0, s) && /^[0-9a-f]+ / { inside=1; next }
    inside && index($0, e) { inside=0; exit }
    inside && /^[[:space:]]*[0-9a-f]+:/ { print }
  ' "$DUMP"
}

# 归一化：剥掉「地址: 机器码」前缀与 `# 注释`，只留助记符与操作数。
# 三臂的 v 寄存器编号不同（v10 累积器 vs v12 结果），把 `vmv.x.s a0,vN` 的来源换成 vSRC，
# 使「同一角色的读回」在差集里对消。
normalize() {
  sed -E 's/#.*$//' \
    | sed -E 's/^[[:space:]]*[0-9a-f]+:[[:space:]]+[0-9a-f]+[[:space:]]+//' \
    | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//' \
    | sed -E 's/^(vmv\.x\.s a0),v[0-9]+$/\1,vSRC/' \
    | sed -E 's/^\.word 0x3a20a[0-9a-f]{3}$/.word VDOT/' \
    | grep -v '^$' || true
}

extract llm_base_begin llm_base_end >"$OUT/llm_attn_static_base.txt"
extract llm_macc_begin llm_macc_end >"$OUT/llm_attn_static_macc.txt"
extract llm_vdot_begin llm_vdot_end >"$OUT/llm_attn_static_vdot.txt"

N_BASE="$(grep -c . "$OUT/llm_attn_static_base.txt" || true)"
N_MACC="$(grep -c . "$OUT/llm_attn_static_macc.txt" || true)"
N_VDOT="$(grep -c . "$OUT/llm_attn_static_vdot.txt" || true)"
[ "${N_BASE:-0}" -ge 1 ] || { echo "[FATAL] base 段计数为 0（符号/标签未命中）" >&2; exit 2; }
[ "${N_MACC:-0}" -ge 1 ] || { echo "[FATAL] macc 段计数为 0（符号/标签未命中）" >&2; exit 2; }
[ "${N_VDOT:-0}" -ge 1 ] || { echo "[FATAL] vdot 段计数为 0（符号/标签未命中）" >&2; exit 2; }

normalize <"$OUT/llm_attn_static_base.txt" >"$OUT/llm_attn_static_base.norm.txt"
normalize <"$OUT/llm_attn_static_macc.txt" >"$OUT/llm_attn_static_macc.norm.txt"
normalize <"$OUT/llm_attn_static_vdot.txt" >"$OUT/llm_attn_static_vdot.norm.txt"

DIFF="$OUT/llm_attn_static_diff.txt"
{
  echo "=== base vs vdot ==="
  diff "$OUT/llm_attn_static_base.norm.txt" "$OUT/llm_attn_static_vdot.norm.txt" 2>&1 || true
  echo "=== macc vs vdot ==="
  diff "$OUT/llm_attn_static_macc.norm.txt" "$OUT/llm_attn_static_vdot.norm.txt" 2>&1 || true
} >"$DIFF"

# 计算段差集：按**去重后的行集合**算「仅本臂有的不同行数」。
# 为什么不用 diff 的 `<`/`>` 行数：每个子块的同一段文本重复 8 次，diff 会逐块计数（8 倍），
# 得到的是「位置差」不是「指令种类差」。这里要回答的是「计算段被替换成了哪几种指令」，
# 故用 sort -u + comm 的集合差。
uniq_only() { # $1=左文件 $2=右文件 → 仅左文件有的**不同**行数
  sort -u "$1" >"$OUT/.u1.txt"; sort -u "$2" >"$OUT/.u2.txt"
  comm -23 "$OUT/.u1.txt" "$OUT/.u2.txt" | grep -c . || true
}
by_vdot_base="$(uniq_only "$OUT/llm_attn_static_base.norm.txt" "$OUT/llm_attn_static_vdot.norm.txt")"
bv_vdot="$(uniq_only "$OUT/llm_attn_static_vdot.norm.txt" "$OUT/llm_attn_static_base.norm.txt")"
by_vdot_macc="$(uniq_only "$OUT/llm_attn_static_macc.norm.txt" "$OUT/llm_attn_static_vdot.norm.txt")"
mv_vdot="$(uniq_only "$OUT/llm_attn_static_vdot.norm.txt" "$OUT/llm_attn_static_macc.norm.txt")"
rm -f "$OUT/.u1.txt" "$OUT/.u2.txt"

ELF_SHA="$(sha256sum "$ELF" | cut -d' ' -f1)"
{
  echo "# llm_attn 静态指令数（口径见 design/verify/cases/objdump_llm_attn.sh 头注）"
  echo "date=$(date '+%F %T')"
  echo "source=$SRC"
  echo "source_sha256=$(sha256sum "$SRC" | cut -d' ' -f1)"
  echo "header=$HDR"
  echo "header_sha256=$(sha256sum "$HDR" 2>/dev/null | cut -d' ' -f1)"
  echo "elf=$ELF"
  echo "elf_sha256=$ELF_SHA"
  echo "toolchain=$("${CC_PREFIX}gcc" --version | head -1)"
  echo "objdump=$("${CC_PREFIX}objdump" --version | head -1)"
  echo "march=$MARCH"
  echo "range_base=llm_base_begin..llm_base_end"
  echo "range_macc=llm_macc_begin..llm_macc_end"
  echo "range_vdot=llm_vdot_begin..llm_vdot_end"
  echo "N_base=$N_BASE"
  echo "N_macc=$N_MACC"
  echo "N_vdot=$N_VDOT"
  echo "N_diff_base_minus_vdot=$((N_BASE - N_VDOT))"
  echo "ratio=N_base/N_vdot=$(awk -v a="$N_BASE" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}')"
  echo "ratio=N_macc/N_vdot=$(awk -v a="$N_MACC" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}')"
  echo "N_base_compute_kinds=$by_vdot_base   # base-vdot：仅 base 有的**不同**归一化行数（被 vdot 顶替的指令种类）"
  echo "N_vdot_compute_kinds_vs_base=$bv_vdot  # 仅 vdot 有的不同行数（实测 10 = 1 vdot + 7 vadd + 2 配置）"
  echo "N_macc_compute_kinds=$by_vdot_macc   # macc-vdot：仅 macc 有的不同行数"
  echo "N_vdot_compute_kinds_vs_macc=$mv_vdot  # 同上（实测 10）"
  echo "（差集按 sort -u 后的行集合算，不是 diff 的逐块行数；逐块全文见 diff 段）"
  echo "denom=unfused_rvv_seq（主分母 = 未融合 RVV 序列）；vwmacc_rvv_seq 只作敏感性"
  echo "note=每 score 的静态数 = 8 个子块 × 每块条数 + 共用清零/读回；比值一律是裸比值，不是加速比"
  echo "--- 逐条（base，$N_BASE 条）---"
  cat "$OUT/llm_attn_static_base.txt"
  echo "--- 逐条（macc，$N_MACC 条）---"
  cat "$OUT/llm_attn_static_macc.txt"
  echo "--- 逐条（vdot，$N_VDOT 条）---"
  cat "$OUT/llm_attn_static_vdot.txt"
  echo "--- 归一化 diff（< = 前臂独有，> = vdot 独有）---"
  cat "$DIFF"
} >"$OUT/llm_attn_static_summary.txt"

echo "N_base=$N_BASE N_macc=$N_MACC N_vdot=$N_VDOT base/vdot=$(awk -v a="$N_BASE" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}') macc/vdot=$(awk -v a="$N_MACC" -v b="$N_VDOT" 'BEGIN{printf "%.3f", a/b}') compute_kinds=base:$by_vdot_base vdot_vs_base:$bv_vdot macc:$by_vdot_macc vdot_vs_macc:$mv_vdot"
echo "产物：$OUT/llm_attn_static_{base,macc,vdot,summary}.txt + llm_attn_static_diff.txt"
exit 0
