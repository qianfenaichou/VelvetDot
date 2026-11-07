#!/usr/bin/env python3
# check_assertions.py — 把 1.3 文档里的「(拍, 信号, 值)」断言表**逐条**核对到 raw/vadd_stages.tsv。
#
# 目的（stage1/1.3-vadd/README.md §3.2 是断言的**唯一来源**）：
#   §3.2 的表是「拍 → 关键信号 → 该拍取值」的人工断言。本脚本把每一行都拿到
#   raw/vadd_stages.tsv（由 VCD 抽取的七级逐拍表）里去比对，输出 checked=N fail=M 与逐条结果，
#   使「README 里写的取值」不再只是文字，而是**可复算的判据**。
#
# 只读：本脚本只打开 raw/ 下的文件读取，**不写任何文件**（raw/ 是原始证据，不得被工具改动）。
#
# 用法：
#   python3 stage1/1.3-vadd/scripts/check_assertions.py [-v] [--strict]
#   python3 stage1/1.3-vadd/scripts/check_assertions.py --claims my_claims.tsv
#
# 参数：
#   --claims FILE  断言文件。默认 = ../README.md 的 §3.2 表。
#                  支持两种格式：(a) Markdown 表（同 README §3.2 的列：级|拍|关键信号|该拍取值|含义）；
#                  (b) 简洁格式，每行「拍<分隔符>信号<分隔符>值」，分隔符支持 TAB/逗号/空白（# 开头为注释）。
#   --tsv FILE     逐拍表，默认 ../raw/vadd_stages.tsv
#   --index FILE   信号索引（VCD 全路径 → stage/label → TSV 列名），默认 ../raw/vadd_stages.index.txt
#   --readme FILE  README 路径（默认 ../README.md），仅用于默认 claims 的定位与 §3.2 的定位
#   -v/--verbose   逐条结果默认就打；加 -v 时额外打印解析出的列名与归一化过程
#   --strict       把「无法解析（TSV 无对应列）」也算失败（默认只统计、不判失败）
#
# 退出码：0 = 无失败断言；1 = 有失败断言（fail>0）；2 = 用法/文件错误。
#
# 解析与判定规则（全部写死在这里，便于核对）：
#   R1 断言行：Markdown 表的「级|拍|关键信号|该拍取值|含义」；「级」为空则继承上一行。
#   R2 一个单元格里可能有多个信号（用 / 分隔），值同样多个；两者按出现顺序一一配对。
#      形如 `_1` / `_vlmul` / `_ready` 的续写 = 把上一信号**最后一个下划线段**换掉：
#        decode/io_out_0_bits_lsrc_0 + _1  ->  decode/io_out_0_bits_lsrc_1
#        decode/io_out_0_bits_vpu_vsew + _vm -> decode/io_out_0_bits_vpu_vlmul 类的同名替换
#   R3 形如 `.../xxx` 的省略写法 = 只用尾部路径去索引里找（目录部分由索引提供）。
#   R4 索引里同一条 VCD 路径可能出现多次（如 io_out_bits_ctrl_pdest 同时是 EX/out_pdest 与 WB/pdest），
#      此时用断言行的「级」映射到的级（IF/ID/RN/DP/IS/EX/WB）来唯一化。
#   R5 仍不能唯一化时（例如 README 写的 `decode/io_out_0_bits_lsrc_2` 在 RVV 里并不存在，
#      真实语义是 vd=ldest），**不再回退到「同拍同级取值唯一匹配」并据此判 PASS**：
#      那样会把「被点名的信号」换成**另一个**信号来核对（被点名的信号根本没被核对），
#      却计入 checked ⇒ 写错的期望值也可能判绿（2026-11-04 实测：
#      `lsrc_2` 期望 0x99 时旧版记 SKIP 且 RC=0）。改为：**命名信号解析不出来 = 该断言未被核对**，
#      默认判 FAIL；只有下面 `KNOWN_UNRESOLVED` 白名单里**显式登记**的
#      「该信号确实未被 TSV 抽取」的行才记 SKIP。
#   R6 取值比较按**整数**做（十六进制、去下划线、去前导零后比数值），避免 0x03 与 03 这类书写差异误判。
#   R7 索引里根本没有该信号（如 `.../mgu/io_out_active`，TSV 未抽这一列）→ 若在
#      `KNOWN_UNRESOLVED` 白名单内则记 SKIP（不计 fail）；否则记 FAIL（**fail-closed**：
#      断言表与证据不一致时不能静默判绿）。
from __future__ import annotations

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)  # stage1/1.3-vadd

DEFAULT_README = os.path.join(BASE, "README.md")
DEFAULT_TSV = os.path.join(BASE, "raw", "vadd_stages.tsv")
DEFAULT_INDEX = os.path.join(BASE, "raw", "vadd_stages.index.txt")

# ---------------------------------------------------------------- 「无法核对」白名单（显式登记）
#
# 背景：README §3.2 断言表里有 4 条断言指向的信号**本工具没有抽进 TSV**
# （raw/vadd_stages.tsv 里没有这一列）⇒ **在原理上无法核对取值**。它们是**已知且已登记**的
# 缺口（不是断言写错），故记 SKIP（不计 fail）。
#
# 注意：白名单是**显式登记**的，且**同时登记期望值**：
#   ① 任何**不在**此表里的「命名信号解析不出来」一律判 FAIL（fail-closed）
#      ⇒ README 把信号名写错这类真错误不会被静默放过
#      （2026-11-04 核对：`decode/io_out_0_bits_lsrc_2` 曾按取值回退到 ID_vd_ldest 而误计 PASS）；
#   ② 登记项若被写成**别的期望值**也判 FAIL ⇒ 白名单不是「任意值都放过」的万能豁免，
#      同一核对中的反例（`lsrc_2` 期望 0x99）由此判失败。
#
# 键 = (展开后的信号尾部路径, 拍)，与 resolve() 用的 tail 字符串一致（经 R2/R3 展开后）。
# 值 = (登记的期望值, 原因)。
KNOWN_UNRESOLVED = {
    # README §3.2「ID 译码」行第三格 `_2`：R2 展开后是 `decode/io_out_0_bits_lsrc_2`。
    # 该信号在 RTL 里**存在**（DecodeUnit.scala:861 `decodedInst.lsrc(2) := Mux(isFMA, inst.FS3, inst.VD)`
    # ⇒ 对向量指令它就是 vd 字段，README 该格写的「vd=v3」与 RTL 一致），
    # 但抽取器 cases/vadd_stage_extract.py:201-202 的 ID 规格只请求了 lsrc_0/lsrc_1，
    # ⇒ 这一列不在 TSV 里，**无法核对取值**（旧版脚本曾把它按取值回退到 ID_vd_ldest 而误判 PASS）。
    ("decode/io_out_0_bits_lsrc_2", 8417): (
        "0x03",
        "TSV 未抽该列：抽取器 ID 规格只请求 lsrc_0/lsrc_1（cases/vadd_stage_extract.py:201-202）；"
        "该信号在 RTL 里是 vd 字段（DecodeUnit.scala:861）",
    ),
    # README §3.2「DP 派发」行：这一拍分发到第 0 号 Exu 通道的**别的**指令的 fuType/fuOpType
    # （README 明写「不是本指令的 fuType」）。抽取器 vadd_stage_extract.py 的 DP 规格里请求的是
    # `dispatch/io_renameIn_0_bits_{fuType,fuOpType}`，但 raw/vadd_stages.index.txt 里
    # DP/fuType 与 DP/fuOpType 实际来自 `dispatch/io_fromRename_0_bits_*`
    # ⇒ 被点名的 `io_renameIn_0_bits_*` 两列在本 TSV 中不存在，无法核对。
    ("dispatch/io_renameIn_0_bits_fuType", 8419): (
        "0x000000001",
        "TSV 未抽该列：本拍 DP 级 fuType 实际取自 dispatch/io_fromRename_0_bits_fuType"
        "（README §3.2 该行明示是「另一视图」，非本指令的 fuType）",
    ),
    ("dispatch/io_renameIn_0_bits_fuOpType", 8419): (
        "0x002",
        "TSV 未抽该列：同上，DP/fuOpType 实际取自 dispatch/io_fromRename_0_bits_fuOpType",
    ),
    # README §3.2「WB 写回」行的字节掩码信号：抽取器规格里没有 mgu 这一路
    # （cases/vadd_stage_extract.py 的七级信号规格不含 mgu/io_out_active）⇒ 该列不存在。
    ("mgu/io_out_active", 8499): (
        "0xFFFF",
        "TSV 未抽该列：抽取器七级信号规格不含 mgu/io_out_active（字节掩码）这一路",
    ),
}


# 「级」列的中文/英文关键字 → 索引里的级前缀
STAGE_KEYWORDS = [
    ("IF", ("IF 取指", "IF取指", "取指", "IF")),
    ("ID", ("ID 译码", "ID译码", "译码", "ID")),
    ("RN", ("RN 重命名", "RN重命名", "重命名", "RN")),
    ("DP", ("DP 派发", "DP派发", "派发", "DP")),
    ("IS", ("IS 发射", "IS发射", "发射", "IS")),
    ("EX", ("EX 执行", "EX执行", "执行", "EX")),
    ("WB", ("WB 写回", "WB写回", "写回", "WB")),
]

CODE_SPAN = re.compile(r"`([^`]+)`")


# ----------------------------------------------------------------- 基础工具
def norm_int(text: str, base: str = "hex"):
    """把 '0x03' / '03' / '0xFFFF_00FF' 统一成整数；不是数字就返回 None。

    base='hex'（默认）：README §3.2 的取值与 TSV 的取值**都是十六进制**
    （TSV 由 VCD 抽取器写成零填充十六进制串，如 '021101D7' / '0000080000160'），
    故一律按十六进制解析；README 里不带 0x 前缀的裸值只有 '0' / '1' 这类单位数字，
    十六进制与十进制同值，不存在歧义。
    """
    if text is None:
        return None
    t = text.strip().replace("_", "").replace("`", "")
    if not t:
        return None
    neg = t.startswith("-")
    if neg:
        t = t[1:]
    try:
        if base == "hex":
            v = int(t, 16)
        else:
            v = int(t, 10)
    except ValueError:
        return None
    return -v if neg else v


def stage_of(level: str):
    """把「级」列的文字映射到索引里的级前缀（IF/ID/RN/DP/IS/EX/WB）。"""
    if not level:
        return None
    for st, keys in STAGE_KEYWORDS:
        for k in keys:
            if k in level:
                return st
    return None


def expand_signal(spec: str, prev: str | None) -> str:
    """R2/R3：把一个信号写法展开成可检索的路径串。"""
    s = spec.strip()
    if s.startswith("..."):
        # R3：省略目录，只留尾部
        s = s[3:].lstrip("/")
        return s
    if s.startswith("_") and prev:
        # R2：续写 —— 换掉上一信号最后一个下划线段
        head, sep, tail = prev.rpartition("_")
        if sep:
            return f"{head}{s}"
        return f"{prev}{s}"
    return s


# ----------------------------------------------------------------- 断言表解析
def parse_markdown_table(text: str):
    """解析 Markdown 表 → [(level, cycle, signal, value)]（R1/R2）。"""
    rows = []
    last_level = ""
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        if cells[0] in ("级", "Level") or cells[0].startswith("-"):
            continue  # 表头 / 分隔行
        level = cells[0].strip() or last_level
        if cells[0].strip():
            last_level = cells[0].strip()
        cycle_txt = cells[1].strip()
        if not re.fullmatch(r"\d+", cycle_txt):
            continue
        sig_spans = CODE_SPAN.findall(cells[2])
        val_spans = CODE_SPAN.findall(cells[3])
        if not sig_spans:
            continue
        if not val_spans:
            continue
        if len(val_spans) < len(sig_spans):
            # 值少于信号：只配对前 N 个（其余标为无值，不判）
            sig_spans = sig_spans[: len(val_spans)]
        prev = None
        for sig, val in zip(sig_spans, val_spans):
            rows.append((level, int(cycle_txt), expand_signal(sig, prev), sig.strip(), val.strip()))
            prev = expand_signal(sig, prev)
    return rows


def parse_simple_claims(text: str):
    """解析简洁断言文件：每行「拍 信号 值」（TAB/逗号/空白分隔，# 注释）。"""
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p for p in re.split(r"[\t,]+|\s{2,}", line) if p.strip()]
        if len(parts) < 3:
            parts = line.split()
        if len(parts) < 3:
            continue
        cycle_txt, sig, val = parts[0], parts[1], parts[2]
        if not re.fullmatch(r"\d+", cycle_txt.strip()):
            continue
        rows.append(("", int(cycle_txt.strip()), sig.strip(), sig.strip(), val.strip()))
    return rows


def load_claims(path: str, is_readme: bool) -> list:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if is_readme or any(l.strip().startswith("|") for l in text.splitlines()[:200]):
        # README：只取 §3.2 那一节（表格在 §3.2 标题与下一个标题之间）
        m = re.search(r"^###\s*3\.2.*?$", text, re.M)
        if m:
            rest = text[m.end():]
            nxt = re.search(r"^#{2,3}\s", rest, re.M)
            if nxt:
                text = text[m.end(): m.end() + nxt.start()]
        return parse_markdown_table(text)
    return parse_simple_claims(text)


# ----------------------------------------------------------------- 索引与 TSV
def load_index(path: str):
    """索引：full_path | width | stage/label  →  列名 = label 的 '/' 换成 '_'。"""
    entries = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#") or "|" not in line:
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) < 3:
                continue
            full, _width, label = parts[0], parts[1], parts[2]
            stage, _, lab = label.partition("/")
            entries.append({"full": full, "stage": stage, "label": label,
                            "col": label.replace("/", "_"), "path": full})
    return entries


def load_tsv(path: str):
    """逐拍表：列名 → {拍: 值字符串}。"""
    with open(path, "r", encoding="utf-8") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    if not lines:
        raise SystemExit(f"[FATAL] TSV 为空：{path}")
    header = lines[0].split("\t")
    cols = {}
    for line in lines[1:]:
        cells = line.split("\t")
        if not cells:
            continue
        t = cells[0].strip()
        if not t.isdigit():
            continue
        row = {}
        for i, c in enumerate(header):
            if i < len(cells):
                row[c] = cells[i].strip()
        cols[int(t)] = row
    return header, cols


# ----------------------------------------------------------------- 解析断言 → 列
def resolve(level, cycle, tail, entries, rows_by_time):
    """把断言的信号写法解析成 TSV 列名；返回 (列名, 解析方式, 候选说明)。"""
    stage = stage_of(level)
    cands = [e for e in entries if e["full"].endswith("/" + tail) or e["full"] == tail]
    if not cands:
        cands = [e for e in entries if e["full"].endswith(tail)]
    if cands:
        if stage:
            same = [e for e in cands if e["stage"] == stage]
            if len(same) == 1:
                return same[0]["col"], "path", f"{same[0]['label']} ({stage})"
            if len(same) > 1:
                return None, "ambiguous", "同路径同级多条：" + ",".join(e["label"] for e in same)
            if len(cands) == 1:
                return cands[0]["col"], "path-stage-fallback", f"{cands[0]['label']} (级不符，README 标 {stage})"
        elif len(cands) == 1:
            return cands[0]["col"], "path", cands[0]["label"]
        else:
            return None, "ambiguous", "同路径多条：" + ",".join(e["label"] for e in cands)
    # R5：命名信号在索引里找不到 ⇒ 该断言**未被核对**（不再按取值回退到别的信号）。
    # 这里只补充「同级有多少候选」供人工排查用；判定交给调用方（白名单 → SKIP，否则 FAIL）。
    pool = [e for e in entries if stage is None or e["stage"] == stage]
    row = rows_by_time.get(cycle, {})
    hits = []
    for e in pool:
        v = row.get(e["col"])
        if v is None:
            continue
        hits.append((e, v))
    return None, "not-found", f"索引里没有尾部路径 '{tail}'（同拍同级候选 {len(hits)} 条）"


# ----------------------------------------------------------------- 主流程
def main() -> int:
    ap = argparse.ArgumentParser(description="核对 1.3 的 (拍,信号,值) 断言表与 raw/vadd_stages.tsv")
    ap.add_argument("--claims", default=None, help="断言文件（默认 README §3.2）")
    ap.add_argument("--readme", default=DEFAULT_README, help="README 路径")
    ap.add_argument("--tsv", default=DEFAULT_TSV, help="逐拍表 TSV")
    ap.add_argument("--index", default=DEFAULT_INDEX, help="信号索引")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--strict", action="store_true", help="把无法解析（SKIP）也算失败")
    args = ap.parse_args()

    claims_path = args.claims or args.readme
    is_readme = args.claims is None
    for p in (claims_path, args.tsv, args.index):
        if not os.path.isfile(p):
            print(f"[FATAL] 文件不存在：{p}", file=sys.stderr)
            return 2

    claims = load_claims(claims_path, is_readme)
    if not claims:
        print(f"[FATAL] 没解析出任何断言：{claims_path}", file=sys.stderr)
        return 2
    entries = load_index(args.index)
    _header, rows_by_time = load_tsv(args.tsv)

    print(f"# claims={claims_path}  tsv={args.tsv}  index={args.index}")
    print(f"# 断言条数={len(claims)}  索引信号数={len(entries)}  TSV 拍数={len(rows_by_time)}")

    checked = fail = skip = 0
    skip_reasons = []
    for idx, (level, cycle, tail, raw_sig, raw_val) in enumerate(claims, 1):
        expected = norm_int(raw_val)
        col, how, note = resolve(level, cycle, tail, entries, rows_by_time)
        if col is None:
            # 命名信号解析不出来 ⇒ 该断言**未被核对**（R5/R7：不再按取值回退到别的信号）。
            # fail-closed：只有白名单里**显式登记**（且期望值与登记值一致）的
            # 「该列未被 TSV 抽取」才记 SKIP；其余（README 写错信号名 / 期望值与登记值不符）一律 FAIL。
            wl = KNOWN_UNRESOLVED.get((tail, cycle))
            if wl is not None:
                wl_val, wl_reason = wl
                if expected is not None and wl_val is not None and expected == norm_int(wl_val):
                    skip += 1
                    skip_reasons.append(f"{raw_sig}@{cycle}: {wl_reason}")
                    print(f"[SKIP] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 取值={raw_val}  原因={wl_reason}")
                else:
                    fail += 1
                    print(f"[FAIL] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 取值={raw_val}  原因="
                          f"该信号未抽进 TSV（{wl_reason}），但期望值与登记值 {wl_val} 不一致 ⇒ 判失败")
            else:
                fail += 1
                print(f"[FAIL] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 取值={raw_val}  原因="
                      f"命名信号在索引里解析不出来（{note}）⇒ 该断言未被核对，判失败"
                      f"（若该信号确实未被 TSV 抽取，请登记进 KNOWN_UNRESOLVED 白名单）")
            continue
        row = rows_by_time.get(cycle)
        if row is None:
            skip += 1
            skip_reasons.append(f"{raw_sig}@{cycle}: TSV 没有这一拍")
            print(f"[SKIP] {idx:3d} 拍={cycle} 列={col}  原因=TSV 没有这一拍")
            continue
        got_txt = row.get(col, "")
        got = norm_int(got_txt)
        if expected is None:
            fail += 1
            print(f"[FAIL] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 列={col} "
                  f"原因=期望值不是数字（{raw_val}）⇒ 断言无法核对，判失败")
            continue
        if got is None:
            fail += 1
            print(f"[FAIL] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 列={col} "
                  f"期望={raw_val} 实得={got_txt}（实得不是数字）")
            continue
        checked += 1
        if got == expected:
            print(f"[PASS] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 列={col} "
                  f"期望={raw_val} 实得={got_txt} 解析={how}")
        else:
            fail += 1
            print(f"[FAIL] {idx:3d} 拍={cycle} 级={level or '-'} 信号={raw_sig} 列={col} "
                  f"期望={raw_val} 实得={got_txt} 解析={how}")

    print(f"checked={checked} fail={fail} skip={skip} claims={len(claims)}")
    if skip_reasons:
        print("# skip 明细：" + " | ".join(skip_reasons))
    if fail > 0:
        return 1
    if args.strict and skip > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
