// perf_vadd.c — L_vadd：vadd.vv 的 RAW 依赖链延迟（ΔL 三链的基线分母）
// 依据：ΔL 三链口径「L_vadd/L_vmacc/L_vdot 同 VL=8 同天平」；
//       design/ALGORITHM.md §3.4「L = 依赖链 latency（官方主口径）」。
// 天平：与 design/verify/perf/perf_vdot.c 的 L_vdot 逐项对齐 ——
//   同一份操作数（buf_a/buf_b，逐字节相同）、同一条「vd == vs2」真 RAW 链、
//   同一种 rdcycle 计数；三链都统一成 vd==vs2（旧版 vmacc 写成 vd==vs1，
//   vs1/vs2 端口差异会污染 ΔL 的对比）。标准汇编顺序是 `vd, vs2, vs1`。
// 口径（分列打印，主指标唯一）：
//   L_vadd      = N_RAW 次「逐次 rdcycle 取差」样本的**中位数** —— 主指标，供 ΔL 三链对比
//   L_vadd_mean = 同批样本均值 —— 附报；与中位数一致说明无长尾
//   L_vadd_loop = 旧版「整段循环 / N」口径 —— 附报，只用于和历史 6/1 对拍
//   日志里 `cycles_per_op=` 是 median 的别名（官方口径），**不是**均值。
// 链自检（2026-11-03 修「空绿」）：v10[0] 每拍 +v1[0]，跑满 N 次后 lane0 = N*buf_a[0] mod 256。
//   单跑 N_RAW=2000 时 lane0 = 0xA0；再跑 N_ALT=1999 得 0x8E（=1999*18 & 0xFF）。两者不同 ⇒ 任何「固定截断到 k 次」
//   的实现不可能同时满足两个余数。（旧版只查一个 8 位值，且 2000 与 1999 未配对验证。）
// 运行要求：emu 必须带 --no-diff（读 mcycle 会与 NEMU 参照不一致，见 ALGORITHM §3.4 计数口径）。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// AM 的 start.S 只开 mstatus.FS；向量指令还需 mstatus.VS != OFF（SPEC §1.1 第六条）
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// 与 perf_vdot.c 逐字节相同：同一天平要求三链喂同一份数据。
// buf_b 低 8 字节 {1,0,0,0,1,1,1,3} 是故意选的：点积 vl=8 → 8、只归约前 4 lane → 18，
// B2 的 e32,m1 误配在结果上必然可见（见 perf_base.c）。
static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

#define VL       8     // SEW=8 / LMUL=1 / VL=8（ΔL 三链统一口径）
#define N_RAW    2000  // 依赖链条数（与 perf_vdot.c 的 L_vdot 同规模）
#define N_ALT    1999  // 第二种长度：与 N_RAW 的余数不同 ⇒ 截断实现必被抓
#define N_WARMUP 16    // 冷启动/流水线填充样本，不计入统计
#define HIST_MAX 4096  // 中位直方图上界；越界计入 over 并显式打印，不静默截断

static uint16_t hist[HIST_MAX];

// 链期望：v10 lane0 初值 0，每拍 += v1[0]（= buf_a[0]）；SEW=8 ⇒ 模 2^8
static uint8_t want_chain_lane0(int len) {
  return (uint8_t)((uint32_t)(len * (int32_t)(int8_t)buf_a[0]) & 0xFFu);
}

// SEW=8 / LMUL=1 / VL=8：v1 <- buf_a、v2 <- buf_b，v10 归零（链起点确定 ⇒ 结果可自检）；
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
      "vmv.v.i v10, 0\n\t"
      "csrr %0, vl\n\t"
      : "=r"(vl)
      : "S"(buf_a), "S"(buf_b)
      : "t0", "a0", "memory");
  return vl;
}

// vadd.vv v10, v10, v1 —— 标准顺序 `vd, vs2, vs1` ⇒ vd 同时是 vs2，
// 相邻两次之间是真 RAW 依赖；形状与 perf_vdot.c 的 vdot.vv v10, v10, v1 完全一致
// （同 vd / 同 vs1=v1 / 同 vs2=v10），与 perf_vmacc.c 的 vmacc.vv v10, v1, v10 也是 vd==vs2。
#define EMIT_VADD_CHAIN() asm volatile("vadd.vv v10, v10, v1\n\t" ::: "memory")

// 逐次 rdcycle 取差（计数法同 perf_base.c 的 B1/B2），出中位/均值/极值
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
    EMIT_VADD_CHAIN();
    c1 = rdcycle();
    d = c1 - c0;
    if (i < N_WARMUP) continue;
    sum += d;
    if (d < mn) mn = d;
    if (d > mx) mx = d;
    if (d >= HIST_MAX) { over++; d = HIST_MAX - 1; }
    hist[d]++;
  }
  // 中位 = 直方图前缀和跨过 n/2 的那个 bin（不排序、不占额外内存）
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

  // lane 0 自检：e8/vl=8 视图下 vmv.x.s 读低 8 位（vdot 那边读的是 32 位标量结果）
  // 读回视图只影响自检取数，不影响 rdcycle 依赖链计时；三链可比性由同 VL=8/SEW=8/同计数法保证
  uint64_t r;
  asm volatile("vmv.x.s %0, v10\n\t" : "=r"(r));
  return r;
}

// 旧口径：整段 len 条链的墙钟 / len（只附报，不参与 ΔL 三链主指标）
static uint64_t measure_loop_total(int len, uint64_t *out_cycles) {
  uint64_t c0, c1, r;
  load_operands();
  c0 = rdcycle();
  for (int i = 0; i < len; i++) {
    EMIT_VADD_CHAIN();
  }
  c1 = rdcycle();
  *out_cycles = c1 - c0;
  asm volatile("vmv.x.s %0, v10\n\t" : "=r"(r));
  return r;
}

static void print_chain_line(const char *tag, int len, uint64_t sum, uint64_t mean,
                             uint64_t median, uint64_t mn, uint64_t mx, uint64_t over,
                             uint64_t got, uint8_t want, int ok) {
  printf("PERF %s : ops=%d cycles=%llu mean=%llu median=%llu cycles_per_op=%llu "
         "min=%llu max=%llu over=%llu result=0x%02X want=0x%02X chain=%s\n",
         tag, len - N_WARMUP, (unsigned long long)sum,
         (unsigned long long)mean, (unsigned long long)median,
         (unsigned long long)median, (unsigned long long)mn,
         (unsigned long long)mx, (unsigned long long)over,
         (uint8_t)got, want, ok ? "OK" : "MISMATCH");
}

int main(void) {
  // AM 的 start.S 已完成 ioe/init_memory（apps/hello 同样不调用）

  uint64_t vl = load_operands();
  int vl_ok = (vl == VL);
  printf("PERF vadd: vl=%llu expect=%d %s\n", (unsigned long long)vl, VL,
         vl_ok ? "OK" : "MISMATCH");

  uint8_t want_raw = want_chain_lane0(N_RAW);
  uint8_t want_alt = want_chain_lane0(N_ALT);

  uint64_t sum, mean, median, mn, mx, over;
  uint64_t r = measure_raw_chain(N_RAW, &sum, &mean, &median, &mn, &mx, &over);
  int chk = ((uint8_t)r == want_raw);
  print_chain_line("L_vadd", N_RAW, sum, mean, median, mn, mx, over, r, want_raw, chk);
  printf("VDOT_METRIC L_vadd %llu\n", (unsigned long long)median);
  printf("VDOT_METRIC L_vadd_mean %llu\n", (unsigned long long)mean);

  uint64_t s2, m2, md2, mn2, mx2, ov2;
  uint64_t r_alt = measure_raw_chain(N_ALT, &s2, &m2, &md2, &mn2, &mx2, &ov2);
  int chk_alt = ((uint8_t)r_alt == want_alt);
  print_chain_line("L_vadd_alt", N_ALT, s2, m2, md2, mn2, mx2, ov2, r_alt, want_alt, chk_alt);
  int alt_differs = (want_raw != want_alt);

  uint64_t cyc;
  uint64_t r2 = measure_loop_total(N_RAW, &cyc);
  int chk2 = ((uint8_t)r2 == want_raw);
  printf("PERF L_vadd_loop : ops=%d cycles=%llu mean=%llu cycles_per_op=%llu "
         "result=0x%02X want=0x%02X chain=%s\n",
         N_RAW, (unsigned long long)cyc,
         (unsigned long long)(cyc / N_RAW), (unsigned long long)(cyc / N_RAW),
         (uint8_t)r2, want_raw, chk2 ? "OK" : "MISMATCH");
  printf("VDOT_METRIC L_vadd_loop %llu\n", (unsigned long long)(cyc / N_RAW));

  int ok = vl_ok && chk && chk_alt && alt_differs && chk2;
  printf("PERF_VADD verdict=%s vl=%s chain=%s chain_alt=%s alt_differs=%s chain_loop=%s\n",
         ok ? "ALL_OK" : "HAS_FAIL", vl_ok ? "OK" : "MISMATCH",
         chk ? "OK" : "MISMATCH", chk_alt ? "OK" : "MISMATCH",
         alt_differs ? "yes" : "no", chk2 ? "OK" : "MISMATCH");
  return ok ? 0 : 1;
}
