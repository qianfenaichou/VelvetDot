// xo3_wb2_v31.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID xo3_wb2_v31
//@CLS vdot-ov
//@FAMILY alias-wb
// 说明：v31 边界 + 两次写回且别名角色互换（先 vd==vs1、后 vd==vs2）：第二次必须读到第一次结果
// 期望值：全部由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1 / §1.2；编码：SPEC §2.2（funct6=001110, vm=1, funct3=010, opcode=1010111）
#include <am.h>
#include <klib.h>
#include <stdint.h>

#define ENC_VDOT(vd, vs1, vs2)                                                 \
  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |            \
   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)

static volatile int8_t op1[16] = {1, 2, 3, 4, 5, 6, 7, 8, 31, 32, 33, 34, 35, 36, 37, 38};
static volatile int8_t op2[16] = {100, -100, 50, -50, 25, -25, 12, -12, 39, 40, 41, 42, 43, 44, 45, 46};

static volatile uint32_t got[1];
static volatile uint32_t hi_0[4] __attribute__((aligned(16)));

int main(void) {
  int fails = 0;
  /* SPEC §1.1 第六条：AM start.S 只开 mstatus.FS，向量还需 VS!=OFF */
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
  for (int i = 0; i < 4; i++) hi_0[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */
  asm volatile(
    //@PROLOGUE 载入全部操作数：e8,m1,vl=16（SPEC §1.1：lane 0..15 全写）
      ".balign 4\n\t"
      ".option push\n\t"
      ".option norvc\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      //@OP load v31 arr=op1
      "la a2, op1\n\t"
      "vle8.v v31, (a2)\n\t"
      //@OP load v30 arr=op2
      "la a2, op2\n\t"
      "vle8.v v30, (a2)\n\t"
      //@OP vdot vd=31 vs1=31 vs2=30 enc=0x3BEFAFD7
      ".4byte 0x3BEFAFD7\n\t"
      //@OP vdot vd=31 vs1=30 vs2=31 enc=0x3BFF2FD7
      ".4byte 0x3BFF2FD7\n\t"
      //@OP read idx=0 vd=31 want=0x00001B58 hi=1
      "li t2, 4\n\t"
      "vsetvli zero, t2, e32, m1, tu, mu\n\t"
      "vmv.x.s t3, v31\n\t"
      "la a5, got\n\t"
      "sw t3, 0(a5)\n\t"
      "la a5, hi_0\n\t"
      "vse32.v v31, (a5)\n\t"
      "li t1, 16\n\t"
      "vsetvli zero, t1, e8, m1, ta, ma\n\t"
      ".option pop\n\t"
      ::: "t0", "t1", "t2", "t3", "t4", "a2", "a3", "a5", "memory");

  /* ---- 断言（期望常量全部来自金模型）---- */
  if (got[0] != 0x00001B58u) { fails++; printf("EXTRA xo3_wb2_v31 read0 got=0x%08X want=0x00001B58\n", got[0], 0x00001B58u); }
  if (hi_0[1] != 0u || hi_0[2] != 0u || hi_0[3] != 0u) { fails++; printf("EXTRA xo3_wb2_v31 read0 hi96=[%08X %08X %08X]\n", hi_0[1], hi_0[2], hi_0[3]); }
  printf("EXTRA xo3_wb2_v31 reads=1 fails=%d\n", fails);
  printf("CASE xo3_wb2_v31: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA xo3_wb2_v31 verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
