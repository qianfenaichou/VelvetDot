// vdot_dualchain.c — 双链实验：自证 vdot→vdot 依赖间隔，并把「4 cyc 从哪来」拆到机制层
//
// 触发：`stage3/3.3/report.md:49-70` 的 L_vdot=4 / L_vmacc=4 只给了一个数，没有回答
//       「4 是不是被 old_vd 写回环撑起来的」。本用例把「真 RAW」「同号反依赖」「无依赖」
//       「读旧 vd 的对照组」放在同一把天平上分开测。
//
// 红线（写进代码，避免后续复用漂移）：
//   · 外部公开材料所述的 7 cyc 只按**其自述**记录、未由本仓复跑；
//     本用例只产出**我方实测**，不构造跨队比较，不写「优于同题」「全场唯一」。
//   · 本用例**不进** `design/verify/cases/manifest.tsv`（该文件 sha256 冻 a90d1071…、30 数据行；
//     口径同 perf_base_chain / perf_kernel_cmp 的「清单外独立测量」处理方式）。走
//     `core-package/scripts/96-run-dualchain.sh` 单例作业。
//   · 期望值**不手抄**：全部由 `design/verify/cases/dualchain_check.py --emit-header` 生成
//     `dualchain_expected.h`（vdot 步用 `design/verify/vdot_model.py` 金模型；vmacc/vadd 步按标准
//     RVV 逐 lane 复算），本文件只 include 它。
//   · 注（2026-11-07）：补充披露注释（O 钳 0 / O 少乘 I / vs1-vs2 不可检 / 范本行号 /
//     判读规则标「跑前假设」），**仅注释改动、行为未改**；已构建/已实跑镜像对应改动前的源
//     （`source_sha256=9e6dba11…`，见 `results/difftest/dualchain/dualchain_build_summary.txt`）。
//
// ============================================================================
// 八条链（同 VL=8 / SEW=8 / LMUL=1 / 同操作数 / 同测量法）
// ============================================================================
//   M1  `vdot.vv v10, v10, v1`  —— 自别名：vd==vs2。指令内是 WAR（写 v10 不得压掉同拍
//       vs2 读），跨指令是真 RAW（后条 vs2 读前条 v10）。report.md:51-53 的 L_vdot 就是它。
//   M2  `vdot.vv v11,v10,v1` / `vdot.vv v10,v11,v1` 交替 —— 跨寄存器真 RAW：依赖只走
//       「上一条 vd → 本条 vs2」，本条 vd 与上一条 vd 不同号 ⇒ 同号 old_vd 假依赖被拆开。
//   M3  `vdot.vv v3, v1, v2` 重复 —— 无数据依赖（源为常量、vd 固定且不被读）。
//       功能侧：结果恒 = dot(a,b)，与执行次数无关、与旧 vd 预填无关（M3b 预填 0xAB）。
//       **它检验 vdRen=F**：若实现读旧 vd（src3=vp），同一 vd 的连续写会形成 WAW 链。
//   M4  `vmacc.vv v10, v1, v10` —— 对照组：old_vd 是语义输入且 vd==vs2。链形状同 M1（但指令不同）。
//   M5  `vmacc.vv v10, v1, v2`  —— 对照组：唯一串行源就是 old_vd（vs2 是常量）。测量形状同 M3（但指令不同）。
//   M6  `vadd.vv v10, v10, v1`  —— 非 vimac 的 ALU 参照链（旧 vd 也是语义输入）。
//   M7  `vadd.vv v3, v1, v2`    —— 无依赖地板（源常量、vd 固定不被读，走 vialuF）。
//   M8  `vdot.vv v8..v15 轮流写、源常量` —— 无依赖且**不同 vd**：释放同号 WAW 压力。
//       与 M3（同一 vd）比：若同号写被串行化，M3 会明显慢于 M8。
//
// ---- 同口径对照三臂（2026-11-07 确定；复现外部公开材料的依赖链口径，方法见 §M9 段） ----
//   M9  `vdot.vv v30, v31, v30` —— 本项 vdot 依赖链：vd==vs1(v30) 同时是源兼目的，
//       下次迭代读上次结果（对方 dependent_w1_vdot 的同链形状；编码槽位不同）。
//   M10 标准 RVV 五指令等价链（vwmul/vset e16/vmv·0/vwredsum/vset e8）—— 对方
//       dependent_w1_rvv 的同构基线；用于确认「同口径在本 emu 上能复现出同类基线量级」。
//   M11 空循环 control —— 对方 control 臂；只用于「扣空循环后」的调整值。
//   口径：N ∈ {0,64,256,1024}、每点 3 次重复取中位数、4 点 OLS 斜率（含循环开销）。
//   红线：对方 7.008065 是【对方材料陈述】、本仓未复跑其镜像；只做同口径量级对照，不写「优于同题」。
//
// 判读规则【跑前假设，非结果】（2026-11-06 开跑前写死；实测见 stage3/3.3/sections/dualchain.md §4.8：
// 依赖链 q8>q4 使差分模型失效，D_M* 只能当上界参考，不得读作依赖延迟）：
//   · D_M1 ≈ D_M2 ≈ 4 且 D_M1 ≈ D_M5 ≈ D_M4 ⇒ 依赖间隔由 vs2→vd 通路的真 RAW 决定；
//   · D_M3 ≈ D_M8 ≈ D_M7（都 ≈ 吞吐地板 1/拍）⇒ 无 RAW 时 vdot 不被 old_vd 串行化；
//     而 D_M5 ≈ 4 ⇒ 读旧 vd 的 vmacc 被串行化 ⇒ 机制归因（vd_old=INT.X ⇒ 无写回环）成立；
//   · D_M3 ≈ D_M5 ⇒ 判别失败，报告只写「口径不同、不可归因」，不得写优势。
//
// ============================================================================
// 测量口径
// ============================================================================
// 主指标 D_<链> = **差分中位数**（评审最关心的「依赖间隔」，参考 perf_kernel_cmp.c 的
//   中位数口径与「CSR 读可与内核体重排」的实测教训，见 perf_kernel_cmp.c 判废做法 ①②）：
//     每轮测 C(n) 与 C(2n)：n 个 rep、每 rep 8 条同一种链指令（M2 是 8 对交替、16 条），
//     rdcycle 只括在循环外；逐轮商 q_r = (C(2n) − C(n)) / (8n) 消掉固定开销与每轮循环开销；
//     取 8 轮的**中位数**，打印到毫拍（milli）再四舍五入。
//   为什么不拿逐条 rdcycle 括窗当主指标：香山的 mcycle/cycle 读**可与内核体重排**
//   （`repos/XiangShan/src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala:10-55`
//   的有序读/屏蔽读白名单都不含它们），短窗口下括窗会低估甚至测到流水线偏斜
//   （perf_kernel_cmp.c 头注的判废记录）。本用例把它降为**附报**口径：
//     附报 B_<链> = 逐条 rdcycle 括窗差的中位数（前 16 次暖机不计，直方图求中位），
//     与 design/verify/perf/perf_vdot.c:104-140（逐条 rdcycle 括窗）逐项同构，仅供与 report.md 的 4
//     交叉对照，**不参与判据**。
// 运行要求：emu 必须带 --no-diff（读 mcycle/cycle 会与 NEMU 参照不一致；同 perf_vdot.c:7）。
//
// 自检（防空绿，逐条都是「硬件读回值 vs 金模型期望」）：
//   1. 编码自检：VDOT_ENC(3,1,2) == 0x3A20A1D7（SPEC.md §2.1）。
//   2. vl 自检：csrr vl 必须 == 8（写了 vl=8 实际不是 8 时立刻红）。
//   3. 功能自检：每条 DUALCHAIN <tag> func 行的字节必须逐字节等于金模型头文件。
//   4. 长度可分辨：M1/M4/M5/M6 跑 N 与 N-1、M2 跑 N 与 N-2，两条长度的期望必须不同；
//      alt_lines= 逐链打印，任一为 no 即判失败（截断实现会露馅）。
//   5. 反累加自检：M3 与 M3b（旧 vd 预填 0xAB×16）必须给出同一结果，且都等于单次 dot(a,b)。
//   6. 汇总串：DUALCHAIN verdict=ALL_OK（由 96-run-dualchain.sh 作为自检串硬判）。
//
// G0 反例（用 -DDC_G0=1 编出的第二个镜像，ALGORITHM.md §3.1）：
//   期望值被**故意翻转 1 bit**（每个期望数组 byte0 ^= 0x01），DUT 与 NEMU 仍逐位一致 ⇒ 必然
//   HIT GOOD TRAP、必然无 ABORT；只有本用例内嵌的逐字节比对能抓住它 ⇒ 必须打印
//   CASE vdot_dualchain_g0: MISMATCH（主镜像里这个 tag 不存在）。G0 镜像不跑计时（只跑
//   功能链），因此它的墙钟远小于主镜像。
//
// 依据：SPEC.md §1.1/§1.2/§2.1；ARCHITECTURE.md §4.1 X2/X6、§6.1-§6.3（vdRen=F、
//       不登记 vmaInsts、isMacc 不含 vdot）；CODING-STD.md §3.4（fireS1 的导出约束）；
//       ALGORITHM.md §3.4（三口径）/ §3.1（G0）；跨口径数值不相减。
#include <am.h>
#include <klib.h>
#include <stdint.h>

#include "dualchain_expected.h"

// ---------------------------------------------------------------------------
// vdot.vv 编码（SPEC.md §2.2）：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111
// 宏实参顺序 = (vd, vs1, vs2)（位域 vs1=[19:15]、vs2=[24:20]）；
// **汇编打印顺序是 vdot.vv vd, vs2, vs1**（同 perf_vdot.c:20-26 / vdot_xcontam.c:78-84）。
// ---------------------------------------------------------------------------
#define VDOT_ENC(vd, vs1, vs2)                                                  \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)
#define EMIT_VDOT(vd, vs1, vs2) \
  asm volatile(".4byte %0" :: "i"(VDOT_ENC(vd, vs1, vs2)) : "memory")

static inline uint64_t rdcycle(void) {
  uint64_t c;
  asm volatile("rdcycle %0" : "=r"(c));
  return c;
}

// AM 的 start.S 只开 mstatus.FS；任何向量指令前必须把 mstatus.VS 置为非 OFF（SPEC.md §1.1）
#define ENABLE_VS() \
  asm volatile("li t0, 0x600\n\t" "csrs mstatus, t0\n\t" ::: "t0")

// 统一把 vtype 复位成 e8,m1,vl=8,ta,ma。**每次 dump16 之后必须再调一次**：dump16 会把
// vtype 改成 e32/vl=4，而 vdot 在 SEW≠8 时按 SPEC §1.1 是非法指令 —— 此前一次实跑正是
// 漏了这次复位，M1_alt 起每次都撞非法指令陷阱，作业一直挂到 20 min TIMEOUT
// （证据：results/difftest/dualchain/cases/vdot_dualchain.20261106T143414.log 止于 M1 func）。
static inline void set_vl8(void) {
  asm volatile("li t0, 8\n\t" "vsetvli zero, t0, e8, m1, ta, ma\n\t" ::: "t0");
}

// 操作数：与 perf_vdot.c / perf_vadd.c / perf_vmacc.c 逐字节相同（同一天平）。
// dot(a,a)=337、dot(a,b)=8（均为 VL=8 前 8 lane）两者不等 ⇒「只归约前 4 lane」「符号/位宽错」
// 会给出别的数。**但「vs1/vs2 搞反」不可检**：点积可交换，交换两源结果不变，本用例不声称能检出它。
static const int8_t dc_a[16] = {
  18, 1, -1, 1, -1, 0, 0, -3, 127, -128, 1, 1, 1, 1, 1, 1
};
static const int8_t dc_b[16] = {
  1, 0, 0, 0, 1, 1, 1, 3, -1, -1, 2, 2, 2, 2, 2, 2
};

/* 16 字节读回：e32/vl=4 视图下 vse32.v 存 4 个 32 位元素（同 perf_vdot.c:143-150）。
   调用前不需要 set_vl8；调用后**必须** set_vl8（vtype 已被改成 e32）。 */
static void dump16(uint8_t out[16], int vreg) {
  uint32_t tmp[4] = {0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu};
  switch (vreg) {
    case 3:
      asm volatile("li t0, 4\n\t" "vsetvli zero, t0, e32, m1, tu, mu\n\t"
                   "vse32.v v3, (%0)\n\t" :: "r"(tmp) : "t0", "memory");
      break;
    case 8:
      asm volatile("li t0, 4\n\t" "vsetvli zero, t0, e32, m1, tu, mu\n\t"
                   "vse32.v v8, (%0)\n\t" :: "r"(tmp) : "t0", "memory");
      break;
    case 10:
      asm volatile("li t0, 4\n\t" "vsetvli zero, t0, e32, m1, tu, mu\n\t"
                   "vse32.v v10, (%0)\n\t" :: "r"(tmp) : "t0", "memory");
      break;
    case 11:
      asm volatile("li t0, 4\n\t" "vsetvli zero, t0, e32, m1, tu, mu\n\t"
                   "vse32.v v11, (%0)\n\t" :: "r"(tmp) : "t0", "memory");
      break;
    case 30:
      asm volatile("li t0, 4\n\t" "vsetvli zero, t0, e32, m1, tu, mu\n\t"
                   "vse32.v v30, (%0)\n\t" :: "r"(tmp) : "t0", "memory");
      break;
    default:
      break;
  }
  for (int i = 0; i < 16; i++) out[i] = ((const uint8_t *)tmp)[i];
}

/* 期望数组在 G0 镜像里被翻转 1 bit（其余镜像原样返回）。 */
static const uint8_t *expect_of(const uint8_t *want, uint8_t *scratch) {
#ifdef DC_G0
  for (int i = 0; i < 16; i++) scratch[i] = want[i];
  scratch[0] ^= 0x01;
  return scratch;
#else
  (void)scratch;
  return want;
#endif
}

static int same16(const uint8_t *x, const uint8_t *y) {
  for (int i = 0; i < 16; i++) if (x[i] != y[i]) return 0;
  return 1;
}

static int cmp_bytes(const uint8_t *got, const uint8_t *want, int n, char *wantbuf, size_t wz) {
  int bad = 0;
  size_t off = 0;
  for (int i = 0; i < n; i++) if (got[i] != want[i]) bad++;
  wantbuf[0] = '\0';
  for (int i = 0; i < n; i++) {
    int wr = snprintf(wantbuf + off, wz - off, "%s%02X", i ? " " : "", want[i]);
    if (wr < 0 || (size_t)wr >= wz - off) break;
    off += (size_t)wr;
  }
  return bad;
}

static void print_func(const char *tag, int n, int bad, const char *wantbuf, int alt) {
  printf("DUALCHAIN %s func checklen=%d bytes_bad=%d alt_differs=%s want=[%s]\n",
         tag, n, bad, alt ? "yes" : "no", wantbuf);
}

/* ===========================================================================
 * 操作数装载与各链的初值
 * ========================================================================= */
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
      "csrr %0, vl\n\t"
      : "=r"(vl)
      : "S"(dc_a), "S"(dc_b)
      : "t0", "a0", "memory");
  return vl;
}

static void init_v10(void) {
  set_vl8();
  asm volatile("vmv.v.v v10, v1\n\t" ::: "memory");
}
static void init_v10_v11(void) {
  set_vl8();
  asm volatile("vmv.v.v v10, v1\n\t" "vmv.v.v v11, v1\n\t" ::: "memory");
}
static void init_v8_v15(void) {
  set_vl8();
  asm volatile("vmv.v.v v8, v1\n\t"  "vmv.v.v v9, v1\n\t"
               "vmv.v.v v10, v1\n\t" "vmv.v.v v11, v1\n\t"
               "vmv.v.v v12, v1\n\t" "vmv.v.v v13, v1\n\t"
               "vmv.v.v v14, v1\n\t" "vmv.v.v v15, v1\n\t" ::: "memory");
}
static void prefill_v3(void) {
  set_vl8();
  uint32_t pf = 0xABu;
  asm volatile("vmv.v.x v3, %0\n\t" :: "r"(pf) : "memory");
}
/* 同口径对照（M9/M10/M11）的初值：v30 = a（链的源兼目的）、v31 = b（常量源）。
   与对方 dependent_w1 程序一致：每次测量前把 v30 复位成 INPUT_A。
   G0 镜像不跑计时臂 ⇒ 该函数在 G0 里未使用，挂 unused 属性（AM 用 -Wall -Werror）。 */
static void __attribute__((unused)) init_v30_v31(void) {
  set_vl8();
  asm volatile("vmv.v.v v30, v1\n\t" "vmv.v.v v31, v2\n\t" ::: "memory");
}

/* ===========================================================================
 * 链指令序列（每条链一个 STEP 宏；M2 的 STEP 是「一对」）
 * ========================================================================= */
#define STEP_M1() EMIT_VDOT(10, 1, 10)
#define STEP_M2() do { EMIT_VDOT(11, 1, 10); EMIT_VDOT(10, 1, 11); } while (0)
#define STEP_M3() EMIT_VDOT(3, 1, 2)
#define STEP_M4() asm volatile("vmacc.vv v10, v1, v10\n\t" ::: "memory")
#define STEP_M5() asm volatile("vmacc.vv v10, v1, v2\n\t" ::: "memory")
#define STEP_M6() asm volatile("vadd.vv v10, v10, v1\n\t" ::: "memory")
#define STEP_M7() asm volatile("vadd.vv v3, v1, v2\n\t" ::: "memory")
#define STEP_M8() do { EMIT_VDOT(8, 1, 2);  EMIT_VDOT(9, 1, 2);  \
                       EMIT_VDOT(10, 1, 2); EMIT_VDOT(11, 1, 2); \
                       EMIT_VDOT(12, 1, 2); EMIT_VDOT(13, 1, 2); \
                       EMIT_VDOT(14, 1, 2); EMIT_VDOT(15, 1, 2); } while (0)

/* ---------- 功能链：跑 len 步（每步 1 条；M2 每步 2 条、M8 每步 8 条） ---------- */
#define DEFINE_FUNC(NAME, STEP)                     \
static void NAME(int len) {                         \
  for (int i = 0; i < len; i++) { STEP; }           \
}
DEFINE_FUNC(func_m1, STEP_M1())
DEFINE_FUNC(func_m2, STEP_M2())
DEFINE_FUNC(func_m3, STEP_M3())
DEFINE_FUNC(func_m4, STEP_M4())
DEFINE_FUNC(func_m5, STEP_M5())
DEFINE_FUNC(func_m6, STEP_M6())
DEFINE_FUNC(func_m7, STEP_M7())
DEFINE_FUNC(func_m8, STEP_M8())

/* 计时函数在 G0 镜像里不跑，但 AM 用 -Wall -Werror ⇒ 统一挂 unused 属性 */
#ifdef DC_G0
#define DC_TIMING_ONLY __attribute__((unused))
#else
#define DC_TIMING_ONLY
#endif

/* ---------- 差分测量：解出「每链步间隔 L」与「每 rep 固定开销 O」 ----------
 * 每次测量跑 reps 个 rep，每 rep 发 R 条链指令（R ∈ {4,8}，宏展开保证无内部分支）。
 *   C(n)   = K + n·(R·L + O)
 *   C(2n)  = K + 2n·(R·L + O)
 *   q(R)   = (C(2n) − C(n)) / (n·R) = L + O/R
 * 于是  L = 2·q(8) − q(4)   （每链步拍数，毫拍精度）
 *      O = 8·(q(4) − q(8))  （每个 rep 的固定开销，毫拍）
 * q 由每轮商取中位数（N_ROUNDS 轮），与 perf_kernel_cmp.c 的中位数口径同构。 */
/* 注意：S 可能是 `asm volatile(...)`（无分号）或 `do{...}while(0)`，拼在一起时
   必须由本宏补分号，否则 `do{...}while(0) do{...}while(0)` 语法错误。 */
#define STEP4(S) S; S; S; S
#define STEP8(S) S; S; S; S; S; S; S; S

#define DEFINE_BULK2(NAME, STEP)                                        \
static DC_TIMING_ONLY uint64_t NAME##_lo(int reps) {                                    \
  uint64_t c0, c1;                                                       \
  c0 = rdcycle();                                                        \
  for (int i = 0; i < reps; i++) { STEP4(STEP); }                        \
  c1 = rdcycle();                                                        \
  return c1 - c0;                                                        \
}                                                                        \
static DC_TIMING_ONLY uint64_t NAME##_hi(int reps) {                                    \
  uint64_t c0, c1;                                                       \
  c0 = rdcycle();                                                        \
  for (int i = 0; i < reps; i++) { STEP8(STEP); }                        \
  c1 = rdcycle();                                                        \
  return c1 - c0;                                                        \
}
DEFINE_BULK2(bulk_m1, STEP_M1())
DEFINE_BULK2(bulk_m2, STEP_M2())
DEFINE_BULK2(bulk_m3, STEP_M3())
DEFINE_BULK2(bulk_m4, STEP_M4())
DEFINE_BULK2(bulk_m5, STEP_M5())
DEFINE_BULK2(bulk_m6, STEP_M6())
DEFINE_BULK2(bulk_m7, STEP_M7())
DEFINE_BULK2(bulk_m8, STEP_M8())

typedef uint64_t (*bulk_fn)(int);
typedef void (*init_fn)(void);

/* ===========================================================================
 * M9/M10/M11：复现外部公开材料的「依赖链」口径（2026-11-07 确定）
 * ---------------------------------------------------------------------------
 * 对方口径原文（`相关证明材料/performance/README.md:35`，【对方材料陈述】）：
 *   「依赖链参照为 20.991935 对 7.008065 周期/点积，周期比 2.995」；
 * 方法（对方仓库公开）：`experiments/throughput/study.py` + `verified/generated_source/
 * dependent_w1_{vdot,rvv,control}_n{0,64,256,1024}.S`
 *   · 链形状 w1：一条点积，**vd 同时是源（v30）+ 目的**，下次迭代读上次结果；
 *   · N ∈ {0,64,256,1024}，每点 3 次重复取中位数，4 点最小二乘斜率 = 周期/点积
 *     （**含循环开销**，不扣空循环；扣除空循环的估计另表）；
 *   · 计时 = `csrr cycle` 括住整段循环；完成后统一比较完整 128 位结果。
 * 复现边界（如实）：
 *   · 对方 vdot 编码 funct6=0b101100、vs1=30/vs2=31/vd=30（`vdot_word`），与本项 0x0E
 *     **不同槽位** ⇒ 其镜像不能直接跑；本项复现的是**链形状 + N 集 + 斜率拟合**这套口径，
 *     不是逐字节复跑其程序。
 *   · 对方 cycle 网格 8 拍（落地垫片把计数右移 3 再左移 2）；本项 `rdcycle` 精确到 1 拍。
 *   · 对方每次重复单独启动 emu；本项同一进程内做 3 次重复、同 N 取中位数。
 *   · 本项计时窗口只括循环；对方窗口还含循环后的 store/fence/比较（常数，只进截距）。
 * 红线：对方 7.008065 是【对方材料陈述】、本仓未复跑其镜像；本节只做**同口径量级对照**，
 *   不写「优于同题」，不把 M9 与对方数字相除当加速比。
 * ========================================================================= */
#define DC_G44_NP 4
#define DC_G44_REP 3
static const int dc_g44_n[DC_G44_NP] = {0, 64, 256, 1024};

/* M9：本项 vdot 依赖链（vd=30, vs1=30, vs2=31 ⇒ v30 既源又目的；点积可交换，与对方同形） */
static DC_TIMING_ONLY void chain_g44_vdot(int n) {
  for (int i = 0; i < n; i++) { EMIT_VDOT(30, 30, 31); }
}

/* M10：标准 RVV 五指令等价链（对方 dependent_w1_rvv 的同构序列；本项用同一组标准 RVV 指令，
   独立重写，不复制对方源码）：vwmul → vset(e16) → vmv.v.i 清零 → vwredsum → vset(e8) */
static DC_TIMING_ONLY void chain_g44_rvv(int n) {
  for (int i = 0; i < n; i++) {
    asm volatile(
        "vwmul.vv v16, v31, v30\n\t"
        "vsetivli zero, 8, e16, m1, tu, mu\n\t"
        "vmv.v.i v30, 0\n\t"
        "vwredsum.vs v30, v16, v30\n\t"
        "vsetivli zero, 8, e8, m1, ta, ma\n\t"
        ::: "memory");
  }
}

/* M11：空循环 control 臂（对方 control；只用来算「扣空循环后」的估计，不参与主结论） */
static DC_TIMING_ONLY void chain_g44_ctrl(int n) {
  for (int i = 0; i < n; i++) { asm volatile("" ::: "memory"); }
}

typedef void (*chain_fn)(int);

/* 同口径计时单元：init 在窗口外；窗口只含循环本体（固定 call/fence 开销进截距）。 */
static DC_TIMING_ONLY uint64_t g44_time(chain_fn fn, init_fn init, int n) {
  init();
  asm volatile("fence rw, rw" ::: "memory");
  uint64_t c0 = rdcycle();
  fn(n);
  asm volatile("fence rw, rw" ::: "memory");
  uint64_t c1 = rdcycle();
  return c1 - c0;
}

static DC_TIMING_ONLY uint64_t median3(uint64_t a, uint64_t b, uint64_t c) {
  if (a > b) { uint64_t t = a; a = b; b = t; }
  if (b > c) { b = c; }
  if (a > b) { b = a; }
  return b;
}

/* 每臂：4 个 N × 3 次重复 → 同 N 中位数 → OLS 斜率（milli 拍/点积，含循环开销）。
   R² 用独立恒等式 (NΣxy−ΣxΣy)² / ((NΣxx−(Σx)²)(NΣyy−(Σy)²))，与逐点残差式互为交叉验证。 */
static DC_TIMING_ONLY void g44_report(const char *tag, chain_fn fn, init_fn init) {
  uint64_t med[DC_G44_NP];
  for (int p = 0; p < DC_G44_NP; p++) {
    uint64_t y[DC_G44_REP];
    for (int r = 0; r < DC_G44_REP; r++) y[r] = g44_time(fn, init, dc_g44_n[p]);
    med[p] = median3(y[0], y[1], y[2]);
    printf("DUALCHAIN_G44 %s n=%d cycles=%llu y=[%llu %llu %llu]\n",
           tag, dc_g44_n[p], (unsigned long long)med[p],
           (unsigned long long)y[0], (unsigned long long)y[1], (unsigned long long)y[2]);
  }
  int64_t sx = 0, sy = 0, sxy = 0, sxx = 0, syy = 0;
  for (int p = 0; p < DC_G44_NP; p++) {
    int64_t x = dc_g44_n[p], y = (int64_t)med[p];
    sx += x; sy += y; sxy += x * y; sxx += x * x; syy += y * y;
  }
  const int64_t N = DC_G44_NP;
  int64_t den = N * sxx - sx * sx;
  int64_t num = N * sxy - sx * sy;
  int64_t slope_milli = (num * 1000 + den / 2) / den;
  int64_t icept_milli = (sy * 1000 - slope_milli * sx) / N;
  /* R² 用独立恒等式 (NΣxy−ΣxΣy)² / ((NΣxx−(Σx)²)(NΣyy−(Σy)²))；
     量级核对：num≤b·den（b≈9、den≈2.67e6）⇒ num²·1000≤4.6e17，int64 安全。 */
  int64_t r2_milli = 0;
  int64_t denom2 = N * syy - sy * sy;
  if (den > 0 && denom2 > 0) {
    int64_t rn = num * num * 1000;
    int64_t rd = den * denom2;
    r2_milli = (rn + rd / 2) / rd;
  }
  printf("DUALCHAIN_G44 %s fit points=%d repeats=%d slope_milli=%llu intercept_milli=%llu r2_milli=%llu\n",
         tag, DC_G44_NP, DC_G44_REP, (unsigned long long)slope_milli,
         (unsigned long long)icept_milli, (unsigned long long)r2_milli);
  printf("DUALCHAIN_METRIC %s_slope_milli %llu\n", tag, (unsigned long long)slope_milli);
}

static DC_TIMING_ONLY uint64_t median_u64(uint64_t *v, int n) {
  for (int i = 1; i < n; i++) {
    uint64_t key = v[i];
    int j = i - 1;
    while (j >= 0 && v[j] > key) { v[j + 1] = v[j]; j--; }
    v[j + 1] = key;
  }
  if (n % 2) return v[n / 2];
  return (v[n / 2 - 1] + v[n / 2]) / 2;
}

/* 求 q(R)（毫拍/链指令）：每轮 (C(2n)−C(n))·1000/(n·R·I)，取 N_ROUNDS 轮中位数。
   I = 每条 STEP 的指令数（M2 为 2、M8 为 8，其余 1）。 */
static DC_TIMING_ONLY uint64_t q_of(bulk_fn fn, init_fn init, int R, int I) {
  uint64_t q[DC_N_ROUNDS];
  for (int r = 0; r < DC_N_ROUNDS; r++) {
    uint64_t c1, c2;
    init(); c1 = fn(DC_N_REPS);
    init(); c2 = fn(2 * DC_N_REPS);
    if (c2 <= c1) { q[r] = 0; continue; }
    q[r] = ((c2 - c1) * 1000ULL) / ((uint64_t)DC_N_REPS * (uint64_t)R * (uint64_t)I);
  }
  return median_u64(q, DC_N_ROUNDS);
}

static DC_TIMING_ONLY void dep_report(const char *tag, bulk_fn fn_lo, bulk_fn fn_hi,
                       init_fn init, int I) {
  uint64_t q_lo = q_of(fn_lo, init, DC_NREP_LO, I);
  uint64_t q_hi = q_of(fn_hi, init, DC_NREP_HI, I);
  /* L = 2·q_hi − q_lo；O = R_hi·(q_lo − q_hi)（R_hi=8）
     口径披露（2026-11-07 补注，仅注释、行为未改）：
       · q_lo/q_hi 已是**每指令**商（q_of 内已除 I），故 L 也是每指令量；
       · O 的每 rep 固定开销应为 R·I·(q_lo−q_hi)；本式只对 I=1 成立，M2(I=2)/M8(I=8) 少乘 I
         （这两条链 q_lo≤q_hi、O 均被钳 0，故已打印值未受影响）；
       · O 用三元表达式**钳 0**：依赖链 q_lo<q_hi（差分模型失效）时真实反解为负（M1 约 −14.75 拍/rep），
         打印的 O_milli=0 是钳位结果，**不是"开销为零"**；负值与模型失效在报告 §4.8.2 披露。 */
  uint64_t L_milli = (q_hi > q_lo / 2) ? (2 * q_hi - q_lo) : 0;
  uint64_t O_milli = (q_lo > q_hi) ? ((uint64_t)DC_NREP_HI * (q_lo - q_hi)) : 0;
  uint64_t L_round = (L_milli + 500) / 1000;
  printf("DUALCHAIN %s dep I=%d q4_milli=%llu q8_milli=%llu L_milli=%llu L=%llu O_milli=%llu\n",
         tag, I, (unsigned long long)q_lo, (unsigned long long)q_hi,
         (unsigned long long)L_milli, (unsigned long long)L_round,
         (unsigned long long)O_milli);
  printf("DUALCHAIN_METRIC %s %llu\n", tag, (unsigned long long)L_round);
  printf("DUALCHAIN_METRIC %s_milli %llu\n", tag, (unsigned long long)L_milli);
}

int main(void) {
  ENABLE_VS();

  const uint32_t enc = VDOT_ENC(3, 1, 2);
  const int enc_ok = (enc == 0x3A20A1D7u);
  printf("DUALCHAIN enc_check=0x%08X expect=0x3A20A1D7 %s\n", enc,
         enc_ok ? "OK" : "MISMATCH");

  const uint64_t vl = load_operands();
  const int vl_ok = (vl == 8);
  printf("DUALCHAIN vl=%llu expect=8 %s\n", (unsigned long long)vl, vl_ok ? "OK" : "MISMATCH");
  printf("DUALCHAIN expected_sha256=%s\n", DUALCHAIN_EXPECTED_SHA256);

  uint8_t got[16], scr[16];
  char wantbuf[3 * 16 + 4];
  int bad = 0, fails = 0;

  /* 长度判别 / 反累加的前提（不依赖运行时数据，先报出来） */
  const int alt_m1  = !same16(DCW_M1, DCW_M1_alt);
  const int alt_m2a = !same16(DCW_M2_v10, DCW_M2_v10_alt);
  const int alt_m2b = !same16(DCW_M2_v11, DCW_M2_v11_alt);
  const int alt_m4  = !same16(DCW_M4, DCW_M4_alt);
  const int alt_m5  = !same16(DCW_M5, DCW_M5_alt);
  const int alt_m6  = !same16(DCW_M6, DCW_M6_alt);
  const int m3_same = same16(DCW_M3, DCW_M3b);
  printf("DUALCHAIN alt_lines m1=%s m2v10=%s m2v11=%s m4=%s m5=%s m6=%s m3_oldvd_invariant=%s\n",
         alt_m1 ? "yes" : "no", alt_m2a ? "yes" : "no", alt_m2b ? "yes" : "no",
         alt_m4 ? "yes" : "no", alt_m5 ? "yes" : "no", alt_m6 ? "yes" : "no",
         m3_same ? "yes" : "no");
  if (!alt_m1 || !alt_m2a || !alt_m2b || !alt_m4 || !alt_m5 || !alt_m6 || !m3_same) {
    printf("DUALCHAIN SETUP_BAD alt/反累加前提不成立 ⇒ 本用例失去可证伪性，必须换操作数\n");
  }

  /* ======================= M1：自别名 RAW/WAR 链 ======================= */
  init_v10();
  func_m1(DC_N_FUNC);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M1, scr), DC_CHECKLEN_M1, wantbuf, sizeof(wantbuf));
  print_func("M1", DC_CHECKLEN_M1, bad, wantbuf, alt_m1);
  if (bad || !alt_m1) fails++;

  init_v10();
  func_m1(DC_N_ALT);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M1_alt, scr), DC_CHECKLEN_M1_alt, wantbuf, sizeof(wantbuf));
  print_func("M1_alt", DC_CHECKLEN_M1_alt, bad, wantbuf, alt_m1);
  if (bad) fails++;

  /* ================= M2：跨寄存器真 RAW 交替链 ================= */
  init_v10_v11();
  func_m2(DC_N_FUNC);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M2_v10, scr), DC_CHECKLEN_M2_v10, wantbuf, sizeof(wantbuf));
  print_func("M2_v10", DC_CHECKLEN_M2_v10, bad, wantbuf, alt_m2a);
  if (bad || !alt_m2a) fails++;
  dump16(got, 11); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M2_v11, scr), DC_CHECKLEN_M2_v11, wantbuf, sizeof(wantbuf));
  print_func("M2_v11", DC_CHECKLEN_M2_v11, bad, wantbuf, alt_m2b);
  if (bad || !alt_m2b) fails++;

  init_v10_v11();
  func_m2(DC_N_ALT2);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M2_v10_alt, scr), DC_CHECKLEN_M2_v10_alt, wantbuf, sizeof(wantbuf));
  print_func("M2_v10_alt", DC_CHECKLEN_M2_v10_alt, bad, wantbuf, alt_m2a);
  if (bad) fails++;
  dump16(got, 11); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M2_v11_alt, scr), DC_CHECKLEN_M2_v11_alt, wantbuf, sizeof(wantbuf));
  print_func("M2_v11_alt", DC_CHECKLEN_M2_v11_alt, bad, wantbuf, alt_m2b);
  if (bad) fails++;

  /* ============ M3 / M3b：无依赖（常量源、固定 vd）—— vdRen 判别 ============ */
  init_v10();                       /* v3 的初值不重要，故意留成上一手结果 */
  func_m3(DC_N_FUNC);
  dump16(got, 3); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M3, scr), DC_CHECKLEN_M3, wantbuf, sizeof(wantbuf));
  print_func("M3", DC_CHECKLEN_M3, bad, wantbuf, 1);
  if (bad) fails++;

  prefill_v3();                     /* 旧 vd 预填 0xAB×16，结果必须不变 */
  func_m3(DC_N_FUNC);
  dump16(got, 3); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M3b, scr), DC_CHECKLEN_M3b, wantbuf, sizeof(wantbuf));
  print_func("M3b", DC_CHECKLEN_M3b, bad, wantbuf, 1);
  if (bad) fails++;

  /* ==================== M4：vmacc 自别名对照组 ==================== */
  init_v10();
  func_m4(DC_N_FUNC);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M4, scr), DC_CHECKLEN_M4, wantbuf, sizeof(wantbuf));
  print_func("M4", DC_CHECKLEN_M4, bad, wantbuf, alt_m4);
  if (bad || !alt_m4) fails++;

  init_v10();
  func_m4(DC_N_ALT);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M4_alt, scr), DC_CHECKLEN_M4_alt, wantbuf, sizeof(wantbuf));
  print_func("M4_alt", DC_CHECKLEN_M4_alt, bad, wantbuf, alt_m4);
  if (bad) fails++;

  /* ============ M5：vmacc 仅 old_vd 串行（vs2 常量）对照组 ============ */
  init_v10();
  func_m5(DC_N_FUNC);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M5, scr), DC_CHECKLEN_M5, wantbuf, sizeof(wantbuf));
  print_func("M5", DC_CHECKLEN_M5, bad, wantbuf, alt_m5);
  if (bad || !alt_m5) fails++;

  init_v10();
  func_m5(DC_N_ALT);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M5_alt, scr), DC_CHECKLEN_M5_alt, wantbuf, sizeof(wantbuf));
  print_func("M5_alt", DC_CHECKLEN_M5_alt, bad, wantbuf, alt_m5);
  if (bad) fails++;

  /* ==================== M6：vadd ALU 参照链 ==================== */
  init_v10();
  func_m6(DC_N_FUNC);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M6, scr), DC_CHECKLEN_M6, wantbuf, sizeof(wantbuf));
  print_func("M6", DC_CHECKLEN_M6, bad, wantbuf, alt_m6);
  if (bad || !alt_m6) fails++;

  init_v10();
  func_m6(DC_N_ALT);
  dump16(got, 10); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M6_alt, scr), DC_CHECKLEN_M6_alt, wantbuf, sizeof(wantbuf));
  print_func("M6_alt", DC_CHECKLEN_M6_alt, bad, wantbuf, alt_m6);
  if (bad) fails++;

  /* ==================== M7：vadd 无依赖地板 ==================== */
  set_vl8();
  func_m7(1);
  dump16(got, 3); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M7, scr), DC_CHECKLEN_M7, wantbuf, sizeof(wantbuf));
  print_func("M7", DC_CHECKLEN_M7, bad, wantbuf, 1);
  if (bad) fails++;

  /* ============ M8：vdot 无依赖、不同 vd（轮转 v8..v15） ============ */
  init_v8_v15();
  func_m8(DC_N_FUNC / 8);
  dump16(got, 8); set_vl8();
  bad = cmp_bytes(got, expect_of(DCW_M8, scr), DC_CHECKLEN_M8, wantbuf, sizeof(wantbuf));
  print_func("M8", DC_CHECKLEN_M8, bad, wantbuf, 1);
  if (bad) fails++;

#ifndef DC_G0
  /* =====================================================================
   * M9/M10 功能一步：链跑 1 步的结果必须等于单次 dot(a,b)，即金模型的 DCW_M3。
   * （完整 16 字节比对；不手抄常量。N 步的最终值不在本用例功能判据内——计时臂。）
   * ===================================================================== */
  init_v30_v31();
  chain_g44_vdot(1);
  dump16(got, 30); set_vl8();
  bad = cmp_bytes(got, DCW_M3, DC_CHECKLEN_M3, wantbuf, sizeof(wantbuf));
  printf("DUALCHAIN_G44 M9 one_step bytes_bad=%d want=[%s]\n", bad, wantbuf);
  if (bad) fails++;

  init_v30_v31();
  chain_g44_rvv(1);
  dump16(got, 30); set_vl8();
  bad = cmp_bytes(got, DCW_M3, DC_CHECKLEN_M3, wantbuf, sizeof(wantbuf));
  printf("DUALCHAIN_G44 M10 one_step bytes_bad=%d want=[%s]\n", bad, wantbuf);
  if (bad) fails++;

  /* =====================================================================
   * 计时：主指标 L_<链>（差分，解出每链步间隔），附报每 rep 固定开销 O
   * ===================================================================== */
  dep_report("M1", bulk_m1_lo, bulk_m1_hi, init_v10, 1);
  dep_report("M2", bulk_m2_lo, bulk_m2_hi, init_v10_v11, 2);
  dep_report("M3", bulk_m3_lo, bulk_m3_hi, init_v10, 1);
  dep_report("M4", bulk_m4_lo, bulk_m4_hi, init_v10, 1);
  dep_report("M5", bulk_m5_lo, bulk_m5_hi, init_v10, 1);
  dep_report("M6", bulk_m6_lo, bulk_m6_hi, init_v10, 1);
  dep_report("M7", bulk_m7_lo, bulk_m7_hi, init_v10, 1);
  dep_report("M8", bulk_m8_lo, bulk_m8_hi, init_v8_v15, 8);

  /* 同口径对照三臂（外部公开材料口径：N=0/64/256/1024、3 重复、4 点 OLS 斜率、含循环开销） */
  g44_report("M9",  chain_g44_vdot, init_v30_v31);
  g44_report("M10", chain_g44_rvv,  init_v30_v31);
  g44_report("M11", chain_g44_ctrl, init_v30_v31);
#endif /* !DC_G0 */

#ifdef DC_G0
  /* G0 反例：上面的功能比对全部用翻转 1 bit 的期望 ⇒ 必判 MISMATCH。
     这里再显式打一条固定格式的 CASE 行，供 harness 用 grep -F 抓。 */
  {
    int gbad = 0;
    init_v10();
    func_m3(DC_N_FUNC);
    dump16(got, 3); set_vl8();
    gbad = cmp_bytes(got, expect_of(DCW_M3, scr), DC_CHECKLEN_M3, wantbuf, sizeof(wantbuf));
    printf("CASE vdot_dualchain_g0: %s bytes_bad=%d want=[%s]\n",
           gbad ? "MISMATCH" : "MATCH", gbad, wantbuf);
  }
#endif

  const int ok = enc_ok && vl_ok && (fails == 0);
  printf("DUALCHAIN verdict=%s enc=%s vl=%s func_fails=%d\n",
         ok ? "ALL_OK" : "HAS_FAIL", enc_ok ? "OK" : "MISMATCH", vl_ok ? "OK" : "MISMATCH", fails);
  return 0;   /* 判定在 verdict 串里；AM 里 return 非零也照样 GOOD TRAP（空绿风险见 ALGORITHM §3.1） */
}