#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""xcontam_crosscheck.py — vdot_xcontam 用例的「金模型侧独立复算」。

与 design/verify/cases/vdot_xcontam.c **逐位同构**，但期望值不抄 C 里的算法，而是：
  * 操作数数组直接从 .c 源里**解析**（不手抄，避免转录错误）；
  * vdot 步用金模型 `design/verify/vdot_model.py` 的 `vdot_vv()`（M08：返回完整 128 位 vd）；
  * vmacc 步按标准 RVV 语义逐 lane 复算：vd[i] = old_vd[i] + vs1[i]*vs2[i]，SEW=8 模 2^8；
  * 打印与用例日志同名同格式的期望行，便于逐行对照 difftest 日志。

用法：
    python3 design/verify/cases/xcontam_crosscheck.py                  # 打印期望行
    python3 design/verify/cases/xcontam_crosscheck.py --check-log L    # 与 difftest 日志逐行比对

判据：`--check-log` 全部命中 ⇒ 金模型 == 用例自检期望 == DUT/NEMU 实测（0 ABORT 另由 difftest 判）。
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, os.pardir, "vdot_model.py")
SRC = os.path.join(HERE, "vdot_xcontam.c")

PREFILL = 0xAB
MASK8 = 0xFF


def load_model():
    spec = importlib.util.spec_from_file_location("vdot_model", MODEL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_arrays(path):
    """从 .c 源解析 `static volatile int8_t NAME[16] = {...};` 的初值。"""
    text = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(
        r"static\s+volatile\s+int8_t\s+(\w+)\s*\[\s*16\s*\]\s*=\s*\{(.*?)\}\s*;",
        text,
        re.S,
    ):
        name, body = m.group(1), m.group(2)
        body = re.sub(r"//[^\n]*", "", body)
        vals = [int(v) for v in re.findall(r"-?\d+", body)]
        if len(vals) != 16:
            raise ValueError("%s 初值不是 16 个：%r" % (name, vals))
        if any(v < -128 or v > 127 for v in vals):
            raise ValueError("%s 有超出 int8 的初值：%r" % (name, vals))
        out[name] = vals
    need = {"d1a", "d1b", "d2a", "d2b", "mp", "mq"}
    missing = need - set(out)
    if missing:
        raise ValueError("源里缺数组：%s" % ", ".join(sorted(missing)))
    return out


def reg128(lanes16):
    """16 个 int8 lane → 128 位寄存器值（小端，lane i = bits [8i+7:8i]）。"""
    v = 0
    for i, b in enumerate(lanes16):
        v |= (b & MASK8) << (8 * i)
    return v


def lanes_of(reg):
    return [(reg >> (8 * i)) & MASK8 for i in range(16)]


def vdot_step(model, a, b):
    """金模型 vdot：S = Σ sext8(a[i])*sext8(b[i])，只取 lane 0..7。"""
    vd = model.vdot_vv(reg128(a), reg128(b))
    return vd


def vmacc_step(old_reg, x, y):
    """标准 RVV vmacc.vv，SEW=8 逐 lane 模 2^8。"""
    old = lanes_of(old_reg)
    new = [((old[i] + x[i] * y[i]) & MASK8) for i in range(16)]
    return reg128(new)


def hexbytes(bs):
    return " ".join("%02X" % b for b in bs)


def check_prefill_consistency(path):
    """校验 .c 里 b0/b3/b4 的 `vmv.v.x v3, %[pf]` 预填写法（两端口径漂移即报错）。

    为什么要查：预填值本身不参与可证伪性（b0/b3/b4 读旧 vd 前都有全写指令或首条就是全写），
    但 .c 若悄悄删掉/改错预填，本脚本此前无法察觉（b0 故障模型恒等于 macc(vdot(S1)），
    与初值无关）。返回 (ok, detail)。
    """
    text = open(path, encoding="utf-8").read()
    m = re.search(r"#define\s+PREFILL\s+0x([0-9A-Fa-f]+)u", text)
    if not m:
        return False, "找不到 `#define PREFILL`"
    pref = int(m.group(1), 16)
    if pref != PREFILL:
        return False, "PREFILL 定义 0x%02X != 脚本常量 0x%02X" % (pref, PREFILL)
    problems = []
    for name in ("b0", "b3", "b4"):
        i = text.find("// ---- %s：" % name)
        j = text.find("// ---- b", i + 10)
        blk = text[i:j if j > 0 else len(text)]
        if '"vmv.v.x v3, %[pf]\\n\\t"' not in blk:
            problems.append("%s 缺 `vmv.v.x v3, %%[pf]` 预填" % name)
        if "uint32_t pf = PREFILL;" not in blk:
            problems.append("%s 缺 `uint32_t pf = PREFILL;`" % name)
    if problems:
        return False, "; ".join(problems)
    return True, "b0/b3/b4 各含 `vmv.v.x v3, %%[pf]` + `pf = PREFILL`（0x%02X）" % pref

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-log", metavar="LOG", help="difftest 用例日志，逐行比对")
    args = ap.parse_args()

    model = load_model()
    arr = parse_arrays(SRC)
    d1a, d1b, d2a, d2b = arr["d1a"], arr["d1b"], arr["d2a"], arr["d2b"]
    mp, mq = arr["mp"], arr["mq"]

    vd1 = vdot_step(model, d1a, d1b)
    vd2 = vdot_step(model, d2a, d2b)
    w1, w2 = vd1 & 0xFFFFFFFF, vd2 & 0xFFFFFFFF
    # 金模型的完整 128 位：高 96 位必须为 0（SPEC §1.1）
    hi1, hi2 = vd1 >> 32, vd2 >> 32

    # 由 vdot_model.dot_product() 复核 S 本身（与 vd 位型分开算，双路径交叉）
    s1 = model.dot_product(reg128(d1a), reg128(d1b))
    s2 = model.dot_product(reg128(d2a), reg128(d2b))

    old1 = vd1                                  # b1/b3 的「中间那条 vdot」写回值
    macc1 = vmacc_step(old1, mp, mq)            # b1 step2 / b3 exp
    old_pref = reg128([PREFILL] * 16)
    macc_pref = vmacc_step(old_pref, mp, mq)    # 只用来证明「读到上一条 vmacc」会红
    # b3 的「旧 vd 读错一条」替代答案：vmacc#2 若把 vmacc#1 的结果当旧 vd
    macc_pref2 = vmacc_step(macc_pref, mp, mq)

    lines = []
    lines.append("XCONTAM SETUP S1=%d w1=0x%08X S2=%d w2=0x%08X" % (s1, w1, s2, w2))
    lines.append("XCONTAM b0 vdot->vmacc->vdot got=0x%08X want=0x%08X hi96_bad=0 OK" % (w2, w2))
    lines.append("XCONTAM b1 step1 got=0x%08X want=0x%08X hi96_bad=0" % (w1, w1))
    lines.append("XCONTAM b1 step2 bytes_bad=0")
    lines.append("XCONTAM b1 step3 got=0x%08X want=0x%08X hi96_bad=0 OK" % (w2, w2))
    lines.append("XCONTAM b1 step2 got=[%s] exp=[%s]"
                 % (hexbytes(lanes_of(macc1)), hexbytes(lanes_of(macc1))))
    lines.append("XCONTAM b2 vdot->vdot got=0x%08X want=0x%08X hi96_bad=0 OK" % (w2, w2))
    lines.append("XCONTAM b2b vdot(S2)->vdot(S1) got=0x%08X want=0x%08X hi96_bad=0 OK" % (w1, w1))
    lines.append("XCONTAM b3 vmacc->vdot->vmacc bytes_bad=0 OK")
    lines.append("XCONTAM b3 got=[%s] exp=[%s]"
                 % (hexbytes(lanes_of(macc1)), hexbytes(lanes_of(macc1))))
    lines.append("XCONTAM b4 vmacc->vdot got=0x%08X want=0x%08X hi96_bad=0 OK" % (w2, w2))
    lines.append("XCONTAM verdict=ALL_OK fails=0")

    for ln in lines:
        print(ln)

    # ---- 可证伪性守卫：本用例的全部判据依赖「各步期望位型两两不同」----
    problems = []
    # 预填口径校验：b0/b3/b4 的 `vmv.v.x v3, %[pf]` 若被删/被改值，本脚本必须报出来
    # （否则「预填是口径统一的一部分」这句话没有任何机械判据支撑）
    pf_ok, pf_detail = check_prefill_consistency(SRC)
    if not pf_ok:
        problems.append("预填口径与 .c 不一致：" + pf_detail)
    if w1 == w2:
        problems.append("w1 == w2（两条 vdot 期望重合，「写回上一条」不可分辨）")
    if hi1 != 0 or hi2 != 0:
        problems.append("金模型高 96 位非零：hi1=0x%X hi2=0x%X" % (hi1, hi2))
    if macc1 == vd1:
        problems.append("vmacc 期望 == vdot 期望（b1 的中间态不可分辨）")
    if macc1 == vd2:
        problems.append("vmacc 期望 == 后一条 vdot 期望（b1 的终值不可分辨）")
    # 「误读上一条 vmacc」的替代答案必须与正确期望不同，否则 b3/b4 抓不到污染
    if macc_pref == macc1:
        problems.append("b3：误读旧 vmacc 与正确期望相同 ⇒ 抓不到污染")
    if macc_pref == vd2:
        problems.append("b4：误读旧 vmacc 与 vdot 期望相同 ⇒ 抓不到污染")
    if macc_pref2 == macc1:
        problems.append("b3：把 vmacc#1 结果当旧 vd 的替代答案与正确期望相同 ⇒ 抓不到")
    # b1 step2 的期望必须与「上一条 vdot 的位型」可分辨（lane 4..15 不为零即可）
    if all(b == 0 for b in lanes_of(macc1)[4:]):
        problems.append("b1 step2：lane 4..15 全零，与 vdot 位型同形 ⇒ 不可分辨")
    # 干扰 lane 8..15 必须非零，否则「高 64 位不参与」这条没被测到
    for nm, a, b in (("d1", d1a, d1b), ("d2", d2a, d2b)):
        if any(a[i] == 0 or b[i] == 0 for i in range(8, 16)):
            problems.append("%s：lane 8..15 有零操作数，干扰不充分" % nm)

    # ---- R13 故障模型仿真：每条指令写回的是**上一条** vimac 的结果（fireS1 误用 valid 的症状）----
    # 逐块检查「正确期望」与「上一条结果」是否不同；任何一块相同 ⇒ 该块抓不到 R13，记为问题。
    # 关于 b0/b1 的预填（2026-11-06 更正）：**两段的首条指令都是 vdot（全写 vd，SPEC §1.1 不读旧
    # vd），故「写回上一条」的故障值恒为 vdot(S1)，与进入该段时 v3 的残余值无关** ⇒ 预填不参与可
    # 证伪性（实测：把 b0 初值换成 0 / 0xAB / F8 10 27 … / None，`detectable` 全部为 True）。
    # .c 里给 b0 补 `vmv.v.x v3, 0xAB` 是为与 b3/b4 统一口径、消除「v3 残余值不可控」的歧义，
    # **不是**补一个会让该段虚假通过的缺口。下面仍按 .c 的实际进入值建模（同口径），并由
    # `check_prefill_consistency()` 校验 .c 的预填写法，防止两端口径漂移。
    r13 = []
    blocks = [
        # (块名, 指令序列, 初始旧 vd)
        ("b0", [("vdot", (d1a, d1b)), ("vmacc", None), ("vdot", (d2a, d2b))], old_pref),
        ("b2", [("vdot", (d1a, d1b)), ("vdot", (d2a, d2b))], None),
        ("b2b", [("vdot", (d2a, d2b)), ("vdot", (d1a, d1b))], None),
        ("b3", [("vmacc", None), ("vdot", (d1a, d1b)), ("vmacc", None)], old_pref),
        ("b4", [("vmacc", None), ("vdot", (d2a, d2b))], old_pref),
    ]
    for name, seq, old0 in blocks:
        hist = []
        cur = old0
        for kind, arg in seq:
            cur = vdot_step(model, arg[0], arg[1]) if kind == "vdot" else vmacc_step(cur, mp, mq)
            hist.append(cur)
        correct, faulty = hist[-1], hist[-2]
        det = correct != faulty
        r13.append((name, correct, faulty, det))
        if not det:
            problems.append("%s：故障模型（写回上一条）与正确值相同 ⇒ 抓不到 R13" % name)
    # b1 逐步（含 bubble）：step2 的上一条 = step1 的 vdot；step3 的上一条 = step2 的 vmacc
    step1 = vd1
    step2 = macc1
    step3 = vd2
    for name, correct, faulty in (("b1.step2", step2, step1), ("b1.step3", step3, step2)):
        det = correct != faulty
        r13.append((name, correct, faulty, det))
        if not det:
            problems.append("%s：故障模型（写回上一条）与正确值相同 ⇒ 抓不到 R13" % name)

    if problems:
        print("XCONTAM_CROSSCHECK FALSIFIABILITY_BAD: " + "; ".join(problems))
        return 1
    for name, correct, faulty, det in r13:
        print("XCONTAM_CROSSCHECK R13 %-9s correct=0x%032X prev=0x%032X detectable=%s"
              % (name, correct, faulty, "YES" if det else "NO"))
    print("XCONTAM_CROSSCHECK prefill=%s" % pf_detail)
    print("XCONTAM_CROSSCHECK falsifiable=YES vd1_hi96=0x%024X vd2_hi96=0x%024X"
          % (hi1, hi2))

    if args.check_log:
        log = open(args.check_log, encoding="utf-8", errors="replace").read()
        bad = 0
        for ln in lines:
            # 日志里 printf 的实际格式与上面同构；逐行整串匹配（去掉可能的 \r）
            if ln not in log:
                print("XCONTAM_CROSSCHECK MISSING: %s" % ln)
                bad += 1
        if bad:
            print("XCONTAM_CROSSCHECK verdict=LOG_MISMATCH missing=%d" % bad)
            return 1
        print("XCONTAM_CROSSCHECK verdict=LOG_MATCH lines=%d" % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
