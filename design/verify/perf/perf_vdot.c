// perf_vdot.c — vdot.vv 的三个「本指令」口径：L_vdot（真 RAW 链延迟）、T_steady（背靠背吞吐）、T_kernel
// 依据 design/ALGORITHM.md §3.4：L_vdot = 依赖链 latency（官方主口径），T_steady = cyc/dot。
// VL 口径：**全流程 VL=8**（L_vadd/L_vmacc/L_vdot 三链统一 VL=8，可直接横向比较）。
// 计数口径（与 perf_vadd.c / perf_vmacc.c 逐项一致，三者才可 apples-to-apples）：
//   L_vdot = N_RAW 次「逐次 rdcycle 取差」样本的中位数（前 16 次暖机不计）—— 主指标
//   日志里 mean / median 分列；`cycles_per_op=` 是 median 的别名（官方口径），不是均值。
// 运行要求：emu 必须带 --no-diff（读 mcycle 会与 NEMU 参照不一致，见 §3.4 计数口径）。
//
// 链自检为什么用**两种长度**（2026-11-03 修「虚假通过」）：
//   旧版只用一条 N=2000 的链做结果比对，而该链在 12 次后进入不动点 114（0x72），
//   只跑 13 次也会打出 chain=OK。现在对同一操作数分别跑 N_RAW=2000 与 N_ALT=1999，
//   各自与独立模型算出的期望比对：8 位 lane 的周期 ≤64，任何「固定截断到 k 次」的实现
//   不可能同时满足 k≡2000 与 k≡1999 两个余数，因此截断必被抓到。
//   操作数 buf_a={18,1,-1,1,-1,0,0,-3} 另外经过筛选：vdot 链前 2000 个状态互不相同
//   （2000 个状态 2000 个不同值），单值检查本身也已是 N 敏感的。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// vdot.vv 自定义编码：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111
// VDOT_ENC(3,1,2) == 0x3A20A1D7（SPEC §2.1 的机器码，用作自检）
#define VDOT_ENC(vd, vs1, vs2) \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) | \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

#define EMIT_VDOT(vd, vs1, vs2) \
  asm volatile(".4byte %0" :: "i"(VDOT_ENC(vd, vs1, vs2)) : "memory")

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// AM 的 start.S 只开 FS；任何向量指令（包括 -O2 把 want_chain()/want_dot() 自动向量化
// 生成的指令）执行前必须先把 mstatus.VS 置为非 OFF（SPEC §1.1 第六条）。
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

#define VL       8     // SEW=8 / LMUL=1 / VL=8（三链统一口径）
#define N_RAW    2000  // 依赖链条数（与 perf_vadd.c / perf_vmacc.c 同规模）
#define N_ALT    1999  // 第二种长度：截断实现无法同时满足两个余数（见文件头）
#define N_WARMUP 16    // 冷启动/流水线填充样本，不计入统计
#define N_STD    4000  // 背靠背条数（8 路独立 vd × 500 轮）
#define HIST_MAX 4096  // 中位直方图上界；越界计入 over 并显式打印，不静默截断

// lane 0-7 的 int8 数据；VL=8 下 `vle8.v` 只载入前 8 字节（数组留 16 字节只为 16B 对齐）。
// 与 perf_vadd.c / perf_vmacc.c / perf_base.c 逐字节相同（同一天平）。
// buf_b 低 8 字节 {1,0,0,0,1,1,1,3} 是故意选的：点积 vl=8 → 8，只归约前 4 lane → 18，
// 两者不等，B2 的 e32,m1 误配（vl 被钳到 4）在结果上必然可见。
static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

static uint16_t hist[HIST_MAX];

// 单条 vdot 的点积期望（vs1=buf_a、vs2=buf_b）—— 8
static int32_t want_dot(void) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

// RAW 链期望：vdot.vv v10, v10, v1（标准顺序 vd, vs2, vs1 ⇒ vd==vs2），
// 初值 v10 = v1 = buf_a；按 SPEC §1.1 逐步模拟 len 次（写回 vd[31:0]、高 96 位每拍清零）。
static int32_t want_chain(int len) {
  uint8_t v[8];
  int32_t s = 0;
  for (int i = 0; i < 8; i++) v[i] = buf_a[i];
  for (int n = 0; n < len; n++) {
    s = 0;
    for (int i = 0; i < 8; i++)
      s += (int32_t)(int8_t)v[i] * (int32_t)(int8_t)buf_a[i];
    uint32_t w = (uint32_t)s;
    for (int i = 0; i < 4; i++) v[i] = (uint8_t)(w >> (8 * i));
    for (int i = 4; i < 8; i++) v[i] = 0;   // vd[127:32] 恒零
  }
  return s;
}

// SEW=8 / LMUL=1 / VL=8：v1 <- buf_a、v2 <- buf_b，v10 <- v1（链起点确定 ⇒ 结果可自检）；
// 返回硬件实际生效的 vl（VL 口径自检，防「写了 vl=8 实际不是 8」）。
static uint64_t load_operands(void) {
  uint64_t vl;
  ENABLE_VS();
  asm volatile(
      "li t0, 8\n\t"
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"
      "la a0, %1\n\t"
      "vle8.v v1, (a0)\n\t"
      "la a0, %2\n\t"
      "vle8.v v2, (a0)\n\t"
      "vmv.v.v v10, v1\n\t"
      "csrr %0, vl\n\t"
      : "=r"(vl)
      : "S"(buf_a), "S"(buf_b)
      : "t0", "a0", "memory");
  return vl;
}

// 逐次 rdcycle 取差（计数法同 perf_vadd.c / perf_vmacc.c），出中位/均值/极值。
// len 是链条数（会跑 N_RAW 与 N_ALT 两种长度）。
static uint64_t measure_raw_chain(int len, uint64_t *out_sum, uint64_t *out_mean,
                                  uint64_t *out_median, uint64_t *out_min,
                                  uint64_t *out_max, uint64_t *out_over) {
  uint64_t c0, c1, d, sum = 0, mn = ~0ULL, mx = 0, over = 0, median = 0;
  const uint32_t n = (uint32_t)(len - N_WARMUP);
  uint32_t acc = 0;

  for (int i = 0; i < HIST_MAX; i++) hist[i] = 0;

  load_operands();
  for (int i = 0; i < len; i++) {
    c0 = rdcycle();
    // vdot.vv v10, v10, v1（标准顺序 vd, vs2, vs1）⇒ vd==vs2，相邻两次是真 RAW 依赖
    EMIT_VDOT(10, 1, 10);
    c1 = rdcycle();
    d = c1 - c0;
    if (i < N_WARMUP) continue;
    sum += d;
    if (d < mn) mn = d;
    if (d > mx) mx = d;
    if (d >= HIST_MAX) { over++; d = HIST_MAX - 1; }
    hist[d]++;
  }
  // 中位 = 直方图前缀和跨过 n/2 的那个 bin
  for (uint32_t v = 0; v < HIST_MAX; v++) {
    acc += hist[v];
    if (acc > n / 2) { median = v; break; }
  }
  *out_sum = sum;
  *out_mean = sum / n;
  *out_median = median;
  *out_min = mn;
  *out_max = mx;
  *out_over = over;

  // 读回必须在 e32 视图下（留在 load_operands 的 e8/vl=8 视图只能读低 8 位）
  uint64_t r;
  asm volatile(
      "li t0, 4\n\t"
      "vsetvli zero, t0, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v10\n\t"
      : "=r"(r) :: "t0", "memory");
  return r;
}

// 旧口径：整段 len 条链的墙钟 / len（只附报，不参与主指标）
static uint64_t measure_loop_total(int len, uint64_t *out_cycles) {
  uint64_t c0, c1, r;
  load_operands();
  c0 = rdcycle();
  for (int i = 0; i < len; i++) {
    EMIT_VDOT(10, 1, 10);
  }
  c1 = rdcycle();
  *out_cycles = c1 - c0;
  asm volatile(
      "li t0, 4\n\t"
      "vsetvli zero, t0, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v10\n\t"
      : "=r"(r) :: "t0", "memory");
  return r;
}

// T_steady：8 条互相独立的 vdot（vd=v8..v15，源恒为 v1/v2），测稳态 cyc/dot
static uint64_t measure_steady(uint64_t *out_cycles) {
  uint64_t c0, c1;
  load_operands();
  c0 = rdcycle();
  for (int i = 0; i < N_STD / 8; i++) {
    EMIT_VDOT(8, 1, 2);
    EMIT_VDOT(9, 1, 2);
    EMIT_VDOT(10, 1, 2);
    EMIT_VDOT(11, 1, 2);
    EMIT_VDOT(12, 1, 2);
    EMIT_VDOT(13, 1, 2);
    EMIT_VDOT(14, 1, 2);
    EMIT_VDOT(15, 1, 2);
  }
  c1 = rdcycle();
  *out_cycles = c1 - c0;
  uint64_t r;
  asm volatile(
      "li t0, 4\n\t"
      "vsetvli zero, t0, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v15\n\t"
      : "=r"(r) :: "t0", "memory");
  return r;
}

// 打印一行 PERF：mean / median 分列，cycles_per_op 是 median 的别名（官方口径）。
static void print_chain_line(const char *tag, int len, uint64_t sum, uint64_t mean,
                             uint64_t median, uint64_t mn, uint64_t mx, uint64_t over,
                             uint64_t got, int32_t want, int ok) {
  printf("PERF %s : ops=%d cycles=%llu mean=%llu median=%llu cycles_per_op=%llu "
         "min=%llu max=%llu over=%llu result=0x%08X want=0x%08X chain=%s\n",
         tag, len - N_WARMUP, (unsigned long long)sum,
         (unsigned long long)mean, (unsigned long long)median,
         (unsigned long long)median, (unsigned long long)mn,
         (unsigned long long)mx, (unsigned long long)over,
         (uint32_t)got, (uint32_t)want, ok ? "OK" : "MISMATCH");
}

int main(void) {
  // AM 的 start.S 已完成 ioe/init_memory（apps/hello 同样不调用）
  // 先开 VS：want_chain()/want_dot() 在 -O2 下会被 GCC 自动向量化，
  // 不能假设后面的 load_operands() 一定先执行；load_operands() 内还会再做一次（幂等）。
  ENABLE_VS();

  uint32_t enc = VDOT_ENC(3, 1, 2);
  int enc_ok = (enc == 0x3A20A1D7u);
  printf("PERF vdot: enc_check=0x%08X expect=0x3A20A1D7 %s\n", enc,
         enc_ok ? "OK" : "MISMATCH");

  uint64_t vl = load_operands();
  int vl_ok = (vl == VL);
  printf("PERF vdot: vl=%llu expect=%d %s\n", (unsigned long long)vl, VL,
         vl_ok ? "OK" : "MISMATCH");

  int32_t want_dot_v = want_dot();
  int32_t want_raw = want_chain(N_RAW);
  int32_t want_alt = want_chain(N_ALT);

  // ---- 主口径 L_vdot：N_RAW ----
  uint64_t sum, mean, median, mn, mx, over;
  uint64_t r_raw = measure_raw_chain(N_RAW, &sum, &mean, &median, &mn, &mx, &over);
  int chk_raw = ((int32_t)r_raw == want_raw);
  print_chain_line("L_vdot", N_RAW, sum, mean, median, mn, mx, over, r_raw, want_raw, chk_raw);
  printf("VDOT_METRIC L_vdot %llu\n", (unsigned long long)median);
  printf("VDOT_METRIC L_vdot_mean %llu\n", (unsigned long long)mean);

  // ---- 长度判别：N_ALT（同一操作数、不同长度；截断实现不可能两个都对）----
  uint64_t s2, m2, md2, mn2, mx2, ov2;
  uint64_t r_alt = measure_raw_chain(N_ALT, &s2, &m2, &md2, &mn2, &mx2, &ov2);
  int chk_alt = ((int32_t)r_alt == want_alt);
  print_chain_line("L_vdot_alt", N_ALT, s2, m2, md2, mn2, mx2, ov2, r_alt, want_alt, chk_alt);
  // 长度判别的有效性前提：两种长度必须给出**不同的**期望值，否则第二条链白跑。
  int alt_differs = (want_raw != want_alt);

  // ---- 旧口径（整段墙钟 / N）：只附报 ----
  uint64_t cyc_loop;
  uint64_t r_loop = measure_loop_total(N_RAW, &cyc_loop);
  int chk_loop = ((int32_t)r_loop == want_raw);
  printf("PERF L_vdot_loop : ops=%d cycles=%llu mean=%llu cycles_per_op=%llu "
         "result=0x%08X want=0x%08X chain=%s\n",
         N_RAW, (unsigned long long)cyc_loop,
         (unsigned long long)(cyc_loop / N_RAW),
         (unsigned long long)(cyc_loop / N_RAW),
         (uint32_t)r_loop, (uint32_t)want_raw, chk_loop ? "OK" : "MISMATCH");
  printf("VDOT_METRIC L_vdot_loop %llu\n", (unsigned long long)(cyc_loop / N_RAW));

  // ---- T_steady ----
  uint64_t cyc;
  uint64_t r_std = measure_steady(&cyc);
  int chk_std = ((int32_t)r_std == want_dot_v);
  printf("PERF T_steady: ops=%d cycles=%llu mean=%llu cycles_per_op=%llu "
         "result=0x%08X want=0x%08X chain=%s\n",
         N_STD, (unsigned long long)cyc,
         (unsigned long long)(cyc / N_STD), (unsigned long long)(cyc / N_STD),
         (uint32_t)r_std, (uint32_t)want_dot_v, chk_std ? "OK" : "MISMATCH");
  printf("VDOT_METRIC T_steady %llu\n", (unsigned long long)(cyc / N_STD));

  // ---- T_kernel：含配置/载入/读回的整段（单条 vdot）----
  uint64_t k0 = rdcycle();
  load_operands();
  EMIT_VDOT(3, 1, 2);
  uint64_t r3;
  asm volatile(
      "li t0, 4\n\t"
      "vsetvli zero, t0, e32, m1, tu, mu\n\t"
      "vmv.x.s %0, v3\n\t"
      : "=r"(r3) :: "t0", "memory");
  uint64_t k1 = rdcycle();
  int chk_kernel = ((int32_t)r3 == want_dot_v);
  printf("PERF T_kernel: cycles=%llu result=0x%08X want=0x%08X chain=%s\n",
         (unsigned long long)(k1 - k0), (uint32_t)r3, (uint32_t)want_dot_v,
         chk_kernel ? "OK" : "MISMATCH");
  printf("VDOT_METRIC T_kernel %llu\n", (unsigned long long)(k1 - k0));

  int ok = enc_ok && vl_ok && chk_raw && chk_alt && alt_differs && chk_loop &&
           chk_std && chk_kernel;
  printf("PERF_VDOT verdict=%s enc=%s vl=%s raw=%s alt=%s alt_differs=%s loop=%s "
         "steady=%s kernel=%s\n",
         ok ? "ALL_OK" : "HAS_FAIL", enc_ok ? "OK" : "MISMATCH",
         vl_ok ? "OK" : "MISMATCH", chk_raw ? "OK" : "MISMATCH",
         chk_alt ? "OK" : "MISMATCH", alt_differs ? "yes" : "no",
         chk_loop ? "OK" : "MISMATCH", chk_std ? "OK" : "MISMATCH",
         chk_kernel ? "OK" : "MISMATCH");
  return ok ? 0 : 1;
}
