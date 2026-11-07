#!/usr/bin/env bash
# =============================================================================
# build_llm_attn.sh — perf_llm_attn 镜像的两遍构建（静态计数 → -D 注入 → 复核计数）
#
# 为什么两遍（「静态↔动态交叉核对」成立的前提）：
#   用例要把「静态数出的 N_base / N_macc / N_vdot」与「emu 实测的退休指令数」比对，
#   于是需要把静态计数以 `-DSTATIC_N_BASE=` / `-DSTATIC_N_MACC=` / `-DSTATIC_N_VDOT=` 编进镜像。
#   但注入值来自同源文件的一次编译 ⇒ 鸡生蛋。做法：
#     第 1 遍：不带 -D 编译 → objdump 数出三个 N
#     第 2 遍：带 -D 注入上述值编译 → 得到运行用 ELF/.bin
#     复核：  对第 2 遍 ELF **再数一次**，必须与第 1 遍同值
#   ⇒ 运行镜像里的注入值与运行镜像自身的实际指令数一致，不是两套数字。
#   第 2 遍的复核计数与第 1 遍不同值即判失败（说明 -D 改变了内核段，注入值不可信）。
#
# 两个镜像（同一份源码、同一个 -D 计数，只差 G0 的期望值被故意改错 1）：
#   正常：llm_attn.bin      打印 `LLM_ATTN verdict=ALL_OK`
#   G0  ：llm_attn_g0.bin   打印 `LLM_ATTN verdict=HAS_FAIL`（`-DLLM_G0_MUTATE`）
#   G0 的存在用于排除「虚假通过」：如果 G0 也打 ALL_OK，本 harness 作废，该次运行的全部数字不得引用。
#   注意 G0 镜像的计数复核仍要做：`-DLLM_G0_MUTATE` 只改 `want_of()` 的常数，不动内核段；
#     若三个 N 变了，说明该宏意外改了内核体，此时两遍一致性会失败（脚本会拦）。
#
# 用法：
#   AM_HOME=/path/to/nexus-am bash design/verify/cases/build_llm_attn.sh [输出目录]
#   AM_HOME=/path/to/nexus-am bash design/verify/cases/build_llm_attn.sh --g0 [输出目录]
# 前置：先跑 `python3 -I design/verify/cases/gen_llm_attn.py --out design/verify/cases/llm_attn_vectors.h`
# 产物：<out>/llm_attn.bin（或 llm_attn_g0.bin）、<out>/llm_attn.elf（或 llm_attn_g0.elf）、
#       <out>/llm_attn_build_summary.txt（或 _g0）、<out>/pass1[_g0]/、<out>/pass2[_g0]/
# 退出码：0 成功 / 2 前置缺失或复核不一致 / 3 用法错误
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
G0=0
if [ "${1:-}" = "--g0" ]; then G0=1; shift; fi
OUT="${1:-$ROOT/results/difftest/llm}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
# xpack riscv-none-elf-gcc 13.2.0 默认 mabi=ilp32（rv32）⇒ 必须显式给 -mabi=lp64d，
# 否则 cc1 报 `ABI requires '-march=rv32'`。与 core-package/scripts/62-wave-vdot.sh:113-115 同处置。
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt -mabi=lp64d}"
SRC="$HERE/perf_llm_attn.c"
HDR="$HERE/llm_attn_vectors.h"
OBJDUMP_SH="$HERE/objdump_llm_attn.sh"

command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
[ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
[ -f "$HDR" ] || { echo "[FATAL] 缺头 $HDR（先跑 gen_llm_attn.py --out）" >&2; exit 2; }
[ -f "$OBJDUMP_SH" ] || { echo "[FATAL] 缺 $OBJDUMP_SH" >&2; exit 2; }
mkdir -p "$OUT"

if [ "$G0" -eq 1 ]; then SUF="_g0"; APPNAME="llm_attn_g0"; G0FLAGS="-DLLM_G0_MUTATE=1";
else SUF=""; APPNAME="llm_attn"; G0FLAGS=""; fi

# 构建一个 AM app；$1=app 名 $2=额外 CFLAGS → 打印 ELF 路径
build_app() {
  local app="$1" extra="${2:-}" d="$AM_HOME/apps/$1"
  rm -rf "$d"; mkdir -p "$d/include"
  cp "$SRC" "$d/main.c"
  cp "$HDR" "$d/include/llm_attn_vectors.h"
  {
    printf 'NAME = %s\nSRCS = main.c\n' "$app"
    [ -n "$extra" ] && printf 'CFLAGS += %s\n' "$extra"
    printf 'include $(AM_HOME)/Makefile.app\n'
  } >"$d/Makefile"
  make -s -C "$d" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
       CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image >/dev/null 2>&1 || return 1
  printf '%s\n' "$d/build/$app-riscv64-xs.elf"
}

# ---------------- 第 1 遍：不带 -D，取静态计数 ----------------
ELF1="$(build_app "${APPNAME}_pass1" "$G0FLAGS")" || { echo "[FATAL] 第 1 遍构建失败${SUF}" >&2; exit 2; }
P1_DIR="$OUT/pass1$SUF"; mkdir -p "$P1_DIR"
bash "$OBJDUMP_SH" --elf "$ELF1" "$P1_DIR" >/dev/null || { echo "[FATAL] 第 1 遍计数失败${SUF}" >&2; exit 2; }
N_BASE="$(awk -F= '/^N_base=/{print $2}' "$P1_DIR/llm_attn_static_summary.txt")"
N_MACC="$(awk -F= '/^N_macc=/{print $2}' "$P1_DIR/llm_attn_static_summary.txt")"
N_VDOT="$(awk -F= '/^N_vdot=/{print $2}' "$P1_DIR/llm_attn_static_summary.txt")"
[ -n "$N_BASE" ] && [ -n "$N_MACC" ] && [ -n "$N_VDOT" ] \
  || { echo "[FATAL] 第 1 遍计数解析失败${SUF}" >&2; exit 2; }
echo "[pass1$SUF] N_base=$N_BASE N_macc=$N_MACC N_vdot=$N_VDOT"

# ---------------- 第 2 遍：注入静态计数 ----------------
ELF2="$(build_app "${APPNAME}_pass2" "-DSTATIC_N_BASE=$N_BASE -DSTATIC_N_MACC=$N_MACC -DSTATIC_N_VDOT=$N_VDOT $G0FLAGS")" \
  || { echo "[FATAL] 第 2 遍构建失败（-D 注入）${SUF}" >&2; exit 2; }
P2_DIR="$OUT/pass2$SUF"; mkdir -p "$P2_DIR"
bash "$OBJDUMP_SH" --elf "$ELF2" "$P2_DIR" >/dev/null || { echo "[FATAL] 第 2 遍计数失败${SUF}" >&2; exit 2; }
N_BASE2="$(awk -F= '/^N_base=/{print $2}' "$P2_DIR/llm_attn_static_summary.txt")"
N_MACC2="$(awk -F= '/^N_macc=/{print $2}' "$P2_DIR/llm_attn_static_summary.txt")"
N_VDOT2="$(awk -F= '/^N_vdot=/{print $2}' "$P2_DIR/llm_attn_static_summary.txt")"
echo "[pass2$SUF] N_base=$N_BASE2 N_macc=$N_MACC2 N_vdot=$N_VDOT2（复核第 1 遍）"

if [ "$N_BASE" != "$N_BASE2" ] || [ "$N_MACC" != "$N_MACC2" ] || [ "$N_VDOT" != "$N_VDOT2" ]; then
  echo "[FATAL] 两遍计数不一致${SUF}：pass1=$N_BASE/$N_MACC/$N_VDOT pass2=$N_BASE2/$N_MACC2/$N_VDOT2" \
       "⇒ -D 注入改变了内核段，注入值不可信" >&2
  exit 2
fi

cp "$ELF2" "$OUT/llm_attn$SUF.elf"
BIN="$AM_HOME/apps/${APPNAME}_pass2/build/${APPNAME}_pass2-riscv64-xs.bin"
[ -f "$BIN" ] || { echo "[FATAL] 缺 .bin：$BIN" >&2; exit 2; }
cp "$BIN" "$OUT/llm_attn$SUF.bin"

# 静态计数按变体落盘：**正常镜像写 llm_attn_static_*，G0 镜像写 llm_attn_g0_static_***。
# （2026-11-06 实测发现：早先无条件写 "$OUT/llm_attn_static_*"，后跑的 G0 会把正常镜像的
#  静态计数覆盖成 G0 ELF 的计数——两者数值相同（只差 want_of 常数），但 elf_sha256 会对不上，
#  证据链自洽性受损。现按变体分开写。）
if [ "$G0" -eq 0 ]; then
  cp "$P2_DIR"/llm_attn_static_{base,macc,vdot,diff,summary}.txt "$OUT/" 2>/dev/null || true
else
  for f in base macc vdot diff summary; do
    cp "$P2_DIR/llm_attn_static_$f.txt" "$OUT/llm_attn_g0_static_$f.txt" 2>/dev/null || true
  done
fi

{
  echo "# build_llm_attn.sh 产物${SUF}（$(date '+%F %T')）"
  echo "variant=$( [ "$G0" -eq 1 ] && echo g0 || echo normal )"
  echo "src=$SRC"
  echo "src_sha256=$(sha256sum "$SRC" | cut -d' ' -f1)"
  echo "header_sha256=$(sha256sum "$HDR" | cut -d' ' -f1)"
  echo "run_elf=$OUT/llm_attn$SUF.elf"
  echo "run_elf_sha256=$(sha256sum "$OUT/llm_attn$SUF.elf" | cut -d' ' -f1)"
  echo "run_bin=$OUT/llm_attn$SUF.bin"
  echo "run_bin_sha256=$(sha256sum "$OUT/llm_attn$SUF.bin" | cut -d' ' -f1)"
  echo "N_base=$N_BASE"
  echo "N_macc=$N_MACC"
  echo "N_vdot=$N_VDOT"
  echo "two_pass_agree=yes"
  echo "injected=-DSTATIC_N_BASE=$N_BASE -DSTATIC_N_MACC=$N_MACC -DSTATIC_N_VDOT=$N_VDOT $G0FLAGS"
} >"$OUT/llm_attn_build_summary$SUF.txt"

echo "[OK] 镜像：$OUT/llm_attn$SUF.bin（sha256 $(sha256sum "$OUT/llm_attn$SUF.bin" | cut -d' ' -f1)）"
exit 0
