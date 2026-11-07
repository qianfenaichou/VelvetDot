#!/usr/bin/env bash
# =============================================================================
# 交付物 2.2「vdot.vv 自身波形」取证作业（昆山 kshcnormal）
#
# 为什么要有这一份（原工作记录 §0「仍开放、非阻塞」第 2 条）：
#   `find stage2 -iname '*.vcd' -o -iname '*.fst' | wc -l` → 0。
#   1.3 的 vadd 波形（stage1/1.3-vadd/）**不能替代**：那是官方 vadd.vv 的七级证据，
#   本条要的是**自定义 vdot.vv** 在 VIMacU / VdotReduce 上的实测波形。
#
# 与范本的关系：五阶段结构与 stage1/1.3-vadd/scripts/60-wave-vadd.sh 一一对应
#   （A 重建 trace emu → B 编最小用例 → C 取 mcycle 窗口 → D 窄窗 dump → E 体检），
#   差异只在「用例 = 单条 vdot.vv」和「E 阶段 = vdot 专用探针 + 摘录」。
#   **本脚本不改 60-wave-vadd.sh 本体**；两者的 A 阶段判定口径完全一致，
#   所以同一台机器上先跑哪个都不会把对方的 emu 弄坏（幂等 + 失败自动回滚）。
#
# 五阶段：
#   A  带 trace 的 emu（EMU_TRACE=1 EMU_TRACE_ALL=1）。已存在则跳过；
#      需要重建时把旧对象目录搬到 .notrace 备份，失败原样搬回（不破坏 difftest 用的 emu）。
#   B  编最小用例 design/verify/cases/vdot_wave.c（唯一一条 vdot.vv = 0x3A20A1D7，
#      前后各一次 rdcycle 自报窗口）。镜像 = $OUT/vdot_wave.bin。
#   C  `--no-diff` 跑一遍，抓 WAVE_MARK c0/c1 + WAVE verdict=OK（用例自检）。
#      读 mcycle 与 NEMU 参照的 CSR 不一致 ⇒ 必须 --no-diff（同 vadd_wave.c 口径）。
#   D  窄窗 `--dump-wave`：窗口 [c0-60, c1+150]（与 60-wave-vadd.sh 同口径）。
#      时间轴 = mcycle（Rob.scala:1607 difftest.cycleCnt := timer；
#      waveform.cpp:59 tfp->dump(waveform_clock) ⇒ 每拍一个时间戳）。
#   E  VCD 体检 + 窄窗关键信号摘录（core-package/verify/vdot_wave_probe.py）：
#      header / scope 索引 / vdot 机器码命中 / 时间戳范围 / 执行级 fuOpType=0x067 /
#      结果低 32 位 = 金模型期望 / 写回高 96 位恒零 / 摘录回读逐拍自校验。
#
# ---------------------------------------------------------------------------
# 产物（返回值 = 最后一行的结果 JSON；下面每个文件都在 JSON 的 artifacts 里点名）
# ---------------------------------------------------------------------------
# 昆山侧（$CORE/results/wave/）：
#   62-wave-<runid>.log                 完整作业日志
#   62-wave-<runid>.json                结果 JSON（stage_rc / 窗口 / 各产物 sha256 / verdict）
#   vdot_wave_<runid>.vcd               **窄窗完整 VCD**（emu 原始产物，未加工）
#   vdot_wave_<runid>.vcd.gz            上面那份的 gzip 归档（+ 解压后 sha256 复核）
#   vcd-head-<runid>.txt                VCD header 原文（前 40 行）
#   vcd-scopes-<runid>.txt              scope 索引（scope 路径 + var 数）+ 摘录信号表（标签→完整层次名）
#   vcd-summary-<runid>.txt             体检摘要（人读，逐条 PASS/FAIL）
#   vdot_wave_<runid>.health.json       体检结论（机读，checks[] 每条 expected/actual/pass）
#   vdot_wave_<runid>.key.vcd           **窄窗关键信号摘录**（真实抽取，非伪造；见下）
#   SHA256SUMS-<runid>.txt              上述所有产物的 sha256（回传后逐份核对）
#   导出目录（默认 $CORE/results/wave/export-stage2/，可用 EXPORT_DIR 覆盖）：
#       vdot_wave_<runid>.key.vcd、vcd-scopes/head/summary、health.json、
#       vdot_wave_<runid>.vcd.gz、SHA256SUMS-<runid>.txt
#       —— 回传到本地后**原样落到** stage2/2.2-rtl/wave/（脚本结束会打印这条映射命令）。
#
# 关键信号摘录的诚实口径（写死在这里，避免事后被当成编造）：
#   * 时间戳**原样保留源 VCD 的拍号**（不重编号）⇒ 可与全量 VCD 逐拍对齐；
#   * 每个信号的值逐拍从源 VCD 抽取；VCD 只记变化，故先前向填值、再在窗口首拍锁定稳态值；
#   * 摘录里的信号名是缩写标签，标签→完整层次名的映射写进 vcd-scopes-<runid>.txt；
#   * 摘录写完后**立刻回读**，逐信号逐拍与源 VCD 比对，不一致即体检 FAIL（excerpt_verify）。
#
# 用法：
#   sbatch -p kshcnormal -N 1 -n 32 --time=01:00:00 core-package/scripts/62-wave-vdot.sh
#   bash core-package/scripts/62-wave-vdot.sh --preflight     # 只查落位，不跑 emu、不出证据
#
# 落位（提交前一次性；脚本按下面的顺序自己找，找不到就 rc=2 并打印缺哪一件）：
#   用例 design/verify/cases/vdot_wave.c        → 昆山 $CORE/verify/cases/ 或 $CORE/wave-vdot/
#   探针 core-package/verify/vdot_wave_probe.py → 昆山 $CORE/verify/ 或 $CORE/core-package/verify/
#     scp design/verify/cases/vdot_wave.c        kunshan:~/core/verify/cases/
#     scp core-package/verify/vdot_wave_probe.py kunshan:~/core/verify/
#
# 退出码：0 达标 / 1 未达标（failed_stage 非空）/ 2 前置缺失 / 3 用法或环境错误
# =============================================================================
#SBATCH -p kshcnormal
#SBATCH -N 1
#SBATCH -n 32
#SBATCH --time=01:00:00
#SBATCH -J vdot_wave_2_2

set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="${CORE_DIR:-$HOME/core}"
SRC="$CORE/src/XiangShan"
NEMU="$CORE/src/NEMU"
AM="${AM_HOME:-$CORE/src/nexus-am}"
OUT="$CORE/results/wave"
EXPORT_DIR="${EXPORT_DIR:-$OUT/export-stage2}"
RUNID="$(date +%Y%m%dT%H%M%S)"
LOG="$OUT/62-wave-$RUNID.log"
JSON="$OUT/62-wave-$RUNID.json"
VCD="$OUT/vdot_wave_$RUNID.vcd"
VCD_GZ="$OUT/vdot_wave_$RUNID.vcd.gz"
EXCERPT="$OUT/vdot_wave_$RUNID.key.vcd"
HEALTH="$OUT/vdot_wave_$RUNID.health.json"
SUMS="$OUT/SHA256SUMS-$RUNID.txt"
SUMS_JOB="$OUT/SHA256SUMS-job-$RUNID.txt"
PREFLIGHT=0

# 用例：优先取随包落位的副本，其次取工作区件（三处兼容，与 20-run-difftest.sh:583-588 同一思路）
CASE_SRC=""
for c in "$CORE/wave-vdot/vdot_wave.c" \
         "$CORE/verify/cases/vdot_wave.c" \
         "$CORE/core-package/verify/cases/vdot_wave.c" \
         "$HERE/../../design/verify/cases/vdot_wave.c" \
         "$HERE/../../../design/verify/cases/vdot_wave.c"; do
  [ -f "$c" ] && { CASE_SRC="$c"; break; }
done
# 探针：同样三处兼容
PROBE_PY=""
for c in "$CORE/verify/vdot_wave_probe.py" \
         "$CORE/core-package/verify/vdot_wave_probe.py" \
         "$HERE/../verify/vdot_wave_probe.py"; do
  [ -f "$c" ] && { PROBE_PY="$c"; break; }
done

# 与 design/verify/cases/build_cases.sh:13 同一串（必须带 _v，否则 vsetvli/vle8 会被 as 拒）
MARCH_STR="${MARCH:-rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt}"
# xpack riscv-none-elf-gcc 13.2.0 默认 mabi=ilp32 ⇒ 必须显式给 -mabi（1.3 实测踩过两次，
# 见 stage1/1.3-vadd/scripts/60-wave-vadd.sh:115-125）
MARCH_STR="$MARCH_STR -mabi=lp64d"
# 期望值（design/verify/vdot_model.py 实算：vdot_vv(0xA55A18810FF03CC3_88796A5B4C3D2E1F,
# 0x9669B44BD22DE77E_938475665748392A) = 0x8780，高 96 位为 0；若误把 16 lane 全算进去
# 会得到 0x7C5F ⇒ 结果等于 0x8780 同时证明「只取低 64 位」）
EXPECT_LOW32="0x00008780"
INSTR_HEX="0x3A20A1D7"
WINDOW_PRE="${WINDOW_PRE:-60}"
WINDOW_POST="${WINDOW_POST:-150}"

# 失败阶段按出现顺序全部记录（第一个 = 根因；后面的多为级联，如 E 无 VCD 导致 F 无法导出）
failed_stages=()
fail() { failed_stages+=("$1"); echo "[FATAL][$1] $2"; }
failed_stage() { printf '%s' "${failed_stages[0]:-}"; }
failed_all() { local j; j="$(printf '%s' "${failed_stages[*]:-}")"; printf '%s' "${j// /,}"; }
usage() { sed -n '3,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --preflight) PREFLIGHT=1; shift ;;
    --case) CASE_SRC="${2:?--case 需要参数}"; shift 2 ;;
    --probe) PROBE_PY="${2:?--probe 需要参数}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[FATAL] 未知参数：$1（用 --help）" >&2; exit 3 ;;
  esac
done

guard_path() {
  case "$1" in
    /work|/work/*|/work1|/work1/*|/public/share|/public/share/*)
      echo "[FATAL] 拒绝写入 $1：平台实测不可写（文件系统实测）" >&2
      exit 3 ;;
  esac
}

# 记账脚本定位（core-package/scripts → scripts → 本脚本同目录；见 20-run-difftest.sh:583-588）
budget_log_script() {
  local c
  for c in "$CORE/core-package/scripts/90-budget-log.sh" \
           "$CORE/scripts/90-budget-log.sh" \
           "$HERE/90-budget-log.sh"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ---------------- 前置（--preflight 也走这一段） ----------------
echo "===== 2.2 vdot wave job=${SLURM_JOB_ID:-NA} host=$(hostname) runid=$RUNID ====="
echo "core=$CORE out=$OUT export=$EXPORT_DIR"
echo "case_src=${CASE_SRC:-<MISSING>}"
echo "probe_py=${PROBE_PY:-<MISSING>}"
echo "expect_low32=$EXPECT_LOW32 instr=$INSTR_HEX window=[c0-$WINDOW_PRE, c1+$WINDOW_POST]"

missing_src=""
[ -n "$CASE_SRC" ] && [ -f "$CASE_SRC" ] || missing_src="$missing_src 用例源"
[ -n "$PROBE_PY" ] && [ -f "$PROBE_PY" ] || missing_src="$missing_src 探针脚本"
if [ -n "$missing_src" ]; then
  echo "[FATAL] 前置缺失：$missing_src" >&2
  echo "       用例应在 design/verify/cases/vdot_wave.c，探针在 core-package/verify/vdot_wave_probe.py" >&2
  exit 2
fi
# 用例必须真的只有一条 vdot（机器码魔数）且带 WAVE_MARK
grep -q '0x3A20A1D7' "$CASE_SRC" || { echo "[FATAL] $CASE_SRC 里没有 0x3A20A1D7" >&2; exit 2; }
grep -q 'WAVE_MARK'  "$CASE_SRC" || { echo "[FATAL] $CASE_SRC 里没有 WAVE_MARK 自报窗口" >&2; exit 2; }
# 「单条 vdot」判据：发射这条指令的 .4byte 必须恰好 1 处（注释里出现不算）
VDOT_SITES="$(grep -c '\.4byte[[:space:]]*0x3A20A1D7' "$CASE_SRC")"
echo "用例里发射 0x3A20A1D7 的 .4byte 处数=$VDOT_SITES（须为 1）"
[ "$VDOT_SITES" -eq 1 ] || { echo "[FATAL] $CASE_SRC 不是「单条 vdot」用例（.4byte 处数=$VDOT_SITES）" >&2; exit 2; }

if [ "$PREFLIGHT" = "1" ]; then
  echo "[preflight] 落位齐备；本模式**不跑 emu、不产出任何证据**（证据须走 sbatch）"
  echo "[preflight] 计划产物：$VCD_GZ / $EXCERPT / $HEALTH / $SUMS"
  echo "[preflight] 回传后落位：stage2/2.2-rtl/wave/"
  exit 0
fi

[ -n "${SLURM_JOB_ID:-}" ] || { echo "[FATAL] 未在作业内：emu 只能在计算节点跑" >&2; exit 3; }

guard_path "$CORE"; guard_path "$OUT"
mkdir -p "$OUT" "$EXPORT_DIR"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[TRAP] 作业被终止（可能是 --time 到）"' TERM INT

echo "cores=$(nproc) start=$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
# shellcheck disable=SC1091
source "$HOME/tools/env.sh" >/dev/null 2>&1 || echo "[WARN] source tools/env.sh 失败"
echo "verilator=$(verilator --version 2>/dev/null | head -1)"
# 与 10-build-emu.sh:201-203 同一口径：make emu 与 AM 构建都要这三个环境变量
export NOOP_HOME="$SRC"
export NEMU_HOME="$NEMU"
export AM_HOME="$AM"
echo "NOOP_HOME=$NOOP_HOME NEMU_HOME=$NEMU_HOME AM_HOME=$AM_HOME"
echo "versions: xiangshan=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null) yunsuan=$(git -C "$SRC/yunsuan" rev-parse --short HEAD 2>/dev/null) nemu=$(git -C "$NEMU" rev-parse --short HEAD 2>/dev/null)"
echo "case_sha256=$(sha256sum "$CASE_SRC" | cut -d' ' -f1) probe_sha256=$(sha256sum "$PROBE_PY" | cut -d' ' -f1)"

# ============================================================ A. 带 trace 重建 emu
echo "===== A. 带 trace 的 emu（EMU_TRACE=1 EMU_TRACE_ALL=1）====="
VC="$SRC/build/verilator-compile"
A_RC=1
# 幂等判定与 60-wave-vadd.sh:70-74 **逐字同口径**：binary 里同时有 'dump wave to %s'
# 且没有 'compile with EMU_TRACE=1'。已满足就复用，绝不重复重建（1451 s 一次，浪费预算）。
if [ -x "$VC/emu" ] \
   && [ "$(strings "$VC/emu" 2>/dev/null | grep -c 'dump wave to %s')" -ge 1 ] \
   && [ "$(strings "$VC/emu" 2>/dev/null | grep -c 'compile with EMU_TRACE=1')" -eq 0 ]; then
  echo "[A] 已存在带 trace 的 emu（$(stat -c '%y %s' "$VC/emu")），跳过重建"
  A_RC=0
else
  if [ -d "$VC.notrace" ]; then
    echo "[A] 已存在 $VC.notrace（上一次运行留下的备份），本次直接在其上重建"
    rm -rf "$VC"
  else
    mv "$VC" "$VC.notrace" && echo "[A] 旧（无 trace）对象目录 -> $VC.notrace（保留供回滚）"
  fi
  A_T0=$(date +%s)
  make -C "$SRC" emu -j"$(nproc)" EMU_TRACE=1 EMU_TRACE_ALL=1 EMU_THREADS=8 \
       JVM_XMX=40G JVM_XSS=256m >"$OUT/build-trace-$RUNID.log" 2>&1
  A_RC=$?
  A_T1=$(date +%s)
  echo "[A] make emu rc=$A_RC elapsed=$((A_T1-A_T0))s（构建日志 build-trace-$RUNID.log）"
  tail -25 "$OUT/build-trace-$RUNID.log"
fi

EMU=""
if [ "$A_RC" -eq 0 ] && [ -x "$SRC/build/emu" ]; then
  EMU="$SRC/build/emu"
  ls -l "$EMU"
  echo "[A] 生效判定 'dump wave to %s' 字符串数=$(strings "$VC/emu" 2>/dev/null | grep -c 'dump wave to %s')"
  echo "[A] 生效判定 'EMU_TRACE=1' 提示串数=$(strings "$VC/emu" 2>/dev/null | grep -c 'compile with EMU_TRACE=1')"
else
  fail A "trace 构建失败（rc=$A_RC，日志 $OUT/build-trace-$RUNID.log）"
  # 回滚：无 trace 的对象目录与 emu 放回原位，保证 difftest 仍可用
  if [ -d "$VC.notrace" ]; then
    rm -rf "$VC"; mv "$VC.notrace" "$VC" && echo "[A] 已回滚到无 trace 的 build/verilator-compile"
  fi
fi

# ============================================================ B. 用例镜像
echo "===== B. 构建 vdot_wave 镜像 ====="
B_RC=1
if [ -n "$EMU" ]; then
  APP="$AM/apps/vdot_wave"
  rm -rf "$APP"; mkdir -p "$APP"
  cp "$CASE_SRC" "$APP/main.c"
  printf 'NAME = vdot_wave\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' >"$APP/Makefile"
  # MARCH 与 mabi 必须同时给、且对 app 与 AM 静态库一致（1.3 实测两个坑，见 60-wave-vadd.sh:115-125）
  echo "[B] MARCH=$MARCH_STR"
  rm -rf "$AM/am/build" "$AM/libs/klib/build"
  echo "[B] 已清空 AM 静态库缓存（am/build、libs/klib/build），按当前 MARCH 重建"
  make -s -C "$APP" AM_HOME="$AM" ARCH=riscv64-xs \
       CROSS_COMPILE=riscv64-unknown-elf- MARCH="$MARCH_STR" image
  B_RC=$?
  if [ "$B_RC" -eq 0 ]; then
    cp "$APP/build/vdot_wave-riscv64-xs.bin" "$OUT/vdot_wave.bin"
    # 裸 bin 不能直接 objdump -d（1.3 踩过：输出为空，不能当证据）；这里给 -b binary -m riscv
    riscv64-unknown-elf-objdump -D -b binary -m riscv "$OUT/vdot_wave.bin" \
        >"$OUT/vdot_wave.dis-$RUNID.txt" 2>/dev/null || true
    echo "[B] 镜像 $(stat -c %s "$OUT/vdot_wave.bin") B md5=$(md5sum "$OUT/vdot_wave.bin" | cut -d' ' -f1)"
    DIS_HITS="$(grep -c -i '3a20a1d7' "$OUT/vdot_wave.dis-$RUNID.txt" 2>/dev/null)"
    echo "[B] 反汇编里 3A20A1D7 出现次数=${DIS_HITS:-0}（反汇编只是旁证；判据用下面的字节检索）"
    # 字节模式检索（比 objdump 可靠）：镜像里必须能找到这条指令的字节序
    BYTEPOS="$(python3 -I -c "
d=open('$OUT/vdot_wave.bin','rb').read()
pat=bytes.fromhex('d7a1203a')
print([hex(i) for i in range(len(d)) if d.startswith(pat,i)])
" 2>/dev/null || echo '[]')"
    echo "[B] 字节检索 d7a1203a 命中偏移=$BYTEPOS"
    case "$BYTEPOS" in *"0x"*) : ;; *) fail B "镜像里找不到 vdot 指令字节（检索=$BYTEPOS）" ;; esac
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
  timeout 1800 "$EMU" -i "$OUT/vdot_wave.bin" --no-diff --max-cycles=3000000 \
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
D_RC=1; B=0; E=0
if [ -n "$C0" ]; then
  B=$((C0 - WINDOW_PRE)); [ "$B" -lt 0 ] && B=0
  E=$((C1 + WINDOW_POST))
  D_T0=$(date +%s)
  timeout 2400 "$EMU" -i "$OUT/vdot_wave.bin" --no-diff --dump-wave --wave-path="$VCD" \
      -b "$B" -e "$E" --max-cycles=3000000 >"$OUT/run-b-$RUNID.log" 2>&1
  D_RC=$?
  D_T1=$(date +%s)
  echo "[D] run-b rc=$D_RC elapsed=$((D_T1-D_T0))s window=[$B,$E]"
  grep -E "WAVE_|dump wave" "$OUT/run-b-$RUNID.log" | tee "$OUT/run-b-$RUNID.key.txt"
  if [ -f "$VCD" ]; then
    VCD_SHA="$(sha256sum "$VCD" | cut -d' ' -f1)"
    echo "[D] VCD=$(stat -c %s "$VCD") B sha256=$VCD_SHA"
    gzip -9 -c "$VCD" >"$VCD_GZ"
    GZ_RC=$?
    echo "[D] gzip rc=$GZ_RC -> $VCD_GZ $(stat -c %s "$VCD_GZ" 2>/dev/null) B"
    # 归档完整性：解压后 sha256 必须与原始 VCD 同值
    GZ_INNER="$(gzip -dc "$VCD_GZ" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    echo "[D] gzip 解压后 sha256=$GZ_INNER（与原始 $( [ "$GZ_INNER" = "$VCD_SHA" ] && echo 一致 || echo 不一致 )）"
    if [ "$GZ_INNER" != "$VCD_SHA" ]; then
      fail D "gzip 归档完整性复核失败（解压 sha256 与原始不同）"
    fi
  else
    fail D "没有产出 VCD"
  fi
else
  fail D "无 c0，跳过"
fi

# ============================================================ E. 体检 + 摘录
echo "===== E. VCD 体检 + 窄窗关键信号摘录 ====="
E_RC=1
# 计算节点 PATH 里可能没有 python3（1.3 实测 `python3: 未找到命令` rc=127，见
# stage1/1.3-vadd/scripts/61-extract-stages.sh:11-14）⇒ 先试站点 python，再退回 PATH
PY3=/public/software/apps/python/3.8.13/bin/python3
[ -x "$PY3" ] || PY3="$(command -v python3 || true)"
[ -n "$PY3" ] || { fail E "找不到 python3（站点与 PATH 都没有）"; PY3=/bin/false; }
echo "[E] PY3=$PY3"
if [ -f "$VCD" ] && [ -f "$PROBE_PY" ]; then
  "$PY3" -I "$PROBE_PY" --vcd "$VCD" --instr "$INSTR_HEX" --expect "$EXPECT_LOW32" \
      --excerpt "$EXCERPT" \
      --head "$OUT/vcd-head-$RUNID.txt" \
      --scopes "$OUT/vcd-scopes-$RUNID.txt" \
      --summary "$OUT/vcd-summary-$RUNID.txt" \
      --json "$HEALTH" \
      --vcd-sha256 "${VCD_SHA:-}" \
      --pre 40 --post 60 --span 200
  E_RC=$?
  echo "[E] probe rc=$E_RC（摘要另存 vcd-summary-$RUNID.txt，内容已在上方逐条打印）"
  if [ "$E_RC" -ne 0 ]; then
    fail E "探针体检未全过（rc=$E_RC，逐条见 vcd-summary-$RUNID.txt）"
  fi
else
  fail E "缺 VCD 或探针脚本"
fi

# ============================================================ F. 导出 + 清单
echo "===== F. 导出（供 stage2/2.2-rtl/wave/）+ 产物清单 ====="
EXPORT_RC=1
if [ -f "$EXCERPT" ] && [ -f "$VCD_GZ" ]; then
  cp "$EXCERPT" "$EXPORT_DIR/vdot_wave_$RUNID.key.vcd"
  cp "$VCD_GZ"   "$EXPORT_DIR/vdot_wave_$RUNID.vcd.gz"
  for f in "$OUT/vcd-head-$RUNID.txt" "$OUT/vcd-scopes-$RUNID.txt" \
           "$OUT/vcd-summary-$RUNID.txt" "$HEALTH"; do
    [ -f "$f" ] && cp "$f" "$EXPORT_DIR/"
  done
  EXPORT_RC=0
  echo "[F] 导出目录 $EXPORT_DIR："
  ls -l "$EXPORT_DIR" | sed -n '2,$p'
else
  fail F "缺摘录或归档，无法导出"
fi

# 产物清单：**真 JSON**（60-wave-vadd.sh 的 F 段写的是 key: value 文本、只是叫 .json；
# 这里改成可被 json.load 解析的真 JSON，键名沿用同一套，便于下游直接读）
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' | tr -d '\r\n'; }
ARTIFACTS=()
for f in "$VCD" "$VCD_GZ" "$EXCERPT" "$HEALTH" \
         "$OUT/vcd-head-$RUNID.txt" "$OUT/vcd-scopes-$RUNID.txt" \
         "$OUT/vcd-summary-$RUNID.txt" "$OUT/vdot_wave.bin" \
         "$OUT/run-a-$RUNID.key.txt" "$OUT/run-b-$RUNID.key.txt"; do
  [ -f "$f" ] && ARTIFACTS+=("$f")
done
{
  printf '{\n'
  printf '  "schema": "vdot-wave/1",\n'
  printf '  "runid": "%s",\n' "$RUNID"
  printf '  "job_id": "%s",\n' "${SLURM_JOB_ID:-NA}"
  printf '  "host": "%s",\n' "$(json_escape "$(hostname)")"
  printf '  "partition": "%s",\n' "${SLURM_JOB_PARTITION:-NA}"
  printf '  "case_src": "%s",\n' "$(json_escape "$CASE_SRC")"
  printf '  "case_sha256": "%s",\n' "$(sha256sum "$CASE_SRC" | cut -d' ' -f1)"
  printf '  "probe_sha256": "%s",\n' "$(sha256sum "$PROBE_PY" | cut -d' ' -f1)"
  printf '  "stage_rc": {"A": %s, "B": %s, "C": %s, "D": %s, "E": %s, "F": %s},\n' \
      "${A_RC:-0}" "${B_RC:-0}" "${C_RC:-0}" "${D_RC:-0}" "${E_RC:-0}" "${EXPORT_RC:-0}"
  printf '  "failed_stage": "%s",\n' "$( [ "${#failed_stages[@]}" -gt 0 ] && { failed_stage; true; } || echo none )"
  printf '  "failed_stages_all": "%s",\n' "$( [ "${#failed_stages[@]}" -gt 0 ] && { failed_all; true; } || echo none )"
  printf '  "window": {"c0": "%s", "c1": "%s", "begin": %s, "end": %s},\n' \
      "${C0:-NA}" "${C1:-NA}" "$B" "$E"
  printf '  "instr": "%s",\n' "$INSTR_HEX"
  printf '  "expect_low32": "%s",\n' "$EXPECT_LOW32"
  printf '  "vcd": "%s",\n' "$(json_escape "$VCD")"
  printf '  "vcd_bytes": %s,\n' "$(stat -c %s "$VCD" 2>/dev/null || echo 0)"
  printf '  "vcd_sha256": "%s",\n' "$(sha256sum "$VCD" 2>/dev/null | cut -d' ' -f1)"
  printf '  "vcd_gz": "%s",\n' "$(json_escape "$VCD_GZ")"
  printf '  "vcd_gz_sha256": "%s",\n' "$(sha256sum "$VCD_GZ" 2>/dev/null | cut -d' ' -f1)"
  printf '  "excerpt": "%s",\n' "$(json_escape "$EXCERPT")"
  printf '  "excerpt_bytes": %s,\n' "$(stat -c %s "$EXCERPT" 2>/dev/null || echo 0)"
  printf '  "excerpt_sha256": "%s",\n' "$(sha256sum "$EXCERPT" 2>/dev/null | cut -d' ' -f1)"
  printf '  "health": "%s",\n' "$(json_escape "$HEALTH")"
  printf '  "export_dir": "%s",\n' "$(json_escape "$EXPORT_DIR")"
  printf '  "local_landing": "stage2/2.2-rtl/wave/",\n'
  printf '  "verdict": "%s",\n' "$( [ "${#failed_stages[@]}" -eq 0 ] && echo OK || echo FAIL )"
  printf '  "end": "%s",\n' "$(date --iso-8601=seconds 2>/dev/null || date '+%FT%T%z')"
  printf '  "artifacts": ['
  first=1
  for f in ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}; do
    [ "$first" -eq 1 ] && first=0 || printf ', '
    printf '"%s"' "$(json_escape "$f")"
  done
  printf ']\n'
  printf '}\n'
} | tee "$JSON"

# 全产物 sha256（只列实际存在的）
# 路径处理（2026-11-06 修订）：`sha256sum` 默认写**传入的绝对路径**，回传到本地后
# `sha256sum -c SHA256SUMS-*.txt` 会因 12 个文件读不到而 rc=1（实测踩到）。这里改成
# 「相对导出目录的 basename」——导出的 6 件都在同一目录，落位后
# `cd stage2/2.2-rtl/wave && sha256sum -c SHA256SUMS-<runid>.txt` 一条命令即可复核；
# 非导出件（作业目录里的 VCD/bin/key.txt/JSON/LOG）另起一张 `SHA256SUMS-job-*.txt`，
# 并显式标注它们在本地不存在。
: >"$SUMS"
: >"$SUMS_JOB"
# 导出件：**以导出目录的实际内容为准**（head/scopes/summary/health 在作业目录里叫别的名字，
# 但都被 cp 到导出目录，所以只能按导出目录枚举，否则那张表会漏 4 件）
for f in "$EXPORT_DIR"/vdot_wave_$RUNID.key.vcd \
         "$EXPORT_DIR"/vdot_wave_$RUNID.vcd.gz \
         "$EXPORT_DIR"/vcd-head-$RUNID.txt \
         "$EXPORT_DIR"/vcd-scopes-$RUNID.txt \
         "$EXPORT_DIR"/vcd-summary-$RUNID.txt \
         "$EXPORT_DIR"/vdot_wave_$RUNID.health.json; do
  [ -f "$f" ] && printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")" >>"$SUMS"
done
for f in ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}; do
  [ -f "$f" ] || continue
  case "$f" in "$EXPORT_DIR"/*) continue ;; esac
  printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")" >>"$SUMS_JOB"
done
for f in "$JSON" "$LOG"; do
  [ -f "$f" ] && printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")" >>"$SUMS_JOB"
done
cp "$SUMS" "$EXPORT_DIR/SHA256SUMS-$RUNID.txt"
cp "$SUMS_JOB" "$EXPORT_DIR/SHA256SUMS-job-$RUNID.txt"
echo "[F] SHA256SUMS（导出件·相对路径·可在落位目录直接 sha256sum -c）：$SUMS"
cat "$SUMS"
echo "[F] SHA256SUMS（作业目录件·仅远端存在；本地复核只到上面那张表）：$SUMS_JOB"
cat "$SUMS_JOB"

echo "===== 回传后落位（本地执行，不在本作业内）====="
echo "  rsync -av kunshan:$EXPORT_DIR/ stage2/2.2-rtl/wave/"
echo "  find stage2 -iname '*.vcd' -o -iname '*.fst' | wc -l   # 期望 >= 1"
echo "  (cd stage2/2.2-rtl/wave && sha256sum -c SHA256SUMS-$RUNID.txt)  # 相对路径，rc 应为 0"

if [ -n "${SLURM_JOB_ID:-}" ]; then
  if bs="$(budget_log_script)"; then
    bash "$bs" auto --item P0-emu --purpose "2.2 vdot.vv 波形：窄窗 VCD + 关键信号摘录" \
      || echo "[WARN] 记账失败"
  else
    echo "[WARN] 找不到 90-budget-log.sh，本次未记账"
  fi
fi
echo "===== DONE failed_stage=$( [ "${#failed_stages[@]}" -gt 0 ] && { failed_stage; true; } || echo none ) all=$( [ "${#failed_stages[@]}" -gt 0 ] && { failed_all; true; } || echo none ) verdict=$( [ "${#failed_stages[@]}" -eq 0 ] && echo OK || echo FAIL ) ====="
[ "${#failed_stages[@]}" -eq 0 ] || exit 1
exit 0
