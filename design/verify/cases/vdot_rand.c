// vdot_rand.c — §3.2 随机类：固定种子 42 的 1024 组，高 64 位填随机干扰，
// 期望值由 §3.1 算法 B（int64 逐项累加）在 C 侧独立计算，与 DUT/金模型交叉对照。
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile uint32_t out[4];

static inline uint32_t lcg(uint32_t *s) { *s = *s * 1664525u + 1013904223u; return *s; }

static long long algo_b(const int8_t *a, const int8_t *b) {
  long long s = 0;
  for (int i = 0; i < 8; i++) s += (long long)a[i] * (long long)b[i];
  return s;
}

int main(void) {
  uint32_t seed = 42;
  int groups = 1024, mism = 0, ab_bad = 0;
  int8_t a[16], b[16];
  for (int g = 0; g < groups; g++) {
    for (int i = 0; i < 16; i++) {
      a[i] = (int8_t)(lcg(&seed) >> 24);
      b[i] = (int8_t)(lcg(&seed) >> 16);
    }
    long long want = algo_b(a, b);
    uint32_t want32 = (uint32_t)(int32_t)want;
    uint32_t got = 0;
    register uint8_t *pa = (uint8_t *)a;
    register uint8_t *pb = (uint8_t *)b;
    register uint32_t *pout = (uint32_t *)out;
    asm volatile(
        "li t0, 0x600\n\t"                   // AM start.S 只开 mstatus.FS；向量还需 VS!=OFF
        "csrs mstatus, t0\n\t"               // （SPEC §1.1 第六条）：无序言时第一条向量指令即非法陷入
        "li t1, 16\n\t"
        "vsetvli zero, t1, e8, m1, ta, ma\n\t"
        "vle8.v v1, (%0)\n\t"
        "vle8.v v2, (%1)\n\t"
        ".4byte 0x3A20A1D7\n\t"      /* vdot.vv v3, v1, v2：只取低 64 位 lane 0-7 */
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %2, v3\n\t"
        "vse32.v v3, (%3)\n\t"
        : "+r"(pa), "+r"(pb), "=r"(got), "+r"(pout)
        :: "t0", "t1", "t2", "memory");
    if (got != want32) mism++;
    if (out[1] != 0 || out[2] != 0 || out[3] != 0) ab_bad++;
  }
  printf("RAND_SUMMARY groups=%d mism=%d ab_bad=%d\n", groups, mism, ab_bad);
  return (mism == 0 && ab_bad == 0) ? 0 : 1;
}
