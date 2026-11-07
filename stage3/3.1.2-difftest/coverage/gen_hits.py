#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_hits.py — 从「存量 30 份逐用例日志 + 30 个 .bin」机械生成 vdot 覆盖命中表。

为什么需要它：`stage3/3.1.2-difftest/coverage/matrix.md` 的每一格都必须可复算，
不能手填。本脚本产出两个机读件：
  · hits.tsv        长表：cid × coverpoint → hit/partial/miss/na + 依据 + 证据串
  · summary.tsv     每个 coverpoint 的命中例数 / 覆盖状态 / 缺口
再可选解析 `statistics.py` 的结构覆盖报告，产出 `vdot-structural.tsv`。

用法（本地，零机时）：
  python3 -I stage3/3.1.2-difftest/coverage/gen_hits.py \
      --manifest design/verify/cases/manifest.tsv \
      --logs stage3/3.1.2-difftest/full-logs-20261103T142246 \
      --log-suffix .20261103T142246.log \
      --bins design/verify/cases \
      --out stage3/3.1.2-difftest/coverage

  # 实跑后（95-coverage.sh 产出）再解析结构覆盖：
  python3 -I .../gen_hits.py --statistics results/coverage/<runid>/merged.coverage/coverage_SimTop.log \
      --out results/coverage/<runid>

判定口径（写进 matrix.md §0，别处引用同一句）：
  hit     = 该例在本 coverpoint 上有**独立**证据（运行日志串 或 二进制/源码静态事实），且该例合法执行（trap 域则要求 HIT CRITICAL ERROR）
  partial = 只在部分 bin 上命中，或只有 --no-diff 自检（缺 difftest 比对）
  miss    = 该例不具备该 coverpoint 的条件（该格对它是 ✗）
  na      = 该 coverpoint 对该例不适用（结构性不可达 / 域不匹配）
覆盖状态（summary.tsv）由命中例数派生：
  covered = ≥2 例命中；thin = 1 例；partial = 只有 partial；gap = 0
"""
import argparse
import glob
import os
import re
import struct
import sys

# ---------------------------------------------------------------- coverpoints
# (id, name, act4_ref, sampling, note)
# act4_ref 缩写：std-vec:L = coverpoints/general/RISCV_coverage_standard_coverpoints_vector.svh:L
#               Vx8:L    = coverpoints/unpriv/Vx8_coverage.svh:L
#                 （commit 8b9ddedcd44a2721dd9153efb4c64fc812090148，分支 act4）
CPS = [
    ("F01", "vstart_zero", "std-vec:31", "legal", "vstart==0 才命中；ACT4 无 vstart!=0 的 bin"),
    ("F02", "vstart_nonzero_trap", "无（自定义扩展）", "trap", "vstart!=0 ⇒ 非法；ACT4 模板无此 bin"),
    ("F03", "vl_max", "std-vec:109", "legal", "vl==VLMAX；SEW=8/LMUL=1 ⇒ VLEN/8=16"),
    ("F04", "vl_not_max", "std-vec:114", "legal", "0<vl<VLMAX"),
    ("F05", "vl_zero_full_write", "Vx8:88 cp_vl_0", "legal", "vl=0 仍全写 vd（SPEC §1.1 明确偏离 RVV）"),
    ("F06", "vtype_prev_vill_clear", "std-vec:23", "legal", "vill==0"),
    ("F07", "vtype_prev_vill_set_trap", "std-vec:27", "trap", "vill==1 ⇒ 非法"),
    ("F08", "cp_csr_vtype_vta", "Vx8:206", "legal", "vta ∈ {0,1}"),
    ("F09", "cp_csr_vtype_vma", "Vx8:210", "legal", "vma ∈ {0,1}"),
    ("F10", "cr_vtype_agnostic", "Vx8:218（裁剪）", "legal", "vta×vma 四组合；ACT4 原 cross 的 mask bin 对 vdot 不可达"),
    ("F11", "vm_unmasked", "std-vec:40 的反面", "legal", "vm==1（ACT4 mask_enabled 只收 vm==0，对 vdot 合法域不可达）"),
    ("F12", "mask_enabled_trap", "std-vec:40（bin enabled={0}）", "trap", "vm==0 ⇒ 非法（vdot 强制 unmasked）"),
    ("F13", "vd_eq_vs1", "std-vec:85", "legal", "vd==vs1（5 位全等；ACT4 的 [24:21]==[11:8] 会误报，不照抄）"),
    ("F14", "vd_eq_vs2", "std-vec:89", "legal", "vd==vs2"),
    ("F15", "vs2_eq_vs1", "std-vec:93", "legal", "vs1==vs2（30 例缺口）"),
    ("F16", "vtype_sew_8", "std-vec:216", "legal", "SEW=8"),
    ("F17", "sew_ne_8_trap", "无（自定义）", "trap", "SEW!=8 ⇒ 非法"),
    ("F18", "vtype_lmul_1", "std-vec:172", "legal", "LMUL=1"),
    ("F19", "lmul_ne_1_trap", "无（自定义）", "trap", "LMUL∈{2,4,8} ⇒ 非法"),
    ("F20", "vs_off_trap", "std-vec:64 std_trap_vec 的补集", "trap", "mstatus.VS=OFF ⇒ 非法"),
    ("F21", "vs1_vs2_edges", "Vx8:106,138", "legal", "±127/±128/0/累加溢出（官方 docx/04:94）"),
    ("F22", "random_groups", "ACT4 约束随机（生成侧）", "legal", "随机 1024 组"),
    ("F23", "hi96_zero", "无（自定义）", "legal", "vd[127:32] 恒 0"),
    ("F24", "vd_changed_value", "std-vec:290（近似）", "legal", "旧 vd 非零不参与结果"),
    ("F25", "vxsat_unchanged", "无（自定义）", "legal", "vxsat 前后不变"),
    ("F26", "back_to_back_raw", "无（自定义）", "legal", "背靠背 / RAW / 混发"),
    ("F27", "high64_interference", "无（自定义）", "legal", "vs1/vs2[127:64] 高 64 位不参与"),
    ("F28", "reg_index_space", "std-vec:73,77,81", "legal", "vd/vs1/vs2 全 32 寄存器索引"),
    ("F29", "sign_mix", "官方 2.3.1–2.3.3", "legal", "正/负/混合符号"),
]
CP_IDS = [c[0] for c in CPS]
CP_BY_ID = {c[0]: c for c in CPS}

# --------------------------------------------------------------- encoding
VDOT_OPCODE = 0x57
VDOT_FUNCT3 = 2
VDOT_FUNCT6 = 0x0E


def scan_bin(path):
    """扫 2 字节对齐的 vdot 编码：返回 [(offset, vm, vd, vs1, vs2, word)]。"""
    out = []
    with open(path, "rb") as f:
        data = f.read()
    for off in range(0, max(0, len(data) - 3), 2):
        (w,) = struct.unpack_from("<I", data, off)
        if (w & 0x7F) != VDOT_OPCODE:
            continue
        if ((w >> 12) & 7) != VDOT_FUNCT3:
            continue
        if ((w >> 26) & 0x3F) != VDOT_FUNCT6:
            continue
        out.append((off, (w >> 25) & 1, (w >> 7) & 0x1F, (w >> 15) & 0x1F, (w >> 20) & 0x1F, w))
    return out


def read_text(path):
    with open(path, "rb") as f:
        raw = f.read()
    return raw.decode("utf-8", "replace")


MATRIX_RE = {
    "vlinvar": re.compile(r"^MATRIX vlinvar vl=(\d+) .* (OK|FAIL)", re.M),
    "vta_vma": re.compile(r"^MATRIX vta=(\d) vma=(\d) .* (OK|FAIL)", re.M),
    "vxsat": re.compile(r"^MATRIX vxsat before=(\S+) after=(\S+) (OK|FAIL)", re.M),
}


def parse_case(cid, cls, extra, log_path, bin_path):
    rec = {
        "cid": cid, "cls": cls, "extra": extra, "log": log_path, "bin": bin_path,
        "good": 0, "abort": 0, "bad": 0, "crit": 0,
        "match": 0, "mismatch": 0,
        "vlinvar": {}, "vta_vma": [], "vxsat": None,
        "rand": None, "mix_ok": 0, "perf_ok": 0, "probe_ok": 0,
        "encs": [], "has_vdot": False, "hi96_assert": False, "vl_fixed": None,
        "sets_vstart": False, "sets_vill": False, "clears_vs": False, "sew": None, "lmul": None,
        "operands": [], "operand_random": False, "expect_s": None,
    }
    if log_path and os.path.isfile(log_path):
        t = read_text(log_path)
        rec["good"] = len(re.findall(r"HIT GOOD TRAP", t))
        rec["abort"] = len(re.findall(r"ABORT", t))
        rec["bad"] = len(re.findall(r"HIT BAD TRAP", t))
        rec["crit"] = len(re.findall(r"HIT CRITICAL ERROR", t))
        rec["match"] = len(re.findall(r"^CASE %s: MATCH" % re.escape(cid), t, re.M))
        rec["mismatch"] = len(re.findall(r"^CASE %s: MISMATCH" % re.escape(cid), t, re.M))
        for m in MATRIX_RE["vlinvar"].finditer(t):
            rec["vlinvar"][int(m.group(1))] = m.group(2)
        for m in MATRIX_RE["vta_vma"].finditer(t):
            rec["vta_vma"].append((int(m.group(1)), int(m.group(2)), m.group(3)))
        m = MATRIX_RE["vxsat"].search(t)
        if m:
            rec["vxsat"] = (m.group(1), m.group(2), m.group(3))
        m = re.search(r"RAND_SUMMARY groups=(\d+) mism=(\d+) ab_bad=(\d+)", t)
        if m:
            rec["rand"] = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        rec["mix_ok"] = len(re.findall(r"^MIX verdict=ALL_OK fails=0", t, re.M))
        rec["perf_ok"] = len(re.findall(r"^PERF_[A-Z_]* verdict=ALL_OK", t, re.M))
        rec["probe_ok"] = len(re.findall(r"^PROBE p3_vdot .*", t, re.M))
    if bin_path and os.path.isfile(bin_path):
        rec["encs"] = scan_bin(bin_path)
        rec["has_vdot"] = bool(rec["encs"])
    # 源码静态事实（与 .c 同目录同名；没有源码就跳过）
    src = os.path.splitext(bin_path)[0] + ".c" if bin_path else ""
    if src and os.path.isfile(src):
        s = read_text(src)
        rec["hi96_assert"] = ("hi=[" in s) or ("hi_nonzero" in s) or ("ab_bad" in s)
        rec["sets_vstart"] = bool(re.search(r"csrw\s+0x008", s))
        rec["sets_vill"] = bool(re.search(r"vsetvl\s+zero,\s*t5,\s*t4", s))
        rec["clears_vs"] = bool(re.search(r"csrc\s+mstatus", s))
        m = re.search(r"li t1,\s*(\d+)", s)
        if m:
            rec["vl_fixed"] = int(m.group(1))
        if re.search(r"vsetvli zero, t\d+, e16,", s):
            rec["sew"] = 16
        elif re.search(r"vsetvli zero, t\d+, e8\s*,", s):
            rec["sew"] = 8
        for lm, pat in ((2, r"e8\s*,\s*m2"), (4, r"e8\s*,\s*m4"), (8, r"e8\s*,\s*m8")):
            if re.search(pat, s):
                rec["lmul"] = lm
                break
        if rec["lmul"] is None and re.search(r"e8\s*,\s*m1", s):
            rec["lmul"] = 1
        # 操作数数组（int8_t x[8|16] = {...}）：用于符号组合 / 边界值两个 bin 级 coverpoint
        vals = []
        for m in re.finditer(r"int8_t\s+\w+\s*\[\s*\d+\s*\]\s*=\s*\{([^}]*)\}", s):
            for tok in m.group(1).split(","):
                tok = tok.strip()
                if re.fullmatch(r"-?\d+", tok):
                    vals.append(int(tok))
        rec["operands"] = vals
        rec["operand_random"] = bool(re.search(r"lcg\(&seed\)", s))
        # 打印的判决值（result/expect）：用于阈值/溢出 bin
        m = re.search(r"expect=0x([0-9A-Fa-f]{8})", s)
        if m:
            v = int(m.group(1), 16)
            rec["expect_s"] = v - (1 << 32) if v & 0x80000000 else v
    # 合法执行：GOOD TRAP ∧ 无 ABORT ∧ 无 BAD TRAP ∧ 非 negative 类
    rec["legal_exec"] = (
        cls != "negative" and rec["good"] >= 1 and rec["abort"] == 0 and rec["bad"] == 0
    )
    rec["trap_exec"] = cls == "negative" and rec["crit"] >= 1 and rec["abort"] == 0
    rec["vd_set"] = sorted({e[2] for e in rec["encs"]})
    rec["vs1_set"] = sorted({e[3] for e in rec["encs"]})
    rec["vs2_set"] = sorted({e[4] for e in rec["encs"]})
    rec["any_eq_vd_vs1"] = any(e[2] == e[3] for e in rec["encs"])
    rec["any_eq_vd_vs2"] = any(e[2] == e[4] for e in rec["encs"])
    rec["any_eq_vs1_vs2"] = any(e[3] == e[4] for e in rec["encs"])
    rec["any_vm0"] = any(e[1] == 0 for e in rec["encs"])
    return rec


# --------------------------------------------------------------- per-cell rules
def cell(rec, cp):
    """返回 (status, basis, evidence)。status ∈ {hit, partial, miss, na}"""
    cid, cls = rec["cid"], rec["cls"]
    legal, trap = rec["legal_exec"], rec["trap_exec"]
    g0 = cls == "g0"

    # 不发射 vdot 的用例对任何 vdot coverpoint 都是 na（不是 miss）：
    # 二进制扫描 0 个 vdot 编码的例（vadd-microbench / perf_base / perf_vadd / perf_vmacc）
    # 只能提供共享向量通路的结构覆盖，不能充当功能 coverpoint 的命中格。
    if not rec["has_vdot"]:
        return "na", "bin", "二进制无 vdot 编码，不发射 vdot"

    if cp == "F01":  # vstart_zero, legal 域
        if not (legal or g0):
            return "na", "-", "非合法执行（%s）" % (cls if cls else "?")
        if rec["sets_vstart"]:
            return "miss", "static", "源码写 vstart（该例不满足 vstart==0）"
        return "hit", "static+legal", "源码无 `csrw 0x008`；GOOD TRAP=%d ABORT=0" % rec["good"]

    if cp == "F02":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["sets_vstart"] and trap:
            return "hit", "static+runtime", "csrw 0x008 后 vdot；HIT CRITICAL ERROR=%d" % rec["crit"]
        return "miss", "static", "源码未设 vstart≠0"

    if cp == "F03":  # vl==16
        if not legal:
            return "na", "-", "非合法执行"
        if rec["vl_fixed"] == 16:
            return "hit", "static+legal", "源码 `li t1,16`；GOOD TRAP=%d" % rec["good"]
        if 16 in rec["vlinvar"]:
            return "hit", "runtime", "`MATRIX vlinvar vl=16`（无此串则 miss）"
        return "miss", "static", "源码 vl=%s（≠VLMAX=16）" % rec["vl_fixed"]

    if cp == "F04":  # 0<vl<16
        if not legal:
            return "na", "-", "非合法执行"
        got = [v for v, st in rec["vlinvar"].items() if 0 < v < 16 and st == "OK"]
        if got:
            return "hit", "runtime", "MATRIX vlinvar vl=%s OK" % ",".join(map(str, sorted(got)))
        if rec["vl_fixed"] is not None and 0 < rec["vl_fixed"] < 16:
            return "hit", "static+legal", "源码 `li t1,%d`" % rec["vl_fixed"]
        if rec["vl_fixed"] == 16:
            # rand 的 vl=16 单次；matrix 的 vl=1..8 另有行
            return "miss", "static", "源码固定 vl=16"
        return "miss", "static", "vl 未定"

    if cp == "F05":  # vl=0 仍全写
        if rec["vlinvar"].get(0) == "OK":
            return "hit", "runtime", "MATRIX vlinvar vl=0 … OK（hi_nonzero=000）"
        return ("na" if not legal else "miss"), "static", "无 vl=0 运行行"

    if cp == "F06":  # vill==0
        if not legal:
            return "na", "-", "非合法执行"
        if rec["sets_vill"]:
            return "miss", "static", "源码写入 vill=1"
        return "hit", "static+legal", "未写非法 vtype；GOOD TRAP=%d" % rec["good"]

    if cp == "F07":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["sets_vill"] and trap:
            return "hit", "static+runtime", "vsetvl(0x38) 后 vdot；HIT CRITICAL ERROR=%d" % rec["crit"]
        return "miss", "static", "未构造 vill=1"

    if cp == "F08":  # vta 两值
        if not legal:
            return "na", "-", "非合法执行"
        vals = {t[0] for t in rec["vta_vma"] if t[2] == "OK"}
        if vals == {0, 1}:
            return "hit", "runtime", "MATRIX vta=0/1 均有 OK 行"
        if vals:
            return "partial", "runtime", "只有 vta=%s" % sorted(vals)
        return "miss", "static", "vta 未显式扫描（ta 固定）"

    if cp == "F09":
        if not legal:
            return "na", "-", "非合法执行"
        vals = {t[1] for t in rec["vta_vma"] if t[2] == "OK"}
        if vals == {0, 1}:
            return "hit", "runtime", "MATRIX vma=0/1 均有 OK 行"
        if vals:
            return "partial", "runtime", "只有 vma=%s" % sorted(vals)
        return "miss", "static", "vma 未显式扫描（ma 固定）"

    if cp == "F10":
        if not legal:
            return "na", "-", "非合法执行"
        combos = {(t[0], t[1]) for t in rec["vta_vma"] if t[2] == "OK"}
        if combos == {(0, 0), (0, 1), (1, 0), (1, 1)}:
            return "hit", "runtime", "四组合 4/4 OK"
        if combos:
            return "partial", "runtime", "%d/4 组合" % len(combos)
        return "miss", "static", "无 vta×vma 扫描"

    if cp == "F11":  # vm=1 legal
        if not legal:
            return "na", "-", "非合法执行"
        if rec["encs"] and not rec["any_vm0"]:
            return "hit", "bin+legal", "全部编码 vm=1（%d 条）" % len(rec["encs"])
        if rec["any_vm0"]:
            return "miss", "bin", "编码含 vm=0"
        return "miss", "bin", "二进制无 vdot 编码"

    if cp == "F12":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["any_vm0"] and trap:
            return "hit", "bin+runtime", "编码 vm=0；HIT CRITICAL ERROR=%d" % rec["crit"]
        return "miss", "bin", "编码无 vm=0"

    if cp == "F13":
        if not legal:
            return "na", "-", "非合法执行"
        if rec["any_eq_vd_vs1"]:
            return "hit", "bin+legal", "编码 vd==vs1 存在"
        return "miss", "bin", "无 vd==vs1 编码"

    if cp == "F14":
        if not legal:
            return "na", "-", "非合法执行"
        if rec["any_eq_vd_vs2"]:
            if rec["extra"] == "--no-diff":
                return "partial", "bin+自检", "vd==vs2 仅 --no-diff 自检，无 difftest 比对"
            return "hit", "bin+legal", "编码 vd==vs2 且 difftest 执行"
        return "miss", "bin", "无 vd==vs2 编码"

    if cp == "F15":
        if not legal:
            return "na", "-", "非合法执行"
        if rec["any_eq_vs1_vs2"]:
            return "hit", "bin+legal", "编码 vs1==vs2 存在"
        return "miss", "bin", "无 vs1==vs2 编码（30 例全缺口）"

    if cp == "F16":
        if not legal:
            return "na", "-", "非合法执行"
        if rec["sew"] == 8:
            return "hit", "static+legal", "vsetvli e8 + 合法执行"
        return "miss", "static", "SEW=%s" % rec["sew"]

    if cp == "F17":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["sew"] not in (None, 8) and trap:
            return "hit", "static+runtime", "源码 e%d；HIT CRITICAL ERROR=%d" % (rec["sew"], rec["crit"])
        return "miss", "static", "未构造 SEW!=8"

    if cp == "F18":
        if not legal:
            return "na", "-", "非合法执行"
        if rec["lmul"] == 1:
            return "hit", "static+legal", "vsetvli m1"
        return "miss", "static", "LMUL=%s" % rec["lmul"]

    if cp == "F19":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["lmul"] in (2, 4, 8) and trap:
            return "hit", "static+runtime", "源码 m%d；HIT CRITICAL ERROR=%d" % (rec["lmul"], rec["crit"])
        return "miss", "static", "未构造 LMUL!=1"

    if cp == "F20":
        if cls != "negative":
            return "na", "-", "trap 域不适用"
        if rec["clears_vs"] and trap:
            return "hit", "static+runtime", "csrc mstatus 清 VS；HIT CRITICAL ERROR=%d" % rec["crit"]
        return "miss", "static", "未清 mstatus.VS"

    if cp == "F21":  # 边界值：int8 的 −128 / 127 / 0 / 累加溢出
        if not legal:
            return "na", "-", "非合法执行"
        if rec["operand_random"]:
            return "hit", "static+legal", "随机 16 字节操作数（统计上覆盖边界组合）+ RAND_SUMMARY"
        ops = rec["operands"]
        if not ops:
            return "miss", "static", "无内联操作数数组"
        bins = []
        if -128 in ops:
            bins.append("-128")
        if 127 in ops:
            bins.append("127")
        if 0 in ops:
            bins.append("0")
        exp = rec.get("expect_s")
        if exp is not None and abs(exp) > 32767:
            bins.append("overflow(|S|>32767)")
        if bins:
            return "hit", "static+legal", "操作数/期望含边界 bin：%s（expect=%s）" % (",".join(bins), exp)
        return "miss", "static", "操作数无 −128/127/0 且 |S|≤32767"

    if cp == "F22":
        if rec["rand"] and rec["rand"][1] == 0:
            return "hit", "runtime", "RAND_SUMMARY groups=%d mism=0" % rec["rand"][0]
        return ("na" if not legal else "miss"), "runtime", "无 RAND_SUMMARY"

    if cp == "F23":  # 高 96 位
        if not legal:
            return "na", "-", "非合法执行"
        t = ""
        if rec["log"] and os.path.isfile(rec["log"]):
            t = read_text(rec["log"])
        runtime_hi = bool(re.search(r"hi_nonzero=000", t)) or bool(re.search(r"hi=\[0x00000000 0x00000000 0x00000000\]", t))
        if rec["hi96_assert"] and (runtime_hi or rec["rand"] or rec["mix_ok"]):
            if runtime_hi:
                return "hit", "runtime", "运行行断言高 96 位为 0（hi_nonzero=000 / hi=[0x0 0x0 0x0]）"
            return "hit", "static+legal", "用例断言 vd[127:32]==0 且判据串在场"
        return ("partial" if rec["hi96_assert"] else "miss"), "static", "无用例侧高 96 位断言"

    if cp == "F24":
        if legal and re.search(r"MATRIX oldvd_prefill .* OK", read_text(rec["log"]) if rec["log"] and os.path.isfile(rec["log"]) else ""):
            return "hit", "runtime", "MATRIX oldvd_prefill … OK"
        return ("na" if not legal else "miss"), "runtime", "无 oldvd_prefill 行"

    if cp == "F25":
        if rec["vxsat"] and rec["vxsat"][2] == "OK":
            return "hit", "runtime", "MATRIX vxsat before=%s after=%s OK" % (rec["vxsat"][0], rec["vxsat"][1])
        return ("na" if not legal else "miss"), "runtime", "无 vxsat 前后对照行"

    if cp == "F26":
        if not legal:
            return "na", "-", "非合法执行"
        t = read_text(rec["log"]) if rec["log"] and os.path.isfile(rec["log"]) else ""
        if re.search(r"MATRIX back_to_back .* OK", t) or rec["mix_ok"] or re.search(r"chain=OK", t):
            return "hit", "runtime", "back_to_back / MIX / chain 自检串"
        return "miss", "runtime", "无背靠背/RAW 自检串"

    if cp == "F27":
        if rec["rand"] and rec["rand"][2] == 0:
            return "hit", "runtime", "16 字节随机 + ab_bad=0"
        return ("na" if not legal else "miss"), "runtime", "未干扰高 64 位"

    if cp == "F28":  # 寄存器索引空间：bin 级 coverpoint，单例只能贡献部分 bin
        if not rec["encs"]:
            return "na", "-", "无 vdot 编码"
        return "partial", "bin", "vd=%s vs1=%s vs2=%s" % (
            rec["vd_set"], rec["vs1_set"], rec["vs2_set"])

    if cp == "F29":
        if not legal:
            if rec["mismatch"] and g0:
                return "miss", "runtime", "g0 反例（期望值故意错），不作正例覆盖"
            return "na", "-", "非合法执行"
        if rec["operand_random"]:
            return "hit", "static+legal", "随机操作数（正/负/零混合，1024 组）"
        ops = rec["operands"]
        if not ops:
            return "miss", "static", "无内联操作数数组"
        has_pos = any(x > 0 for x in ops)
        has_neg = any(x < 0 for x in ops)
        has_zero = any(x == 0 for x in ops)
        cls_sign = "mixed" if (has_pos and has_neg) else ("pos" if has_pos else ("neg" if has_neg else "zero"))
        if has_pos and has_neg:
            return "hit", "static+legal", "操作数正负混合（含 0=%s）" % ("是" if has_zero else "否")
        if has_pos or has_neg:
            return "partial", "static+legal", "仅%s操作数一类" % ("正" if has_pos else "负")
        return "miss", "static", "全 0 操作数"

    return "na", "-", "未定义"


def coverage_status(recs, cp):
    """由逐例状态派生覆盖状态。"""
    # F28 是 bin 级（32 个寄存器索引 × 3 个操作数位），单例只贡献部分 bin：
    # 状态由「全表并集」派生，避免把「某例用到了 vd=v3」误当成整条 coverpoint 覆盖。
    if cp == "F28":
        vd, vs1, vs2 = set(), set(), set()
        for r in recs:
            vd |= set(r["vd_set"]); vs1 |= set(r["vs1_set"]); vs2 |= set(r["vs2_set"])
        full = (len(vd) == 32 and len(vs1) == 32 and len(vs2) == 32)
        contributors = [r["cid"] for r in recs if r["encs"]]
        st = "covered" if full else ("partial" if contributors else "gap")
        return st, contributors, []
    hits = [r["cid"] for r in recs if cell(r, cp)[0] == "hit"]
    parts = [r["cid"] for r in recs if cell(r, cp)[0] == "partial"]
    if len(hits) >= 2:
        return "covered", hits, parts
    if len(hits) == 1:
        return "thin", hits, parts
    if parts:
        return "partial", hits, parts
    return "gap", hits, parts


def write_regspace(recs, out_dir):
    """F28 的 bin 级明细：每个操作数位的寄存器索引 → 命中例。"""
    path = os.path.join(out_dir, "regspace.tsv")
    acc = {"vd": {}, "vs1": {}, "vs2": {}}
    keys = {"vd": "vd_set", "vs1": "vs1_set", "vs2": "vs2_set"}
    for r in recs:
        for key, field in keys.items():
            for reg in r[field]:
                acc[key].setdefault(reg, []).append(r["cid"])
    with open(path, "w") as f:
        f.write("# operand\treg\thit\tcases\n")
        for key in ("vd", "vs1", "vs2"):
            for reg in range(32):
                cases = acc[key].get(reg, [])
                f.write("%s\tv%d\t%d\t%s\n" % (key, reg, 1 if cases else 0, ",".join(cases) if cases else "-"))
    return path


def write_hits(recs, out_dir):
    path = os.path.join(out_dir, "hits.tsv")
    with open(path, "w") as f:
        f.write("# cid\tcls\tcp_id\tcp_name\tstatus\tbasis\tevidence\n")
        for r in recs:
            for cp in CP_IDS:
                st, basis, ev = cell(r, cp)
                f.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                    r["cid"], r["cls"], cp, CP_BY_ID[cp][1], st, basis, ev.replace("\t", " ")))
    return path


def write_summary(recs, out_dir):
    path = os.path.join(out_dir, "summary.tsv")
    rows = []
    with open(path, "w") as f:
        f.write("# cp_id\tcp_name\tact4_ref\tsampling\tstatus\thit_cases\tpartial_cases\thit_count\tnote\n")
        for cp in CP_IDS:
            st, hits, parts = coverage_status(recs, cp)
            rows.append("%s\t%s\t%s" % (cp, st, len(hits)))
            f.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\n" % (
                cp, CP_BY_ID[cp][1], CP_BY_ID[cp][2], CP_BY_ID[cp][3], st,
                ",".join(hits) if hits else "-",
                ",".join(parts) if parts else "-",
                len(hits), CP_BY_ID[cp][4]))
    return path, rows


STRUCT_MODULES = ["VdotReduce", "VIMac64b", "VIMacU", "VIMacSrcTypeModule", "VecExceptionGen", "DecodeUnit"]
TREE_RE = re.compile(r"^(\s*)- (\S+)\s*$")
ATTR_RE = re.compile(r"^\s*(tree_line|self_line|tree_toggle|self_toggle)\((\d+),\s*(\d+),\s*([\d.]+)\)\s*$")


def write_structural(statistics, out_dir):
    """解析 statistics.py 的 AllCoverage 树 → vdot-structural.tsv。"""
    with open(statistics) as f:
        lines = f.read().splitlines()
    started = False
    stack = []  # [(indent, name)]
    found = {}
    for ln in lines:
        if ln.strip() == "AllCoverage:":
            started = True
            continue
        if not started:
            continue
        m = TREE_RE.match(ln)
        if m:
            indent = len(m.group(1))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack.append((indent, m.group(2)))
            continue
        a = ATTR_RE.match(ln)
        if a and stack:
            name = stack[-1][1]
            if name in STRUCT_MODULES:
                d = found.setdefault(name, {})
                d[a.group(1)] = (int(a.group(2)), int(a.group(3)), float(a.group(4)))
    path = os.path.join(out_dir, "vdot-structural.tsv")
    with open(path, "w") as f:
        # 元组语义（difftest/scripts/coverage/statistics.py:309-315 print_tree_coverage）：
        #   tree_line(covered, NOT_covered, pct) —— 第二项是未覆盖数，不是总数。
        # 2026-11-07 更正：旧版把第二项写成 line_total（真实数据会把 not_covered 当总数、总数算错）。
        f.write("# module\tline_covered\tline_not_covered\tline_total\tline_pct"
                "\ttoggle_covered\ttoggle_not_covered\ttoggle_total\ttoggle_pct\tstatus\n")
        for mod in STRUCT_MODULES:
            d = found.get(mod)
            if not d or "tree_line" not in d:
                f.write("%s\t-\t-\t-\t-\t-\t-\t-\t-\t未运行\n" % mod)
                continue
            lc, lnc, lp = d["tree_line"]
            tc, tnc, tp = d.get("tree_toggle", (0, 0, 0.0))
            f.write("%s\t%d\t%d\t%d\t%.2f\t%d\t%d\t%d\t%.2f\t实测\n"
                    % (mod, lc, lnc, lc + lnc, lp, tc, tnc, tc + tnc, tp))
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="design/verify/cases/manifest.tsv")
    ap.add_argument("--logs", default="stage3/3.1.2-difftest/full-logs-20261103T142246")
    ap.add_argument("--log-suffix", default=".20261103T142246.log")
    ap.add_argument("--bins", default="design/verify/cases")
    ap.add_argument("--out", required=True)
    ap.add_argument("--statistics", default="")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    recs = []
    with open(args.manifest) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            cid, cls = parts[0], parts[1]
            img = parts[2].replace("@IMG_DIR@", args.bins)
            extra = parts[3] if len(parts) > 3 else ""
            log = os.path.join(args.logs, cid + args.log_suffix)
            recs.append(parse_case(cid, cls, extra, log, img))

    hits = write_hits(recs, args.out)
    summ, rows = write_summary(recs, args.out)
    reg = write_regspace(recs, args.out)
    print("cases=%d cps=%d cells=%d" % (len(recs), len(CP_IDS), len(recs) * len(CP_IDS)))
    print("hits ->%s" % hits)
    print("summary ->%s" % summ)
    print("regspace ->%s" % reg)
    counts = {"covered": 0, "thin": 0, "partial": 0, "gap": 0}
    for row in rows:
        cp, st, n = row.split("\t")
        counts[st] = counts.get(st, 0) + 1
    print("coverage: covered=%d thin=%d partial=%d gap=%d" % (
        counts["covered"], counts["thin"], counts["partial"], counts["gap"]))
    # 寄存器索引空间汇总（F28 的整表结论）
    vd, vs1, vs2 = set(), set(), set()
    for r in recs:
        vd |= set(r["vd_set"]); vs1 |= set(r["vs1_set"]); vs2 |= set(r["vs2_set"])
    print("reg_space: vd=%d/32 %s" % (len(vd), sorted(vd)))
    print("reg_space: vs1=%d/32 %s" % (len(vs1), sorted(vs1)))
    print("reg_space: vs2=%d/32 %s" % (len(vs2), sorted(vs2)))
    if args.statistics:
        p = write_structural(args.statistics, args.out)
        print("structural ->%s" % p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
