#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""extra_crosscheck.py — 扩容用例的「期望值来源」机械复核。

它回答一个问题：**`manifest.extra.tsv` 里每一行镜像的期望值，是不是真的由
`design/verify/vdot_model.py` 算出来的？**

做法（不重复实现点积，全部调金模型）：
  1. 读 `extra/spec.extra.json`（用例清单）与 `extra/<cid>.c`（生成物）；
  2. 从 C 源的 `//@OP ...` 注释逐条重放指令序列：`load` 取 .c 里的数组初值，
     `vdot` 调 `M.vdot_vv(vs1, vs2)`，`vadd`/`vmacc` 按标准 RVV 语义推进（只为占写回口）；
  3. 把重放得到的期望与 C 源里**实际烧进去的断言常量**（`if (got[i] != 0x........u)`）
     逐条比对 —— 不一致即说明「期望常量不是金模型算的」；
  4. 用 `M.decode_vdot_vv()` 反解每条 `vdot` 的机器码，确认 `(vd, vs2, vs1)` 与注释一致；
  5. 负例：用 `M.illegal_reasons()` 确认该用例构造的状态**确实非法**，且机器码确实是 vdot
     （`vm=0` 那条除外，它靠解码不命中）；
  6. `vdot_rand10k`：用同一 LCG 重算 10000 组，与镜像里 `want10k[]` 逐组比对。

判据：`全部命中 ⇒ verdict=MATCH`；任一不一致 ⇒ `verdict=MISMATCH ...` 且退出码 1。
用法：
    python3 design/verify/cases/extra_crosscheck.py            # 全量复核
    python3 design/verify/cases/extra_crosscheck.py --quiet     # 只打汇总
退出码：0 一致 / 1 不一致 / 3 用法或前置错误
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXTRA = os.path.join(HERE, "extra")
SPEC = os.path.join(EXTRA, "spec.extra.json")
# 清单定位：显式环境变量 > 与本脚本同目录（仓库布局） > 集群部署目录 $CORE_DIR/test/
MANIFEST = os.environ.get("EXTRA_MANIFEST") or next(
    (p for p in (os.path.join(HERE, "manifest.extra.tsv"),
                 os.path.join(HERE, os.pardir, os.pardir, "test", "manifest.extra.tsv"))
     if os.path.isfile(p)),
    os.path.join(HERE, "manifest.extra.tsv"),
)

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "vdot_model", os.path.join(os.path.dirname(HERE), "vdot_model.py"))
M = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(M)


def reg128(lanes):
    v = 0
    for i, b in enumerate(lanes):
        v |= (b & 0xFF) << (8 * i)
    return v


def parse_arrays(text):
    """从 .c 源解析 `static volatile int8_t opN[16] = {...};` 的初值。"""
    out = {}
    for m in re.finditer(r"static\s+volatile\s+int8_t\s+(\w+)\[16\]\s*=\s*\{(.*?)\}\s*;", text, re.S):
        vals = [int(v) for v in re.findall(r"-?\d+", m.group(2))]
        if len(vals) != 16:
            raise ValueError("数组 %s 初值不是 16 个" % m.group(1))
        out[m.group(1)] = vals
    return out


def replay(text, arrs):
    """重放 //@OP 注释，返回 {read_idx: (want32, hi_zero)} 与 vdot 编码校验结果。"""
    regs = {}
    reads = {}
    enc_bad = []
    for line in text.split("\n"):
        if "//@OP " not in line:
            continue
        body = line.split("//@OP ", 1)[1].strip()
        tok = body.split()
        if not tok:
            continue
        kind = tok[0]
        kv = dict(t.split("=", 1) for t in tok[1:] if "=" in t)
        if kind == "load":
            vd = int(tok[1][1:])
            regs[vd] = reg128(arrs[kv["arr"]])
        elif kind == "vmv":
            vd = int(tok[1][1:])
            imm = int(kv["imm"], 16)
            regs[vd] = imm * 0x01010101010101010101010101010101
        elif kind == "vdot":
            vd, vs1, vs2 = int(kv["vd"]), int(kv["vs1"]), int(kv["vs2"])
            w = int(kv["enc"], 16)
            dec = M.decode_vdot_vv(w)
            if dec != (vd, vs2, vs1):
                enc_bad.append((vd, vs1, vs2, kv["enc"], dec))
            regs[vd] = M.vdot_vv(regs.get(vs1, 0), regs.get(vs2, 0))
        elif kind == "vdot(SKIPPED)":
            # 被 taken jal 跳过：不执行、不写回（金模型按「不执行」推进）
            continue
        elif kind == "vadd":
            vd, vs1, vs2 = int(kv["vd"]), int(kv["vs1"]), int(kv["vs2"])
            x, y = regs.get(vs1, 0), regs.get(vs2, 0)
            out = 0
            for i in range(16):
                out |= (((x >> (8 * i)) + (y >> (8 * i))) & 0xFF) << (8 * i)
            regs[vd] = out
        elif kind == "vmacc":
            vd, vs1, vs2 = int(kv["vd"]), int(kv["vs1"]), int(kv["vs2"])
            old, x, y = regs.get(vd, 0), regs.get(vs1, 0), regs.get(vs2, 0)
            out = 0
            for i in range(16):
                ob = (old >> (8 * i)) & 0xFF
                xb = M.sext((x >> (8 * i)) & 0xFF, 8)
                yb = M.sext((y >> (8 * i)) & 0xFF, 8)
                out |= ((ob + xb * yb) & 0xFF) << (8 * i)
            regs[vd] = out
        elif kind == "read":
            idx = int(kv["idx"])
            vd = int(kv["vd"])
            want = regs.get(vd, 0)
            reads[idx] = (want & 0xFFFFFFFF, 1 if (want >> 32) == 0 else 0)
    return reads, enc_bad


def emitted_constants(text):
    """取出 C 里实际烧进去的断言常量：if (got[i] != 0x........u)。"""
    out = {}
    for m in re.finditer(r"if\s*\(\s*got\[(\d+)\]\s*!=\s*0x([0-9A-Fa-f]{8})u\s*\)", text):
        out[int(m.group(1))] = int(m.group(2), 16)
    return out


def check_rand10k(text):
    """重算 10000 组 LCG，与镜像 want10k[] 逐组比对。"""
    m = re.search(r"#define GROUPS (\d+)", text)
    if not m:
        return None, "缺 #define GROUPS"
    groups = int(m.group(1))
    m = re.search(r"uint32_t seed = (\d+)u;", text)
    if not m:
        return None, "缺 seed 字面量"
    seed = int(m.group(1))
    m = re.search(r"want10k\[GROUPS\]\s*=\s*\{(.*?)\};", text, re.S)
    if not m:
        return None, "缺 want10k 数组"
    wants = [int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{8})u", m.group(1))]
    if len(wants) != groups:
        return None, "want10k 长度 %d != GROUPS %d" % (len(wants), groups)
    s = seed & 0xFFFFFFFF
    bad = 0
    for g in range(groups):
        a, b = [], []
        for _ in range(16):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            a.append(M.sext(s >> 24, 8))
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            b.append(M.sext(s >> 16, 8))
        if (M.vdot_vv(reg128(a), reg128(b)) & 0xFFFFFFFF) != wants[g]:
            bad += 1
    return (groups, bad), None


def check_negative(text, spec_case):
    """负例：机器码是 vdot 且模型判非法；vm=0 那条靠解码不命中。"""
    encs = re.findall(r"\.4byte 0x([0-9A-Fa-f]{8})\\n", text)
    if not encs:
        return ["缺 .4byte 机器码"]
    w = int(encs[-1], 16)
    dec = M.decode_vdot_vv(w)
    cid = spec_case["cid"]
    note = spec_case["note"]
    reasons = []
    if "vm=0" in note:
        if dec is not None:
            reasons.append("vm=0 用例的机器码仍被解成 vdot：0x%08X" % w)
        return reasons
    if dec is None:
        reasons.append("机器码 0x%08X 不是 vdot.vv" % w)
        return reasons
    # 从 note 里解析出非法维度，交给模型判定
    kwargs = {}
    m = re.search(r"SEW=(\w+)", note)
    if m:
        kwargs["sew"] = {"e8": 8, "e16": 16, "e32": 32, "e64": 64}[m.group(1)]
    m = re.search(r"LMUL=(\w+)", note)
    if m:
        kwargs["lmul"] = {"m1": 1, "m2": 2, "m4": 4, "m8": 8,
                          "mf8": 0.125, "mf4": 0.25, "mf2": 0.5}[m.group(1)]
    m = re.search(r"vstart=(\d+)", note)
    if m:
        kwargs["vstart"] = int(m.group(1))
    if "vill=1" in note:
        kwargs["vill"] = True
    if "VS=OFF" in note:
        kwargs["mstatus_vs"] = M.MSTATUS_VS_OFF
    if not kwargs:
        reasons.append("无法从 note 判定非法维度：%s" % note)
        return reasons
    if not M.illegal_reasons(**kwargs):
        reasons.append("模型认为该组合合法（note=%s, kwargs=%r）" % (note, kwargs))
    return reasons


def main():
    quiet = "--quiet" in sys.argv
    if not os.path.isfile(SPEC):
        print("[FATAL] 缺 %s（先跑 gen_extra.py）" % SPEC, file=sys.stderr)
        return 3
    spec = json.load(open(SPEC, encoding="utf-8"))
    cases = spec["cases"]
    problems = []
    checked_reads = 0
    checked_enc = 0
    for c in cases:
        cid = c["cid"]
        path = os.path.join(EXTRA, cid + ".c")
        if not os.path.isfile(path):
            problems.append("%s: 缺源 %s" % (cid, path))
            continue
        text = open(path, encoding="utf-8").read()
        if c["cls"] == "negative":
            for p in check_negative(text, c):
                problems.append("%s: %s" % (cid, p))
            continue
        if c["cls"] == "vdot-rand10k":
            res, err = check_rand10k(text)
            if err:
                problems.append("%s: %s" % (cid, err))
            else:
                groups, bad = res
                checked_reads += groups
                if bad:
                    problems.append("%s: %d/%d 组与金模型不一致" % (cid, bad, groups))
                elif not quiet:
                    print("  %-18s rand10k groups=%d bad=0" % (cid, groups))
            continue
        if c["family"] == "loop":
            m = re.search(r"const uint32_t want = 0x([0-9A-Fa-f]{8})u;", text)
            if not m:
                problems.append("%s: 缺 want 常量" % cid)
                continue
            arrs = parse_arrays(text)
            model_want = M.vdot_vv(reg128(arrs["op1"]), reg128(arrs["op2"])) & 0xFFFFFFFF
            checked_reads += 1
            if int(m.group(1), 16) != model_want:
                problems.append("%s: want=0x%s != 金模型 0x%08X" % (cid, m.group(1), model_want))
            continue
        arrs = parse_arrays(text)
        reads, enc_bad = replay(text, arrs)
        for e in enc_bad:
            problems.append("%s: 编码反解不符 %r" % (cid, e))
        checked_enc += len(re.findall(r"//@OP vdot ", text))
        consts = emitted_constants(text)
        g0 = c["family"] == "g0"
        for idx, (want, hi) in sorted(reads.items()):
            if idx not in consts:
                problems.append("%s: 源里缺 got[%d] 的断言常量" % (cid, idx))
                continue
            checked_reads += 1
            if g0 and idx == 0:
                # G0：C 里的常量必须是「金模型值错 1 bit」
                if consts[idx] == want:
                    problems.append("%s: G0 反例的期望值没有被写错（防止虚假通过的防护失效）" % cid)
                elif bin(consts[idx] ^ want).count("1") != 1:
                    problems.append("%s: G0 反例不是错 1 bit" % cid)
            elif consts[idx] != want:
                problems.append("%s: got[%d] 常量 0x%08X != 金模型 0x%08X"
                                % (cid, idx, consts[idx], want))
        if not quiet:
            print("  %-18s reads=%d ok" % (cid, len(reads)))

    # manifest 与 spec 必须逐行一致
    rows = []
    with open(MANIFEST, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                rows.append((parts[0], parts[1]))
    spec_rows = [(c["cid"], c["cls"]) for c in cases]
    if rows != spec_rows:
        problems.append("manifest.extra.tsv 与 spec.extra.json 行不一致（%d vs %d 行）"
                        % (len(rows), len(spec_rows)))

    print("EXTRA_CROSSCHECK cases=%d reads_or_groups=%d vdot_encs=%d problems=%d"
          % (len(cases), checked_reads, checked_enc, len(problems)))
    if problems:
        print("EXTRA_CROSSCHECK verdict=MISMATCH")
        for p in problems[:50]:
            print("  - " + p)
        return 1
    print("EXTRA_CROSSCHECK verdict=MATCH（全部期望常量与金模型逐条一致）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
