// vdot_ill_vs — 非法组合：mstatus.VS=OFF（先开 VS 再关，唯一变量是 VS）（negative 类，期望 difftest 双侧一致陷入非法）
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[8] = {1,2,3,4,5,6,7,8};
static volatile int8_t bv[8] = {1,1,1,1,1,1,1,1};

int main(void) {
  uint64_t res = 0;
  asm volatile(
      "li t0, 0x600\n\t"
      "csrs mstatus, t0\n\t"
      "li t1, 8\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "la a2, av\n\t"
      "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t"
      "vle8.v v2, (a3)\n\t"
      "li t4, 0x600\n\t"
      "csrc mstatus, t4\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "vmv.x.s %0, v3\n\t"
      : "=r"(res) :: "t0", "t1", "t4", "t5", "a2", "a3", "memory");
  printf("CASE vdot_ill_vs: 未如期陷入非法指令 res=0x%08X\n", (uint32_t)res);
  return 1;
}
