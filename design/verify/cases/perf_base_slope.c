// perf_base_slope.c — 基线链的**多规模斜率口径**（N=8/64/512 × {vdot,B2} × {resident,stream}）
//
// 为什么单开一个用例（而不是改 perf_base_chain.c）：
//   · `perf_base_chain.c` 及其镜像已冻结为独立测量项（`L_base_chain=16`，作业 `126750763`/`126762127`），
//     本用例**不读也不改**它，二者的数字互不替代、不相除。
//   · 本用例回答的是另一个问题：**每点成本随点数 N 的斜率**（cyc/dot）+ 拟合优度 R²，
//     对标外部公开材料的「多 workload × 3 基线 × 3 个 N 的线性拟合 + R²」方法学
//     （方法学口径取自其公开材料）。
//
// 口径（三条互不可替代，引用时必须分列）：
//   ① **斜率口径（本用例主产出）**：同一变体测 N=8/64/512 三点的窗口周期中位数，
//      取 `cyc = a + b·N` 的最小二乘 `b`（cyc/dot）+ R²。**b 是批吞吐**，不是依赖延迟。
//      截距 `a` 吸收窗口边缘固定项（`rdcycle` 的流水线偏斜，见下），不作结论引用。
//   ② **中位数口径（既有 `T_steady`/`L_*`）**：逐次 `rdcycle` 取差、去 16 次暖机、取中位数
//      （`design/verify/perf/perf_vdot.c`）。本用例每个 N 点的 `median=` 也是「窗口周期的中位数」，
//      但**窗口内含 UNROLL 条（vdot）或整条 B2 序列**，与 `T_steady` 的逐条括窗**不是同一估计量**：
//      两数只作同量级交叉核对，不互替、不相除。
//   ③ **每指令 1.33×**：`L_base_chain_per_instr / L_vdot`（整数口径 1.25×），由 `perf_base_chain.c`
//      与 ΔL 三链产出；**本用例不产出、不引用为比值**。
//
// 为什么用斜率而不是单点（与 `perf_kernel_cmp.c:27-40` 的实测结论同源）：
//   香山的 `mcycle`/`minstret`/`cycle` 不在有序读 CSR 白名单
//   （`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55`），
//   `rdcycle` 括窗可与内核体重排 ⇒ 单点绝对周期带一个**与 N 无关的固定偏斜**。
//   斜率拟合把该固定项收进截距 `a`，`b` 不受其影响；N=8 的窗口只有 8–24 条指令、与 ROB 深度同量级，
//   是**最受偏斜影响**的一点 ⇒ 另打印 `SLOPE fit2`（只用 N=64/512 的两点斜率）作稳健性披露。
//   两点与三点斜率同量级才说明「三点里没有坏点」；不一致必须如实写出，不得只报一个数。
//
// 组数与点数（≥ 任务要求的 2×2×3）：
//   2 通道 `ch`：`vdot`（本指令）/ `b2`（基线 B2，序列与 `design/verify/perf/perf_base.c:84-103` 逐指令一致）
//   2 类   `cls`：`resident`（操作数常驻 v1/v2，窗口内只跑计算）/ `stream`（**每点重新 load**）
//   3 个 N：8 / 64 / 512（同 VL=8、同 `buf_a`/`buf_b`、同 8 路独立 vd 展开）
//   ⇒ 12 个点（4 组 × 3 个 N）；每点 ROUNDS 个窗口，窗口周期以 CSV 落在 `SLOPE point` 行，
//     可由 `results/difftest/slope/calc_slope.py` 独立复算（斜率/R² 必须逐值一致）。
//   · 一点一行而不是一窗口一行：emu 里 UART 输出按字符计费（实测 56 行日志让 ROUNDS=2
//     的冒烟作业吃掉 10 分钟），逐窗口打印会把机时预算吃光；CSV 里保留全部窗口原值，信息不丢。
//
// 两条通道各自的「点」定义（**不同**，不得混称）：
//   · `vdot` 点 = 1 条 `vdot.vv`（8 路独立 vd=v8..v15 展开，窗口内零 `vsetvli`、零读回）
//     ⇒ 与 `perf_vdot.c` 的 `T_steady`（1 cyc/dot）**同形态**，可作同量级交叉核对。
//   · `b2` 点 = `perf_base.c` 的 `b2_once` 全序列（3 条配置 + `vmv.v.x v8` 死指令
//     + `vmv.v.i` + `vwmul/vwadd/vredsum` + 读回配置 + `vmv.x.s`）
//     ⇒ 与 B2=9（每点开销）**同形态**，可作同量级交叉核对。
//     `perf_kernel_cmp.c:11-13` 把 `vmv.v.x v8, zero` 当死指令**删掉**了；本用例与 `perf_base.c` 一致保留，
//     因为 B2=9 这个数就由 `perf_base.c` 定义 —— 两者差 1 条指令，是**已知差异**，不是疏忽。
//
// stream 类的边界（如实声明，别当成内存带宽结论）：
//   · `stream` 的两个地址是**同一对 16B 缓冲**（`buf_a`/`buf_b`，L1 常驻），每点重复 load
//     ⇒ 量的是**装载通路吞吐 + 计算**，**不是** DRAM/LLC 带宽；报告不得写成「内存受限 1.0×」。
//
// 运行要求：emu 必须带 `--no-diff`（用例读 `rdcycle`，与 NEMU 参照不一致；同 `perf_vdot.c:7`）。
//
// 入库状态：**不在** `design/verify/cases/manifest.tsv`（该文件冻结 30 行，按清单外
// 独立测量处理）。走 `core-package/scripts/98-run-slope.sh` 的单例作业路径；
// 镜像由 `design/verify/cases/build_slope.sh` 产出（不进 `build_all.sh` 的 manifest 核对）。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// AM 的 start.S 只开 mstatus.FS；向量指令还需 VS != OFF（SPEC §1.1 第六条）
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// ---------------------------------------------------------------- 编码与数据
// vdot.vv 自定义编码：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111（SPEC §2.1）
// `VDOT_ENC(vd, vs1, vs2)` 与 perf_vdot.c:21-23 逐位同式；发射到汇编时由 `"i"(…)` 求值成十进制字面量。
#define VDOT_ENC(vd, vs1, vs2) \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) | \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

#define E8  VDOT_ENC(8, 1, 2)
#define E9  VDOT_ENC(9, 1, 2)
#define E10 VDOT_ENC(10, 1, 2)
#define E11 VDOT_ENC(11, 1, 2)
#define E12 VDOT_ENC(12, 1, 2)
#define E13 VDOT_ENC(13, 1, 2)
#define E14 VDOT_ENC(14, 1, 2)
#define E15 VDOT_ENC(15, 1, 2)
// stream 用 vs1=v3、vs2=v4（每点重新 load 的寄存器）
#define S8  VDOT_ENC(8, 3, 4)
#define S9  VDOT_ENC(9, 3, 4)
#define S10 VDOT_ENC(10, 3, 4)
#define S11 VDOT_ENC(11, 3, 4)
#define S12 VDOT_ENC(12, 3, 4)
#define S13 VDOT_ENC(13, 3, 4)
#define S14 VDOT_ENC(14, 3, 4)
#define S15 VDOT_ENC(15, 3, 4)

// 操作数与 perf_vdot.c / perf_base.c / perf_base_chain.c 逐字节相同（同一天平）。
// buf_b 低 8 字节 {1,0,0,0,1,1,1,3}：点积 vl=8 → 8，只归约前 4 lane → 18（可分辨 vl）。
static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

static int32_t want_dot(void) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

// 只归约前 4 lane 的错值：错误 vtype（e32,m1 被钳到 vl=4）会读出它（同 perf_base.c:32-39）
static int32_t want_dot_vl4(void) {
  int32_t s = 0;
  for (int i = 0; i < 4; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

#define VL        8
#define UNROLL    8        // 一个展开块的 vdot 条数（8 路独立 vd = v8..v15，同 T_steady 形态）
#define N_POINTS  3
#ifndef ROUNDS
#define ROUNDS    3        // 每点窗口数（奇数 ⇒ 真中位数）；emu 约 50–80 模拟周期/秒墙钟，
                              // 每多一轮就多 ~18k 模拟周期 ⇒ ROUNDS 直接决定机时（见票内预算注记）
#endif
#define MAX_ROUNDS 64

static const int n_list[N_POINTS] = { 8, 64, 512 };

// ---------------------------------------------------------------- 窗口体
// 结构：**固定 8 点展开 + C 层循环**，不按 N 全展开（N=512 的 B2 若 `.rept 512` 会生成 ~26 KB
// 直落代码，把 L1I 打爆、让测量变成 I-cache 敏感 —— 那不是「每点开销」而是「代码体积」）。
// 因此：每个 BODY 硬编码 8 个点（写成显式 8 行，vdot 通道是 8 路独立 vd=v8..v15），
// C 循环跑 reps = N/8 次；八个通道的循环开销（2 条指令/8 点）**完全同形**，摊进斜率的是
// 相同的量 ⇒ vdot/B2 的 `b` 之差就是每点开销差，不被循环结构污染。
// vdot 编码用 `"i"(…)` 操作数求值（`.` 号在编译器展开后是十进制字面量，GNU as 接受）。
#define VDOT_RES_8()                                                          \
  asm volatile(                                                              \
      ".4byte %0\n\t" ".4byte %1\n\t" ".4byte %2\n\t" ".4byte %3\n\t"     \
      ".4byte %4\n\t" ".4byte %5\n\t" ".4byte %6\n\t" ".4byte %7\n\t"     \
      :                                                                       \
      : "i"(E8), "i"(E9), "i"(E10), "i"(E11), "i"(E12), "i"(E13), "i"(E14), "i"(E15) \
      : "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15", "memory")

// stream：8 点各自先 load 两路 8B 到 v3/v4，再发一条 vdot（v3/v4 每点重载 ⇒ load 通路被测量）
#define VDOT_STR_8(PA, PB)                                                    \
  asm volatile(                                                              \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %2\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %3\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %4\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %5\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %6\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %7\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %8\n\t"                                                        \
      "vle8.v v3, (%0)\n\t"                                                 \
      "vle8.v v4, (%1)\n\t"                                                 \
      ".4byte %9\n\t"                                                        \
      :                                                                       \
      : "r"(PA), "r"(PB), "i"(S8), "i"(S9), "i"(S10), "i"(S11),                \
        "i"(S12), "i"(S13), "i"(S14), "i"(S15)                                \
      : "v3", "v4", "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15", "memory")

// B2 resident：8 点 × （与 perf_base.c b2_once 逐指令一致的序列）；重复体用 `.rept 8` 展开，
//   每个重复引用相同的操作数寄存器（B2 序列本就固定寄存器，串行点在 v10 归约初值，逐点清零）。
#define B2_RES_8                                                                 \
  asm volatile(                                                                 \
      ".rept 8\n\t"                                                             \
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"                                   \
      "vwmul.vv v4, v1, v2\n\t"                                                \
      "li t1, 8\n\t"                                                           \
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"                                  \
      "vmv.v.x v8, zero\n\t"                                                   \
      "vwadd.vx v6, v4, zero\n\t"                                              \
      "li t2, 8\n\t"                                                           \
      "vsetvli zero, t2, e32, m2, ta, ma\n\t"                                  \
      "vmv.v.i v10, 0\n\t"                                                     \
      "vredsum.vs v10, v6, v10\n\t"                                            \
      "li t3, 4\n\t"                                                           \
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"                                  \
      "vmv.x.s a3, v10\n\t"                                                    \
      ".endr\n\t"                                                              \
      :                                                                          \
      :                                                                          \
      : "a3", "t1", "t2", "t3", "v4", "v5", "v6", "v7", "v8", "v10", "v11", "memory")

// B2 stream：8 点 × （首条 `vsetivli e8,m1,vl=8` 之后插 2 条 load（此时 VL=8，load 才取满 8 字节）+
//   B2 序列）；每点都重载 ⇒ load 通路被测量，与 vdot stream 的 `2 × vle8.v` 同形
#define B2_STR_8(PA, PB)                                                          \
  asm volatile(                                                                  \
      ".rept 8\n\t"                                                             \
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"                                   \
      "vle8.v v1, (%0)\n\t"                                                    \
      "vle8.v v2, (%1)\n\t"                                                    \
      "vwmul.vv v4, v1, v2\n\t"                                                \
      "li t1, 8\n\t"                                                           \
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"                                  \
      "vmv.v.x v8, zero\n\t"                                                   \
      "vwadd.vx v6, v4, zero\n\t"                                              \
      "li t2, 8\n\t"                                                           \
      "vsetvli zero, t2, e32, m2, ta, ma\n\t"                                  \
      "vmv.v.i v10, 0\n\t"                                                     \
      "vredsum.vs v10, v6, v10\n\t"                                            \
      "li t3, 4\n\t"                                                           \
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"                                  \
      "vmv.x.s a3, v10\n\t"                                                    \
      ".endr\n\t"                                                              \
      :                                                                          \
      : "r"(PA), "r"(PB)                                                         \
      : "a3", "t1", "t2", "t3", "v1", "v2", "v4", "v5", "v6", "v7", "v8", "v10", "v11", "memory")

// 窗口 = 一个 rdcycle 对括住 `reps` 次 8 点 body；C 层循环（计数器 + 分支）对四个通道同形。
static void window_vdot(int stream, int n, uint64_t *c0, uint64_t *c1) {
  uint8_t *pa = buf_a, *pb = buf_b;
  int reps = n / UNROLL;                    // N=8/64/512 ⇒ 1/8/64
  *c0 = rdcycle();
  for (int r = 0; r < reps; r++) {
    if (stream) VDOT_STR_8(pa, pb);
    else        VDOT_RES_8();
  }
  *c1 = rdcycle();
}

static void window_b2(int stream, int n, uint64_t *c0, uint64_t *c1) {
  uint8_t *pa = buf_a, *pb = buf_b;
  int reps = n / UNROLL;                    // N=8/64/512 ⇒ 1/8/64
  uint64_t d0, d1;
  d0 = rdcycle();
  for (int r = 0; r < reps; r++) {
    if (stream) B2_STR_8(pa, pb);
    else        B2_RES_8;
  }
  d1 = rdcycle();
  *c0 = d0; *c1 = d1;
}

// ---------------------------------------------------------------- 统计学（整数，可复算）
static uint64_t median_u64(const uint64_t *v, int n) {
  uint64_t t[MAX_ROUNDS];
  if (n > MAX_ROUNDS) n = MAX_ROUNDS;
  for (int i = 0; i < n; i++) t[i] = v[i];
  for (int i = 1; i < n; i++) {           // 插入排序（n ≤ 64，样本极小）
    uint64_t x = t[i];
    int j = i - 1;
    while (j >= 0 && t[j] > x) { t[j + 1] = t[j]; j--; }
    t[j + 1] = x;
  }
  return (n & 1) ? t[n / 2] : (t[n / 2 - 1] + t[n / 2]) / 2;
}

// 最小二乘 `y = a + b·x`（x = N，y = 窗口周期中位数）：
//   b = (n·Sxy − Sx·Sy) / (n·Sxx − Sx²)
//   a = (Sy·den − num·Sx) / (n·den)
//   SSres = Σy² − a·Σy − b·Σxy = (den·(n·Syy − Sy²) − num²) / (n·den)
//   R² = 1 − SSres/SStot = 1 − (den·(n·Syy − Sy²) − num²) / (den·(n·Syy − Sy²))
//   （独立恒等式 R² = (n·Sxy−Sx·Sy)²/((n·Sxx−Sx²)(n·Syy−Sy²)) 可用于交叉校验，两式同值）
// 打印 slope_milli = round(1000·b)、intercept_milli、r2_micro = round(1e6·R²)；
// 原始五个矩也打印，Python 侧可用任意精度整数复算同一组数。
typedef struct {
  int64_t num, den;        // b = num/den
  int64_t slope_milli;
  int64_t intercept_milli;
  int64_t r2_micro;
  int64_t sx, sxx, sy, syy, sxy;
  int degenerate;
} fit_t;

// `round(num/den · scale)`：先把 |num|·scale 与 den/2 相加再整除（全整数；本用例量级远小于 2^63）
static int64_t round_ratio(int64_t num, int64_t den, int64_t scale) {
  if (den == 0) return 0;
  int neg = ((num < 0) != (den < 0));
  int64_t an = num < 0 ? -num : num;
  int64_t ad = den < 0 ? -den : den;
  int64_t q = (an * scale + ad / 2) / ad;
  return neg ? -q : q;
}

static void fit_points(const int64_t *x, const int64_t *y, int n, fit_t *f) {
  int64_t sx = 0, sxx = 0, sy = 0, syy = 0, sxy = 0;
  for (int i = 0; i < n; i++) {
    sx += x[i]; sxx += x[i] * x[i];
    sy += y[i]; syy += y[i] * y[i];
    sxy += x[i] * y[i];
  }
  int64_t num = (int64_t)n * sxy - sx * sy;
  int64_t den = (int64_t)n * sxx - sx * sx;
  f->sx = sx; f->sxx = sxx; f->sy = sy; f->syy = syy; f->sxy = sxy;
  f->num = num; f->den = den;
  f->degenerate = (den == 0);
  if (den == 0) { f->slope_milli = 0; f->intercept_milli = 0; f->r2_micro = 0; return; }
  f->slope_milli = round_ratio(num, den, 1000);                  // round(1000·b)
  f->intercept_milli = round_ratio(sy * den - num * sx, (int64_t)n * den, 1000);  // round(1000·a)
  int64_t sstot_num = (int64_t)n * syy - sy * sy;                // n·Syy = n·Σ(y−ȳ)²
  if (sstot_num == 0) { f->r2_micro = 1000000; return; }          // 全等 y ⇒ R²=1（本用例不会出现）
  // SSres = Σy² − a·Σy − b·Σxy = (den·sstot_num − num²)/(n·den)
  int64_t ssres_num = den * sstot_num - num * num;                // SSres = ssres_num/(n·den)
  // R² = 1 − SSres/SStot = 1 − ssres_num/(den·sstot_num)
  f->r2_micro = 1000000 - round_ratio(ssres_num, den * sstot_num, 1000000);
}

// ---------------------------------------------------------------- 单变体测量
typedef struct {
  const char *cls;    // resident / stream
  const char *ch;     // vdot / b2
  uint64_t cyc[MAX_ROUNDS];
  int rounds;
  uint64_t med[N_POINTS];
  int ok_self;
  int ok_not_vl4;
  uint32_t result;
  fit_t fit;          // 三点拟合
  fit_t fit2;         // 只用 N=64/512 的两点拟合（稳健性披露）
  int monotonic;
} variant_t;

static void setup_ops(void) {
  // 计时窗外：配置 e8,m1,vl=8 并装载 v1/v2（resident 通道用；stream 通道也用这条配置）
  asm volatile(
      "li t0, 8\n\t"
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"
      "la a0, %0\n\t"
      "vle8.v v1, (a0)\n\t"
      "la a0, %1\n\t"
      "vle8.v v2, (a0)\n\t"
      ::"S"(buf_a), "S"(buf_b)
      : "t0", "a0", "memory");
}

static uint64_t vl_now(void) {
  uint64_t vl;
  asm volatile("csrr %0, vl" : "=r"(vl));
  return vl;
}

static void run_variant(variant_t *v, int is_b2, int stream, int32_t want, int32_t want4) {
  int64_t xs[N_POINTS], ys[N_POINTS];
  v->rounds = ROUNDS;
  if (v->rounds > MAX_ROUNDS) v->rounds = MAX_ROUNDS;

  setup_ops();
  {                                       // 暖机：一个不计数的小窗口，把冷启动效应挪出统计
    uint64_t w0, w1;
    if (is_b2) window_b2(stream, 8, &w0, &w1);
    else       window_vdot(stream, 8, &w0, &w1);
  }

  for (int p = 0; p < N_POINTS; p++) {
    int n = n_list[p];
    uint64_t mn = ~0ULL, mx = 0, sum = 0;
    (void)sum;
    for (int r = 0; r < v->rounds; r++) {
      uint64_t c0, c1;
      if (is_b2) window_b2(stream, n, &c0, &c1);
      else       window_vdot(stream, n, &c0, &c1);
      v->cyc[r] = c1 - c0;
      if (v->cyc[r] < mn) mn = v->cyc[r];
      if (v->cyc[r] > mx) mx = v->cyc[r];
      sum += v->cyc[r];
    }
    v->med[p] = median_u64(v->cyc, v->rounds);
    xs[p] = n;
    ys[p] = (int64_t)v->med[p];
    // 一点一行（原始窗口周期 CSV）：模拟器里 UART 输出按字符计费，逐行打印会把机时吃光。
    // calc_slope.py 从 `cyc=` 的 CSV 重算中位数与斜率，因此这一行就是完整原始数据。
    printf("SLOPE point ch=%s cls=%s n=%d rounds=%d median=%llu min=%llu max=%llu cyc=",
           v->ch, v->cls, n, v->rounds, (unsigned long long)v->med[p],
           (unsigned long long)mn, (unsigned long long)mx);
    for (int r = 0; r < v->rounds; r++)
      printf("%s%llu", r ? "," : "", (unsigned long long)v->cyc[r]);
    printf("\n");
  }

  fit_points(xs, ys, 3, &v->fit);
  fit_points(xs + 1, ys + 1, 2, &v->fit2);
  v->monotonic = (v->med[0] < v->med[1]) && (v->med[1] < v->med[2]);

  printf("SLOPE fit ch=%s cls=%s points=3 n0=%d n1=%d n2=%d m0=%llu m1=%llu m2=%llu "
         "slope_milli=%lld intercept_milli=%lld r2_micro=%lld "
         "sx=%lld sxx=%lld sy=%lld syy=%lld sxy=%lld slope_status=%s\n",
         v->ch, v->cls, n_list[0], n_list[1], n_list[2],
         (unsigned long long)v->med[0], (unsigned long long)v->med[1],
         (unsigned long long)v->med[2],
         (long long)v->fit.slope_milli, (long long)v->fit.intercept_milli,
         (long long)v->fit.r2_micro,
         (long long)v->fit.sx, (long long)v->fit.sxx, (long long)v->fit.sy,
         (long long)v->fit.syy, (long long)v->fit.sxy,
         v->fit.degenerate ? "degenerate" : "computed");
  printf("SLOPE fit2 ch=%s cls=%s points=2 n0=%d n1=%d slope_milli=%lld\n",
         v->ch, v->cls, n_list[1], n_list[2], (long long)v->fit2.slope_milli);
  printf("SLOPE monotonic ch=%s cls=%s m0=%llu m1=%llu m2=%llu increasing=%s\n",
         v->ch, v->cls, (unsigned long long)v->med[0], (unsigned long long)v->med[1],
         (unsigned long long)v->med[2], v->monotonic ? "yes" : "no");

  // 功能自检：窗口跑完后读回结果，与软件模型比对
  if (is_b2) {
    uint64_t r;
    asm volatile(
        "li t0, 4\n\t"
        "vsetvli zero, t0, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v10\n\t"
        : "=r"(r) :: "t0", "memory");
    v->result = (uint32_t)r;
    v->ok_self = ((int32_t)v->result == want);
    v->ok_not_vl4 = ((int32_t)v->result != want4);
    printf("SLOPE check ch=%s cls=%s result=0x%08X want=0x%08X want_vl4=0x%08X "
           "match=%s not_vl4=%s\n",
           v->ch, v->cls, v->result, (uint32_t)want, (uint32_t)want4,
           v->ok_self ? "OK" : "MISMATCH", v->ok_not_vl4 ? "yes" : "no");
    return;
  }
  {
    uint64_t r8, r15;
    asm volatile(
        "li t0, 4\n\t"
        "vsetvli zero, t0, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v8\n\t"
        "vmv.x.s %1, v15\n\t"
        : "=r"(r8), "=r"(r15) :: "t0", "memory");
    v->result = (uint32_t)r8;
    // v8 与 v15 都在窗口内被写；两者都必须等于模型值 ⇒ 单点漏写/写错寄存器都会被抓
    v->ok_self = ((int32_t)r8 == want) && ((int32_t)r15 == want);
    v->ok_not_vl4 = ((int32_t)r8 != want4) && ((int32_t)r15 != want4);
    printf("SLOPE check ch=%s cls=%s result_v8=0x%08X result_v15=0x%08X want=0x%08X "
           "want_vl4=0x%08X match=%s not_vl4=%s\n",
           v->ch, v->cls, (uint32_t)r8, (uint32_t)r15, (uint32_t)want, (uint32_t)want4,
           v->ok_self ? "OK" : "MISMATCH", v->ok_not_vl4 ? "yes" : "no");
  }
}

int main(void) {
  ENABLE_VS();

  uint32_t enc = VDOT_ENC(3, 1, 2);
  int enc_ok = (enc == 0x3A20A1D7u);
  int32_t want = want_dot();
  int32_t want4 = want_dot_vl4();
  int discriminates = (want != want4);

  setup_ops();
  uint64_t vl = vl_now();
  int vl_ok = (vl == VL);

  printf("PERF slope: enc_check=0x%08X expect=0x3A20A1D7 %s\n", enc, enc_ok ? "OK" : "MISMATCH");
  printf("PERF slope: vl=%llu expect=%d %s\n", (unsigned long long)vl, VL, vl_ok ? "OK" : "MISMATCH");
  printf("PERF slope: want_vl8=0x%08X want_vl4=0x%08X discriminates=%s\n",
         (uint32_t)want, (uint32_t)want4, discriminates ? "yes" : "no");
  printf("SLOPE header vl=%d unroll=%d rounds=%d n_list=%d,%d,%d data=buf_a/buf_b "
         "groups=4 points=%d\n",
         VL, UNROLL, ROUNDS, n_list[0], n_list[1], n_list[2], 4 * N_POINTS);

  static variant_t vs[4];
  const char *cls_name[2] = { "resident", "stream" };
  const char *ch_name[2]  = { "vdot", "b2" };
  int idx = 0;
  for (int c = 0; c < 2; c++) {        // 0=vdot 1=b2
    for (int s = 0; s < 2; s++) {      // 0=resident 1=stream
      variant_t *v = &vs[idx++];
      v->ch = ch_name[c];
      v->cls = cls_name[s];
      v->rounds = 0;
      v->ok_self = 0;
      v->ok_not_vl4 = 0;
      v->result = 0;
      v->monotonic = 0;
      run_variant(v, c == 1, s == 1, want, want4);
    }
  }

  int all_self = 1, all_not_vl4 = 1, all_slope = 1, all_mono = 1, all_fit = 1;
  for (int i = 0; i < 4; i++) {
    if (!vs[i].ok_self) all_self = 0;
    if (!vs[i].ok_not_vl4) all_not_vl4 = 0;
    if (!vs[i].monotonic) all_mono = 0;
    if (vs[i].fit.degenerate) all_fit = 0;
    if (vs[i].fit.slope_milli <= 0) all_slope = 0;
  }
  int ok = enc_ok && vl_ok && discriminates && all_self && all_not_vl4 &&
           all_slope && all_mono && all_fit;
  printf("SLOPE summary enc=%s vl=%s discriminates=%s selfcheck=%s not_vl4=%s slope_positive=%s "
         "monotonic=%s fit_computed=%s\n",
         enc_ok ? "OK" : "MISMATCH", vl_ok ? "OK" : "MISMATCH",
         discriminates ? "yes" : "no", all_self ? "OK" : "MISMATCH",
         all_not_vl4 ? "yes" : "no", all_slope ? "yes" : "no",
         all_mono ? "yes" : "no", all_fit ? "yes" : "no");
  printf("SLOPE verdict=%s groups=4 points=%d rounds_per_point=%d\n",
         ok ? "ALL_OK" : "HAS_FAIL", 4 * N_POINTS, ROUNDS);
  return ok ? 0 : 1;
}
