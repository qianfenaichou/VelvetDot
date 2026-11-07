#!/usr/bin/env python3
"""生成 vdot 定向用例源与期望值（ALGORITHM §3.1 算法 B：逐项 int64 累加）。

机器码：vdot.vv 的编码字段 funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111。
0x3A20A1D7 = vdot.vv vd=3, vs1=1, vs2=2（SPEC §2.1 的验收机器码）。
负例对齐说明（2026-11-02 审计修正）：LMUL=2/4/8 的非法用例必须用**对齐**寄存器组，
使陷阱落在 vdot 的 LMUL 谓词上而不是载入指令的对齐检查上；VS=OFF/vill/vstart
三类同样先完成合法装载，再在 vdot 前一步构造非法状态。
"""
import json

V_BASE = 0x3A20A1D7  # vdot.vv v3, v1, v2


def venc(vd, vs1, vs2, vm=1):
    return ((0x0E << 26) | (vm << 25) | (vs2 << 20) | (vs1 << 15) | (2 << 12) | (vd << 7) | 0x57)


def s32(x):
    return x & 0xFFFFFFFF


def algo_b(a, b):
    """算法 B：逐项 int64 累加（不经归约树），截断到 32 位补码。"""
    return s32(sum(x * y for x, y in zip(a, b)))


def src(name, a, b, expect=None, note="", cls="vdot-pos", vtype="e8,m1", extra_asm=""):
    expect = algo_b(a, b) if expect is None else s32(expect)
    a_lit = ", ".join(str(x) for x in a)
    b_lit = ", ".join(str(x) for x in b)
    body = f"""// {name} — {note}（期望由 gen.py 按 §3.1 算法 B 手算，经 32 位补码截断）
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[8] = {{{a_lit}}};
static volatile int8_t bv[8] = {{{b_lit}}};
static volatile uint32_t out[4];

int main(void) {{
  uint32_t res = 0;
  asm volatile(
      "li t0, 0x600\\n\\t"                 // AM 的 start.S 只开 mstatus.FS；向量还需 VS!=OFF（SPEC §1.1 第六条）
      "csrs mstatus, t0\\n\\t"
      "li t1, 8\\n\\t"
      "vsetvli zero, t1, {vtype}, ta, ma\\n\\t"
      "la a2, av\\n\\t"
      "vle8.v v1, (a2)\\n\\t"
      "la a3, bv\\n\\t"
      "vle8.v v2, (a3)\\n\\t"
      "{extra_asm}"
      ".4byte 0x{V_BASE:08X}\\n\\t"
      "li t2, 4\\n\\t"
      "vsetvli zero, t2, e32, m1, tu, mu\\n\\t"
      "vmv.x.s %0, v3\\n\\t"
      "la a4, out\\n\\t"
      "vse32.v v3, (a4)\\n\\t"
      : "=r"(res) :: "t0", "t1", "t2", "a2", "a3", "a4", "memory");
  uint32_t w1 = out[1], w2 = out[2], w3 = out[3];
  printf("CASE {name}: result=0x%08X expect=0x{expect:08X} hi=[0x%08X 0x%08X 0x%08X]\\n",
         (uint32_t)res, w1, w2, w3);
  int ok = ((uint32_t)res == 0x{expect:08X}u) && (w1 == 0) && (w2 == 0) && (w3 == 0);
  printf("CASE {name}: %s\\n", ok ? "MATCH" : "MISMATCH");
  return ok ? 0 : 1;
}}
"""
    open(f"{name}.c", "w").write(body)
    return {"name": name, "cls": cls, "expect": expect}


def asm_body(*lines):
    """把若干条汇编行渲染成**合法 C 源码**的一段内联汇编。

    每条 line 是纯指令文本（不含 C 引号与转义），本函数负责补 `"..."`、行尾 `\\n\\t`
    以及**行与行之间的真实换行**。旧版调用点自己手写 '''"li t1, 8\\n\\t"\\n      "vsetvli…"'''
    ——三引号里的 `\\n` 是**字面反斜杠+n**，粘到 .c 里落在字符串字面量之外，GCC 报
    `stray '\\' in program`（vdot_ill_* 七个负例全编不过的真因）。统一走本函数即不会再犯。
    """
    return "\n      ".join('"%s\\n\\t"' % ln for ln in lines)


def illegal(name, note, body_lines, sentinel="未如期陷入非法指令"):
    """负例：先合法装载（VS 已开），随后构造非法状态并发射 vdot；走到 vdot 之后即失败。

    body_lines 必须由 asm_body() 产出（保证是合法 C 内联汇编），不得手写转义。
    """
    body = f"""// {name} — 非法组合：{note}（negative 类，期望 difftest 双侧一致陷入非法）
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[8] = {{1,2,3,4,5,6,7,8}};
static volatile int8_t bv[8] = {{1,1,1,1,1,1,1,1}};

int main(void) {{
  uint64_t res = 0;
  asm volatile(
      "li t0, 0x600\\n\\t"
      "csrs mstatus, t0\\n\\t"
      "li t1, 8\\n\\t"
      "vsetvli zero, t1, e8, m1, ta, ma\\n\\t"
      "la a2, av\\n\\t"
      "vle8.v v1, (a2)\\n\\t"
      "la a3, bv\\n\\t"
      "vle8.v v2, (a3)\\n\\t"
      {body_lines}
      "vmv.x.s %0, v3\\n\\t"
      : "=r"(res) :: "t0", "t1", "t4", "t5", "a2", "a3", "memory");
  printf("CASE {name}: {sentinel} res=0x%08X\\n", (uint32_t)res);
  return 1;
}}
"""
    open(f"{name}.c", "w").write(body)
    return {"name": name, "cls": "negative"}


cases = []
# ---------- 正数 / 负数 / 混合符号 ----------
cases.append(src("vdot_pos1", [1,2,3,4,5,6,7,8], [1,1,1,1,1,1,1,1], note="正数定向（§3.2 正数）"))
cases.append(src("vdot_pos2", [1,2,3,4,5,6,7,8], [1,-1,1,-1,1,-1,1,-1], note="混合符号（§3.2 正数）"))
cases.append(src("vdot_pos3", [127,-128,1,-1,5,-5,100,-100], [1,1,1,1,1,1,1,1], note="±127/±128 单元素边界（§3.2 边界值）"))
cases.append(src("vdot_neg1", [-1,-2,-3,-4,-5,-6,-7,-8], [1,1,1,1,1,1,1,1], note="全负积（§3.2 负数）", cls="vdot-neg"))
# 奇数个负积：b 全正，a 前 k 个为负 ⇒ 负积个数 = k（k=1/3/5/7）
for k, name in [(1, "vdot_neg_odd1"), (3, "vdot_neg_odd3"), (5, "vdot_neg_odd5"), (7, "vdot_neg_odd7")]:
    a = [-7] * k + [5] * (8 - k)
    b = [3] * 8
    cases.append(src(name, a, b, note=f"奇数个负积 n={k}（§3.2 混合符号奇数负 lane，专抓符号扩展 bug）", cls="vdot-neg"))
# ---------- 边界值 ----------
cases.append(src("vdot_bound1", [-128]*8, [-128]*8, note="全 -128 → S=131072（19 位上边界，§3.2 边界值）", cls="vdot-bound"))
cases.append(src("vdot_bound2", [-128,-128,-128,-128,127,127,127,127],
                 [127,127,127,127,-128,-128,-128,-128], note="最小负和 -130048（§3.2 边界值）", cls="vdot-bound"))
cases.append(src("vdot_bound3", [0]*8, [127,-128,1,-1,5,-5,100,-100], note="一侧全零（§3.2 边界值）", cls="vdot-bound"))
cases.append(src("vdot_bound4", [127]*8, [127]*8, note="全 +127 → S=129032（§3.2 边界值）", cls="vdot-bound"))
cases.append(src("vdot_bound5", [126,-127,126,-127,-128,-128,127,127],
                 [127,-128,-128,127,1,-1,1,-1], note="交错极值（§3.2 边界值）", cls="vdot-bound"))

# ---------- 非法组合（陷阱必须落在 vdot 自身，见文件头注释）----------
# 每个 body 都走 asm_body(...)，只给纯指令文本——不要再手写 C 字符串转义（见 asm_body docstring）。
# SEW=16：vle8 的 EMUL=0.5 不触发对齐，陷阱落在 vdot 的 vdotIllegal 上
cases.append(illegal("vdot_ill_sew", "SEW=16（e16）",
                     asm_body("li t1, 8",
                              "vsetvli zero, t1, e16, m1, ta, ma",
                              ".4byte 0x%08X" % venc(0, 0, 0))))
# LMUL=2/4/8：换对齐寄存器组，使 vdot 的 LMUL 谓词命中（编码见 venc）
cases.append(illegal("vdot_ill_lmul2", "LMUL=2（对齐寄存器 vd=4,vs1=2,vs2=0）",
                     asm_body("li t1, 16",
                              "vsetvli zero, t1, e8, m2, ta, ma",
                              ".4byte 0x%08X" % venc(4, 2, 0))))
cases.append(illegal("vdot_ill_lmul4", "LMUL=4（对齐寄存器 vd=8,vs1=4,vs2=0）",
                     asm_body("li t1, 32",
                              "vsetvli zero, t1, e8, m4, ta, ma",
                              ".4byte 0x%08X" % venc(8, 4, 0))))
cases.append(illegal("vdot_ill_lmul8", "LMUL=8（对齐寄存器 vd=16,vs1=8,vs2=0）",
                     asm_body("li t1, 64",
                              "vsetvli zero, t1, e8, m8, ta, ma",
                              ".4byte 0x%08X" % venc(16, 8, 0))))
# vm=0：保留 vdot 位型但清 vm 位（0x3A20A1D7 去掉 bit25 = 0x3820A1D7）→ 不命中解码 → 非法
cases.append(illegal("vdot_ill_vm0", "vm=0（0x3820A1D7）",
                     asm_body(".4byte 0x3820A1D7")))
# vstart=1：合法装载后、vdot 前写 vstart（CSR 0x008）
cases.append(illegal("vdot_ill_vstart", "vstart=1（CSR 0x008）",
                     asm_body("li t4, 1",
                              "csrw 0x008, t4",
                              ".4byte 0x3A20A1D7")))
# vill=1：合法装载后用一个非法 vtype 执行 vsetvl（vill 置位但 vtype 被清 0），立即执行 vdot → villIllegal
cases.append(illegal("vdot_ill_vill", "vill=1（非法 vtype 0x38 的 vsetvl 后立即 vdot）",
                     asm_body("li t4, 0x38",
                              "li t5, 8",
                              "vsetvl zero, t5, t4",
                              ".4byte 0x3A20A1D7")))
# VS=OFF：先关掉 mstatus.VS（此时 vsetvli 会先被拦截，属系统级第六条件，SPEC 亦要求）
cases.append(illegal("vdot_ill_vs", "mstatus.VS=OFF（先开 VS 再关，唯一变量是 VS）",
                     asm_body("li t4, 0x600",
                              "csrc mstatus, t4",
                              ".4byte 0x3A20A1D7")))

# ---------- 期望值清单 ----------
json.dump({"machine_code": hex(V_BASE), "note": "期望值由算法 B（int64 累加）计算；负例无期望（必须陷入非法）",
           "cases": cases}, open("cases.json", "w"), ensure_ascii=False, indent=2)
print(f"gen.py 生成 {len(cases)} 个用例：", ", ".join(c["name"] for c in cases))
