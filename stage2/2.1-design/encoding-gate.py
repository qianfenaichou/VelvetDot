#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vdot.vv 编码冲突检查（离线、可复现）
=================================================

目的：对冻结三元组 (opcode, funct3, funct6, vm) 做一次「全空间重叠」判定，
输入只允许是**本地文件**（工作区快照 + 可选的 riscv-opcodes 快照目录），
不联网、不调用外部服务，因此在无网/离线评审环境下可复跑。

判据（口径）：
  两条指令冲突 <=> 存在一个 32 位字同时满足两者的固定位（掩码交集上取值相等）。
  这一判据同时覆盖「同 funct6 不同 vm」「vs1/vs2 被固定成常数（如 VCPOP_M）」
  「mask 不含 vm 位（NEMU 的 MASK_VCLMUL_VV = 0xfc00707f）」三类共槽情形，
  比「逐字段比 funct6/funct3/opcode」更严（见 SPEC.md §4 A-6 的共槽提示）。

退出码语义（必须区分，否则「没跑出冲突」会被读成「没有冲突」）：
  0  PASS                工作区全部快照 0 重叠，且全部阳性对照命中，且与 SPEC/金模型一致
  1  CONFLICT            检出与冻结三元组重叠的编码（禁止锁码/禁止宣称冻结）
  2  SELFTEST_FAILED     阳性对照未命中 => 检查本身失效，本次结论不可信（必须修检查逻辑）
  3  INPUT_MISSING       快照文件缺失或解析到 0 条编码 => 无法判定（不等于通过）
  4  UPSTREAM_NOT_COVERED 工作区维度已过，但未提供 riscv-opcodes 本地快照，
                          「官方归属/未批准提案」维度未覆盖，不得据此宣称全空间无冲突

用法（在仓库根执行；脚本按当前工作目录定位工作区快照）：
  python3 stage2/2.1-design/encoding-gate.py                 # 只查工作区快照 -> 未落地 vdot 的干净树 exit 4；已落地则 exit 1
  python3 stage2/2.1-design/encoding-gate.py --snapshot DIR  # 追加官方归属维度 -> 干净树 exit 0（脚本 PASS 分支）；已落地 vdot 的树 exit 1（自检命中，非冲突）
  python3 stage2/2.1-design/encoding-gate.py -v              # 打印每条来源的命中/占用明细

说明：本脚本只做离线静态检查、不联网，结果用于支撑 `design/SPEC.md` §2 的编码论证。
"""

import argparse
import os
import re
import sys

# ---------------------------------------------------------------- 冻结三元组
OPCODE = 0b1010111          # OP-V
FUNCT3 = 0b010              # OPMVV
FUNCT6 = 0b001110           # C-enc1b（SPEC.md §0 速查表 / §2.1）
VM = 0b1                    # 无掩码；vm=0 由译码层判非法（SPEC.md §1.1）
MACHINE_CODE = 0x3A20A1D7   # vdot.vv v3, v2, v1（SPEC.md §0/:19、§2.2/:95）

# 阳性对照用的「已知撞车」编码（历史上真实出现过的冲突，必须被本脚本检出）
OLD_C_ENC1 = (OPCODE, FUNCT3, 0b001100, 0b1)   # 被 Zvbc vclmul.vv 占用
OLD_C_ENC1_WORD = 0x3220A1D7                   # 旧机器码（SPEC 修订前）

WS = os.getcwd()
SRC = {
    "nemu-encoding.h": "repos/NEMU/src/isa/riscv64/local-include/encoding.h",
    "nemu-decode.h":   "repos/NEMU/src/isa/riscv64/instr/rvv/decode.h",
    "rocket-Instructions.scala": "repos/XiangShan/rocket-chip/src/main/scala/rocket/Instructions.scala",
    "xs-Instructions.scala":     "repos/XiangShan/src/main/scala/xiangshan/backend/decode/Instructions.scala",
    "VecDecoder.scala":          "repos/XiangShan/src/main/scala/xiangshan/backend/decode/VecDecoder.scala",
    "yunsuan-package.scala":     "repos/XiangShan/yunsuan/src/main/scala/yunsuan/package.scala",
    "SPEC.md":                   "design/SPEC.md",
    "vdot_model.py":             "design/verify/vdot_model.py",
}


def word_of(opcode, funct3, funct6, vm, vs2=0, vs1=0, vd=0):
    return ((funct6 << 26) | (vm << 25) | (vs2 << 20) | (vs1 << 15)
            | (funct3 << 12) | (vd << 7) | opcode)


OURS_MASK = 0xFC00707F                 # funct6[31:26] + vm[25] + funct3[14:12] + opcode[6:0]
OURS_VAL = word_of(OPCODE, FUNCT3, FUNCT6, VM) & OURS_MASK


def overlap(m1, v1, m2, v2):
    """存在一个字同时匹配两者 <=> 固定位交集上取值相同。"""
    c = m1 & m2
    return (v1 & c) == (v2 & c)


def same_triple(m, v):
    """另一条编码是否与我们在同一 funct6/funct3/opcode(/vm) 槽位上完全同值。"""
    if (m >> 26 & 0x3F) != (OURS_MASK >> 26 & 0x3F):
        return False
    if (v >> 26 & 0x3F) != FUNCT6:
        return False
    if (m >> 12 & 0x7) == 0x7 and (v >> 12 & 0x7) != FUNCT3:
        return False
    if (m & 0x7F) == 0x7F and (v & 0x7F) != OPCODE:
        return False
    return True


class Report:
    def __init__(self):
        self.lines = []
        self.conflicts = []
        self.controls = []      # (name, ok)
        self.fatal = []         # 直接决定退出码的失败

    def say(self, s=""):
        self.lines.append(s)
        print(s)


# ---------------------------------------------------------------- 解析器
def parse_bitpat(text):
    """BitPat("b001110??????????010?????1010111") -> (mask, val)。返回 32 位条目。"""
    out = []
    for m in re.finditer(r'BitPat\("b([01?x_]+)"\)', text):
        s = m.group(1).replace("_", "")
        if len(s) != 32:
            continue
        mask = val = 0
        for i, ch in enumerate(s):
            bit = 31 - i
            if ch == "1":
                mask |= 1 << bit
                val |= 1 << bit
            elif ch == "0":
                mask |= 1 << bit
        out.append((s, mask, val))
    return out


def parse_match_mask(text):
    """encoding.h 的 MATCH_/MASK_ 成对宏 -> (name, mask, match_value)。"""
    ms, vk = {}, {}
    for m in re.finditer(r'#define\s+MATCH_(\w+)\s+(0x[0-9a-fA-F]+)', text):
        ms[m.group(1)] = int(m.group(2), 16)
    for m in re.finditer(r'#define\s+MASK_(\w+)\s+(0x[0-9a-fA-F]+)', text):
        vk[m.group(1)] = int(m.group(2), 16)
    return [(k, vk[k], ms[k]) for k in ms if k in vk]


def parse_nemu_vopmvv(text):
    """decode.h 里 def_THelper(vopmvv) 的表项 -> funct6 集合。

    注意：该块同时使用 def_INSTR_TAB 与 def_INSTR_IDTAB（后者出现在
    decode.h:332 的 010010 -> vxunary0_dispatch，即 Zvbb 子派发表）。
    只匹配前者会把 50 条读成 49 条，与源码侧的 50/14 空闲统计不符。
    """
    i = text.find("def_THelper(vopmvv)")
    if i < 0:
        return None, None
    j = text.find("\n}", i)
    block = text[i:j if j > 0 else len(text)]
    used = {}
    for m in re.finditer(r'def_INSTR(?:_TAB|_IDTAB|_ID)\("([^"]+)"([^)]*)\)', block):
        pat = m.group(1).replace(" ", "")
        if len(pat) != 32:
            continue
        f6 = pat[0:6]
        if re.fullmatch(r'[01]{6}', f6):
            args = re.findall(r'\b(\w+)\b', m.group(2))
            used.setdefault(int(f6, 2), []).append((args[-1] if args else "?", pat))
    return used, len(block.splitlines())


def parse_vimac_type(text):
    """yunsuan VimacType 的 9 位 fuOpType 空间（另一套命名空间，独立于指令编码）。"""
    i = text.find("object VimacType")
    if i < 0:
        return None
    block = text[i:i + 6000]
    vals = {}
    for m in re.finditer(r'def\s+(\w+)\s*=\s*LiteralCat\(.*?//\s*"b([01_x]+)"', block, re.S):
        s = m.group(2).replace("_", "")
        if len(s) == 9 and re.fullmatch(r'[01]+', s):
            vals[m.group(1)] = int(s, 2)
    for m in re.finditer(r'def\s+(\w+)\s*=\s*"b([01_x]+)"\.U\(OpTypeWidth\.W\)', block):
        s = m.group(2).replace("_", "")
        if len(s) == 9 and re.fullmatch(r'[01]+', s):
            vals[m.group(1)] = int(s, 2)
    vals.setdefault("dummy(BitPat.Y)", 0b111111111)
    return vals


def parse_upstream(directory):
    """本地 riscv-opcodes 快照：extensions/** 与 opcodes* 的指令行 -> (mask, val)。"""
    rows = []
    nfiles = 0
    for root, _dirs, files in os.walk(directory):
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, directory)
            if not (rel.replace("\\", "/").startswith("extensions/") or rel.startswith("opcodes")):
                continue
            if rel == "encoding.h":
                continue
            nfiles += 1
            try:
                text = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for ln, line in enumerate(text.splitlines(), 1):
                s = line.strip()
                if not s or s[0] in "#$-" or "pseudo_op" in s:
                    continue
                fields = re.findall(r'(?<![\d.])(\d+)(?:\.\.(\d+))?=(\S+)', s)
                if not fields:
                    continue
                mask = val = 0
                ok = True
                for hi, lo, v in fields:
                    hi, lo = int(hi), int(lo) if lo else int(hi)
                    w = hi - lo + 1
                    if v.lower().startswith("0x"):
                        num = int(v, 16)
                    elif v.lower().startswith("0b"):
                        num = int(v, 2)
                    elif re.fullmatch(r"[01]+", v):
                        num = int(v, 2)
                    elif re.fullmatch(r"\d+", v) and len(v) <= 2:
                        num = int(v)
                    else:
                        ok = False
                        break
                    mm = ((1 << w) - 1) << lo
                    mask |= mm
                    val = (val & ~mm) | ((num << lo) & mm)
                    val &= 0xFFFFFFFF
                if ok:
                    rows.append((s.split()[0], rel, ln, mask, val))
    return rows, nfiles


# ---------------------------------------------------------------- 主流程
def check_frozen_selfconsistency(r, verbose=False):
    """三元组 -> 机器码，并与 SPEC.md 正文、金模型常数对齐（防文档漂移）。"""
    w = word_of(OPCODE, FUNCT3, FUNCT6, VM, vs2=2, vs1=1, vd=3)
    if w != MACHINE_CODE:
        r.fatal.append(("MISMATCH", "三元组算出的机器码 0x%08X != 记录的 0x%08X" % (w, MACHINE_CODE)))
    r.say("[A] 三元组 -> 机器码: opcode=%s funct3=%s funct6=%s vm=%s => 0x%08X (%s 0x%08X)"
          % (format(OPCODE, '07b'), format(FUNCT3, '03b'), format(FUNCT6, '06b'), VM,
             w, "==" if w == MACHINE_CODE else "!=", MACHINE_CODE))

    # SPEC.md 里写死的 funct6 / 机器码必须与本文常数一致
    p = os.path.join(WS, SRC["SPEC.md"])
    if os.path.isfile(p):
        txt = open(p, encoding="utf-8", errors="replace").read()
        f6_in_spec = ("`%s`" % format(FUNCT6, '06b')) in txt
        mc_in_spec = ("0x%08X" % MACHINE_CODE) in txt or ("0x%08x" % MACHINE_CODE) in txt
        stale = re.findall(r'0x3220A1D7|b0011001\?\?\?\?\?\?\?\?\?\?010', txt)
        r.say("[A] design/SPEC.md: funct6 文本命中=%s 机器码命中=%s 旧编码残留=%d 处"
              % (f6_in_spec, mc_in_spec, len(stale)))
        if not (f6_in_spec and mc_in_spec):
            r.conflicts.append(("DOC-DRIFT", "design/SPEC.md",
                                "正文未包含冻结 funct6=%s 或机器码=0x%08X，检查与正文已漂移"
                                % (format(FUNCT6, '06b'), MACHINE_CODE)))
        if stale:
            r.conflicts.append(("DOC-DRIFT", "SPEC.md", "正文仍含旧编码 C-enc1 痕迹 %r" % (stale[:3],)))
    else:
        r.say("[A] design/SPEC.md 缺失 -> 记 INPUT_MISSING")
        r.fatal.append(("INPUT_MISSING", "design/SPEC.md 不存在"))

    # 金模型常数
    p = os.path.join(WS, SRC["vdot_model.py"])
    if os.path.isfile(p):
        txt = open(p, encoding="utf-8", errors="replace").read()
        def grab(name):
            m = re.search(r'%s\s*=\s*(0b[01_]+|0x[0-9a-fA-F]+|\d+)' % name, txt)
            return int(m.group(1).replace("_", ""), 0) if m else None
        got = (grab("OPCODE_OP_V"), grab("FUNCT3_OPMVV"), grab("FUNCT6_VDOT"), grab("VM_UNMASKED"))
        want = (OPCODE, FUNCT3, FUNCT6, VM)
        r.say("[A] design/verify/vdot_model.py:50-53 常数 = %s（期望 %s）"
              % (tuple(bin(x) if x is not None else None for x in got), tuple(bin(x) for x in want)))
        if got != want:
            r.conflicts.append(("DOC-DRIFT", "design/verify/vdot_model.py:50-53",
                                "金模型常数 %r != 冻结三元组 %r" % (got, want)))
    else:
        r.fatal.append(("INPUT_MISSING", "design/verify/vdot_model.py 不存在"))


def scan_scala_bitpats(r, verbose):
    """XiangShan + rocket-chip + yunsuan 里所有 32 位 BitPat 的重叠检查。

    只统计「opcode 字段被完全固定」的模式（= 真正的指令匹配模式），
    其余（字段掩码、切片常量）单独计数、不参与判定。
    重叠判据用通用 overlap()，因此 funct6/vm 通配、vs1/vs2/vd 被固定成常数
    （如 VCPOP_M 固定 vs1=x0）都能被检出，不做「必须整段 funct6 固定」的弱过滤。
    """
    roots = ["repos/XiangShan/src", "repos/XiangShan/rocket-chip/src", "repos/XiangShan/yunsuan/src"]
    total = 0
    skipped = 0
    hits = []
    per_file = {}
    for rel_root in roots:
        root = os.path.join(WS, rel_root)
        if not os.path.isdir(root):
            r.fatal.append(("INPUT_MISSING", "缺目录 %s" % rel_root))
            continue
        for dirpath, _d, files in os.walk(root):
            for fn in files:
                if not fn.endswith(".scala"):
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    text = open(p, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                entries = parse_bitpat(text)
                if not entries:
                    continue
                rel = os.path.relpath(p, WS)
                per_file[rel] = len(entries)
                for pat, mask, val in entries:
                    if (mask & 0x7F) != 0x7F:
                        skipped += 1          # opcode 未完全固定：不是指令匹配模式
                        continue
                    total += 1
                    if overlap(OURS_MASK, OURS_VAL, mask, val) or same_triple(mask, val):
                        hits.append((pat, rel, mask, val))
    r.say("[B] Scala BitPat 扫描: 文件 %d 个 / 指令级 32 位模式 %d 条（另有 opcode 未固定的 %d 条，不参与判定）"
          " -> 与冻结三元组重叠 %d 条" % (len(per_file), total, skipped, len(hits)))
    if total == 0:
        r.fatal.append(("INPUT_MISSING", "Scala BitPat 解析到 0 条指令级模式，扫描管线可能失效"))
    for pat, f, mask, val in hits:
        r.conflicts.append(("SCALA-BITPAT", "%s: %s" % (f, pat), "mask=0x%08X val=0x%08X" % (mask, val)))
    if verbose:
        for f, n in sorted(per_file.items()):
            r.say("        %-72s %d 条" % (f, n))
    return total, len(hits)


def scan_nemu_encoding_h(r, verbose):
    p = os.path.join(WS, SRC["nemu-encoding.h"])
    if not os.path.isfile(p):
        r.fatal.append(("INPUT_MISSING", SRC["nemu-encoding.h"]))
        return 0, 0
    text = open(p, encoding="utf-8", errors="replace").read()
    pairs = parse_match_mask(text)
    ins = [(k, m, v) for (k, m, v) in pairs if (m & 0x7F) == 0x7F and (m & 3) == 3]
    hits = [(k, m, v) for (k, m, v) in ins if overlap(OURS_MASK, OURS_VAL, m, v)]
    r.say("[C] NEMU encoding.h: MATCH_/MASK_ 成对宏 %d 组（其中 opcode 完全固定的 %d 组参与判定）"
          " -> 重叠 %d 条" % (len(pairs), len(ins), len(hits)))
    if not pairs:
        r.fatal.append(("INPUT_MISSING", "encoding.h 解析到 0 组 MATCH_/MASK_"))
    for k, m, v in hits:
        r.conflicts.append(("NEMU-MATCH", "MATCH_%s (encoding.h)" % k, "mask=0x%08X val=0x%08X" % (m, v)))
    # OPMVV(funct3=010)/OP-V 槽位在 NEMU 头文件里的占用情况（供回退候选逐个复核）
    own = {}
    for k, m, v in ins:
        if (m >> 26) & 0x3F == 0x3F and (m >> 12) & 7 == 7 and (v >> 12) & 7 == FUNCT3 and (v & 0x7F) == OPCODE:
            own.setdefault((v >> 26) & 0x3F, []).append(k)
    r.say("[C]   encoding.h 中 funct3=010/opcode=0x57 已占 funct6: %s"
          % (", ".join("0x%02X(%s)" % (q, "/".join(sorted(set(own[q])))) for q in sorted(own)) or "无"))
    r.say("[C]   冻结 funct6=0x%02X 是否出现在该列表: %s" % (FUNCT6, "是（冲突）" if FUNCT6 in own else "否"))
    # 溯源：文件头声明的 riscv-opcodes 生成 commit
    head = re.search(r"auto-generated by running 'make' in\s*\*\s*https://github\.com/riscv/riscv-opcodes \((\w+)\)", text)
    if head:
        r.say("[C]   该快照的上游来源: riscv-opcodes @ %s（文件头 :5-8 注明）" % head.group(1))
    return len(pairs), len(hits)



def scan_nemu_decode_h(r, verbose):
    p = os.path.join(WS, SRC["nemu-decode.h"])
    if not os.path.isfile(p):
        r.fatal.append(("INPUT_MISSING", SRC["nemu-decode.h"]))
        return
    text = open(p, encoding="utf-8", errors="replace").read()
    used, _n = parse_nemu_vopmvv(text)
    if used is None:
        r.fatal.append(("INPUT_MISSING", "decode.h 未找到 def_THelper(vopmvv)"))
        return
    free = [x for x in range(64) if x not in used]
    r.say("[D] NEMU decode.h vopmvv: 已占 funct6 %d 个 / 空闲 %d 个" % (len(used), len(free)))
    r.say("[D]   空闲列表: " + " ".join(format(x, '06b') for x in free))
    if FUNCT6 in used:
        for name, pat in used[FUNCT6]:
            r.conflicts.append(("NEMU-DECODE-H", "vopmvv 表项 %s (pattern %s)" % (name, pat), ""))
    # 上游占用但 NEMU 未占的槽位（这些不能当回退候选直接用）
    r.say("[D]   冻结 funct6 %s 在 NEMU 译码表: %s"
          % (format(FUNCT6, '06b'), "已占（冲突）" if FUNCT6 in used else "空闲"))


def scan_vecdecoder_opmvv(r, verbose):
    p = os.path.join(WS, SRC["VecDecoder.scala"])
    q = os.path.join(WS, SRC["rocket-Instructions.scala"])
    if not (os.path.isfile(p) and os.path.isfile(q)):
        r.fatal.append(("INPUT_MISSING", "VecDecoder.scala 或 rocket-chip Instructions.scala 缺失"))
        return
    vtext = open(p, encoding="utf-8", errors="replace").read()
    itext = open(q, encoding="utf-8", errors="replace").read()
    ipat = dict((m.group(1), m.group(2)) for m in
                re.finditer(r'def\s+(\w+)\s*=\s*BitPat\("b([01?x_]+)"\)', itext))
    block = vtext[vtext.find("val opmvv"):]
    block = block[:block.find("\n  val opmvx")] if "\n  val opmvx" in block else block
    entries = re.findall(r'(\w+)\s*->\s*OPMVV\(', block)
    used = {}
    for name in entries:
        pat = ipat.get(name)
        if not pat:
            continue
        f6 = pat.replace("_", "")[0:6]
        if re.fullmatch(r'[01]{6}', f6):
            used.setdefault(int(f6, 2), []).append(name)
    free = [x for x in range(64) if x not in used]
    r.say("[E] XiangShan VecDecoder.opmvv: 表项 %d 条 / 已解析 funct6 %d 个 / 空闲 %d 个"
          % (len(entries), len(used), len(free)))
    if FUNCT6 in used:
        for name in used[FUNCT6]:
            r.conflicts.append(("VECDECODER", "opmvv 表项 %s" % name, ""))
    if len(entries) == 0:
        r.fatal.append(("INPUT_MISSING", "VecDecoder opmvv 表解析到 0 条"))
    if verbose:
        r.say("        空闲: " + " ".join(format(x, '06b') for x in free))


def scan_fuopcode_namespace(r, verbose):
    p = os.path.join(WS, SRC["yunsuan-package.scala"])
    if not os.path.isfile(p):
        r.fatal.append(("INPUT_MISSING", SRC["yunsuan-package.scala"]))
        return
    text = open(p, encoding="utf-8", errors="replace").read()
    vals = parse_vimac_type(text)
    if not vals:
        r.say("[F] yunsuan VimacType 9 位 fuOpType: 未解析到条目（该维度记未覆盖）")
        return
    occupied = sorted(set(vals.values()))
    free = [x for x in range(512) if x not in occupied]
    r.say("[F] yunsuan VimacType(9-bit fuOpType, 与指令编码是两套命名空间): 已用 %d 个 / 空闲 %d 个"
          % (len(occupied), len(free)))
    if verbose:
        r.say("        已用: " + ", ".join("%s=%s" % (k, format(v, '09b')) for k, v in vals.items()))


def positive_controls(r):
    """阳性对照：脚本必须能检出历史上真实存在的撞车，否则检查本身失效。"""
    # P1 旧 C-enc1(001100/010/0x57/vm=1) 必须与 NEMU 的 vclmul.vv 重叠
    p = os.path.join(WS, SRC["nemu-encoding.h"])
    ok = False
    if os.path.isfile(p):
        pairs = dict((k, (m, v)) for (k, m, v) in parse_match_mask(open(p, encoding="utf-8", errors="replace").read()))
        for nm in ("VCLMUL_VV", "VCLMULH_VV"):
            if nm not in pairs:
                continue
            m, v = pairs[nm]
            old_mask, old_val = OURS_MASK, word_of(*OLD_C_ENC1[:3], OLD_C_ENC1[3], vs2=2, vs1=1, vd=3) & OURS_MASK
            if nm == "VCLMUL_VV":
                ok = overlap(old_mask, old_val, m, v) and (v >> 26 & 0x3F) == 0x0C
        r.say("[P1] 阳性对照 · 旧码 001100/010/vm=1 (0x%08X) vs encoding.h MATCH_VCLMUL_VV(0x30002057/MASK 0xfc00707f) -> %s"
              % (OLD_C_ENC1_WORD, "命中（正确）" if ok else "未命中 => 检查失效"))
        if not ok:
            r.controls.append(("P1 vclmul vs 旧 C-enc1", False))
        else:
            r.controls.append(("P1 vclmul vs 旧 C-enc1", True))
    else:
        r.controls.append(("P1 vclmul vs 旧 C-enc1 (encoding.h 缺失)", False))

    # P2 已知撞车：111111/010 = vwmaccsu（rocket-chip Instructions.scala）
    q = os.path.join(WS, SRC["rocket-Instructions.scala"])
    ok2 = False
    if os.path.isfile(q):
        for _pat, m, v in parse_bitpat(open(q, encoding="utf-8", errors="replace").read()):
            if (m >> 26 & 0x3F) == 0x3F and (v >> 26 & 0x3F) == 0b111111 and (v >> 12 & 7) == 0b010:
                ok2 = True
    r.say("[P2] 阳性对照 · 111111/010 在 rocket-chip Instructions.scala 中被占用（VWMACCSU_VV, :819）-> %s"
          % ("命中（正确）" if ok2 else "未命中 => 检查失效"))
    r.controls.append(("P2 vwmaccsu 111111/010", ok2))

    # P3 已知撞车：101101/010 = vmacc（NEMU decode.h vopmvv 表内）
    p3 = os.path.join(WS, SRC["nemu-decode.h"])
    ok3 = False
    if os.path.isfile(p3):
        used, _ = parse_nemu_vopmvv(open(p3, encoding="utf-8", errors="replace").read())
        ok3 = bool(used) and 0b101101 in used
    r.say("[P3] 阳性对照 · NEMU vopmvv 表含 funct6=101101（vmacc）-> %s" % ("命中（正确）" if ok3 else "未命中 => 检查失效"))
    r.controls.append(("P3 nemu vopmvv 101101 vmacc", ok3))

    # P4 反向对照：vm 位不参与掩码时仍要能检出 —— vclmul.vx（funct3=110）不得被判为与 010 冲突
    ok4 = True
    if os.path.isfile(p):
        pairs = dict((k, (m, v)) for (k, m, v) in parse_match_mask(open(p, encoding="utf-8", errors="replace").read()))
        m, v = pairs.get("VCLMUL_VX", (0, 0))
        ok4 = not overlap(OURS_MASK, OURS_VAL, m, v) if m else False
    r.say("[P4] 反向对照 · funct3=110 的 vclmul.vx 不得与 010 槽位判重叠 -> %s"
          % ("正确排除" if ok4 else "误判 => 掩码逻辑有误"))
    r.controls.append(("P4 vclmul.vx(funct3=110) 不误判", ok4))


def upstream_scan(r, snapshot, verbose):
    rows, nfiles = parse_upstream(snapshot)
    if not rows:
        r.fatal.append(("INPUT_MISSING", "快照 %s 未解析到任何指令行" % snapshot))
        return True
    v32 = [x for x in rows if (x[3] & 0x7F) == 0x7F and (x[3] & 3) == 3 and (x[4] & 3) == 3]
    hits = [x for x in v32 if overlap(OURS_MASK, OURS_VAL, x[3], x[4])]
    mn = [x for x in rows if x[0].lower().startswith("vdot")]
    r.say("[U] riscv-opcodes 本地快照 %s: 文件 %d / 指令行 %d（32 位 %d）-> 与冻结三元组重叠 %d 条"
          % (snapshot, nfiles, len(rows), len(v32), len(hits)))
    for name, rel, ln, m, v in hits:
        r.conflicts.append(("UPSTREAM", "%s (%s:%d)" % (name, rel, ln), "mask=0x%08X val=0x%08X" % (m, v)))
    if mn:
        r.say("[U]   快照内以 vdot 开头的助记符: " + ", ".join(sorted({x[0] for x in mn})))
    def owner_is_vvopmvv(x):
        return ((x[3] & 0x7F) == 0x7F and (x[4] & 0x7F) == OPCODE
                and (x[3] >> 12 & 7) == 7 and (x[4] >> 12 & 7) == FUNCT3
                and (x[3] >> 26 & 0x3F) == 0x3F)

    # 阳性对照：同一管线必须命中 0x0C(vclmul.vv) / 0x2C(vdot4a.vv)
    def owner(f6, f3=FUNCT3):
        return sorted({x[0] for x in v32
                       if (x[3] & 0x7F) == 0x7F and (x[4] & 0x7F) == OPCODE          # opcode 固定且 = OP-V
                       and (x[3] >> 12 & 7) == 7 and (x[4] >> 12 & 7) == f3           # funct3 固定且 = OPMVV
                       and (x[3] >> 26 & 0x3F) == 0x3F and (x[4] >> 26 & 0x3F) == f6})  # funct6 固定
    c1 = owner(0x0C)
    c2 = owner(0x2C)
    cu = owner(FUNCT6)
    okc = bool(c1) and bool(c2) and (not cu or FUNCT6 in (0x0C, 0x2C))
    r.say("[U]   阳性对照: 0x0C->%s 0x2C->%s ; 0x%02X(本编码)->%s ; 判定=%s"
          % (c1 or "-", c2 or "-", FUNCT6, cu or "FREE", "管线有效" if okc else "管线失效"))
    r.controls.append(("U-scan 0x0C/0x2C 命中且 0x%02X 空闲" % FUNCT6, okc))
    if verbose:
        occupied = {y[4] >> 26 & 0x3F for y in v32 if owner_is_vvopmvv(y)}
        free = [x for x in range(64) if x not in occupied]
        r.say("        上游 opcode=0x57/funct3=010 已占 funct6 %d 个 / 空闲 %d 个: "
              % (len(occupied), len(free)) + " ".join(format(x, '06b') for x in free))
    return okc


def emit(r, covered_upstream):
    print("")
    if r.conflicts:
        print("!!! 检出冲突/漂移 %d 条:" % len(r.conflicts))
        for tag, who, detail in r.conflicts:
            print("    [%s] %s %s" % (tag, who, detail))
    fails = [n for n, ok in r.controls if not ok]
    if fails:
        print("!!! 阳性对照未命中 %d 项: %s" % (len(fails), "; ".join(fails)))
    if r.fatal:
        print("!!! 输入缺失/不可判定 %d 项: %s" % (len(r.fatal), "; ".join("%s: %s" % x for x in r.fatal)))

    if r.conflicts:
        print("结论: 检出冲突/文档漂移（退出码 1 = CONFLICT，禁止锁码/禁止宣称冻结）")
        return 1
    if fails:
        print("结论: 自检失败（退出码 2 = SELFTEST_FAILED，本次『无冲突』结论作废）")
        return 2
    if r.fatal:
        print("结论: 无法判定（退出码 3 = INPUT_MISSING / 解析失效）")
        return 3
    if not covered_upstream:
        print("结论: 工作区维度 0 冲突，但官方归属维度未覆盖（退出码 4）。")
        print("      要判『全空间无冲突』必须再跑: --snapshot <本地 riscv-opcodes 快照目录>")
        print("      取快照: git clone --depth 1 https://github.com/riscv/riscv-opcodes.git <dir>"
              " && git -C <dir> rev-parse HEAD  （把 commit 记进证据文件）")
        return 4
    print("结论: PASS（退出码 0）——工作区快照 + 上游快照 0 重叠，阳性对照全部命中，文档/金模型常数一致")
    return 0


def main():
    ap = argparse.ArgumentParser(description="vdot.vv 编码冲突检查（离线）")
    ap.add_argument("--snapshot", help="本地 riscv-opcodes 快照目录（含 extensions/）")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    r = Report()
    r.say("=== vdot.vv 编码检查 · 冻结三元组 funct6=%s / funct3=%s / opcode=%s / vm=%s ==="
          % (format(FUNCT6, '06b'), format(FUNCT3, '03b'), format(OPCODE, '07b'), VM))
    check_frozen_selfconsistency(r, args.verbose)
    scan_scala_bitpats(r, args.verbose)
    scan_nemu_encoding_h(r, args.verbose)
    scan_nemu_decode_h(r, args.verbose)
    scan_vecdecoder_opmvv(r, args.verbose)
    scan_fuopcode_namespace(r, args.verbose)
    positive_controls(r)
    covered = False
    if args.snapshot:
        if os.path.isdir(args.snapshot):
            covered = upstream_scan(r, args.snapshot, args.verbose)
        else:
            r.fatal.append(("INPUT_MISSING", "--snapshot 目录不存在: %s" % args.snapshot))
    return emit(r, covered)


if __name__ == "__main__":
    sys.exit(main())
