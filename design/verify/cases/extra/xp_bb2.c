// xp_bb2.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xp_bb2
//@CLS vdot-pl
//@FAMILY back2back
// 说明：2 条背靠背独立 vdot（0 bubble，不同 vd）
// 期望值：全部由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1 / §1.2；编码：SPEC §2.2（funct6=001110, vm=1, funct3=010, opcode=1010111）
#include <am.h>
#include <klib.h>
#include <stdint.h>

#define ENC_VDOT(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |            \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

static volatile int8_t op1[16] = {3, -5, 7, -9, 11, -13, 17, -19, 21, -23, 25, -27, 29, -31, 33, -35};
static volatile int8_t op2[16] = {-2, 4, -6, 8, -10, 12, -14, 16, -18, 20, -22, 24, -26, 28, -30, 32};

static volatile uint32_t got[2];
static volatile uint32_t hi_0[4] __attribute__((aligned(16)));
static volatile uint32_t hi_1[4] __attribute__((aligned(16)));

int main(void) {
  int fails = 0;
  /* SPEC §1.1 第六条：AM start.S 只开 mstatus.FS，向量还需 VS!=OFF */
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
  for (int i = 0; i < 4; i++) hi_0[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_1[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  asm volatile(
    //@PROLOGUE 载入全部操作数：e8,m1,vl=16（SPEC §1.1：lane 0..15 全写）
      ".balign 4\n\t"
      ".option push\n\t"
      ".option norvc\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP load v1 arr=op1
      "la a2, op1\n\t"
      "vle8.v v1, (a2)\n\t"
      //@OP load v2 arr=op2
      "la a2, op2\n\t"
      "vle8.v v2, (a2)\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP vdot vd=4 vs1=1 vs2=2 enc=0x3A20A257
      ".4byte 0x3A20A257\n\t"
      //@OP read idx=0 vd=3 want=0xFFFFFC4C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 0(a5)\n\t"
      "la a5, hi_0\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=1 vd=4 want=0xFFFFFC4C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v4\n\t"
      "la a5, got\n\t"
      "sw t3, 4(a5)\n\t"
      "la a5, hi_1\n\t"
      "vse32.v v4, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      ".option pop\n\t"
      ::: "t0", "t1", "t2", "t3", "t4", "a2", "a3", "a5", "memory");

  /* ---- 断言（期望常量全部来自金模型）---- */
  if (got[0] != 0xFFFFFC4Cu) { fails++; printf("EXTRA xp_bb2 read0 got=0x%08X want=0xFFFFFC4C\n", got[0], 0xFFFFFC4Cu); }
  if (hi_0[1] != 0u || hi_0[2] != 0u || hi_0[3] != 0u) { fails++; printf("EXTRA xp_bb2 read0 hi96=[%08X %08X %08X]\n", hi_0[1], hi_0[2], hi_0[3]); }
  if (got[1] != 0xFFFFFC4Cu) { fails++; printf("EXTRA xp_bb2 read1 got=0x%08X want=0xFFFFFC4C\n", got[1], 0xFFFFFC4Cu); }
  if (hi_1[1] != 0u || hi_1[2] != 0u || hi_1[3] != 0u) { fails++; printf("EXTRA xp_bb2 read1 hi96=[%08X %08X %08X]\n", hi_1[1], hi_1[2], hi_1[3]); }
  printf("EXTRA xp_bb2 reads=2 fails=%d\n", fails);
  printf("CASE xp_bb2: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA xp_bb2 verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
