// perf_base.c — vdot.vv 的基线分母（B1 最保守下界 / B2 主分母），口径来自 design/ALGORITHM.md §3.4
// B1 = vwmul.vv + vwredsum.vs（2 条向量计算 / 6 宏 / 11 uop）
// B2 = vwmul.vv + vwadd.vx(widen 到 32) + vredsum.vs（3 条向量计算 / 8 宏 / 17 uop）
// 两者都取 **VL=8**（e8 视图 8 个 int8 lane），与 vdot 的 lane 0-7 语义严格对齐，结果可逐位比对；
// 这是 HARD-DESIGN §6① 的 T5 裁决（L_vadd/L_vmacc/L_vdot 与 B1/B2 同 VL=8 同天平）。
// 每个计算块用 `vsetivli zero, 8, e8, …` 显式重设 VL：vsetivli 是立即数形式，
// 不依赖上一块 asm 留在 t0 里的 8（t0 在 clobber 表里，跨块读它是未定义行为）。
// 运行要求：emu 带 --no-diff（读 mcycle）。
#include <am.h>
#include <klib.h>
#include <stdint.h>

static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
// buf_b 低 8 字节特意选 {1,0,0,0,1,1,1,3}：前 4 个积之和 = 18，全 8 个积之和 = 8。
// 旧数据（前 4 积和 = 全 8 积和）让 B2 的 e32,m1→m2 修复（vl 从 4 恢复到 8）在结果上
// 完全不可见；这组数据下错误配置必然读出 18 ≠ 8。
// buf_a/buf_b 与 perf_vdot.c / perf_vadd.c / perf_vmacc.c 逐字节相同（同一天平）。
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

// 8 个 int8 lane 的点积期望（算法 A：逐项有符号）
static int32_t want_dot(void) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

// 只归约前 4 lane 的「错误配置」会读出的值：B2 若把配置 3 写成 e32,m1（VLMAX=4），
// avl=8 会被钳到 4 ⇒ 结果 = 这个数。用例要求 result == want_dot()，两者不等即可证伪。
static int32_t want_dot_vl4(void) {
  int32_t s = 0;
  for (int i = 0; i < 4; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// AM 的 start.S 只开 FS；任何向量指令（包括 -O2 把 want_dot() 自动向量化生成的指令）
// 执行前必须先把 mstatus.VS 置为非 OFF（SPEC §1.1 第六条）。
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

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
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"      // 配置 1：VL=8（立即数形式，不读跨块残留的 t0）
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
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"      // 配置 1：VL=8（立即数形式，不读跨块残留的 t0）
      "vwmul.vv v4, v1, v2\n\t"                   // 计算 1：8 个 16 位积
      "li t1, 8\n\t"
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"     // 配置 2
      "vmv.v.x v8, zero\n\t"
      "vwadd.vx v6, v4, zero\n\t"                 // 计算 2：widen 到 32 位（v6/v7）
      "li t2, 8\n\t"
      // 配置 3 必须 e32,m2：VLMAX(e32,m1)=VLEN/32=4，avl=8 会被钳到 vl=4，只归约 v6[0..3]（4 个积，
      // 不是 8 个）——那既不是 VL=8 同天平，也不是"8 个 int8 的点积"分母。LMUL=2 才是 VLMAX=8。
      "vsetvli zero, t2, e32, m2, ta, ma\n\t"     // 配置 3：VL=8（e32,m2 ⇒ VLMAX=8）
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
  // 先开 VS：want_dot() 在 -O2 下会被 GCC 自动向量化，不能等 LOAD8() 才开；
  // LOAD8() 还会再做一次（幂等），并在每次测量前重新装载 v1/v2。
  ENABLE_VS();
  uint64_t res, cyc, total;
  int32_t want = want_dot();
  int32_t want4 = want_dot_vl4();
  int ok1, ok2;
  // 「数据能分辨 vl」的前提：错误配置（只归约前 4 lane）会读出另一个值。
  int data_discriminates = (want != want4);
  printf("PERF base: want_vl8=0x%08X want_vl4=0x%08X discriminates=%s\n",
         (uint32_t)want, (uint32_t)want4, data_discriminates ? "yes" : "no");

  LOAD8();
  total = 0;
  for (int i = 0; i < N; i++) {
    cyc = rdcycle();
    b1_once(&res);
    total += rdcycle() - cyc;
  }
  ok1 = ((int32_t)res == want);
  printf("PERF B1: ops=%d cycles=%llu cycles_per_op=%llu result=0x%08X want=0x%08X match=%s\n",
         N, (unsigned long long)total,
         (unsigned long long)(total / N), (uint32_t)res, (uint32_t)want,
         ok1 ? "OK" : "MISMATCH");
  printf("VDOT_METRIC B1 %llu\n", (unsigned long long)(total / N));

  LOAD8();
  total = 0;
  for (int i = 0; i < N; i++) {
    cyc = rdcycle();
    b2_once(&res);
    total += rdcycle() - cyc;
  }
  ok2 = ((int32_t)res == want);
  int b2_not_vl4 = ((int32_t)res != want4);
  printf("PERF B2: ops=%d cycles=%llu cycles_per_op=%llu result=0x%08X want=0x%08X "
         "not_vl4=%s match=%s\n",
         N, (unsigned long long)total,
         (unsigned long long)(total / N), (uint32_t)res, (uint32_t)want,
         b2_not_vl4 ? "yes" : "no", ok2 ? "OK" : "MISMATCH");
  printf("VDOT_METRIC B2 %llu\n", (unsigned long long)(total / N));

  int ok = ok1 && ok2 && data_discriminates && b2_not_vl4;
  printf("PERF_BASE verdict=%s B1=%s B2=%s b2_not_vl4=%s discriminates=%s "
         "want=0x%08X want_vl4=0x%08X\n",
         ok ? "ALL_OK" : "HAS_FAIL", ok1 ? "OK" : "MISMATCH",
         ok2 ? "OK" : "MISMATCH", b2_not_vl4 ? "yes" : "no",
         data_discriminates ? "yes" : "no", (uint32_t)want, (uint32_t)want4);
  return ok ? 0 : 1;
}
