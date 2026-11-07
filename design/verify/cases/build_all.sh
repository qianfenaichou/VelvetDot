#!/usr/bin/env bash
# build_all.sh — 一键产出 manifest.tsv 需要的**全部**用例镜像（manifest.tsv 全部镜像的统一构建入口）。
#
# 为什么需要它（2026-11-03）：
#   镜像源分两处：design/verify/cases/*.c（vdot_* / p*.c / hello_identity）与
#   design/verify/perf/*.c（perf_vdot / perf_base）。旧版两个脚本各编一半：
#     · cases/build_cases.sh 的 `p*.c` 只覆盖 perf_vadd/perf_vmacc
#     · perf/build.sh 原本覆盖 perf_vdot/perf_base
#   没有任何单一入口能保证「manifest 里每个镜像都来自最新源」，这就是「源新镜像旧」的复发路径。
#   本脚本顺序调用两者，最后按 manifest 逐行核对产物是否存在，缺一个就非 0 退出。
#
# 用法：
#   AM_HOME=/path/to/nexus-am \
#   HOST_IP="$(hostname -I | awk '{print $1}')" \
#     bash design/verify/cases/build_all.sh [输出目录]
#   输出目录默认 design/verify/cases（manifest 的 @IMG_DIR@ 默认就指向这里）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
HOST_IP="${HOST_IP:-0.0.0.0}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH"; exit 3; }

echo "== [1/2] 用例镜像（vdot_* / p* / hello_identity）=="
HOST_IP="$HOST_IP" CROSS_COMPILE="$CC_PREFIX" \
  bash "$HERE/build_cases.sh" "$OUT"

echo "== [2/2] perf 镜像（perf_vdot / perf_base / perf_vadd / perf_vmacc）=="
AM_HOME="$AM_HOME" CROSS_COMPILE="$CC_PREFIX" \
  bash "$HERE/../perf/build.sh" "$OUT"

# 产物核对：manifest 的每一行都必须有对应镜像（这条是「源新镜像旧」的机械判据）。
# 例外：vadd-microbench 用的 microbench.bin 是 XiangShan 仓库自带的**预编译** AM 负载
# （repos/XiangShan/ready-to-run/microbench.bin，md5 d6bd6228…），不是本包源码产物，
# 大/小写不变地随基线入库；缺了就从那里补一份，而不是去编。
echo "== 核对 manifest 产物 =="
PREBUILT_MICROBENCH="$(cd "$HERE/../../.." && pwd)/repos/XiangShan/ready-to-run/microbench.bin"
case "$OUT" in
  */) microbench_dst="${OUT}microbench.bin" ;;
  *)  microbench_dst="$OUT/microbench.bin" ;;
esac
if [ ! -f "$microbench_dst" ] && [ -f "$PREBUILT_MICROBENCH" ]; then
  cp "$PREBUILT_MICROBENCH" "$microbench_dst"
  echo "  [预编译] microbench.bin <- $PREBUILT_MICROBENCH（XiangShan 自带 AM 负载，非本包源码）"
fi
missing=0
while IFS=$'\t' read -r cid cls img extra; do
  case "${cid:-}" in ''|'#'*) continue ;; esac
  # manifest 用 @IMG_DIR@ 占位；这里换成实际输出目录
  path="${img//@IMG_DIR@/$OUT}"
  if [ ! -f "$path" ]; then
    echo "  [MISSING] $cid -> $path" >&2
    missing=$((missing + 1))
  fi
done <"$HERE/manifest.tsv"

if [ "$missing" -ne 0 ]; then
  echo "[FATAL] manifest 有 $missing 个镜像未产出（见上方 [MISSING]）" >&2
  exit 1
fi
echo "+ manifest 全部镜像齐备 -> $OUT"
# 同时报「镜像比源旧」的嫌疑：按 manifest 逐行推导源文件，覆盖 **gen.py 生成的
# vdot_*.c** 与手写源（旧版固定列 6 个手写源，vdot_ill_sew.c 比 .bin 晚 6 秒的
# 「源新镜像旧」因此漏报）。预编译 microbench 无本包源码，跳过。
stale=0
while IFS=$'\t' read -r cid cls img extra; do
  case "${cid:-}" in ''|'#'*) continue ;; esac
  bin="$(basename "$img" .bin)"
  src=""
  for cand in "$HERE/$bin.c" "$HERE/../perf/$bin.c"; do
    if [ -f "$cand" ]; then src="$cand"; break; fi
  done
  if [ -z "$src" ]; then
    echo "  [SKIP] $bin 无本包源码（预编译/非源码产物），不做新于检查"
    continue
  fi
  binpath="$OUT/$bin.bin"
  if [ -f "$binpath" ] && [ "$src" -nt "$binpath" ]; then
    echo "  [STALE] $binpath 早于源 $src" >&2
    stale=$((stale + 1))
  fi
done <"$HERE/manifest.tsv"
if [ "$stale" -ne 0 ]; then
  echo "[FATAL] $stale 个镜像比源码旧" >&2
  exit 1
fi
echo "+ 镜像均新于对应源码"
