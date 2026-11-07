// P3：P1 之后追加 vdot.vv（SEW=8/LMUL=1/vm=1/vstart=0/VS=ON 六条件全合法）
#include <am.h>
#include <klib.h>
#include <stdint.h>
static volatile int8_t av[8] = {1,2,3,4,5,6,7,8};
static volatile int8_t bv[8] = {1,1,1,1,1,1,1,1};
int main(void) {
  uint64_t r;
  asm volatile(
      "li t0, 0x600\n\t" "csrs mstatus, t0\n\t"
      "li t1, 8\n\t" "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "la a2, av\n\t" "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t" "vle8.v v2, (a3)\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "li t2, 4\n\t" "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v3\n\t" : "=r"(r) :: "t0","t1","t2","a2","a3","memory");
  printf("PROBE p3_vdot r=0x%08X expect=0x00000024\n", (uint32_t)r);
  return (uint32_t)r == 0x24u ? 0 : 1;
}
