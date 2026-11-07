// vdot_xcontam.c — R13「fireS1 误用 valid ⇒ 写回上一条指令数据」交叉污染专项用例
//
// 风险背景：R13 已落码、此前无专项用例（本文件即该专项）；
// 契约：design/CODING-STD.md §3.4（`fireS1` 必须由 X15 显式导出，
//       新归约模块的输出寄存使能必须是 `RegEnable(reduction, io.fireS1)`，禁止用 `valid`）；
// 依据：design/ARCHITECTURE.md §8 R13 / §2.2 第 7 条；拍对齐检查条目见 §8:192。
//
// 为什么「同一个 vd + vdot/vmacc 混排」是触发面：
//   vdot.vv  是全写指令：vd[31:0] = sext32(S)，vd[127:32] = 0，**旧 vd 不是语义输入**
//            （SPEC §1.1「旧 vd：不读、不累加」）；
//   vmacc.vv 是读改写指令：vd[i] = old_vd[i] + vs1[i]*vs2[i]，SEW=8 逐字节模 2^8 回绕。
//   两者写同一个 vd 时写语义互斥：一个清零高 96 位，一个保留并累加旧值。若输出寄存器的
//   使能误用 `valid`（而不是 `fireS1`），使能会早/晚一拍，把**上一条** vimac 指令的结果
//   写回 vd ⇒ 后一条 vdot 写出前一条 vdot/vmacc 的位型。
//
// 本用例的可证伪性前提（关键，改动数组前必读）：
//   每一步的期望位型必须**两两不同**，否则「写回上一条」与「写回本条」在数值上重合，
//   用例会静默通过（空绿）。本文件用两组点积操作数得到 S1=-948、S2=-272（w32 分别为
//   0xFFFFFC4C / 0xFFFFFEF0，高 96 位同为 0），vmacc 终值又是 16 字节逐 lane 位型，
//   三者互不相同；main 开头还有 `want1 != want2` 的 SETUP 守卫。
//
// 六段（全部 SEW=8、LMUL=1、vl=16=VLMAX；共享同一 vd = v3）：
//   b0  vdot(v1,v2)→vmacc(v6,v7)→vdot(v4,v5)  **0 bubble 背靠背**（R13 本命序列）
//       旧 vd **显式预填 0xAB×16**（与 b3/b4 同口径）：b0 的 vmacc 是序列里第一条读旧 vd 的
//       指令，若不预填，它的输入就是进入 b0 时 v3 的**残余值**（不可控、随上一块/上一次运行变化），
//       「写回上一条」的故障位型也随之漂移 ⇒ 该段可能静默通过（空绿）。其余块不需要预填：
//       b1/b2/b2b 的首条指令是 vdot（全写 vd，旧 vd 非输入），b3/b4 已自带预填。
//       断言：终值 = S2 的 vdot 位型，且 vd[127:32] 恒零
//   b1  同上三步，但每步之后插入读回（= 含 bubble 变体，ARCHITECTURE §8:192 的「含 bubble」）
//       断言：① S1 位型 + 高 96 位零 ② vmacc 的 16 字节（旧 vd = S1 的 4 字节 + 12 字节 0）
//             ③ S2 位型 + 高 96 位零
//   b2  vdot(S1)→vdot(S2) 连发对照：断言终值 = S2（若第二条写了第一条的数据 ⇒ 命中 S1）
//   b2b vdot(S2)→vdot(S1) 连发对照（反向顺序）：断言终值 = S1
//   b3  vmacc→vdot→vmacc（vmacc 终值）：断言 16 字节 = (S1 的 4 字节 + 12 字节 0) + 逐 lane 积
//       —— 若第二条 vmacc 读到的旧 vd 是**第一条** vmacc 的结果（0xAB+积），lane 4..15 必错
//   b4  vmacc→vdot（vdot 终值）：旧 vd 预填 0xAB×16，断言 vdot 输出 = S2 位型 + 高 96 位零
//       —— 证明 vdot 不读、不累加旧 vd（SPEC §1.1）
//
// 期望值语义（与 design/verify/vdot_model.py 逐位同构；两种累加语义严禁混用）：
//   vdot.vv   S = Σ_{i=0..7} sext8(vs1[i]) × sext8(vs2[i])（int64 逐项累加 = 算法 B），
//             vd[31:0] = sext32(S)，vd[127:32] = 0；取 vs1/vs2 低 64 位 lane 0–7，高 64 位不参与。
//   vmacc.vv  逐元素 MAC：vd[i] = old_vd[i] + vs1[i] × vs2[i]，SEW=8 ⇒ 每个 lane 独立按模 2^8
//             回绕。它不是「点积和加到标量」（那是 vdot 的语义）。
//   预填 `vmv.v.x v3, rs` 在 SEW=8 下只把 rs 的低 8 位 splat 到各 lane（vl=16 ⇒ 16 lane 全写）。
//
// 高 96 位断言（SPEC §1.2 第 2 条）：vdot 写回后在 e32/vl=4 视图下 `vse32.v` 存回 4 个 32 位
// 元素，元素 1..3 = vd[127:32] 必须全 0；每块独立缓冲 + 0xFFFFFFFF 哨兵预填，防止「漏发
// vse32.v ⇒ 读到 BSS 零初值」的旁路（同 vdot_mix.c:49-59 的哨兵预填做法）。
//
// 本用例**不进** design/verify/cases/manifest.tsv（该文件 sha256 冻结 a90d1071…、30 行；
// 口径同 perf_base_chain 的「独立测量」）。因此
// core-package/scripts/20-run-difftest.sh 的 selfcheck_pattern 里没有本用例的类映射；
// 独立跑时以本文件自己打印的 `XCONTAM verdict=ALL_OK fails=0` 作为自检串。
//
// 复现（单例路径，不触发 build_all.sh 的整批重建；构建参数与 build_cases.sh:36-37 同一套）：
//   AM_HOME=<nexus-am> PATH=<riscv64-unknown-elf-*>:$PATH
//   d=$AM_HOME/apps/vdot_xcontam; mkdir -p $d; cp vdot_xcontam.c $d/main.c
//   printf 'NAME = vdot_xcontam\nSRCS = main.c\ninclude $(AM_HOME)/Makefile.app\n' > $d/Makefile
//   make -s -C $d AM_HOME=$AM_HOME ARCH=riscv64-xs CROSS_COMPILE=riscv64-unknown-elf-
//        MARCH=rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt HOST_IP=0.0.0.0 image
//   cp $d/build/vdot_xcontam-riscv64-xs.bin design/verify/cases/vdot_xcontam.bin
//   期望值独立复算：python3 -I design/verify/cases/xcontam_crosscheck.py
//   difftest 侧（昆山）：$EMU --diff $REF_SO -i vdot_xcontam.bin --max-instr=200000000
//   （上面续行去掉反斜杠：C 注释里行尾 '\' 会触发 -Werror=comment，AM 用 -Werror 编译）
//
// 依据：SPEC §1.1/§1.2/§2.1；CODING-STD §3.4；ARCHITECTURE §8 R13、§8:192；
//       vdot_model.py 的 dot_product()/writeback()；编码三元组同 SPEC §2.1 示例
//       `vdot.vv v3, v2, v1` = 0x3A20A1D7。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// vdot.vv：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111 ⇒ vd=3/vs1=1/vs2=2 时
//   0x3A20A1D7（SPEC §2.1 机器码示例，位域展开见 SPEC §2.2）。
//   **宏实参顺序是 (vd, vs1, vs2)，对应位域 vs1=[19:15]、vs2=[24:20]；而汇编助记符打印顺序
//   是 `vdot.vv vd, vs2, vs1`**（同 vdot_mix.c:28-31 的约定）。两者不要混读。
#define VDOT_ENC(vd, vs1, vs2)                                                  \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)
// vmacc.vv vd, vs1, vs2（RVV 标准助记符顺序，与本宏实参顺序一致）：funct6=101101, vm=1,
//   funct3=**010**(OPMVV), opcode=1010111。基码（全 0 寄存器）= 0xB6002057；
//   `vmacc.vv v4, v1, v2` = 0xB620A257（llvm-mc 实测）。funct3 必须是 010：写成 001 会落进
//   OPFVV 命名空间（同 funct6 的 0xB6201257 实测反汇编为 vfnmacc.vv，浮点指令），整条用例就
//   不是 vmacc 了。（同 vdot_mix.c:32-38）
//   本文件用到的 `vmacc.vv v3, v6, v7` = 0xB67321D7，已由 objdump -M rv64gcv 反汇编确认为
//   `vmacc.vv v3,v6,v7`（见验收记录）。
#define VMACC_ENC(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x2Du << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

// 两组点积操作数：lane 0..7 参与点积，lane 8..15 是**故意非零的干扰字节**（SPEC §1.1：
// 高 64 位不参与）。若实现误把 lane 8..15 也算进点积，S 会明显偏离。
static volatile int8_t d1a[16] = {3,   -5,  7,   -9,  11,  -13, 17,  -19,
                                  21,  -23, 25,  -27, 29,  -31, 33,  -35};
static volatile int8_t d1b[16] = {-2,  4,   -6,  8,   -10, 12,  -14, 16,
                                  -18, 20,  -22, 24,  -26, 28,  -30, 32};
// d2 取值覆盖 int8 极值对（-128 × -128 = 16384）与 -128 × 127，用来同时压 19 位累加器边界。
static volatile int8_t d2a[16] = {-128, -128, 0,   5,   -7,  9,   -11, 13,
                                  15,   -17,  19,  -21, 23,  -25, 27,  -29};
static volatile int8_t d2b[16] = {-128, 127,  3,   -4,  6,   -8,  10,  -12,
                                  14,   -16,  18,  -20, 22,  -24, 26,  -28};
// vmacc 的 16 lane 乘数（vl=16 ⇒ 16 个 lane 全部参与逐元素 MAC）
static volatile int8_t mp[16] = {2,   -3,  5,   -7,  11,  -13, 17,  -19,
                                 23,  -29, 31,  -37, 41,  -43, 47,  -53};
static volatile int8_t mq[16] = {-4,  6,   -8,  10,  -12, 14,  -16, 18,
                                 -20, 22,  -24, 26,  -28, 30,  -32, 34};

#define PREFILL 0xABu   // SEW=8 ⇒ 每个 lane 旧值 = 0xAB

// 每块独立的读回缓冲（不共用：共用会让断言读到上一块残留的实测值，见 vdot_mix.c:49-55）
static volatile uint8_t macc_b1[16];
static volatile uint8_t macc_b3[16];
static volatile uint32_t hi_b0[4] __attribute__((aligned(16)));
static volatile uint32_t hi_b1a[4] __attribute__((aligned(16)));
static volatile uint32_t hi_b1b[4] __attribute__((aligned(16)));
static volatile uint32_t hi_b2[4] __attribute__((aligned(16)));
static volatile uint32_t hi_b2b[4] __attribute__((aligned(16)));
static volatile uint32_t hi_b4[4] __attribute__((aligned(16)));

// ---- 期望值算法（纯 C，逐位对齐 SPEC §1.1 与 vdot_model.py；本段可单独抽取做宿主机自检）----

// 算法 B：逐项 int64 累加，只取 lane 0..7（与 vdot_model.dot_product() 的 lanes_int8() 同口径）
static long long dot8(const volatile int8_t *a, const volatile int8_t *b) {
  long long s = 0;
  for (int i = 0; i < 8; i++) s += (long long)a[i] * (long long)b[i];
  return s;
}

// vdot 的 vd[31:0] = sext32(S) 的位型（高 96 位恒零，单独由 cmp_hi_zero 断言）
static uint32_t w32(long long s) { return (uint32_t)(int32_t)s; }

// vdot 写回后的旧 vd 16 字节：低 4 字节 = S 小端，高 12 字节 = 0（SPEC §1.1）
static void old_from_vdot(uint32_t s32, uint8_t old16[16]) {
  for (int i = 0; i < 16; i++) old16[i] = 0;
  for (int i = 0; i < 4; i++) old16[i] = (uint8_t)((s32 >> (8 * i)) & 0xFFu);
}

// vmacc 逐 lane 期望：exp[i] = (old16[i] + mp[i]*mq[i]) mod 2^8。
// 用无符号 32 位相加再截断到 8 位等价于模 2^8（与积的符号无关，同 vdot_mix.c:84-90）。
static void expect_vmacc16(const uint8_t old16[16], const volatile int8_t *x,
                           const volatile int8_t *y, uint8_t exp[16]) {
  for (int i = 0; i < 16; i++) {
    int32_t prod = (int32_t)x[i] * (int32_t)y[i];
    exp[i] = (uint8_t)((uint32_t)old16[i] + (uint32_t)prod);
  }
}

static int cmp_bytes16(const volatile uint8_t got[16], const uint8_t exp[16]) {
  int bad = 0;
  for (int i = 0; i < 16; i++)
    if (got[i] != exp[i]) bad++;
  return bad;
}

// 高 96 位断言：元素 1..3 是 vd[127:32]，必须全 0（元素 0 是 S，不在此检查）
static int cmp_hi_zero(const volatile uint32_t w[4]) {
  return (w[1] != 0u) + (w[2] != 0u) + (w[3] != 0u);
}

#define HI_SENTINEL 0xFFFFFFFFu
static void poison_hi(volatile uint32_t w[4]) {
  for (int i = 0; i < 4; i++) w[i] = HI_SENTINEL;
}

static void show_bytes16(const char *tag, const volatile uint8_t got[16], const uint8_t exp[16]) {
  printf("%s got=[", tag);
  for (int i = 0; i < 16; i++) printf("%02X%s", got[i], (i == 15) ? "" : " ");
  printf("] exp=[");
  for (int i = 0; i < 16; i++) printf("%02X%s", exp[i], (i == 15) ? "" : " ");
  printf("]\n");
}

// ---- 以上为期望值算法 ----

// 向量指令需要 mstatus.VS != OFF；AM 的 start.S 只开 FS 不开 VS（vdot_rand.c:33-34 同一 prologue）
static void enable_vs(void) {
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
}

// `.4byte` 是 4 字节指令，必须 4 字节对齐：整段禁用压缩指令（norvc），否则 li/la 会被压成
// 2 字节，使后面的 `.4byte` 落在 2 mod 4 上（取指不对齐陷入）。（同 vdot_mix.c:127-131）
#define ASM_HEAD ".balign 4\n\t.option push\n\t.option norvc\n\t"
#define ASM_TAIL ".option pop\n\t"

// 装载全部操作数（vl=16=VLMAX，e8/m1，ta/ma ⇒ 16 个字节 lane 全写）
// v1=d1a v2=d1b（S1 的操作数）、v4=d2a v5=d2b（S2 的操作数）、v6=mp v7=mq（vmacc 乘数）
#define LOAD_OPS                                                              \
  "li t1, 16\n\t"                                                             \
  "vsetvli zero, t1, e8, m1, ta, ma\n\t"                                      \
  "la a2, d1a\n\t"                                                            \
  "vle8.v v1, (a2)\n\t"                                                       \
  "la a3, d1b\n\t"                                                            \
  "vle8.v v2, (a3)\n\t"                                                       \
  "la a2, d2a\n\t"                                                            \
  "vle8.v v4, (a2)\n\t"                                                       \
  "la a3, d2b\n\t"                                                            \
  "vle8.v v5, (a3)\n\t"                                                       \
  "la a2, mp\n\t"                                                             \
  "vle8.v v6, (a2)\n\t"                                                       \
  "la a3, mq\n\t"                                                             \
  "vle8.v v7, (a3)\n\t"

#define SET_E8  "li t1, 16\n\t" "vsetvli zero, t1, e8, m1, ta, ma\n\t"
#define SET_E32 "li t2, 4\n\t"  "vsetvli zero, t2, e32, m1, tu, mu\n\t"

int main(void) {
  enable_vs();
  int fails = 0;

  long long s1 = dot8(d1a, d1b);
  long long s2 = dot8(d2a, d2b);
  uint32_t want1 = w32(s1), want2 = w32(s2);
  printf("XCONTAM SETUP S1=%lld w1=0x%08X S2=%lld w2=0x%08X\n", s1, want1, s2, want2);
  // SETUP 守卫：若两组操作数碰巧给出相同 w32，「写回上一条」与「写回本条」就不可分辨
  if (want1 == want2) {
    printf("XCONTAM SETUP_BAD w1==w2=0x%08X（序列失去可证伪性，必须换操作数）\n", want1);
    fails++;
  }

  // ---- b0：vdot→vmacc→vdot，0 bubble 背靠背，共享 v3（R13 本命序列）----
  // 正确语义：v3 依次被 (1) S1 位型 (2) 逐字节 MAC (3) S2 位型（hi96 清零）覆盖；
  //           终值必须是 S2，既不是 S1（前一条 vdot 的数据），也不是 vmacc 的字节型。
  // 预填口径（2026-11-06 复核更正）：下面这句 `vmv.v.x v3, %[pf]` 是**与 b3/b4 统一口径**、
  //           消除「进入 b0 时 v3 残余值不可控」的歧义；它**不是**可证伪性的前提 —— b0 首条就是
  //           vdot（全写 vd、不读旧 vd），故「写回上一条」的故障值恒为 vdot(S1)，与预填无关
  //           （实测把预填换成 0 / 0xF8 10 27 … / 删掉，b0 仍可分辨）。
  {
    uint32_t got = 0;
    uint32_t pf = PREFILL;
    poison_hi(hi_b0);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        "vmv.v.x v3, %[pf]\n\t"          // 旧 vd 预填 0xAB×16（必须在 vl=16 的 vsetvli 之后）
        ".4byte %[vdA]\n\t"              // vdot v3, v1, v2  ⇒ S1
        ".4byte %[vm]\n\t"               // vmacc v3, v6, v7 ⇒ v3[i] = old_v3[i] + mp[i]*mq[i]
        ".4byte %[vdB]\n\t"              // vdot v3, v4, v5  ⇒ S2（hi96 清零）
        SET_E32
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_b0\n\t"
        "vse32.v v3, (a5)\n\t"
        ASM_TAIL
        : "=r"(got)
        : [pf] "r"(pf),
          [vdA] "i"(VDOT_ENC(3, 1, 2)), [vm] "i"(VMACC_ENC(3, 6, 7)),
          [vdB] "i"(VDOT_ENC(3, 4, 5))
        : "t1", "t2", "a2", "a3", "a5", "memory");
    int hi = cmp_hi_zero(hi_b0);
    int ok = (got == want2) && (hi == 0);
    printf("XCONTAM b0 vdot->vmacc->vdot got=0x%08X want=0x%08X hi96_bad=%d %s\n",
           got, want2, hi, ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }

  // ---- b1：同三步，但每步后插入读回（= 含 bubble 变体；ARCHITECTURE §8:192 要求含 bubble）----
  // 逐步断言三个中间态，这是「写回上一条」最直接的可观测点。
  {
    uint32_t g1 = 0, g3 = 0;
    uint8_t old16[16], exp2[16];
    old_from_vdot(want1, old16);
    expect_vmacc16(old16, mp, mq, exp2);
    poison_hi(hi_b1a);
    poison_hi(hi_b1b);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        ".4byte %[vdA]\n\t"              // ① vdot ⇒ S1
        SET_E32
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_b1a\n\t"
        "vse32.v v3, (a5)\n\t"
        SET_E8
        ".4byte %[vm]\n\t"               // ② vmacc，旧 vd = ① 的写回值
        "li t2, 16\n\t"
        "vsetvli zero, t2, e8, m1, tu, mu\n\t"
        "la a4, macc_b1\n\t"
        "vse8.v v3, (a4)\n\t"
        SET_E8
        ".4byte %[vdB]\n\t"              // ③ vdot ⇒ S2
        SET_E32
        "vmv.x.s %1, v3\n\t"
        "la a5, hi_b1b\n\t"
        "vse32.v v3, (a5)\n\t"
        ASM_TAIL
        : "=r"(g1), "=r"(g3)
        : [vdA] "i"(VDOT_ENC(3, 1, 2)), [vm] "i"(VMACC_ENC(3, 6, 7)),
          [vdB] "i"(VDOT_ENC(3, 4, 5))
        : "t1", "t2", "a2", "a3", "a4", "a5", "memory");
    int hi1 = cmp_hi_zero(hi_b1a);
    int hi3 = cmp_hi_zero(hi_b1b);
    int bad2 = cmp_bytes16(macc_b1, exp2);
    int ok = (g1 == want1) && (hi1 == 0) && (bad2 == 0) && (g3 == want2) && (hi3 == 0);
    printf("XCONTAM b1 step1 got=0x%08X want=0x%08X hi96_bad=%d\n", g1, want1, hi1);
    printf("XCONTAM b1 step2 bytes_bad=%d\n", bad2);
    printf("XCONTAM b1 step3 got=0x%08X want=0x%08X hi96_bad=%d %s\n",
           g3, want2, hi3, ok ? "OK" : "FAIL");
    show_bytes16("XCONTAM b1 step2", macc_b1, exp2);
    if (!ok) fails++;
  }

  // ---- b2：vdot(S1)→vdot(S2) 连发对照（0 bubble）----
  // 若第二条 vdot 写回的是第一条的数据（fireS1 误用 valid 的典型症状），终值会是 S1。
  {
    uint32_t got = 0;
    poison_hi(hi_b2);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        ".4byte %[vdA]\n\t"              // vdot ⇒ S1
        ".4byte %[vdB]\n\t"              // vdot ⇒ S2（必须覆盖，hi96 清零）
        SET_E32
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_b2\n\t"
        "vse32.v v3, (a5)\n\t"
        ASM_TAIL
        : "=r"(got)
        : [vdA] "i"(VDOT_ENC(3, 1, 2)), [vdB] "i"(VDOT_ENC(3, 4, 5))
        : "t1", "t2", "a2", "a3", "a5", "memory");
    int hi = cmp_hi_zero(hi_b2);
    int ok = (got == want2) && (hi == 0);
    printf("XCONTAM b2 vdot->vdot got=0x%08X want=0x%08X hi96_bad=%d %s\n",
           got, want2, hi, ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }

  // ---- b2b：vdot(S2)→vdot(S1) 反向顺序（防止「总是写回较早那条」的单向偶然通过）----
  {
    uint32_t got = 0;
    poison_hi(hi_b2b);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        ".4byte %[vdB]\n\t"              // vdot ⇒ S2
        ".4byte %[vdA]\n\t"              // vdot ⇒ S1
        SET_E32
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_b2b\n\t"
        "vse32.v v3, (a5)\n\t"
        ASM_TAIL
        : "=r"(got)
        : [vdA] "i"(VDOT_ENC(3, 1, 2)), [vdB] "i"(VDOT_ENC(3, 4, 5))
        : "t1", "t2", "a2", "a3", "a5", "memory");
    int hi = cmp_hi_zero(hi_b2b);
    int ok = (got == want1) && (hi == 0);
    printf("XCONTAM b2b vdot(S2)->vdot(S1) got=0x%08X want=0x%08X hi96_bad=%d %s\n",
           got, want1, hi, ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }

  // ---- b3：vmacc→vdot→vmacc（vmacc 终值）----
  // 第二条 vmacc 的旧 vd 必须是**中间那条 vdot**的输出（S1 的 4 字节 + 12 字节 0）。
  // 若它读到的是第一条 vmacc 的结果（0xAB + 积），lane 4..15 会整体偏离 ⇒ 本块必红。
  {
    uint8_t old16[16], exp3[16];
    uint32_t pf = PREFILL;
    old_from_vdot(want1, old16);
    expect_vmacc16(old16, mp, mq, exp3);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        "vmv.v.x v3, %[pf]\n\t"          // 旧 vd 预填 0xAB×16（必须在 vl=16 的 vsetvli 之后）
        ".4byte %[vm]\n\t"               // vmacc#1 ⇒ 0xAB + 积
        ".4byte %[vdA]\n\t"              // vdot ⇒ S1（忽略旧 vd，hi96 清零）
        ".4byte %[vm]\n\t"               // vmacc#2 ⇒ S1 的 4 字节 + 12 字节 0 + 积
        "li t2, 16\n\t"
        "vsetvli zero, t2, e8, m1, tu, mu\n\t"
        "la a4, macc_b3\n\t"
        "vse8.v v3, (a4)\n\t"
        ASM_TAIL
        :
        : [pf] "r"(pf), [vm] "i"(VMACC_ENC(3, 6, 7)), [vdA] "i"(VDOT_ENC(3, 1, 2))
        : "t1", "t2", "a2", "a3", "a4", "memory");
    int bad = cmp_bytes16(macc_b3, exp3);
    printf("XCONTAM b3 vmacc->vdot->vmacc bytes_bad=%d %s\n", bad, (bad == 0) ? "OK" : "FAIL");
    show_bytes16("XCONTAM b3", macc_b3, exp3);
    if (bad != 0) fails++;
  }

  // ---- b4：vmacc→vdot（vdot 终值）----
  // 旧 vd 预填 0xAB×16 后紧接 vdot：vdot 必须完全忽略旧 vd 并清零高 96 位（SPEC §1.1）。
  // 若 fireS1 使能错拍把上一条 vmacc 的数据写回，终值会是 0xAB+积 的字节型 ⇒ 必红。
  {
    uint32_t got = 0;
    uint32_t pf = PREFILL;
    poison_hi(hi_b4);
    asm volatile(
        ASM_HEAD
        LOAD_OPS
        "vmv.v.x v3, %[pf]\n\t"
        ".4byte %[vm]\n\t"               // vmacc ⇒ 0xAB + 积
        ".4byte %[vdB]\n\t"              // vdot ⇒ S2（覆盖，hi96 清零）
        SET_E32
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_b4\n\t"
        "vse32.v v3, (a5)\n\t"
        ASM_TAIL
        : "=r"(got)
        : [pf] "r"(pf), [vm] "i"(VMACC_ENC(3, 6, 7)), [vdB] "i"(VDOT_ENC(3, 4, 5))
        : "t1", "t2", "a2", "a3", "a5", "memory");
    int hi = cmp_hi_zero(hi_b4);
    int ok = (got == want2) && (hi == 0);
    printf("XCONTAM b4 vmacc->vdot got=0x%08X want=0x%08X hi96_bad=%d %s\n",
           got, want2, hi, ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }

  // 判据串写成字面量：独立跑（不经 20-run-difftest 的 selfcheck_pattern）时以本行取证；
  // 也便于 grep -c 'XCONTAM verdict=ALL_OK' 直接在源上取证。
  if (fails == 0) {
    printf("XCONTAM verdict=ALL_OK fails=0\n");
  } else {
    printf("XCONTAM verdict=HAS_FAIL fails=%d\n", fails);
  }
  return fails == 0 ? 0 : 1;
}
