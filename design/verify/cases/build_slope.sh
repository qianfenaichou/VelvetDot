#!/usr/bin/env bash
# =============================================================================
# build_slope.sh — perf_base_slope 镜像构建（单遍，无 -D 注入）
#
# 为什么单遍：本用例不需要「静态计数注入」（那是 perf_kernel_cmp 的两遍做法），
# 自检全靠运行期读回值 vs 软件模型，故一次编译即可；但**必须**把源 sha256 与产物
# sha256 一起落盘，供事后核对「跑的是这份源」。
#
# 为什么不进 build_all.sh：manifest.tsv 已冻结 30 行（a90d1071…），
# perf_base_slope 是**清单外独立测量项**（同 perf_base_chain / perf_kernel_cmp 的口径裁定，
# 见 stage3/3.3/report.md §1）。把它塞进 manifest 会让 --full 选中它、改变回归口径。
#
# 用法：
#   AM_HOME=/path/to/nexus-am bash design/verify/cases/build_slope.sh [输出目录]
#   # 昆山：AM_HOME=~/core/src/nexus-am bash build_slope.sh ~/core/test/bin
# 产物：<out>/perf_base_slope.bin（运行镜像）+ <out>/perf_base_slope.build.txt（源/产物 sha256）
# 退出码：0 成功 / 2 前置缺失或构建失败 / 3 用法错误
#
# 注意（ABI）：昆山的 xpack `riscv-none-elf-gcc 13.2.0` **默认 mabi=ilp32**（实测 `-Q --help=target`
#   → `-mabi= ilp32`、`-march= rv32imac`），而 AM 的 `am/arch/isa/riscv64.mk` 只传 `-march`、
#   不传 `-mabi` ⇒ 只给 rv64 的 MARCH 会报 `cc1: error: ABI requires '-march=rv32'`
#   （2026-11-06 实测复现）。故 MARCH 变量末尾追加 `-mabi=<MABI>`（同
#   `core-package/scripts/30-hello-nodeip.sh:141-170` 的 ccwrap 与 `design/verify/cases/build_llm_attn.sh:41`
#   的先例：`MARCH="… -mabi=lp64d"`）。MABI 可覆盖，默认 `lp64d`。
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MABI="${MABI:-lp64d}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt -mabi=$MABI}"
SRC="$HERE/perf_base_slope.c"
APP="perf_base_slope"

command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
[ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
[ -d "$AM_HOME" ] || { echo "[FATAL] AM_HOME 不存在：$AM_HOME" >&2; exit 2; }
mkdir -p "$OUT"

D="$AM_HOME/apps/$APP"
rm -rf "$D"; mkdir -p "$D"
cp "$SRC" "$D/main.c"
{
  printf 'NAME = %s\nSRCS = main.c\n' "$APP"
  # EXTRA_CFLAGS 用于冒烟镜像（如 -DROUNDS=2）：正式镜像必须不带，否则 ROUNDS 与脚本判据 ②/③ 不符。
  [ -n "${EXTRA_CFLAGS:-}" ] && printf 'CFLAGS += %s\n' "$EXTRA_CFLAGS"
  printf 'include $(AM_HOME)/Makefile.app\n'
} >"$D/Makefile"

if ! make -s -C "$D" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
      CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image; then
  echo "[FATAL] 构建失败：$APP（源 $SRC）" >&2
  exit 2
fi

BIN_SRC="$D/build/$APP-riscv64-xs.bin"
ELF_SRC="$D/build/$APP-riscv64-xs.elf"
[ -f "$BIN_SRC" ] || { echo "[FATAL] 缺产物 $BIN_SRC" >&2; exit 2; }
cp "$BIN_SRC" "$OUT/$APP.bin"
[ -f "$ELF_SRC" ] && cp "$ELF_SRC" "$OUT/$APP.elf"

{
  echo "# build_slope.sh 产物（$(date '+%F %T')）"
  echo "src=$SRC"
  echo "src_sha256=$(sha256sum "$SRC" | cut -d' ' -f1)"
  echo "run_bin=$OUT/$APP.bin"
  echo "run_bin_sha256=$(sha256sum "$OUT/$APP.bin" | cut -d' ' -f1)"
  echo "run_bin_bytes=$(stat -c %s "$OUT/$APP.bin")"
  echo "march=$MARCH"
  echo "toolchain=$("${CC_PREFIX}gcc" --version | head -1)"
  echo "am_home=$AM_HOME"
} >"$OUT/$APP.build.txt"

echo "[OK] $OUT/$APP.bin（sha256 $(sha256sum "$OUT/$APP.bin" | cut -d' ' -f1)）"
exit 0
