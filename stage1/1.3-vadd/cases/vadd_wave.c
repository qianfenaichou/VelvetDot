// vadd_wave.c — 交付物 1.3「向量加法指令执行过程文档」的波形取证用例
//
// 目标：在香山昆明湖 V2（XiangShan @ a4eeaab + vdot 实施补丁）的 RTL 仿真
//       （Verilator，EMU_TRACE=1 → --dump-wave）里，产生**一条可被波形唯一辨识**的
//       vadd.vv，并用 mcycle 标出它前后各一拍的周期号，供窄窗 dump 定位。
//
// 为什么用 mcycle 当时间轴：Rob.scala:1607 `difftest.cycleCnt := timer`，即 emu 的
//   trap->cycleCnt 与 mcycle 同源；程序读到的 c0/c1 就是 VCD 的时间刻度（见
//   difftest/src/test/csrc/verilator/waveform.cpp:59 `tfp->dump(waveform_clock)`，
//   waveform_clock 从 log_begin 起每拍 +1）。
//   读 mcycle 会与 NEMU 参照的 CSR 不一致 ⇒ 运行必须带 --no-diff（同 perf_vadd.c 口径）。
//
// 形状（SPEC 口径：SEW=8 / LMUL=1 / vl=8）：
//   v1 = 0x0807060504030201   （lane0..7 = 01 02 03 04 05 06 07 08）
//   v2 = 0x8070605040302010   （lane0..7 = 10 20 30 40 50 60 70 80）
//   vadd.vv v3, v1, v2  ⇒ v3 = 0x8877665544332211（低 64 位），高 64 位 = 0
//   指令编码（funct6=000000 / vm=1 / vs2=1 / vs1=2 / funct3=000 / rd=3 / opcode=1010111）
//     = 0x021101D7  ← 波形里用这个魔数在译码级 io_in_0_bits_instr 上定位本条指令
//
// 只发一条 vadd.vv：不做循环、不与其它向量指令混排，保证七级流水里每一步都能对应到
// 同一 uop 的同一份 ROB/物理寄存器编号。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// AM 的 start.S 只开 mstatus.FS；向量指令还要求 mstatus.VS != OFF
#define ENABLE_VS() asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

static uint8_t va[16] __attribute__((aligned(16))) = {
  1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0
};
static uint8_t vb[16] __attribute__((aligned(16))) = {
  0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0, 0, 0, 0, 0, 0, 0, 0
};
static uint8_t vout[16] __attribute__((aligned(16)));

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

int main(void) {
  uint64_t vl = 0, c0 = 0, c1 = 0;
  int i;

  ENABLE_VS();
  asm volatile("li t0, 8\n\t" "vsetvli zero, t0, e8, m1, ta, ma\n\t" ::: "t0");
  asm volatile("la a0, %0\n\t" "vle8.v v1, (a0)\n\t" :: "S"(va) : "a0", "memory");
  asm volatile("la a0, %0\n\t" "vle8.v v2, (a0)\n\t" :: "S"(vb) : "a0", "memory");
  asm volatile("csrr %0, vl" : "=r"(vl));

  // ---- 被测指令：唯一一条 vadd.vv，前后各一次 rdcycle 定窗口 ----
  c0 = rdcycle();
  asm volatile("vadd.vv v3, v1, v2\n\t" ::: "memory");
  c1 = rdcycle();
  asm volatile("la a0, %0\n\t" "vse8.v v3, (a0)\n\t" :: "S"(vout) : "a0", "memory");

  printf("WAVE_MARK c0=%llu c1=%llu vl=%llu\n",
         (unsigned long long)c0, (unsigned long long)c1, (unsigned long long)vl);
  printf("WAVE_RESULT vout=%02X %02X %02X %02X %02X %02X %02X %02X\n",
         vout[0], vout[1], vout[2], vout[3], vout[4], vout[5], vout[6], vout[7]);

  int ok = (vl == 8);
  for (i = 0; i < 8; i++) {
    if (vout[i] != (uint8_t)(va[i] + vb[i])) ok = 0;
  }
  // 高 96 位必须是 0（SPEC §1.1 写回恒清零）
  for (i = 8; i < 16; i++) {
    if (vout[i] != 0) ok = 0;
  }
  printf("WAVE verdict=%s\n", ok ? "OK" : "MISMATCH");
  return ok ? 0 : 1;
}