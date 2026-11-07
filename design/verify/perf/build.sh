#!/usr/bin/env bash
# 构建 perf 镜像（nexus-am app 形式，ARCH=riscv64-xs）。
# 依赖：riscv64-unknown-elf-* 工具链在 PATH 上；AM_HOME 指向 nexus-am 源码树。
# 说明：nexus-am 的 am/arch/isa/riscv64.mk 默认前缀是 riscv64-unknown-linux-gnu-，这里显式覆盖成 elf 前缀。
#
# 用法：AM_HOME=/path/to/nexus-am bash design/verify/perf/build.sh [输出目录]
# 产物：<out>/{perf_vdot,perf_base,perf_vadd,perf_vmacc}.bin（供 emu --no-diff 运行）
#
# 为什么这里也编 perf_vadd/perf_vmacc（2026-11-03）：
#   四个 perf 镜像的源分两处 —— perf_vdot/perf_base 在本目录，perf_vadd/perf_vmacc 在
#   design/verify/cases/。旧版只有 cases/build_cases.sh 编后两个、本脚本编前两个，
#   没有任何单一入口能保证「四个镜像都来自最新源」，正是「源新镜像旧」的复发路径。
#   现在本脚本一次产出四个，且用 build_all.sh 把两条链串起来。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY_DIR="$(cd "$HERE/.." && pwd)"
OUT="${1:-$HERE/bin}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH"; exit 3; }

mkdir -p "$OUT"
built=0
failed=0
failed_names=""

build_one() { # $1=源文件 $2=app 名
  local src="$1" app="$2" dst="$AM_HOME/apps/$2"
  [ -f "$src" ] || { echo "[ERROR] 缺源 $src" >&2; failed=$((failed + 1)); failed_names="$failed_names $app"; return 0; }
  rm -rf "$dst"; mkdir -p "$dst"
  cp "$src" "$dst/main.c"
  cat >"$dst/Makefile" <<MK
NAME = $app
SRCS = main.c
include \$(AM_HOME)/Makefile.app
MK
  echo "+ build $app（源 $src）"
  # AM 的 riscv64-xs.mk 默认 MARCH 不含 V；vsetvli/vle8/vmv.x.s 需要 _v，这里显式补上。
  if ! make -s -C "$dst" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
      CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image; then
    echo "[ERROR] 构建失败：$app（源 $src）" >&2
    failed=$((failed + 1)); failed_names="$failed_names $app"
    rm -rf "$dst"
    return 0
  fi
  cp "$dst/build/$app-riscv64-xs.bin" "$OUT/$app.bin"
  echo "  -> $OUT/$app.bin ($(stat -c%s "$OUT/$app.bin") bytes)"
  rm -rf "$dst"
  built=$((built + 1))
}

build_one "$HERE/perf_vdot.c"             perf_vdot
build_one "$HERE/perf_base.c"             perf_base
build_one "$VERIFY_DIR/cases/perf_vadd.c" perf_vadd
build_one "$VERIFY_DIR/cases/perf_vmacc.c" perf_vmacc
# perf_base_chain 必须**点名**构建，不能只靠 cases/build_cases.sh 的 `p*.c` 通配符顺带产出：
# `p*` 目前恰好匹配 `perf_*.c`，但一旦有人把通配收紧成 `p[0-9]*.c`（很自然的清理），
# 该镜像会**静默**从构建链掉出。
# 口径决定（2026-11-04，口径表见 stage3/3.3/report.md §1）：perf_base_chain **已从 manifest.tsv 移出**
#   （保持独立测量，不并入 30 例官方回归清单）⇒ build_all.sh 的「镜像齐备 / 镜像新于源码」
#   两项检查**不再覆盖**它。改 perf_base_chain.c 后必须手工重建并核对 md5
#   （实测：仓库件 md5 `8c5538c9…` == 远端运行件 md5，见
#   results/difftest/b3/provenance/91-b3-provenance.txt §P2/P3）。
build_one "$VERIFY_DIR/cases/perf_base_chain.c" perf_base_chain

echo "+ 构建 perf 镜像 $built 个 -> $OUT"
if [ "$failed" -ne 0 ]; then
  echo "[FATAL] $failed 个 perf 镜像构建失败：$failed_names" >&2
  exit 1
fi
