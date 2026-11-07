#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""parse_stats.py —— 把 difftest/scripts/coverage/statistics.py 的**五段报告**解析成长表。

为什么单独写：gen_hits.py 只取 AllCoverage 树的 tree_line/tree_toggle（功能矩阵用）；
本节要回填「五段报告数字」（LineSelfCoverage / LineTreeCoverage / ToggleSelfCoverage /
ToggleTreeCoverage / AllCoverage），需要同一次解析给出四段的模块级元组与树内 self/tree 对照。

输入：coverage_SimTop.log（`make -C difftest coverage` 的 statistics.py 输出）
输出：<out>/stats-5sections.tsv（长表）
      section  module  metric(line|toggle)  scope(self|tree)  covered  not_covered  total  pct

口径（difftest/scripts/coverage/statistics.py:309-315）：
  四段列表的元组是 (covered, NOT_covered, ratio)，第二项**不是**总数；total = covered + not_covered。
  AllCoverage 的 tree_line/self_line/tree_toggle/self_toggle 同为 (covered, not_covered, pct)。
  行覆盖只数 `if` / `end else` 行；翻转覆盖只数 reg/wire/input/output 声明行 —— 不是语句覆盖。

用法：
  python3 -I parse_stats.py --log results/coverage/<runid>/merged.coverage/coverage_SimTop.log \
      --out results/coverage/<runid> [--modules VdotReduce,VIMac64b,...]
"""
import argparse
import os
import re

FLAT = [
    ("LineSelfCoverage", "line", "self"),
    ("LineTreeCoverage", "line", "tree"),
    ("ToggleSelfCoverage", "toggle", "self"),
    ("ToggleTreeCoverage", "toggle", "tree"),
]
TUPLE_RE = re.compile(r"\('([A-Za-z0-9_$]+)',\s*\((\d+),\s*(\d+),\s*([\d.eE+-]+)\)\)")
TREE_RE = re.compile(r"^(\s*)- (\S+)\s*$")
ATTR_RE = re.compile(r"^\s*(tree_line|self_line|tree_toggle|self_toggle)\((\d+),\s*(\d+),\s*([\d.]+)\)\s*$")


def read_sections(path):
    sections = {}
    cur = None
    with open(path, errors="replace") as f:
        for ln in f:
            key = ln.split(":", 1)[0].strip()
            if ln.rstrip().endswith(":") and key in {n for n, _, _ in FLAT} | {"AllCoverage"}:
                cur = key
                sections.setdefault(cur, [])
                continue
            if cur:
                sections[cur].append(ln.rstrip("\n"))
    return sections


def parse_flat(lines):
    out = []
    for ln in lines:
        for m in TUPLE_RE.finditer(ln):
            c, n, p = int(m.group(2)), int(m.group(3)), float(m.group(4))
            out.append((m.group(1), c, n, c + n, p * 100.0))
    return out


def parse_tree(lines):
    out = []  # (module, attr, covered, not_covered, total, pct)
    stack = []
    for ln in lines:
        m = TREE_RE.match(ln)
        if m:
            indent = len(m.group(1))
            while stack and stack[-1][0] >= indent:
                stack.pop()
            stack.append((indent, m.group(2)))
            continue
        a = ATTR_RE.match(ln)
        if a and stack:
            c, n = int(a.group(2)), int(a.group(3))
            out.append((stack[-1][1], a.group(1), c, n, c + n, float(a.group(4))))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--modules", default="")
    args = ap.parse_args()

    sections = read_sections(args.log)
    rows = []  # section, module, metric, scope, covered, not_covered, total, pct
    for name, metric, scope in FLAT:
        if name not in sections:
            continue
        for mod, c, n, t, p in parse_flat(sections[name]):
            rows.append((name, mod, metric, scope, c, n, t, p))
    if "AllCoverage" in sections:
        for mod, attr, c, n, t, p in parse_tree(sections["AllCoverage"]):
            metric = "line" if attr.endswith("_line") else "toggle"
            scope = "tree" if attr.startswith("tree_") else "self"
            rows.append(("AllCoverage", mod, metric, scope, c, n, t, p))

    want = [m for m in args.modules.split(",") if m]
    if want:
        rows = [r for r in rows if r[1] in want]

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, "stats-5sections.tsv")
    with open(path, "w") as f:
        f.write("# section\tmodule\tmetric\tscope\tcovered\tnot_covered\ttotal\tpct\n")
        for r in rows:
            f.write("%s\t%s\t%s\t%s\t%d\t%d\t%d\t%.2f\n" % r)
    print("sections_found=%s rows=%d -> %s"
          % (",".join(sorted(sections.keys())) or "none", len(rows), path))


if __name__ == "__main__":
    main()