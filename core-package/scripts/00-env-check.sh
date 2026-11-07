#!/usr/bin/env bash
# =============================================================================
# 验证项：P0-1 环境自检 + EDA 工具自带安装（昆山 kshcnormal）
# 预计机时：2.0（1 机时 = 1 计算节点 × 1 小时，X86 32C / 126.5 GB）
# 状态：已在昆山实跑（2026-11-01 起多次；最新 `results/env/00-env-20261105T092724.json` `status=通过`）。
#       本行原写「未在任何节点执行」已过期，2026-11-06 更正
# 分区：kshcnormal（CPU）。DCU 当前不排；不写 --qos=；不写 /work /work1 /public/share
# 密钥：不读取、不打印、不复制任何密钥文件
# 用法：
#   bash 00-env-check.sh --probe      # 只读探测，登录节点允许（module/which/版本/分区/可写性）
#   bash 00-env-check.sh --fetch      # 只下载到 $TOOLS_DIR/dist|src，登录节点允许，不编译
#   sbatch ... 00-env-check.sh --install   # 计算节点：编译/安装到 $TOOLS_DIR，装一次全局复用
#   bash 00-env-check.sh --dry-run    # 打印计划命令，不执行
# 判据：results/env/00-env-<runid>.json 中 criteria 里 tool_* 全部「达标」，且 java_version / riscv_toolchain 达标
# 产物：results/env/00-env-<runid>.log|json|tools.tsv、$TOOLS_DIR/env.sh
# 退出码：0 达标 / 1 未达标 / 2 未运行（前置缺失）/ 3 用法或环境错误
# =============================================================================
set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly ITEM="P0-env"
CORE_DIR="${CORE_DIR:-/public/home/${USER}/core}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
SRC_ROOT="${SRC_ROOT:-$CORE_DIR/src}"
readonly RUN_ID="$(date '+%Y%m%dT%H%M%S')"
readonly OUT_DIR="$CORE_DIR/results/env"
readonly LOG_FILE="$OUT_DIR/00-env-$RUN_ID.log"
readonly JSON_FILE="$OUT_DIR/00-env-$RUN_ID.json"
readonly TSV_FILE="$OUT_DIR/00-env-$RUN_ID.tools.tsv"
readonly BUDGET_ITEM="$ITEM"
readonly PURPOSE="环境自检 + EDA 工具自带安装"

MODE="probe"
DRY_RUN=0
CRITERIA=()
STARTED_AT=""

# -----------------------------------------------------------------------------
# 基础
# -----------------------------------------------------------------------------
guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr '\n' ' '
}

add_criterion() { # name expected actual status
  CRITERIA+=("    {\"name\": \"$(json_escape "$1")\", \"expected\": \"$(json_escape "$2")\", \"actual\": \"$(json_escape "$3")\", \"status\": \"$(json_escape "$4")\"}")
}

run() {
  if [ "$DRY_RUN" = "1" ]; then log "[dry-run] $*"; return 0; fi
  "$@"
}

write_json() { # $1 = status
  local status="$1" tmp="$JSON_FILE.tmp" i n
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
    printf '  "machine_hours_planned": 2.0,\n'
    printf '  "mode": "%s",\n' "$MODE"
    printf '  "tools_tsv": "%s",\n' "$TSV_FILE"
    printf '  "criteria": [\n'
    n=${#CRITERIA[@]}
    if [ "$n" -gt 0 ]; then
      for ((i = 0; i < n; i++)); do
        printf '%s' "${CRITERIA[$i]}"
        if [ "$i" -lt $((n - 1)) ]; then printf ',\n'; else printf '\n'; fi
      done
    fi
    printf '  ],\n'
    printf '  "artifacts": ["%s", "%s"]\n' "$LOG_FILE" "$TSV_FILE"
    printf '}\n'
  } >"$tmp"
  mv "$tmp" "$JSON_FILE"
  log "结果 JSON：$JSON_FILE"
}

ensure_dirs() {
  guard_path "$CORE_DIR"; guard_path "$OUT_DIR"; guard_path "$TOOLS_DIR"
  mkdir -p "$OUT_DIR" "$CORE_DIR/results/logs" "$TOOLS_DIR/bin" "$TOOLS_DIR/dist" "$TOOLS_DIR/src"
  : >"$TSV_FILE"
}

module_init() {
  if ! type module >/dev/null 2>&1; then
    local f
    for f in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
      if [ -r "$f" ]; then . "$f"; break; fi
    done
  fi
  if ! type module >/dev/null 2>&1; then
    log "[WARN] module 命令不可用：跳过 module load（改用 PATH 上的默认工具）"
    return 0
  fi
  # module load 不能接管道：截断 eval 输入会导致静默加载失败
  set +u
  module load compiler/gcc/13.3.0 || log "[WARN] module load compiler/gcc/13.3.0 失败"
  module load compiler/cmake/3.25.0 || log "[WARN] module load compiler/cmake/3.25.0 失败"
  module load apps/python/3.8.13 || log "[WARN] module load apps/python/3.8.13 失败"
  set -u
  hash -r
}

probe_tool() { # $1 名称；$2.. 版本命令（可选）
  local name="$1" cmd="$1"; shift
  local path ver="-"
  if path="$(command -v "$name" 2>/dev/null)" && [ -n "$path" ]; then
    if [ "$#" -gt 0 ]; then
      # 用 sed -n '1p' 而非 head：head 提前关闭管道会让版本命令收到 SIGPIPE，
      # 在 set -o pipefail 下被误判为失败。
      ver="$("$cmd" "$@" 2>&1 | sed -n '1p')" || ver="(版本命令失败)"
    fi
    printf '%s\t%s\t%s\n' "$name" "$path" "$ver" >>"$TSV_FILE"
    log "  [命中] $name -> $path :: $ver"
    return 0
  fi
  printf '%s\t%s\t%s\n' "$name" "MISSING" "-" >>"$TSV_FILE"
  log "  [缺失] $name"
  return 1
}

probe_all_tools() {
  probe_tool gcc --version || true
  probe_tool g++ --version || true
  probe_tool cmake --version || true
  probe_tool make --version || true
  probe_tool python3 -V || true
  probe_tool java -version || true
  probe_tool git --version || true
  probe_tool verilator --version || true
  probe_tool yosys -V || true
  probe_tool sby || true
  probe_tool mill --version || true
  probe_tool riscv64-unknown-elf-gcc --version || true
  probe_tool riscv64-linux-gnu-gcc --version || true
  probe_tool riscv64-elf-gcc --version || true
  probe_tool riscv64-elf-newlib-gcc --version || true
  probe_tool z3 --version || true
  probe_tool apptainer --version || true
}

probe_platform() {
  log "== 平台信息 =="
  log "hostname=$(hostname) user=${USER:-?} date=$(date '+%F %T')"
  log "SLURM_JOB_ID=${SLURM_JOB_ID:-<none>} SLURM_JOB_PARTITION=${SLURM_JOB_PARTITION:-<none>}"
  if command -v sinfo >/dev/null 2>&1; then
    log "sinfo kshcnormal: $(sinfo -h -p kshcnormal -o '%P|%a|%c|%m' 2>/dev/null | head -n 1 || echo '(查询失败)')"
  fi
  log "CORE_DIR=$CORE_DIR"
  if [ -w "$CORE_DIR" ] || mkdir -p "$CORE_DIR" 2>/dev/null; then
    log "  CORE_DIR 可写"
  else
    log "  [WARN] CORE_DIR 不可写"
  fi
  local p
  for p in /work /work1 /public/share; do
    if [ -w "$p" ] 2>/dev/null; then
      log "  [WARN] $p 当前可写，但本包仍禁止写入"
    else
      log "  $p 不可写（与平台实测一致）"
    fi
  done
}

# -----------------------------------------------------------------------------
# fetch（登录节点允许：只下载）
# -----------------------------------------------------------------------------
download() { # $1 url  $2 out
  if [ "$DRY_RUN" = "1" ]; then log "[dry-run] curl -fL $1 -o $2"; return 0; fi
  curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"
}

mill_version() {
  local v="0.12.3"
  if [ -r "$SRC_ROOT/XiangShan/.mill-version" ]; then
    v="$(tr -d '[:space:]' <"$SRC_ROOT/XiangShan/.mill-version")"
  fi
  printf '%s' "$v"
}

fetch_all() {
  log "== fetch：只下载，不编译（登录节点允许）=="
  mkdir -p "$TOOLS_DIR/dist" "$TOOLS_DIR/src" "$TOOLS_DIR/bin"
  local mv
  mv="$(mill_version)"
  log "mill 版本 = $mv（来源 ${SRC_ROOT}/XiangShan/.mill-version，缺失时用内置候选 0.12.3）"
  download "https://github.com/com-lihaoyi/mill/releases/download/${mv}/${mv}" \
           "$TOOLS_DIR/dist/mill-${mv}" || log "[WARN] mill 启动器下载失败"
  chmod +x "$TOOLS_DIR/dist/mill-${mv}" 2>/dev/null || true

  if ! command -v conda >/dev/null 2>&1 && ! command -v mamba >/dev/null 2>&1 && ! command -v micromamba >/dev/null 2>&1; then
    download "https://micro.mamba.pm/api/micromamba/linux-64/latest" "$TOOLS_DIR/dist/micromamba.tar.bz2" \
      || log "[WARN] micromamba 下载失败"
    if [ -s "$TOOLS_DIR/dist/micromamba.tar.bz2" ] && [ "$DRY_RUN" != "1" ]; then
      tar -xjf "$TOOLS_DIR/dist/micromamba.tar.bz2" -C "$TOOLS_DIR" bin/micromamba \
        || log "[WARN] micromamba 解包失败"
    fi
  else
    log "已有 conda/mamba/micromamba：跳过 micromamba 下载"
  fi

  local repo url
  for repo in yosys verilator sby; do
    if [ -d "$TOOLS_DIR/src/$repo/.git" ]; then
      log "源码树已存在：$TOOLS_DIR/src/$repo"
      continue
    fi
    case "$repo" in
      verilator) url="https://github.com/verilator/verilator.git" ;;   # 2026-10-30 实测：YosysHQ/verilator 为 404
      *)         url="https://github.com/YosysHQ/$repo.git" ;;
    esac
    run git clone --depth 1 "$url" "$TOOLS_DIR/src/$repo" \
      || log "[WARN] $repo 源码克隆失败（$url）"
    if [ -d "$TOOLS_DIR/src/$repo/.git" ]; then
      log "$repo 提交：$(git -C "$TOOLS_DIR/src/$repo" rev-parse HEAD 2>/dev/null || echo 未知)"
    fi
  done
}

# -----------------------------------------------------------------------------
# install（必须计算节点）
# -----------------------------------------------------------------------------
find_pkg_manager() {
  local c
  for c in micromamba mamba conda; do
    if command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
  done
  if [ -x "$TOOLS_DIR/bin/micromamba" ]; then printf '%s' "$TOOLS_DIR/bin/micromamba"; return 0; fi
  return 1
}

conda_install() {
  local pm env_prefix="$TOOLS_DIR/envs/eda" pkg ok=1
  if ! pm="$(find_pkg_manager)"; then
    log "[跳过] 无 conda/mamba/micromamba：conda-forge 一档不可用"
    return 1
  fi
  log "包管理器=$pm 目标环境=$env_prefix"
  run "$pm" create -y -p "$env_prefix" -c conda-forge yosys verilator openjdk=17 z3 \
    || log "[WARN] conda 基础包安装未完成（继续逐包尝试）"
  # RISC-V GCC：antmicro 通道的 gcc-riscv64-elf-newlib 已查证存在（2026-10-30：anaconda API 命中 12.1.0；
  # 包内 bin/riscv64-elf-newlib-gcc -> riscv64-elf-gcc-12.1.0，其依赖 gcc-riscv64-elf-nostdc 提供 bin/riscv64-elf-gcc；
  # conda solve 未实测）。探针同时认 riscv64-elf-newlib-gcc 与 riscv64-elf-gcc 两个名字。
  # conda-forge 上的 gcc-riscv64-unknown-elf / riscv64-unknown-elf-gcc / gcc_riscv64_unknown_elf
  # 三个旧候选名经 anaconda API 实测均 404，仅作历史候选保留。
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] $pm install -p $env_prefix -c antmicro -c conda-forge gcc-riscv64-elf-newlib"
    return 0
  fi
  if "$pm" install -y -p "$env_prefix" -c antmicro -c conda-forge gcc-riscv64-elf-newlib >>"$LOG_FILE" 2>&1; then
    log "[命中] conda 包 gcc-riscv64-elf-newlib（-c antmicro）"
    ok=0
  else
    for pkg in gcc-riscv64-unknown-elf riscv64-unknown-elf-gcc gcc_riscv64_unknown_elf; do
      if "$pm" install -y -p "$env_prefix" -c conda-forge "$pkg" >>"$LOG_FILE" 2>&1; then
        log "[命中] conda 包 $pkg"
        ok=0
        break
      fi
      log "[未命中] conda 包名 $pkg（候选名，已于 2026-10-30 实测 404）"
    done
  fi
  if [ -d "$env_prefix/bin" ]; then export PATH="$env_prefix/bin:$PATH"; fi
  hash -r
  return $ok
}

source_build_yosys() {
  local src="$TOOLS_DIR/src/yosys"
  [ -d "$src" ] || { log "[跳过] 缺 yosys 源码树：$src"; return 1; }
  log "源码编译 yosys -> $TOOLS_DIR"
  run bash -c "cd '$src' && make config-gcc && make -j\"\$(nproc)\" && make install PREFIX='$TOOLS_DIR'"
}

source_build_verilator() {
  local src="$TOOLS_DIR/src/verilator"
  [ -d "$src" ] || { log "[跳过] 缺 verilator 源码树：$src"; return 1; }
  log "源码编译 verilator -> $TOOLS_DIR"
  run bash -c "cd '$src' && autoconf && ./configure --prefix='$TOOLS_DIR' && make -j\"\$(nproc)\" && make install"
}

source_build_sby() {
  local src="$TOOLS_DIR/src/sby"
  [ -d "$src" ] || { log "[跳过] 缺 sby 源码树：$src"; return 1; }
  log "安装 SymbiYosys（纯 Python）-> $TOOLS_DIR"
  run bash -c "cd '$src' && make install PREFIX='$TOOLS_DIR'"
}

install_mill() {
  local mv f
  mv="$(mill_version)"
  f="$TOOLS_DIR/dist/mill-${mv}"
  if [ -x "$f" ]; then
    run cp -f "$f" "$TOOLS_DIR/bin/mill"
    run chmod +x "$TOOLS_DIR/bin/mill"
    log "mill 启动器就位：$TOOLS_DIR/bin/mill（版本 $mv）"
    return 0
  fi
  log "[跳过] mill 启动器未下载（先跑 --fetch）"
  return 1
}

write_env_sh() {
  local f="$TOOLS_DIR/env.sh"
  {
    echo "# 由 $SCRIPT_NAME 生成（$RUN_ID）——source 本文件复用 EDA 工具"
    echo 'export TOOLS_DIR="'"$TOOLS_DIR"'"'
    echo 'export PATH="$TOOLS_DIR/bin:$TOOLS_DIR/envs/eda/bin:$PATH"'
    echo 'if [ -d "$TOOLS_DIR/envs/eda" ]; then export JAVA_HOME="$TOOLS_DIR/envs/eda"; fi'
    echo 'hash -r 2>/dev/null || true'
  } >"$f"
  log "已写 $f"
}

install_all() {
  if [ -z "${SLURM_JOB_ID:-}" ]; then
    log "[FATAL] --install 属重计算，禁止在登录节点执行。"
    log "        提交：sbatch -p kshcnormal -N 1 -n 32 --time=02:00:00 $CORE_DIR/scripts/$SCRIPT_NAME --install"
    exit 3
  fi
  log "== install：编译/安装（计算节点）=="
  conda_install || log "[WARN] conda-forge 一档未装齐，转源码编译"
  if ! command -v verilator >/dev/null 2>&1; then source_build_verilator || log "[WARN] verilator 源码编译未完成"; fi
  if ! command -v yosys >/dev/null 2>&1; then source_build_yosys || log "[WARN] yosys 源码编译未完成"; fi
  if ! command -v sby >/dev/null 2>&1; then source_build_sby || log "[WARN] sby 安装未完成"; fi
  install_mill || log "[WARN] mill 未就位"
  write_env_sh
  if [ -d "$TOOLS_DIR/bin" ]; then export PATH="$TOOLS_DIR/bin:$PATH"; fi
  if [ -d "$TOOLS_DIR/envs/eda/bin" ]; then export PATH="$TOOLS_DIR/envs/eda/bin:$PATH"; fi
  hash -r
  probe_apptainer_image
}

# 第三档 Apptainer：只做「镜像内工具是否齐全」的只读探测，不把镜像内工具注入 PATH。
# 真正的回退用法是人工 `apptainer exec <image> <命令>`（README §4）。
probe_apptainer_image() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] module load apps/apptainer/1.3.4; apptainer exec \${VDOT_EDA_IMAGE:-<unset>} sh -c 'command -v yosys; command -v verilator'"
    return 0
  fi
  if [ -z "${VDOT_EDA_IMAGE:-}" ]; then
    log "[跳过] 未设 VDOT_EDA_IMAGE：第三档 Apptainer 不可用（不阻塞判据）"
    return 0
  fi
  if ! command -v apptainer >/dev/null 2>&1; then
    if type module >/dev/null 2>&1; then
      set +u
      module load apps/apptainer/1.3.4 || log "[WARN] module load apps/apptainer/1.3.4 失败"
      set -u
      hash -r
    fi
  fi
  if ! command -v apptainer >/dev/null 2>&1; then
    log "[WARN] apptainer 不可用（VDOT_EDA_IMAGE 已设但无法执行镜像探测）"
    return 0
  fi
  local out=""
  out="$(apptainer exec "$VDOT_EDA_IMAGE" sh -c 'command -v yosys; command -v verilator' 2>&1 || true)"
  log "[Apptainer] image=$VDOT_EDA_IMAGE 内工具探测：$(printf '%s' "$out" | tr '\n' ' ')"
  log "[Apptainer] 本脚本不注入镜像内工具；若上面命中而本机仍缺工具，请人工 apptainer exec 回退"
  return 0
}

# -----------------------------------------------------------------------------
# 判据
# -----------------------------------------------------------------------------
tsv_get() { # $1 tool  $2 字段号
  awk -F'\t' -v n="$1" -v f="$2" '$1==n{print $f}' "$TSV_FILE" | tail -n 1
}

judge() {
  local required="gcc g++ cmake make python3 java git verilator yosys mill" t path ver st
  local all_ok=0 raw_ver major
  for t in $required; do
    path="$(tsv_get "$t" 2)"
    ver="$(tsv_get "$t" 3)"
    if [ -n "${path:-}" ] && [ "$path" != "MISSING" ]; then st="达标"; else st="未达标"; all_ok=1; fi
    add_criterion "tool_$t" "which 命中且记录版本" "${path:-MISSING} ${ver:-}" "$st"
  done

  raw_ver="$(tsv_get java 3)"
  major="$(printf '%s' "${raw_ver:-}" | sed -n 's/.*version "\([0-9][0-9.]*\).*/\1/p' | head -n 1)"
  case "${major:-}" in
    1.*) major="$(printf '%s' "$major" | cut -d. -f2)" ;;
    *)   major="$(printf '%s' "${major:-}" | cut -d. -f1)" ;;
  esac
  if [ -n "${major:-}" ] && [ "$major" -ge 11 ] 2>/dev/null; then
    add_criterion "java_version" ">= 11（repos/XiangShan/.github/workflows/emu.yml:630-633）" "major=${major}" "达标"
  else
    add_criterion "java_version" ">= 11（repos/XiangShan/.github/workflows/emu.yml:630-633）" "major=${major:-未知} raw=${raw_ver:-}" "未达标"
    all_ok=1
  fi

  local rv=""
  for t in riscv64-unknown-elf-gcc riscv64-linux-gnu-gcc riscv64-elf-newlib-gcc riscv64-elf-gcc; do
    path="$(tsv_get "$t" 2)"
    if [ -n "${path:-}" ] && [ "$path" != "MISSING" ]; then rv="$t"; break; fi
  done
  if [ -n "$rv" ]; then
    add_criterion "riscv_toolchain" "riscv64-*-gcc 至少一种可用" "$rv" "达标"
  else
    add_criterion "riscv_toolchain" "riscv64-*-gcc 至少一种可用" "MISSING" "未达标"
    all_ok=1
  fi

  path="$(tsv_get sby 2)"
  if [ -n "${path:-}" ] && [ "$path" != "MISSING" ]; then
    add_criterion "tool_sby_optional" "可选：SymbiYosys" "$path" "达标"
  else
    add_criterion "tool_sby_optional" "可选：SymbiYosys" "MISSING（50 用 yosys 内置 sat，不阻塞）" "未运行"
  fi

  return $all_ok
}

# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------
usage() { sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --probe) MODE="probe" ;;
      --fetch) MODE="fetch" ;;
      --install) MODE="install" ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
    esac
    shift
  done
  STARTED_AT="$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  ensure_dirs
  log "===== $SCRIPT_NAME mode=$MODE dry_run=$DRY_RUN ====="
  module_init
  probe_platform
  log "== 工具探测 =="
  probe_all_tools

  case "$MODE" in
    probe) log "probe 结束（只读）" ;;
    fetch) fetch_all ;;
    install) install_all; log "== 安装后复探 =="; probe_all_tools ;;
  esac

  if judge; then
    write_json "通过"
    log "判据：全部达标"
    exit 0
  fi
  if [ "$MODE" = "install" ]; then
    write_json "失败"
    log "判据：存在未达标项（install 已执行）——见 JSON criteria"
    exit 1
  fi
  write_json "未运行"
  log "判据：存在未达标项（$MODE 模式尚未安装）——见 JSON criteria"
  exit 2
}

# 机时记账脚本定位：昆山实际落位是 $CORE_DIR/core-package/scripts/（验证包整体在 ~/core/core-package/，
# 平台落位实测），**$CORE_DIR/scripts/ 并不存在** ⇒ 旧 trap 的
# `[ -x "$CORE_DIR/scripts/90-budget-log.sh" ]` 恒为假 ⇒ auto 记账从未落盘。
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

# 一次作业只记一次账：父脚本（30-hello-nodeip.sh）已按同一 job_id 记过时，子脚本跳过（record 不去重）。
trap '_bl="$(budget_log_script || true)"; if [ -n "${SLURM_JOB_ID:-}" ] && [ -n "${_bl:-}" ] && [ -z "${BUDGET_LOG_SKIP:-}" ]; then "$_bl" auto --item "$BUDGET_ITEM" --purpose "$PURPOSE" >/dev/null 2>&1 || true; fi' EXIT

main "$@"
