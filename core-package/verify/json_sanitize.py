#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""把含裸控制字符的 JSON 结果文件清洗成合法 JSON（原件只读，清洗件另存）。

背景（2026-11-03 实测）：`core-package/scripts/10-build-emu.sh` 早期版本的 `json_escape`
只转义反斜杠/引号，把 AM `printf` 的 CRLF 里的裸 `\r` 原样写进 JSON 字符串，于是
`python3 -c "import json; json.load(open(f))"` 报
`Invalid control character at: line 24 column 175 (char 1611)`，整份结果 JSON 不可解析。
生成端已在 `core-package/scripts/10-build-emu.sh` 修好（先删裸控制字符再转义），
本脚本用于清洗**历史**产物：原件一个字节都不改，清洗件另存为新文件。

清洗手法是「外科式」的：逐字符扫原文，只把**字符串字面量内部**的裸控制字符换成 JSON 转义
（`\b` `\f` `\n` `\r` `\t`，其余用 `\u00XX`），其余字节原样保留 ⇒ 清洗件与原件的差异只有
被转义的那几个字符，排版/键序/数值完全不变（不做整份 re-dump，避免无谓的 diff 噪声）。

用法：
  python3 json_sanitize.py SRC.json -o OUT.json   # 写清洗件到指定路径
  python3 json_sanitize.py SRC.json                # 另存为同目录 <stem>.clean.json
  python3 json_sanitize.py SRC.json --check        # 只校验：合法则 0，非法则 1（不落盘）
退出码：0 成功（清洗件已写 / 原本就合法） / 1 清洗后仍不可解析 / 2 用法错误或读不到文件
"""

import argparse
import json
import os
import sys

CTRL_ESCAPES = {
    0x08: "\\b",
    0x09: "\\t",
    0x0A: "\\n",
    0x0C: "\\f",
    0x0D: "\\r",
}


def escape_controls_in_strings(text):
    """把字符串字面量内部的裸控制字符换成 JSON 转义；返回 (新文本, 替换处数)。"""
    out = []
    in_str = False
    escaped = False
    hits = 0
    for ch in text:
        if in_str:
            if escaped:
                out.append(ch)
                escaped = False
                continue
            if ch == "\\":
                out.append(ch)
                escaped = True
                continue
            if ch == '"':
                out.append(ch)
                in_str = False
                continue
            code = ord(ch)
            if code < 0x20:
                out.append(CTRL_ESCAPES.get(code, "\\u%04x" % code))
                hits += 1
                continue
            out.append(ch)
            continue
        if ch == '"':
            out.append(ch)
            in_str = True
            continue
        out.append(ch)
    return "".join(out), hits


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="清洗含裸控制字符的 JSON（原件不改，清洗件另存）")
    ap.add_argument("src", help="待清洗的 JSON 文件")
    ap.add_argument("-o", "--output", help="清洗件输出路径（缺省：<src 目录>/<stem>.clean.json）")
    ap.add_argument("--check", action="store_true",
                    help="只校验不落盘：合法返回 0，非法返回 1")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.src):
        sys.stderr.write("[FATAL] 文件不存在：%s\n" % args.src)
        return 2
    try:
        # newline="" 是**必须**的：默认的 universal-newlines 模式会在读入时把裸 CR(0x0D)
        # 预先翻译成 LF(0x0A)，于是下面的逐字符扫描根本看不到 CR ⇒ CTRL_ESCAPES[0x0D]
        # 成了死代码、清洗件里写的是 "\n" 而非 "\r"，解析后与原件的 "\r" **不等价**
        # （2026-11-04 实测：json.loads(原件,strict=False) == json.load(清洗件) 为 False）。
        # newline="" 关闭该翻译，裸 CR 原样进 text，才能按 CTRL_ESCAPES 转成 "\r"。
        with open(args.src, "r", encoding="utf-8", newline="") as f:
            text = f.read()
    except OSError as e:
        sys.stderr.write("[FATAL] 读不了 %s：%s\n" % (args.src, e))
        return 2

    try:
        json.loads(text)
        already = True
    except ValueError:
        already = False

    if args.check:
        if already:
            print("[OK] %s 已是合法 JSON" % args.src)
            return 0
        sys.stderr.write("[BAD] %s 不是合法 JSON：%s\n" % (args.src, _first_error(text)))
        return 1

    if already:
        # 原本就合法：不重排、不改写，直接原样复制一份（保证清洗件与原件字节相同）。
        out = args.output or _default_out(args.src)
        if out == args.src:
            sys.stderr.write("[FATAL] 拒绝原地覆盖原件：%s\n" % args.src)
            return 2
        with open(args.src, "rb") as fi, open(out, "wb") as fo:
            fo.write(fi.read())
        print("[OK] %s 原本合法，已原样复制到 %s" % (args.src, out))
        return 0

    fixed, hits = escape_controls_in_strings(text)
    try:
        json.loads(fixed)
    except ValueError as e:
        sys.stderr.write("[FATAL] 清洗后仍不可解析：%s\n" % e)
        return 1

    out = args.output or _default_out(args.src)
    if os.path.abspath(out) == os.path.abspath(args.src):
        sys.stderr.write("[FATAL] 拒绝原地覆盖原件：%s\n" % args.src)
        return 2
    # 写侧也 newline=""：不做换行翻译，保证输出字节 = fixed 字符串（否则在 CRLF 平台上
    # 每个 "\n" 会再变成 "\r\n"，与「只改被转义的那几个字符」的承诺不符）。
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write(fixed)
    print("[OK] %s：转义 %d 处裸控制字符 -> %s（原件未改）" % (args.src, hits, out))
    return 0


def _default_out(src):
    stem, ext = os.path.splitext(src)
    return stem + ".clean" + (ext or ".json")


def _first_error(text):
    try:
        json.loads(text)
    except ValueError as e:
        return str(e)
    return "unknown"


if __name__ == "__main__":
    sys.exit(main())
