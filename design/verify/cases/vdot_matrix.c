// vdot_matrix.c — ALGORITHM §3.2 中「单条数值之外」的语义不变量，一程序打尽：
//   ① vl 不变性（vl=0/1/7/8）② vta/vma 四组合 ③ vxsat 前后一致
//   ④ 旧 vd 预填不干扰 ⑤ vd==vs1 重叠 ⑥ 背靠背 4 条独立 vdot（含气泡）
// 期望值由 §3.1 算法 B（逐项 int64 累加）在 C 侧独立算出，不重跑归约树。
// 依据：SPEC §1.1（vl / vta / vma / vxsat / 旧 vd 各行）、§1.2 三个机器可判点。
#include <am.h>
#include <klib.h>
#include <stdint.h>

// vdot.vv vd, vs1, vs2：funct6=001110, vm=1, funct3=010, opcode=1010111
// 展开即 SPEC §2.1 的 0x3A20A1D7 = VDOT(3,1,2)
#define VDOT_ENC(vd, vs1, vs2)                                                  \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |             \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

#define ENC_3_1_2 VDOT_ENC(3, 1, 2)
#define ENC_4_1_2 VDOT_ENC(4, 1, 2)
#define ENC_5_1_2 VDOT_ENC(5, 1, 2)
#define ENC_6_1_2 VDOT_ENC(6, 1, 2)
#define ENC_7_1_2 VDOT_ENC(7, 1, 2)
#define ENC_1_1_2 VDOT_ENC(1, 1, 2)
_Static_assert(ENC_3_1_2 == 0x3A20A1D7u, "encoding must equal SPEC §2.1 machine code");

static volatile int8_t av[8] = {3, -5, 7, -9, 11, -13, 17, -19};
static volatile int8_t bv[8] = {-2, 4, -6, 8, -10, 12, -14, 16};
static volatile uint32_t out[4];

static long long algo_b(void) {  /* 算法 B：逐项累加，不经归约树 */
  long long s = 0;
  for (int i = 0; i < 8; i++) s += (long long)av[i] * (long long)bv[i];
  return s;
}

/* AM 的 start.S 只开 mstatus.FS；向量指令还需 VS!=OFF（SPEC §1.1 第六条） */
static void enable_vs(void) {
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
}

/* 载入 v1=av、v2=bv（e8,m1），vsetvli 由调用方给 */
/* 载入 v1=av / v2=bv（e8,m1，vl 由 t1 给定）*/
#define LOAD2_ABS                                                            \
  "mv t1, %1\n\t"                                                            \
  "la a2, av\n\t"                                                            \
  "vsetvli zero, t1, e8, m1, ta, ma\n\t"                                    \
  "vle8.v v1, (a2)\n\t"                                                      \
  "la a3, bv\n\t"                                                            \
  "vle8.v v2, (a3)\n\t"

/* 载入用固定 vl=8（无输入操作数的场合）*/
#define LOAD2_VL8                                                            \
  "li t1, 8\n\t"                                                            \
  "la a2, av\n\t"                                                            \
  "vsetvli zero, t1, e8, m1, ta, ma\n\t"                                    \
  "vle8.v v1, (a2)\n\t"                                                      \
  "la a3, bv\n\t"                                                            \
  "vle8.v v2, (a3)\n\t"

/* 用 t-寄存器里的 vl 执行一次 vdot 并读回 vd[31:0] 与 vd[127:32] */
static uint32_t run_vdot_vl(uint64_t vl, uint32_t *w1, uint32_t *w2, uint32_t *w3) {
  uint32_t res = 0;
  enable_vs();
  asm volatile(LOAD2_ABS
               ".4byte 0x3A20A1D7\n\t"
               "li t2, 4\n\t"
               "vsetvli zero, t2, e32, m1, tu, mu\n\t"
               "vmv.x.s %0, v3\n\t"
               "la a4, out\n\t"
               "vse32.v v3, (a4)\n\t"
               : "=r"(res)
               : "r"(vl)
               : "t1", "t2", "a2", "a3", "a4", "memory");
  *w1 = out[1];
  *w2 = out[2];
  *w3 = out[3];
  return res;
}

/* ① 的正确形式（2026-11-01 修正）：先用 vl=8 把 v1/v2 装满，之后**只改 vl、不再载入**，
 * 然后执行 vdot 并读回。这样测的才是 SPEC §1.1「vl 不影响结果」这一条。
 * （原 ① 用 run_vdot_vl()，vl 同时作用在 vle8 上 ⇒ 尾部 lane 根本没被装进寄存器，
 *   测出来的是 vle8 的 tail 行为，不是 vdot 的 vl 语义；2026-11-01 首次实跑即由
 *   `no_empty_green` 判据抓出。） */
static uint32_t run_vdot_vl_only(uint64_t vl, uint32_t *w1, uint32_t *w2, uint32_t *w3) {
  uint32_t res = 0;
  enable_vs();
  asm volatile(LOAD2_VL8
               "mv t1, %1\n\t"
               "vsetvli zero, t1, e8, m1, ta, ma\n\t" /* 只改 vl：不重新载入操作数 */
               ".4byte 0x3A20A1D7\n\t"
               "li t2, 4\n\t"
               "vsetvli zero, t2, e32, m1, tu, mu\n\t"
               "vmv.x.s %0, v3\n\t"
               "la a4, out\n\t"
               "vse32.v v3, (a4)\n\t"
               : "=r"(res)
               : "r"(vl)
               : "t1", "t2", "a2", "a3", "a4", "memory");
  *w1 = out[1];
  *w2 = out[2];
  *w3 = out[3];
  return res;
}

/* vsetvl 变体：直接写入编码好的 vxrm/vta/vma 字段（ta/ma 或 tu/mu），vl=8 */
static uint32_t run_vdot_vtype(uint32_t vtype_val, uint32_t *w1, uint32_t *w2, uint32_t *w3) {
  uint32_t res = 0;
  enable_vs();
  asm volatile(
      "li t1, 8\n\t"
      "mv t3, %1\n\t"
      "vsetvl zero, t1, t3\n\t"                       /* 用 vtype 字面量：可精确控制 vta/vma */
      "la a2, av\n\t"
      "vle8.v v1, (a2)\n\t"
      "la a3, bv\n\t"
      "vle8.v v2, (a3)\n\t"
      ".4byte 0x3A20A1D7\n\t"
      "li t2, 4\n\t"
      "mv t3, %2\n\t"
      "vsetvl zero, t2, t3\n\t"                       /* 切 e32 读回视图 */
      "vmv.x.s %0, v3\n\t"
      "la a4, out\n\t"
      "vse32.v v3, (a4)\n\t"
      : "=r"(res)
      : "r"(vtype_val), "r"((uint32_t)0x10 /* e32,m1,tu,mu：vsew=010<<3 */)
      : "t1", "t2", "t3", "a2", "a3", "a4", "memory");
  *w1 = out[1];
  *w2 = out[2];
  *w3 = out[3];
  return res;
}

int main(void) {
  int fails = 0;
  uint32_t w1, w2, w3;
  long long want = algo_b();
  uint32_t want32 = (uint32_t)(int32_t)want;
  printf("MATRIX expect=0x%08X (S=%lld)\n", want32, want);

  /* ① vl 不变性：vl=0/1/4/7/8 都必须算 lane0-7 并全写 vd（操作数先由 vl=8 装满） */
  for (uint64_t vl = 0; vl <= 8; vl++) {
    uint32_t r = run_vdot_vl_only(vl, &w1, &w2, &w3);
    int ok = (r == want32) && w1 == 0 && w2 == 0 && w3 == 0;
    printf("MATRIX vlinvar vl=%llu r=0x%08X hi_nonzero=%d%d%d %s\n", (unsigned long long)vl, r,
           w1 != 0, w2 != 0, w3 != 0, ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }
  /* ①b 诊断（不计入 fails）：vl 同时作用在 vle8 上时的实测形态——
   *    记录「尾部 lane 未被载入」时 DUT/NEMU 的一致行为，作为上面修正的依据。 */
  for (uint64_t vl = 1; vl <= 8; vl++) {
    uint32_t r = run_vdot_vl(vl, &w1, &w2, &w3);
    printf("MATRIX diag_loadvl vl=%llu r=0x%08X\n", (unsigned long long)vl, r);
  }

  /* ② vta/vma 四组合（RVV vtype 字段：vsew[2:0]、vlmul[5:3]、vta[6]、**vma[7]**）
   * 2026-11-02 修正：原实现把 vma 写到 bit5（那是 vlmul[2]）⇒ vtype=0x20 实际是 LMUL=4，
   * vdot 按第六条合法性判非法 → 双 trap（pc=0xe）→ 用例在第二组组合处静默结束。
   * 首次实跑证据：core/results/difftest/cases/vdot_matrix.20261101T234136.log:29867。 */
  for (int vta = 0; vta < 2; vta++) {
    for (int vma = 0; vma < 2; vma++) {
      uint32_t vtype = ((uint32_t)vta << 6) | ((uint32_t)vma << 7);   /* e8,m1 + vta/vma */
      /* 读回视图用 e32,m1,tu,mu = vsew=010<<3 = 0x10 */
      uint32_t r = run_vdot_vtype(vtype, &w1, &w2, &w3);
      int ok = (r == want32) && w1 == 0 && w2 == 0 && w3 == 0;
      printf("MATRIX vta=%d vma=%d vtype=0x%02X r=0x%08X %s\n", vta, vma, vtype, r,
             ok ? "OK" : "FAIL");
      if (!ok) fails++;
    }
  }

  /* ③ vxsat 前后一致（SPEC §1.1：恒 0、不修改）
   * 2026-11-02 修正：vxsat 是 CSR 0x009（0x008 是 vstart），原来读 0x008 等于在比 vstart，
   * 恒 0==0 属零覆盖。 */
  uint64_t xs0 = 0xA5A5A5A5ull, xs1 = 0x5A5A5A5Aull;
  enable_vs();
  asm volatile("csrr %0, 0x009\n\t" : "=r"(xs0));
  uint32_t rr = run_vdot_vl(8, &w1, &w2, &w3);
  asm volatile("csrr %0, 0x009\n\t" : "=r"(xs1));
  printf("MATRIX vxsat before=0x%llX after=0x%llX %s\n", (unsigned long long)xs0,
         (unsigned long long)xs1, (xs0 == xs1) ? "OK" : "FAIL");
  if (xs0 != xs1) fails++;
  (void)rr;

  /* ④ 旧 vd 预填非零（v3=全 1）后执行，结果必须与预填无关 */
  enable_vs();
  asm volatile(
      "li t1, 4\n\t"
      "vsetvli zero, t1, e32, m1, ta, ma\n\t"
      "vmv.v.i v3, -1\n\t" ::
          : "t1", "memory");
  {
    uint32_t r4 = run_vdot_vl(8, &w1, &w2, &w3);
    printf("MATRIX oldvd_prefill r=0x%08X %s\n", r4, r4 == want32 ? "OK" : "FAIL");
    if (r4 != want32) fails++;
  }

  /* ⑤ vd==vs1 重叠：vdot.vv v1, v1, v2 */
  enable_vs();
  {
    uint32_t r5 = 0;
    asm volatile(LOAD2_VL8
                 ".4byte 0x3A20A0D7\n\t"   /* vdot.vv v1, v1, v2 */
                 "li t2, 4\n\t"
                 "vsetvli zero, t2, e32, m1, tu, mu\n\t"
                 "vmv.x.s %0, v1\n\t"
                 : "=r"(r5)
                 :
                 : "t1", "t2", "a2", "a3", "memory");
    printf("MATRIX overlap_vd_eq_vs1 r=0x%08X %s\n", r5, r5 == want32 ? "OK" : "FAIL");
    if (r5 != want32) fails++;
  }

  /* ⑥ 背靠背 4 条独立 vdot（vd=v4..v7）：每条都必须是同一个 S */
  enable_vs();
  {
    uint32_t a = 0, b = 0, c = 0, d = 0;
    asm volatile(LOAD2_VL8
                 ".4byte 0x3A20A257\n\t"   /* vdot.vv v4, v1, v2 */
                 ".4byte 0x3A20A2D7\n\t"   /* vdot.vv v5, v1, v2 */
                 ".4byte 0x3A20A357\n\t"   /* vdot.vv v6, v1, v2 */
                 ".4byte 0x3A20A3D7\n\t"   /* vdot.vv v7, v1, v2 */
                 "li t2, 4\n\t"
                 "vsetvli zero, t2, e32, m1, tu, mu\n\t"
                 "vmv.x.s %0, v4\n\t"
                 "vmv.x.s %1, v5\n\t"
                 "vmv.x.s %2, v6\n\t"
                 "vmv.x.s %3, v7\n\t"
                 : "=r"(a), "=r"(b), "=r"(c), "=r"(d)
                 :
                 : "t1", "t2", "a2", "a3", "memory");
    int ok = (a == want32) && (b == want32) && (c == want32) && (d == want32);
    printf("MATRIX back_to_back v4=0x%08X v5=0x%08X v6=0x%08X v7=0x%08X %s\n", a, b, c, d,
           ok ? "OK" : "FAIL");
    if (!ok) fails++;
  }

  printf("MATRIX verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
