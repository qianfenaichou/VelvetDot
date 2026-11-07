// perf_base_chain.c — 基线组合序列的 RAW 依赖链延迟（L_base_chain）+ B3 第三套基线（**不作分母**）
//
// 缺口来源（先读这段，避免把本用例的数字误当成官方口径）：
//   · stage3/3.3/report.md §4.3 表最后一行：「`L_vdot` vs 基线组合序列的**依赖链** | **未测**」，
//     同 §4.3「诚实边界」：官方要求的「Baseline（组合指令）与 vdot 的 latency 加速比」需要一个
//     **基线组合序列的依赖链延迟测量**（`vwmul.vv → vwadd.vx → vredsum.vs` 同 vd 链）。
//   · stage3/3.3/report.md §7 待回填表：「基线组合序列的**依赖链延迟**（官方 3.3 要求项「Baseline 与 vdot 的 latency 加速比」所需的测量输入；口径为内部自设）| 未运行 |
//     在 perf_base.c 增 RAW 链测量（`vwmul→vwadd.vx→vredsum.vs` 同 `vd` 链）」。
//   · stage3/3.3/report.md §4.1 表：「B3 | 无归约上限（只进敏感性分析，不作分母）| 未测（源码无实现）」。
//
// 本用例给出**两个基线链口径 + 一个第三分母**，口径互不相同，不得互相替代、不得跨口径相除：
//
//   ① L_base_chain（主指标，任务口径「循环内零 vsetvli」）
//      固定 vtype = e16,m1,VL=8（配置在计时窗外），循环内**零 vsetvli**；
//      三指令 `vwmul.vv v4,v12,v2` → `vwadd.vx v6,v4,zero` → `vredsum.vs v12,v6,v12`；
//      循环携带的 RAW 边落在**同一个 vd 寄存器 v12** 上（`vredsum.vs` 写 vd=v12，
//      下一轮 `vwmul.vv` 读 vs2=v12）——与 ΔL 三链「vd==vs2」同形。
//      **计数法与 ΔL 三链同源但迭代数/样本数不同**（勿写「完全一致」）：VL=8；逐次 rdcycle 取差；
//      去前 16 次暖机；直方图取**中位数**（`cycles_per_op` 是中位数的别名，不是均值）；
//      HIST_MAX=4096，越界计入 over 并打印。
//      差异：ΔL 三链（design/verify/cases/perf_vadd.c:42-44,84,138-140；perf_vmacc.c 同）
//      是 **N_RAW=2000 次迭代、丢前 16 次 ⇒ 计入 1984 样本**（打印的 `ops=` 就是它）；
//      本用例是 **N_ITER=2016 次迭代、丢前 16 次 ⇒ 计入 2000 样本**（任务口径要求「≥2000 样本」，
//      本用例满足，ΔL 三链的 1984 不满足）。故两者**不可互称「完全一致」**，只能称「同源计数法、样本数不同」。
//      ⚠ **归一声明（回填 §4.3/§7 前必读）**：L_base_chain 是**三条指令**（vwmul.vv → vwadd.vx →
//        vredsum.vs）的 RAW 链延迟，而 L_vdot/L_vadd/L_vmacc 是**单条指令**的延迟 ⇒ **两者不是同一口径**，
//        直接相除就是 stage3/3.3/report.md §4.2 明令禁止的跨口径比值。
//        唯一允许的归一方式：**L_base_chain_per_instr = L_base_chain / 3**（组合基线的每指令平均延迟，
//        链内 3 条指令串行依赖 ⇒ 链延迟≈三者之和）。本用例同时打印该归一值
//        （`VDOT_METRIC L_base_chain_per_instr`），回填时**必须**引用它并在同句声明归一方式。
//      「8 条独立链互不干扰」：**8 轮独立链实例**（seed=1..8，各自重新装载初值、顺序执行、寄存器不重叠占用），
//      每轮 2000 样本（合计 16000 样本 ≥ 2000），逐轮终值与软件模型逐一比对 ⇒ 任何跨轮污染都会被抓；
//      8 轮中位数必须一致、8 个终值必须互不相同 ⇒ 「互不干扰」是被**检验**的，不是被假设的。
//      ⚠ **这条判据是纯硬件行为，本地无法预验**：`medians_agree` 要求 8 轮中位数逐位相同；
//        若 guest/emu 侧存在跨轮抖动（如宿主机调度、cache 状态差异）使某轮中位数差 1，
//        **语义完全正确的镜像也会判 HAS_FAIL**。当前无 emu 可跑，故该风险未被任何本地检查覆盖；
//        首次硬件实跑若在此项失败，先看 8 轮 median 的分布再判断是镜像缺陷还是测量噪声，
//        不要直接改用例。同理 `finals_distinct`（8 个终值互不相同）也依赖硬件实际执行。
//      ⚠ 8 条链**无法并行驻留**：本指令组合每条链要占 4+2+1=7 个向量寄存器（v4/v5 扩宽目的、
//        v6/v7 扩宽目的、v12 累加器），8 条需 56 个 > 32 个向量寄存器 ⇒ 并行方案在 RVV 128-bit VLEN 下
//        物理不可行，故实现为 8 轮顺序独立实例（判据见上）。
//
//   ② L_base_chain_ladder（忠实基线形态，含配置）
//      真实基线实现是 B2 阶梯：`vwmul.vv`(e8) → `vwadd.vx`(e16 widen 到 32) → `vredsum.vs`(e32,m2)，
//      三段 SEW 不同 ⇒ **每轮必须改 3 次 vsetvli，配置不可外提**：
//      三类 vsetvli 分属不同 SEW，无法提到循环外。
//      本口径把 vsetvli 计进每轮耗时，是「真实基线写法」的延迟；①是同指令组合、配置外提后的下界。
//      ⚠ ①与②的 vtype 不同（①全程 e16，②是 e8/e16/e32 阶梯），数据通路宽度不同 ⇒ 两个数**不可相减**。
//
//   ③ B3（第三套基线，**只进敏感性分析，不作分母**）
//      定义来源：stage3/3.3/report.md §4.1 表（B3 = 无归约上限）+ design/ALGORITHM.md:192
//      的指令序列（7 条计算 + 3 次配置）。
//      「无归约」= 序列里**没有** vredsum/vwredsum 归约指令，改用 vadd.vv + vslidedown.vi 树形求和。
//      口径与 B1/B2 同族（每点开销 = 整段序列墙钟 / 点数），因此可与 B1/B2 并列进 §4.1 的表。
//      ⚠ 内部自设口径：官方 docx/02-赛题与评分细则.md 只要求「用已有向量指令组合实现」，未规定条数/
//        延迟口径 ⇒ 本用例的任何数字都**不得**写成「官方口径」。
//      （任务口径里「每点含归约的完整基线序列」这一第三口径 = ② L_base_chain_ladder：它是含 vredsum 的
//        完整基线序列的每点链延迟；③ 是 §4.1 已定义的「无归约上限」每点开销。两者一并给出。）
//
// 自检（防「空绿」，逐项都必须是硬件读回值 vs 独立软件模型的比对）：
//   · vl 自检：硬件生效的 vl 必须 == 8。
//   · 链终值自检：每轮链跑完后读回累加器，与**逐字节精确的软件模型**比对（模型见下方 model_* 函数，
//     口径与 RVV 1.0 的寄存器组字节视图一致：元素 i 占字节 [i*EEW,(i+1)*EEW)，小端）。
//   · 长度可分辨性自检：同一 seed 跑 N 次与 N-1 次，终值必须不同 ⇒ 任何「固定截断到 k 次」的实现必被抓。
//   · 数据可分辨性自检：链用乘数 B=2（配置自由版）/ {3,1,0,...}（阶梯版），
//     都是「乘积回灌累加器」。**递推不是 3^k 型**：vwadd.vx v6,v4,zero 把 {v4} 的 16 字节
//     当 8 个 int16 lane 重读（= int32 积的低/高半字交错），故 acc 一旦为负，
//     sum ≠ 2·acc，递推不再等于 3^k（实测：acc(i)==3^i 只在 i≤9 成立，i=10 起分叉）。
//     ⇒ 「acc(N) ≠ acc(N-1)」**不作为闭式结论**，改由**经验判据**保证：同一 seed 跑 N 与
//     N-1 次的终值必须不同（下面 alt_differs 那条自检），实测不同即可，不依赖任何闭式证明。
//   · B3 结果自检：必须等于 8 个 int8 的点积（= 8），且与「只归约前 4 lane」的错值 18 不同 ⇒ 可分辨 vl。
//
// 运行要求：emu 必须带 --no-diff（本用例读 rdcycle/mcycle，与 NEMU 参照不一致；同 perf_vadd/perf_vmacc）。
//
// 入库状态（打包与流水线必读项）：
//   · 本用例**不在** design/verify/cases/manifest.tsv（2026-11-04 口径：保持独立测量，
//     不并入 30 例官方回归清单）。曾短暂加入后被移除 ⇒
//     build_all.sh 的「镜像齐备 / 镜像新于源码」两项检查**不覆盖本用例**，改源码后必须手工
//     重建并核对 md5（实测仓库件 md5 8c5538c9… == 远端运行件 md5，见
//     results/difftest/b3/provenance/91-b3-provenance.txt）。
//     core-package/scripts/20-run-difftest.sh 的 selfcheck_pattern() 仍保留
//         perf_base_chain) echo 'PERF_BASE_CHAIN verdict=ALL_OK' ;;
//     分支，仅供「临时清单直跑 20-run」时兜底；正常测量路径是 core-package/scripts/91-run-b3.sh。
//   · **已在硬件上跑通两轮**（昆山 emu）：
//       - min 尺度（-DCHAIN_MIN -DN_SAMPLES=500 -DROUNDS=4）：作业 126750763，
//         `PERF_BASE_CHAIN verdict=ALL_OK … samples=2000 rounds=4 scale=min(ladder/B3_skipped)`，
//         `L_base_chain=16`（results/difftest/b3/91-b3-20261104T092457.log）。
//       - full 尺度（默认 8×2000 + 阶梯链 + B3）：作业 126762127（独占 <node>，32 核，1:30:18），
//         `verdict=ALL_OK … ladder=OK b3=OK b3_not_vl4=yes discriminates=yes samples=16000 rounds=8 scale=full`，
//         `L_base_chain=16` / `L_base_chain_ladder=24` / `B3=11`
//         （results/difftest/b3/91-b3-20261104T115624.log）。
//     失败记录（只作排障）：126749121（600 s 超时、rc=124，只完成 round 0）、
//     126758062（共享节点 1:02:30 只走完 round 0/1 后取消）。
//   · 指令量：8 轮 × 2016 迭代 + 2 轮阶梯链 + 1 轮 B3 ≈ 2.0e5 条指令。
//     实测耗时：full 尺度整套 **1:30:18**（独占 32 核节点）；min 尺度 8:47（527 s）。
//     ⚠ 早期头注写的「昆山 emu 下约 5~6 分钟」是**未实测的估计值**，已被实测取代。
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

// ---------------------------------------------------------------- 操作数
#ifndef CHAIN_MIN  // 最小口径只测链延迟，不需要 B3 操作数（否则触发 -Werror=unused）
// 与 perf_vdot.c / perf_vadd.c / perf_vmacc.c / perf_base.c 逐字节相同（同一天平）。
static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

// 8 个 int8 的点积（B3 的期望值）
static int32_t want_dot(void) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}
// 只归约前 4 lane 的错值（用于证明数据可分辨 vl）
static int32_t want_dot_vl4(void) {
  int32_t s = 0;
  for (int i = 0; i < 4; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}
#endif // CHAIN_MIN

// ---------------------------------------------------------------- 计数口径（与 ΔL 三链同源）
#define VL        8      // SEW/LMUL 视图下的 VL=8（ΔL 三链统一口径）
// N_SAMPLES / ROUNDS 允许编译期覆盖（-DCHAIN_MIN 最小作业口径，见文件尾注）：
//   默认仍是 2000×8（官方口径）；最小口径用 -DCHAIN_MIN -DN_SAMPLES=500 -DROUNDS=4
//   ⇒ 合并样本 4×500=2000（满足「≥2000 样本」），迭代总数 ≈2064（默认口径 16128，
//   实测昆山单轮 2016 次 ≈ 数分钟，默认口径一次要 >1 机时，会吃掉整个 P3 预算）。
#ifndef N_SAMPLES
#define N_SAMPLES 2000   // 每轮**计入**的样本数（≥2000，与任务口径一致）
#endif
#define N_WARMUP  16     // 冷启动/流水线填充样本，不计入统计（同 perf_vadd/perf_vmacc）
#define N_ITER    (N_SAMPLES + N_WARMUP)  // 每轮实际迭代次数 = 2016（默认口径）
#define N_ALT     (N_SAMPLES - 1)        // 长度可分辨性对照：1999 次（默认口径）
#ifndef ROUNDS
#define ROUNDS    8       // 「8 条独立链」的轮数
#endif
#define HIST_MAX  4096   // 中位直方图上界；越界计入 over 并显式打印

static uint16_t hist[HIST_MAX];      // 单轮直方图
static uint16_t hist_all[HIST_MAX];  // 8 轮合并直方图

// 链的乘数与初值（每轮重新装载 ⇒ 每轮都是独立链实例）
//
// ⚠ **乘数必须真初始化**：`cf_mul` 若无初值就落在 **.bss**（运行时全 0）⇒ 硬件链退化成
//   acc' = acc（恒等）⇒ 终值恒等于 seed，与模型期望完全不符 ⇒ 8 轮全部 chain=MISMATCH、
//   且 alt(N-1) 也等于 finals[0] ⇒ alt_differs=no ⇒ verdict 永远 HAS_FAIL。
//   故此处给**静态初值**（与 ld_mul 同法，落在 .data，运行时确实装载；已用
//   `riscv64-unknown-elf-nm -S` 核对段位 + .bin 字节核对）。
//   `cf_seed` / `ld_seed` 无需初值：它们在 cf_measure()/ld_measure() 里每轮显式写满 8 lane
//   （.bss 由 C 运行时清零 + 显式赋值），不依赖装载。
#define CF_MUL 2  // 配置自由链的乘数（int16 lane0）
static int16_t cf_mul[8] __attribute__((aligned(16))) = {
  CF_MUL, 0, 0, 0, 0, 0, 0, 0
};
static int16_t cf_seed[8] __attribute__((aligned(16)));  // {seed, 0,0,0,0,0,0,0}，每轮显式写

// 阶梯链的乘数（int8 视图）与初值（int32 视图，e32,m2 的 8 个 int32 = {v10,v11}）
static uint8_t ld_mul[16] __attribute__((aligned(16))) = {
  3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};
static int32_t ld_seed[8] __attribute__((aligned(16)));

// ---------------------------------------------------------------- 软件模型（逐字节精确，RVV 1.0 寄存器组字节视图）
//
// ① 配置自由链（e16,m1,vl=8）：
//    v12 的 8 个 int16 lane：lane0 = acc，lane1..7 = 0
//    v2  的 8 个 int16 lane：lane0 = CF_MUL，lane1..7 = 0
//    vwmul.vv v4,v12,v2 → 目的 EEW=32、EMUL=2（{v4,v5}）：8 个 int32 p_i = a_i*b_i
//    vwadd.vx v6,v4,zero → 读 {v4} 的 8 个 int16 lane（= p0..p3 的低/高半字交错）→ q_j = sext16(lane_j)
//    vredsum.vs v12,v6,v12 → 读 {v6} 的 8 个 int16 lane → sum = Σ sext16(lane)
//    acc' = acc + sum（mod 2^16）
//    注意：v12 的 lane1..7 的内容对结果**无影响**（乘数 lane1..7 = 0 ⇒ 乘积恒 0），
//    故模型不依赖「归约只写 lane0、其余是 tail」的实现细节（tail 用 tu，语义无关）。
static int16_t model_cf_step(int16_t acc, int16_t mul) {
  int32_t p[8], q[8];
  for (int i = 0; i < 8; i++) {
    int16_t a = (i == 0) ? acc : (int16_t)0;
    int16_t b = (i == 0) ? mul : (int16_t)0;
    p[i] = (int32_t)a * (int32_t)b;
  }
  for (int j = 0; j < 8; j++) {  // {v4} 的低 16 字节 → 8 个 int16 lane
    int32_t src = p[j >> 1];
    uint32_t half = (j & 1) ? (uint32_t)((src >> 16) & 0xFFFF) : (uint32_t)(src & 0xFFFF);
    q[j] = (int32_t)(int16_t)(uint16_t)half;
  }
  int32_t sum = 0;
  for (int j = 0; j < 8; j++) {  // {v6} 的低 16 字节 → 8 个 int16 lane
    int32_t src = q[j >> 1];
    uint32_t half = (j & 1) ? (uint32_t)((src >> 16) & 0xFFFF) : (uint32_t)(src & 0xFFFF);
    sum += (int32_t)(int16_t)(uint16_t)half;
  }
  uint16_t s16 = (uint16_t)(int16_t)(uint16_t)(uint32_t)sum;
  return (int16_t)(uint16_t)((uint16_t)acc + s16);
}

static int16_t model_cf_run(int16_t seed, int n) {
  int16_t acc = seed;
  for (int i = 0; i < n; i++) acc = model_cf_step(acc, (int16_t)CF_MUL);
  return acc;
}

// ② 阶梯链（e8 → e16 → e32,m2）：
//    vwmul.vv v4,v10,v2 @e8,m1 → p_i = sext8(a_i)*sext8(b_i)（int16，8 个正好在 {v4} 的 16 字节）
//    vwadd.vx v6,v4,zero @e16,m1 → 读 {v4} 的 8 个 int16 = p0..p7 → q_i = sext16(p_i)（int32，8 个在 {v6,v7}）
//    vredsum.vs v10,v6,v10 @e32,m2 → 读 {v6,v7} 的 8 个 int32 = q0..q7 → acc' = acc + Σ q_i（mod 2^32）
//    其中 a_i = v10 的第 i 个 int8 lane = acc 的第 i 个字节（i<4），i>=4 取 0（v10 的 int32 lane1 为 0）。
static int32_t model_ladder_step(int32_t acc) {
  int32_t sum = 0;
  for (int i = 0; i < 8; i++) {
    int8_t a = (i < 4) ? (int8_t)(uint8_t)((uint32_t)acc >> (8 * i)) : (int8_t)0;
    int8_t b = (int8_t)ld_mul[i];
    int16_t p = (int16_t)(uint16_t)((uint32_t)((int32_t)a * (int32_t)b));
    sum = (int32_t)((uint32_t)sum + (uint32_t)(int32_t)p);
  }
  return (int32_t)((uint32_t)acc + (uint32_t)sum);
}

static int32_t model_ladder_run(int32_t seed, int n) {
  int32_t acc = seed;
  for (int i = 0; i < n; i++) acc = model_ladder_step(acc);
  return acc;
}

// ---------------------------------------------------------------- 汇编块
// ① 配置自由链：配置 + 装载（**计时窗外**）
#define CF_SETUP()                                                          \
  asm volatile(                                                              \
      "li t0, 8\n\t"                                                          \
      "vsetvli zero, t0, e16, m1, tu, mu\n\t"                                \
      "la a0, %0\n\t"                                                         \
      "vle16.v v2, (a0)\n\t"                                                 \
      "la a0, %1\n\t"                                                         \
      "vle16.v v12, (a0)\n\t"                                                \
      ::"S"(cf_mul), "S"(cf_seed)                                            \
      : "t0", "a0", "memory")

// ① 三指令同 vd RAW 链（循环内零 vsetvli；循环携带 RAW 边 = v12）
#define CF_CHAIN()                                                           \
  asm volatile(                                                              \
      "vwmul.vv v4, v12, v2\n\t"                                              \
      "vwadd.vx v6, v4, zero\n\t"                                             \
      "vredsum.vs v12, v6, v12\n\t"                                           \
      ::: "memory")

// ② 阶梯链：配置 + 装载（计时窗外；e32,m2 装载 acc，e8 装载乘数）
#define LD_SETUP()                                                           \
  asm volatile(                                                              \
      "li t0, 8\n\t"                                                          \
      "vsetvli zero, t0, e32, m2, tu, mu\n\t"                                \
      "la a0, %0\n\t"                                                         \
      "vle32.v v10, (a0)\n\t"                                                \
      "li t0, 8\n\t"                                                          \
      "vsetvli zero, t0, e8, m1, tu, mu\n\t"                                  \
      "la a0, %1\n\t"                                                         \
      "vle8.v v2, (a0)\n\t"                                                  \
      ::"S"(ld_seed), "S"(ld_mul)                                            \
      : "t0", "a0", "memory")

// ② 忠实 B2 阶梯链（每轮 3 次 vsetvli，**含配置**，与基线设计 §2.1 的「不可外提」一致）
#define LD_CHAIN()                                                           \
  asm volatile(                                                              \
      "vsetivli zero, 8, e8, m1, tu, mu\n\t"                                 \
      "vwmul.vv v4, v10, v2\n\t"                                              \
      "li t1, 8\n\t"                                                          \
      "vsetvli zero, t1, e16, m1, tu, mu\n\t"                                 \
      "vwadd.vx v6, v4, zero\n\t"                                             \
      "li t2, 8\n\t"                                                          \
      "vsetvli zero, t2, e32, m2, tu, mu\n\t"                                \
      "vredsum.vs v10, v6, v10\n\t"                                           \
      ::: "t1", "t2", "memory")

// ③ B3：vsetivli + vle8.v 装载 v1/v2（e8,m1,vl=8）
#define B3_LOAD()                                                            \
  asm volatile(                                                              \
      "li t0, 8\n\t"                                                          \
      "vsetvli zero, t0, e8, m1, ta, ma\n\t"                                 \
      "la a0, %0\n\t"                                                         \
      "vle8.v v1, (a0)\n\t"                                                  \
      "la a0, %1\n\t"                                                         \
      "vle8.v v2, (a0)\n\t"                                                  \
      ::"S"(buf_a), "S"(buf_b)                                               \
      : "t0", "a0", "memory")

// ③ B3 单点序列（基线设计 §1.4 的「无归约上限」序列；本块把首段 e8 配置也计入，
//   与 B1/B2 的每点开销口径一致；读回 vmv.x.s 同样计入，与 b1_once/b2_once 一致）
#define B3_ONCE(res)                                                         \
  asm volatile(                                                              \
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"                                 \
      "vwmul.vv v4, v1, v2\n\t"                                               \
      "li t1, 8\n\t"                                                          \
      "vsetvli zero, t1, e16, m1, tu, mu\n\t"                                \
      "vwadd.vx v8, v4, zero\n\t"                                             \
      "li t2, 4\n\t"                                                          \
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"                                \
      "vadd.vv v10, v8, v9\n\t"                                               \
      "vslidedown.vi v11, v10, 2\n\t"                                         \
      "vadd.vv v12, v10, v11\n\t"                                             \
      "vslidedown.vi v13, v12, 1\n\t"                                         \
      "li t3, 1\n\t"                                                          \
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"                                \
      "vadd.vv v14, v12, v13\n\t"                                             \
      "vmv.x.s %0, v14\n\t"                                                   \
      : "=r"(res)                                                            \
      :                                                                       \
      : "t1", "t2", "t3", "memory")

// ---------------------------------------------------------------- 测量
static uint64_t median_of(const uint16_t *h, uint32_t n) {
  uint32_t acc = 0;
  for (uint32_t v = 0; v < HIST_MAX; v++) {
    acc += h[v];
    if (acc > n / 2) return v;
  }
  return HIST_MAX - 1;
}

// ① 配置自由链：跑 n_iter 轮，返回读回的 acc（低 16 位）
static uint16_t cf_measure(int seed, int n_iter, uint64_t *out_sum, uint64_t *out_mean,
                           uint64_t *out_median, uint64_t *out_min, uint64_t *out_max,
                           uint64_t *out_over, int pooled) {
  uint64_t c0, c1, d, sum = 0, mn = ~0ULL, mx = 0, over = 0;
  const uint32_t n = (uint32_t)(n_iter - N_WARMUP);

  for (int i = 0; i < HIST_MAX; i++) hist[i] = 0;
  for (int i = 0; i < 8; i++) cf_seed[i] = 0;
  cf_seed[0] = (int16_t)seed;
  // 乘数同样**每次显式写满**（不依赖静态初值/装载器是否搬运 .data）：若乘数为 0，
  // 链退化为 acc'=acc ⇒ 终值=seed，用例必然 HAS_FAIL（复核 F1）。这行在计时窗外。
  for (int i = 0; i < 8; i++) cf_mul[i] = 0;
  cf_mul[0] = (int16_t)CF_MUL;
  CF_SETUP();

  for (int i = 0; i < n_iter; i++) {
    c0 = rdcycle();
    CF_CHAIN();
    c1 = rdcycle();
    d = c1 - c0;
    if (i < N_WARMUP) continue;
    sum += d;
    if (d < mn) mn = d;
    if (d > mx) mx = d;
    if (d >= HIST_MAX) { over++; d = HIST_MAX - 1; }
    hist[d]++;
    if (pooled) hist_all[d]++;
  }
  *out_sum = sum;
  *out_mean = sum / n;
  *out_median = median_of(hist, n);
  *out_min = mn;
  *out_max = mx;
  *out_over = over;

  uint64_t r;
  asm volatile("vmv.x.s %0, v12\n\t" : "=r"(r));  // e16 视图：读 lane0 的 16 位
  return (uint16_t)(r & 0xFFFFu);
}

// ② 阶梯链：跑 n_iter 轮，返回读回的 acc（32 位）
static uint32_t ld_measure(int seed, int n_iter, uint64_t *out_sum, uint64_t *out_mean,
                           uint64_t *out_median, uint64_t *out_min, uint64_t *out_max,
                           uint64_t *out_over) {
  uint64_t c0, c1, d, sum = 0, mn = ~0ULL, mx = 0, over = 0;
  const uint32_t n = (uint32_t)(n_iter - N_WARMUP);

  for (int i = 0; i < HIST_MAX; i++) hist[i] = 0;
  for (int i = 0; i < 8; i++) ld_seed[i] = 0;
  ld_seed[0] = (int32_t)seed;
  LD_SETUP();

  for (int i = 0; i < n_iter; i++) {
    c0 = rdcycle();
    LD_CHAIN();
    c1 = rdcycle();
    d = c1 - c0;
    if (i < N_WARMUP) continue;
    sum += d;
    if (d < mn) mn = d;
    if (d > mx) mx = d;
    if (d >= HIST_MAX) { over++; d = HIST_MAX - 1; }
    hist[d]++;
  }
  *out_sum = sum;
  *out_mean = sum / n;
  *out_median = median_of(hist, n);
  *out_min = mn;
  *out_max = mx;
  *out_over = over;

  uint64_t r;
  asm volatile("vmv.x.s %0, v10\n\t" : "=r"(r));  // e32 视图：读 lane0 的 32 位
  return (uint32_t)r;
}

int main(void) {
  // AM 的 start.S 已完成 ioe/init_memory（apps/hello 同样不调用）
  ENABLE_VS();

  // ---------- vl 自检 ----------
  uint64_t vl;
  asm volatile(
      "li t0, 8\n\t"
      "vsetvli zero, t0, e16, m1, tu, mu\n\t"
      "csrr %0, vl\n\t"
      : "=r"(vl)
      :
      : "t0", "memory");
  int vl_ok = (vl == VL);
  printf("PERF base_chain: vl=%llu expect=%d %s\n", (unsigned long long)vl, VL,
         vl_ok ? "OK" : "MISMATCH");

  // ---------- ① 配置自由链：8 轮独立链 ----------
  for (int i = 0; i < HIST_MAX; i++) hist_all[i] = 0;
  uint64_t all_sum = 0, all_mean = 0, all_median = 0, all_min = ~0ULL, all_max = 0, all_over = 0;
  uint16_t finals[ROUNDS];
  int rounds_ok = 1, medians_agree = 1, finals_distinct = 1;
  uint64_t first_median = 0;

  for (int k = 0; k < ROUNDS; k++) {
    uint64_t sum, mean, median, mn, mx, over;
    int seed = k + 1;
    uint16_t got = cf_measure(seed, N_ITER, &sum, &mean, &median, &mn, &mx, &over, 1);
    int16_t want = model_cf_run((int16_t)seed, N_ITER);
    int ok = (got == (uint16_t)want);
    finals[k] = got;
    if (!ok) rounds_ok = 0;
    if (k == 0) first_median = median;
    else if (median != first_median) medians_agree = 0;
    all_sum += sum;
    all_min = (mn < all_min) ? mn : all_min;
    all_max = (mx > all_max) ? mx : all_max;
    all_over += over;
    printf("PERF chain_free_round: round=%d seed=%d samples=%d median=%llu mean=%llu "
           "min=%llu max=%llu over=%llu result=0x%04X want=0x%04X chain=%s\n",
           k, seed, N_SAMPLES, (unsigned long long)median, (unsigned long long)mean,
           (unsigned long long)mn, (unsigned long long)mx, (unsigned long long)over,
           got, (uint16_t)want, ok ? "OK" : "MISMATCH");
  }
  for (int k = 0; k < ROUNDS; k++)
    for (int j = k + 1; j < ROUNDS; j++)
      if (finals[k] == finals[j]) finals_distinct = 0;

  uint32_t pooled_n = (uint32_t)(ROUNDS * N_SAMPLES);
  all_median = median_of(hist_all, pooled_n);
  all_mean = all_sum / pooled_n;
  printf("PERF L_base_chain: rounds=%d samples=%u median=%llu cycles_per_op=%llu mean=%llu "
         "min=%llu max=%llu over=%llu rounds_agree=%s finals_distinct=%s\n",
         ROUNDS, pooled_n, (unsigned long long)all_median, (unsigned long long)all_median,
         (unsigned long long)all_mean, (unsigned long long)all_min, (unsigned long long)all_max,
         (unsigned long long)all_over, medians_agree ? "yes" : "no",
         finals_distinct ? "yes" : "no");
  printf("VDOT_METRIC L_base_chain %llu\n", (unsigned long long)all_median);
  printf("VDOT_METRIC L_base_chain_mean %llu\n", (unsigned long long)all_mean);
  // 归一后的**每指令**延迟（唯一允许与 L_vdot/L_vadd/L_vmacc 同口径相除的量）：
  // 链内 3 条指令串行依赖 ⇒ 链延迟 ≈ 三者之和 ⇒ 每指令 = 链延迟 / 3。
  // ⚠ 这是**本用例自设**的归一方式；回填 stage3/3.3/report.md §4.3/§7 时必须引用本行
  //   并在同句声明「按 3 条指令归一」，**不得**直接用 L_base_chain 与单指令延迟相除
  //   （那是 §4.2 明令禁止的跨口径比值）。整数除法，精度 ±1 拍。
  printf("VDOT_METRIC L_base_chain_per_instr %llu\n", (unsigned long long)(all_median / 3));

  // 长度可分辨性：同 seed 跑 N-1 次，终值必须与 N 次不同（硬件实测，不是模型自证）
  uint64_t s2, m2, md2, mn2, mx2, ov2;
  uint16_t got_alt = cf_measure(1, N_ITER - 1, &s2, &m2, &md2, &mn2, &mx2, &ov2, 0);
  int16_t want_alt = model_cf_run(1, N_ITER - 1);
  int cf_alt_ok = (got_alt == (uint16_t)want_alt);
  int cf_alt_differs = (got_alt != finals[0]);
  printf("PERF L_base_chain_alt: samples=%d median=%llu result=0x%04X want=0x%04X "
         "chain=%s alt_differs=%s\n",
         N_SAMPLES - 1, (unsigned long long)md2, got_alt, (uint16_t)want_alt,
         cf_alt_ok ? "OK" : "MISMATCH", cf_alt_differs ? "yes" : "no");

#ifndef CHAIN_MIN
  // ---------- ② 忠实 B2 阶梯链（含配置） ----------
  uint64_t s3, m3, md3, mn3, mx3, ov3;
  uint32_t ld_got = ld_measure(1, N_ITER, &s3, &m3, &md3, &mn3, &mx3, &ov3);
  int32_t ld_want = model_ladder_run(1, N_ITER);
  int ld_ok = ((int32_t)ld_got == ld_want);
  printf("PERF L_base_chain_ladder: samples=%d cycles=%llu mean=%llu median=%llu "
         "cycles_per_op=%llu min=%llu max=%llu over=%llu result=0x%08X want=0x%08X chain=%s\n",
         N_SAMPLES, (unsigned long long)s3, (unsigned long long)m3, (unsigned long long)md3,
         (unsigned long long)md3, (unsigned long long)mn3, (unsigned long long)mx3,
         (unsigned long long)ov3, ld_got, (uint32_t)ld_want, ld_ok ? "OK" : "MISMATCH");
  printf("VDOT_METRIC L_base_chain_ladder %llu\n", (unsigned long long)md3);
  printf("VDOT_METRIC L_base_chain_ladder_mean %llu\n", (unsigned long long)m3);

  uint64_t s4, m4, md4, mn4, mx4, ov4;
  uint32_t ld_got_alt = ld_measure(1, N_ITER - 1, &s4, &m4, &md4, &mn4, &mx4, &ov4);
  int32_t ld_want_alt = model_ladder_run(1, N_ITER - 1);
  int ld_alt_ok = ((int32_t)ld_got_alt == ld_want_alt);
  int ld_alt_differs = (ld_got_alt != ld_got);
  printf("PERF L_base_chain_ladder_alt: samples=%d median=%llu result=0x%08X want=0x%08X "
         "chain=%s alt_differs=%s\n",
         N_SAMPLES - 1, (unsigned long long)md4, ld_got_alt, (uint32_t)ld_want_alt,
         ld_alt_ok ? "OK" : "MISMATCH", ld_alt_differs ? "yes" : "no");

  // ---------- ③ B3（无归约上限，第三套基线；只进敏感性分析，不作分母） ----------
  int32_t want = want_dot();
  int32_t want4 = want_dot_vl4();
  int data_discriminates = (want != want4);
  uint64_t res = 0, total = 0;
  // ⚠ 计数法与 B1/B2 不同（复核口径要求写明）：本循环对 N_ITER=2016 次**全部计时**，
  //   **不丢**前 N_WARMUP=16 次暖机（对比 cf_measure/ld_measure 都有 `if (i < N_WARMUP) continue;`），
  //   samples 记为 2016；而 perf_base.c 的 B1/B2 是 N=2000、**无暖机丢弃**。
  //   ⇒ B3 与 B1/B2 同属「每点开销」类，但暖机处理不同，**不得**做「同法同口径」的差值或比值；
  //   报告只把 B3 并列进敏感性分析（stage3/3.3/report.md §4.3 诚实边界 ⑥）。
  B3_LOAD();
  for (int i = 0; i < N_ITER; i++) {
    uint64_t cyc = rdcycle();
    B3_ONCE(res);
    total += rdcycle() - cyc;
  }
  int b3_ok = ((int32_t)(uint32_t)res == want);
  int b3_not_vl4 = ((int32_t)(uint32_t)res != want4);
  printf("PERF B3: ops=%d cycles=%llu cycles_per_op=%llu result=0x%08X want=0x%08X "
         "not_vl4=%s match=%s\n",
         N_ITER, (unsigned long long)total, (unsigned long long)(total / N_ITER),
         (uint32_t)res, (uint32_t)want, b3_not_vl4 ? "yes" : "no", b3_ok ? "OK" : "MISMATCH");
  printf("VDOT_METRIC B3 %llu\n", (unsigned long long)(total / N_ITER));
#endif // CHAIN_MIN

#ifdef CHAIN_MIN
  // 最小作业口径：只测 L_base_chain（含跨轮一致性），不跑阶梯链/B3 附加段。
  int ok = vl_ok && rounds_ok && medians_agree && finals_distinct && cf_alt_ok && cf_alt_differs;
  printf("PERF_BASE_CHAIN verdict=%s vl=%s chain_free=%s chain_free_rounds=%s "
         "chain_free_alt=%s chain_free_alt_differs=%s samples=%u rounds=%d "
         "scale=min(ladder/B3_skipped)\n",
         ok ? "ALL_OK" : "HAS_FAIL", vl_ok ? "OK" : "MISMATCH",
         rounds_ok ? "OK" : "MISMATCH", medians_agree ? "OK" : "MISMATCH",
         cf_alt_ok ? "OK" : "MISMATCH", cf_alt_differs ? "yes" : "no",
         pooled_n, ROUNDS);
#else
  int ok = vl_ok && rounds_ok && medians_agree && finals_distinct && cf_alt_ok && cf_alt_differs &&
           ld_ok && ld_alt_ok && ld_alt_differs && b3_ok && b3_not_vl4 && data_discriminates;
  printf("PERF_BASE_CHAIN verdict=%s vl=%s chain_free=%s chain_free_rounds=%s "
         "chain_free_alt=%s chain_free_alt_differs=%s ladder=%s ladder_alt=%s "
         "ladder_alt_differs=%s b3=%s b3_not_vl4=%s discriminates=%s samples=%u rounds=%d "
         "scale=full\n",
         ok ? "ALL_OK" : "HAS_FAIL", vl_ok ? "OK" : "MISMATCH",
         rounds_ok ? "OK" : "MISMATCH", medians_agree ? "OK" : "MISMATCH",
         cf_alt_ok ? "OK" : "MISMATCH", cf_alt_differs ? "yes" : "no",
         ld_ok ? "OK" : "MISMATCH", ld_alt_ok ? "OK" : "MISMATCH",
         ld_alt_differs ? "yes" : "no", b3_ok ? "OK" : "MISMATCH",
         b3_not_vl4 ? "yes" : "no", data_discriminates ? "yes" : "no",
         pooled_n, ROUNDS);
#endif // CHAIN_MIN
  return ok ? 0 : 1;
}
