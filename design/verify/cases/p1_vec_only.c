// P1：只用标准向量指令（先开 mstatus.VS），验证「向量使能/启动」是否通
#include <am.h>
#include <klib.h>
#include <stdint.h>
int main(void) {
  uint64_t r;
  asm volatile(
      "li t0, 0x600\n\t" "csrs mstatus, t0\n\t"
      "li t1, 8\n\t" "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "vmv.v.i v1, 5\n\t"
      "li t2, 4\n\t" "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v1\n\t" : "=r"(r) :: "t0","t1","t2","memory");
  printf("PROBE p1_vec_only r=0x%08X\n", (uint32_t)r);
  return 0;
}
