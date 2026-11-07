#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dualchain_check.py — vdot_dualchain 用例的「金模型侧」期望值生成与日志复核。

两条入口（都只用 design/verify/vdot_model.py 作语义事实源，不手抄任何 want 常量）：

  1) ``--emit-header OUT.h``
     解析 ``vdot_dualchain.c`` 的操作数数组 → 用金模型逐步模拟八条链 →
     产出 C 头文件 ``dualchain_expected.h``（``static const uint8_t DCW_*[16]`` +
     ``DC_CHECKLEN_*`` + 内容 sha256）。C 源 ``#include`` 它 ⇒「期望值来自金模型」
     是编译期事实，不是一句注释。

  2) ``--check-log LOG``
     对用例日志逐行比对：每条 ``DUALCHAIN <tag> func`` 行的 ``want=`` 必须等于金模型
     重算值、``bytes_bad=0``；八条链的依赖间隔行（``DUALCHAIN <M> dep``）与汇总串必须齐全。

判据：``--emit-header`` 退出 0 且 ``--check-log`` 打印 ``verdict=LOG_MATCH``
⇒ 金模型 == 用例自检期望 == DUT 实测（ABORT 另由 96-run-dualchain.sh 判）。

口径提醒（改语义先改这里）：
  * vdot 步用 ``vdot_model.vdot_vv()``（SPEC §1.1：读 vs1/vs2 低 64 位，写
    vd[31:0]=sext32(S)、vd[127:32]=0，**旧 vd 不是语义输入**）；
  * vmacc 步按标准 RVV 逐 lane 复算 ``vd[i] = old_vd[i] + vs1[i]*vs2[i]``（SEW=8 模 2^8）；
  * vadd 步按标准 RVV 逐 lane 复算 ``vd[i] = old_vd[i] + vs1[i]``（SEW=8 模 2^8）；
  * vl=8 ⇒ 只有 lane 0..7 参与；vdot 之外的链**只比 8 字节**（lane 8..15 是 tail，
    ta 下架构未定义，比它会把「未定义」当「错」）；vdot 链比 16 字节（高 96 位恒零）。

链编号与 ``vdot_dualchain.c`` 一一对应（M1..M8）；改链必须先改这里再改 C。
"""
import argparse
import hashlib
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, os.pardir, "vdot_model.py")
SRC = os.path.join(HERE, "vdot_dualchain.c")
MASK8 = 0xFF
PREFILL = 0xAB          # M3b 的旧 vd 预填（C 源里同一常量，parse 后核对）

# 链规模（SEW=8 / LMUL=1 / VL=8 / 同操作数 = 与 perf_vdot.c 同一把天平）
N_FUNC = 256            # 功能链长度（N 与 N-1 / N-2 两个长度都跑，防截断）
N_ALT = 255
N_ALT2 = 254
N_WARMUP = 16
N_REPS = 4              # 差分的循环轮数上限（每轮的链指令数见 NREP_LO/HI）
N_ROUNDS = 5            # 差分的轮数（取逐轮商的中位数，同 perf_kernel_cmp 的中位数口径）
NREP_LO = 4             # 每 rep 4 条链指令（探测每-rep 固定开销）
NREP_HI = 8             # 每 rep 8 条链指令


def load_model():
    spec = importlib.util.spec_from_file_location("vdot_model", MODEL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_arrays(path):
    """从 .c 源解析 `static const int8_t NAME[16] = {...};` 的初值（不手抄）。"""
    text = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(
        r"static\s+const\s+int8_t\s+(\w+)\s*\[\s*16\s*\]\s*=\s*\{(.*?)\}\s*;",
        text, re.S,
    ):
        name, body = m.group(1), m.group(2)
        body = re.sub(r"//[^\n]*", "", body)
        body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
        vals = [int(v) for v in re.findall(r"-?\d+", body)]
        if len(vals) != 16:
            raise ValueError("%s 初值不是 16 个：%r" % (name, vals))
        if any(v < -128 or v > 127 for v in vals):
            raise ValueError("%s 有超出 int8 的初值：%r" % (name, vals))
        out[name] = vals
    need = {"dc_a", "dc_b"}
    missing = need - set(out)
    if missing:
        raise ValueError("源里缺数组：%s" % ", ".join(sorted(missing)))
    return out


def reg128(lanes16):
    v = 0
    for i, b in enumerate(lanes16):
        v |= (b & MASK8) << (8 * i)
    return v


def lanes_of(reg):
    return [(reg >> (8 * i)) & MASK8 for i in range(16)]


def s8(x):
    return x - 256 if x >= 128 else x


# --------------------------------------------------------------------------
# 逐链模拟（与 vdot_dualchain.c 的 asm 序列逐条对应；M1..M8）
# --------------------------------------------------------------------------
def vmacc_step(old_reg, x_reg, y_reg):
    old = lanes_of(old_reg)
    xs = [s8(v) for v in lanes_of(x_reg)]
    ys = [s8(v) for v in lanes_of(y_reg)]
    return reg128([(old[i] + xs[i] * ys[i]) & MASK8 for i in range(16)])


def vadd_step(old_reg, x_reg):
    old = lanes_of(old_reg)
    xs = [s8(v) for v in lanes_of(x_reg)]
    return reg128([(old[i] + xs[i]) & MASK8 for i in range(16)])


def vadd2_step(x_reg, y_reg):
    xs = [s8(v) for v in lanes_of(x_reg)]
    ys = [s8(v) for v in lanes_of(y_reg)]
    return reg128([(xs[i] + ys[i]) & MASK8 for i in range(16)])


def m1_vdot_selfalias(model, n, a_reg):
    """vdot.vv v10, v10, v1 —— 自别名：vd==vs2（指令内 WAR + 跨指令真 RAW）。"""
    v = a_reg
    for _ in range(n):
        v = model.vdot_vv(v, a_reg)
    return v


def m2_vdot_dual(model, n, a_reg):
    """vdot.vv v11,v10,v1 / vdot.vv v10,v11,v1 交替，**一个 n 步 = 这两条**（与 C 的
    STEP_M2 逐条对应：一次循环体里先写 v11 再写 v10，共 2 条指令）。

    2026-11-06 首跑修正：旧版把「一个 n 步」写成只发一条（按 i 的奇偶交替），与 C 的
    STEP_M2（每步两条）差一倍 ⇒ M2_v10/M2_v11 四条功能自检全红。"""
    v10 = a_reg
    v11 = a_reg
    for _ in range(n):
        v11 = model.vdot_vv(v10, a_reg)   # vdot.vv v11, v10, v1
        v10 = model.vdot_vv(v11, a_reg)   # vdot.vv v10, v11, v1
    return v10, v11


def m3_vdot_indep(model, a_reg, b_reg, old_vd):
    """vdot.vv v3, v1, v2 —— 无数据依赖（源常量、vd 固定不被读）；结果与次数/旧 vd 无关。"""
    return model.vdot_vv(a_reg, b_reg, old_vd=old_vd)


def m4_vmacc_selfalias(n, a_reg):
    """vmacc.vv v10, v1, v10 —— 对照组：old_vd 是语义输入且 vd==vs2。"""
    v = a_reg
    for _ in range(n):
        v = vmacc_step(v, a_reg, v)
    return v


def m5_vmacc_oldonly(n, a_reg, b_reg):
    """vmacc.vv v10, v1, v2 —— 对照组：串行源只有 old_vd（vs2 是常量）。"""
    v = a_reg
    for _ in range(n):
        v = vmacc_step(v, a_reg, b_reg)
    return v


def m6_vadd_selfalias(n, a_reg):
    """vadd.vv v10, v10, v1 —— 非 vimac 的 ALU 参照链（旧 vd 也是语义输入）。"""
    v = a_reg
    for _ in range(n):
        v = vadd_step(v, a_reg)
    return v


def m7_vadd_constsources(a_reg, b_reg):
    """vadd.vv v3, v1, v2 —— 无依赖地板（源常量、vd 固定不被读，走 vialuF）。"""
    return vadd2_step(a_reg, b_reg)


def m8_vdot_rotating(model, n, a_reg, b_reg):
    """vdot.vv v8..v15 轮流写、源常量 —— 无依赖且不同 vd（释放同号 WAW 压力）。
    与 M3（同一 vd）比：若 vdRen=T 造成 WAW 串行，M3 会明显慢于 M8。"""
    regs = [a_reg] * 8
    for i in range(n):
        regs[i % 8] = model.vdot_vv(a_reg, b_reg)
    return regs


def build_expectations(arrays):
    model = load_model()
    a = reg128(arrays["dc_a"])
    b = reg128(arrays["dc_b"])
    pre = reg128([PREFILL] * 16)

    exp = {}
    exp["M1"] = m1_vdot_selfalias(model, N_FUNC, a)
    exp["M1_alt"] = m1_vdot_selfalias(model, N_ALT, a)
    v10, v11 = m2_vdot_dual(model, N_FUNC, a)
    exp["M2_v10"] = v10
    exp["M2_v11"] = v11
    v10b, v11b = m2_vdot_dual(model, N_ALT2, a)
    exp["M2_v10_alt"] = v10b
    exp["M2_v11_alt"] = v11b
    exp["M3"] = m3_vdot_indep(model, a, b, 0)
    exp["M3b"] = m3_vdot_indep(model, a, b, pre)
    exp["M4"] = m4_vmacc_selfalias(N_FUNC, a)
    exp["M4_alt"] = m4_vmacc_selfalias(N_ALT, a)
    exp["M5"] = m5_vmacc_oldonly(N_FUNC, a, b)
    exp["M5_alt"] = m5_vmacc_oldonly(N_ALT, a, b)
    exp["M6"] = m6_vadd_selfalias(N_FUNC, a)
    exp["M6_alt"] = m6_vadd_selfalias(N_ALT, a)
    exp["M7"] = m7_vadd_constsources(a, b)          # 与次数无关 ⇒ 无 alt
    exp["M8"] = m8_vdot_rotating(model, N_FUNC, a, b)[N_FUNC % 8]

    # 比对字节数：vdot 写满 128 位 ⇒ 16；vmacc/vadd 的 lane 8..15 是 tail（ta 未定义）⇒ 8
    clen = {
        "M1": 16, "M1_alt": 16,
        "M2_v10": 16, "M2_v11": 16, "M2_v10_alt": 16, "M2_v11_alt": 16,
        "M3": 16, "M3b": 16,
        "M4": 8, "M4_alt": 8,
        "M5": 8, "M5_alt": 8,
        "M6": 8, "M6_alt": 8,
        "M7": 8,
        "M8": 16,
    }
    return model, exp, clen


def falsifiability_problems(model, arrays, exp):
    """可证伪性守卫：每条链的期望必须在「正确」与「最可能的故障模型」之间可分。"""
    a = reg128(arrays["dc_a"])
    b = reg128(arrays["dc_b"])
    pre = reg128([PREFILL] * 16)
    p = []
    # 1) 长度判别：N 与 N-1（M2 为 N-2）的期望必须不同
    for tag, alt in (("M1", "M1_alt"), ("M4", "M4_alt"), ("M5", "M5_alt"), ("M6", "M6_alt")):
        if exp[tag] == exp[alt]:
            p.append("%s：N=%d 与 N-1 期望相同 ⇒ 长度不可分辨" % (tag, N_FUNC))
    for tag, alt in (("M2_v10", "M2_v10_alt"), ("M2_v11", "M2_v11_alt")):
        if exp[tag] == exp[alt]:
            p.append("%s：N=%d 与 N-2 期望相同 ⇒ 长度不可分辨" % (tag, N_FUNC))
    # 2) 自别名链 N 次必须与 1 次不同
    if exp["M1"] == model.vdot_vv(a, a):
        p.append("M1：N=%d 与 1 次相同 ⇒ 链没真跑满" % N_FUNC)
    # 3) M3 反累加：正确值必须 ≠「旧 vd 每拍累加 dot(a,b)」的故障值，且 M3 == M3b
    acc_mutant = (0xABABABAB + N_FUNC * 8) & 0xFFFFFFFF
    if (exp["M3"] & 0xFFFFFFFF) == acc_mutant:
        p.append("M3：反累加故障值与正确值相同 ⇒ 抓不到「读旧 vd 累加」")
    if exp["M3"] != exp["M3b"]:
        p.append("M3 与 M3b（旧 vd 预填 0xAB）期望不同 ⇒ 金模型自身违反「旧 vd 非输入」")
    # 4) M3 == 单次 dot(a,b)（与次数无关）
    if exp["M3"] != model.vdot_vv(a, b):
        p.append("M3：与单次 vdot 期望不同 ⇒ 「与次数无关」不成立")
    # 5) 对照组必须读旧 vd：M5 预填不同值结果必须不同
    if m5_vmacc_oldonly(1, pre, b) == m5_vmacc_oldonly(1, a, b):
        p.append("M5：旧 vd 换成 0xAB 后结果不变 ⇒ 对照链的 old_vd 未被使用")
    if exp["M5"] == vmacc_step(a, a, b):
        p.append("M5：N=%d 与 1 次相同 ⇒ vmacc 对照链失去区分力" % N_FUNC)
    # 6) M7（vadd 常量源）与 M3（vdot 常量源）必须功能上可分
    if exp["M7"] == exp["M3"]:
        p.append("M7 与 M3 期望相同 ⇒ 两条链功能上不可分辨")
    # 7) M8 与 M3 都是 dot(a,b)（无依赖语义自洽）；M1 与 M3 必须不同（有/无依赖可分）
    if exp["M8"] != exp["M3"]:
        p.append("M8 与 M3 期望不同 ⇒ 两者都是 dot(a,b)，金模型自相矛盾")
    if exp["M1"] == exp["M3"]:
        p.append("M1 与 M3 期望相同 ⇒ 有依赖/无依赖功能上不可分辨")
    return p


def emit_header(path, exp, clen):
    lines = []
    lines.append("/* 由 design/verify/cases/dualchain_check.py --emit-header 生成，勿手改。")
    lines.append(" * 期望值来源：design/verify/vdot_model.py（vdot 步）+ 标准 RVV 逐 lane 复算（vmacc/vadd 步）。")
    lines.append(" * 链规模：N_FUNC=%d / N_ALT=%d / N_ALT2=%d / N_WARMUP=%d / N_REPS=%d / N_ROUNDS=%d / NREP=%d,%d。"
                 % (N_FUNC, N_ALT, N_ALT2, N_WARMUP, N_REPS, N_ROUNDS, NREP_LO, NREP_HI))
    lines.append(" */")
    lines.append("#ifndef DUALCHAIN_EXPECTED_H")
    lines.append("#define DUALCHAIN_EXPECTED_H")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("#define DC_N_FUNC    %d" % N_FUNC)
    lines.append("#define DC_N_ALT     %d" % N_ALT)
    lines.append("#define DC_N_ALT2    %d" % N_ALT2)
    lines.append("#define DC_N_WARMUP  %d" % N_WARMUP)
    lines.append("#define DC_NREP_LO   %d" % NREP_LO)
    lines.append("#define DC_NREP_HI   %d" % NREP_HI)
    lines.append("#define DC_N_REPS    %d" % N_REPS)
    lines.append("#define DC_N_ROUNDS  %d" % N_ROUNDS)
    lines.append("")
    for tag in sorted(exp):
        bl = lanes_of(exp[tag])
        body = ", ".join("0x%02X" % x for x in bl)
        lines.append("static const uint8_t DCW_%s[16] = {%s};" % (tag, body))
        lines.append("#define DC_CHECKLEN_%s %d" % (tag, clen[tag]))
    lines.append("")
    payload = "\n".join(lines)
    digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    lines.append('#define DUALCHAIN_EXPECTED_SHA256 "%s"' % digest)
    lines.append("")
    lines.append("#endif /* DUALCHAIN_EXPECTED_H */")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return digest


def hexbytes(bs, n):
    return " ".join("%02X" % b for b in bs[:n])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit-header", metavar="OUT_H", help="生成 C 头文件（期望值来自金模型）")
    ap.add_argument("--check-log", metavar="LOG", help="用例日志，逐行比对")
    args = ap.parse_args()
    if not args.emit_header and not args.check_log:
        ap.error("至少给 --emit-header 或 --check-log")

    arrays = parse_arrays(SRC)
    model, exp, clen = build_expectations(arrays)

    problems = falsifiability_problems(model, arrays, exp)
    if problems:
        print("DUALCHAIN_CROSSCHECK FALSIFIABILITY_BAD: " + "; ".join(problems))
        return 1
    print("DUALCHAIN_CROSSCHECK falsifiable=YES chains=8")

    want_lines = {}
    for tag in sorted(exp):
        want_lines[tag] = hexbytes(lanes_of(exp[tag]), clen[tag])
        print("DUALCHAIN_CROSSCHECK want %-12s checklen=%2d [%s]"
              % (tag, clen[tag], want_lines[tag]))

    if args.emit_header:
        digest = emit_header(args.emit_header, exp, clen)
        print("DUALCHAIN_CROSSCHECK header=%s sha256=%s" % (args.emit_header, digest))

    if args.check_log:
        log = open(args.check_log, encoding="utf-8", errors="replace").read()
        bad = 0
        seen = set()
        for m in re.finditer(r"^DUALCHAIN (\w+) func .*?want=\[([0-9A-F ]*)\]", log, re.M):
            tag, want = m.group(1), m.group(2).strip()
            seen.add(tag)
            if tag not in want_lines:
                print("DUALCHAIN_CROSSCHECK UNKNOWN_TAG: %s" % tag)
                bad += 1
                continue
            if want != want_lines[tag]:
                print("DUALCHAIN_CROSSCHECK WANT_MISMATCH %s log=[%s] model=[%s]"
                      % (tag, want, want_lines[tag]))
                bad += 1
        missing = sorted(set(want_lines) - seen)
        if missing:
            print("DUALCHAIN_CROSSCHECK MISSING_FUNC_LINES: %s" % ",".join(missing))
            bad += 1
        for m in re.finditer(r"^DUALCHAIN (\w+) func .*?bytes_bad=(\d+)", log, re.M):
            if m.group(2) != "0":
                print("DUALCHAIN_CROSSCHECK BYTES_BAD: %s bytes_bad=%s" % (m.group(1), m.group(2)))
                bad += 1
        # 八条链的依赖间隔行必须齐全
        dep = set(re.findall(r"^DUALCHAIN (M\d) dep ", log, re.M))
        need = {"M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8"}
        if not need <= dep:
            print("DUALCHAIN_CROSSCHECK MISSING_DEP_LINES: %s" % ",".join(sorted(need - dep)))
            bad += 1
        if "DUALCHAIN verdict=ALL_OK" not in log:
            print("DUALCHAIN_CROSSCHECK MISSING_VERDICT")
            bad += 1
        if bad:
            print("DUALCHAIN_CROSSCHECK verdict=LOG_MISMATCH problems=%d" % bad)
            return 1
        print("DUALCHAIN_CROSSCHECK verdict=LOG_MATCH chains=%d dep_lines=%d"
              % (len(want_lines), len(dep)))
    return 0


if __name__ == "__main__":
    sys.exit(main())