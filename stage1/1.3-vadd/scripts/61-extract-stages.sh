#!/usr/bin/env bash
# 交付物 1.3：把已 dump 的 VCD 抽成七级逐拍表 + PNG 波形（计算节点批处理）
# 用法：sbatch -p kshcnormal -N 1 -n 8 --time=00:20:00 stage1/1.3-vadd/scripts/61-extract-stages.sh
# 产物（~/core/results/wave/）：vadd_stages.tsv / .md / .index.txt / wave_*.png
# 判据：extract rc=0 且 index 里 anchor_seqNum 非 None 且 MISSING 段为空
set -uo pipefail
CORE="${CORE_DIR:-$HOME/core}"
W="$CORE/results/wave"
VCD="$W/vadd_wave_20261103T164323.vcd"
PY="$CORE/wave-vadd"
# 计算节点的 PATH 里没有 python3（本作业 126696175 实测 `python3: 未找到命令` rc=127）；
# 用 env.sh 挂的站点 python（与 10-build-emu.sh 同一来源）
PY3=/public/software/apps/python/3.8.13/bin/python3
[ -x "$PY3" ] || PY3="$(command -v python3 || true)"
echo "PY3=$PY3"
RUNID="$(date +%Y%m%dT%H%M%S)"
LOG="$W/61-extract-$RUNID.log"
exec > >(tee -a "$LOG") 2>&1

echo "===== 1.3 抽取 job=${SLURM_JOB_ID:-NA} host=$(hostname) runid=$RUNID ====="
echo "VCD=$VCD"
ls -l "$VCD" || { echo "[FATAL] 缺 VCD"; exit 2; }

"$PY3" -I "$PY/vadd_stage_extract.py" --vcd "$VCD" --instr 0x021101D7 \
  --out-tsv "$W/vadd_stages.tsv" --out-md "$W/vadd_stages.md" \
  --out-index "$W/vadd_stages.index.txt"
RC=$?
echo "[E1] extract rc=$RC"
[ "$RC" -eq 0 ] || { echo "[FATAL] 抽取失败"; exit 1; }

echo "=== index 摘要 ==="
sed -n '1,12p' "$W/vadd_stages.index.txt"
echo "=== MISSING 段 ==="
sed -n '/# MISSING/,$p' "$W/vadd_stages.index.txt" | head -20

# 判据
if grep -q "anchor_seqNum: None" "$W/vadd_stages.index.txt"; then
  echo "[FAIL] anchor_seqNum 为 None（关联键没取到）"; exit 1
fi
MISS=$(sed -n '/# MISSING/,$p' "$W/vadd_stages.index.txt" | grep -c '^- ' || true)
echo "[E2] MISSING 信号数=$MISS"

# PNG 在**本机**用 PIL 生成（昆山计算节点 python3.8 无 PIL，实测
# `ModuleNotFoundError: No module named 'PIL'`，作业 126696284）。这里只把 TSV 备好。
echo "[E3] PNG 渲染改在本机做（昆山无 PIL）：tsv=$W/vadd_stages.tsv"

echo "===== DONE rc=$RC MISSING=$MISS ====="
[ "$MISS" -eq 0 ] || exit 1
