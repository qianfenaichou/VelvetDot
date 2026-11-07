// xp_loop4.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xp_loop4
//@CLS vdot-pl
//@FAMILY loop
// 说明：循环 4 次
// 期望值：单次 S 由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1（vl 不影响结果；vd[31:0]=sext32(S)，vd[127:32]=0）
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t op1[16] = {3, -5, 7, -9, 11, -13, 17, -19, 21, -23, 25, -27, 29, -31, 33, -35};
static volatile int8_t op2[16] = {-2, 4, -6, 8, -10, 12, -14, 16, -18, 20, -22, 24, -26, 28, -30, 32};

int main(void) {
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
  const uint32_t want = 0xFFFFFC4Cu;
  uint64_t sum = 0;
  for (int it = 0; it < 4; it++) {
    uint32_t r = 0;
    asm volatile(
        ".balign 4\n\t.option push\n\t.option norvc\n\t"
        "li t1, 16\n\t"
        "vsetvli zero, t1, e8, m1, ta, ma\n\t"
        "la a2, op1\n\t"
        "vle8.v v1, (a2)\n\t"
        "la a3, op2\n\t"
        "vle8.v v2, (a3)\n\t"
        ".4byte 0x3A20A1D7\n\t"
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v3\n\t"
        ".option pop\n\t"
        : "=r"(r)
        :
        : "t1", "t2", "a2", "a3", "memory");
    sum += r;
  }
  int fails = 0;
  if (sum != (uint64_t)want * 4) {
    fails++;
    printf("EXTRA xp_loop4 sum=0x%llX want=0x%llX\n", (unsigned long long)sum,
           (unsigned long long)((uint64_t)want * 4));
  }
  printf("EXTRA xp_loop4 iters=4 fails=%d\n", fails);
  printf("CASE xp_loop4: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA xp_loop4 verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
