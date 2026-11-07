#!/usr/bin/env bash
# =============================================================================
# 验证项：P0-2 emu 构建冒烟（make emu + hello 输出 HIT GOOD TRAP）
# 预计机时：3.0（1 机时 = 1 计算节点 × 1 小时，X86 32C / 126.5 GB）
# 状态：已在昆山实跑（2026-11-01 起多次；`results/emu/10-build-*.json` 18 份，最新 `10-build-20261104T105328.json`）。
#       本行原写「未在任何节点执行」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 加密钥说明：本脚本不读取、不打印任何密钥文件
# 用法：
#   sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 scripts/10-build-emu.sh --src-root "$PWD/src"
#   参数：--src-root DIR（默认 $CORE_DIR/src）  --image FILE  --fallback-microbench  --jobs N
#         --emu-threads N  --jvm-xmx SIZE  --require-pin  --dry-run
# 判据：make emu 退出码 0；build/emu 存在；冒烟日志含 HIT GOOD TRAP 且不含 ABORT
#       1.1 证据额外要求 JSON 的 smoke_image=hello（microbench(fallback) 不算）
# 产物：results/emu/10-build-<runid>.log|json
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P0-emu"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
SRC_ROOT="${SRC_ROOT:-$CORE_DIR/src}"
IMAGE=""
FALLBACK_MICROBENCH=0
JOBS="$(nproc 2>/dev/null || echo 8)"
EMU_THREADS=""
JVM_XMX="${JVM_XMX:-40G}"
MAX_INSTR="${MAX_INSTR:-200000000}"
EMU_TIMEOUT="${EMU_TIMEOUT:-7200}"
REQUIRE_PIN=0
DRY_RUN=0
CRITERIA=()
STARTED_AT=""

readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/emu"
readonly LOG_FILE="$OUT_DIR/10-build-$RUN_ID.log"
readonly JSON_FILE="$OUT_DIR/10-build-$RUN_ID.json"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="emu 构建冒烟"

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
# JSON 串转义：**先删裸控制字符，再转义引号/反斜杠**。裸控制字符（实测最常见是 AM printf 的
# CRLF 里的 \r）落在 JSON 字符串里是非法的 ⇒ `python3 -c "json.load(...)"` 报
# "Invalid control character"，整份结果 JSON 不可解析（实例：stage1/1.1-env/raw/
# 10-build-20261103T150714.json:24 的 smoke_hello_identity.actual，源头是冒烟日志第 3 行
# "…IP: 10.1.11.2\r"）。\t 与 \n 保留给后面的 sed/tr 转成空格（同行格式与 20-run-difftest.sh 一致，
# 那里 2026-11-02 已按同一个坑修过）。
json_escape() { printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '; }
add_criterion() { CRITERIA+=("    {\"name\": \"$(json_escape "$1")\", \"expected\": \"$(json_escape "$2")\", \"actual\": \"$(json_escape "$3")\", \"status\": \"$(json_escape "$4")\"}"); }
run() { if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi; "$@"; }

write_json() { # status  extra_key extra_val...
  local status="$1"; shift
  local tmp="$JSON_FILE.tmp" i n kv
  mkdir -p "$OUT_DIR"
  {
    printf '{\n'
    printf '  "schema": "vdot-verify/1",\n'
    printf '  "item": "%s",\n' "$ITEM"
    printf '  "script": "scripts/%s",\n' "$SCRIPT_NAME"
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "platform": "%s",\n' "$( [ -n "${SLURM_JOB_ID:-}" ] && echo "${SLURM_JOB_PARTITION:-slurm}" || echo "login-node" )"
    printf '  "slurm_job_id": "%s",\n' "${SLURM_JOB_ID:-}"
    printf '  "started_at": "%s",\n' "$STARTED_AT"
    printf '  "ended_at": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
    printf '  "machine_hours_planned": 3.0,\n'
    printf '  "versions": {"xiangshan": "%s", "yunsuan": "%s", "nemu": "%s"},\n' \
      "$(json_escape "${XS_HEAD:-}")" "$(json_escape "${YS_HEAD:-}")" "$(json_escape "${NEMU_HEAD:-}")"
    while [ "$#" -gt 0 ]; do
      kv="$1"; shift
      printf '  "%s": "%s",\n' "${kv%%=*}" "$(json_escape "${kv#*=}")"
    done
    printf '  "criteria": [\n'
    n=${#CRITERIA[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CRITERIA[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "artifacts": ["%s"]\n' "$LOG_FILE"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  log "结果 JSON：$JSON_FILE"
}

module_init() {
  if ! type module >/dev/null 2>&1; then
    local f
    for f in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
      if [ -r "$f" ]; then . "$f"; break; fi
    done
  fi
  if type module >/dev/null 2>&1; then
    set +u
    module load compiler/gcc/13.3.0 || log "[WARN] module load compiler/gcc/13.3.0 失败"
    module load compiler/cmake/3.25.0 || log "[WARN] module load compiler/cmake/3.25.0 失败"
    module load apps/python/3.8.13 || log "[WARN] module load apps/python/3.8.13 失败"
    set -u
  else
    log "[WARN] module 命令不可用：跳过 module load"
  fi
  if [ -r "$TOOLS_DIR/env.sh" ]; then . "$TOOLS_DIR/env.sh"; log "已 source $TOOLS_DIR/env.sh"; fi
  hash -r
}

pick_emu_threads() {
  local v major minor
  v="$(verilator --version 2>/dev/null | sed -n '1p' | sed -n 's/.*Verilator \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
  major="${v%% *}"; minor="${v##* }"
  # 10# 前缀：版本号可能有前导 0（如 5.028），否则 $(( )) 会按八进制解析而报错
  if [ -n "${major:-}" ] && [ -n "${minor:-}" ] && [ $((10#$major * 1000 + 10#$minor)) -ge 5050 ]; then
    printf '8'    # emu.yml:401-409：verilator >= 5.050 时 8 线程更快
  else
    printf '16'
  fi
}

fail_unrun() { # $1 原因
  add_criterion "preconditions" "前置齐备" "$1" "未运行"
  write_json "未运行" "reason=$1"
  log "未运行：$1"
  exit 2
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --src-root) SRC_ROOT="${2:?--src-root 需要参数}"; shift 2 ;;
      --image) IMAGE="${2:?--image 需要参数}"; shift 2 ;;
      --fallback-microbench) FALLBACK_MICROBENCH=1; shift ;;
      --jobs) JOBS="${2:?--jobs 需要参数}"; shift 2 ;;
      --emu-threads) EMU_THREADS="${2:?--emu-threads 需要参数}"; shift 2 ;;
      --jvm-xmx) JVM_XMX="${2:?--jvm-xmx 需要参数}"; shift 2 ;;
      --require-pin) REQUIRE_PIN=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
  done

  if [ -z "${SLURM_JOB_ID:-}" ]; then
    echo "[FATAL] 构建属重计算，禁止在登录节点执行。" >&2
    echo "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=03:00:00 ${SCRIPT_PATH} --src-root <dir> --image <bin>" >&2
    exit 3
  fi

  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"
  mkdir -p "$OUT_DIR" "$CORE_DIR/results/logs"
  log "===== $SCRIPT_NAME jobs=$JOBS jvm_xmx=$JVM_XMX dry_run=$DRY_RUN ====="
  module_init

  [ -n "$SRC_ROOT" ] || fail_unrun "缺 --src-root"
  local NOOP_HOME="$SRC_ROOT/XiangShan" NEMU_HOME="$SRC_ROOT/NEMU"
  [ -d "$NOOP_HOME" ] || fail_unrun "缺源码树 $NOOP_HOME（见 README §1 的 rsync 步骤）"
  [ -d "$NEMU_HOME" ] || fail_unrun "缺源码树 $NEMU_HOME（见 README §1 的 rsync 步骤）"

  XS_HEAD="$(git -C "$NOOP_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)"  YS_HEAD="$(git -C "$NOOP_HOME/yunsuan" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  NEMU_HEAD="$(git -C "$NEMU_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  log "版本：XiangShan=$XS_HEAD yunsuan=$YS_HEAD NEMU=$NEMU_HEAD（锁定值见 `versions.env`）"

  local pin_bad=0
  [ "$XS_HEAD" = "a4eeaab" ] || pin_bad=1
  [ "$YS_HEAD" = "9559211" ] || pin_bad=1
  [ "$NEMU_HEAD" = "a683e0b" ] || pin_bad=1
  if [ "$pin_bad" = "1" ]; then
    if [ "$REQUIRE_PIN" = "1" ]; then
      add_criterion "version_pin" "XiangShan a4eeaab / yunsuan 9559211 / NEMU a683e0b" \
        "实际 $XS_HEAD / $YS_HEAD / $NEMU_HEAD" "未达标"
      write_json "失败" "reason=version-pin"
      exit 3
    fi
    log "[WARN] 版本与锁定值不一致（实施期允许），已记入 JSON；加 --require-pin 可改为硬失败"
    add_criterion "version_pin" "与 `versions.env` 一致（软判据）" "$XS_HEAD / $YS_HEAD / $NEMU_HEAD" "警告"
  else
    add_criterion "version_pin" "XiangShan a4eeaab / yunsuan 9559211 / NEMU a683e0b" "$XS_HEAD / $YS_HEAD / $NEMU_HEAD" "达标"
  fi

  # 工具前置
  local missing=""
  command -v verilator >/dev/null 2>&1 || missing="$missing verilator"
  command -v mill >/dev/null 2>&1 || missing="$missing mill"
  command -v java >/dev/null 2>&1 || missing="$missing java"
  if [ -n "$missing" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[WARN] dry-run：缺工具$missing；照常打印计划命令（真跑前须先 00-env-check.sh --install）"
    else
      fail_unrun "缺工具：$missing（先跑 00-env-check.sh --install）"
    fi
  fi
  [ -z "$EMU_THREADS" ] && EMU_THREADS="$(pick_emu_threads)"
  log "verilator=$(verilator --version 2>/dev/null | sed -n '1p') EMU_THREADS=$EMU_THREADS"

  export NOOP_HOME NEMU_HOME
  export AM_HOME="${AM_HOME:-$SRC_ROOT/nexus-am}"
  log "NOOP_HOME=$NOOP_HOME NEMU_HOME=$NEMU_HOME AM_HOME=$AM_HOME"

  # 子模块：cde/hardfloat 必须是「非空」才算就绪。工作区里这两个目录存在但为空
  # （git submodule status 前导 '-' = 未初始化），rsync -a 会把空目录带过去，
  # 只用 -e/-d 判断会误判为就绪并跳过 make init（repos/XiangShan/Makefile:321-324）。
  if [ -z "$(ls -A "$NOOP_HOME/rocket-chip/cde" 2>/dev/null)" ] \
     || [ -z "$(ls -A "$NOOP_HOME/rocket-chip/hardfloat" 2>/dev/null)" ]; then
    log "子模块未初始化（cde/hardfloat 为空或缺失）：尝试 make init（需要外网；计算节点外网未探测，失败属已知风险 README §7-12）"
    log "  更稳妥的做法：落位阶段在登录节点先跑 make -C <src>/XiangShan init（README §1）"
    run make -C "$NOOP_HOME" init || log "[WARN] make init 未完成"
  fi
  if [ "$DRY_RUN" != "1" ] && { [ -z "$(ls -A "$NOOP_HOME/rocket-chip/cde" 2>/dev/null)" ] \
     || [ -z "$(ls -A "$NOOP_HOME/rocket-chip/hardfloat" 2>/dev/null)" ]; }; then
    fail_unrun "子模块 cde/hardfloat 仍为空（make init 失败）：$NOOP_HOME/rocket-chip（先在登录节点跑 make init）"
  fi

  # 1) NEMU ref .so（difftest 参照；kmhv2-ref 分层配置含 CONFIG_SHARE=y）
  local nemu_so="$NEMU_HOME/build/riscv64-nemu-interpreter-so"
  log "== 构建 NEMU ref .so =="
  if run make -C "$NEMU_HOME" riscv64-xs-kmhv2-ref_defconfig; then
    log "NEMU defconfig: riscv64-xs-kmhv2-ref_defconfig"
  else
    log "[WARN] NEMU defconfig 失败"
  fi
  run make -C "$NEMU_HOME" -j"$JOBS" || log "[WARN] NEMU 构建失败"
  if [ -f "$nemu_so" ]; then
    add_criterion "nemu_ref_so" "$nemu_so 存在" "$nemu_so" "达标"
    local nm_hits
    nm_hits="$(nm -a "$nemu_so" 2>/dev/null | grep -cw exec_vdot || true)"
    if [ "${nm_hits:-0}" -ge 1 ]; then
      add_criterion "nm_exec_vdot" "nm 命中 exec_vdot >= 1 行" "命中 $nm_hits 行" "达标"
    else
      # 本脚本的判据是「构建 + hello 冒烟」；exec_vdot 的强制判据在 20-run-difftest.sh。
      # 这里只记录，不阻断 P0-2（RTL/NEMU 未实现时本就该为 0）。
      add_criterion "nm_exec_vdot" "提示项（强制判据在 20-run-difftest.sh）" "命中 0 行（NEMU 未扩展或 static inline 被内联）" "警告"
    fi
  else
    add_criterion "nemu_ref_so" "$nemu_so 存在" "MISSING" "未达标"
    add_criterion "nm_exec_vdot" "提示项（强制判据在 20-run-difftest.sh）" "无 .so" "未运行"
  fi

  # 2) emu
  log "== 构建 emu：make emu -j$JOBS EMU_THREADS=$EMU_THREADS JVM_XMX=$JVM_XMX =="
  local build_rc=0
  run make -C "$NOOP_HOME" emu -j"$JOBS" EMU_THREADS="$EMU_THREADS" JVM_XMX="$JVM_XMX" JVM_XSS=256m || build_rc=$?
  local emu_bin="$NOOP_HOME/build/emu"
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] 跳过 build/emu 存在性检查与冒烟"
    add_criterion "build_emu" "make emu 退出码 0 且 build/emu 可执行" "dry-run：未执行" "未运行"
    write_json "未运行" "reason=dry-run"
    exit 2
  fi
  if [ "$build_rc" = "0" ] && [ -x "$emu_bin" ]; then
    add_criterion "build_emu" "make emu 退出码 0 且 build/emu 可执行" "rc=$build_rc $emu_bin" "达标"
  else
    add_criterion "build_emu" "make emu 退出码 0 且 build/emu 可执行" "rc=$build_rc $emu_bin" "未达标"
    write_json "失败" "reason=build-emu-failed"
    log "构建未达标，停止（不跑冒烟）"
    exit 1
  fi

  # 3) 冒烟
  # 镜像解析：--image 显式给定时按给定路径；未给时若 $NOOP_HOME/ready-to-run/microbench.bin
  # 存在则自动回退（--fallback-microbench 仅为显式确认，保留兼容），否则记「未运行」。
  local smoke_label="hello" hello_evidence="yes"
  if [ -z "$IMAGE" ]; then
    if [ -f "$NOOP_HOME/ready-to-run/microbench.bin" ]; then
      IMAGE="$NOOP_HOME/ready-to-run/microbench.bin"
      smoke_label="microbench(fallback)"
      hello_evidence="no"
      log "[WARN] --image 未给：自动回退 ready-to-run/microbench.bin 做构建冒烟；它不是 1.1 的 hello 证据（JSON 记 smoke_image=microbench(fallback)）"
    else
      add_criterion "smoke_image" "hello 镜像（1.1 交付物）" "MISSING（--image 未给，且 $NOOP_HOME/ready-to-run/microbench.bin 不存在）" "未运行"
      write_json "未运行" "reason=hello-image-missing" "smoke_image=$smoke_label"
      log "未运行：缺 hello 镜像。AM_HOME=$AM_HOME（nexus-am 源码树需先取；见 README §4）"
      exit 2
    fi
  else
    smoke_label="custom:$(basename "$IMAGE")"
    hello_evidence="no"
    # 1.1 的 hello 证据：镜像名以 hello 开头（nexus-am/apps/hello 产物 hello-riscv64-xs.bin，
    # 或本包的 hello_identity.bin）。命中时 log 不能再打「hello_evidence=no」（2026-11-03 修：
    # 旧版无条件打印，日志与实际判定相反）。
    case "$(basename "$IMAGE")" in
      hello*) hello_evidence="yes"; smoke_label="hello:$(basename "$IMAGE")" ;;
    esac
    if [ "$hello_evidence" = "yes" ]; then
      log "--image 为 hello 类镜像（$smoke_label）：按 1.1 证据处理（hello_evidence=yes）；身份串判据见下（要求团队标识 + 真实 IP）"
    else
      log "[WARN] --image 为自选镜像（$smoke_label）：冒烟只证明构建可用，不构成 1.1 的 hello 证据（hello_evidence=no）"
    fi
    if [ "$FALLBACK_MICROBENCH" = "1" ]; then
      log "--fallback-microbench 已给但 --image 也给出，按 --image 执行"
    fi
  fi
  [ -f "$IMAGE" ] || fail_unrun "镜像不存在：$IMAGE"

  local smoke_log="$OUT_DIR/10-smoke-$RUN_ID.log"
  log "== 冒烟运行：$IMAGE（label=$smoke_label）=="
  local rc=0
  if [ "$DRY_RUN" != "1" ]; then
    timeout "$EMU_TIMEOUT" "$emu_bin" --diff "$nemu_so" -i "$IMAGE" --max-instr="$MAX_INSTR" \
      >"$smoke_log" 2>&1 || rc=$?
  fi
  local good bad abort
  good="$(grep -c 'HIT GOOD TRAP' "$smoke_log" 2>/dev/null || true)"
  bad="$(grep -c 'HIT BAD TRAP' "$smoke_log" 2>/dev/null || true)"
  abort="$(grep -c 'ABORT' "$smoke_log" 2>/dev/null || true)"
  log "冒烟结果：rc=$rc HIT_GOOD_TRAP=${good:-0} HIT_BAD_TRAP=${bad:-0} ABORT=${abort:-0}"

  if [ "${good:-0}" -ge 1 ]; then
    add_criterion "smoke_good_trap" "日志含 HIT GOOD TRAP" "命中 ${good} 次" "达标"
  else
    add_criterion "smoke_good_trap" "日志含 HIT GOOD TRAP" "命中 0 次（rc=$rc）" "未达标"
  fi
  if [ "${abort:-0}" -eq 0 ] && [ "${bad:-0}" -eq 0 ]; then
    add_criterion "smoke_no_abort" "无 ABORT / 无 HIT BAD TRAP" "ABORT=0 BAD=${bad:-0}" "达标"
  else
    add_criterion "smoke_no_abort" "无 ABORT / 无 HIT BAD TRAP" "ABORT=${abort:-0} BAD=${bad:-0}" "未达标"
  fi

  # 1.1 证据独立判据：hello 路径必须命中**完整身份串**：
  #   hello xiangshan, I am <团队名>, IP: <真实 IPv4>
  # 只 grep hello/xiangshan/i am 会让 hello_identity.c 的 0.0.0.0 占位输出（该镜像自带 WARN）
  # 也记「达标」，与官方 1.1「真实终端输出含团队标识与 IP」不符（docx/02 §1.1）。
  if [ "$hello_evidence" = "yes" ]; then
    local ident_line="" ident_team="" ident_ip="" ident_ok=0 ip_oct_ok=0 oct
    # 只认问候行（WARN 行不含 "hello xiangshan, I am"）；取第一条
    ident_line="$(grep -aE 'hello xiangshan, I am .+, IP: ' "$smoke_log" 2>/dev/null | head -n 1 || true)"
    if [ -n "$ident_line" ]; then
      ident_team="$(printf '%s\n' "$ident_line" | sed -n 's/.*hello xiangshan, I am \(.*\), IP: .*/\1/p')"
      ident_ip="$(printf '%s\n' "$ident_line" | sed -n 's/.*, IP: *\([0-9.]*\).*/\1/p')"
    fi
    # IP 硬判据三道：① 必须是点分四段 IPv4，且每段 0..255（只满足「三个点」的
    # 999.999.999.999 之类假 IP 不得混过）；② 占位/广播地址（0.0.0.0 / 255.255.255.255）拒收；
    # ③ 回环 127.0.0.0/8 与链路本地 169.254.0.0/16 拒收（复核：构建机 hostname -I
    # 可能只返回回环地址，旧判据会把 127.0.0.1 记成「真实 IP」而误判达标）。
    if printf '%s\n' "$ident_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
      ip_oct_ok=1
      for oct in ${ident_ip//./ }; do
        [ "$oct" -le 255 ] || ip_oct_ok=0
      done
    fi
    if [ -n "$ident_team" ] && [ "$ip_oct_ok" -eq 1 ]; then
      case "$ident_ip" in
        0.0.0.0|255.255.255.255) ident_ok=0 ;;   # 占位/广播地址不是真实 IP
        127.*|169.254.*)         ident_ok=0 ;;   # 回环 / 链路本地不是节点真实 IP
        *) ident_ok=1 ;;
      esac
    fi
    if [ "$ident_ok" -eq 1 ]; then
      add_criterion "smoke_hello_identity" "日志含 1.1 身份串（hello xiangshan, I am <团队名>, IP: <真实 IP>）" "命中：$ident_line（team=$ident_team ip=$ident_ip）" "达标"
    else
      add_criterion "smoke_hello_identity" "日志含 1.1 身份串（hello xiangshan, I am <团队名>, IP: <真实 IP>）" "未命中或 IP 为占位/回环/链路本地（got: ${ident_line:-<none>}；要求非 0.0.0.0、非 127.0.0.0/8、非 169.254.0.0/16 的真实 IPv4）" "未达标"
    fi
  else
    add_criterion "smoke_hello_identity" "日志含 1.1 身份串（hello xiangshan, I am <团队名>, IP: <真实 IP>）" "非 hello 镜像（$smoke_label），不适用" "不适用"
  fi

  local ok=0
  local c
  for c in ${CRITERIA[@]+"${CRITERIA[@]}"}; do
    case "$c" in
      *'"未达标"'*|*'"未运行"'*) ok=1 ;;
    esac
  done
  if [ "$ok" = "0" ]; then
    write_json "通过" "hello_evidence=$hello_evidence" "smoke_image=$smoke_label" "smoke_log=$smoke_log" "emu_threads=$EMU_THREADS" "jvm_xmx=$JVM_XMX"
    log "判据：构建与冒烟达标（镜像标签=$smoke_label）"
    exit 0
  fi
  write_json "失败" "hello_evidence=$hello_evidence" "smoke_image=$smoke_label" "smoke_log=$smoke_log" "emu_threads=$EMU_THREADS" "jvm_xmx=$JVM_XMX"
  log "判据：冒烟未达标"
  exit 1
}

# 机时记账脚本定位：昆山实际落位是 $CORE_DIR/core-package/scripts/（验证包整体在 ~/core/core-package/，
# 平台落位实测），**$CORE_DIR/scripts/ 并不存在** ⇒ 旧 trap 的
# `[ -x "$CORE_DIR/scripts/90-budget-log.sh" ]` 恒为假 ⇒ auto 记账从未落盘（作业 126681977 等
# 均无自动记账行；stage1/1.1-env/README.md §4 记的那行是人工 record 的）。
# 依次兼容三种布局：core-package/scripts/（昆山实际）→ scripts/（扁平/文档口径）→ 与本脚本同目录（随包同发）。
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

# 一次作业只记一次账：本脚本被 30-hello-nodeip.sh 当子进程调用时，父脚本已按同一 job_id 记过，
# 子脚本再记一次会把机时记两遍（90-budget-log.sh 的 record 不按 job_id 去重）⇒ 父脚本设
# BUDGET_LOG_SKIP=1 时本 trap 不记账。
trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$BUDGET_ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
