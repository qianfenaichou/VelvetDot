// vdot_wave.c — 交付物 2.2 的 vdot.vv **波形取证**用例（唯一一条 vdot.vv + 自报 mcycle 窗口）
//
// 与 vadd_wave.c（stage1/1.3-vadd/cases/vadd_wave.c）同构：程序自己用 rdcycle 圈出窗口，
// 供 core-package/scripts/62-wave-vdot.sh 的窄窗 --dump-wave 定位；窗口前后不夹其它向量指令。
//
// 为什么用 mcycle 当时间轴：Rob.scala:1607 `difftest.cycleCnt := timer`，emu 的 trap->cycleCnt
//   与 mcycle 同源（见 difftest/src/test/csrc/verilator/waveform.cpp:59 `tfp->dump(waveform_clock)`）。
//   读 mcycle 会与 NEMU 参照的 CSR 不一致 ⇒ 运行必须带 --no-diff（同 perf_vadd.c / vadd_wave.c 口径）。
//   实测 mcycle 与 VCD 时间戳有固定偏移（1.3 实测 c0=8424 而指令在 #8416），所以脚本按
//   「指令字在译码级 valid=1」定锚点，不靠这个偏移。
//
// 指令与编码（SPEC §2.1）：vdot.vv v3, v2, v1 = 0x3A20A1D7
//   funct6=001110 / vm=1 / vs2=2 / vs1=1 / funct3=010 / vd=3 / opcode=1010111
//   ⇒ 波形里用这个机器码在译码级 io_in_<slot>_bits_instr 上定位本条指令。
//
// 语义（SPEC §1.1）：S = Σ_{i=0..7} sext19(sext8(vs1[i]) × sext8(vs2[i]))，只取 vs1/vs2 的低 64 位；
//   vd[31:0] = sext32(S)，vd[127:32] = 0（恒清零）。
//
// 操作数（16 字节整寄存器；**高 8 字节是干扰位**，按 SPEC 不参与运算）：
//   v1 = 0xA55A18810FF03CC3_88796A5B4C3D2E1F   lane0..7 = 1F 2E 3D 4C 5B 6A 79 88
//   v2 = 0x9669B44BD22DE77E_938475665748392A   lane0..7 = 2A 39 48 57 66 75 84 93
//   有符号 lane0..7：v1 = (31, 46, 61, 76, 91, 106, 121, -120)
//                    v2 = (42, 57, 72, 87, 102, 117, -124, -109)
//   逐 lane 积 = 1302, 2622, 4392, 6612, 9282, 12402, -15004, 13080
//   ⇒ S = 34688 = 0x00008780（19 位有符号范围内；sext32 后仍是 0x00008780）
//   期望 vd = 0x00000000_00000000_00000000_00008780
//
// 反例判别（本用例的核心断言之一）：若实现把 16 个 lane 全算进去（高 64 位没被排除），
//   S = 31839 = 0x7C5F ≠ 0x8780。⇒ 结果等于 0x8780 就同时证明了「只取低 64 位」。
//   期望值由 design/verify/vdot_model.py 算出（下面自算复核用同一常量）：
//     python3 -I -c "import sys;sys.path.insert(0,'design/verify');import vdot_model as m;
//       print(m.vdot_vv(0xA55A18810FF03CC388796A5B4C3D2E1F, 0x9669B44BD22DE77E938475665748392A))"
//     → 0x8780（高 96 位为 0）
//
// 构建：由 design/verify/cases/build_cases.sh（glob `vdot_*.c`）或 build_all.sh 自动纳入，
//   产物 vdot_wave.bin；**不写入 manifest.tsv**（30 例清单 sha256 冻结，本用例是清单外的取证作业）。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// AM 的 start.S 只开 mstatus.FS；向量指令还要求 mstatus.VS != OFF（SPEC §1.1 第六条）
#define ENABLE_VS() asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

// v1 / v2 的 16 字节：低 8 字节参与运算，高 8 字节是干扰位（SPEC §1.1「高 64 位不参与」）
static uint8_t va[16] __attribute__((aligned(16))) = {
  0x1F, 0x2E, 0x3D, 0x4C, 0x5B, 0x6A, 0x79, 0x88,
  0xC3, 0x3C, 0xF0, 0x0F, 0x81, 0x18, 0x5A, 0xA5
};
static uint8_t vb[16] __attribute__((aligned(16))) = {
  0x2A, 0x39, 0x48, 0x57, 0x66, 0x75, 0x84, 0x93,
  0x7E, 0xE7, 0x2D, 0xD2, 0x4B, 0xB4, 0x69, 0x96
};
static uint32_t out[4] __attribute__((aligned(16)));

#define EXPECT_LOW32 0x00008780u   // S = 34688，sext32 后低 32 位
#define WRONG_ALL16  0x00007C5Fu   // 若误把 16 lane 全算进去会得到的值（必须不等于结果）

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

int main(void) {
  uint64_t vl = 0, c0 = 0, c1 = 0;
  uint32_t res = 0;

  ENABLE_VS();
  // vl=16（VLMAX(e8,m1)=16）：两个 vle8.v 把 16 字节整寄存器装满（含高 64 位干扰位）。
  // vl 不是 vdot 的合法条件之一（SPEC §1.1 六条只约束 SEW/LMUL/vm/vstart/vill/VS），
  // 且 vl 不影响结果（lane 0..7 无条件全算）。
  asm volatile("li t0, 16\n\t" "vsetvli zero, t0, e8, m1, ta, ma\n\t" ::: "t0");
  asm volatile("la a0, %0\n\t" "vle8.v v1, (a0)\n\t" :: "S"(va) : "a0", "memory");
  asm volatile("la a0, %0\n\t" "vle8.v v2, (a0)\n\t" :: "S"(vb) : "a0", "memory");
  asm volatile("csrr %0, vl" : "=r"(vl));

  // ---- 被测指令：唯一一条 vdot.vv，前后各一次 rdcycle 定窗口 ----
  c0 = rdcycle();
  // .4byte 而非助记符：交叉工具链的 as 不认自定义 vdot.vv（30 例用例同一写法）
  asm volatile(".4byte 0x3A20A1D7\n\t" ::: "memory");
  c1 = rdcycle();

  // 读回：先取 vd[31:0]（e32 视图 vmv.x.s），再整 128 位落内存（vse32.v ×4 = 16 字节）
  asm volatile(
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v3\n\t"
      "la a4, %1\n\t"
      "vse32.v v3, (a4)\n\t"
      : "=r"(res) : "S"(out) : "t2", "a4", "memory");

  uint32_t w1 = out[1], w2 = out[2], w3 = out[3];
  printf("WAVE_MARK c0=%llu c1=%llu vl=%llu\n",
         (unsigned long long)c0, (unsigned long long)c1, (unsigned long long)vl);
  printf("WAVE_RESULT vd=0x%08X%08X%08X%08X low32=0x%08X\n",
         w3, w2, w1, out[0], (uint32_t)res);
  printf("WAVE_EXPECT vd=0x00000000000000000000000000008780 wrong_all16=0x%08X\n", WRONG_ALL16);

  // 判据：低 32 位 = 0x8780；高 96 位 = 0；vl=16；且不是「16 lane 全算」的 0x7C5F
  int ok = ((uint32_t)res == EXPECT_LOW32) && (out[0] == EXPECT_LOW32) &&
           (w1 == 0) && (w2 == 0) && (w3 == 0) &&
           (vl == 16) && (out[0] != WRONG_ALL16);
  printf("WAVE verdict=%s\n", ok ? "OK" : "MISMATCH");
  return ok ? 0 : 1;
}
