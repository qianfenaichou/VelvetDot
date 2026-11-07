#!/bin/bash
# P-2 gate builder (scratch, not a repo artifact):
#   1) rebuild emu from the shared tree (10-build-emu.sh, same invocation as HANDOFF rounds)
#   2) snapshot the freshly built emu + NEMU .so into ~/core-p2 so the difftest job cannot be
#      silently swapped by a concurrent coverage rebuild
#   3) snapshot the VdotReduce RTL closure while build/rtl is known to be the P-2 version
set -uo pipefail
CORE=/public/home/$USER/core
SCRATCH=/public/home/$USER/core-p2
cd "$CORE" || exit 3

echo "== [p2] source sha256 (expect aa00c2b9... P-2 version) =="
sha256sum "$CORE/src/XiangShan/yunsuan/src/main/scala/yunsuan/vector/vectorIMAC/VdotReduce.scala"
echo "== [p2] git heads =="
( cd "$CORE/src/XiangShan" && git rev-parse --short HEAD && cd yunsuan && git rev-parse --short HEAD && git status --porcelain )

echo "== [p2] force Chisel re-elaboration =="
# XiangShan/Makefile:54 `SCALA_FILE = $(shell find ./src/main/scala -name '*.scala')` does NOT
# cover the yunsuan submodule, so `make emu` alone treats build/rtl/SimTop.sv as up to date and
# silently rebuilds the OLD RTL (observed on job 127135545: "对'emu-mk'无需做任何事" + 0 sumS2 hits).
# Removing the target makes `$(SIM_TOP_V)` out of date -> mill re-emits every module.
rm -f "$CORE/src/XiangShan/build/rtl/SimTop.sv"
ls -la "$CORE/src/XiangShan/build/rtl/VdotReduce.sv" 2>/dev/null

core-package/scripts/10-build-emu.sh --src-root "$CORE/src"
rc=$?
echo "BUILD_RC=$rc"

if [ "$rc" -eq 0 ]; then
  echo "== [p2] generated VdotReduce.sv provenance =="
  sha256sum "$CORE/src/XiangShan/build/rtl/VdotReduce.sv"
  grep -n "sumS2\|carryS2" "$CORE/src/XiangShan/build/rtl/VdotReduce.sv" | head -6
  if ! grep -q "sumS2\|carryS2" "$CORE/src/XiangShan/build/rtl/VdotReduce.sv"; then
    echo "[p2][FATAL] generated RTL is NOT the P-2 version -> abort snapshot"
    rc=5
  fi
fi

if [ "$rc" -eq 0 ]; then
  echo "== [p2] snapshot emu/ref-so =="
  cp -L "$CORE/src/XiangShan/build/emu" "$SCRATCH/emu-p2" || rc=4
  cp -L "$CORE/src/NEMU/build/riscv64-nemu-interpreter-so" "$SCRATCH/ref-p2.so" || rc=4
  sha256sum "$SCRATCH/emu-p2" "$SCRATCH/ref-p2.so"
fi

if [ "$rc" -eq 0 ]; then
  echo "== [p2] regenerate area closure from build/rtl =="
  bash "$CORE/design_verify/area/build_area_rtl.sh" "$CORE/src/XiangShan" "$SCRATCH/rtl/area" || rc=4
  ls -la "$SCRATCH/rtl/area"
  sha256sum "$SCRATCH"/rtl/area/*.sv
fi
echo "P2_BUILD_WRAPPER_DONE rc=$rc"
exit $rc