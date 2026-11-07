#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从香山 emu 的 VCD 里抽出 vadd.vv 的七级流水证据（交付物 1.3 主工具）。

--------------------------------------------------------------------------
为什么用 debug_seqNum 而不是 pc/instr 当关联键
--------------------------------------------------------------------------
实测（2026-11-03 作业 126690786 的 VCD vadd_wave_20261103T164323.vcd）踩到三个坑：

1) **Verilator 复用 VCD 标识符**。同一根网在多级层次里共用同一个 code：实测
   1,357,193 个完整名字只对应 703,548 个 code，单个 code 最多被 35,439 个名字共用。
   按 code 建索引会把 `decode/io_in_0_bits_instr` 覆盖成别的 scope 的同名信号。
   ⇒ 本脚本按**完整层次名**建索引，再反查 code。

2) **vadd.vv 不落在译码 0 号槽**。译码 6 路（DecodeWidth=6），目标指令实测落在
   `io_in_2`（slot 2），真锚点 t=8416（`valid=1`）。只看 slot 0 会得出
   「窗口没套住」的假结论（最初只扫 slot 0 时曾得到该错误结论）。
   ⇒ 扫全部 6 槽，取 `valid=1` 的那一次。

3) **pc 不唯一**。多条指令共用同一 pc 视图，按 pc 命中会误判。
   ⇒ 用 `debug_seqNum_seqNum`（56 位指令唯一序号）做跨级关联键；实测它在
      decode/io_in_<slot> → decode/io_out_0 → rename/io_out_0 →
      dispatch/io_fromRename_0 → vfExuBlock/io_in_2_0 → vfExuBlock/io_out_2_0
      逐级都在。

--------------------------------------------------------------------------
七级信号（路径全部实测自本仓 RTL 生成的 VCD，层次前缀 P = TOP/SimTop/cpu/l_soc/core_with_l2/core/backend）
--------------------------------------------------------------------------
  IF 取指  decode/io_in_<slot>_bits_{pc,instr,debug_seqNum_seqNum}、_valid、_ready
  ID 译码  decode/io_out_0_bits_{instr,debug_seqNum_seqNum,fuType,fuOpType,lsrc_0,lsrc_1,
           ldest,rfSrc_0,rfSrc_1,rfDest,vecWen,vpu_vill,vpu_vm,vpu_vsew,vpu_vlmul,
           vpu_vstart,vpu_vuopIdx,vpu_vma,vpu_vta}
  RN 重命名 rename/io_out_0_{valid,bits_debug_seqNum_seqNum,bits_psrc_0,bits_psrc_1,
           bits_pdest,bits_ldest,bits_robIdx_value}
  DP 派发  dispatch/io_fromRename_0_{valid,ready,bits_debug_seqNum_seqNum}、
           dispatch/io_renameIn_0_bits_{fuType,fuOpType}
  IS 发射  inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_{valid,ready}、
           inner_bypassNetwork2vfExuBlock/io_out_{valid,ready,bits_pdest,
           bits_robIdx_value,bits_vpu_vsew,bits_vpu_vm}
  EX 执行  inner_vfExuBlock/io_in_2_0_bits_{debug_seqNum_seqNum,fuType,fuOpType,vpu_vsew,
           vpu_vlmul,vpu_vm,vpu_vstart,vpu_vuopIdx,src_0,src_1,pdest,robIdx_value}
  WB 写回  inner_vfExuBlock/io_out_2_0_{valid,bits_debug_seqNum_seqNum,bits_data_0,
           bits_pdest,bits_vecWen,bits_robIdx_value}

用法：
  python3 -I vadd_stage_extract.py --vcd X.vcd --instr 0x021101D7 \
      --out-tsv Y.tsv --out-md Y.md --out-index Z.txt [--pre 8 --post 100]
"""
import argparse
import re
import sys
from collections import OrderedDict

P = "TOP/SimTop/cpu/l_soc/core_with_l2/core/backend"
FP = "TOP/SimTop/cpu/l_soc/core_with_l2/core/frontend"


def parse_header(fh):
    """按完整层次名建索引：name -> (code, width)。见模块头 §1。"""
    names = OrderedDict()
    scopes = []
    cur = []
    date = version = timescale = ""
    while True:
        line = fh.readline()
        if not line:
            break
        t = line.strip()
        if t.startswith("$date"):
            date = t[5:].replace("$end", "").strip()
        elif t.startswith("$version"):
            version = t[8:].replace("$end", "").strip()
        elif t.startswith("$timescale"):
            timescale = t[11:].replace("$end", "").strip()
        elif t.startswith("$scope"):
            p = t.split()
            if len(p) >= 3:
                cur.append(p[2])
                scopes.append("/".join(cur))
        elif t.startswith("$upscope"):
            if cur:
                cur.pop()
        elif t.startswith("$var"):
            p = t.split()
            if len(p) >= 5:
                w = int(re.sub(r"[^0-9]", "", p[2]) or 1)
                names["/".join(cur + [p[4]])] = (p[3], w)
        elif t.startswith("$enddefinitions"):
            break
    return names, scopes, date, version, timescale


def iter_blocks(fh):
    t = None
    ch = []
    for line in fh:
        s = line.strip()
        if not s or s[0] == "$":
            continue
        if s[0] == "#":
            if t is not None:
                yield t, ch
            t = int(s[1:])
            ch = []
        elif t is not None:
            if s[0] == "b":
                p = s.split()
                if len(p) >= 2:
                    ch.append((p[1], p[0][1:]))
            else:
                ch.append((s[1:], s[0]))
    if t is not None:
        yield t, ch


def vint(v):
    if not v:
        return None
    if set(v) <= {"0", "1"}:
        return int(v, 2)
    if set(v.lower()) <= set("0123456789abcdef"):
        return int(v, 16)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcd", required=True)
    ap.add_argument("--instr", default="0x021101D7")
    ap.add_argument("--pre", type=int, default=8)
    ap.add_argument("--post", type=int, default=100)
    ap.add_argument("--out-tsv", required=True)
    ap.add_argument("--out-md", required=True)
    ap.add_argument("--out-index", required=True)
    a = ap.parse_args()
    target = int(a.instr, 0)

    # ---------------- pass 1: 全部译码槽里找 valid=1 的真锚点
    with open(a.vcd, errors="replace") as fh:
        names, scopes, date, version, ts = parse_header(fh)
        slot_codes = {}
        for i in range(6):
            ni = "%s/inner_ctrlBlock/decode/io_in_%d_bits_instr" % (P, i)
            nv = "%s/inner_ctrlBlock/decode/io_in_%d_valid" % (P, i)
            ns = "%s/inner_ctrlBlock/decode/io_in_%d_bits_debug_seqNum_seqNum" % (P, i)
            if ni in names and nv in names:
                slot_codes[names[ni][0]] = (i, names[nv][0],
                                            names[ns][0] if ns in names else None)
        if not slot_codes:
            print("[FATAL] 译码级 io_in_*_bits_instr 全部缺失", file=sys.stderr)
            return 2

        last = {}
        cands = []
        anchor = anchor_slot = anchor_seq = None
        for t, ch in iter_blocks(fh):
            for c, v in ch:
                last[c] = v
            for c, v in ch:
                if c not in slot_codes:
                    continue
                if vint(v) != target:
                    continue
                slot, vcode, scode = slot_codes[c]
                ok = (last.get(vcode, "0") == "1")
                seq = vint(last.get(scode)) if scode else None
                cands.append((t, slot, ok, seq))
                if ok and anchor is None:
                    anchor, anchor_slot, anchor_seq = t, slot, seq

    print("decode_candidates(t,slot,valid,seqNum): %s" % (cands,))
    if anchor is None:
        print("[FATAL] 0x%08X 在任何译码槽的 valid 拍都没出现" % target, file=sys.stderr)
        return 3
    print("anchor_time=%d slot=%d seqNum=%s" % (anchor, anchor_slot, anchor_seq))

    lo, hi = max(0, anchor - a.pre), anchor + a.post

    stages = [
        # IF 取指：两级实测证据
        #  a) IFU 预译码出口（frontend/inner_ifu/preDecoder）：指令第一次出现的地方，
        #     本指令在 `pd_3_instr`（实测 t=8410）
        #  b) IFU → IBuffer 的整拍指令组（io_toIbuffer_bits_instrs_*），本指令在 instrs_3
        #     （实测 t=8411）
        #  c) IBuffer → DecodeStage 的 StaticInst（DecodeStage.scala:46 `in`），t=8416
        ("IF", "取指", [
            (FP + "/inner_ifu/preDecoder/io_out_instr_3", "ifu_pd3_instr", True),
            (FP + "/inner_ifu/preDecoder/io_out_pd_3_valid", "ifu_pd3_valid", False),
            (FP + "/inner_ifu/io_toIbuffer_valid", "ifu2ib_valid", False),
            (FP + "/inner_ifu/io_toIbuffer_bits_instrs_3", "ifu2ib_instr3", True),
            ("inner_ctrlBlock/decode/io_in_%d_bits_pc" % anchor_slot, "pc", True),
            ("inner_ctrlBlock/decode/io_in_%d_bits_instr" % anchor_slot, "instr", True),
            ("inner_ctrlBlock/decode/io_in_%d_valid" % anchor_slot, "valid", False),
            ("inner_ctrlBlock/decode/io_in_%d_ready" % anchor_slot, "ready", False),
        ]),
        # ID 译码：DecodeStage.scala:48 `out`（DecodedInst）
        ("ID", "译码", [
            ("inner_ctrlBlock/decode/io_out_0_bits_instr", "instr", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_fuType", "fuType", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_fuOpType", "fuOpType", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_lsrc_0", "vs1_lsrc", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_lsrc_1", "vs2_lsrc", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_ldest", "vd_ldest", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_vecWen", "vecWen", False),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vill", "vill", False),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vm", "vm", False),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vsew", "vsew", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vlmul", "vlmul", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vstart", "vstart", True),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vma", "vma", False),
            ("inner_ctrlBlock/decode/io_out_0_bits_vpu_vta", "vta", False),
        ]),
        # RN 重命名：Rename.scala:49 `io.out`（DynInst，逻辑号→物理号）
        ("RN", "重命名", [
            ("inner_ctrlBlock/rename/io_out_0_valid", "out_valid", False),
            ("inner_ctrlBlock/rename/io_out_0_bits_psrc_0", "psrc0", True),
            ("inner_ctrlBlock/rename/io_out_0_bits_psrc_1", "psrc1", True),
            ("inner_ctrlBlock/rename/io_out_0_bits_pdest", "pdest", True),
            ("inner_ctrlBlock/rename/io_out_0_bits_ldest", "ldest", True),
            ("inner_ctrlBlock/rename/io_out_0_bits_robIdx_value", "robIdx", True),
            ("inner_ctrlBlock/rename/io_out_0_bits_vpu_vuopIdx", "vuopIdx", True),
        ]),
        # DP 派发：NewDispatch.scala（rename→dispatch 握手 + 到各 Exu 的分发视图）
        ("DP", "派发", [
            ("inner_ctrlBlock/dispatch/io_fromRename_0_valid", "in_valid", False),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_ready", "in_ready", False),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_fuType", "fuType", True),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_fuOpType", "fuOpType", True),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_pdest", "pdest", True),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_psrc_0", "psrc0", True),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_psrc_1", "psrc1", True),
            ("inner_ctrlBlock/dispatch/io_fromRename_0_bits_robIdx_value", "robIdx", True),
        ]),
        # IS 发射：向量定点 IQ（vialuFix 挂这条 IQ）。按 robIdx=0x41 反查得到**真实**时间线
        #   （实测，见 find_issue.py 输出）：
        #     8419 入队  IssueQueue.../io_enq_0_bits_robIdx_value = 0x41
        #     8494 出队  .../deqBeforeDly_0_bits_common_robIdx_value = 0x41
        #     8495 发往 dataPath  .../io_toDataPathAfterDelay_1_0_bits_common_robIdx_value
        #     8497 旁路到 exus  inner_bypassNetwork/io_toExus_vf_1_0_bits_pdest = 0x33
        #   三个 RTL 自记时间戳（Rob.scala:433-435 debugInfo.* := timer）在 8496 一拍里
        #   同时写回：enqRsTime / selectTime / issueTime。
        ("IS", "发射", [
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_valid", "iq_enq_valid", False),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_ready", "iq_enq_ready", False),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_bits_robIdx_value",
             "iq_enq_robIdx", True),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/deqBeforeDly_0_bits_common_robIdx_value",
             "deq_robIdx", True),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_deqDelay_0_valid",
             "deqDelay_valid", False),
            ("inner_vfScheduler/io_toDataPathAfterDelay_1_0_valid", "toDP_valid", False),
            ("inner_vfScheduler/io_toDataPathAfterDelay_1_0_bits_common_pdest", "toDP_pdest", True),
            ("inner_bypassNetwork/io_toExus_vf_1_0_valid", "bypass_valid", False),
            ("inner_bypassNetwork/io_toExus_vf_1_0_bits_pdest", "bypass_pdest", True),
            ("inner_bypassNetwork/io_toExus_vf_1_0_bits_robIdx_value", "bypass_robIdx", True),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_bits_debugInfo_enqRsTime",
             "enqRsTime", True),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_bits_debugInfo_selectTime",
             "selectTime", True),
            ("inner_vfScheduler/IssueQueueVfmaVialuFixVfalu/io_enq_0_bits_debugInfo_issueTime",
             "issueTime", True),
        ]),
        # EX 执行：vadd 走 vialuF → VIAluFix；**实测落在 exus_2**（按操作数数值反查：
        #   vs1=0x0807.. 与 vs2=0x8070.. 与结果 0x8877.. 都出现在 exus_2/VialuFix）
        ("EX", "执行", [
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_valid", "in_valid", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_ready", "in_ready", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_ctrl_fuOpType", "fuOpType", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_ctrl_vpu_vsew", "vsew", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_ctrl_vpu_vm", "vm", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_ctrl_vpu_vuopIdx", "vuopIdx", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_ctrlPipe_1_pdest", "pdestPipe1", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_bits_ctrl_pdest", "out_pdest", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_data_src_0", "src0_vs1", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_in_bits_data_src_1", "src1_vs2", True),
            ("inner_vfExuBlock/exus_2/VialuFix/vIntFixpAlus_0/vIntAdder64b/io_vd", "lane_sum", True),
        ]),
        # WB 写回：VIAluFix 出口（128 位结果 + pdest + vecWen）
        ("WB", "写回", [
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_valid", "valid", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_ready", "ready", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_bits_res_data", "res_data", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_bits_ctrl_pdest", "pdest", True),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_bits_ctrl_vecWen", "vecWen", False),
            ("inner_vfExuBlock/exus_2/VialuFix/io_out_bits_ctrl_robIdx_value", "robIdx", True),
        ]),
    ]

    picked, missing = [], []
    with open(a.vcd, errors="replace") as fh:
        names, _, _, _, _ = parse_header(fh)
        for sc, sn, sigs in stages:
            for rel, label, is_bus in sigs:
                key = rel if rel.startswith("TOP/") else (P + "/" + rel)
                if key not in names:
                    missing.append("%s/%s -> %s" % (sc, label, key))
                    continue
                code, w = names[key]
                picked.append((sc, sn, label, code, key, w, is_bus))

        want = {p[3]: p for p in picked}
        raw = {p[3]: {} for p in picked}
        seen = []
        # VCD 只在**值变化**时记录（实测：窗口内大量信号整段是 '-'）。
        # 因此必须从波形起点一路前向填值，只在 [lo,hi] 内收集采样点。
        carry = {}
        seeded = False
        for t, ch in iter_blocks(fh):
            if t > hi:
                break
            for c, v in ch:
                if c in want:
                    carry[c] = vint(v)
            if lo <= t <= hi:
                if not seeded:
                    # 窗口首拍：按进入窗口前的稳态值填充。否则整段不变的信号
                    # （VCD 只在值变化时记录）会整行显示 '-'，已实测复现。
                    for c in want:
                        raw[c][t] = carry.get(c)
                    seeded = True
                for c, v in ch:
                    if c in want:
                        raw[c][t] = vint(v)
                seen.append(t)

    times = sorted(set(seen))
    filled = {}
    for c, tv in raw.items():
        cur = None
        o = {}
        for t in times:
            if t in tv:
                cur = tv[t]
            o[t] = cur
        filled[c] = o

    with open(a.out_tsv, "w") as f:
        f.write("\t".join(["time"] + ["%s_%s" % (p[0], p[2]) for p in picked]) + "\n")
        for t in times:
            row = [str(t)]
            for p in picked:
                v = filled[p[3]][t]
                row.append("-" if v is None else ("%0*X" % (max(1, (p[5] + 3) // 4), v)))
            f.write("\t".join(row) + "\n")

    with open(a.out_index, "w") as f:
        f.write("# VCD 元信息\n")
        f.write("date: %s\nversion: %s\ntimescale: %s\n" % (date, version, ts))
        f.write("vars: %d\nscopes: %d\n" % (len(names), len(scopes)))
        f.write("target: 0x%08X\n" % target)
        f.write("anchor_time: %d\nanchor_slot: %d\nanchor_seqNum: %s\n"
                % (anchor, anchor_slot, anchor_seq))
        f.write("window: [%d, %d]\n" % (lo, hi))
        f.write("decode_candidates: %s\n" % (cands,))
        f.write("\n# 取到的信号（full_path | width | stage/label）\n")
        for p in picked:
            f.write("%s | %d | %s/%s\n" % (p[4], p[5], p[0], p[2]))
        f.write("\n# MISSING（VCD 中不存在，未静默跳过）\n")
        for m in missing:
            f.write("- %s\n" % m)

    with open(a.out_md, "w") as f:
        f.write("# vadd.vv 七级流水逐拍取值（VCD 抽取）\n\n")
        f.write("- VCD：`%s`\n" % a.vcd.split("/")[-1])
        f.write("- 目标指令：`0x%08X`（`vadd.vv v3, v1, v2`）\n" % target)
        f.write("- 锚点拍：**%d**（译码 slot %d，`valid=1`）\n" % (anchor, anchor_slot))
        f.write("- 指令字贯穿校验：译码/执行/写回的 instr 与操作数逐位比对\n")
        f.write("- 窗口：`[%d, %d]`\n" % (lo, hi))
        f.write("- timescale=%s；VCD vars=%d scopes=%d\n\n" % (ts, len(names), len(scopes)))
        for sc, sn, sigs in stages:
            rows = [p for p in picked if p[0] == sc]
            f.write("## %s %s\n\n" % (sc, sn))
            if not rows:
                f.write("（本级无可取信号）\n\n")
                continue
            f.write("| 信号 | 位宽 | " + " | ".join(str(t) for t in times) + " |\n")
            f.write("|---|---|" + "---|" * len(times) + "\n")
            for p in rows:
                vals = []
                for t in times:
                    v = filled[p[3]][t]
                    vals.append("-" if v is None else "%X" % v)
                f.write("| `%s` | %d | %s |\n" % (p[2], p[5], " | ".join(vals)))
            f.write("\n")
        if missing:
            f.write("## MISSING\n\n")
            for m in missing:
                f.write("- `%s`\n" % m)
    print("ok tsv=%s md=%s index=%s" % (a.out_tsv, a.out_md, a.out_index))
    return 0


if __name__ == "__main__":
    sys.exit(main())