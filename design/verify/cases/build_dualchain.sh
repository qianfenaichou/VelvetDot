#!/usr/bin/env bash
# =============================================================================
# build_dualchain.sh — vdot_dualchain 的两个镜像（主镜像 + G0 反例）一次建成
#
# 为什么单独一份（不进 build_all.sh）：
#   `build_all.sh` 产出的是 manifest.tsv 需要的**全部**镜像；vdot_dualchain 是
#   **清单外独立测量**（口径同 perf_base_chain / perf_kernel_cmp），进 build_all 会
#   让「manifest 每行都有镜像」这条判据混入非清单件。故单列一份，只服务 96 号作业。
#
# 为什么期望值要过一遍 Python：
#   用例的 16 条功能期望必须来自金模型链：vdot 步由 `design/verify/vdot_model.py`（语义事实源）、
#   vmacc/vadd 步由 `design/verify/cases/dualchain_check.py` 按标准 RVV 逐 lane 复算，
#   不允许在 C 里手抄常量。本脚本调 `dualchain_check.py --emit-header` 生成
#   `dualchain_expected.h`，再把它和 .c 一起拷进 AM app 目录编译。
#   同口径对照三臂（M9 vdot 依赖链 / M10 标准 RVV 五指令链 / M11 空循环 control）只做计时；
#   M9/M10 的「跑 1 步」功能自检复用金模型的 `DCW_M3`（= 单次 dot(a,b)），不新增期望值。
#
# 产物（默认 <out> = design/verify/cases）：
#   dualchain_expected.h            金模型生成的期望头（含 DUALCHAIN_EXPECTED_SHA256）
#   vdot_dualchain.bin              主镜像
#   vdot_dualchain_g0.bin           G0 反例（-DDC_G0=1，期望翻转 1 bit）
#   dualchain_build_summary.txt     两镜像 sha256/md5 + 源码 sha256 + 工具链版本 + 编码核对
#   dualchain_objdump.txt           主镜像反汇编（含 vdot 的 .4byte 展开，人工核对编码）
#
# 用法：
#   AM_HOME=/path/to/nexus-am CROSS_COMPILE=<riscv64-unknown-elf-> \
#     bash design/verify/cases/build_dualchain.sh [输出目录]
# 退出码：0 成功 / 2 前置缺失或编码核对失败 / 3 用法错误
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-$HERE}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
# 站点工具链的默认 ABI 是 rv32（实测昆山 xpack 13.2.0：`gcc -Q --help=target` → `-mabi= ilp32`），
# 而 AM 的 am/arch/isa/riscv64.mk 只给 `-march=$(MARCH)`、不给 `-mabi` ⇒ 必须显式补 lp64d，
# 否则报 `cc1: error: ABI requires '-march=rv32'`。**必须走环境变量**（make 的 `CFLAGS +=` 才会累加）；
# 用命令行 `CFLAGS+=…` 会整体替换掉 CFLAGS（连 -march 一起丢），反而报
# `requested ABI requires '-march' to subsume the 'D' extension`（两种写法均已实测）。
ABI_FLAGS="${ABI_FLAGS:--mabi=lp64d}"
SRC="$HERE/vdot_dualchain.c"
CHECKER="$HERE/dualchain_check.py"

command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH" >&2; exit 2; }
command -v python3 >/dev/null || { echo "[FATAL] 缺 python3" >&2; exit 2; }
[ -f "$SRC" ] || { echo "[FATAL] 缺源 $SRC" >&2; exit 2; }
[ -f "$CHECKER" ] || { echo "[FATAL] 缺 $CHECKER" >&2; exit 2; }
[ -d "$AM_HOME" ] || { echo "[FATAL] AM_HOME 不存在：$AM_HOME" >&2; exit 2; }
mkdir -p "$OUT"

HDR="$OUT/dualchain_expected.h"
echo "== [1/4] 金模型生成期望头 =="
if ! python3 -I "$CHECKER" --emit-header "$HDR" >"$OUT/dualchain_emit.log" 2>&1; then
  echo "[FATAL] 期望头生成失败（见 $OUT/dualchain_emit.log）" >&2
  tail -20 "$OUT/dualchain_emit.log" >&2
  exit 2
fi
grep -E 'DUALCHAIN_CROSSCHECK (falsifiable|header)' "$OUT/dualchain_emit.log" || true
HDR_SHA="$(sha256sum "$HDR" | cut -d' ' -f1)"
echo "  header=$HDR sha256=$HDR_SHA"
# 头文件里必须带 DUALCHAIN_EXPECTED_SHA256（防止「头文件是旧的 / 手写的」）
grep -q 'DUALCHAIN_EXPECTED_SHA256' "$HDR" || { echo "[FATAL] 头文件缺 DUALCHAIN_EXPECTED_SHA256" >&2; exit 2; }

build_one() { # $1=app 名 $2=额外 CFLAGS（可空）→ 成功打印 bin 路径，失败返回 1
  local app="$1" extra="${2:-}" d="$AM_HOME/apps/$1"
  rm -rf "$d"; mkdir -p "$d"
  cp "$SRC" "$d/main.c"
  cp "$HDR" "$d/dualchain_expected.h"
  {
    printf 'NAME = %s\nSRCS = main.c\n' "$app"
    printf 'CFLAGS += -I.\n'
    [ -n "$extra" ] && printf 'CFLAGS += %s\n' "$extra"
    printf 'include $(AM_HOME)/Makefile.app\n'
  } >"$d/Makefile"
  # ABI_FLAGS 走环境变量（见文件头的实测说明）：AM 的 riscv64.mk 不带 -mabi
  CFLAGS="$ABI_FLAGS" ASFLAGS="$ABI_FLAGS" \
  make -s -C "$d" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
       CROSS_COMPILE="$CC_PREFIX" MARCH="$MARCH" image >"$d/build.log" 2>&1 || {
    echo "[ERROR] 构建失败：$app" >&2
    tail -20 "$d/build.log" >&2
    return 1
  }
  cp "$d/build/$app-riscv64-xs.bin" "$OUT/$app.bin" || return 1
  cp "$d/build/$app-riscv64-xs.elf" "$OUT/$app.elf" 2>/dev/null || true
  printf '%s\n' "$OUT/$app.bin"
}

echo "== [2/4] 主镜像 =="
MAIN_BIN="$(build_one vdot_dualchain "")" || exit 2
echo "  $MAIN_BIN"

echo "== [3/4] G0 反例镜像（-DDC_G0=1）=="
G0_BIN="$(build_one vdot_dualchain_g0 "-DDC_G0=1")" || exit 2
echo "  $G0_BIN"

echo "== [4/4] 编码核对（objdump）=="
OBJDUMP="${CC_PREFIX}objdump"
command -v "$OBJDUMP" >/dev/null || { echo "[FATAL] 缺 $OBJDUMP" >&2; exit 2; }
"$OBJDUMP" -d "$OUT/vdot_dualchain.elf" >"$OUT/dualchain_objdump.txt" 2>&1 || {
  echo "[FATAL] objdump 失败" >&2; exit 2; }
# .4byte 展开后 objdump 对未知编码会打 `.insn 4, 0x3a20a1d7` 或 `unknown`。
# 判据：源里 VDOT_ENC 的四种 (vd,vs1,vs2) 组合都必须以 0x...57 形式在反汇编里出现，
# 且 0x3a20a1d7（vd=3,vs1=1,vs2=2）必须在场（SPEC.md §2.1 的机器码示例）。
enc_hits_main="$(grep -c '3a20a1d7' "$OUT/dualchain_objdump.txt" || true)"
enc_hits_57="$(grep -coE '0x[0-9a-f]{6}57' "$OUT/dualchain_objdump.txt" || true)"
# 更稳的机械判据：数「以 57 结尾」的 .insn 行（objdump 对自定义编码打 .insn 或 unknown）
enc_insn="$(grep -cE '\.insn|unknown' "$OUT/dualchain_objdump.txt" || true)"
echo "  objdump: 3a20a1d7_hits=$enc_hits_main 0x...57_hits=$enc_hits_57 insn_or_unknown=$enc_insn"

TOOL_VER="$("${CC_PREFIX}gcc" --version 2>/dev/null | head -1)"
SRC_SHA="$(sha256sum "$SRC" | cut -d' ' -f1)"
CHECKER_SHA="$(sha256sum "$CHECKER" | cut -d' ' -f1)"
{
  echo "schema=dualchain-build/1"
  echo "built_at=$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  echo "host=$(hostname)"
  echo "toolchain=$TOOL_VER"
  echo "march=$MARCH"
  echo "source=$SRC"
  echo "source_sha256=$SRC_SHA"
  echo "checker_sha256=$CHECKER_SHA"
  echo "expected_header=$HDR"
  echo "expected_header_sha256=$HDR_SHA"
  echo "binary_main=$MAIN_BIN"
  echo "binary_main_sha256=$(sha256sum "$MAIN_BIN" | cut -d' ' -f1)"
  echo "binary_main_md5=$(md5sum "$MAIN_BIN" | cut -d' ' -f1)"
  echo "binary_g0=$G0_BIN"
  echo "binary_g0_sha256=$(sha256sum "$G0_BIN" | cut -d' ' -f1)"
  echo "binary_g0_md5=$(md5sum "$G0_BIN" | cut -d' ' -f1)"
  echo "objdump_3a20a1d7_hits=$enc_hits_main"
  echo "objdump_insn_or_unknown=$enc_insn"
  echo "note=期望值由 dualchain_check.py 生成（vdot 步经 vdot_model.py 金模型；vmacc/vadd 步逐 lane 复算）；C 侧不含手抄 want 常量"
} | tee "$OUT/dualchain_build_summary.txt"

# 硬判据：机器码示例必须在反汇编里出现（编码宏与发射字节同源，防「宏改了但没发这条」）
if [ "${enc_hits_main:-0}" -lt 1 ]; then
  echo "[FATAL] 反汇编里找不到 3a20a1d7（SPEC.md §2.1 的机器码示例）⇒ 编码核对未通过" >&2
  exit 2
fi
echo "[OK] 两镜像构建完成：$OUT/vdot_dualchain.bin、$OUT/vdot_dualchain_g0.bin"
