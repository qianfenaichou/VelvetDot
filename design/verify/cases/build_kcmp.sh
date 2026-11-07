#!/usr/bin/env bash
# =============================================================================
# build_kcmp.sh — perf_kernel_cmp 镜像的两遍构建（静态计数 → -D 注入 → 复核计数）
#
# 为什么两遍（这是「静态↔动态交叉核对」成立的前提）：
#   用例要把「静态数出的 N_base / N_vdot」与「emu 实测的退休指令数」比对，
#   于是需要把静态计数以 `-DSTATIC_N_BASE=` / `-DSTATIC_N_VDOT=` 编进镜像。
#   但注入值来自同源文件的一次编译 ⇒ 鸡生蛋。做法：
#     第 1 遍：不带 -D 编译 → objdump 数出 N_base/N_vdot
#     第 2 遍：带 -D 注入上述值编译 → 得到运行用 ELF/.bin
#     复核：  对第 2 遍 ELF **再数一次**，必须与第 1 遍同值
#   ⇒ 运行镜像里的注入值与运行镜像自身的实际指令数一致，不是两套数字。
#   第 2 遍的复核计数与第 1 遍不同值即判失败（说明 -D 改变了内核段，注入值不可信）。
#
# 用法：AM_HOME=/path/to/nexus-am bash design/verify/cases/build_kcmp.sh [输出目录]
# 产物：<out>/perf_kernel_cmp.bin（运行镜像）
#       <out>/perf_kernel_cmp.elf（运行镜像 ELF，sha256 记入 summary）
#       <out>/kcmp_static_*.txt（两遍的静态计数，pass1/pass2 分列）
# 退出码：0 成功 / 2 前置缺失或复核不一致 / 3 用法错误
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-$ROOT/results/difftest/kernel}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
SRC="$HERE/perf_kernel_cmp.c"
OBJDUMP_SH="$HERE/objdump_kcmp.sh"

command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
[ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
[ -f "$OBJDUMP_SH" ] || { echo "[FATAL] 缺 $OBJDUMP_SH" >&2; exit 2; }
mkdir -p "$OUT"

build_app() { # $1=app 名 $2=额外 CFLAGS（可空）→ 打印 ELF 路径
  local app="$1" extra="${2:-}" d="$AM_HOME/apps/$1"
  rm -rf "$d"; mkdir -p "$d"
  cp "$SRC" "$d/main.c"
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
ELF1="$(build_app kcmp_pass1 "")" || { echo "[FATAL] 第 1 遍构建失败" >&2; exit 2; }
P1_DIR="$OUT/pass1"; mkdir -p "$P1_DIR"
bash "$OBJDUMP_SH" --elf "$ELF1" "$P1_DIR" >/dev/null || { echo "[FATAL] 第 1 遍计数失败" >&2; exit 2; }
N_BASE="$(awk -F= '/^N_base=/{print $2}' "$P1_DIR/kcmp_static_summary.txt")"
N_VDOT="$(awk -F= '/^N_vdot=/{print $2}' "$P1_DIR/kcmp_static_summary.txt")"
[ -n "$N_BASE" ] && [ -n "$N_VDOT" ] || { echo "[FATAL] 第 1 遍计数解析失败" >&2; exit 2; }
echo "[pass1] N_base=$N_BASE N_vdot=$N_VDOT"

# ---------------- 第 2 遍：注入静态计数 ----------------
ELF2="$(build_app kcmp_pass2 "-DSTATIC_N_BASE=$N_BASE -DSTATIC_N_VDOT=$N_VDOT")" \
  || { echo "[FATAL] 第 2 遍构建失败（-D 注入）" >&2; exit 2; }
P2_DIR="$OUT/pass2"; mkdir -p "$P2_DIR"
bash "$OBJDUMP_SH" --elf "$ELF2" "$P2_DIR" >/dev/null || { echo "[FATAL] 第 2 遍计数失败" >&2; exit 2; }
N_BASE2="$(awk -F= '/^N_base=/{print $2}' "$P2_DIR/kcmp_static_summary.txt")"
N_VDOT2="$(awk -F= '/^N_vdot=/{print $2}' "$P2_DIR/kcmp_static_summary.txt")"
echo "[pass2] N_base=$N_BASE2 N_vdot=$N_VDOT2（复核第 1 遍）"

if [ "$N_BASE" != "$N_BASE2" ] || [ "$N_VDOT" != "$N_VDOT2" ]; then
  echo "[FATAL] 两遍计数不一致：pass1=$N_BASE/$N_VDOT pass2=$N_BASE2/$N_VDOT2" \
       "⇒ -D 注入改变了内核段，注入值不可信" >&2
  exit 2
fi

cp "$ELF2" "$OUT/perf_kernel_cmp.elf"
BIN="$AM_HOME/apps/kcmp_pass2/build/kcmp_pass2-riscv64-xs.bin"
[ -f "$BIN" ] || { echo "[FATAL] 缺 .bin：$BIN" >&2; exit 2; }
cp "$BIN" "$OUT/perf_kernel_cmp.bin"

# 运行镜像的静态计数作为**权威件**落盘（pass1 目录保留作复核）
cp "$P2_DIR/kcmp_static_base.txt" "$P2_DIR/kcmp_static_vdot.txt" \
   "$P2_DIR/kcmp_static_diff.txt" "$P2_DIR/kcmp_static_summary.txt" "$OUT/" 2>/dev/null || true

{
  echo "# build_kcmp.sh 产物（$(
    date '+%F %T')）"
  echo "src=$SRC"
  echo "src_sha256=$(sha256sum "$SRC" | cut -d' ' -f1)"
  echo "run_elf=$OUT/perf_kernel_cmp.elf"
  echo "run_elf_sha256=$(sha256sum "$OUT/perf_kernel_cmp.elf" | cut -d' ' -f1)"
  echo "run_bin=$OUT/perf_kernel_cmp.bin"
  echo "run_bin_sha256=$(sha256sum "$OUT/perf_kernel_cmp.bin" | cut -d' ' -f1)"
  echo "N_base=$N_BASE"
  echo "N_vdot=$N_VDOT"
  echo "two_pass_agree=yes"
  echo "injected=-DSTATIC_N_BASE=$N_BASE -DSTATIC_N_VDOT=$N_VDOT"
} >"$OUT/kcmp_build_summary.txt"

echo "[OK] 镜像：$OUT/perf_kernel_cmp.bin（sha256 $(sha256sum "$OUT/perf_kernel_cmp.bin" | cut -d' ' -f1)）"
exit 0
