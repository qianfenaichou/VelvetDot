#!/usr/bin/env bash
# 构建 vdot 用例与探针镜像（nexus-am ARCH=riscv64-xs）。
# 依赖：riscv64-unknown-elf-{gcc,ld,objcopy} 在 PATH 上；AM_HOME 指向 nexus-am 源码树。
# 两个必须（实测踩坑）：
#   1) MARCH 必须带 _v（AM 的 riscv64-xs.mk 默认 MARCH 无 V，vsetvli/vle8 会被 as 拒）；
#   2) 用例 asm 序言必须 `li t0,0x600; csrs mstatus,t0`（AM start.S 只开 FS 不开 VS，
#      否则第一条向量指令就按 SPEC §1.1 第六条（VS=OFF）陷入非法）。
# 用法：AM_HOME=/path/to/nexus-am bash design/verify/cases/build_cases.sh [输出目录]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE}"
AM_HOME="${AM_HOME:?需要 AM_HOME（nexus-am 源码树）}"
MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
CC_PREFIX="${CROSS_COMPILE:-riscv64-unknown-elf-}"
# 1.1 hello_identity 的 IP 在编译期注入（裸机 AM 无网络栈，见 hello_identity.c 文件头）。
# 默认 0.0.0.0 只是占位：镜像会额外打 WARN，10-build-emu.sh 的 1.1 判据也会拒收。
# 真实 IP 用法：HOST_IP="$(hostname -I | awk '{print $1}')" bash build_cases.sh
HOST_IP="${HOST_IP:-0.0.0.0}"
hello_invalid=0
if [ "$HOST_IP" = "0.0.0.0" ]; then
  hello_invalid=1
  echo "[WARN] HOST_IP 未注入（=0.0.0.0）：hello_identity.bin 只打印占位 IP ⇒ 本次产物判废，不得作为 1.1 交付证据（仅可留作构建/冒烟自检）" >&2
else
  # 给了 HOST_IP 就必须是点分四段 IPv4（每段 0..255）：否则 -DTARGET_IP 把垃圾写进镜像，
  # 「真实 IP」判据在编译期就被污染，且要等 10-build-emu.sh 冒烟阶段才拒收、白费一次构建。
  ip_bad=0
  case "$HOST_IP" in
    ''|*[!0-9.]*|.*|*.|*..*) ip_bad=1 ;;
  esac
  IFS=. read -r ip1 ip2 ip3 ip4 ip_extra <<<"$HOST_IP"
  [ -n "$ip4" ] && [ -z "$ip_extra" ] || ip_bad=1
  for ip_o in "$ip1" "$ip2" "$ip3" "$ip4"; do
    [ -n "$ip_o" ] || ip_bad=1
    [ "$ip_o" -le 255 ] 2>/dev/null || ip_bad=1
  done
  if [ "$ip_bad" -ne 0 ]; then
    echo "[FATAL] HOST_IP 不是合法 IPv4：'$HOST_IP'（示例 HOST_IP=\"\$(hostname -I | awk '{print \$1}')\"）" >&2
    exit 3
  fi
fi
command -v "${CC_PREFIX}gcc" >/dev/null || { echo "[FATAL] ${CC_PREFIX}gcc 不在 PATH"; exit 3; }

# gen.py 以相对路径写 .c 与 cases.json（open(f"{name}.c","w")），必须在本目录内执行，
# 否则源被写到调用者的 CWD、下面的 glob 只看到旧文件（静默编旧源）。
( cd "$HERE" && python3 gen.py >/dev/null )   # 由生成器产出用例源（期望值=算法 B）
# 用例源清单：vdot_*.c / p*.c 由 gen.py 生成或手写；hello_identity.c 是交付物 1.1 的证据镜像，
# 必须显式列入——旧版 glob 只取 vdot_*.c 与 p*.c，hello_identity.c 会被静默漏编、1.1 镜像永不产出。
# **排除 vdot_dualchain.c**（2026-11-06 双链实验）：它是**清单外独立测量**用例，且 `#include
# "dualchain_expected.h"` —— 该头由 `dualchain_check.py --emit-header` 从金模型生成，
# 只有 `build_dualchain.sh` 会先生成再编译；进本脚本会因缺头文件直接编译失败。
# 它的构建路径见 `design/verify/cases/build_dualchain.sh`，运行路径见 `96-run-dualchain.sh`。
sources=$(ls "$HERE"/vdot_*.c "$HERE"/p*.c "$HERE"/hello_identity.c 2>/dev/null | grep -v '/vdot_dualchain\.c$' || true)
[ -n "$sources" ] || { echo "[FATAL] 没有用例源"; exit 3; }
# 点名的源缺失时必须可见（不许静默跳过）
[ -f "$HERE/hello_identity.c" ] || \
  echo "[WARN] 缺源 $HERE/hello_identity.c ⇒ hello_identity 镜像不产出（1.1 证据需补源）"
mkdir -p "$OUT"
built=0
failed=0
failed_names=""
built_hello=0
hello_bin_built=0
for f in $sources; do
  n="$(basename "$f" .c)"
  if [ "$n" = "hello_identity" ]; then built_hello=1; fi
  d="$AM_HOME/apps/$n"; rm -rf "$d"; mkdir -p "$d"
  cp "$f" "$d/main.c"
  if [ "$n" = "hello_identity" ]; then
    # 1.1 证据镜像必须在应用 Makefile 里注入 TARGET_IP（命令行 CFLAGS+= 会覆盖 AM 自带
    # 的 -march/-mabi/-I，见 hello_identity.c 文件头）。make 变量 HOST_IP 由 make 展开，引号原样进编译器。
    cat >"$d/Makefile" <<MK
NAME = $n
SRCS = main.c
HOST_IP ?= $HOST_IP
CFLAGS += -DTARGET_IP='"\$(HOST_IP)"'
include \$(AM_HOME)/Makefile.app
MK
  else
    printf 'NAME = %s\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' "$n" > "$d/Makefile"
  fi
  # 单例失败不中断整批：把失败名收集起来最后统一报错（否则一个坏生成源会挡住后面的
  # hello_identity/perf 镜像）；退出码仍非 0，不掩盖失败。
  if ! make -s -C "$d" AM_HOME="$AM_HOME" ARCH=riscv64-xs CROSS_COMPILE="$CC_PREFIX" \
      MARCH="$MARCH" HOST_IP="$HOST_IP" image; then
    echo "[ERROR] 构建失败：$n（源 $f，见上方 make 输出）" >&2
    failed=$((failed + 1))
    failed_names="$failed_names $n"
    rm -rf "$d"
    continue
  fi
  cp "$d/build/$n-riscv64-xs.bin" "$OUT/$n.bin"
  if [ "$n" = "hello_identity" ]; then hello_bin_built=1; fi
  rm -rf "$d"
  built=$((built + 1))
done
echo "+ 构建镜像 $built 个 -> $OUT"
if [ "$failed" -ne 0 ]; then
  echo "[FATAL] $failed 个镜像构建失败：$failed_names（其余 $built 个已产出）" >&2
  exit 1
fi
if [ "$built_hello" -eq 0 ]; then
  echo "[WARN] hello_identity 未编（缺源 $HERE/hello_identity.c）⇒ 1.1 证据镜像缺失"
fi
# 占位 IP 的落盘产物明确判废：保留文件以便构建/冒烟自检，但不得作为 1.1 交付证据。
if [ "$hello_invalid" -eq 1 ] && [ "$hello_bin_built" -eq 1 ]; then
  echo "[WARN] $OUT/hello_identity.bin 为占位 IP 镜像（判废）：不得收入 stage1/1.1 或作为 1.1 交付证据；请以 HOST_IP=<本机真实 IPv4> 重建" >&2
fi
