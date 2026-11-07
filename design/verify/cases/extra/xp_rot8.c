// xp_rot8.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xp_rot8
//@CLS vdot-pl
//@FAMILY rotate
// 说明：8 个不同 vd(20..27) 同时在飞（覆盖 vd 索引全部有效位），8 个结果两两互异；写回目的地解码不是 3 位截断或相邻别名
// 期望值：全部由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1 / §1.2；编码：SPEC §2.2（funct6=001110, vm=1, funct3=010, opcode=1010111）
#include <am.h>
#include <klib.h>
#include <stdint.h>

#define ENC_VDOT(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |            \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

static volatile int8_t op1[16] = {3, -5, 7, -9, 11, -13, 17, -19, 21, -23, 25, -27, 29, -31, 33, -35};
static volatile int8_t op2[16] = {-1, -2, -3, -4, -5, -6, -7, -8, 9, 10, 11, 12, 13, 14, 15, 16};
static volatile int8_t op3[16] = {-7, -7, -7, 5, 5, 5, 5, 5, 127, -128, 1, -1, 5, -5, 100, -100};
static volatile int8_t op4[16] = {127, 127, 127, 127, 127, 127, 127, 127, -128, 127, -128, 127, -128, 127, -128, 127};
static volatile int8_t op5[16] = {-2, 4, -6, 8, -10, 12, -14, 16, -18, 20, -22, 24, -26, 28, -30, 32};
static volatile int8_t op6[16] = {1, 1, 1, 1, 1, 1, 1, 1, -17, 18, -19, 20, -21, 22, -23, 24};
static volatile int8_t op7[16] = {3, 3, 3, 3, 3, 3, 3, 3, -1, 2, -3, 4, -5, 6, -7, 8};
static volatile int8_t op8[16] = {127, 127, 127, 127, 127, 127, 127, 127, 127, -128, 127, -128, 127, -128, 127, -128};

static volatile uint32_t got[8];
static volatile uint32_t hi_0[4] __attribute__((aligned(16)));
static volatile uint32_t hi_1[4] __attribute__((aligned(16)));
static volatile uint32_t hi_2[4] __attribute__((aligned(16)));
static volatile uint32_t hi_3[4] __attribute__((aligned(16)));
static volatile uint32_t hi_4[4] __attribute__((aligned(16)));
static volatile uint32_t hi_5[4] __attribute__((aligned(16)));
static volatile uint32_t hi_6[4] __attribute__((aligned(16)));
static volatile uint32_t hi_7[4] __attribute__((aligned(16)));

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
      //@OP load v3 arr=op3
      "la a2, op3\n\t"
      "vle8.v v3, (a2)\n\t"
      //@OP load v4 arr=op4
      "la a2, op4\n\t"
      "vle8.v v4, (a2)\n\t"
      //@OP load v5 arr=op5
      "la a2, op5\n\t"
      "vle8.v v5, (a2)\n\t"
      //@OP load v6 arr=op6
      "la a2, op6\n\t"
      "vle8.v v6, (a2)\n\t"
      //@OP load v7 arr=op7
      "la a2, op7\n\t"
      "vle8.v v7, (a2)\n\t"
      //@OP load v8 arr=op8
      "la a2, op8\n\t"
      "vle8.v v8, (a2)\n\t"
      //@OP vdot vd=20 vs1=1 vs2=5 enc=0x3A50AA57
      ".4byte 0x3A50AA57\n\t"
      //@OP vdot vd=21 vs1=2 vs2=6 enc=0x3A612AD7
      ".4byte 0x3A612AD7\n\t"
      //@OP vdot vd=22 vs1=3 vs2=7 enc=0x3A71AB57
      ".4byte 0x3A71AB57\n\t"
      //@OP vdot vd=23 vs1=4 vs2=8 enc=0x3A822BD7
      ".4byte 0x3A822BD7\n\t"
      //@OP vdot vd=24 vs1=2 vs2=5 enc=0x3A512C57
      ".4byte 0x3A512C57\n\t"
      //@OP vdot vd=25 vs1=3 vs2=6 enc=0x3A61ACD7
      ".4byte 0x3A61ACD7\n\t"
      //@OP vdot vd=26 vs1=4 vs2=7 enc=0x3A722D57
      ".4byte 0x3A722D57\n\t"
      //@OP vdot vd=27 vs1=1 vs2=8 enc=0x3A80ADD7
      ".4byte 0x3A80ADD7\n\t"
      //@OP read idx=0 vd=20 want=0xFFFFFC4C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v20\n\t"
      "la a5, got\n\t"
      "sw t3, 0(a5)\n\t"
      "la a5, hi_0\n\t"
      "vse32.v v20, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=1 vd=21 want=0xFFFFFFDC hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v21\n\t"
      "la a5, got\n\t"
      "sw t3, 4(a5)\n\t"
      "la a5, hi_1\n\t"
      "vse32.v v21, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=2 vd=22 want=0x0000000C hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v22\n\t"
      "la a5, got\n\t"
      "sw t3, 8(a5)\n\t"
      "la a5, hi_2\n\t"
      "vse32.v v22, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=3 vd=23 want=0x0001F808 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v23\n\t"
      "la a5, got\n\t"
      "sw t3, 12(a5)\n\t"
      "la a5, hi_3\n\t"
      "vse32.v v23, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=4 vd=24 want=0xFFFFFFB8 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v24\n\t"
      "la a5, got\n\t"
      "sw t3, 16(a5)\n\t"
      "la a5, hi_4\n\t"
      "vse32.v v24, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=5 vd=25 want=0x00000004 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v25\n\t"
      "la a5, got\n\t"
      "sw t3, 20(a5)\n\t"
      "la a5, hi_5\n\t"
      "vse32.v v25, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=6 vd=26 want=0x00000BE8 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v26\n\t"
      "la a5, got\n\t"
      "sw t3, 24(a5)\n\t"
      "la a5, hi_6\n\t"
      "vse32.v v26, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP read idx=7 vd=27 want=0xFFFFFC08 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v27\n\t"
      "la a5, got\n\t"
      "sw t3, 28(a5)\n\t"
      "la a5, hi_7\n\t"
      "vse32.v v27, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      ".option pop\n\t"
      ::: "t0", "t1", "t2", "t3", "t4", "a2", "a3", "a5", "memory");

  /* ---- 断言（期望常量全部来自金模型）---- */
  if (got[0] != 0xFFFFFC4Cu) { fails++; printf("EXTRA xp_rot8 read0 got=0x%08X want=0xFFFFFC4C\n", got[0], 0xFFFFFC4Cu); }
  if (hi_0[1] != 0u || hi_0[2] != 0u || hi_0[3] != 0u) { fails++; printf("EXTRA xp_rot8 read0 hi96=[%08X %08X %08X]\n", hi_0[1], hi_0[2], hi_0[3]); }
  if (got[1] != 0xFFFFFFDCu) { fails++; printf("EXTRA xp_rot8 read1 got=0x%08X want=0xFFFFFFDC\n", got[1], 0xFFFFFFDCu); }
  if (hi_1[1] != 0u || hi_1[2] != 0u || hi_1[3] != 0u) { fails++; printf("EXTRA xp_rot8 read1 hi96=[%08X %08X %08X]\n", hi_1[1], hi_1[2], hi_1[3]); }
  if (got[2] != 0x0000000Cu) { fails++; printf("EXTRA xp_rot8 read2 got=0x%08X want=0x0000000C\n", got[2], 0x0000000Cu); }
  if (hi_2[1] != 0u || hi_2[2] != 0u || hi_2[3] != 0u) { fails++; printf("EXTRA xp_rot8 read2 hi96=[%08X %08X %08X]\n", hi_2[1], hi_2[2], hi_2[3]); }
  if (got[3] != 0x0001F808u) { fails++; printf("EXTRA xp_rot8 read3 got=0x%08X want=0x0001F808\n", got[3], 0x0001F808u); }
  if (hi_3[1] != 0u || hi_3[2] != 0u || hi_3[3] != 0u) { fails++; printf("EXTRA xp_rot8 read3 hi96=[%08X %08X %08X]\n", hi_3[1], hi_3[2], hi_3[3]); }
  if (got[4] != 0xFFFFFFB8u) { fails++; printf("EXTRA xp_rot8 read4 got=0x%08X want=0xFFFFFFB8\n", got[4], 0xFFFFFFB8u); }
  if (hi_4[1] != 0u || hi_4[2] != 0u || hi_4[3] != 0u) { fails++; printf("EXTRA xp_rot8 read4 hi96=[%08X %08X %08X]\n", hi_4[1], hi_4[2], hi_4[3]); }
  if (got[5] != 0x00000004u) { fails++; printf("EXTRA xp_rot8 read5 got=0x%08X want=0x00000004\n", got[5], 0x00000004u); }
  if (hi_5[1] != 0u || hi_5[2] != 0u || hi_5[3] != 0u) { fails++; printf("EXTRA xp_rot8 read5 hi96=[%08X %08X %08X]\n", hi_5[1], hi_5[2], hi_5[3]); }
  if (got[6] != 0x00000BE8u) { fails++; printf("EXTRA xp_rot8 read6 got=0x%08X want=0x00000BE8\n", got[6], 0x00000BE8u); }
  if (hi_6[1] != 0u || hi_6[2] != 0u || hi_6[3] != 0u) { fails++; printf("EXTRA xp_rot8 read6 hi96=[%08X %08X %08X]\n", hi_6[1], hi_6[2], hi_6[3]); }
  if (got[7] != 0xFFFFFC08u) { fails++; printf("EXTRA xp_rot8 read7 got=0x%08X want=0xFFFFFC08\n", got[7], 0xFFFFFC08u); }
  if (hi_7[1] != 0u || hi_7[2] != 0u || hi_7[3] != 0u) { fails++; printf("EXTRA xp_rot8 read7 hi96=[%08X %08X %08X]\n", hi_7[1], hi_7[2], hi_7[3]); }
  printf("EXTRA xp_rot8 reads=8 fails=%d\n", fails);
  printf("CASE xp_rot8: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA xp_rot8 verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
