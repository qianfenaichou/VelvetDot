// xb_vl_sweep.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xb_vl_sweep
//@CLS vdot-base
//@FAMILY base
// 说明：vl=0..8 全扫：结果与 vl 无关且全写 vd（SPEC §1.1 有意偏离）
// 期望值：全部由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1 / §1.2；编码：SPEC §2.2（funct6=001110, vm=1, funct3=010, opcode=1010111）
#include <am.h>
#include <klib.h>
#include <stdint.h>

#define ENC_VDOT(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |            \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

static volatile int8_t op1[16] = {-7, -7, -7, 5, 5, 5, 5, 5, 127, -128, 1, -1, 5, -5, 100, -100};
static volatile int8_t op2[16] = {3, 3, 3, 3, 3, 3, 3, 3, -1, 2, -3, 4, -5, 6, -7, 8};

static volatile uint32_t got[9];
static volatile uint32_t hi_0[4] __attribute__((aligned(16)));
static volatile uint32_t hi_1[4] __attribute__((aligned(16)));
static volatile uint32_t hi_2[4] __attribute__((aligned(16)));
static volatile uint32_t hi_3[4] __attribute__((aligned(16)));
static volatile uint32_t hi_4[4] __attribute__((aligned(16)));
static volatile uint32_t hi_5[4] __attribute__((aligned(16)));
static volatile uint32_t hi_6[4] __attribute__((aligned(16)));
static volatile uint32_t hi_7[4] __attribute__((aligned(16)));
static volatile uint32_t hi_8[4] __attribute__((aligned(16)));

int main(void) {
  int fails = 0;
  /* SPEC §1.1 第六条：AM start.S 只开 mstatus.FS，向量还需 VS!=OFF */
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
  for (int i = 0; i < 4; i++) hi_0[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_1[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_2[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_3[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_4[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_5[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_6[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_7[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  for (int i = 0; i < 4; i++) hi_8[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
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
      //@OP vl 0
      "li t1, 0\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=0 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 0(a5)\n\t"
      "la a5, hi_0\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 0\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 1
      "li t1, 1\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=1 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 4(a5)\n\t"
      "la a5, hi_1\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 1\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 2
      "li t1, 2\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=2 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 8(a5)\n\t"
      "la a5, hi_2\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 2\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 3
      "li t1, 3\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=3 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 12(a5)\n\t"
      "la a5, hi_3\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 3\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 4
      "li t1, 4\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=4 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 16(a5)\n\t"
      "la a5, hi_4\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 4\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 5
      "li t1, 5\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=5 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 20(a5)\n\t"
      "la a5, hi_5\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 5\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 6
      "li t1, 6\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=6 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 24(a5)\n\t"
      "la a5, hi_6\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 6\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 7
      "li t1, 7\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=7 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 28(a5)\n\t"
      "la a5, hi_7\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 7\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vl 8
      "li t1, 8\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP vdot vd=3 vs1=1 vs2=2 enc=0x3A20A1D7
      ".4byte 0x3A20A1D7\n\t"
      //@OP read idx=8 vd=3 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v3\n\t"
      "la a5, got\n\t"
      "sw t3, 32(a5)\n\t"
      "la a5, hi_8\n\t"
      "vse32.v v3, (a5)\n\t"
      "li t1, 8\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      ".option pop\n\t"
      ::: "t0", "t1", "t2", "t3", "t4", "a2", "a3", "a5", "memory");

  /* ---- 断言（期望常量全部来自金模型）---- */
  if (got[0] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read0 got=0x%08X want=0x0000000C\n", got[0], 0x0000000Cu); }
  if (hi_0[1] != 0u || hi_0[2] != 0u || hi_0[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read0 hi96=[%08X %08X %08X]\n", hi_0[1], hi_0[2], hi_0[3]); }
  if (got[1] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read1 got=0x%08X want=0x0000000C\n", got[1], 0x0000000Cu); }
  if (hi_1[1] != 0u || hi_1[2] != 0u || hi_1[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read1 hi96=[%08X %08X %08X]\n", hi_1[1], hi_1[2], hi_1[3]); }
  if (got[2] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read2 got=0x%08X want=0x0000000C\n", got[2], 0x0000000Cu); }
  if (hi_2[1] != 0u || hi_2[2] != 0u || hi_2[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read2 hi96=[%08X %08X %08X]\n", hi_2[1], hi_2[2], hi_2[3]); }
  if (got[3] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read3 got=0x%08X want=0x0000000C\n", got[3], 0x0000000Cu); }
  if (hi_3[1] != 0u || hi_3[2] != 0u || hi_3[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read3 hi96=[%08X %08X %08X]\n", hi_3[1], hi_3[2], hi_3[3]); }
  if (got[4] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read4 got=0x%08X want=0x0000000C\n", got[4], 0x0000000Cu); }
  if (hi_4[1] != 0u || hi_4[2] != 0u || hi_4[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read4 hi96=[%08X %08X %08X]\n", hi_4[1], hi_4[2], hi_4[3]); }
  if (got[5] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read5 got=0x%08X want=0x0000000C\n", got[5], 0x0000000Cu); }
  if (hi_5[1] != 0u || hi_5[2] != 0u || hi_5[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read5 hi96=[%08X %08X %08X]\n", hi_5[1], hi_5[2], hi_5[3]); }
  if (got[6] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read6 got=0x%08X want=0x0000000C\n", got[6], 0x0000000Cu); }
  if (hi_6[1] != 0u || hi_6[2] != 0u || hi_6[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read6 hi96=[%08X %08X %08X]\n", hi_6[1], hi_6[2], hi_6[3]); }
  if (got[7] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read7 got=0x%08X want=0x0000000C\n", got[7], 0x0000000Cu); }
  if (hi_7[1] != 0u || hi_7[2] != 0u || hi_7[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read7 hi96=[%08X %08X %08X]\n", hi_7[1], hi_7[2], hi_7[3]); }
  if (got[8] != 0x0000000Cu) { fails++; printf("EXTRA xb_vl_sweep read8 got=0x%08X want=0x0000000C\n", got[8], 0x0000000Cu); }
  if (hi_8[1] != 0u || hi_8[2] != 0u || hi_8[3] != 0u) { fails++; printf("EXTRA xb_vl_sweep read8 hi96=[%08X %08X %08X]\n", hi_8[1], hi_8[2], hi_8[3]); }
  printf("EXTRA xb_vl_sweep reads=9 fails=%d\n", fails);
  printf("CASE xb_vl_sweep: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA xb_vl_sweep verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
