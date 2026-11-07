// P2：同 P1 但**不开** mstatus.VS —— 按 SPEC 第六条应触发非法（预期 CRITICAL）
#include <am.h>
#include <klib.h>
#include <stdint.h>
int main(void) {
  uint64_t r;
  asm volatile(
      "li t1, 8\n\t" "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      "vmv.v.i v1, 5\n\t"
      "li t2, 4\n\t" "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v1\n\t" : "=r"(r) :: "t1","t2","memory");
  printf("PROBE p2_vec_novs r=0x%08X（若出现说明 VS 未拦）\n", (uint32_t)r);
  return 0;
}
