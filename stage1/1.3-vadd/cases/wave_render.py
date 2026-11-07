#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把逐拍信号表（vcd_probe 输出的 TSV）画成波形 PNG（无 matplotlib，只用 PIL）。

输入 TSV 格式（vcd_probe.py --dump-tsv 产出）：
  time \t <sig1> \t <sig2> ...
  每行一拍；值为十六进制串（位宽 >32 时补零到 32 位），缺值为 "-"。

输出：一张或多张 PNG，每张画一段（stage 分组），行名 = 信号名，右侧标每拍取值。
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

CELL_W = 62
ROW_H = 30
LEFT = 330
TOP = 56
BOTTOM = 26


def load_tsv(path):
    rows = []
    with open(path, "r") as fh:
        header = None
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("\t")
            if header is None:
                header = cols
                continue
            rows.append(cols)
    return header, rows


def fmt_val(v, maxlen=14):
    if v in ("-", "", None):
        return "x"
    s = "%X" % int(v, 16)
    if len(s) <= maxlen:
        return s
    return s[:maxlen - 1] + "~"   # 高位优先显示，尾部用 ~ 表示被截断


def draw_png(path, title, header, rows, is_bus):
    """is_bus: 每列 True = 总线（画方块 + 值），False = 单比特（画方波高低）。"""
    n = len(rows)
    w = LEFT + CELL_W * n + 8
    h = TOP + ROW_H * len(header[1:]) + BOTTOM
    img = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 12)
        fbig = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 15)
    except Exception:
        font = ImageFont.load_default()
        fbig = font

    d.text((8, 10), title, fill="black", font=fbig)
    # 拍号标尺
    for i, r in enumerate(rows):
        x = LEFT + i * CELL_W
        d.line([(x, TOP - 8), (x, h - BOTTOM)], fill=(228, 228, 228))
        d.text((x + 2, h - BOTTOM + 4), r[0], fill=(110, 110, 110), font=font)

    for j, name in enumerate(header[1:]):
        y = TOP + j * ROW_H
        d.line([(0, y + ROW_H - 1), (w, y + ROW_H - 1)], fill=(238, 238, 238))
        d.text((6, y + 6), name[-40:], fill=(20, 20, 20), font=font)
        bus = is_bus[j] if j < len(is_bus) else True
        prev = None
        for i, r in enumerate(rows):
            v = r[j + 1] if j + 1 < len(r) else "-"
            x = LEFT + i * CELL_W
            if bus:
                txt = fmt_val(v)
                changed = (txt != prev)
                fill = (232, 242, 255) if changed else (248, 250, 255)
                d.rectangle([x + 1, y + 3, x + CELL_W - 2, y + ROW_H - 5],
                            fill=fill, outline=(120, 150, 200))
                d.text((x + 3, y + 5), txt, fill=(10, 30, 80), font=font)
                prev = txt
            else:
                hi = (v not in ("-", "", None)) and int(v, 16) != 0
                y_hi, y_lo = y + 4, y + ROW_H - 6
                if hi:
                    d.line([(x + 1, y_hi), (x + CELL_W - 2, y_hi)], fill=(190, 40, 40), width=2)
                    d.text((x + 8, y_hi + 1), "1", fill=(150, 30, 30), font=font)
                else:
                    d.line([(x + 1, y_lo), (x + CELL_W - 2, y_lo)], fill=(70, 70, 190), width=2)
                    d.text((x + 8, y_lo - 14), "0", fill=(50, 50, 150), font=font)
                prev = hi
    img.save(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--prefix", default="vadd_stages")
    ap.add_argument("--groups", default="IF,ID,RN,DP,IS,EX,WB",
                    help="按列名前缀分组，每组一张 PNG")
    ap.add_argument("--bus-cols", default="", help="额外总线列（逗号分隔）")
    a = ap.parse_args()

    header, rows = load_tsv(a.tsv)
    os.makedirs(a.out_dir, exist_ok=True)
    bus_names = set(x for x in a.bus_cols.split(",") if x)
    produced = []
    for g in [x for x in a.groups.split(",") if x]:
        cols = [i for i, h in enumerate(header) if i > 0 and h.startswith(g + "_")]
        if not cols:
            continue
        sub = [header[0]] + [header[i] for i in cols]
        subrows = [[r[0]] + [r[i] for i in cols] for r in rows]
        is_bus = []
        for i in cols:
            nm = header[i]
            is_bus.append(nm in bus_names or not nm.endswith(("_valid", "_ready", "_wen",
                        "_vecWen", "_vm", "_vill", "_vma", "_vta", "_out_valid")))
        out = os.path.join(a.out_dir, "%s_%s.png" % (a.prefix, g))
        draw_png(out, "%s —— %s" % (a.prefix, g), sub, subrows, is_bus)
        produced.append(out)
    if not produced:
        out = os.path.join(a.out_dir, a.prefix + "_all.png")
        is_bus = [h in bus_names or not h.endswith(("_valid", "_ready")) for h in header[1:]]
        draw_png(out, a.prefix, header, rows, is_bus)
        produced.append(out)
    for p in produced:
        print(p)


if __name__ == "__main__":
    sys.exit(main())
