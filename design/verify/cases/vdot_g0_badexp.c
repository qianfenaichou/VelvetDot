// vdot_g0_badexp.c — G0 反例（ALGORITHM §3.1）：期望值被**故意写错 1 bit**（0x24 → 0x25），
// 但 DUT 与 NEMU 必然逐位一致并 GOOD TRAP；只有本用例内嵌自检（要求 CASE ...: MATCH）能抓住它。
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[8] = {1,2,3,4,5,6,7,8};
static volatile int8_t bv[8] = {1,1,1,1,1,1,1,1};
static volatile uint32_t out[4];

int main(void) {
  uint32_t res = 0;
  asm volatile(
      "li t0, 0x600\n\t" "csrs mstatus, t0\n\t"
      "li t1, 8\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "la a2, av\n\t" "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t" "vle8.v v2, (a3)\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v3\n\t"
      "la a4, out\n\t" "vse32.v v3, (a4)\n\t"
      : "=r"(res) :: "t0", "t1", "t2", "a2", "a3", "a4", "memory");
  uint32_t w1 = out[1], w2 = out[2], w3 = out[3];
  printf("CASE vdot_g0_badexp: result=0x%08X expect=0x00000025(MUTATED) hi=[0x%08X 0x%08X 0x%08X]\n",
         (uint32_t)res, w1, w2, w3);
  int ok = ((uint32_t)res == 0x00000025u) && (w1 == 0) && (w2 == 0) && (w3 == 0);
  printf("CASE vdot_g0_badexp: %s\n", ok ? "MATCH" : "MISMATCH");
  return 0;  /* 期望故意错 → 本用例必判 MISMATCH，但程序正常 GOOD TRAP */
}
