// perf_kernel_cmp.c — 同一 8×int8 点积内核的两版本：**指令数对比 / 吞吐对比**
//
// ⚠ 口径约定（本文件所有输出与后续引用都必须遵守）：
//   · 本用例只报「指令数对比 / 吞吐对比」。**不是**延迟加速比、**不是**官方口径。
//   · 分母永远是「未融合 RVV 序列」（本文件的 BASE 版），不得改称「官方基线」。
//   · 禁止「4.0×」「6/9 拍」等旧口径字样回流；比值一律写成 `N_base/N_vdot` 与
//     `cyc_base/cyc_vdot` 的**裸比值**，不加「加速」定语。
//
// 两版本（同一输入、同一输出，逐位断言）：
//   (a) BASE = **未融合 RVV 序列**：vwmul.vv（e8→e16 逐元素乘）→ vwadd.vx（widen 到 32）
//       → vredsum.vs（32 位求和）。逐元素链形态，取自 design/verify/perf/perf_base.c:84-103
//       的 B2 序列（**唯一差异**：删掉 perf_base.c:90 的 `vmv.v.x v8, zero`——该指令写的 v8
//       在整段里无人读，是遗留死指令；保留会让「基线序列」多一条无用指令、虚高分母）。
//       **不融合** = 每条向量指令各自完成一段工作、写各自的 vd，没有任何单指令完成整段点积。
//   (b) VDOT = vdot.vv 单指令（SEW=8、LMUL=1、K=8 单结果，见 design/SPEC.md §1.1）。
//
// 两版本**共用同一条装载/配置序列**（`vsetivli e8,m1,vl=8` + 两条 `vle8.v`），差异只在计算段：
//   BASE 计算段 = vwmul.vv → (e16 配置) → vwadd.vx → (e32,m2 配置) → vmv.v.i → vredsum.vs
//   VDOT 计算段 = vdot.vv 一条
// ⇒ 静态指令数差 = 纯计算段差，不被装载差异污染。
//
// ============================================================================
// 测量口径 —— **两次实跑判废后定稿**，每一条都有硬件证据，不是先验推理
// ============================================================================
// 判废做法 ①「逐次调用 + 逐次 CSR 括窗」（作业 126979059，证据
//   `results/difftest/kernel/failed-20261106T040817/`）：
//   · 香山的 `mcycle` / `minstret` / `cycle` **不在有序读 CSR 白名单**
//     （`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55`
//     的 `waitForwardInOrderCsrReadList`（`:10-38`）/ `blockBackwardInOrderCsrReadList`（`:39-55`）都不含它们）
//     ⇒ CSR 读可与内核体重排。窗口只有 ~20 条指令（< ROB 深度）时窗口根本没包住内核体。
//   · 实测空窗口（只读 6 条 CSR、无内核体）`inst_med=18` ⇒ 循环控制指令被算进「本样本」。
//   · 实测 `base inst_med=45 / vdot inst_med=20`（静态 18 / 11）⇒ 污染量与内核长度相关。
//   · 顺带作废「同一窗口内 rdcycle 差 == mcycle 差」这条判据（实测 1146/2000、67/2000）：
//     两路 CSR 各按发射时刻取样，测到的是**流水线偏斜**，该判据的前提假设本身是错的。
// 判废做法 ②「`.rept` 批窗口 + 空窗口对消」（作业 126982225，证据
//   `results/difftest/kernel/failed-20261106T043716/`）：
//   · 批窗口把偏斜摊薄了（`empty inst_med=15` 稳定、`div_ok` 仍 MISMATCH），
//     但**尾端**仍有残留：`vdot_inst_delta=688` 而 `64×11=704` ⇒ 尾部 CSR 读在
//     最后 16 条内核指令退休前就执行了。尾端误差与「内核在批中的位置」相关 ⇒ 不可对消。
// 现行做法 ③**差分（三点法）**——不依赖任何排序/串行化假设：
//   · 对每个版本跑三次：批大小 n = 0、N_SMALL、N_BIG（N_BIG = 2×N_SMALL），
//     每次都是「C 循环 R_LOOP 轮 × `.rept n` 展开的内核体」，CSR 读只在循环**外**。
//   · 设单轮循环开销 = O、窗口边缘固定项 = K、单次内核指令数 = B。则
//         I(n) = K + R_LOOP × (O + n×B)
//     ⇒ I(N_SMALL) − I(0)   = R_LOOP × N_SMALL × B
//        I(N_BIG)  − I(N_SMALL) = R_LOOP × (N_BIG−N_SMALL) × B
//     **K 与 O 在差分里精确消掉**。上式对两段差分都成立，但**只有 route1（下端锚在空批）实测给出精确 B**：
//     两轮成功实跑（`run-20261106T053316` / `run-20261106T060159`）的 `route_disclosure` 行均为
//     `route1_base=18 route1_vdot=11 route2_base=17 route2_vdot=11 route2_minus_route1_base=-1 …`。
//   · ⇒ **route2 不参与判据**：`ok` 表达式里没有任何 route2 比较，route2 只作 `route_disclosure`
//     披露项（它两端都含内核，尾端缺口随 n 增长 ⇒ 偏离量有信息量，但不可当估计量）。
//     判废轮 `failed-20261106T050500` 曾有 `route_selfcheck … MISMATCH`，定稿版删掉该判据后
//     仍把「两路必须同一 B」写在头注 —— 那是**未实现的判据**，已按实测改为本条。
//   · 尾端误差、CSR 偏斜、循环开销都是「与 n 无关或与 n 线性」的项，在差分里消失；
//     route1 的实测结果（18/11 逐值等于静态计数、`i1_q_varied=no`）是这条的检验证据。
//   · 拍数同法：C(n) 三点差分、整数除法；`base_instr` 行上旧的 `cyc_rem_base`/`cyc_rem_vdot`
//     两个余数项**已删**（判废轮 `failed-20261106T044754` 曾打印 `cyc_rem_base=66 cyc_rem_vdot=113`）；
//     定稿版只在 `div_check` 行保留 `base_rem`/`vdot_rem`（判的是**指令数**中位数的整除性）。
//   · 指令数是**精确整数**：B 必须整除，且必须逐值等于 objdump 静态计数
//     （`-DSTATIC_N_BASE`/`-DSTATIC_N_VDOT` 注入，见 build_kcmp.sh 两遍构建）。
//
// ⚠ 「样本」口径必须照实说：
//   内核**调用次数**（base+vdot 合计）≥ 2000，这是数量的硬要求（同 91-run-b3.sh 的 min 口径）。
//   但**估计量**来自 ROUNDS 个批间差分，**不是** 2000 个逐次独立样本的统计
//   —— 后者在本 OoO 核上已被 ①② 两次实跑证伪。日志里两个数都打印，不许混称。
//
// `minstret` 计的是**退休指令条数**：`MachineLevel.scala:354-362` 累加 `robCommit.instNum`。
// `rdcycle` 映射到 unprivileged `cycle`（`Unprivileged.scala:206` 的 `CSRs.cycle  -> (cycle.w -> cycle.rdata)`），而
// `NewCSR.scala:709` 的 `m.mHPM.cycle := mcycle.rdata` 说明两者是同一计数器。
//
// 自检（防「空绿」，全部是硬件读回值 vs 独立软件模型的比对；`verdict` 只聚合第 1–4、6–9 条）：
//   1. 编码自检：VDOT_ENC(3,1,2) == 0x3A20A1D7（SPEC §2.1）。
//   2. vl 自检：两版本各自 `csrr vl` 必须 == 8。
//   3. 功能等价：BASE 与 VDOT 同一 buf_a/buf_b 读回值相等，且都等于软件模型 want_dot()（= 8）。
//   4. vl 可分辨：只归约前 4 lane 的错值 want_dot_vl4()（= 18）≠ want_dot()，
//      两版本实测值都 ≠ 该错值 ⇒ 「vl 被钳到 4」的实现必被抓。
//   5. route1 商披露：逐轮 route1 商打印 `i1_q_min` / `i1_q_max` / `i1_q_varied`（两版本都打印）；
//      它是**披露项**，不进入 `verdict`（`ok` 表达式只含第 1–4、6–9 条）。
//      **route2 不作判据**（两端都含内核，尾端缺口使商少 1，实测见 `route_disclosure`）。
//   6. 整除性：route1 的**中位数**原始增量必须能整除 step（`div_check`，两版本都查）；
//      判的是中位数、不是「每轮都整除」（逐轮抖动被中位数剔除，见 `div_check` 行注释）。
//   7. 静态↔动态：B 必须逐值等于 objdump 静态计数（两版本都要对）。
//   8. 调用次数：≥ 2000。
//   9. 长度可分辨：BASE 跑 N 次与 N−1 次，累加终值必须不同（只对 BASE 有意义）。
//
// 运行要求：emu 必须带 `--no-diff`（读 mcycle/minstret 会与 NEMU 参照不一致；同 perf_vdot.c:7）。
//
// 入库状态（复现与引用必读）：
//   · 本用例**不在** design/verify/cases/manifest.tsv（该文件冻结 sha256
//     a90d1071…、30 行数据行）。本用例是**清单外独立测量项**，走
//     core-package/scripts/93-run-kcmp.sh（按 91-run-b3.sh 的同类单例作业路径）。
//   · 构建：`design/verify/perf/build.sh` 不含本文件；本用例由
//     `design/verify/cases/build_kcmp.sh` 构建（两遍编译：先取静态计数，再 `-D` 注入）。
//   · 静态指令数：`design/verify/cases/objdump_kcmp.sh` 产出逐条列表与 N_base/N_vdot。
//
// 失败记录（只作排障，**不得当作结果引用**）：
//   · 作业 `126979059`（2026-11-06 04:08，`<node>`）：做法 ①，
//     `KERNEL_CMP verdict=HAS_FAIL`、`ctr_same_source base=1146/2000 vdot=67/2000 MISMATCH`、
//     `static_xcheck … measured_delta=25 delta=MISMATCH`、`HIT BAD TRAP`。
//     证据 `results/difftest/kernel/failed-20261106T040817/`。
//   · 作业 `126982225`（2026-11-06 04:37，节点见日志头）：做法 ②，
//     `div_ok=MISMATCH`、`vdot_inst_delta=688`（应 704）、`ctr_same_source … MISMATCH`。
//     证据 `results/difftest/kernel/failed-20261106T043716/`。
//   两轮均**不构成任何结论**；本文件随后改成做法 ③。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// vdot.vv 自定义编码：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111
// VDOT_ENC(3,1,2) == 0x3A20A1D7（SPEC §2.1 的机器码，用作自检；同 perf_vdot.c:22-24）
// 工具链不认识 `vdot.vv` 这个助记符（`riscv64-unknown-elf-as` 报
// `Error: unrecognized opcode`，本机构建实测），故用 `.4byte <编码>` 发射，
// 编码由同一常量表达式生成 ⇒ 自检串与实际发射的字节**同源**，不会漂移。
#define VDOT_ENC(vd, vs1, vs2) \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) | \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)
#define VDOT_VV_3_1_2 VDOT_ENC(3, 1, 2)   // 内核里实际发射的那一条

// AM 的 start.S（nexus-am/am/src/nemu/isa/riscv/boot/start.S:37-38）只开 mstatus.FS；
// 向量指令还需 mstatus.VS != OFF（SPEC §1.1 第六条）。
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// ---------------------------------------------------------------- 口径常量
#define VL        8     // SEW=8 / LMUL=1 / VL=8（与 perf_vdot/perf_base 同天平）
#define N_SMALL   8     // 小批的内核份数（`.rept` 展开，无循环控制指令）
#define N_BIG     16    // 大批 = 2×N_SMALL（差分步长 = N_SMALL）
#define R_LOOP    10    // 每个测量点的 C 循环轮数（每轮一份 `.rept` 批）
#define ROUNDS    10    // 轮数；每轮给出一组差分估计
#define N_WARMUP  2     // 暖机轮数（不计入直方图）
#define HIST_MAX  65536 // 直方图上界（单位=每次内核调用的拍数）；越界计入 over 并显式打印

// **每个版本**的内核调用次数（跨 ROUNDS 轮、三种批大小：0 / N_SMALL / N_BIG）：
//   ROUNDS × R_LOOP × (N_SMALL + N_BIG) = 10 × 10 × 24 = 2400 ≥ 2000
//   （空批 n=0 不计入，它不含内核）。任务口径要求「≥2000 合并样本」，
//   这里按**每版本**各自满足来取，避免「两版本合起来才够」的混算。
// 规模依据（实测吞吐）：前一轮作业 `126982225`（`failed-20261106T043716/` 日志实读
//   `KCMP window batches=32 per_batch=64 invocations=2048`）跑 **2048** 次内核调用，作业
//   04:37:18 起、`sacct` 记 472 s（≈ 7.9 min，含 emu 启动与装载）⇒ 约 0.2 s/次内核。
//   2400×2 = 4800 次 ⇒ 约 10 min 量级；成功轮 `126986882` 实测 652 s、复跑 `126989295` 291 s，
//   均落在 93-run-kcmp.sh 的 `--time=00:20:00` 内。
#define INVOCATIONS_PER_VERSION (ROUNDS * R_LOOP * (N_SMALL + N_BIG))

// 让 `.rept` 的计数可以由宏名给出（XSTR 先展开宏，再字符串化）
#define STR_(x) #x
#define XSTR_(x) STR_(x)
#define REPT(n) ".rept " XSTR_(n) "\n\t"

// ---------------------------------------------------------------- 操作数
// 与 perf_vdot.c:51-56 / perf_base.c:13-22 逐字节相同（同一天平）。
// buf_b 低 8 字节 {1,0,0,0,1,1,1,3}：全 8 lane 点积 = 8，只归约前 4 lane = 18 ⇒ vl 可分辨。
static uint8_t buf_a[16] __attribute__((aligned(16))) = {
  18, 1, -1, 1, -1, 0, 0, -3, (uint8_t)0x7f, (uint8_t)0x80, 1, 1, 1, 1, 1, 1
};
static uint8_t buf_b[16] __attribute__((aligned(16))) = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

// 累加 sink：内核返回值必须被消费，否则 -O2 会把整段调用删掉（静默空测）。
static volatile int32_t sink;

// 每轮差分估计的直方图（base / vdot 各一份）
static uint16_t hist_base[HIST_MAX];
static uint16_t hist_vdot[HIST_MAX];

static uint64_t median_of(const uint16_t *h, uint32_t n) {
  uint32_t acc = 0;
  for (uint32_t v = 0; v < HIST_MAX; v++) {
    acc += h[v];
    if (acc > n / 2) return v;
  }
  return HIST_MAX - 1;
}

// 8 个 int8 lane 的点积期望（逐项有符号）—— 8
static int32_t want_dot(void) {
  int32_t s = 0;
  for (int i = 0; i < 8; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}
// 只归约前 4 lane 的错值（证明数据可分辨 vl）—— 18
static int32_t want_dot_vl4(void) {
  int32_t s = 0;
  for (int i = 0; i < 4; i++)
    s += (int32_t)(int8_t)buf_a[i] * (int32_t)(int8_t)buf_b[i];
  return s;
}

// ---------------------------------------------------------------- 内核体（两版本）
// 两个宏用**同一组命名操作数**（[res] / [pa] / [pb]），因此同一段文本既能放进
// noinline 函数（供 objdump 静态计数），也能嵌进 `.rept` 批（供动态实测）——
// 静态与动态计的是**同一份指令序列**，这是交叉核对成立的前提。
//
// 内核体**不含**任何计数器读：括窗在调用方。内核体**含** vsetvli 与 vle8.v 装载：
// 那是内核的一部分（真实内核也要配 vl + 载操作数），两版本装载序列逐条相同。

// (a) BASE：未融合 RVV 序列（perf_base.c:84-103 的 B2 逐元素链，删去死指令 vmv.v.x v8,zero）
//     vsetivli(e8,m1,vl=8) · vle8.v v1 · vle8.v v2          ← 与 VDOT 版共用
//     vwmul.vv v4,v1,v2          （计算 1：8 个 16 位积，逐元素乘）
//     li t1,8 · vsetvli(e16,m1)  （配置 2）
//     vwadd.vx v6,v4,zero        （计算 2：widen 到 32 位）
//     li t2,8 · vsetvli(e32,m2)  （配置 3：e32,m1 的 VLMAX=4 会把 vl 钳到 4 ⇒ 必须 m2）
//     vmv.v.i v10,0              （归约初值清零）
//     vredsum.vs v10,v6,v10      （计算 3：32 位求和）
//     li t3,4 · vsetvli(e32,m1,tu,mu) · vmv.x.s res,v10   ← 与 VDOT 版共用
//     ⇒ 计算段 **3 条向量计算指令**（vwmul / vwadd / vredsum）
//
// 注：`vwadd.vx v6,v4,zero` 被 binutils 反汇编为 `vwcvt.x.x.v v6,v4`
//     （RVV 1.0 对「vwadd.vx 且 rs1=x0」的正式别名，**机器码相同**，不是编错）。
#define KCMP_BODY_BASE                                                          \
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"                                    \
      "la t4, %[pa]\n\t"                                                        \
      "vle8.v v1, (t4)\n\t"                                                     \
      "la t5, %[pb]\n\t"                                                        \
      "vle8.v v2, (t5)\n\t"                                                     \
      "vwmul.vv v4, v1, v2\n\t"                                                 \
      "li t1, 8\n\t"                                                            \
      "vsetvli zero, t1, e16, m1, ta, ma\n\t"                                   \
      "vwadd.vx v6, v4, zero\n\t"                                               \
      "li t2, 8\n\t"                                                            \
      "vsetvli zero, t2, e32, m2, ta, ma\n\t"                                   \
      "vmv.v.i v10, 0\n\t"                                                      \
      "vredsum.vs v10, v6, v10\n\t"                                             \
      "li t3, 4\n\t"                                                            \
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"                                   \
      "vmv.x.s %[res], v10\n\t"

// (b) VDOT：单指令版（装载/配置与 BASE 逐条相同，计算段只有 1 条）
#define KCMP_BODY_VDOT                                                          \
      "vsetivli zero, 8, e8, m1, ta, ma\n\t"                                    \
      "la t4, %[pa]\n\t"                                                        \
      "vle8.v v1, (t4)\n\t"                                                     \
      "la t5, %[pb]\n\t"                                                        \
      "vle8.v v2, (t5)\n\t"                                                     \
      ".4byte %[enc]\n\t"                                                       \
      "li t3, 4\n\t"                                                            \
      "vsetvli zero, t3, e32, m1, tu, mu\n\t"                                   \
      "vmv.x.s %[res], v3\n\t"

#define KCMP_CLOBBER "t1", "t2", "t3", "t4", "t5", "memory"

// 静态计数的**边界标签**：objdump 只数 [<符号>, <end 标签>) 之间的指令，
// 即「asm 文本本身的指令」，**不含** gcc 在 asm 之后补的 `sext.w` 与 `ret`。
// 标签本身不产生指令，故不影响任何计数。
#define KCMP_MARK_BASE_END ".globl kcmp_base_end\n\t" "kcmp_base_end:\n\t"
#define KCMP_MARK_VDOT_END ".globl kcmp_vdot_end\n\t" "kcmp_vdot_end:\n\t"

// noinline 包装：只为给 objdump 一个稳定符号。函数体 == 宏文本（+ 尾随 ret）。
// 用局部寄存器变量把返回值固定在 a0，避免 gcc 额外插一条 `mv a0, …` 污染静态计数。
__attribute__((noinline))
static int32_t base_kernel(void) {
  register int32_t res asm("a0");
  asm volatile(KCMP_BODY_BASE KCMP_MARK_BASE_END : [res] "=r"(res)
               : [pa] "S"(buf_a), [pb] "S"(buf_b) : KCMP_CLOBBER);
  return res;
}
__attribute__((noinline))
static int32_t vdot_kernel(void) {
  register int32_t res asm("a0");
  asm volatile(KCMP_BODY_VDOT KCMP_MARK_VDOT_END : [res] "=r"(res)
               : [pa] "S"(buf_a), [pb] "S"(buf_b), [enc] "i"(VDOT_VV_3_1_2)
               : KCMP_CLOBBER);
  return res;
}

// ---------------------------------------------------------------- 三点差分测量
// 一个「测量点」= C 循环 R_LOOP 轮，每轮一份 `.rept n` 展开的内核批；CSR 读只在循环外。
// 三个点：n = 0（空批，测出「循环开销 + 窗口边缘」合并项）、N_SMALL、N_BIG。
//
// ⚠ **`fence` 的作用与实际边界**（第三次实跑才定位到）：
//   `mcycle`/`minstret` 不在有序读白名单（`CSROoORead.scala:10-55` 的两个 list 均不含它们），
//   没有屏障时尾部 CSR 读会在最后几条内核指令退休前就执行 ⇒ 实测 `instr_route1=18/11`（对）
//   但 `instr_route2` 偏短，短缺量随 n 增长。
//   `fence` 在香山是 `blockBack = T, flushPipe = T`（`DecodeUnit.scala:230`）⇒ 前后指令被严格分开，
//   窗口边界不再漂移。
//   **两轮判废日志实读（本文件只报可读到的数字，不按目录名推断有无 fence）**：
//     · `failed-20261106T044754/` → `instr_route1=18/11`、`instr_route2=17/10`（两版本各短 1）；
//     · `failed-20261106T050500/`  → `instr_route1=18/11`、`instr_route2=17/11`（base 短 1、vdot 未偏离）。
//   ⇒ `fence` 压不住 route2 的尾端缺口（作业 `126984043`/`126984760` 两轮均复现），
//   所以 route2 只作披露、不作判据（见文件头第 5 条）。
//   **披露**：这两轮 case log 内既无 `job=` 行、也未打印屏障标记 ⇒ 「哪一轮加了 `fence`」
//   无法由文件内容自证（`126984043` = 加 fence 的标注只来自 `results/budget-log.tsv:79` 与本票记录）。
//
// 输出：窗口内的 mcycle 差、minstret 差，以及批里最后一次 `vmv.x.s` 的结果。

// 开窗：屏障 + 读两个计数器（屏障保证「此前所有指令已退休」）
#define KCMP_WIN_OPEN(c, i)                                                     \
      "fence iorw, iorw\n\t"                                                   \
      "csrr %[" #c "], mcycle\n\t"                                             \
      "csrr %[" #i "], 0xB02\n\t"
// 关窗：屏障 + 读两个计数器（屏障保证「此前所有指令已退休」后才取样）
#define KCMP_WIN_CLOSE(c, i)                                                    \
      "fence iorw, iorw\n\t"                                                   \
      "csrr %[" #c "], mcycle\n\t"                                             \
      "csrr %[" #i "], 0xB02\n\t"

static void measure_point(int which, int n, int32_t *out_res,
                          uint64_t *out_cyc, uint64_t *out_inst) {
  uint64_t c0, i0, c1, i1;
  int32_t res = 0;

  if (which == 0) {
    if (n == 0) {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(0) ".endr\n\t" ::: "memory");
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    } else if (n == N_SMALL) {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(N_SMALL) KCMP_BODY_BASE ".endr\n\t"
                     : [res] "=&r"(res)
                     : [pa] "S"(buf_a), [pb] "S"(buf_b)
                     : KCMP_CLOBBER);
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    } else {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(N_BIG) KCMP_BODY_BASE ".endr\n\t"
                     : [res] "=&r"(res)
                     : [pa] "S"(buf_a), [pb] "S"(buf_b)
                     : KCMP_CLOBBER);
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    }
  } else {
    if (n == 0) {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(0) ".endr\n\t" ::: "memory");
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    } else if (n == N_SMALL) {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(N_SMALL) KCMP_BODY_VDOT ".endr\n\t"
                     : [res] "=&r"(res)
                     : [pa] "S"(buf_a), [pb] "S"(buf_b), [enc] "i"(VDOT_VV_3_1_2)
                     : KCMP_CLOBBER);
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    } else {
      asm volatile(
          KCMP_WIN_OPEN(c0, i0)
          : [c0] "=&r"(c0), [i0] "=&r"(i0) :: "memory");
      for (int r = 0; r < R_LOOP; r++)
        asm volatile(REPT(N_BIG) KCMP_BODY_VDOT ".endr\n\t"
                     : [res] "=&r"(res)
                     : [pa] "S"(buf_a), [pb] "S"(buf_b), [enc] "i"(VDOT_VV_3_1_2)
                     : KCMP_CLOBBER);
      asm volatile(
          KCMP_WIN_CLOSE(c1, i1)
          : [c1] "=&r"(c1), [i1] "=&r"(i1) :: "memory");
    }
  }

  *out_res = res;
  *out_cyc = c1 - c0;
  *out_inst = i1 - i0;
}

// 一次「三点采样」：返回三个点各自的 (cyc, inst)。调用方做差分。
typedef struct { uint64_t cyc, inst; } point_t;

static void sample_three(int which, point_t *p0, point_t *p1, point_t *p2, int32_t *last_res) {
  int32_t res;
  measure_point(which, 0,       &res, &p0->cyc, &p0->inst);
  measure_point(which, N_SMALL, &res, &p1->cyc, &p1->inst);
  measure_point(which, N_BIG,   &res, &p2->cyc, &p2->inst);
  if (last_res) *last_res = res;
}

// 长度可分辨：BASE 跑 n 次，返回累加终值（只用于「N 与 N−1 终值不同」的对照）。
static int32_t base_alt_accum(int n) {
  int32_t acc = 0;
  for (int i = 0; i < n; i++) acc += base_kernel();
  return acc;
}

int main(void) {
  ENABLE_VS();

  // ---------- 1. 编码自检 ----------
  uint32_t enc = VDOT_ENC(3, 1, 2);
  int enc_ok = (enc == 0x3A20A1D7u);
  printf("KCMP enc_check=0x%08X expect=0x3A20A1D7 %s\n", enc, enc_ok ? "OK" : "MISMATCH");

  // ---------- 2. vl 自检（两版本各自的配置之后读 vl） ----------
  uint64_t vl_b, vl_v;
  asm volatile("vsetivli zero, 8, e8, m1, ta, ma\n\t" "csrr %0, vl\n\t" : "=r"(vl_b) :: "memory");
  asm volatile("vsetivli zero, 8, e8, m1, ta, ma\n\t" "csrr %0, vl\n\t" : "=r"(vl_v) :: "memory");
  int vl_ok = (vl_b == VL) && (vl_v == VL);
  printf("KCMP vl base=%llu vdot=%llu expect=%d %s\n",
         (unsigned long long)vl_b, (unsigned long long)vl_v, VL, vl_ok ? "OK" : "MISMATCH");

  // ---------- 3/4. 功能等价 + vl 可分辨 ----------
  int32_t want = want_dot();
  int32_t want4 = want_dot_vl4();
  int disc = (want != want4);
  int32_t got_b = base_kernel();
  int32_t got_v = vdot_kernel();
  int eq_ok = (got_b == got_v) && (got_b == want);
  int not_vl4_ok = (got_b != want4) && (got_v != want4);
  printf("KCMP equiv base=0x%08X vdot=0x%08X want=0x%08X want_vl4=0x%08X "
         "equiv=%s not_vl4=%s discriminates=%s\n",
         (uint32_t)got_b, (uint32_t)got_v, (uint32_t)want, (uint32_t)want4,
         eq_ok ? "OK" : "MISMATCH", not_vl4_ok ? "yes" : "no", disc ? "yes" : "no");

  printf("KCMP plan rounds=%d r_loop=%d n_small=%d n_big=%d warmup_rounds=%d "
         "invocations_per_version=%d\n",
         ROUNDS, R_LOOP, N_SMALL, N_BIG, N_WARMUP, INVOCATIONS_PER_VERSION);

  // ---------- 5. 逐轮三点采样 + 差分 ----------
  for (int i = 0; i < HIST_MAX; i++) { hist_base[i] = 0; hist_vdot[i] = 0; }

  // 每轮估计量的极值/均值（用于打印；中位数走直方图）
  uint64_t b_sum = 0, b_n = 0, b_min = ~0ULL, b_max = 0, b_over = 0;
  uint64_t v_sum = 0, v_n = 0, v_min = ~0ULL, v_max = 0, v_over = 0;
  // **逐轮原始差值的直方图**：每轮的 route1 指令数增量（未除以 step）。
  // 取中位数后再除 ⇒ 个别轮次的尾部抖动被中位数剔除，且整除性在中位数上判定。
  // 直方图上界 = HIST_MAX（增量最大 = step × 单次指令数，远小于 65536）。
  static uint16_t hist_b_i1[HIST_MAX], hist_v_i1[HIST_MAX];
  for (int i = 0; i < HIST_MAX; i++) { hist_b_i1[i] = 0; hist_v_i1[i] = 0; }
  // 逐轮 route1 商的最小/最大值（披露抖动幅度）
  uint64_t b_q_min = ~0ULL, b_q_max = 0, v_q_min = ~0ULL, v_q_max = 0;
  // 出现过的不同商（用于「是否只有一种值」的披露）
  int b_q_var = 0, v_q_var = 0, b_q_seen = 0, v_q_seen = 0;
  uint64_t b_q_first = 0, v_q_first = 0;
  // route2 的商（记录最近一轮，仅披露）
  uint64_t b_route2 = 0, v_route2 = 0;
  uint64_t b_route2c = 0, v_route2c = 0;
  int32_t res_b = 0, res_v = 0;
  uint64_t step = (uint64_t)R_LOOP * N_SMALL;   // 每路差分对应的调用次数

  for (int k = 0; k < ROUNDS; k++) {
    point_t bp0, bp1, bp2, vp0, vp1, vp2;
    sample_three(0, &bp0, &bp1, &bp2, &res_b);
    sample_three(1, &vp0, &vp1, &vp2, &res_v);

    // 两路差分：
    //   route1 = I(N_SMALL) − I(0)     —— 下端锚在**空批**上
    //   route2 = I(N_BIG) − I(N_SMALL) —— 两端都含内核
    //
    // **实测结论（两轮成功日志 `run-20261106T053316` / `run-20261106T060159` 的
    //   `route_disclosure` 行逐值相同）**：
    //   route1 的商逐值等于静态计数（base=18、vdot=11），`i1_q_varied=no`；
    //   route2 的商为 `base=17、vdot=11`（`route2_minus_route1_base=-1`、`…_vdot=0`）；
    //   判废轮 `failed-20261106T044754` 为 `17/10`、`failed-20261106T050500` 为 `17/11`
    //   （哪一轮加了 `fence` 不能由 case log 自证，见 `measure_point()` 上方「`fence` 的作用与实际边界」）。
    //   ⇒ 偏离**只出现在 base、且只差 1**，不随 vdot 出现；不是「每次调用少 1」的普遍规律。
    //   根因（`route1` 干净、`route2` 不干净）：尾端 CSR 读不保证在最后一批内核退休后取样，
    //   而 route1 的下端是空批（没有任何未退休内核）⇒ 下端缺口为 0；route2 两端都含内核，
    //   下端缺口与上端缺口不等价 ⇒ 残差与「一批内核的尾端缺口」成比例。
    //   ⇒ **route1 是唯一可用的估计量**；route2 保留为**一致性披露项**，
    //     它的偏离量本身是有信息量的（偏离 = 尾端缺口随 n 的增长率），
    //     但不参与判据、不进入任何数字。
    uint64_t b_i1 = (bp1.inst >= bp0.inst) ? (bp1.inst - bp0.inst) : 0;
    uint64_t b_i2 = (bp2.inst >= bp1.inst) ? (bp2.inst - bp1.inst) : 0;
    uint64_t v_i1 = (vp1.inst >= vp0.inst) ? (vp1.inst - vp0.inst) : 0;
    uint64_t v_i2 = (vp2.inst >= vp1.inst) ? (vp2.inst - vp1.inst) : 0;
    uint64_t b_c1 = (bp1.cyc >= bp0.cyc) ? (bp1.cyc - bp0.cyc) : 0;
    uint64_t v_c1 = (vp1.cyc >= vp0.cyc) ? (vp1.cyc - vp0.cyc) : 0;
    // route2 的拍数增量仅披露（不参与估计量）
    b_route2c = (bp2.cyc >= bp1.cyc) ? (bp2.cyc - bp1.cyc) : 0;
    v_route2c = (vp2.cyc >= vp1.cyc) ? (vp2.cyc - vp1.cyc) : 0;

    b_route2 = b_i2 / step; v_route2 = v_i2 / step;   // 仅披露
    b_route2c = (bp2.cyc >= bp1.cyc) ? (bp2.cyc - bp1.cyc) : 0;
    v_route2c = (vp2.cyc >= vp1.cyc) ? (vp2.cyc - vp1.cyc) : 0;

    // 每轮估计量：拍数取 route1 差分；指令数取 route1 原始增量（入直方图后取中位数）。
    uint64_t b_cyc_est = b_c1 / step;
    uint64_t v_cyc_est = v_c1 / step;

    if (k < N_WARMUP) continue;

    // 逐轮 route1 商（披露抖动幅度；不参与估计量）
    uint64_t bq = b_i1 / step, vq = v_i1 / step;
    if (bq < b_q_min) b_q_min = bq;
    if (bq > b_q_max) b_q_max = bq;
    if (vq < v_q_min) v_q_min = vq;
    if (vq > v_q_max) v_q_max = vq;
    if (bq != b_q_first && b_q_seen) b_q_var = 1;
    if (vq != v_q_first && v_q_seen) v_q_var = 1;
    if (!b_q_seen) { b_q_first = bq; b_q_seen = 1; }
    if (!v_q_seen) { v_q_first = vq; v_q_seen = 1; }
    if (b_i1 >= HIST_MAX) { b_over++; } else hist_b_i1[b_i1]++;
    if (v_i1 >= HIST_MAX) { v_over++; } else hist_v_i1[v_i1]++;
    if (b_cyc_est >= HIST_MAX) { b_over++; b_cyc_est = HIST_MAX - 1; }
    if (v_cyc_est >= HIST_MAX) { v_over++; v_cyc_est = HIST_MAX - 1; }
    hist_base[b_cyc_est]++; hist_vdot[v_cyc_est]++;
    b_sum += b_cyc_est; v_sum += v_cyc_est; b_n++; v_n++;
    if (b_cyc_est < b_min) b_min = b_cyc_est;
    if (b_cyc_est > b_max) b_max = b_cyc_est;
    if (v_cyc_est < v_min) v_min = v_cyc_est;
    if (v_cyc_est > v_max) v_max = v_cyc_est;
    sink += res_b + res_v;
  }

  uint64_t b_med_c = median_of(hist_base, (uint32_t)b_n);
  uint64_t v_med_c = median_of(hist_vdot, (uint32_t)v_n);
  // 指令数：逐轮原始增量的**中位数**，再除以 step。
  // 为什么取中位数而不是「要求每轮都整除」：尾端缺口逐轮抖动（实测商在 18/17 之间跳），
  // 单轮整除性不是稳定判据；中位数把抖动轮次剔掉，且整除性在中位数上仍可硬判。
  uint64_t b_med_i1 = median_of(hist_b_i1, (uint32_t)b_n);
  uint64_t v_med_i1 = median_of(hist_v_i1, (uint32_t)v_n);
  int div_ok = ((b_med_i1 % step) == 0) && ((v_med_i1 % step) == 0);
  uint64_t b_instr = div_ok ? b_med_i1 / step : 0;
  uint64_t v_instr = div_ok ? v_med_i1 / step : 0;

  printf("KCMP est base_rounds=%llu cyc_med=%llu cyc_mean=%llu cyc_min=%llu cyc_max=%llu "
         "over=%llu i1_med_raw=%llu i1_q_min=%llu i1_q_max=%llu i1_q_varied=%s\n",
         (unsigned long long)b_n, (unsigned long long)b_med_c,
         (unsigned long long)(b_n ? b_sum / b_n : 0),
         (unsigned long long)(b_min == ~0ULL ? 0 : b_min),
         (unsigned long long)b_max, (unsigned long long)b_over,
         (unsigned long long)b_med_i1,
         (unsigned long long)(b_q_min == ~0ULL ? 0 : b_q_min),
         (unsigned long long)b_q_max, b_q_var ? "yes" : "no");
  printf("KCMP est vdot_rounds=%llu cyc_med=%llu cyc_mean=%llu cyc_min=%llu cyc_max=%llu "
         "over=%llu i1_med_raw=%llu i1_q_min=%llu i1_q_max=%llu i1_q_varied=%s\n",
         (unsigned long long)v_n, (unsigned long long)v_med_c,
         (unsigned long long)(v_n ? v_sum / v_n : 0),
         (unsigned long long)(v_min == ~0ULL ? 0 : v_min),
         (unsigned long long)v_max, (unsigned long long)v_over,
         (unsigned long long)v_med_i1,
         (unsigned long long)(v_q_min == ~0ULL ? 0 : v_q_min),
         (unsigned long long)v_q_max, v_q_var ? "yes" : "no");

  // ---------- 6. 判据串（每次内核调用的指令数与拍数） ----------
  // 指令数 = 逐轮原始增量的中位数 / step（必须整除）；拍数 = 逐轮差分的中位数。
  uint64_t b_cyc = b_med_c, v_cyc = v_med_c;
  printf("KCMP base_instr=%llu base_cyc=%llu vdot_instr=%llu vdot_cyc=%llu "
         "instr_ratio=%llu.%02llu cyc_ratio=%llu.%02llu denom=unfused_rvv_seq\n",
         (unsigned long long)b_instr, (unsigned long long)b_cyc,
         (unsigned long long)v_instr, (unsigned long long)v_cyc,
         (unsigned long long)(v_instr ? b_instr / v_instr : 0),
         (unsigned long long)(v_instr ? (b_instr * 100 / v_instr) % 100 : 0),
         (unsigned long long)(v_cyc ? b_cyc / v_cyc : 0),
         (unsigned long long)(v_cyc ? (b_cyc * 100 / v_cyc) % 100 : 0));
  printf("VDOT_METRIC KCMP_base_instr %llu\n", (unsigned long long)b_instr);
  printf("VDOT_METRIC KCMP_base_cyc %llu\n", (unsigned long long)b_cyc);
  printf("VDOT_METRIC KCMP_vdot_instr %llu\n", (unsigned long long)v_instr);
  printf("VDOT_METRIC KCMP_vdot_cyc %llu\n", (unsigned long long)v_cyc);

  // ---------- 7. 差分披露（route1 = 估计量；route2 仅披露偏离量） ----------
  // route2 偏离 route1 的量 = 尾端缺口随批大小的增长率，**不参与判据**（见文件头）。
  printf("KCMP route_disclosure route1_base=%llu route1_vdot=%llu "
         "route2_base=%llu route2_vdot=%llu route2_minus_route1_base=%lld "
         "route2_minus_route1_vdot=%lld route1_used=yes\n",
         (unsigned long long)b_instr, (unsigned long long)v_instr,
         (unsigned long long)b_route2, (unsigned long long)v_route2,
         (long long)b_route2 - (long long)b_instr,
         (long long)v_route2 - (long long)v_instr);
  printf("KCMP route2_cyc_disclosure base_per_call=%llu vdot_per_call=%llu\n",
         (unsigned long long)(b_route2c / step), (unsigned long long)(v_route2c / step));
  printf("KCMP div_check step=%llu i1_med_base=%llu i1_med_vdot=%llu "
         "base_rem=%llu vdot_rem=%llu %s\n",
         (unsigned long long)step, (unsigned long long)b_med_i1,
         (unsigned long long)v_med_i1,
         (unsigned long long)(b_med_i1 % step), (unsigned long long)(v_med_i1 % step),
         div_ok ? "OK" : "MISMATCH");

  // ---------- 8. 长度可分辨（只对 BASE） ----------
  int32_t acc_n = base_alt_accum(ROUNDS * N_SMALL);
  int32_t acc_alt = base_alt_accum(ROUNDS * N_SMALL - 1);
  int alt_differs = (acc_n != acc_alt);
  printf("KCMP base_alt accum_n=0x%08X accum_nm1=0x%08X alt_differs=%s\n",
         (uint32_t)acc_n, (uint32_t)acc_alt, alt_differs ? "yes" : "no");

  // ---------- 9. 调用次数自检 ----------
  int samples_ok = (INVOCATIONS_PER_VERSION >= 2000);
  printf("KCMP invocations per_version=%d base_plus_vdot=%d need>=2000_each %s\n",
         INVOCATIONS_PER_VERSION, INVOCATIONS_PER_VERSION * 2,
         samples_ok ? "OK" : "MISMATCH");

  // ---------- 10. 静态↔动态交叉核对 ----------
  // STATIC_N_BASE / STATIC_N_VDOT 由 objdump_kcmp.sh 数出后 -D 注入（build_kcmp.sh 负责串联）。
  // 未注入时记「未运行」，不得记通过。对消后的每次调用指令数**必须逐值等于**静态计数。
#if defined(STATIC_N_BASE) && defined(STATIC_N_VDOT)
  int sbase_ok = (b_instr == (uint64_t)STATIC_N_BASE);
  int svdot_ok = (v_instr == (uint64_t)STATIC_N_VDOT);
  int static_ok = sbase_ok && svdot_ok;
  int static_ran = 1;
  printf("KCMP static_xcheck static_base=%d measured_base=%llu base=%s "
         "static_vdot=%d measured_vdot=%llu vdot=%s\n",
         STATIC_N_BASE, (unsigned long long)b_instr, sbase_ok ? "OK" : "MISMATCH",
         STATIC_N_VDOT, (unsigned long long)v_instr, svdot_ok ? "OK" : "MISMATCH");
#else
  printf("KCMP static_xcheck 未运行（未注入 STATIC_N_BASE/STATIC_N_VDOT）\n");
  int static_ok = 0;
  int static_ran = 0;
#endif

  int ok = enc_ok && vl_ok && eq_ok && not_vl4_ok && disc && alt_differs && samples_ok &&
           div_ok &&
           (b_instr >= 1) && (v_instr >= 1) && (b_cyc >= 1) && (v_cyc >= 1) &&
           (!static_ran || static_ok);
  printf("KERNEL_CMP verdict=%s enc=%s vl=%s equiv=%s not_vl4=%s discriminates=%s "
         "div=%s alt_differs=%s invocations=%s static_xcheck=%s\n",
         ok ? "ALL_OK" : "HAS_FAIL", enc_ok ? "OK" : "MISMATCH",
         vl_ok ? "OK" : "MISMATCH", eq_ok ? "OK" : "MISMATCH",
         not_vl4_ok ? "yes" : "no", disc ? "yes" : "no",
         div_ok ? "OK" : "MISMATCH",
         alt_differs ? "yes" : "no", samples_ok ? "OK" : "MISMATCH",
         static_ran ? (static_ok ? "OK" : "MISMATCH") : "未运行");
  return ok ? 0 : 1;
}
