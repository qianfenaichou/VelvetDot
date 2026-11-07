#!/usr/bin/env bash
# =============================================================================
# build_extra.sh — 构建 `manifest.extra.tsv` 需要的**全部**扩容用例镜像。
#
# 与 `build_cases.sh` / `build_all.sh` 的分工（三个入口互不替代）：
#   build_cases.sh  → 30 例主清单的 cases/*.bin（**本脚本不调用它，也不改它的产物**）
#   build_all.sh    → 主清单一键构建（本脚本不碰）
#   build_extra.sh  → 扩容清单 extra/*.bin（本脚本）
#
# 前置：`gen_extra.py` 已生成 extra/*.c（本脚本会先重跑一次，保证源与期望常量同步）。
# 判据：extra/*.c 每一份都编出 .bin；`manifest.extra.tsv` 每一行的镜像存在。
# 退出码：0 达标 / 1 有镜像构建失败或缺失 / 3 用法或环境错误
#
# 用法：
#   AM_HOME=/path/to/nexus-am CROSS_COMPILE=riscv64-unknown-elf- \
#     bash design/verify/cases/build_extra.sh [输出目录]
#   输出目录默认 design/verify/cases/extra（manifest.extra.tsv 的 @IMG_DIR@ 指向这里）
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/extra}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"

command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 3; }

echo "== [1/3] 生成器：gen_extra.py（期望值来自金模型 vdot_model.py）=="
( cd "$HERE" && python3 gen_extra.py )

echo "== [2/3] 逐例构建镜像（AM ARCH=riscv64-xs）=="
mkdir -p "$OUT"
sources=$(ls "$HERE"/extra/*.c 2>/dev/null || true)
[ -n "$sources" ] || { echo "[FATAL] extra/ 下没有 .c 源（先跑 gen_extra.py）" >&2; exit 3; }

built=0
failed=0
failed_names=""
for f in $sources; do
  n="$(basename "$f" .c)"
  d="$AM_HOME/apps/$n"
  rm -rf "$d"
  mkdir -p "$d"
  cp "$f" "$d/main.c"
  printf 'NAME = %s\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' "$n" >"$d/Makefile"
  if ! make -s -C "$d" AM_HOME="$AM_HOME" ARCH=riscv64-xs CROSS_COMPILE="$CC_PREFIX" \
      MARCH="$MARCH" HOST_IP=0.0.0.0 image; then
    echo "[ERROR] 构建失败：$n（源 $f）" >&2
    failed=$((failed + 1))
    failed_names="$failed_names $n"
    rm -rf "$d"
    continue
  fi
  cp "$d/build/$n-riscv64-xs.bin" "$OUT/$n.bin"
  rm -rf "$d"
  built=$((built + 1))
done
echo "+ 构建镜像 $built 个 -> $OUT"

echo "== [3/3] 按 manifest.extra.tsv 核对产物 =="
missing=0
while IFS=$'\t' read -r cid cls img extra; do
  case "${cid:-}" in ''|'#'*) continue ;; esac
  path="${img//@IMG_DIR@/$OUT}"
  if [ ! -f "$path" ]; then
    echo "  [MISSING] $cid -> $path" >&2
    missing=$((missing + 1))
  fi
done <"$HERE/manifest.extra.tsv"

if [ "$failed" -ne 0 ]; then
  echo "[FATAL] $failed 个镜像构建失败：$failed_names" >&2
  exit 1
fi
if [ "$missing" -ne 0 ]; then
  echo "[FATAL] manifest.extra.tsv 有 $missing 个镜像未产出" >&2
  exit 1
fi
echo "+ manifest.extra.tsv 全部镜像齐备（$built 个）"
