#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 vdot 归约树的「扩展实测」RTL（独立数据通路、同结构参数化、未集成进 VIMacU）。

用途
----
stage3/3.3/report.md §7 的扩展面积全是【推算】（按 481 实测基数线性外推）。本脚本生成
**可综合的独立数据通路模块**，让 K=16 这一格可以真的跑 Yosys，而不是按比例算。

三个模块（每个文件自包含，可直接 `read_verilog -sv <file>; synth -top <top>`）：

  VdotReduceK8    K=8,  W=19  纯 4:2 树 8→4→2（3 实例 / 2 段）——**对照**，结构逐字复刻
                 公开仓 K1 的 VdotReduce（即 481 / 4,900 / 22 那个件），用于验证「同一
                 结构 + 同一综合流程」时能复现 481，从而证明扩展格与它同口径。
  VdotReduceK16   K=16, W=20  纯 4:2 树 16→8→4→2（7 实例 / 3 段）——**扩展**，即 §7.4 表
                 「K=16, SEW=8, np=1 → 1,149 cells」那一行所指的理想 4:2 结构。
  VdotReduceK16Gen K=16, W=20 仓内生成器 CSA_Nto2With3to2MainPipeline 在 n=16 时的**退化
                 调度**（n∉{4,8} ⇒ 全用 3:2）：5+3+2+1 = 11 实例 / 4 段。仅作 §7.2
                 「生成器退化 3:2 ⇒ 1,792 cells / 1.56 倍」那条【推算】的旁证，不进
                 base/ext 比值。

结构口径（与现有 VdotReduce 一致，见 repos/XiangShan/yunsuan/.../VdotReduce.scala）
-------------------------------------------------------------------------------
  sum_wo[15:0] × K → 符号扩展到 W 位（严禁零扩展，见 design/ARCHITECTURE.md §2.2 第 3 条）
  → 4:2 CSA 树（纯组合，pipeLevel=0）
  → W 位 CPA（sum + carry）
  → 1 拍寄存器（io.fireS1 使能）→ 格式化 {96'h0, sext32(S)} 输出 128 位 vd

拍级切分与 K1 版 VdotReduce **完全一致**：树与 CPA 都在寄存器之前（组合），寄存器只打
一拍在格式化后的 vd 上 —— 这正是 481 那个件的切法（firtool 生成的等价 SV 里
`io_vd_r <= {96'h0, {13{cpa[18]}}, cpa}`，19 个 `$_DFFE_PP_`）。P-2 的 carry-save 重定时
（寄存器打 (sum,carry) 对、38 FF）是**另一条轴**，本脚本不混进来，否则 base 就不再是 481。

生成的 CSA4to2 / CSA3to2 逐位表达式与 Chisel 源一一对应（VectorFloatFMA.scala:1600-1660
的 CSA4to2、1580-1595 的 CSA3to2），并对 K8 做与基线 RTL 的等价性检查（见 run_ext_yosys.sh）。

用法
----
  python3 design/verify/area/gen_ext.py            # 写到同目录 ext/
  python3 design/verify/area/gen_ext.py --out DIR  # 指定输出目录
"""

import argparse
import json
import os

# ---------------------------------------------------------------------------
# 位宽定理（report §7.1 / out/validate/run.log [A6]）：W = 2*SEW + floor(log2 K)
# ---------------------------------------------------------------------------
def w_min(sew: int, k: int) -> int:
    return 2 * sew + (k.bit_length() - 1)   # K 为 2 的幂时 floor(log2 K) = bit_length-1


# ---------------------------------------------------------------------------
# 叶子原语：CSA4to2 / CSA3to2（逐位展开，语义与 VectorFloatFMA.scala 一致）
# ---------------------------------------------------------------------------
def emit_csa4to2(w: int, name: str) -> str:
    """Chisel CSA4to2(width=w) 的逐位展开。

    cout_vec(i) = a^b ? c : a                        (i 与 i-1 的进位链，非零延迟)
    sum_vec(0)  = a^b^c^d ;  carry_vec(0) = (a^b^c^d) ? 0   : d
    sum_vec(i)  = a^b^c^d^cout(i-1) ; carry_vec(i) = (a^b^c^d) ? cout(i-1) : d
    out_sum/out_car = 相邻位交换（sum_temp/carry_temp 的奇偶换位）
    """
    L = []
    L.append("module %s (" % name)
    L.append("  input  wire [%d:0] a," % (w - 1))
    L.append("  input  wire [%d:0] b," % (w - 1))
    L.append("  input  wire [%d:0] c," % (w - 1))
    L.append("  input  wire [%d:0] d," % (w - 1))
    L.append("  output wire [%d:0] sum," % (w - 1))
    L.append("  output wire [%d:0] car" % (w - 1))
    L.append(");")
    L.append("  wire [%d:0] cout_vec, sum_vec, carry_vec, sum_tmp, carry_tmp;" % (w - 1))
    for i in range(w):
        L.append("  assign cout_vec[%d] = (a[%d] ^ b[%d]) ? c[%d] : a[%d];" % (i, i, i, i, i))
    for i in range(w):
        x = "a[%d] ^ b[%d] ^ c[%d] ^ d[%d]" % (i, i, i, i)
        if i == 0:
            L.append("  assign sum_vec[0]   = %s;" % x)
            L.append("  assign carry_vec[0] = (%s) ? 1'b0 : d[0];" % x)
        else:
            L.append("  assign sum_vec[%d]   = %s ^ cout_vec[%d];" % (i, x, i - 1))
            L.append("  assign carry_vec[%d] = (%s) ? cout_vec[%d] : d[%d];" % (i, x, i - 1, i))
    L.append("  assign sum_tmp[0]   = sum_vec[0];")
    L.append("  assign carry_tmp[0] = 1'b0;")
    for i in range(1, w):
        if i % 2 == 1:   # 奇：sum<-carry(i-1), carry<-sum(i)
            L.append("  assign sum_tmp[%d]   = carry_vec[%d];" % (i, i - 1))
            L.append("  assign carry_tmp[%d] = sum_vec[%d];" % (i, i))
        else:            # 偶：sum<-sum(i), carry<-carry(i-1)
            L.append("  assign sum_tmp[%d]   = sum_vec[%d];" % (i, i))
            L.append("  assign carry_tmp[%d] = carry_vec[%d];" % (i, i - 1))
    L.append("  assign sum = sum_tmp;")
    L.append("  assign car = carry_tmp;")
    L.append("endmodule")
    return "\n".join(L)


def emit_csa3to2(w: int, name: str) -> str:
    """Chisel CSA3to2(width=w)：sum = a^b^c ; car = {(a&b)|(a&c)|(b&c)}(w-2..0), 0。"""
    L = []
    L.append("module %s (" % name)
    L.append("  input  wire [%d:0] a," % (w - 1))
    L.append("  input  wire [%d:0] b," % (w - 1))
    L.append("  input  wire [%d:0] c," % (w - 1))
    L.append("  output wire [%d:0] sum," % (w - 1))
    L.append("  output wire [%d:0] car" % (w - 1))
    L.append(");")
    L.append("  wire [%d:0] carry_hi = (a & b) | (a & c) | (b & c);" % (w - 1))
    L.append("  assign sum = a ^ b ^ c;")
    L.append("  assign car = {carry_hi[%d:0], 1'b0};" % (w - 2))
    L.append("endmodule")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# 归约树拓扑
# ---------------------------------------------------------------------------
def tree_pure42(k: int):
    """纯 4:2 树：每段严格 n -> n/2。返回 [(段号, [ (实例下标列表) ... ])]，实例用 4 个操作数。"""
    stages = []
    n = k
    while n > 2:
        assert n % 4 == 0, "纯 4:2 树要求每段 n 是 4 的倍数，n=%d" % n
        stages.append([(i, i + 1, i + 2, i + 3) for i in range(0, n, 4)])  # 每实例吃 4 个连续操作数
        n = n // 2
    return stages


def tree_gen32(k: int):
    """复刻 CSA_Nto2With3to2MainPipeline 的确定性调度（n∉{4,8} 时全 3:2 + remainder 尾巴）。

    返回 [(kind, idx_tuple)] 的扁平实例表，按段分组；kind ∈ {'4','3'}。
    """
    stages = []
    n = k
    while n > 2:
        if n == 8 or n == 4:
            num4, num3 = n // 4, 0
        else:
            num4, num3 = 0, n // 3
        rem = n - num4 * 4 - num3 * 3
        insts = []
        for i in range(num4):
            insts.append(("4", (i * 4 + 0, i * 4 + 1, i * 4 + 2, i * 4 + 3)))
        for i in range(num3):
            insts.append(("3", (i * 3 + 0, i * 3 + 1, i * 3 + 2)))
        stages.append((insts, num4, num3, rem))
        n = (num4 + num3) * 2 + rem
    return stages


def build_netlist(k: int, mode: str, w: int):
    """生成操作数网表：返回 (stages_out, n_inst4, n_inst3, n_stages)。

    stages_out = [ [(kind, [src_id,...], [dst_sum_id, dst_car_id]) ...], ... ]
    src_id: ('in', lane) 或 ('w', wid)（上一段产生的中间线）
    """
    # 当前段的输入：list of ('in', i)
    cur = [("in", i) for i in range(k)]
    out_stages = []
    n4 = n3 = 0
    wid = 0
    if mode == "pure42":
        plan = tree_pure42(k)
        for si, groups in enumerate(plan):
            insts = []
            nxt = []
            for g in groups:
                ops = [cur[j] for j in g]
                s_id, c_id = ("w", wid), ("w", wid + 1)
                wid += 2
                insts.append(("4", ops, [s_id, c_id]))
                nxt += [s_id, c_id]
                n4 += 1
            out_stages.append(insts)
            cur = nxt
    elif mode == "gen32":
        plan = tree_gen32(k)
        for si, (insts_plan, num4, num3, rem) in enumerate(plan):
            insts = []
            nxt = []
            for kind, idxs in insts_plan:
                ops = [cur[j] for j in idxs]
                s_id, c_id = ("w", wid), ("w", wid + 1)
                wid += 2
                insts.append((kind, ops, [s_id, c_id]))
                nxt += [s_id, c_id]
                if kind == "4":
                    n4 += 1
                else:
                    n3 += 1
            # remainder：Chisel 里是 `in_next += in(in.length-2); in_next += in.last`（尾部、保序）
            if rem == 2:
                nxt.append(cur[-2])
                nxt.append(cur[-1])
            elif rem == 1:
                nxt.append(cur[-1])
            out_stages.append(insts)
            cur = nxt
    else:
        raise ValueError(mode)
    assert len(cur) == 2, "归约收尾应剩 2 个操作数，实得 %d" % len(cur)
    return out_stages, cur, n4, n3


def emit_tree(name: str, k: int, mode: str, w: int):
    """归约树子模块（对应 Chisel 的 CSA_Nto2With3to2MainPipeline 实例）。

    单独成模块而不是在顶层展开，是为了让综合后的 $scopeinfo 数与 Chisel/firtool 的
    层次一致（模块定义 + 顶层 always 各贡献 1 个）——481 锚点里有 4 个 $scopeinfo，
    若把树摊平进顶层就只有 3 个，会白白少 1 cell，破坏与 §7.4 基数的同口径。
    """
    stages, final, n4, n3 = build_netlist(k, mode, w)
    hi = w - 1
    L = []
    L.append("module %s (" % name)
    for i in range(k):
        L.append("  input  wire [%d:0] io_in_%d," % (hi, i))
    L.append("  output wire [%d:0] io_out_sum," % hi)
    L.append("  output wire [%d:0] io_out_car" % hi)
    L.append(");")
    L.append("")
    for si, insts in enumerate(stages):
        L.append("  // ---- stage %d ----" % (si + 1))
        for (kind, ops, dst) in insts:
            def sig(o):
                return "io_in_%d" % o[1] if o[0] == "in" else "w%d" % o[1]
            sname = "s%d_%s" % (dst[0][1] // 2, "csa4to2" if kind == "4" else "csa3to2")
            L.append("  wire [%d:0] w%d, w%d;" % (hi, dst[0][1], dst[1][1]))
            if kind == "4":
                L.append("  csa4to2_w%d %s (.a(%s), .b(%s), .c(%s), .d(%s), .sum(w%d), .car(w%d));"
                         % (w, sname, sig(ops[0]), sig(ops[1]), sig(ops[2]), sig(ops[3]),
                            dst[0][1], dst[1][1]))
            else:
                L.append("  csa3to2_w%d %s (.a(%s), .b(%s), .c(%s), .sum(w%d), .car(w%d));"
                         % (w, sname, sig(ops[0]), sig(ops[1]), sig(ops[2]),
                            dst[0][1], dst[1][1]))
        L.append("")
    def fsig(o):
        return "io_in_%d" % o[1] if o[0] == "in" else "w%d" % o[1]
    L.append("  assign io_out_sum = %s;" % fsig(final[0]))
    L.append("  assign io_out_car = %s;" % fsig(final[1]))
    L.append("endmodule")
    return "\n".join(L), stages, n4, n3


def emit_top(top: str, k: int, mode: str, note: str) -> str:
    w = w_min(8, k)
    hi = w - 1
    tree_name = "reduce_tree_k%d" % k
    tree_txt, stages, n4, n3 = emit_tree(tree_name, k, mode, w)
    L = []
    L.append("// " + "=" * 76)
    L.append("// %s.sv" % top)
    L.append("// 独立数据通路、同结构参数化、未集成进 VIMacU。")
    L.append("//")
    L.append("// %s" % note)
    L.append("//")
    L.append("// 参数：K=%d lanes, SEW=8, W=2*SEW+floor(log2 K)=%d bits（位宽定理 L4）" % (k, w))
    L.append("// 树  ：%s，%d 个 CSA4to2 + %d 个 CSA3to2，%d 段" %
             ("纯 4:2（每段 n->n/2）" if mode == "pure42" else "仓内生成器退化调度（n∉{4,8} ⇒ 3:2）",
              n4, n3, len(stages)))
    L.append("// 拍级：签名扩展 + 树 + W 位 CPA 全组合，单拍寄存器打在格式化后的 vd 上（同 K1 版")
    L.append("//       VdotReduce：io_vd_r <= {96'h0, sext32(cpa)}，fireS1 使能）")
    L.append("// 由 design/verify/area/gen_ext.py 生成，勿手改（改参数改脚本再重生成）。")
    L.append("// " + "=" * 76)
    L.append("`default_nettype none")
    L.append("")
    L.append(emit_csa4to2(w, "csa4to2_w%d" % w))
    L.append("")
    if n3:
        L.append(emit_csa3to2(w, "csa3to2_w%d" % w))
        L.append("")
    L.append(tree_txt)
    L.append("")
    # ---- 顶层 ----
    L.append("module %s (" % top)
    L.append("  input  wire         clock,")
    for i in range(k):
        L.append("  input  wire [15:0]  io_sum_wo_%d," % i)
    L.append("  input  wire         io_fireS1,")
    L.append("  output wire [127:0] io_vd")
    L.append(");")
    L.append("")
    # 符号扩展（严禁零扩展）
    for i in range(k):
        L.append("  wire [%d:0] op%d = {{%d{io_sum_wo_%d[15]}}, io_sum_wo_%d};"
                 % (hi, i, w - 16, i, i))
    L.append("")
    # 实例：一棵树一个子模块（层次与 Chisel 的 CSA_Nto2With3to2MainPipeline 对齐）
    L.append("  wire [%d:0] tree_sum, tree_car;" % hi)
    conns = ", ".join(".io_in_%d(op%d)" % (i, i) for i in range(k))
    L.append("  %s tree (%s, .io_out_sum(tree_sum), .io_out_car(tree_car));" % (tree_name, conns))
    L.append("")
    L.append("  // ---- %d 位 CPA + 单拍寄存器（同 K1 版 VdotReduce 的切分）----" % w)
    L.append("  wire [%d:0] cpa = tree_sum + tree_car;" % hi)
    L.append("  reg  [127:0] io_vd_r;")
    L.append("  always @(posedge clock) begin")
    L.append("    if (io_fireS1)")
    L.append("      io_vd_r <= {96'h0, {%d{cpa[%d]}}, cpa};" % (32 - w, hi))
    L.append("  end")
    L.append("  assign io_vd = io_vd_r;")
    L.append("")
    L.append("endmodule")
    L.append("")
    L.append("`default_nettype wire")
    return "\n".join(L) + "\n"


MODULES = [
    dict(top="VdotReduceK8", k=8, mode="pure42",
         note="对照件：K=8 纯 4:2 树（3 实例 / 2 段），结构逐字复刻公开仓 K1 的 VdotReduce。\n"
              "// 若综合得 481 cells / ltp 22，则本件与报告 §7.4 的 481 锚点同口径。"),
    dict(top="VdotReduceK16", k=16, mode="pure42",
         note="扩展件：K=16 纯 4:2 树（7 实例 / 3 段），对应 §7.4 表「K=16, SEW=8, np=1」那一行\n"
              "// 的 1,149 cells【推算】所假设的理想 4:2 结构。乘法器侧不变（仍是 16 位积）。"),
    dict(top="VdotReduceK16Gen", k=16, mode="gen32",
         note="旁证件：K=16 走仓内生成器 CSA_Nto2With3to2MainPipeline 的退化调度（n∉{4,8} ⇒ 全 3:2，\n"
              "// 5+3+2+1 = 11 实例 / 4 段），对应 §7.2「1,792 cells / 1.56 倍」那条【推算】。\n"
              "// 仅作旁证，不进 base/ext 比值。"),
]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(here, "ext"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    manifest = {}
    for m in MODULES:
        sv = emit_top(m["top"], m["k"], m["mode"], m["note"])
        path = os.path.join(args.out, m["top"] + ".sv")
        with open(path, "w") as f:
            f.write(sv)
        w = w_min(8, m["k"])
        stages, final, n4, n3 = build_netlist(m["k"], m["mode"], w)
        manifest[m["top"]] = dict(k=m["k"], sew=8, width=w, mode=m["mode"],
                                  n_csa4to2=n4, n_csa3to2=n3, n_stages=len(stages),
                                  lines=sv.count("\n"))
        print("-> %s  K=%d W=%d %s  instances=%d(%d×4:2,%d×3:2) stages=%d lines=%d"
              % (path, m["k"], w, m["mode"], n4 + n3, n4, n3, len(stages), sv.count("\n")))
    mpath = os.path.join(args.out, "ext_manifest.json")
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("-> %s" % mpath)


if __name__ == "__main__":
    main()