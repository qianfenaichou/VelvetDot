// xn_vstart64_vl0.c — 扩容负例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xn_vstart64_vl0
//@CLS negative
//@FAMILY illegal
// 说明：vstart=64（2^6，需 vstart 的 bit6）且 vl=0：非法判定必须用完整 7 位 vstart 字段，且优先于 vl=0 全写（≤6 位截断会把 64 读成 0 而漏判）
// 自检：DUT/NEMU 双侧一致陷入非法（HIT CRITICAL ERROR）、无失配；若未陷入，则打印「CASE <cid>: 未如期陷入非法指令」
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[16] = {3, -5, 7, -9, 11, -13, 17, -19, 21, -23, 25, -27, 29, -31, 33, -35};
static volatile int8_t bv[16] = {-2, 4, -6, 8, -10, 12, -14, 16, -18, 20, -22, 24, -26, 28, -30, 32};

int main(void) {
  uint64_t res = 0;
  asm volatile(
      ".balign 4\n\t.option push\n\t.option norvc\n\t"
      "li t0, 0x600\n\t"
      "csrs mstatus, t0\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "la a2, av\n\t"
      "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t"
      "vle8.v v2, (a3)\n\t"
      "li t1, 0\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "li t4, 64\n\t"
      "csrw 0x008, t4\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "vmv.x.s %0, v3\n\t"
      ".option pop\n\t"
      : "=r"(res)
      :
      : "t0", "t1", "t4", "t5", "a2", "a3", "memory");
  printf("CASE xn_vstart64_vl0: 未如期陷入非法指令 res=0x%08X\n", (unsigned int)res);
  return 1;
}
