// vdot_neg_odd5：奇数负 lane 用例，负 lane 数 n=5（ALGORITHM §3.2 混合符号奇数负 lane），专抓积的符号扩展 bug。
// 期望值由 gen.py 按 §3.1 的算法 B 独立算出，再按 32 位补码截断。
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[8] = {-7, -7, -7, -7, -7, 5, 5, 5};
static volatile int8_t bv[8] = {3, 3, 3, 3, 3, 3, 3, 3};
static volatile uint32_t out[4];

int main(void) {
  uint32_t res = 0;
  asm volatile(
      "li t0, 0x600\n\t"                 // AM 的 start.S 只开 mstatus.FS；向量还需 VS!=OFF（SPEC §1.1 第六条）
      "csrs mstatus, t0\n\t"
      "li t1, 8\n\t"
      "vsetvli zero, t1, e8,m1, ta, ma\n\t"
      "la a2, av\n\t"
      "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t"
      "vle8.v v2, (a3)\n\t"
      ""
      ".4byte 0x3A20A1D7\n\t"
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v3\n\t"
      "la a4, out\n\t"
      "vse32.v v3, (a4)\n\t"
      : "=r"(res) :: "t0", "t1", "t2", "a2", "a3", "a4", "memory");
  uint32_t w1 = out[1], w2 = out[2], w3 = out[3];
  printf("CASE vdot_neg_odd5: result=0x%08X expect=0xFFFFFFC4 hi=[0x%08X 0x%08X 0x%08X]\n",
         (uint32_t)res, w1, w2, w3);
  int ok = ((uint32_t)res == 0xFFFFFFC4u) && (w1 == 0) && (w2 == 0) && (w3 == 0);
  printf("CASE vdot_neg_odd5: %s\n", ok ? "MATCH" : "MISMATCH");
  return ok ? 0 : 1;
}
