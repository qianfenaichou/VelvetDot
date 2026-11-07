// vdot_mix.c — R13 交叉污染防护专项（design/ARCHITECTURE.md §2.2 第 7 条 / §5.3）
// 最小可证伪序列：vdot(A) @v3, vmacc(M) @v4, vdot(C) @v6, vdot(D) @v7（0 bubble 背靠背）
// 三个变体：① 0 bubble 四连发 ② 1 bubble（vdot, nop, vmacc, vdot） ③ 2 bubble（vdot, nop, nop, vmacc）
// 目的：
//   ① 验证 tap 无 opcode、每条 vimac 都 latch 时，输出级 Mux(outIsVdot) 正确屏蔽非 vdot 结果
//   ② 只有第 4 条是 vdot 时，选路用 inCtrl 的变异（M1）才必然写错 vmacc 结果 ⇒ 本用例是 M1 的确定性杀手
//   ③ vmacc 结果 = 旧 v4 + 逐元素积，验证 vdot 的 R 寄存器不污染 vmacc 写回
//
// 期望值语义（逐条对齐 SPEC §1.1；两种累加语义严禁混用）：
//   vdot.vv   S = Σ_{i=0..7} sext8(av[i]) × sext8(bv[i])（int64 逐项累加 = 算法 B），
//             vd[31:0] = sext32(S)，vd[127:32] = 0；与 vl 无关（SPEC §1.1）。
//   vmacc.vv  **逐元素 MAC**：vd[i] = old_vd[i] + vs1[i] × vs2[i]；SEW=8 ⇒ 每个 lane 独立按
//             模 2^8 回绕。它不是"点积和加到标量"（那是 vdot 的语义）：
//             逐字节结果与标量和毫无关系，期望值必须逐 lane 算。
//   预填       `vmv.v.x v4, rs` 在 SEW=8 下只把 rs 的**低 8 位** splat 到各 lane；
//             且预填必须写在合法 vsetvli（vl≥1）之后——写在 vl=0 时是空操作，v4 不会被预填。
// 每个测试块的指令序列不同（bubble 数、vdot 条数都不同），期望值一律由**本块自己的预填值**
// 独立计算，禁止跨块复用上一块的结果。
// 高 96 位断言（SPEC §1.2 第 2 条「每个用例必须断言高 96 位恒零」）：
//   vdot 写回后立刻在 e32/vl=4 视图下 `vse32.v` 把 vd 的 4 个 32 位元素存回内存；
//   元素 0 = S，元素 1..3 = vd[127:32] 必须全 0。本用例对每个块写入的 v3/v6/v7 全查。
// 依据：SPEC §1.1/§1.2；wrapper/VIMacU.scala:158-160（outIsVdot 输出级选路）、:165（高 96 位恒零断言）；
//       VIMac64b.scala:125（isMacc 时累加 oldVd）；VdotReduce.scala:44（每条 vimac 都 latch）
#include <am.h>
#include <klib.h>
#include <stdint.h>

// vdot.vv vd, vs1, vs2：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111 ⇒ 0x3A20A1D7
#define VDOT_ENC(vd, vs1, vs2)                                                  \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)
// vmacc.vv vd, vs1, vs2：funct6=101101, vm=1, funct3=**010**(OPMVV), opcode=1010111
//   基码（vd=vs1=vs2=0, vm=1）= 0xB6002057；vmacc.vv v4, v1, v2 = 0xB620A257（llvm-mc 实测）。
//   funct3 必须是 010：写成 001 会落进 OPFVV 命名空间（同 funct6 的 0xB6201257 实测反汇编为
//   vfnmacc.vv，浮点指令），整条用例就不是 vmacc 了。
#define VMACC_ENC(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x2Du << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

// 三个块各自的预填常量（互不相同，用来证明每块期望值是独立算的，不是复用上一块的）
#define PREFILL_BB4  0xDEADBEEFu   // SEW=8 ⇒ 每 lane 旧值 = 0xEF
#define PREFILL_BUB1 0x12345678u   // SEW=8 ⇒ 每 lane 旧值 = 0x78
#define PREFILL_BUB2 0xCAFEBABEu   // SEW=8 ⇒ 每 lane 旧值 = 0xBE

static volatile int8_t av[8] = {3, -5, 7, -9, 11, -13, 17, -19};
static volatile int8_t bv[8] = {-2, 4, -6, 8, -10, 12, -14, 16};
static volatile uint8_t macc_out[8];   // vmacc 结果：e8/vl=8 存回的 8 个字节

// 高 96 位断言用：e32/vl=4 存回 vd[0..3]（vd[0]=S，vd[1..3]=vd[127:32]）
// 每块用**自己的**缓冲：块②③只写自己那几条 vd 的槽位，若与块①共用一块，
// 断言读到的会是块①残留的实测值（块①写全 4 槽 ⇒ 残留恰为 0），高 96 位检查就被静默旁路。
// 独立缓冲后每块的 cmp_hi_zero 读到的必然是**本块**的 vse32.v 实测结果。
// 哨兵预填：只靠 BSS 零初值仍有旁路——若某条 vse32.v 漏发，缓冲保持 0，
// 断言照样判过。故每块执行前把 4 槽全填 0xFFFFFFFF；正常写回后 [1..3] 变 0，
// 漏发则残留哨兵 ⇒ cmp_hi_zero 非 0，高 96 位检查不再可被「漏 store」旁路。
#define HI_SENTINEL 0xFFFFFFFFu
static void poison_hi(volatile uint32_t w[4]) {
  for (int i = 0; i < 4; i++) w[i] = HI_SENTINEL;
}
static volatile uint32_t hi_bb4_v3[4] __attribute__((aligned(16)));
static volatile uint32_t hi_bb4_v6[4] __attribute__((aligned(16)));
static volatile uint32_t hi_bb4_v7[4] __attribute__((aligned(16)));
static volatile uint32_t hi_bub1_v3[4] __attribute__((aligned(16)));
static volatile uint32_t hi_bub1_v6[4] __attribute__((aligned(16)));
static volatile uint32_t hi_bub2_v3[4] __attribute__((aligned(16)));

// ---- 期望值算法（纯 C，逐位对齐 SPEC §1.1；本段可单独抽取做宿主机自检）----

// 算法 B：逐项 int64 累加（不经归约树）
static long long algo_b(void) {
  long long s = 0;
  for (int i = 0; i < 8; i++) s += (long long)av[i] * (long long)bv[i];
  return s;
}

// vdot 的 vd[31:0] = sext32(S) 的位型
static uint32_t want_vdot(void) { return (uint32_t)(algo_b() & 0xFFFFFFFFu); }

// `vmv.v.x v4, rs` 在 SEW=8 下每 lane 只取 rs 的低 8 位
static uint8_t macc_fill_byte(uint32_t prefill) { return (uint8_t)(prefill & 0xFFu); }

// vmacc.vv 逐元素期望：exp[i] = (old_vd[i] + av[i]*bv[i]) mod 2^8，old_vd[i] = prefill 的低字节。
// 用无符号 32 位相加再截断到 8 位等价于模 2^8（与积的符号无关）。
static void expect_vmacc(uint32_t prefill, uint8_t exp[8]) {
  uint32_t carry = (uint32_t)macc_fill_byte(prefill);
  for (int i = 0; i < 8; i++) {
    uint32_t prod = (uint32_t)((int32_t)av[i] * (int32_t)bv[i]);   // 16 位有符号积
    exp[i] = (uint8_t)(carry + prod);                              // 取低 8 位 = 模 2^8
  }
}

// 逐字节比对，返回不匹配的字节数（0 = 全等）
static int cmp_bytes(const volatile uint8_t got[8], const uint8_t exp[8]) {
  int bad = 0;
  for (int i = 0; i < 8; i++)
    if (got[i] != exp[i]) bad++;
  return bad;
}

// 高 96 位断言：元素 1..3 是 vd[127:32]，必须全 0（元素 0 是 S，不在此检查）
static int cmp_hi_zero(const volatile uint32_t w[4]) {
  return (w[1] != 0u) + (w[2] != 0u) + (w[3] != 0u);
}

// ---- 以上为期望值算法 ----

static void show_bytes(const char *tag, const volatile uint8_t got[8], const uint8_t exp[8]) {
  printf("%s got=[", tag);
  for (int i = 0; i < 8; i++) printf("%02X%s", got[i], (i == 7) ? "" : " ");
  printf("] exp=[");
  for (int i = 0; i < 8; i++) printf("%02X%s", exp[i], (i == 7) ? "" : " ");
  printf("]\n");
}

static void enable_vs(void) {
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
}

#define LOAD2_VL8                                                            \
  "li t1, 8\n\t"                                                             \
  "la a2, av\n\t"                                                            \
  "vsetvli zero, t1, e8, m1, ta, ma\n\t"                                     \
  "vle8.v v1, (a2)\n\t"                                                       \
  "la a3, bv\n\t"                                                             \
  "vle8.v v2, (a3)\n\t"

// `.4byte` 是 4 字节指令，必须 4 字节对齐：整段禁用压缩指令（norvc），
// 否则 `nop` 会被压缩成 2 字节 c.nop，使后面的 `.4byte` 落在 2 mod 4 上（取指不对齐陷入）。
// `.balign 4` 只对齐块首，块内全是 4 字节指令 ⇒ 中间的 nop 就是恰好 1 个 bubble。
#define ASM_HEAD ".balign 4\n\t.option push\n\t.option norvc\n\t"
#define ASM_TAIL ".option pop\n\t"

// 把 v4 的 8 个字节按 e8/vl=8 存回 macc_out（vmacc 的 SEW=8 结果只有 8 个 8 位 lane）
#define STORE_V4_BYTES                                                       \
  "li t2, 8\n\t"                                                             \
  "vsetvli zero, t2, e8, m1, tu, mu\n\t"                                     \
  "la a4, macc_out\n\t"                                                       \
  "vse8.v v4, (a4)\n\t"

int main(void) {
  enable_vs();
  int fails = 0;

  uint32_t want0 = want_vdot();
  printf("MIX S=%lld want32=0x%08X\n", algo_b(), want0);

  // ① 0-bubble 四连发：vdot v3 / vmacc v4 / vdot v6 / vdot v7
  //    v4 预填 0xDEADBEEF（SEW=8 ⇒ 每字节 0xEF），vmacc 期望 = 逐字节 (0xEF + av[i]*bv[i]) mod 256
  {
    uint32_t pf = PREFILL_BB4;
    uint32_t v3 = 0, v6 = 0, v7 = 0;
    uint32_t want = want_vdot();          // 本块自己的 vdot 期望
    uint8_t exp[8];
    expect_vmacc(pf, exp);                // 本块自己的 vmacc 期望（不引用其它块）
    poison_hi(hi_bb4_v3);                 // 哨兵预填：漏发 vse32.v 会被 cmp_hi_zero 抓到
    poison_hi(hi_bb4_v6);
    poison_hi(hi_bb4_v7);
    asm volatile(
        ASM_HEAD
        LOAD2_VL8
        "vmv.v.x v4, %[pf]\n\t"          // 预填：必须在上面 vl=8 的 vsetvli 之后，vl=0 时是空操作
        ".4byte %[vdot3]\n\t"            // vdot  v3 = S
        ".4byte %[vmacc4]\n\t"           // vmacc v4[i] = old_v4[i] + av[i]*bv[i]（8 位回绕）
        ".4byte %[vdot6]\n\t"            // vdot  v6 = S
        ".4byte %[vdot7]\n\t"            // vdot  v7 = S
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v3\n\t"
        "vmv.x.s %1, v6\n\t"
        "vmv.x.s %2, v7\n\t"
        // 高 96 位断言：同一 e32/vl=4 视图下存回 4 个 32 位元素（元素 1..3 必须为 0）
        "la a5, hi_bb4_v3\n\t"
        "vse32.v v3, (a5)\n\t"
        "la a5, hi_bb4_v6\n\t"
        "vse32.v v6, (a5)\n\t"
        "la a5, hi_bb4_v7\n\t"
        "vse32.v v7, (a5)\n\t"
        STORE_V4_BYTES
        ASM_TAIL
        : "=r"(v3), "=r"(v6), "=r"(v7)
        : [pf] "r"(pf),
          [vdot3] "i"(VDOT_ENC(3, 1, 2)),
          [vmacc4] "i"(VMACC_ENC(4, 1, 2)),
          [vdot6] "i"(VDOT_ENC(6, 1, 2)),
          [vdot7] "i"(VDOT_ENC(7, 1, 2))
        : "t1", "t2", "a2", "a3", "a4", "a5", "memory");
    int bad = cmp_bytes(macc_out, exp);
    int hi = cmp_hi_zero(hi_bb4_v3) + cmp_hi_zero(hi_bb4_v6) + cmp_hi_zero(hi_bb4_v7);
    int ok = (v3 == want) && (v6 == want) && (v7 == want) && (bad == 0) && (hi == 0);
    printf("MIX bb4 v3=0x%08X v6=0x%08X v7=0x%08X want=0x%08X hi96_bad=%d %s\n",
           v3, v6, v7, want, hi, ok ? "OK" : "FAIL");
    show_bytes("MIX bb4 v4", macc_out, exp);
    if (!ok) fails++;
  }

  // ② 1-bubble 变体：vdot, [bubble], vmacc, vdot —— 只覆盖对齐，不保证抓 M1
  //    v4 预填 0x12345678（每字节 0x78），期望独立算：逐字节 (0x78 + av[i]*bv[i]) mod 256
  {
    uint32_t pf = PREFILL_BUB1;
    uint32_t v3 = 0, v6 = 0;
    uint32_t want = want_vdot();
    uint8_t exp[8];
    expect_vmacc(pf, exp);
    poison_hi(hi_bub1_v3);                // 哨兵预填：漏发 vse32.v 会被 cmp_hi_zero 抓到
    poison_hi(hi_bub1_v6);
    asm volatile(
        ASM_HEAD
        LOAD2_VL8
        "vmv.v.x v4, %[pf]\n\t"
        ".4byte %[vdot3]\n\t"
        "nop\n\t"
        ".4byte %[vmacc4]\n\t"
        ".4byte %[vdot6]\n\t"
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v3\n\t"
        "vmv.x.s %1, v6\n\t"
        "la a5, hi_bub1_v3\n\t"
        "vse32.v v3, (a5)\n\t"
        "la a5, hi_bub1_v6\n\t"
        "vse32.v v6, (a5)\n\t"
        STORE_V4_BYTES
        ASM_TAIL
        : "=r"(v3), "=r"(v6)
        : [pf] "r"(pf),
          [vdot3] "i"(VDOT_ENC(3, 1, 2)),
          [vmacc4] "i"(VMACC_ENC(4, 1, 2)),
          [vdot6] "i"(VDOT_ENC(6, 1, 2))
        : "t1", "t2", "a2", "a3", "a4", "a5", "memory");
    int bad = cmp_bytes(macc_out, exp);
    int hi = cmp_hi_zero(hi_bub1_v3) + cmp_hi_zero(hi_bub1_v6);
    int ok = (v3 == want) && (v6 == want) && (bad == 0) && (hi == 0);
    printf("MIX bubble1 v3=0x%08X v6=0x%08X want=0x%08X hi96_bad=%d %s\n",
           v3, v6, want, hi, ok ? "OK" : "FAIL");
    show_bytes("MIX bubble1 v4", macc_out, exp);
    if (!ok) fails++;
  }

  // ③ 2-bubble 变体：vdot, [bubble], [bubble], vmacc
  //    v4 预填 0xCAFEBABE（每字节 0xBE），期望独立算：逐字节 (0xBE + av[i]*bv[i]) mod 256
  {
    uint32_t pf = PREFILL_BUB2;
    uint32_t v3 = 0;
    uint32_t want = want_vdot();
    uint8_t exp[8];
    expect_vmacc(pf, exp);
    poison_hi(hi_bub2_v3);                // 哨兵预填：漏发 vse32.v 会被 cmp_hi_zero 抓到
    asm volatile(
        ASM_HEAD
        LOAD2_VL8
        "vmv.v.x v4, %[pf]\n\t"
        ".4byte %[vdot3]\n\t"
        "nop\n\t"
        "nop\n\t"
        ".4byte %[vmacc4]\n\t"
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v3\n\t"
        "la a5, hi_bub2_v3\n\t"
        "vse32.v v3, (a5)\n\t"
        STORE_V4_BYTES
        ASM_TAIL
        : "=r"(v3)
        : [pf] "r"(pf),
          [vdot3] "i"(VDOT_ENC(3, 1, 2)),
          [vmacc4] "i"(VMACC_ENC(4, 1, 2))
        : "t1", "t2", "a2", "a3", "a4", "a5", "memory");
    int bad = cmp_bytes(macc_out, exp);
    int hi = cmp_hi_zero(hi_bub2_v3);
    int ok = (v3 == want) && (bad == 0) && (hi == 0);
    printf("MIX bubble2 v3=0x%08X want=0x%08X hi96_bad=%d %s\n",
           v3, want, hi, ok ? "OK" : "FAIL");
    show_bytes("MIX bubble2 v4", macc_out, exp);
    if (!ok) fails++;
  }

  // 判据串写成字面量（20-run-difftest.sh 的 selfcheck_pattern 按 'MIX verdict=ALL_OK' 匹配日志；
  // 也便于 grep -c 'MIX verdict=ALL_OK' 直接在源上取证）
  if (fails == 0) {
    printf("MIX verdict=ALL_OK fails=0\n");
  } else {
    printf("MIX verdict=HAS_FAIL fails=%d\n", fails);
  }
  return fails == 0 ? 0 : 1;
}
