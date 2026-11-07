// perf_base.c — vdot.vv 的基线分母（B1 最保守下界 / B2 主分母），口径来自 design/ALGORITHM.md §3.4
// B1 = vwmul.vv + vwredsum.vs（2 条向量计算 / 6 宏 / 11 uop）
// B2 = vwmul.vv + vwadd.vx(widen 到 32) + vredsum.vs（3 条向量计算 / 8 宏 / 17 uop）
// 两者都取 vl=8（e8 视图 8 个 int8 lane），与 vdot 的 lane 0-7 语义严格对齐，结果可逐位比对。
// 运行要求：emu 带 --no-diff（读 mcycle）。
#include <am.h>
#include <klib.h>
#include <stdint.h>

static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  1, 2, 3, 4, -5, 6, 7, -8, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 1, 1, 1, 1, 1, 1, 1, -1, -1, 2, 2, 2, 2, 2, 2
};

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

#define N 2000

// 载入 v1/v2 的 8 个 int8（e8, m1, vl=8）
#define LOAD8()                                                     \
  asm volatile(                                                     \
      "li t0, 0x600\n\t"                                             \
      "csrs mstatus, t0\n\t"                                              \
      "li t0, 8\n\t"                                                \
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"                        \
      "la a0, %0\n\t"                                               \
      "vle8.v v1, (a0)\n\t"                                         \
      "la a1, %1\n\t"                                               \
      "vle8.v v2, (a1)\n\t" ::"S"(buf_a), "S"(buf_b)                \
      : "t0", "a0", "a1", "memory")

// B1：vwmul.vv（e8→e16，8 积）→ vwredsum.vs（e16 求和成 e32）→ vmv.x.s 读回（e32 视图）
static uint64_t b1_once(uint64_t *res) {
  asm volatile(
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"      // t0 仍是 8（配置 1 已设，这里显式重申）
      "vwmul.vv v4, v1, v2\n\t"                   // 计算 1：8 个 16 位积（v4/v5）
      "li t1, 8\n\t"
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"     // 配置 2
      "vmv.v.i v6, 0\n\t"                         // 归约初值清零
      "vwredsum.vs v6, v4, v6\n\t"                // 计算 2：v6[0] = Σ v4[0..7]（32 位）
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"     // 配置 3：vmv.x.s 前必须切 e32
      "vmv.x.s %0, v6\n\t"
      : "=r"(*res) :: "t0", "t1", "t2", "memory");
  return 0;
}

// B2：vwmul.vv → vwadd.vx（16→32 widen，加零）→ vredsum.vs（32 位求和）→ vmv.x.s 读回
static uint64_t b2_once(uint64_t *res) {
  asm volatile(
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"
      "vwmul.vv v4, v1, v2\n\t"                   // 计算 1：8 个 16 位积
      "li t1, 8\n\t"
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"     // 配置 2
      "vmv.v.x v8, zero\n\t"
      "vwadd.vx v6, v4, zero\n\t"                 // 计算 2：widen 到 32 位（v6/v7）
      "li t2, 8\n\t"
      "vsetvli zero, t2, e32, m1, ta, ma\n\t"     // 配置 3
      "vmv.v.i v10, 0\n\t"                        // 归约初值
      "vredsum.vs v10, v6, v10\n\t"               // 计算 3：v10[0] = Σ v6[0..7]
      "li t3, 4\n\t"
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"     // 读回视图
      "vmv.x.s %0, v10\n\t"
      : "=r"(*res) :: "t0", "t1", "t2", "t3", "memory");
  return 0;
}

int main(void) {
  // AM 的 start.S 已完成 ioe/init_memory（apps/hello 同样不调用）
  uint64_t res, cyc, total;

  LOAD8();
  total = 0;
  for (int i = 0; i < N; i++) {
    cyc = rdcycle();
    b1_once(&res);
    total += rdcycle() - cyc;
  }
  printf("PERF B1: ops=%d cycles=%llu cycles_per_op=%llu result=0x%llX\n",
         N, (unsigned long long)total,
         (unsigned long long)(total / N), (unsigned long long)res);
  printf("VDOT_METRIC B1 %llu\n", (unsigned long long)(total / N));

  LOAD8();
  total = 0;
  for (int i = 0; i < N; i++) {
    cyc = rdcycle();
    b2_once(&res);
    total += rdcycle() - cyc;
  }
  printf("PERF B2: ops=%d cycles=%llu cycles_per_op=%llu result=0x%llX\n",
         N, (unsigned long long)total,
         (unsigned long long)(total / N), (unsigned long long)res);
  printf("VDOT_METRIC B2 %llu\n", (unsigned long long)(total / N));
  return 0;
}
