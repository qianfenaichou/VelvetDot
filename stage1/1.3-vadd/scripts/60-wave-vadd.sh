#!/usr/bin/env bash
# =============================================================================
# 交付物 1.3 波形取证作业（昆山 kshcnormal）
#
# 背景（实测，见 stage1/1.3-vadd/README.md §1）：
#   * 昆山登录节点 `which vcs verdi verilator iverilog gtkwave` 全部 MISSING；
#     `module avail` 里也没有 VCS/Verdi（只有 apps/mpi/compiler 类）。
#   * 现有 build/verilator-compile/emu 是 **不带 trace** 编的：
#     `strings emu | grep -c 'dump wave to %s'` → 0，且 binary 里有
#     "please compile with EMU_TRACE=1"（difftest/src/test/csrc/emu/simulator.h:24-26）。
#     ⇒ 必须重建一次 emu 才能 --dump-wave。
#
# 本作业五阶段：
#   A  重建 emu（EMU_TRACE=1 + EMU_TRACE_ALL=1）；旧对象目录搬到 .notrace 备份，
#      失败则原样搬回（不破坏后续 difftest 可用的 emu）。
#   B  编最小 vadd.vv 用例 vadd_wave.c（nexus-am / riscv64-xs）
#   C  跑一遍 --no-diff，取程序自报的 mcycle 窗口 c0/c1
#   D  窄窗 --dump-wave 出 VCD（时间轴 = mcycle；Rob.scala:1607 difftest.cycleCnt := timer）
#   E  VCD 体检：header、scope 索引、本条指令机器码命中、时间戳范围
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 32 --time=01:00:00 stage1/1.3-vadd/scripts/60-wave-vadd.sh
# 产物（昆山 ~/core/results/wave/）：60-wave-<runid>.{log,json}、vadd_wave.bin、
#   vadd_wave_<runid>.vcd、vcd-head-<runid>.txt、vcd-scopes-<runid>.txt
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 32
#SBATCH --time=01:00:00
#SBATCH -J vadd_wave_1_3

set -uo pipefail

CORE="${CORE_DIR:-$HOME/core}"
SRC="$CORE/src/XiangShan"
NEMU="$CORE/src/NEMU"
AM="$CORE/src/nexus-am"
OUT="$CORE/results/wave"
CASE_SRC="$CORE/wave-vadd/vadd_wave.c"
PROBE_PY="$CORE/wave-vadd/vcd_probe.py"
RUNID="$(date +%Y%m%dT%H%M%S)"
LOG="$OUT/60-wave-$RUNID.log"
JSON="$OUT/60-wave-$RUNID.json"
mkdir -p "$OUT"
exec > >(tee -a "$LOG") 2>&1

failed_stage=""
fail() { failed_stage="$1"; echo "[FATAL] $2"; }
trap 'echo "[TRAP] 作业被终止（可能是 --time 到）"' TERM INT

echo "===== 1.3 vadd wave job runid=$RUNID host=$(hostname) job=${SLURM_JOB_ID:-NA} partition=${SLURM_JOB_PARTITION:-NA} ====="
echo "cores=$(nproc) start=$(date --iso-8601=seconds)"
# shellcheck disable=SC1091
source "$HOME/tools/env.sh" >/dev/null 2>&1 || echo "[WARN] source tools/env.sh 失败"

echo "verilator=$(verilator --version 2>/dev/null | head -1)"
# 与 10-build-emu.sh:201-203 同一口径：make emu 与 AM 构建都要这三个环境变量
export NOOP_HOME="$SRC"
export NEMU_HOME="$NEMU"
export AM_HOME="$AM"
echo "NOOP_HOME=$NOOP_HOME NEMU_HOME=$NEMU_HOME AM_HOME=$AM_HOME"
echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null) nemu=$(git -C "$NEMU" rev-parse --short HEAD 2>/dev/null)"

# ============================================================ A. 带 trace 重建 emu
echo "===== A. 重建带 trace 的 emu（EMU_TRACE=1 EMU_TRACE_ALL=1）====="
VC="$SRC/build/verilator-compile"
A_RC=1
# 幂等：作业 126687276（2026-11-03 16:05–16:29）已成功编出带 trace 的 emu，
# 判定口径 = binary 里同时有 'dump wave to %s' 且没有 'compile with EMU_TRACE=1'。
if [ -x "$VC/emu" ] \
   && [ "$(strings "$VC/emu" 2>/dev/null | grep -c 'dump wave to %s')" -ge 1 ] \
   && [ "$(strings "$VC/emu" 2>/dev/null | grep -c 'compile with EMU_TRACE=1')" -eq 0 ]; then
  echo "[A] 已存在带 trace 的 emu（$(stat -c '%y %s' "$VC/emu")），跳过重建"
  A_RC=0
else
  if [ -d "$VC.notrace" ]; then
    echo "[A] 已存在 $VC.notrace（早前重建留下的备份），本次直接在其上重建"
    rm -rf "$VC"
  else
    mv "$VC" "$VC.notrace" && echo "[A] 旧（无 trace）对象目录 -> $VC.notrace（保留供回滚）"
  fi

  A_T0=$(date +%s)
  make -C "$SRC" emu -j"$(nproc)" EMU_TRACE=1 EMU_TRACE_ALL=1 EMU_THREADS=8 \
       JVM_XMX=40G JVM_XSS=256m >"$OUT/build-trace-$RUNID.log" 2>&1
  A_RC=$?
  A_T1=$(date +%s)
  echo "[A] make emu rc=$A_RC elapsed=$((A_T1-A_T0))s"
  tail -25 "$OUT/build-trace-$RUNID.log"
fi

EMU=""
if [ "$A_RC" -eq 0 ] && [ -x "$SRC/build/emu" ]; then
  EMU="$SRC/build/emu"
  ls -l "$EMU"
  # 生效判定：带 trace 的 binary 里必须有 VCD/FST 相关的 trace 符号
  echo "[A] 生效判定 'dump wave to %s' 字符串数=$(strings "$SRC/build/verilator-compile/emu" 2>/dev/null | grep -c 'dump wave to %s')"
  echo "[A] 生效判定 'EMU_TRACE=1' 提示串数=$(strings "$SRC/build/verilator-compile/emu" 2>/dev/null | grep -c 'compile with EMU_TRACE=1')"
else
  fail A "trace 构建失败（rc=$A_RC，日志 $OUT/build-trace-$RUNID.log）"
  # 回滚：把无 trace 的对象目录与 emu 放回原位，保证 difftest 仍可用
  if [ -d "$VC.notrace" ]; then
    rm -rf "$VC"; mv "$VC.notrace" "$VC" && echo "[A] 已回滚到无 trace 的 build/verilator-compile"
  fi
fi

# ============================================================ B. 用例镜像
echo "===== B. 构建 vadd_wave 镜像 ====="
B_RC=1
if [ -n "$EMU" ]; then
  APP="$AM/apps/vadd_wave"
  rm -rf "$APP"; mkdir -p "$APP"
  cp "$CASE_SRC" "$APP/main.c"
  printf 'NAME = vadd_wave\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' >"$APP/Makefile"
  # MARCH 与 mabi 必须**同时**给、且对 app 与 AM 静态库一致（两条均为实测踩到）：
  #  a) xpack riscv-none-elf-gcc 13.2.0 默认 mabi=ilp32（软浮点）；只给 -march=rv64gcv
  #     ⇒ `cc1: error: ABI requires '-march=rv32'`（作业 126690058 实测）；
  #  b) 给 -mabi=lp64d 但 AM 静态库按 ilp32 编过 ⇒ `can't link soft-float modules with
  #     double-float modules`（作业 126687276 实测）⇒ 必须清库缓存后按同一 MARCH 重建。
  #  MARCH 本体取 design/verify/cases/build_cases.sh:13 的同一串（含 _v，否则
  #  vsetvli/vle8/vadd.vv 会被 as 拒），再追加 -mabi=lp64d。
  MARCH_STR="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt -mabi=lp64d}"
  echo "[B] MARCH=$MARCH_STR"
  rm -rf "$AM/am/build" "$AM/libs/klib/build"
  echo "[B] 已清空 AM 静态库缓存（am/build、libs/klib/build），按本次 MARCH 重建"
  make -s -C "$APP" AM_HOME="$AM" ARCH=riscv64-xs \
       CROSS_COMPILE=riscv64-unknown-elf- MARCH="$MARCH_STR" image
  B_RC=$?
  if [ "$B_RC" -eq 0 ]; then
    cp "$APP/build/vadd_wave-riscv64-xs.bin" "$OUT/vadd_wave.bin"
    riscv64-unknown-elf-objdump -d "$OUT/vadd_wave.bin" >"$OUT/vadd_wave.dis-$RUNID.txt" 2>/dev/null
    echo "[B] 镜像 $(stat -c %s "$OUT/vadd_wave.bin") B -> $OUT/vadd_wave.bin"
    echo "[B] objdump 里 vadd.vv 条数=$(grep -c 'vadd.vv' "$OUT/vadd_wave.dis-$RUNID.txt")"
    echo "[B] 反汇编定位：$(grep -m3 'vadd.vv' "$OUT/vadd_wave.dis-$RUNID.txt")"
    echo "[B] 期望机器码 0x021101D7 是否出现=$(grep -c -i '021101d7' "$OUT/vadd_wave.dis-$RUNID.txt")"
  else
    fail B "用例构建失败（rc=$B_RC）"
  fi
else
  fail B "A 阶段无 emu，跳过"
fi

# ============================================================ C. mcycle 窗口
echo "===== C. --no-diff 跑一遍，取 c0/c1 ====="
C_RC=1; C0=""; C1=""
if [ -n "$EMU" ] && [ "$B_RC" -eq 0 ]; then
  C_T0=$(date +%s)
  timeout 1800 "$EMU" -i "$OUT/vadd_wave.bin" --no-diff --max-cycles=3000000 \
      >"$OUT/run-a-$RUNID.log" 2>&1
  C_RC=$?
  C_T1=$(date +%s)
  echo "[C] run-a rc=$C_RC elapsed=$((C_T1-C_T0))s"
  grep -E "WAVE_" "$OUT/run-a-$RUNID.log" | tee "$OUT/run-a-$RUNID.key.txt"
  C0=$(sed -n 's/.*WAVE_MARK c0=\([0-9][0-9]*\) c1=\([0-9][0-9]*\).*/\1/p' "$OUT/run-a-$RUNID.log" | head -1)
  C1=$(sed -n 's/.*WAVE_MARK c0=\([0-9][0-9]*\) c1=\([0-9][0-9]*\).*/\2/p' "$OUT/run-a-$RUNID.log" | head -1)
  echo "[C] c0=${C0:-NA} c1=${C1:-NA}"
  if [ -z "$C0" ]; then
    fail C "日志里没抓到 WAVE_MARK（用例没跑或没打印）"
  elif ! grep -q "WAVE verdict=OK" "$OUT/run-a-$RUNID.log"; then
    fail C "用例自检未通过（见 run-a 日志）"
  fi
else
  fail C "前置失败，跳过"
fi

# ============================================================ D. 窄窗 VCD
echo "===== D. 窄窗 --dump-wave ====="
D_RC=1; VCD=""; B=0; E=0
if [ -n "$C0" ]; then
  B=$((C0 - 60)); [ "$B" -lt 0 ] && B=0
  E=$((C1 + 150))
  VCD="$OUT/vadd_wave_${RUNID}.vcd"
  D_T0=$(date +%s)
  timeout 2400 "$EMU" -i "$OUT/vadd_wave.bin" --no-diff --dump-wave --wave-path="$VCD" \
      -b "$B" -e "$E" --max-cycles=3000000 >"$OUT/run-b-$RUNID.log" 2>&1
  D_RC=$?
  D_T1=$(date +%s)
  echo "[D] run-b rc=$D_RC elapsed=$((D_T1-D_T0))s window=[$B,$E]"
  grep -E "WAVE_|dump wave" "$OUT/run-b-$RUNID.log" | tee "$OUT/run-b-$RUNID.key.txt"
  if [ -f "$VCD" ]; then
    echo "[D] VCD=$(stat -c %s "$VCD") B sha256=$(sha256sum "$VCD" | cut -d' ' -f1)"
    head -40 "$VCD" >"$OUT/vcd-head-$RUNID.txt"
  else
    fail D "没有产出 VCD"
  fi
else
  fail D "无 c0，跳过"
fi

# ============================================================ E. VCD 体检
echo "===== E. VCD 体检（header / scope 索引 / 指令命中）====="
E_RC=1
if [ -f "$VCD" ] && [ -f "$PROBE_PY" ]; then
  python3 -I "$PROBE_PY" --vcd "$VCD" --instr 0x021101D7 \
      --scopes "$OUT/vcd-scopes-$RUNID.txt" --summary "$OUT/vcd-summary-$RUNID.txt"
  E_RC=$?
  echo "[E] probe rc=$E_RC"
  cat "$OUT/vcd-summary-$RUNID.txt" 2>/dev/null
else
  fail E "缺 VCD 或探针脚本"
fi

# ============================================================ F. 清单
echo "===== F. 产物清单 ====="
{
  echo "schema: vadd-wave/1"
  echo "runid: $RUNID"
  echo "job_id: ${SLURM_JOB_ID:-NA}"
  echo "host: $(hostname)"
  echo "stage_rc: A=${A_RC:-NA} B=${B_RC:-NA} C=${C_RC:-NA} D=${D_RC:-NA} E=${E_RC:-NA}"
  echo "failed_stage: ${failed_stage:-none}"
  echo "window: c0=${C0:-NA} c1=${C1:-NA} begin=$B end=$E"
  [ -n "$VCD" ] && echo "vcd: $VCD"
  [ -n "$VCD" ] && echo "vcd_bytes: $(stat -c %s "$VCD" 2>/dev/null)"
  [ -n "$VCD" ] && echo "vcd_sha256: $(sha256sum "$VCD" 2>/dev/null | cut -d' ' -f1)"
  echo "end: $(date --iso-8601=seconds)"
} | tee "$JSON"

if [ -n "${SLURM_JOB_ID:-}" ]; then
  bash "$CORE/core-package/scripts/90-budget-log.sh" auto --item P0-emu \
       --purpose "1.3 vadd 波形：EMU_TRACE 重建 + 窄窗 VCD" || echo "[WARN] 记账失败"
fi
echo "===== DONE failed_stage=${failed_stage:-none} ====="
[ -z "$failed_stage" ] || exit 1
exit 0