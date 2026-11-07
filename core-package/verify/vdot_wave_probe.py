#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vdot.vv 波形体检 + 窄窗关键信号摘录（**真实抽取**）。

调用方：core-package/scripts/62-wave-vdot.sh 的 E 阶段。
输入：emu `--dump-wave` 产出的 Verilator VCD（窄窗，时间轴与 mcycle 同源）。
输出：
  * `vcd-head-<runid>.txt`       header 原文（前 N 行）
  * `vcd-scopes-<runid>.txt`      scope 索引（每 scope 路径 + var 数）+ 摘录信号表（标签 → 完整层次名）
  * `vcd-summary-<runid>.txt`     体检摘要（人读）
  * `vcd-health-<runid>.json`     体检结论（机读，逐条 checks[]）
  * `vdot_wave_<runid>.key.vcd`   **关键信号摘录**（窄窗、真值、可直接用 GTKWave 打开）

摘录口径（写清楚，否则会被当成编造）：
  - 时间戳**原样保留**源 VCD 的拍号（不重编号）⇒ 摘录可与全量 VCD 逐拍对齐；
  - 每个信号的值**逐拍从源 VCD 抽取**；VCD 只记变化，故先做前向填值，再在窗口首拍锁定稳态值；
  - 信号**标签**是缩写（`vimac_res_data` 等），标签 → 完整层次名的映射写进
    `vcd-scopes-<runid>.txt` 的「摘录信号表」段，来源不丢；
  - 摘录写完后**立刻回读自校验**（默认开）：逐信号逐拍与源 VCD 比对，不一致即 rc=1。
    这条是「摘录非伪造」的机械判据。

体检项（每条落进 JSON 的 checks[]）：
  1 `header_ok`      `$timescale` 可解析、vars/scopes 计数非零
  2 `ts_range`       时间戳范围 [min,max] 与采样点数
  3 `instr_hit`      机器码 0x3A20A1D7 在译码级 `valid=1` 命中（给出拍号与槽号）
  4 `fuoptype_exec`  执行级 `Vimac/io_in_bits_ctrl_fuOpType == 0x067`（VimacType.vdot）
  5 `result_low32`   `vdotReduce/io_vd` 低 32 位 == 期望值（金模型 0x00008780）
  6 `high96_zero`    写回 `Vimac/io_out_bits_res_data[127:32] == 0`（SPEC §1.1 恒清零）
  7 `wb_after_anchor` 写回拍在译码锚点之后（窗口确实覆盖了这条指令）
  8 `excerpt_verify` 摘录回读自校验逐拍一致

用法：
  python3 -I vdot_wave_probe.py --vcd X.vcd --instr 0x3A20A1D7 --expect 0x00008780 \
      --excerpt Y.key.vcd --head H.txt --scopes S.txt --summary M.txt --json J.json \
      [--vcd-sha256 ...] [--pre 40] [--post 60] [--span 200]

退出码：0 体检全过 / 1 体检有未过项（摘录仍会产出）/ 2 致命（找不到锚点或信号）/ 3 用法错误
"""
import argparse
import json
import os
import re
import sys
from collections import OrderedDict

# 层次前缀（与 stage1/1.3-vadd/cases/vadd_stage_extract.py:54-55 同口径，来自实测 VCD）
P = "TOP/SimTop/cpu/l_soc/core_with_l2/core/backend"
CLOCK = "TOP/SimTop/clock"

# VimacType.vdot 的 9 位值（yunsuan/package.scala 的 `def vdot`：00_1_1_0_0_111）
VDOT_FUOPTYPE = 0x067
# 写回高 96 位必须为 0（SPEC §1.1）
HIGH_ZERO_MASK = ((1 << 128) - 1) ^ ((1 << 32) - 1)


def parse_header(fh):
    """按完整层次名建索引（Verilator 复用 VCD 标识符，不能按 code 建索引）。

    返回 names{full_path: (code, width)}、scopes[(path, var_count)]、meta{date,version,timescale}。
    """
    names = OrderedDict()
    scopes = OrderedDict()
    cur = []
    meta = {"date": "", "version": "", "timescale": ""}
    while True:
        line = fh.readline()
        if not line:
            break
        t = line.strip()
        if t.startswith("$date"):
            meta["date"] = t[5:].replace("$end", "").strip()
        elif t.startswith("$version"):
            meta["version"] = t[8:].replace("$end", "").strip()
        elif t.startswith("$timescale"):
            meta["timescale"] = t[11:].replace("$end", "").strip()
        elif t.startswith("$scope"):
            p = t.split()
            if len(p) >= 3:
                cur.append(p[2])
                scopes["/".join(cur)] = 0
        elif t.startswith("$upscope"):
            if cur:
                cur.pop()
        elif t.startswith("$var"):
            p = t.split()
            if len(p) >= 5:
                w = int(re.sub(r"[^0-9]", "", p[2]) or 1)
                full = "/".join(cur + [p[4]])
                names[full] = (p[3], w)
                if cur:
                    scopes["/".join(cur)] += 1
        elif t.startswith("$enddefinitions"):
            break
    return names, scopes, meta


def iter_blocks(fh):
    """yield (time, [(code, (kind, text)])；kind 'b' 向量 / 's' 标量。"""
    t = None
    ch = []
    for line in fh:
        s = line.strip()
        if not s or s[0] == "$":
            continue
        if s[0] == "#":
            if t is not None:
                yield t, ch
            try:
                t = int(s[1:])
            except ValueError:
                continue
            ch = []
        elif t is not None:
            if s[0] == "b":
                p = s.split()
                if len(p) >= 2:
                    ch.append((p[1], ("b", p[0][1:])))
            else:
                ch.append((s[1:], ("s", s[0])))
    if t is not None:
        yield t, ch


def vint(item):
    if item is None:
        return None
    kind, text = item
    try:
        return int(text, 2) if kind == "b" else int(text)
    except ValueError:
        return None


def emit(item, code):
    kind, text = item
    return ("b%s %s" % (text, code)) if kind == "b" else (text + code)


def find_scope(scopes, pred):
    for s in scopes:
        if pred(s):
            return s
    return None


def build_signals(names, anchor_slot, vimac_scope, exu_scope, iq_scope):
    """摘录信号表：[(label, full_path, is_bus)]；不存在的信号进 missing，不静默跳过。"""
    leaf = exu_scope.rsplit("/", 1)[-1]
    exu_idx = 0 if leaf == "exus" else int(re.sub(r"[^0-9]", "", leaf) or 0)
    vs = vimac_scope.rsplit("/", 1)[-1]  # "Vimac"
    vm = "%s/%s" % (exu_scope, vs)
    iq = iq_scope

    rels = [
        ("clock", CLOCK, False),
        ("dec_in_instr", "inner_ctrlBlock/decode/io_in_%d_bits_instr" % anchor_slot, True),
        ("dec_in_valid", "inner_ctrlBlock/decode/io_in_%d_valid" % anchor_slot, False),
        ("dec_in_ready", "inner_ctrlBlock/decode/io_in_%d_ready" % anchor_slot, False),
        ("dec_in_pc", "inner_ctrlBlock/decode/io_in_%d_bits_pc" % anchor_slot, True),
        ("id_instr", "inner_ctrlBlock/decode/io_out_0_bits_instr", True),
        ("id_fuType", "inner_ctrlBlock/decode/io_out_0_bits_fuType", True),
        ("id_fuOpType", "inner_ctrlBlock/decode/io_out_0_bits_fuOpType", True),
        ("id_vsew", "inner_ctrlBlock/decode/io_out_0_bits_vpu_vsew", True),
        ("id_vlmul", "inner_ctrlBlock/decode/io_out_0_bits_vpu_vlmul", True),
        ("id_vm", "inner_ctrlBlock/decode/io_out_0_bits_vpu_vm", False),
        ("id_vstart", "inner_ctrlBlock/decode/io_out_0_bits_vpu_vstart", True),
        ("id_vill", "inner_ctrlBlock/decode/io_out_0_bits_vpu_vill", False),
        ("rn_valid", "inner_ctrlBlock/rename/io_out_0_valid", False),
        ("rn_pdest", "inner_ctrlBlock/rename/io_out_0_bits_pdest", True),
        ("rn_robIdx", "inner_ctrlBlock/rename/io_out_0_bits_robIdx_value", True),
        ("dp_valid", "inner_ctrlBlock/dispatch/io_fromRename_0_valid", False),
        ("dp_pdest", "inner_ctrlBlock/dispatch/io_fromRename_0_bits_pdest", True),
        ("dp_robIdx", "inner_ctrlBlock/dispatch/io_fromRename_0_bits_robIdx_value", True),
        ("iq_enq_valid", "%s/io_enq_0_valid" % iq, False),
        ("iq_enq_robIdx", "%s/io_enq_0_bits_robIdx_value" % iq, True),
        ("iq_deq_robIdx", "%s/deqBeforeDly_0_bits_common_robIdx_value" % iq, True),
        ("exu_in_valid", "inner_vfExuBlock/io_in_%d_0_valid" % exu_idx, False),
        ("exu_in_fuOpType", "inner_vfExuBlock/io_in_%d_0_bits_fuOpType" % exu_idx, True),
        ("exu_in_pdest", "inner_vfExuBlock/io_in_%d_0_bits_pdest" % exu_idx, True),
        ("exu_in_robIdx", "inner_vfExuBlock/io_in_%d_0_bits_robIdx_value" % exu_idx, True),
        ("vimac_in_valid", "%s/io_in_valid" % vm, False),
        ("vimac_fuOpType", "%s/io_in_bits_ctrl_fuOpType" % vm, True),
        ("vimac_src0_vs1", "%s/io_in_bits_data_src_0" % vm, True),
        ("vimac_src1_vs2", "%s/io_in_bits_data_src_1" % vm, True),
        ("fireS1", "%s/vimacs_0/io_fireS1" % vm, False),
        ("vdot_vd", "%s/vdotReduce/io_vd" % vm, True),
        ("tree_sum", "%s/vdotReduce/tree/io_out_sum" % vm, True),
        ("tree_car", "%s/vdotReduce/tree/io_out_car" % vm, True),
        ("vimac_out_valid", "%s/io_out_valid" % vm, False),
        ("vimac_out_pdest", "%s/io_out_bits_ctrl_pdest" % vm, True),
        ("vimac_res_data", "%s/io_out_bits_res_data" % vm, True),
        ("exu_out_valid", "inner_vfExuBlock/io_out_%d_0_valid" % exu_idx, False),
        ("exu_out_data_0", "inner_vfExuBlock/io_out_%d_0_bits_data_0" % exu_idx, True),
        ("exu_out_pdest", "inner_vfExuBlock/io_out_%d_0_bits_pdest" % exu_idx, True),
        ("exu_out_robIdx", "inner_vfExuBlock/io_out_%d_0_bits_robIdx_value" % exu_idx, True),
    ]
    # 8 个 16 位部分积（X15 导出的 sum_wo，tap0 接法的取数口）
    for i in range(8):
        rels.append(("sum_wo_%d" % i, "%s/vimacs_0/io_sum_wo_%d" % (vm, i), True))

    picked, missing = [], []
    for label, rel, bus in rels:
        full = rel if rel.startswith("TOP/") else (P + "/" + rel)
        if full not in names:
            missing.append((label, full))
            continue
        picked.append((label, full, bus))
    return picked, missing


def write_head(vcd, out, n):
    with open(vcd, "rb") as fh:
        buf = []
        for i, line in enumerate(fh):
            if i >= n:
                break
            buf.append(line.decode("utf-8", "replace"))
    with open(out, "w") as f:
        f.writelines(buf)


def write_scopes(scopes, picked, missing, out, meta, vcd, vcd_sha):
    with open(out, "w") as f:
        f.write("# VCD scope 索引（%s）\n" % vcd)
        f.write("# date=%s version=%s timescale=%s\n"
                % (meta["date"], meta["version"], meta["timescale"]))
        if vcd_sha:
            f.write("# vcd_sha256=%s\n" % vcd_sha)
        f.write("# scopes=%d\n\n" % len(scopes))
        for s, n in scopes.items():
            f.write("%s\t%d\n" % (s, n))
        f.write("\n# 摘录信号表（标签 | 位宽 | 完整层次名）\n")
        for label, full, bus in picked:
            f.write("%s | %s | %s\n" % (label, "bus" if bus else "1", full))
        f.write("\n# MISSING（VCD 中不存在，未静默跳过）\n")
        for label, full in missing:
            f.write("- %s -> %s\n" % (label, full))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcd", required=True)
    ap.add_argument("--instr", default="0x3A20A1D7")
    ap.add_argument("--expect", default="0x00008780")
    ap.add_argument("--excerpt", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--scopes", required=True)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--json", required=True)
    ap.add_argument("--vcd-sha256", default="")
    ap.add_argument("--pre", type=int, default=40)
    ap.add_argument("--post", type=int, default=60)
    ap.add_argument("--span", type=int, default=200)
    ap.add_argument("--head-lines", type=int, default=40)
    ap.add_argument("--no-verify", action="store_true")
    a = ap.parse_args()

    target = int(a.instr, 0)
    expect = int(a.expect, 0) & 0xFFFFFFFF
    checks = []

    def add_check(name, expected, actual, ok):
        checks.append({"name": name, "expected": expected, "actual": actual,
                       "pass": bool(ok)})

    # ---------------- pass 1：header + 锚点 / 结果拍
    with open(a.vcd, errors="replace") as fh:
        names, scopes, meta = parse_header(fh)
        if not names or not meta["timescale"]:
            print("[FATAL] VCD header 解析失败（vars=%d timescale=%r）"
                  % (len(names), meta["timescale"]), file=sys.stderr)
            return 2
        add_check("header_ok", "timescale 可解析且 vars/scopes 非零",
                  "timescale=%s vars=%d scopes=%d"
                  % (meta["timescale"], len(names), len(scopes)),
                  bool(meta["timescale"]) and len(names) > 0)

        # 译码 6 槽
        slot_codes = {}
        for i in range(6):
            ni = "%s/inner_ctrlBlock/decode/io_in_%d_bits_instr" % (P, i)
            nv = "%s/inner_ctrlBlock/decode/io_in_%d_valid" % (P, i)
            if ni in names and nv in names:
                slot_codes[names[ni][0]] = (i, names[nv][0])

        # Vimac 执行体、它所在的 exu、Vimac 那条 IQ（按 scope 名反查，不硬编码序号）
        vimac_scope = find_scope(scopes, lambda s: s.endswith("/inner_vfExuBlock/exus/Vimac"))
        exu_scope = vimac_scope.rsplit("/", 1)[0] if vimac_scope else None
        iq_scope = find_scope(scopes, lambda s: "/inner_vfScheduler/" in s
                              and s.rsplit("/", 1)[-1].startswith("IssueQueue")
                              and "Vimac" in s.rsplit("/", 1)[-1])
        if not vimac_scope or not exu_scope or not iq_scope:
            print("[FATAL] 找不到 Vimac 执行体 / exu / IQ scope（vimac=%s exu=%s iq=%s）"
                  % (vimac_scope, exu_scope, iq_scope), file=sys.stderr)
            return 2
        vd_code = names["%s/vdotReduce/io_vd" % vimac_scope][0] if \
            "%s/vdotReduce/io_vd" % vimac_scope in names else None
        res_code = names["%s/io_out_bits_res_data" % vimac_scope][0] if \
            "%s/io_out_bits_res_data" % vimac_scope in names else None
        ov_code = names["%s/io_out_valid" % vimac_scope][0] if \
            "%s/io_out_valid" % vimac_scope in names else None
        fu_code = names["%s/io_in_bits_ctrl_fuOpType" % vimac_scope][0] if \
            "%s/io_in_bits_ctrl_fuOpType" % vimac_scope in names else None
        iv_code = names["%s/io_in_valid" % vimac_scope][0] if \
            "%s/io_in_valid" % vimac_scope in names else None

        # 注意：`io_in_<slot>_valid` 的 code 也在 slot_codes.values() 里，必须一起跟踪，
        # 否则 last[] 里永远没有 valid 的值（本工具首版就踩了这个：候选全 False）。
        watch = {c for c in (vd_code, res_code, ov_code, fu_code, iv_code) if c}
        tracked = set(slot_codes) | {vc for _, vc in slot_codes.values()} | watch
        last = {}
        hits = []
        anchor = anchor_slot = None
        res_time = wb_time = None
        fu_at_exec = None
        res_at_wb = None
        t_min = t_max = None
        samples = 0
        for t, ch in iter_blocks(fh):
            if t_min is None:
                t_min = t
            t_max = t
            samples += 1
            for c, v in ch:
                if c in tracked:
                    last[c] = v
            # 锚点：指令字在译码槽里且该槽 valid=1
            for c, v in ch:
                if c not in slot_codes:
                    continue
                iv = vint(v)
                if iv is None or (iv & 0xFFFFFFFF) != target:
                    continue
                slot, vcode = slot_codes[c]
                ok = (vint(last.get(vcode)) == 1)
                hits.append((t, slot, ok))
                if ok and anchor is None:
                    anchor, anchor_slot = t, slot
            # 结果必须在**锚点之后**才算数（否则窗口外的历史残留值会冒充命中）
            if vd_code and res_time is None and anchor is not None and t > anchor:
                val = vint(last.get(vd_code))
                if val is not None and (val & 0xFFFFFFFF) == expect:
                    res_time = t
            if res_code and ov_code and wb_time is None and anchor is not None and t > anchor:
                if vint(last.get(ov_code)) == 1:
                    val = vint(last.get(res_code))
                    if val is not None and (val & 0xFFFFFFFF) == expect:
                        wb_time = t
                        res_at_wb = val
            # 执行级 fuOpType：只认 Vimac io_in_valid=1 且 fuOpType==0x067 的那一拍
            # （该 FU 也跑 vmacc/vmul 等，取「第一个 valid 拍」会把别的指令算进来）
            if fu_code and iv_code and fu_at_exec is None:
                if vint(last.get(iv_code)) == 1:
                    cur_fu = vint(last.get(fu_code))
                    if cur_fu == VDOT_FUOPTYPE:
                        fu_at_exec = cur_fu

    if anchor is None:
        print("[FATAL] 0x%08X 在任何译码槽的 valid=1 拍都没出现（候选 %s）"
              % (target, hits), file=sys.stderr)
        return 2

    add_check("instr_hit", "0x%08X 在译码级 valid=1 命中" % target,
              "anchor_time=%d slot=%d（全 VCD 候选 %d 次）"
              % (anchor, anchor_slot, len(hits)), True)
    add_check("fuoptype_exec", "Vimac io_in_bits_ctrl_fuOpType == 0x%03X" % VDOT_FUOPTYPE,
              "0x%03X" % fu_at_exec if fu_at_exec is not None else "未取到",
              fu_at_exec == VDOT_FUOPTYPE)
    add_check("result_low32", "锚点之后 vdotReduce/io_vd 低 32 位 == 0x%08X" % expect,
              ("t=%d" % res_time) if res_time is not None else "锚点之后未出现该值",
              res_time is not None)
    hi_zero = None
    if res_at_wb is not None:
        hi_zero = (res_at_wb & HIGH_ZERO_MASK) == 0
    add_check("high96_zero", "写回 res_data[127:32] == 0",
              ("t=%d res_data=0x%032X" % (wb_time, res_at_wb)) if res_at_wb is not None
              else "未取到写回值", bool(hi_zero))
    add_check("wb_after_anchor", "写回拍 > 译码锚点",
              ("wb=%s anchor=%d" % (wb_time, anchor)), wb_time is not None and wb_time > anchor)

    # ---------------- 窗口
    hi = anchor + a.span
    for t in (res_time, wb_time):
        if t is not None:
            hi = max(hi, t + a.post)
    hi = min(hi, t_max)
    lo = max(0, anchor - a.pre)
    add_check("ts_range", "VCD 时间戳范围 [min,max]",
              "[%d,%d] 采样点=%d；摘录窗口=[%d,%d]" % (t_min, t_max, samples, lo, hi),
              t_min is not None and t_max is not None)

    picked, missing = build_signals(names, anchor_slot, vimac_scope, exu_scope, iq_scope)
    if not picked:
        print("[FATAL] 摘录信号表全部缺失", file=sys.stderr)
        return 2

    # ---------------- pass 2：抽值（前向填值 + 窗口首拍锁定）+ 写摘录
    # **别名处理（2026-11-06 修订）**：Verilator 复用 VCD 标识符，同一个 code 可对应多个
    # 层次名（实测 Vimac/io_in_bits_ctrl_fuOpType 与 exu/io_in_0_0_bits_fuOpType 同为 `z+9`，
    # 共 21 条路径）。早先版本用 `code2label = {code: label}`（一对一）⇒ 同一 code 的后一个标签
    # 覆盖前一个，前一个标签**整条没有值**、被自校验的 `exp is None and got is None` 静默跳过
    # （实测 checked=9648=48×201，而 49 信号×201 拍应为 9849）。这类别名是**同一条网线**
    # （连线合并），值必然相同，所以正确做法是 code→**标签列表**，两个标签都取同一批值。
    want = OrderedDict((full, label) for label, full, _ in picked)
    code2labels = {}
    for full, label in want.items():
        code2labels.setdefault(names[full][0], []).append(label)
    alias_groups = [[lab for lab in labs] for labs in code2labels.values() if len(labs) > 1]
    carry = {}
    times = []
    src_vals = {label: {} for label in want.values()}
    seeded = False
    with open(a.vcd, errors="replace") as fh:
        parse_header(fh)
        for t, ch in iter_blocks(fh):
            if t > hi:
                break
            for c, v in ch:
                if c in code2labels:
                    carry[c] = v
            if lo <= t <= hi:
                if not seeded:
                    for c, v in carry.items():
                        for lab in code2labels[c]:
                            src_vals[lab][t] = v
                    seeded = True
                for c, v in ch:
                    if c in code2labels:
                        for lab in code2labels[c]:
                            src_vals[lab][t] = v
                times.append(t)

    # 每个标签在窗口内逐拍补齐（未变化的沿用前值）
    filled = {}
    for label in want.values():
        cur = None
        row = {}
        for t in times:
            if t in src_vals[label]:
                cur = src_vals[label][t]
            row[t] = cur
        filled[label] = row

    codes = {label: "sig%d" % i for i, label in enumerate(want.values())}
    # 时钟口径（2026-11-06 修 P2）：Verilator 每拍（时钟沿）dump 一次 ⇒ 采样域里 clock 恒为 1、
    # 全 VCD 只变化 1 次（实测 t=8365 由 x 置 1 后不再翻转，而摘录窗口 [8377,8577] 在其之后 ⇒
    # 窗口内 0 次翻转）。GTKWave 打开摘录时看到的是「恒高的时钟」，这是**采样语义**而不是
    # 驱动缺失；必须写进摘录头与摘要，否则会被读成缺陷。
    clk_lab = "clock" if "clock" in filled else None
    clk_changes = 0
    clk_vals = []
    if clk_lab:
        prev = None
        for t in times:
            v = filled[clk_lab][t]
            # 只数**窗口内**的翻转：首个采样点不计（它是窗口首拍的稳态值，其置位可能发生在
            # 窗口之前；把 seed 计成 1 次会与「窗口内 0 次」的独立复算冲突）
            if v is not None and prev is not None and v != prev:
                clk_changes += 1
            if v is not None:
                prev = v
                clk_vals.append(v)
    clk_note = ("clock 为采样域时钟：每拍一个时间戳、每拍 dump 一次 ⇒ 摘录里恒为 %s、窗口内变化 %d 次；"
                "GTKWave 中不会翻转，属采样语义而非缺驱动"
                % (("1" if clk_vals and all(vint(v) == 1 for v in clk_vals) else "见值"), clk_changes)
                if clk_lab else "摘录未含 clock（信号表里没有该路径）")
    with open(a.excerpt, "w") as f:
        f.write("$date %s $end\n" % (meta["date"] or "unknown"))
        f.write("$version vdot_wave_excerpt (extracted from %s) $end\n" % os.path.basename(a.vcd))
        f.write("$timescale %s $end\n" % meta["timescale"])
        f.write("$comment vdot.vv narrow-window key-signal excerpt; timestamps are the source"
                " VCD cycle numbers (not renumbered); label->full-path map is in the scopes file $end\n")
        f.write("$comment %s $end\n" % clk_note)
        if alias_groups:
            f.write("$comment aliased signals (同一 VCD 标识符 = 同一条网线，值必然相同): %s $end\n"
                    % "; ".join("+".join(g) for g in alias_groups))
        f.write("$scope module vdot_wave $end\n")
        for label, full, bus in picked:
            w = names[full][1]
            rng = "" if w == 1 else " [%d:0]" % (w - 1)
            f.write(" $var wire %d %s %s%s $end\n" % (w, codes[label], label, rng))
        f.write("$upscope $end\n")
        f.write("$enddefinitions $end\n\n")
        # body：首拍把窗口内的稳态值全部写出，其后只在值变化时写（VCD 语义）
        if times:
            f.write("#%d\n" % times[0])
            for label in want.values():
                v = filled[label][times[0]]
                if v is not None:
                    f.write(emit(v, codes[label]) + "\n")
            prev = {label: filled[label][times[0]] for label in want.values()}
            for t in times[1:]:
                f.write("#%d\n" % t)
                for label in want.values():
                    v = filled[label][t]
                    if v is not None and v != prev[label]:
                        f.write(emit(v, codes[label]) + "\n")
                        prev[label] = v

    # ---------------- 摘录回读自校验（非伪造的机械判据）
    ok_verify = True
    detail = "skipped(--no-verify)"
    if not a.no_verify:
        # 摘录与源一样「只在变化时写」，所以回读也必须前向填值再逐拍比对。
        reread = {label: {} for label in want.values()}
        code_back = {codes[label]: label for label in want.values()}
        cur2 = {}
        with open(a.excerpt, errors="replace") as fh:
            parse_header(fh)
            for t, ch in iter_blocks(fh):
                for c, v in ch:
                    if c in code_back:
                        cur2[code_back[c]] = v
                for lab in want.values():
                    if lab in cur2:
                        reread[lab][t] = cur2[lab]
        bad = 0
        checked = 0
        unseeded = []   # 窗口内**整条没有源值**的信号：早先版本会被 `exp is None and got is None` 静默跳过
        for label in want.values():
            if all(filled[label][t] is None for t in times):
                unseeded.append(label)
                continue
            for t in times:
                exp = filled[label][t]
                got = reread[label].get(t)
                if exp is None and got is None:
                    continue
                checked += 1
                if exp != got:
                    bad += 1
                    if bad <= 5:
                        print("[VERIFY] %s@%d 源=%r 摘录=%r" % (label, t, exp, got),
                              file=sys.stderr)
        # 覆盖数判据：每个有值的信号必须逐拍都进 checked ⇒ checked 应等于 Σ(该信号有值的拍数)。
        expect_checked = sum(1 for label in want.values() for t in times
                             if filled[label][t] is not None)
        ok_verify = bad == 0 and not unseeded and checked == expect_checked
        detail = ("checked=%d/%d mismatches=%d unseeded=%d%s"
                  % (checked, expect_checked, bad, len(unseeded),
                     ("(" + ",".join(unseeded) + ")") if unseeded else ""))
    add_check("excerpt_verify", "摘录回读逐拍与源 VCD 一致（且每个有值信号都被覆盖）", detail, ok_verify)

    # ---------------- 输出体检件
    write_head(a.vcd, a.head, a.head_lines)
    write_scopes(scopes, picked, missing, a.scopes, meta, a.vcd, a.vcd_sha256)

    verdict = "OK" if all(c["pass"] for c in checks) else "FAIL"
    payload = OrderedDict([
        ("schema", "vdot-wave-health/1"),
        ("vcd", a.vcd),
        ("vcd_bytes", os.path.getsize(a.vcd)),
        ("vcd_sha256", a.vcd_sha256),
        ("excerpt", a.excerpt),
        ("excerpt_bytes", os.path.getsize(a.excerpt)),
        ("timescale", meta["timescale"]),
        ("vars", len(names)),
        ("scopes", len(scopes)),
        ("time_min", t_min),
        ("time_max", t_max),
        ("samples", samples),
        ("excerpt_window", [lo, hi]),
        ("instr", "0x%08X" % target),
        ("anchor_time", anchor),
        ("anchor_slot", anchor_slot),
        ("decode_hits", [list(h) for h in hits]),
        ("expect_low32", "0x%08X" % expect),
        ("result_time", res_time),
        ("wb_time", wb_time),
        ("wb_res_data", ("0x%032X" % res_at_wb) if res_at_wb is not None else None),
        ("fuoptype_at_exec", ("0x%03X" % fu_at_exec) if fu_at_exec is not None else None),
        ("signals_picked", len(picked)),
        ("signals_missing", ["%s -> %s" % m for m in missing]),
        # 别名披露（2026-11-06）：同一 VCD 标识符对应的标签组。它们值必然相同（同一网线），
        # 摘录里各自独立成 var，但**不是**互相独立的观测点，下游不得当作「N 个独立证据」。
        ("aliased_label_groups", alias_groups),
        ("clock_note", clk_note),
        ("checks", checks),
        ("verdict", verdict),
    ])
    with open(a.json, "w") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")

    lines = []
    lines.append("===== vdot 波形体检 =====")
    lines.append("vcd            : %s (%d B)" % (a.vcd, payload["vcd_bytes"]))
    lines.append("vcd_sha256     : %s" % (a.vcd_sha256 or "NA"))
    lines.append("timescale      : %s" % meta["timescale"])
    lines.append("vars / scopes  : %d / %d" % (len(names), len(scopes)))
    lines.append("时间戳范围     : [%d, %d] 采样点=%d" % (t_min, t_max, samples))
    lines.append("摘录窗口       : [%d, %d]" % (lo, hi))
    lines.append("指令机器码     : 0x%08X  锚点拍=%d 槽=%d（候选 %d 次）"
                 % (target, anchor, anchor_slot, len(hits)))
    lines.append("执行级 fuOpType: %s（期望 0x%03X）"
                 % (payload["fuoptype_at_exec"], VDOT_FUOPTYPE))
    lines.append("结果拍         : %s" % (res_time if res_time is not None else "未出现"))
    lines.append("写回拍/res_data: %s / %s" % (wb_time, payload["wb_res_data"]))
    lines.append("摘录信号       : 取到 %d 个，缺失 %d 个" % (len(picked), len(missing)))
    lines.append("别名组         : %d 组（同一 VCD 标识符 = 同一条网线，值必然相同、非独立观测点）"
                 % len(alias_groups))
    for g in alias_groups:
        lines.append("  [ALIAS] %s" % " + ".join(g))
    lines.append("时钟口径       : %s" % clk_note)
    for m in missing:
        lines.append("  [MISSING] %s -> %s" % m)
    lines.append("摘录文件       : %s (%d B)" % (a.excerpt, payload["excerpt_bytes"]))
    lines.append("")
    for c in checks:
        lines.append("[%s] %-16s 期望=%s | 实测=%s"
                     % ("PASS" if c["pass"] else "FAIL", c["name"], c["expected"], c["actual"]))
    lines.append("")
    lines.append("verdict=%s" % verdict)
    with open(a.summary, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if verdict == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
