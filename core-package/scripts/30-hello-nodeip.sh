#!/usr/bin/env bash
# =============================================================================
# 验证项：1.1 hello 身份镜像的「执行节点 IP」重建 + emu 冒烟（30-hello-nodeip v2）
#
# 用途（为什么要有这个脚本）：
#   官方交付物 1.1 要求终端输出里带**本机真实 IP**。nexus-am 是裸机 AM、无网络栈，
#   运行期拿不到地址 ⇒ IP 只能在**编译期**注入（-DTARGET_IP）。上一版把编译放在构建机上，
#   注入的是构建机地址（192.168.0.4），与「运行环境 IP」口径不符；
#   本脚本把「取 IP + 编译 + 冒烟」整体搬进**计算节点作业步**里：
#   节点内 hostname -I 取首字段 → 节点内重编 hello_identity → 节点内跑 10-build-emu.sh 冒烟。
#   实测依据（注意版本）：作业 126681977（节点 a11r1n01），日志
#   results/emu/30-hello-nodeip-20261103T150703.log 与 results/logs/126681977_t1c_hello_ip.out（同值），
#   镜像 md5 0086e33b1739c297dc0c7ae685473e6b，身份串 "hello xiangshan, I am XinXiangXiangRong,
#   IP: 10.1.11.2"，HIT GOOD TRAP=1 / ABORT=0。
#   注意：那份归档日志由**更早版本**脚本产出；现版新增的 ccwrap 包装器（`-mabi=lp64`）与
#     「清 AM 静态库缓存」两步**尚未在计算节点上实跑过**（本机用 riscv64-unknown-elf-gcc 14.2.0
#     跑了同构构建，但 14.2.0 默认已是 lp64 ⇒ 未真正验证 -mabi 注入的效果）。因此
#     **不得**把该归档日志当成本脚本的输出证据；新版首次节点实跑后应以新日志为准。
#
# 两个必须处理的坑（本脚本已在代码中处理，理由写在对应位置的注释里）：
#   ① nexus-am 的 am/arch/isa/riscv64.mk 只给 -march=$(MARCH)，**没有 -mabi**；
#      而 xpack riscv-none-elf-gcc 13.2.0 默认 ABI 是 ilp32（rv32 软浮点），
#      只给 -march=rv64gcv_* ⇒ `cc1: error: ABI requires '-march=rv32'`（实测，见 stage1/1.3-vadd/README.md §坑 1）。
#      处置：用 ccwrap 包装器给所有编译调用强制追加 -mabi=lp64（app / lib-am / lib-klib 全部一致）。
#   ② AM 静态库缓存是**按 ABI 编译**的：若此前按别的 ABI 编过（ilp32），改为 lp64 会链接失败
#      （`can't link soft-float modules with double-float modules` 一类，见 stage1/1.3-vadd/README.md §坑 1）。
#      处置：重建前清掉 $AM_HOME/am/build 与 $AM_HOME/libs/klib/build，整棵树按同一 ABI 重编。
#
# 用法（必须在计算节点的作业步里跑；登录节点无 SLURM_JOB_ID ⇒ 脚本拒绝执行）：
#   sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 \
#          -J hello-nodeip -o results/logs/%x-%j.out \
#          core-package/scripts/30-hello-nodeip.sh \
#          --src-root /public/home/$USER/core/src \
#          --am-home   /public/home/$USER/core/src/nexus-am
#   参数：--src-root DIR（默认 $CORE_DIR/src）  --am-home DIR（默认 $CORE_DIR/src/nexus-am）
#         --src FILE（hello_identity.c，默认 $AM_HOME/apps/hello_identity/main.c）
#         --image-out FILE（默认 $CORE_DIR/.upload/nodeimg/hello_identity.bin）
#         --jobs N（默认 32）  --emu-threads N  --jvm-xmx SIZE（默认 40G）
#         --keep-am-cache（不清 AM 静态库缓存；仅在确认缓存已按当前 ABI 编译时使用）
#         --dry-run（只打印计划，不编译不冒烟）
# 判据：① 节点内取到的 IP 是合法 IPv4 且非占位/回环/链路本地；
#       ② 节点内重编出 hello_identity 镜像，且镜像里能找到注入的 IP 字符串；
#       ③ 10-build-emu.sh 退出码 0（其 JSON 的 smoke_hello_identity=达标）。
# 产物：results/emu/30-hello-nodeip-<runid>.log；results/emu/10-build-<runid>.{log,json}（子脚本）
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P0-emu"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="1.1 hello 身份镜像（节点 IP）重建 + emu 冒烟"

CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
SRC_ROOT="${SRC_ROOT:-$CORE_DIR/src}"
AM_HOME="${AM_HOME:-$SRC_ROOT/nexus-am}"
APP_DIR=""
SRC_FILE=""
IMAGE_OUT=""
JOBS=32
EMU_THREADS=""
JVM_XMX="40G"
KEEP_AM_CACHE=0
DRY_RUN=0
NODE_IP=""
CCWRAP_DIR=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/emu"
readonly LOG_FILE="$OUT_DIR/30-hello-nodeip-$RUN_ID.log"
# AM 的 MARCH 与 design/verify/cases/build_cases.sh:13 同一串（必须带 _v，否则 vsetvli 等会被 as 拒）；
# 与本仓库其它镜像保持一致，产物才可与远端/仓库里的同名镜像对 md5。
readonly MARCH="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
# 交叉工具链前缀：xpack riscv-none-elf-*（13.2.0）。它的默认 ABI 是 ilp32 ⇒ 必须由 ccwrap 追加 -mabi=lp64。
readonly REAL_CROSS="${REAL_CROSS:-riscv-none-elf-}"
readonly ABI="${ABI:-lp64}"

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
die() { echo "[FATAL] $*" >&2; exit 3; }

# 记账脚本定位：昆山实际落位是 $CORE_DIR/core-package/scripts/（验证包在 ~/core/core-package/，
# 平台落位实测），$CORE_DIR/scripts/ 不存在 ⇒ 旧 trap 恒不命中。
budget_log_script() {
  local c here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for c in "$CORE_DIR/core-package/scripts/90-budget-log.sh" \
           "$CORE_DIR/scripts/90-budget-log.sh" \
           "$here/90-budget-log.sh"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# 同上：10-build-emu.sh 的位置（core-package/scripts/ → scripts/ → 与本脚本同目录）
find_build_script() {
  local c here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for c in "$CORE_DIR/core-package/scripts/10-build-emu.sh" \
           "$CORE_DIR/scripts/10-build-emu.sh" \
           "$here/10-build-emu.sh"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# 环境：交叉工具链（xpack riscv-none-elf-*）只在 source $TOOLS_DIR/env.sh 之后才在 PATH 上
# （env.sh 末尾 append 了 xpack 的 bin 目录，见工具链记录）。
# 这里**静默** source（不打印「已 source」行：归档日志 30-hello-nodeip-20261103T150703.log 里
# 这一行是子脚本 10-build-emu.sh 打的，父脚本那一侧没有这一行）。
source_env() {
  if [ -r "$TOOLS_DIR/env.sh" ]; then . "$TOOLS_DIR/env.sh"; fi
  hash -r
}

# IPv4 合法性：四段、每段 0..255、无多余字符（与 design/verify/cases/build_cases.sh:24-43 同口径）
ip_is_valid() {
  local ip="$1" bad=0 o
  case "$ip" in
    ''|*[!0-9.]*|.*|*.|*..*) bad=1 ;;
  esac
  local -a parts
  IFS=. read -r -a parts <<<"$ip"
  [ "${#parts[@]}" -eq 4 ] || bad=1
  for o in "${parts[@]:-}"; do
    [ -n "$o" ] || bad=1
    [ "$o" -le 255 ] 2>/dev/null || bad=1
  done
  return $bad
}

# ccwrap：给所有交叉工具调用统一追加 -mabi=<ABI>。
# AM 的 am/arch/isa/riscv64.mk 只给 -march=$(MARCH)、没有 -mabi；xpack riscv-none-elf-gcc 13.2.0
# 默认 ilp32（rv32）⇒ 只给 -march=rv64gcv_* 会报 `cc1: error: ABI requires '-march=rv32'`。
# 包装器按 basename($0) 分派到真实工具，gcc/g++ 前置 -mabi=lp64，其余工具（ld/ar/objcopy/…）不加。
make_ccwrap() {
  CCWRAP_DIR="$CORE_DIR/.upload/ccwrap-$RUN_ID"
  mkdir -p "$CCWRAP_DIR"
  local wrapper="$CCWRAP_DIR/ccwrap"
  cat >"$wrapper" <<WRAP
#!/usr/bin/env bash
# 由 core-package/scripts/30-hello-nodeip.sh 生成：强制给编译调用追加 -mabi=$ABI。
# 理由：AM 的 riscv64.mk 不带 -mabi，而 xpack riscv-none-elf-gcc 13.2.0 默认 ilp32（rv32）。
set -euo pipefail
self="\$(basename "\$0")"
tool="\${self#ccwrap-}"
real="${REAL_CROSS}\${tool}"
# real 是 PATH 里的裸名字：不能用 [ -x "\$real ]（那查的是当前目录，不是 PATH），必须 command -v 解析。
real_path="\$(command -v "\$real" || true)"
[ -n "\$real_path" ] || { echo "[FATAL] ccwrap: 找不到真实工具 \$real（PATH 里没有）" >&2; exit 3; }
case "\$tool" in
  gcc|g++)
    exec "\$real_path" -mabi=$ABI "\$@"
    ;;
  *)
    exec "\$real_path" "\$@"
    ;;
esac
WRAP
  chmod +x "$wrapper"
  local t
  for t in gcc g++ ld ar objcopy objdump readelf; do
    ln -sf ccwrap "$CCWRAP_DIR/ccwrap-$t"
  done
}

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --src-root) SRC_ROOT="${2:?--src-root 需要参数}"; shift 2 ;;
      --am-home) AM_HOME="${2:?--am-home 需要参数}"; shift 2 ;;
      --src) SRC_FILE="${2:?--src 需要参数}"; shift 2 ;;
      --image-out) IMAGE_OUT="${2:?--image-out 需要参数}"; shift 2 ;;
      --jobs) JOBS="${2:?--jobs 需要参数}"; shift 2 ;;
      --emu-threads) EMU_THREADS="${2:?--emu-threads 需要参数}"; shift 2 ;;
      --jvm-xmx) JVM_XMX="${2:?--jvm-xmx 需要参数}"; shift 2 ;;
      --keep-am-cache) KEEP_AM_CACHE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1（用 --help）" ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] 本脚本必须在计算节点的作业步里执行（登录节点取到的不是执行节点 IP）。" >&2
    echo "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 ${SCRIPT_PATH}" >&2
    exit 3
  fi

  APP_DIR="${APP_DIR:-$AM_HOME/apps/hello_identity}"
  SRC_FILE="${SRC_FILE:-$APP_DIR/main.c}"
  IMAGE_OUT="${IMAGE_OUT:-$CORE_DIR/.upload/nodeimg/hello_identity.bin}"

  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR" "$CORE_DIR/results/logs"
  log "===== 30-hello-nodeip v2 开始 job=$SLURM_JOB_ID ====="
  source_env

  # ---- 1. 节点内取 IP ----
  log "hostname=$(hostname) partition=${SLURM_JOB_PARTITION:-unknown} nodelist=${SLURM_JOB_NODELIST:-$(hostname)}"
  local ips
  ips="$(hostname -I 2>/dev/null || true)"
  log "hostname -I 输出：$ips"
  NODE_IP="$(printf '%s\n' "$ips" | awk 'NF{print $1; exit}')"
  if ! ip_is_valid "$NODE_IP"; then
    die "节点内 hostname -I 没给出合法 IPv4（得到：'${NODE_IP:-<none>}'；原始输出：'$ips'）"
  fi
  case "$NODE_IP" in
    0.0.0.0|255.255.255.255) die "节点 IP 是占位/广播地址（$NODE_IP），不得作为 1.1 证据" ;;
    127.*|169.254.*)         die "节点 IP 是回环/链路本地（$NODE_IP），不是真实节点地址" ;;
  esac
  log "NODE_IP = $NODE_IP（IP 来源口径：执行节点 hostname -I 第一个字段；与构建机 IP 无关——即使两者同值，口径仍是「取执行节点」）"

  # ---- 2. 编译器与 ccwrap ----
  command -v "${REAL_CROSS}gcc" >/dev/null 2>&1 || \
    die "找不到 ${REAL_CROSS}gcc（先 source $TOOLS_DIR/env.sh）"
  log "交叉编译器：$("${REAL_CROSS}gcc" --version 2>/dev/null | head -n1)（包装器加 -mabi=$ABI，理由见脚本头）"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] 计划：ccwrap -mabi=$ABI → 重编 $APP_DIR（HOST_IP=$NODE_IP）→ 10-build-emu.sh --image"
    exit 0
  fi

  make_ccwrap
  log "ccwrap 已就绪：$CCWRAP_DIR（-mabi=$ABI；AM 的 riscv64.mk 不带 -mabi，xpack 默认 ilp32）"

  # ---- 3. 应用 Makefile（IP 编译期注入）----
  # AM_HOME 的前置校验必须在下面 rm -rf 缓存之前：AM_HOME 写错时不能盲删。
  [ -f "$AM_HOME/Makefile.app" ] || \
    die "AM_HOME 不对（缺 $AM_HOME/Makefile.app）：$AM_HOME（--am-home 可指定 nexus-am 源码树）"
  [ -f "$SRC_FILE" ] || \
    die "找不到 hello_identity 源：$SRC_FILE（用 --src 指定；仓库件在 design/verify/cases/hello_identity.c）"
  mkdir -p "$APP_DIR"
  cp "$SRC_FILE" "$APP_DIR/main.c"
  cat >"$APP_DIR/Makefile" <<MK
NAME = hello_identity
SRCS = main.c
HOST_IP ?= $NODE_IP
CFLAGS += -DTARGET_IP='"\$(HOST_IP)"'
include \$(AM_HOME)/Makefile.app
MK
  log "应用 Makefile：HOST_IP=$NODE_IP（CFLAGS += -DTARGET_IP）"

  # ---- 4. 节点内重编（清 AM 静态库缓存：缓存里的对象是按旧 ABI 编的）----
  if [ "$KEEP_AM_CACHE" = "0" ]; then
    rm -rf "$AM_HOME/am/build" "$AM_HOME/libs/klib/build"
    log "已清空 AM 静态库缓存（am/build、libs/klib/build），整棵树按 -mabi=$ABI 重编"
  fi
  local img
  img="$APP_DIR/build/hello_identity-riscv64-xs.bin"
  rm -f "$img"
  if ! make -C "$APP_DIR" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
        CROSS_COMPILE="$CCWRAP_DIR/ccwrap-" MARCH="$MARCH" HOST_IP="$NODE_IP" image; then
    log "[FATAL] hello_identity 编译失败（见上方 make 输出）"
    exit 1
  fi
  [ -f "$img" ] || die "编译成功但没有产物：$img"
  local sz md5
  sz="$(stat -c %s "$img")"
  md5="$(md5sum "$img" | cut -d' ' -f1)"
  log "节点内重建：$sz 字节 md5=$md5"

  if strings "$img" | grep -qF "$NODE_IP"; then
    log "镜像内含 IP 字符串 $NODE_IP：是"
  else
    log "[FATAL] 镜像里找不到注入的 IP 字符串 $NODE_IP（-DTARGET_IP 没生效？）"
    exit 1
  fi

  # ---- 5. 交给 10-build-emu.sh 冒烟 ----
  mkdir -p "$(dirname "$IMAGE_OUT")"
  cp "$img" "$IMAGE_OUT"
  local build_script
  build_script="$(find_build_script || true)"
  [ -n "$build_script" ] || die "找不到 10-build-emu.sh（试过 $CORE_DIR/core-package/scripts/、$CORE_DIR/scripts/、本脚本同目录）"

  local args=(--src-root "$SRC_ROOT" --image "$IMAGE_OUT" --jobs "$JOBS" --jvm-xmx "$JVM_XMX")
  [ -n "$EMU_THREADS" ] && args+=(--emu-threads "$EMU_THREADS")
  # 记账只由本脚本（外层）做一次：子脚本同一 job_id 再记一遍会把机时记两遍。
  local rc=0
  BUDGET_LOG_SKIP=1 "$build_script" "${args[@]}" || rc=$?
  if [ "$rc" != "0" ]; then
    log "[FATAL] 10-build-emu.sh 未达标（rc=$rc）"
    exit 1
  fi
  log "判据：节点内 IP 重建 + 冒烟达标（NODE_IP=$NODE_IP，镜像 md5=$md5）"
  exit 0
}

# 一次作业只记一次账：子脚本（10-build-emu.sh）带 BUDGET_LOG_SKIP=1 调用，不会重复记账。
trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$BUDGET_ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
