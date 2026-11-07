// xn_vill_keepl_vlmax.c — 扩容负例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xn_vill_keepl_vlmax
//@CLS negative
//@FAMILY illegal
// 说明：keep-vl（rd=x0,rs1=x0）把 VLMAX 从 32(m2) 改成 16(m1)：vsetvl 必须判非法，vill=1、vl=0
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
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m2, ta, ma\n\t"
      "vsetvli zero, zero, e8, m1, ta, ma\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "vmv.x.s %0, v3\n\t"
      ".option pop\n\t"
      : "=r"(res)
      :
      : "t0", "t1", "t4", "t5", "a2", "a3", "memory");
  printf("CASE xn_vill_keepl_vlmax: 未如期陷入非法指令 res=0x%08X\n", (unsigned int)res);
  return 1;
}
