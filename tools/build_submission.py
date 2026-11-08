#!/usr/bin/env python3
"""把提交材料打成官网能直接上传的一包：Markdown 原件 + 四份 PDF + 一份清单。"""

import os
import subprocess
import sys
import zipfile
from pathlib import Path

from markdown_it import MarkdownIt

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out" / "submit-20261108"

MD = MarkdownIt("commonmark").enable("table").enable("strikethrough")

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
body { font-family: "Noto Serif CJK SC", "Source Han Serif SC", serif;
       font-size: 10.5pt; line-height: 1.75; color: #111; }
h1 { font-size: 20pt; margin: 0 0 12pt 0; page-break-before: always; }
h1:first-child { page-break-before: avoid; }
h2 { font-size: 14pt; margin: 18pt 0 6pt; border-bottom: 1px solid #ccc; padding-bottom: 3pt; }
h3 { font-size: 12pt; margin: 14pt 0 4pt; }
p { margin: 4pt 0; text-align: justify; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; font-size: 9pt; }
th, td { border: 1px solid #999; padding: 4pt 6pt; vertical-align: top; }
th { background: #f0f0f0; }
code { font-family: "DejaVu Sans Mono", monospace; font-size: 9pt;
       background: #f4f4f4; padding: 0 2pt; }
pre { background: #f6f6f6; padding: 8pt; overflow-wrap: anywhere;
      white-space: pre-wrap; font-size: 8.5pt; }
blockquote { border-left: 3px solid #bbb; margin: 6pt 0; padding-left: 8pt; color: #444; }
ul, ol { margin: 4pt 0 4pt 18pt; }
img { max-width: 100%; }
.doc { page-break-after: always; }
.cover { text-align: center; padding-top: 60mm; }
.cover h1 { page-break-before: avoid; font-size: 26pt; border: 0; }
.cover p { font-size: 12pt; }
"""

META = [
    ("README.md", "仓库简介"),
    ("docs/README.md", "材料入口"),
    ("docs/正文/01_项目概述与任务对应.md", "第一章 项目概述与任务对应"),
    ("docs/正文/02_环境部署与运行验证.md", "第二章 环境部署与运行验证"),
    ("docs/正文/03_VADD指令执行过程.md", "第三章 VADD 指令执行过程"),
    ("docs/正文/04_指令规格与编码选择.md", "第四章 指令规格与编码选择"),
    ("docs/正文/05_微架构与RTL实现.md", "第五章 微架构与 RTL 实现"),
    ("docs/正文/06_整核接入与NEMU扩展.md", "第六章 整核接入与 NEMU 扩展"),
    ("docs/正文/07_功能测试与差分验证.md", "第七章 功能测试与差分验证"),
    ("docs/正文/08_性能测量.md", "第八章 性能测量"),
    ("docs/正文/09_面积时序与结构覆盖.md", "第九章 面积、时序、功耗与结构覆盖"),
    ("docs/正文/10_形式验证扩展与局限.md", "第十章 形式验证、扩展与局限"),
    ("docs/附录/A_环境与波形.md", "附录 A 环境与波形"),
    ("docs/附录/B_源码与验证.md", "附录 B 源码与验证"),
    ("docs/附录/C_模型与数据.md", "附录 C 模型与数据"),
    ("docs/图示索引.md", "图示索引"),
    ("REPRODUCE.md", "复现说明"),
    ("VALIDATION.md", "验证说明"),
    ("EVIDENCE_INDEX.md", "证据索引"),
]

STAGES = {
    "阶段一_环境与VADD": [
        "docs/正文/01_项目概述与任务对应.md",
        "docs/正文/02_环境部署与运行验证.md",
        "docs/正文/03_VADD指令执行过程.md",
        "docs/附录/A_环境与波形.md",
    ],
    "阶段二_设计与接入": [
        "docs/正文/04_指令规格与编码选择.md",
        "docs/正文/05_微架构与RTL实现.md",
        "docs/正文/06_整核接入与NEMU扩展.md",
        "docs/附录/B_源码与验证.md",
    ],
    "阶段三_验证与性能": [
        "docs/正文/07_功能测试与差分验证.md",
        "docs/正文/08_性能测量.md",
        "docs/正文/09_面积时序与结构覆盖.md",
        "docs/正文/10_形式验证扩展与局限.md",
        "docs/附录/C_模型与数据.md",
    ],
}

TITLE = "香山昆明湖 V2 自定义 vdot.vv · 提交材料"


def render(files, cover_sub=""):
    parts = [f'<div class="cover"><h1>{TITLE}</h1>']
    if cover_sub:
        parts.append(f"<p>{cover_sub}</p>")
    parts.append("<p>芯芯像绒 · 南昌交通学院 · 2026-11-08</p></div>")
    for rel in files:
        path = ROOT / rel
        text = path.read_text(encoding="utf-8")
        parts.append(f'<section class="doc">{MD.render(text)}</section>')
    body = "\n".join(parts)
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>{body}</body></html>'


def to_pdf(html_path, pdf_path):
    cmd = [
        "google-chrome", "--headless=new", "--disable-gpu", "--no-sandbox",
        "--no-pdf-header-footer", "--virtual-time-budget=15000",
        f"--print-to-pdf={pdf_path}", html_path.as_uri(),
    ]
    subprocess.run(cmd, check=True, capture_output=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    all_files = [p for p, _ in META]

    jobs = [(TITLE + "（总册）", all_files, "提交材料总册", "")]
    for name, files in STAGES.items():
        jobs.append((name, files, name, name.replace("_", " · ")))

    produced = []
    for _title, files, stem, sub in jobs:
        html = OUT / f"_{stem}.html"
        html.write_text(render(files, sub), encoding="utf-8")
        pdf = OUT / f"{stem}.pdf"
        to_pdf(html, pdf)
        html.unlink()
        produced.append(pdf.name)
        print(f"PDF  {pdf.name}  {pdf.stat().st_size/1024/1024:.1f} MB")

    note = OUT / "00_提交说明.md"
    note.write_text(
        "# 提交材料说明\n\n"
        "这一包对应 2026 CIE 香山赛道三个阶段。\n\n"
        "| 文件 | 内容 |\n|---|---|\n"
        "| 提交材料总册.pdf | 十章正文、三份附录、图示索引、复现、验证、证据索引，一份读完 |\n"
        "| 阶段一_环境与VADD.pdf | 概述、环境、VADD 波形、附录 A |\n"
        "| 阶段二_设计与接入.pdf | 规格、微架构、整核接入、附录 B |\n"
        "| 阶段三_验证与性能.pdf | 功能测试、性能、面积时序覆盖、形式与局限、附录 C |\n"
        "| docs/ | 以上正文的 Markdown 原件 |\n"
        "| README.md、REPRODUCE.md、VALIDATION.md、EVIDENCE_INDEX.md | 仓库首页、复现、验证、证据索引 |\n\n"
        "上传顺序：阶段一传阶段一 PDF，阶段二传阶段二 PDF，阶段三传阶段三 PDF；"
        "总册作为补充材料一并上传。\n",
        encoding="utf-8",
    )

    zpath = OUT / "提交材料.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for f in ["README.md", "REPRODUCE.md", "VALIDATION.md", "EVIDENCE_INDEX.md"]:
            z.write(ROOT / f, f)
        for p in sorted((ROOT / "docs").rglob("*.md")):
            z.write(p, p.relative_to(ROOT).as_posix())
        for pdf in OUT.glob("*.pdf"):
            z.write(pdf, pdf.name)
        z.write(note, note.name)
    print(f"ZIP  {zpath.name}  {zpath.stat().st_size/1024/1024:.1f} MB")
    print("目录：", OUT)


if __name__ == "__main__":
    sys.exit(main())
