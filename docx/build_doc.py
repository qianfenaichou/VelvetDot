#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 CIE 2026 香山赛道参赛资料汇总 docx。"""

import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.opc.constants import RELATIONSHIP_TYPE as RT

BASE = os.path.dirname(os.path.abspath(__file__))
ATT = os.path.join(BASE, "attachments")
OUT = os.path.join(BASE, "CIE-香山赛道-参赛资料汇总.docx")

NAVY = RGBColor(0x1F, 0x38, 0x64)
BLUE = RGBColor(0x2E, 0x5C, 0x9A)
GRAY = RGBColor(0x59, 0x59, 0x59)
RED = RGBColor(0xC0, 0x00, 0x00)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

CN_FONT = "微软雅黑"
CN_BODY = "宋体"
EN_FONT = "Calibri"
MONO = "Consolas"


def set_run_font(run, size=10.5, bold=None, color=None, font=CN_BODY, mono=False):
    run.font.name = EN_FONT if not mono else MONO
    run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = color
    r = run._element
    rPr = r.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:ascii"), EN_FONT if not mono else MONO)
    rFonts.set(qn("w:hAnsi"), EN_FONT if not mono else MONO)
    rFonts.set(qn("w:eastAsia"), font)


def add_para(doc, text="", size=10.5, bold=False, color=None, align=None,
             space_before=0, space_after=4, line=1.35, indent=None, font=CN_BODY):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    pf.line_spacing = line
    if indent is not None:
        pf.first_line_indent = Cm(indent)
    if text:
        r = p.add_run(text)
        set_run_font(r, size=size, bold=bold, color=color, font=font)
    return p


_NUM = [0]


def add_heading(doc, text, level=1):
    _NUM[0] = 0
    sizes = {1: 17, 2: 14, 3: 12, 4: 10.5}
    colors = {1: NAVY, 2: NAVY, 3: BLUE, 4: BLUE}
    p = doc.add_heading(level=level)
    p.paragraph_format.space_before = Pt(14 if level == 1 else 10)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    if level == 1:
        p.paragraph_format.page_break_before = True
    r = p.add_run(text)
    set_run_font(r, size=sizes.get(level, 10.5), bold=True, color=colors.get(level, NAVY), font=CN_FONT)
    return p


def add_bullet(doc, text, level=0, size=10.5, bold_prefix=None):
    p = doc.add_paragraph(style="List Bullet" if level == 0 else "List Bullet 2")
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.3
    if bold_prefix:
        r = p.add_run(bold_prefix)
        set_run_font(r, size=size, bold=True)
    r = p.add_run(text)
    set_run_font(r, size=size)
    return p


def add_number(doc, text, size=10.5):
    _NUM[0] += 1
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(0.75)
    p.paragraph_format.first_line_indent = Cm(-0.75)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.3
    r = p.add_run(f"{_NUM[0]}. ")
    set_run_font(r, size=size, bold=True)
    r2 = p.add_run(text)
    set_run_font(r2, size=size)
    return p


def shade_cell(cell, hex_color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER


def set_cell_margins(cell, top=60, bottom=60, left=90, right=90):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement("w:tcMar")
    for tag, val in (("top", top), ("bottom", bottom), ("left", left), ("right", right)):
        el = OxmlElement(f"w:{tag}")
        el.set(qn("w:w"), str(val))
        el.set(qn("w:type"), "dxa")
        tcMar.append(el)
    tcPr.append(tcMar)


def set_row_cant_split(row):
    trPr = row._tr.get_or_add_trPr()
    cant = OxmlElement("w:cantSplit")
    trPr.append(cant)


def set_repeat_header(row):
    trPr = row._tr.get_or_add_trPr()
    hdr = OxmlElement("w:tblHeader")
    hdr.set(qn("w:val"), "true")
    trPr.append(hdr)


def add_table(doc, headers, rows, widths=None, font_size=9, header_bg="1F3864",
              zebra=True, first_col_bold=False, tight=False):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True
    pad = (30, 30, 60, 60) if tight else (60, 60, 90, 90)
    hdr = table.rows[0].cells
    set_row_cant_split(table.rows[0])
    set_repeat_header(table.rows[0])
    for i, h in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run(h)
        set_run_font(r, size=font_size, bold=True, color=WHITE)
        shade_cell(hdr[i], header_bg)
        set_cell_margins(hdr[i], *pad)
    for ri, row in enumerate(rows):
        tr = table.add_row()
        set_row_cant_split(tr)
        cells = tr.cells
        for ci, val in enumerate(row):
            cells[ci].text = ""
            p = cells[ci].paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing = 1.15
            r = p.add_run(str(val))
            set_run_font(r, size=font_size, bold=(first_col_bold and ci == 0))
            set_cell_margins(cells[ci], *pad)
            if zebra and ri % 2 == 1:
                shade_cell(cells[ci], "F2F5FA")
    if widths:
        for i, w in enumerate(widths):
            for row in table.rows:
                row.cells[i].width = Cm(w)
    return table


def add_code_block(doc, code, size=8.5):
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_row_cant_split(table.rows[0])
    cell = table.rows[0].cells[0]
    shade_cell(cell, "F4F4F4")
    set_cell_margins(cell, 80, 80, 120, 120)
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.1
    for i, line in enumerate(code.split("\n")):
        if i:
            p.add_run().add_break()
        r = p.add_run(line)
        set_run_font(r, size=size, font=CN_BODY, mono=True)
    return table


def add_callout(doc, title, body, bg="FFF2CC", border="BF9000"):
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = table.rows[0].cells[0]
    shade_cell(cell, bg)
    set_cell_margins(cell, 120, 120, 160, 160)
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run(title)
    set_run_font(r, size=10.5, bold=True, color=RED)
    for line in body.split("\n"):
        p2 = cell.add_paragraph()
        p2.paragraph_format.space_after = Pt(0)
        p2.paragraph_format.line_spacing = 1.3
        r2 = p2.add_run(line)
        set_run_font(r2, size=9.5)


def add_hyperlink(paragraph, url, text=None, size=9.5):
    part = paragraph.part
    r_id = part.relate_to(url, RT.HYPERLINK, is_external=True)
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), r_id)
    new_run = OxmlElement("w:r")
    rPr = OxmlElement("w:rPr")
    rFonts = OxmlElement("w:rFonts")
    rFonts.set(qn("w:ascii"), EN_FONT)
    rFonts.set(qn("w:hAnsi"), EN_FONT)
    rFonts.set(qn("w:eastAsia"), CN_BODY)
    rPr.append(rFonts)
    color = OxmlElement("w:color")
    color.set(qn("w:val"), "0563C1")
    rPr.append(color)
    u = OxmlElement("w:u")
    u.set(qn("w:val"), "single")
    rPr.append(u)
    sz = OxmlElement("w:sz")
    sz.set(qn("w:val"), str(int(size * 2)))
    rPr.append(sz)
    new_run.append(rPr)
    t = OxmlElement("w:t")
    t.text = text or url
    new_run.append(t)
    hyperlink.append(new_run)
    paragraph._p.append(hyperlink)


def add_link_para(doc, label, url, size=9.5):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.25
    if label:
        r = p.add_run(label + "：")
        set_run_font(r, size=size, bold=True)
    add_hyperlink(p, url, url, size=size)
    return p


def add_page_number_footer(section):
    footer = section.footer
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("CIE 2026 香山赛道资料汇编  ·  第 ")
    set_run_font(r, size=8, color=GRAY)
    run = p.add_run()
    set_run_font(run, size=8, color=GRAY)
    fld1 = OxmlElement("w:fldChar"); fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText"); instr.set(qn("xml:space"), "preserve"); instr.text = "PAGE"
    fld2 = OxmlElement("w:fldChar"); fld2.set(qn("w:fldCharType"), "end")
    run._r.append(fld1); run._r.append(instr); run._r.append(fld2)
    r2 = p.add_run(" 页")
    set_run_font(r2, size=8, color=GRAY)


def add_header(section, text):
    header = section.header
    p = header.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    r = p.add_run(text)
    set_run_font(r, size=8, color=GRAY)


def build():
    doc = Document()

    # 页面设置
    section = doc.sections[0]
    section.page_height = Cm(29.7)
    section.page_width = Cm(21.0)
    section.top_margin = Cm(2.2)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(2.2)
    section.right_margin = Cm(2.2)
    add_header(section, "CIE 全国 RISC-V 高水平创新及应用大赛（第二届）")
    add_page_number_footer(section)

    # 默认样式
    style = doc.styles["Normal"]
    style.font.name = EN_FONT
    style.font.size = Pt(10.5)
    style._element.rPr.rFonts.set(qn("w:eastAsia"), CN_BODY)

    # ================= 封面 =================
    for _ in range(3):
        add_para(doc, "", space_after=0)

    add_para(doc, "CIE 全国 RISC-V 高水平创新及应用大赛", size=22, bold=True,
             color=NAVY, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=2, font=CN_FONT)
    add_para(doc, "（第二届）", size=18, bold=True,
             color=NAVY, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=14, font=CN_FONT)
    add_para(doc, "CIE-香山社区 RISC-V 应用创新赛道", size=25, bold=True,
             color=RED, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=14, font=CN_FONT)
    add_para(doc, "参赛资料汇编", size=20, bold=True, color=NAVY,
             align=WD_ALIGN_PARAGRAPH.CENTER, space_after=30, font=CN_FONT)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("赛题：面向边缘 AI 大语言模型推理的 RISC-V 自定义 vdot 指令设计\n——基于“香山”昆明湖 V2 处理器架构")
    set_run_font(r, size=14, bold=True, color=BLUE, font=CN_FONT)

    add_para(doc, "", space_after=24)
    add_para(doc, "命题方：北京开源芯片研究院", size=12, bold=True,
             align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6, font=CN_FONT)
    add_para(doc, "资料采集日期：2026 年 10 月 29 日", size=11,
             align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6)
    add_para(doc, "官方页面：https://rv.cie.org.cn/direction?id=8", size=10,
             align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6, color=GRAY)

    add_para(doc, "", space_after=30)
    add_para(doc, "本文件由公开网页与官方仓库整理，最终以大赛官网和组委会通知为准。", size=9,
             align=WD_ALIGN_PARAGRAPH.CENTER, color=GRAY)


    # ================= 0. 速览 =================
    add_heading(doc, "0. 一页速览", 1)
    add_callout(
        doc,
        "⚠ 最重要的事：报名截止 2026-11-08 23:59:59",
        "截至 2026-10-29，本赛道官网显示已有 46 支团队报名（count_team=46）。\n"
        "每个参赛项目限报 1 个赛题，一经选定不得更改；报名截止后参赛代表不可更改。\n"
        "建议至少提前 3 天完成官网报名、组队和材料初稿，避免最后时刻网络拥堵。"
    )
    add_para(doc, "", space_after=2)

    add_table(doc,
        ["项目", "内容"],
        [
            ["赛事", "CIE 全国 RISC-V 高水平创新及应用大赛（第二届）"],
            ["方向 / 赛道", "高水平应用方向 / CIE-香山社区 RISC-V 应用创新赛道"],
            ["赛题", "面向边缘 AI 大语言模型推理的 RISC-V 自定义 vdot 指令设计——基于“香山”昆明湖 V2 处理器架构"],
            ["命题方", "北京开源芯片研究院"],
            ["目标平台", "香山昆明湖 V2（Kunminghu V2）"],
            ["指令规格", "vdot.vv，SEW=8，VLEN=128；两个源向量各取 8 个 int8 做点积，结果写 vd[0]，其余通道清零"],
            ["报名时间", "2026-06-30 00:00:00 — 2026-11-08 23:59:59"],
            ["格式审查", "2026-11-09 — 2026-11-13"],
            ["预赛", "2026-11-16 — 2026-11-27（线上材料评审）"],
            ["选拔赛", "2026-11-30 — 2026-12-18（线上材料评审）"],
            ["总决赛", "官网流程 2026-12-21 — 2027-01-16；预计 2027 年 1 月中旬线下"],
            ["团队人数", "1–6 人（本赛题 subject 设置 min_number=1, max_number=6）"],
            ["奖金", "钻石 5000 元（1 项）；铂金 3000 元（≤5 项）；金奖 1000 元（≤10 项）；银奖 500 元（≤20 项），均含税"],
            ["官方页面", "https://rv.cie.org.cn/direction?id=8"],
            ["咨询电话", "大赛咨询 010-68600753；监督 010-68600638；大赛办公室 010-68600640"],
        ],
        widths=[3.2, 13.4], font_size=9, first_col_bold=True)

    add_heading(doc, "0.1 本资料夹里有什么", 2)
    add_bullet(doc, "本 docx：赛事、赛题、规则、评分、提交、备赛资源、技术路线的一份完整汇总。", bold_prefix="")
    add_bullet(doc, "attachments/：官网通知 PDF、参赛手册 PDF、vdot 语义图、赛道咨询群二维码、备赛指南视频与波形样例。")
    add_bullet(doc, "data/：从官网 API 抓取的结构化原始数据（home、race、subject、help）。")
    add_bullet(doc, "repos/：已下载的香山代码/文档仓库（详见第 8 章）。")


    # ================= 1. 大赛与赛道概况 =================
    add_heading(doc, "1. 大赛与赛道概况", 1)
    add_heading(doc, "1.1 大赛基本信息", 2)
    add_para(doc, "赛事名称：CIE 全国 RISC-V 高水平创新及应用大赛（第二届）。", indent=0.74)
    add_para(doc, "赛事主题：芯芯之火·芯芯向荣。", indent=0.74)
    add_para(doc, "主办单位：中国电子学会、国家工业信息安全发展研究中心、中国电子技术标准化研究院。", indent=0.74)
    add_para(doc, "承办单位：中电新一代（北京）信息技术研究院有限公司。", indent=0.74)
    add_para(doc, "组织委员会主席单位：中国电子学会、国家工业信息安全发展研究中心、中国电子技术标准化研究院、"
                  "中国科学院计算技术研究所、中国科学院软件研究所。", indent=0.74)
    add_para(doc, "副主席单位包括：中电标协 RISC-V 工作委员会、中国开放指令生态（RISC-V）联盟、"
                  "中国电子学会高校电子信息学科建设专家委员会、如意 RISC-V 社区、北京开源芯片研究院、"
                  "中兴通讯、达摩院、进迭时空等。", indent=0.74)

    add_heading(doc, "1.2 赛道结构（第二届）", 2)
    add_table(doc,
        ["方向", "赛道", "命题方 / 方向"],
        [
            ["RISC-V 高水平创新方向", "企业和科研机构赛道", "中国电子学会；处理器 IP、芯片、基础软件、工具链等"],
            ["RISC-V 高水平创新方向", "高校赛道", "中国电子学会、天津大学、复旦大学、北京理工大学、西安交通大学、中国科学院软件研究所"],
            ["RISC-V 高水平应用方向", "CIE-香山社区", "北京开源芯片研究院；围绕“香山”昆明湖开展处理器研发与应用创新"],
            ["RISC-V 高水平应用方向", "CIE-中兴&砺睿微", "中兴通讯、中兴微电子、北京砺睿微；RISC-V 基础库/AI 算子库性能优化、生态建设"],
            ["RISC-V 高水平应用方向", "CIE-玄铁", "达摩院、杭州电子科技大学、龙蜥社区、九宸微电子；视觉大模型智能问答 Agent"],
            ["RISC-V 高水平应用方向", "CIE-进迭时空", "进迭时空；基于 K1 的嵌入式终端、边缘 AI、大模型部署"],
        ],
        widths=[3.3, 3.6, 9.7], font_size=8.5)

    add_heading(doc, "1.3 香山赛道定位", 2)
    add_para(doc, "官网赛道介绍原文：", bold=True, space_before=4)
    add_para(doc, "“主要围绕‘香山’开源 RISC-V 高性能处理器核昆明湖，开展处理器研发与应用创新相关的技术探索与实践，"
                  "包括但不限于指令执行动态分析、AI 指令功能扩展、性能优化等方向，进行项目的征集和评选。”",
             indent=0.74, color=GRAY)
    add_para(doc, "命题方：北京开源芯片研究院。", indent=0.74)
    add_para(doc, "面向群体：对 RISC-V 高性能处理器感兴趣的学生群体、RISC-V 领域相关科研机构、创业企业、处理器设计厂商。",
             indent=0.74)
    add_para(doc, "赛道领域：高性能计算与人工智能，强调 RISC-V + AI 的系统软件栈、核心 IP、关键芯片与智算解决方案。",
             indent=0.74)

    add_heading(doc, "1.4 奖项与奖金（香山赛道）", 2)
    add_table(doc,
        ["奖项", "奖金（含税）", "名额", "说明"],
        [
            ["钻石奖", "5,000 元 / 项目", "仅 1 个项目", "总决赛最高奖项"],
            ["铂金奖", "3,000 元 / 项目", "不超过 5 个项目", "总决赛优胜奖"],
            ["金奖", "1,000 元 / 项目", "不超过 10 个项目", "总决赛优胜奖"],
            ["银奖", "500 元 / 项目", "不超过 20 个项目", "总决赛优胜奖"],
        ],
        widths=[3.0, 4.2, 4.2, 5.2], font_size=9)
    add_para(doc, "注：以官网通知为准；奖金颁发给获奖项目所属团队的牵头人或牵头单位。除奖金外，还有证书、"
                  "实习就业内推、能力等级证书、高校推免/考研复试推荐信、开发板套件、笔记本套件（指导教师）、"
                  "高端学术会议与行业活动席位等激励。", size=9.5, color=GRAY)

    add_heading(doc, "1.5 联系方式", 2)
    add_bullet(doc, "大赛咨询电话：010-68600753（工作日 09:00–17:00）")
    add_bullet(doc, "大赛监督电话：010-68600638")
    add_bullet(doc, "大赛办公室：010-68600640")
    add_bullet(doc, "赛题和技术咨询：在大赛网站报名后，通过专属交流群沟通。香山赛道咨询群二维码见下方。")

    add_heading(doc, "1.6 香山赛道咨询群", 2)
    add_para(doc, "官网说明：赛题和技术咨询需先在大赛网站完成报名，再通过专属交流群沟通。群内会发布赛题更新、"
                  "提交提醒、答疑与社区活动信息。建议进群前先准备好团队名称、学校/单位、所选赛题和当前进度，"
                  "提问时附上复现步骤、命令、报错日志与环境信息（OS、编译器版本、commit hash），更容易得到有效答复。",
             indent=0.74)
    add_table(doc,
        ["进群前建议准备", "说明"],
        [
            ["团队名称 / 牵头人", "与官网报名信息保持一致，便于组委会核对"],
            ["学校 / 单位", "在校生注明学校与年级；单位注明名称"],
            ["赛题名称", "面向边缘 AI 大语言模型推理的 RISC-V 自定义 vdot 指令设计"],
            ["环境信息", "OS 版本、gcc/clang 版本、JDK 版本、XiangShan commit hash"],
            ["问题复现", "命令、完整报错、日志片段、已尝试的方案"],
        ],
        widths=[4.6, 12.0], font_size=8.5, first_col_bold=True)
    qr = os.path.join(ATT, "xiangshan_group.jpg")
    if os.path.exists(qr):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(qr, width=Cm(5.0))
        add_para(doc, "香山赛道咨询群二维码（来自官网 race/detail?id=8 的 group_image）",
                 size=8.0, color=GRAY, align=WD_ALIGN_PARAGRAPH.CENTER)


    # ================= 2. 赛题详解 =================
    add_heading(doc, "2. 赛题详解", 1)
    add_heading(doc, "2.1 赛题名称与目标平台", 2)
    add_para(doc, "赛题名称：面向边缘 AI 大语言模型推理的 RISC-V 自定义 vdot 指令设计——基于“香山”昆明湖 V2 处理器架构。",
             bold=True, indent=0.74)
    add_bullet(doc, "目标平台：“香山”昆明湖 V2 处理器（国产开源高性能 RISC-V 处理器）。")
    add_bullet(doc, "技术基础：具备成熟的向量扩展与自定义指令接口。")
    add_bullet(doc, "核心要求：复用香山昆明湖 V2 现有的向量实现，将 vdot 指令作为向量指令集中新增的自定义指令进行功能单元扩展。")
    add_bullet(doc, "指令语义：vdot.vv，SEW = 8，VLEN = 128。")

    add_heading(doc, "2.2 赛题背景", 2)
    add_para(doc, "点积（Dot Product）是深度学习模型的核心计算内核，在推荐系统、大语言模型（LLM）等 AI 应用中通常占据总计算量的 60%–80%。",
             indent=0.74)
    add_para(doc, "在推荐系统中，78% 的个性化推荐将点积作为核心排序指标，用于计算用户向量与商品向量的匹配度；"
                  "在 Transformer 架构的 LLM 中，自注意力机制的矩阵乘法由海量点积构成，以 GPT-2 为例，点积占总计算量 70% 以上，"
                  "其执行效率直接决定推理性能与能效，尤其在资源受限的边缘端更为关键。", indent=0.74)
    add_para(doc, "RISC-V 凭借开源、模块化及可自定义扩展的优势，成为边缘 AI 处理器的主流架构。通过自定义向量点积指令（vdot），"
                  "可在处理器流水线中集成专用硬件加速单元，以极小面积开销换取数倍点积吞吐提升，满足边缘 LLM 对高性能、低功耗、低成本的需求。",
             indent=0.74)
    add_para(doc, "“香山”昆明湖 V2 作为国产高性能 RISC-V 处理器，具备成熟的向量扩展与自定义指令接口，为 vdot 指令的硬件集成提供了理想的架构基础。",
             indent=0.74)

    add_heading(doc, "2.3 vdot.vv 指令语义", 2)
    add_para(doc, "官网赛题给出的参考语义（伪代码）：", bold=True)
    add_code_block(doc,
"""def vdot_vv(vs1, vs2, sew=8):
    # 根据SEW设定，从两个源向量寄存器中各取8个int8数据
    result = 0
    for i in range(8):
        result += sign_extend(vs1[i]) * sign_extend(vs2[i])
    # 结果写入目标向量寄存器vd的第一个元素
    vd[0] = result
    vd[1..VLEN-1] = 0  # 其他通道清零""")
    img = os.path.join(ATT, "vdot_semantics.png")
    if os.path.exists(img):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(img, width=Cm(13.5))
        add_para(doc, "图：官网赛题页给出的 vdot_vv 参考语义（attachments/vdot_semantics.png）",
                 size=8.5, color=GRAY, align=WD_ALIGN_PARAGRAPH.CENTER)
    add_callout(doc, "实现要点（务必在设计中写清楚）",
        "1) 两个源向量各取 8 个 int8（SEW=8），做符号扩展后相乘，建议 32 位累加；\n"
        "2) 结果写入 vd[0]；vd[1..VLEN-1] 清零（不是 tail-agnostic 的随机值）；\n"
        "3) 官网伪代码没有明确 vd[0] 的位宽：SEW=8 时 vd[0] 只有 8 位，装不下 8 个 int8 乘积的和（最大 8×127×127=129032，至少需要 18 位有符号）。建议在设计文档中明确结果位宽与写入方式（例如按 32 位结果写入 vd 的最低 32 位，其余字节清零），并与 NEMU/RTL 保持一致；如组委会给出补充口径，以官方为准；\n"
        "4) 需明确 vl、vstart、vm、LMUL 等向量配置对语义的影响；建议在报告中给出你的取舍与理由；\n"
        "5) 指令编码需避开现有 RVV 指令，并在 NEMU 与 RTL 两侧保持一致。",
        bg="DEEAF6", border="2E5C9A")

    add_heading(doc, "2.4 三个阶段与交付物", 2)
    add_para(doc, "三个阶段难度递进，评审将根据完成度逐级评价。无论本科生还是研究生，都能找到适合自己的挑战。",
             indent=0.74)

    add_heading(doc, "阶段一：环境部署（入门难度）", 3)
    add_para(doc, "你需要按照香山操作手册完成开发环境部署，输出验证信息与操作日志，并基于仿真波形分析向量加法指令的执行过程。"
                  "这一步让你快速上手真实的工业级处理器开发环境，为后续设计打下基础。", indent=0.74)
    add_bullet(doc, "1.1 环境部署验证：输出 hello xiangshan, I am xxx, IP address（xxx 替换为团队或个人标识）。")
    add_bullet(doc, "1.2 操作日志：完整的开发环境部署与操作过程日志。")
    add_bullet(doc, "1.3 向量加法指令执行过程文档：依据仿真波形和参考文档，描述向量加法指令在香山中的执行过程。")

    add_heading(doc, "阶段二：设计与实现（中等难度）", 3)
    add_para(doc, "根据 vdot.vv 指令语义（SEW=8，VLEN=128），完成设计文档和 RTL 实现，并基于香山仿真环境完成正数、负数、边界值三项基础功能测试。"
                  "你将真正在香山向量执行单元中新增一条自定义指令，体验从指令定义到 RTL 编码再到功能验证的完整硬件开发流程，"
                  "理解向量数据通路、符号扩展和累加器等关键模块。", indent=0.74)
    add_bullet(doc, "2.1 vdot.vv 设计文档：包含指令语义、微架构设计、数据通路等完整设计说明。")
    add_bullet(doc, "2.2 vdot.vv RTL 实现：Verilog/Chisel 代码，实现 vdot.vv 指令功能单元扩展。")
    add_bullet(doc, "2.3.1 正数点积测试：基于香山仿真环境，验证正数输入的点积结果。")
    add_bullet(doc, "2.3.2 负数点积测试：基于香山仿真环境，验证含负数输入的点积结果。")
    add_bullet(doc, "2.3.3 边界值测试：基于香山仿真环境，验证边界值（如最大值、最小值、零等）的点积结果。")

    add_heading(doc, "阶段三：验证与优化（高难度）", 3)
    add_para(doc, "为 NEMU 模拟器新增 vdot 指令，完成 RTL 与 NEMU 的协同仿真；用已有向量指令组合实现相同功能作为基线；"
                  "对比基线组合与 vdot 专用加速单元的延迟，完成加速比分析。你将掌握软硬件协同验证方法，"
                  "量化评估微架构优化的收益，学会用数据证明专用硬件加速的价值——这是处理器性能工程师的核心能力。", indent=0.74)
    add_bullet(doc, "3.1.1 NEMU 指令扩展：为 NEMU 模拟器新增 vdot.vv 指令支持。")
    add_bullet(doc, "3.1.2 协同仿真验证：完成 NEMU 与 RTL 的协同仿真测试，确保一致性。")
    add_bullet(doc, "3.2 基线功能实现：用 RISC-V 已有向量指令组合实现 vdot 相同功能（作为性能对比基线）。")
    add_bullet(doc, "3.3 延迟加速分析报告：对比 Baseline（组合指令）与 vdot 加速单元的 latency 加速比分析。")

    add_heading(doc, "2.5 作品提交形式（官方原文整理）", 2)
    add_para(doc, "1）在系统的文档提交位置：", bold=True)
    add_bullet(doc, "第一阶段的执行日志、过程文档；")
    add_bullet(doc, "第二阶段的设计文档和基础测试文档；")
    add_bullet(doc, "第三阶段的协同仿真和性能分析文档。")
    add_para(doc, "2）在系统的视频提交位置：", bold=True)
    add_bullet(doc, "第一阶段的操作过程录屏；")
    add_bullet(doc, "第二阶段的解题思路讲解录屏；")
    add_bullet(doc, "第三阶段的基于波形仿真和性能分析录屏。")
    add_para(doc, "3）在大赛官网系统的相应位置上传参赛方的代码仓库：", bold=True)
    add_bullet(doc, "按要求，参赛者需将加密后的代码仓库同步到 https://github.com/OpenXiangShan/XiangShanLab.git（详细流程见第 4 章）。")
    add_bullet(doc, "参赛者需提交 GitHub 仓库；选拔赛和总决赛需准备 PPT 讲解解题思路。")


    # ================= 2.6 评分规则 =================
    add_heading(doc, "2.6 评分规则（官网 rule_content 整理）", 2)
    add_para(doc, "官网赛题页给出的评分表如下。总分 100 分，四个一级指标：完整性 60%、可行性 20%、探索性 10%、创新性 10%。",
             indent=0.74)
    rubric = [
        ["完整性（60 分）", "60%", "阶段一交付物完成度", "是否完成环境部署验证、操作日志、向量加法指令执行文档", "15%", "15", "优秀 13–15 / 良好 9–13 / 一般 4–9 / 较差 0–4"],
        ["完整性（60 分）", "60%", "阶段二交付物完成度", "是否完成 vdot.vv 设计文档、RTL 实现、三项基础功能测试", "20%", "20", "优秀 16–20 / 良好 11–16 / 一般 6–11 / 较差 0–6"],
        ["完整性（60 分）", "60%", "阶段三交付物完成度", "是否完成 NEMU 扩展、协同仿真验证、基线实现、延迟加速分析报告", "25%", "25", "优秀 20–25 / 良好 13–20 / 一般 6–13 / 较差 0–6"],
        ["可行性（20 分）", "20%", "技术路径合理性", "设计文档与 RTL 实现是否可落地、是否复用香山现有向量实现", "10%", "10", "优秀 9–10 / 良好 7–9 / 一般 4–7 / 较差 0–4"],
        ["可行性（20 分）", "20%", "功能验证有效性", "测试用例是否覆盖正数、负数、边界值，协同仿真是否通过", "10%", "10", "优秀 9–10 / 良好 7–9 / 一般 4–7 / 较差 0–4"],
        ["探索性（10 分）", "10%", "微架构优化分析", "是否完成 Baseline 与 vdot 加速单元的延迟对比分析", "5%", "5", "优秀 4–5 / 良好 3–4 / 一般 2–3 / 较差 0–2"],
        ["探索性（10 分）", "10%", "软硬件协同理解", "是否理解 NEMU 与 RTL 的协同仿真机制", "5%", "5", "优秀 4–5 / 良好 3–4 / 一般 2–3 / 较差 0–2"],
        ["创新性（10 分）", "10%", "设计优化独特性", "在 vdot 指令实现中是否有独特的微架构或数据通路优化", "5%", "5", "优秀 4–5 / 良好 3–4 / 一般 2–3 / 较差 0–2"],
        ["创新性（10 分）", "10%", "扩展应用潜力", "方案是否具备向其他向量指令或更高 SEW/VLEN 扩展的能力", "5%", "5", "优秀 4–5 / 良好 3–4 / 一般 2–3 / 较差 0–2"],
    ]
    add_table(doc,
        ["一级指标", "一级权重", "二级指标", "指标描述", "二级权重", "分值", "得分档"],
        rubric, widths=[2.2, 1.5, 2.8, 4.8, 1.5, 1.0, 4.4], font_size=7.2, tight=True)

    add_heading(doc, "2.7 评分策略解读", 2)
    add_bullet(doc, "85 分集中在“完整性 + 可行性”：三个阶段都做出可验证的交付物，比只把第二阶段打磨到极致更划算。"
                    "建议先保证阶段一完整、阶段二可跑通、阶段三有最小闭环（NEMU 扩展 + 协同仿真 + 一个基线 + 一组延迟数据）。",
               bold_prefix="先拿满基础分：")
    add_bullet(doc, "60% 的完整性里，阶段三占 25 分，是单项最高。即使 vdot 数据通路不是最优，也要把 NEMU、协同仿真、基线、加速比报告四件事做齐。",
               bold_prefix="阶段三是分水岭：")
    add_bullet(doc, "可行性明确要求“复用香山现有向量实现”，所以设计文档里要写清楚复用了哪些模块（VecDataSplitModule、Mgu、VecPipedFuncUnit、VIMac64b 等），"
                    "避免重复造轮子；功能验证要覆盖正数、负数、边界值，并保留可复现的测试脚本与日志。",
               bold_prefix="复用是加分项：")
    add_bullet(doc, "探索性 10 分看 Baseline 与 vdot 的延迟对比；创新性 10 分看独特的数据通路优化与向更高 SEW/VLEN 扩展的能力。"
                    "报告里至少给出 latency、throughput、加速比三个量化指标，并解释瓶颈。",
               bold_prefix="15 分靠量化证据：")
    add_bullet(doc, "所有材料都要能复现：命令、commit hash、配置、波形、日志、测试输入/输出。评审最怕“只有结论没有证据”。",
               bold_prefix="可复现性是底线：")


    # ================= 3. 赛程与规则 =================
    add_heading(doc, "3. 赛程与参赛规则", 1)
    add_heading(doc, "3.1 赛程时间线", 2)
    add_table(doc,
        ["阶段", "时间", "形式 / 说明"],
        [
            ["报名", "2026-06-30 00:00:00 — 2026-11-08 23:59:59", "官网免费在线报名；组队、选择赛题"],
            ["格式审查", "2026-11-09 — 2026-11-13", "大赛办公室审查材料格式；收到通知需按期重新提交，否则视为放弃"],
            ["预赛", "2026-11-16 — 2026-11-27", "线上材料评审；评审时间官网标注 11-08 至 11-27"],
            ["选拔赛", "2026-11-30 — 2026-12-18", "线上材料评审；评审时间官网标注 12-07 至 12-18"],
            ["总决赛", "2026-12-21 — 2027-01-16（官网流程）", "预计 2027 年 1 月中旬线下举办；现场讲演 + 提问，可实物展示"],
        ],
        widths=[2.8, 6.2, 8.0], font_size=9)
    add_para(doc, "说明：以上为官网流程；具体时间安排和流程要求以大赛网站首页和新闻实时公布为准。",
             size=9, color=GRAY)

    add_heading(doc, "3.2 参赛团队规则（官方参赛手册）", 2)
    add_bullet(doc, "参赛团队可以是个人或单位。个人须具备完全民事行为能力；单位须是具有独立法人资格的企业、事业单位、科研院所、高校等。"
                    "允许跨单位组队；个人团队须指定 1 名牵头人，单位团队须指定 1 个牵头单位，均须用真实信息注册。")
    add_bullet(doc, "被列入“信用中国”失信被执行人、重大税收违法案件当事人名单、政府采购严重违法失信行为记录名单的个人和单位不得参赛。")
    add_bullet(doc, "同一参赛单位可以有多个团队参赛（不限方向、赛道、赛题）；每个团队可以向不同方向/赛道/赛题分别提交不同项目。")
    add_bullet(doc, "每位参赛代表（个人和单位）只能代表 1 个团队参加比赛；报名截止后参赛代表不可更改。")
    add_bullet(doc, "团队须对信息准确性、真实性负责；提供虚假信息将被注销资格、取消成绩、收回奖励。")
    add_bullet(doc, "本赛题团队人数：1–6 人（官网 subject 设置）。")

    add_heading(doc, "3.3 参赛项目规则", 2)
    add_bullet(doc, "每个参赛项目限报 1 个赛题，一经选定不得更改。")
    add_bullet(doc, "项目创意、产品、技术及相关专利等知识产权归参赛团队；不得侵犯他人专利权、著作权、商标权等；违者取消资格和成绩。")
    add_bullet(doc, "项目名称由团队自拟，须遵守法律法规和公序良俗。")
    add_bullet(doc, "选拔赛、总决赛期间，可在不改变项目名称和主要内容的前提下持续迭代，并在规定时间内更新材料。")
    add_bullet(doc, "评审期间须按要求补充材料；所有已提交材料默认不退还。")
    add_bullet(doc, "已发表论文、已参加其他赛事、已商业化落地的项目原则上可参赛，但不得侵权。")

    add_heading(doc, "3.4 报名与作品提交步骤（官网选手指南）", 2)
    add_number(doc, "打开 https://rv.cie.org.cn/home，点击右上角“注册/登录”，选择“中国电子学会用户登录”，跳转到统一认证页面。")
    add_number(doc, "完善资料：在校生填写学校名称、学信网截图、指导老师；非在校生填写单位名称、身份证、信用中国信息。")
    add_number(doc, "创建或加入团队：个人团队或单位团队；填写指导老师（如有）；队长负责报名操作。")
    add_number(doc, "首页导航“赛事内容”→ 选择“RISC-V 高水平应用方向”→“CIE-香山社区”→ 查看赛题详情 → “立即报名”。")
    add_number(doc, "个人中心 → 我的参赛，查看报名信息；切换“预赛”类目 → “更新项目” → 上传材料；红星为必填项。")
    add_number(doc, "每个赛事阶段以最后一次成功提交的资料为最终参赛项目资料；可重复提交更新。")

    add_heading(doc, "3.5 评审方式", 2)
    add_bullet(doc, "预赛、选拔赛均为线上材料评审，不需要线上答辩。")
    add_bullet(doc, "总决赛为线下现场讲演，可能需要实物展示，并接受评审委员会现场提问。")
    add_bullet(doc, "初赛/决赛提交文档说明材料和演示视频；若成果提交到开源项目，请在说明文档中附上相关 PR/MR。")

    add_heading(doc, "3.6 证书与奖励", 2)
    add_table(doc,
        ["证书 / 奖励", "获得条件"],
        [
            ["预赛完赛证书", "完成预赛阶段赛题并提交，材料符合格式审查要求，均可申请"],
            ["选拔赛晋级证书", "能够晋级总决赛的参赛项目"],
            ["总决赛奖励证书", "获得总决赛优胜奖（钻石/铂金/金/银）或专项奖（特色创新/商业潜力/评委推荐）"],
            ["指导教师奖励证书", "高校在读学生参赛团队晋级总决赛，指导教师可获得"],
            ["奖金", "香山赛道：钻石 5000 元（1 项）、铂金 3000 元（≤5 项）、金奖 1000 元（≤10 项）、银奖 500 元（≤20 项），含税"],
            ["其他激励", "实习就业内推、能力等级证书、高校推免/考研复试推荐信、开发板套件、笔记本套件（指导教师）、高端会议/行业活动席位"],
        ],
        widths=[4.0, 12.6], font_size=9, first_col_bold=True)

    add_heading(doc, "3.7 常见问题（官网 FAQ 摘要）", 2)
    add_table(doc,
        ["问题", "官方答复要点"],
        [
            ["可以跨赛道报名吗？", "不可以。每个参赛项目限报 1 个比赛方向下的 1 个赛题，一经选定不得更改。"],
            ["报名截止到什么时候？", "2026 年 11 月 8 日 24:00 准时结束，避免临近时刻网络拥堵。"],
            ["在校学生、企业员工、科研院所人员可以跨单位组队吗？", "可以。高校赛道要求团队牵头人须为在校学生，其余赛道无特定要求。"],
            ["团队人数有上下限吗？", "部分赛道有。高校赛道最多 3 名；玄铁赛道也有限制；其余赛道暂无明确限制。本赛题官网设置 1–6 人。"],
            ["同一单位/高校可以多支队伍报多个赛道吗？", "可以，但每个赛道的项目方案必须相互独立，不能雷同或相似。"],
            ["项目必须全新开发吗？", "不是必须。已发表论文、参加过其他赛事、已商业化落地的项目原则上可参赛，但不得侵权。"],
            ["预赛、选拔赛需要答辩吗？", "不需要。按目前流程，预赛、选拔赛都是材料评审。"],
            ["代码提交到哪里？", "赛题说明了提交位置就按说明上传；未说明可放在“其他材料”附件。"],
            ["什么是预赛完赛证书？", "完成赛题并提交，通过格式审查即可申领，不论得分高低。"],
            ["什么是指导教师证书？", "仅限高校学生参赛团队，在选拔赛、总决赛阶段均可获得。"],
            ["选拔赛与总决赛证书如何获得？", "选拔赛证书需得分靠前并晋级总决赛；总决赛证书需到现场参赛并入选优胜奖或专项奖。"],
            ["企业赛道可以提交视频等辅助材料吗？", "可以。辅助材料整体不超过 450MB，支持 PPT、宣传册、mp4/mov 等视频格式，内容不涉密。"],
        ],
        widths=[5.0, 11.6], font_size=7.6, first_col_bold=True, tight=True)


    # ================= 4. 香山赛道专属提交流程 =================
    add_heading(doc, "4. 香山赛道专属提交流程（XiangShanLab）", 1)
    add_para(doc, "香山赛道在官网系统之外，还要求把加密后的提交信息同步到香山社区仓库 XiangShanLab，并通过 Pull Request 提交。"
                  "官方仓库中的 SUBMISSION_GUIDE.md 给出了完整流程。", indent=0.74)
    add_link_para(doc, "提交指南", "https://github.com/OpenXiangShan/XiangShanLab/blob/master/2026-CIE-RISC-V-Contest-Application-Track/SUBMISSION_GUIDE.md")
    add_link_para(doc, "赛题目录", "https://github.com/OpenXiangShan/XiangShanLab/tree/master/2026-CIE-RISC-V-Contest-Application-Track")

    add_heading(doc, "4.1 三条提交链路", 2)
    add_table(doc,
        ["链路", "提交内容", "位置"],
        [
            ["大赛官网系统", "第一阶段执行日志/过程文档；第二阶段设计文档和基础测试文档；第三阶段协同仿真和性能分析文档", "个人中心 → 我的参赛 → 预赛 → 更新项目 → 文档提交位置"],
            ["大赛官网系统", "第一阶段操作录屏；第二阶段解题思路录屏；第三阶段波形仿真和性能分析录屏", "系统的视频提交位置"],
            ["大赛官网系统", "参赛方代码仓库地址", "大赛官网系统的相应位置"],
            ["XiangShanLab", "加密后的提交信息 submission.asc", "Fork 后提交到 01_参赛选手提交区/<团队名称>/，再发起 PR"],
        ],
        widths=[3.0, 9.6, 4.0], font_size=8.5, first_col_bold=True)

    add_heading(doc, "4.2 XiangShanLab 提交步骤", 2)
    add_number(doc, "Fork 主仓库：打开 https://github.com/OpenXiangShan/XiangShanLab，点击右上角 Fork 到自己的账号。")
    add_number(doc, "克隆自己 Fork 的仓库：git clone https://github.com/<你的用户名>/XiangShanLab.git，进入 "
                    "XiangShanLab/2026-CIE-RISC-V-Contest-Application-Track。")
    add_number(doc, "在 GitHub 上创建作品公有仓库，命名建议 cie2026-团队名称-作品名（示例 cie2026-innovators-riscv-ai）。"
                    "SUBMISSION_GUIDE 明确要求选择 public；但其 my_submission.txt 模板示例里写的是“私有仓库”，存在不一致，"
                    "建议以 public 为准并向组委会确认。")
    add_number(doc, "把作品代码、设计文档、测试、报告推到该公有仓库。")
    add_number(doc, "在 2026-CIE-RISC-V-Contest-Application-Track 目录下创建 my_submission.txt，按 4.3 填写。")
    add_number(doc, "运行 source ./submit.sh my_submission.txt。脚本会导入 contest/public-key.asc，用 GPG 加密 my_submission.txt，"
                    "生成 01_参赛选手提交区/<团队名称>/submission.asc。")
    add_number(doc, "git add . && git commit -m \"提交2026CIE大赛作品：<团队名称>\" && git push。")
    add_number(doc, "在 GitHub 发起 Pull Request：base 选 OpenXiangShan/XiangShanLab，head 选你的 Fork。"
                    "PR 标题格式：[2026CIE大赛] 团队名称 - 项目名称。")
    add_number(doc, "按模板填写 PR 描述，勾选阶段完成情况（阶段一/二/三），等待评审委员会在 PR 中反馈。")

    add_heading(doc, "4.3 my_submission.txt 字段模板", 2)
    add_code_block(doc,
"""team-name: 您的团队名称
repo-url: https://github.com/您的用户名/您的公有仓库.git
github-username: 您的GitHub用户名
contact-email: 您的邮箱@example.com
project-description: 简要描述您的项目，不超过100字

# 可选信息
team-members: 成员1(角色), 成员2(角色)
university: 您的学校/单位
advisor: 指导老师
phone: 联系电话
notes: 其他需要说明的事项""")
    add_para(doc, "注意：只提交加密后的 submission.asc；不要把 my_submission.txt 明文、手机号、邮箱等个人信息直接提交到公开仓库。",
             size=9.5, color=RED, bold=True)

    add_heading(doc, "4.4 PR 描述模板（官方）", 2)
    add_code_block(doc,
"""## 团队与项目信息
- **团队名称**：
- **参赛单位**：
- **赛题**：面向边缘AI大语言模型推理的RISC-V自定义vdot指令设计

## 阶段完成情况
- [ ] 阶段一：环境部署与验证
- [ ] 阶段二：vdot设计与实现
- [ ] 阶段三：协同仿真与评估

## 提交内容概述
（请简要说明本次提交的内容）

---
## 评审区（请评委填写）
**评审意见**：""")

    add_heading(doc, "4.5 容易踩的坑", 2)
    add_bullet(doc, "submit.sh 的 GPG 收件人是 3502918558@qq.com，公钥指纹 936E3DCCFEB2C1C1472BD43E11489B37147B12E1；脚本会从 contest/public-key.asc 导入。"
                    "如果 GPG 未安装，Ubuntu 用 sudo apt install gnupg，macOS 用 brew install gnupg。")
    add_bullet(doc, "SUBMISSION_GUIDE 写 PR base 为 main，但仓库默认分支是 master；创建 PR 时以页面实际默认分支为准。")
    add_bullet(doc, "团队名称会作为目录名，避免使用 /、空格、特殊字符；建议用英文/数字/下划线。")
    add_bullet(doc, "每个团队只创建一个提交目录；重复目录或覆盖他人目录会被视为异常提交。")
    add_bullet(doc, "官网系统和 XiangShanLab 两条链路都要完成，不要只做其中一条。")
    add_bullet(doc, "官方原文说“加密后的代码仓库”，但 submit.sh 实际加密的是 my_submission.txt（内含 repo-url），"
                    "不是把整个代码仓库加密上传；代码仓库放在公有 GitHub 仓库即可，submission.asc 只保护提交信息。")


    # ================= 5. 备赛资源 =================
    add_heading(doc, "5. 备赛资源与学习路径", 1)
    add_heading(doc, "5.1 已下载 / 建议下载的仓库", 2)
    add_table(doc,
        ["仓库", "用途", "分支 / 版本", "本地位置", "状态"],
        [
            ["OpenXiangShan/xs-env", "香山开发环境（工具链、脚本、子模块入口）", "master", "repos/xs-env", "已下载"],
            ["OpenXiangShan/XiangShan", "香山处理器 RTL（Chisel）", "kunminghu-v2", "repos/XiangShan", "已下载（含子模块）"],
            ["OpenXiangShan/XiangShanLab", "香山学习与实践仓库；含 2026 CIE 赛题目录、课程、题库", "master", "repos/XiangShanLab-docs（文本镜像）", "已下载文本；完整仓库见说明"],
            ["OpenXiangShan/NEMU", "RISC-V 指令模拟器；第三阶段要新增 vdot", "master", "repos/NEMU", "已下载"],
            ["OpenXiangShan/YunSuan", "向量 ALU / 向量 MAC 硬件库（VIMac64b 等）", "master", "repos/YunSuan", "已下载"],
            ["OpenXiangShan/XiangShan-doc", "香山设计文档（昆明湖 V2）", "master", "repos/XiangShan-doc-docs（文本镜像）", "文本镜像；完整仓库较大"],
            ["OpenXiangShan/ready-to-run", "预编译 workload 与 Difftest 参考库（riscv64-nemu-interpreter-so）", "kunminghu-v2", "repos/XiangShan/ready-to-run", "已随子模块下载"],
            ["OpenXiangShan/difftest", "差分验证框架", "master", "repos/XiangShan/difftest", "已随子模块下载"],
            ["OpenXiangShan/riscv-vector-tests", "RVV 指令测试生成器（可选）", "master", "未下载", "可选"],
            ["OpenXiangShan/bootcamp", "香山 bootcamp 教程（可选）", "master", "未下载", "可选"],
        ],
        widths=[4.0, 6.0, 2.4, 3.4, 2.6], font_size=7.8, first_col_bold=True)
    add_para(doc, "说明：XiangShanLab 与 XiangShan-doc 完整仓库包含大量图片/波形，体积较大（GitHub 标注约 951MB / 476MB）。"
                  "本资料夹已把其中的 Markdown 文本镜像到 repos/XiangShanLab-docs 与 repos/XiangShan-doc-docs，便于本地检索；"
                  "如需完整仓库，可在网络条件好时执行 docx/fetch_full_repos.sh（或手动 git clone）。", size=9, color=GRAY)

    add_heading(doc, "5.2 推荐学习路径", 2)
    add_table(doc,
        ["阶段", "内容", "入口", "预计时间"],
        [
            ["0. 入门", "跑通 Hello XiangShan：环境部署、编译仿真器、运行程序、DiffTest", "XiangShanLab 课程第 1 章", "1 天"],
            ["1. Chisel", "Chisel 基础、 Diplomacy、TileLink、AXI；能写简单 RTL", "课程第 2 章 + 编程实践", "约 5 天"],
            ["2. RISC-V 规范", "RVV 向量扩展、指令编码、CSR（vtype/vl/vstart）", "课程第 3 章 + RVV 规范", "约 3 天（按需）"],
            ["3. 微架构", "超标量、乱序执行、前端/后端/访存子系统", "课程第 4 章", "按需"],
            ["4. 场景分析", "指令生命周期、向量加法/向量浮点加法、预取、重放", "课程第 5 章（本赛题重点）", "重点"],
            ["5. 调试", "Bug 分析、波形、Difftest、CSR/PMA/PMP", "课程第 6 章", "按需"],
            ["6. AI 方向", "点积、Attention、KV Cache、量化、RISC-V NPU", "课程第 8 章（本赛题背景）", "按需"],
        ],
        widths=[2.4, 8.6, 4.0, 1.8], font_size=8.5, first_col_bold=True)

    add_heading(doc, "5.3 本赛题最相关的文档", 2)
    add_table(doc,
        ["文档", "为什么相关", "路径 / 链接"],
        [
            ["第 1 章：香山开发环境总述", "环境部署、Hello XiangShan、DiffTest 注入错误示例，直接对应阶段一",
             "repos/XiangShanLab-docs/xiangshan-course/docs/1-xiangshan-development-environment/Chapter_1_Overview_of_the_Xiangshan_Development_Environment.md"],
            ["Hello XiangShan 作业题与提交指南", "题库中的 Hello 任务 + GitHub Issue/邮件提交流程；可用于环境自检（CIE 参赛材料仍按官网要求提交）",
             "repos/XiangShanLab-docs/xiangshan-question-bank/1-xiangshan-development/hello-xiangshan.md；repos/XiangShanLab-docs/XiangShanLab-user-guide/how-to-commit-hello-xiangshan.md"],
            ["向量浮点加法指令的执行过程", "744 行，含测试程序、反汇编、波形逐级分析；是阶段一“向量加法执行过程文档”的最佳范本",
             "repos/XiangShanLab-docs/xiangshan-course/docs/5-xiangshan-scenarios-analysis/instructions-lifecycle/vector-float-add/simple-execution-process-of-a-vfadd-instruction.md"],
            ["vector-alu.md", "向量 ALU 执行过程提纲（decode、vsetvl rename、ROB 压缩）",
             "repos/XiangShanLab-docs/xiangshan-course/docs/5-xiangshan-scenarios-analysis/instructions-lifecycle/vector-add/vector-alu.md"],
            ["RVV 规范", "vdot 语义、SEW/VLEN/LMUL、vstart/vm 等",
             "repos/XiangShanLab-docs/xiangshan-course/docs/3-riscv-specification/unprivileged-spec/9-vector-operation/1-rvv.md"],
            ["香山入门指南（六）向量", "以昆明湖 V2（commit 6318236）为例讲向量访存与 RVV",
             "https://github.com/OpenXiangShan/XiangShan-doc/blob/master/docs/blog/posts/beginner-guide-2025/6-vector.md"],
            ["XiangShan 官方文档", "环境、工具、微架构、开发流程",
             "https://docs.xiangshan.cc/zh-cn/latest/"],
            ["RVV 测试生成器", "可生成 RVV 指令测试，用于自测（可选）",
             "https://github.com/OpenXiangShan/riscv-vector-tests"],
        ],
        widths=[4.0, 6.0, 6.6], font_size=8.0, first_col_bold=True)

    add_heading(doc, "5.4 官方备赛指南（视频 / 公众号 / 微博）", 2)
    add_para(doc, "第二届备赛指南合集（官网文章 id=45）汇总了公众号、微博、B 站三套链接。与香山赛道直接相关的是“备赛指南三”。",
             indent=0.74)
    add_table(doc,
        ["渠道", "内容", "链接"],
        [
            ["B 站", "【赛题讲解】备赛指南三 - 香山赛道（717 秒）", "https://www.bilibili.com/video/BV1G3gH6rE3a"],
            ["微信公众号", "【赛题讲解】备赛指南三 - 香山赛道", "https://mp.weixin.qq.com/s/BGVx9dZtAKZC4bMyYH_GZA"],
            ["微博", "【赛题讲解】备赛指南三 - 香山赛道", "https://weibo.com/7480746650/R9rNUpuej"],
            ["B 站", "备赛指南一：RISC-V 与开源芯片发展新趋势", "https://www.bilibili.com/video/BV1w1gE6DE6J"],
            ["B 站", "备赛指南二：大赛总体情况介绍", "https://www.bilibili.com/video/BV1srgE6WEzT"],
            ["B 站", "备赛指南四：中兴&砺睿微赛道", "https://www.bilibili.com/video/BV1MBgn6PE87"],
            ["B 站", "备赛指南五：玄铁赛道", "https://www.bilibili.com/video/BV1Tzgn6YEs3"],
            ["B 站", "备赛指南六：进迭时空赛道", "https://www.bilibili.com/video/BV1G8gn6zEeU"],
        ],
        widths=[2.4, 7.4, 6.8], font_size=8.5, first_col_bold=True)
    add_para(doc, "本资料夹已下载备赛指南三的视频（480P，约 17MB）到 attachments/香山赛道备赛指南三-BV1G3gH6rE3a.mp4，"
                  "并抽取了关键帧到 attachments/frames/。", size=9, color=GRAY)


    # ================= 6. 技术路线 =================
    add_heading(doc, "6. 技术实施路线（建议）", 1)
    add_para(doc, "以下路线基于香山昆明湖 V2 当前源码（kunminghu-v2 分支，commit a4eeaabb，2026-10-22）整理，"
                  "用于快速定位改动点；具体实现以你的设计和评审要求为准。", indent=0.74)

    add_heading(doc, "6.1 阶段一：环境与向量加法波形", 2)
    add_number(doc, "克隆并部署 xs-env：git clone https://github.com/OpenXiangShan/xs-env.git；cd xs-env；"
                    "sudo -s ./setup-tools.sh；source setup.sh；source env.sh。")
    add_number(doc, "准备 XiangShan：将 NOOP_HOME 指向 kunminghu-v2 的 XiangShan 仓库；make init；"
                    "make emu CONFIG=MinimalConfig EMU_TRACE=1 -j$(nproc)。首次编译约 1 小时，取决于机器性能。")
    add_number(doc, "编译 Hello 程序：cd $AM_HOME/apps/hello；make ARCH=riscv64-xs；修改打印内容为 "
                    "hello xiangshan, I am <团队标识>, <本机 IP>。")
    add_number(doc, "运行并留证：./build/emu -i $AM_HOME/apps/hello/build/hello-riscv64-xs.bin --no-diff；"
                    "再用 --diff ready-to-run/riscv64-nemu-interpreter-so 跑一遍，保存完整终端日志。")
    add_number(doc, "写一个向量加法程序（vsetivli + vle32.v + vadd.vv + vse32.v），编译并在香山仿真中运行；"
                    "打开 VCD/FST 波形，按“取指 → 译码 → 重命名 → 派发 → 发射 → 执行 → 写回”逐级截图。")
    add_number(doc, "参考课程中的 vfadd 文档（744 行）组织阶段一文档：指令选择、反汇编、全流程概括、逐级波形、结论。")
    add_para(doc, "阶段一交付物检查：1.1 运行输出（含团队标识和 IP）；1.2 完整操作日志；1.3 向量加法执行过程文档（含波形截图与文字说明）。",
             bold=True, size=9.5)

    add_heading(doc, "6.2 阶段二：vdot.vv 的 RTL 实现", 2)
    add_para(doc, "建议按“指令编码 → 译码 → 功能单元 → 数据通路 → 测试”的顺序推进。关键源码位置如下：", indent=0.74)
    add_table(doc,
        ["层次", "文件", "你要做的事"],
        [
            ["指令编码", "src/main/scala/xiangshan/backend/decode/Instructions.scala", "新增 vdot.vv 的 32 位编码（opcode/funct3/funct6），避开现有 RVV 指令"],
            ["向量译码", "src/main/scala/xiangshan/backend/decode/VecDecoder.scala", "新增译码表项，映射到 FuType.vimac（或新增 FuType.vdot）与对应 fuOpType"],
            ["FU 类型", "src/main/scala/xiangshan/backend/fu/FuType.scala", "如需新 FU，新增类型并加入 vecOPI/vecArith 序列"],
            ["FU 配置", "src/main/scala/xiangshan/backend/fu/FuConfig.scala", "配置 latency、dataBits、读端口、issue 队列等"],
            ["执行单元", "src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala", "复用 VIMac64b 的乘法/累加能力，或新增 VDotU wrapper"],
            ["向量库", "repos/YunSuan/src/main/scala/yunsuan/vector/vectorIMAC/", "在 VIMac64b 中支持 8×int8 → int32 点积；新增 VimacType 操作码"],
            ["数据拆分", "backend/fu/vector/utils/VecDataSplitModule.scala", "把 128 位向量拆成 8 个 int8 通道，送入乘法器"],
            ["流水线", "backend/fu/vector/VecPipedFuncUnit.scala / VecNonPipedFuncUnit.scala", "选择流水/非流水实现；注意 latency 与 bypass"],
            ["测试", "nexus-am apps + XiangShan 仿真", "正数、负数、边界值三组测试；用 --diff 与 NEMU 对比"],
        ],
        widths=[2.4, 7.6, 6.6], font_size=7.8, first_col_bold=True)

    add_para(doc, "实现提示：", bold=True, space_before=6)
    add_bullet(doc, "香山现有向量归约指令（如 vredsum.vs）走 FuType.vipu + VipuType.vredsum_vs，可作为“结果写 vd[0]”的参考路径；"
                    "向量乘加（vmacc/vmul）走 FuType.vimac + VimacType，可作为“8 个 int8 乘加”的参考路径。两条路径都可以复用。")
    add_bullet(doc, "若复用 VIMac64b：它按 64 位 lane 工作，需要把 8 个 int8 打包进 lane，做符号扩展后相乘并累加；"
                    "注意 8 位乘法的符号扩展、32 位累加位宽、以及结果只写 vd[0] 的约束。")
    add_bullet(doc, "若新增专用 VDotU：8 个乘法器 + 加法树，面积小、延迟低；可用 VecPipedFuncUnit 做 2–3 级流水，"
                    "并在 FuConfig 中声明 latency。")
    add_bullet(doc, "无论哪种方案，都要在设计中明确：vl 的处理、vstart 的处理、vm 掩码、tail 元素清零、SEW/VLEN 参数化。")
    add_bullet(doc, "测试程序建议用内联汇编构造输入，C 代码计算参考结果，打印 vdot 结果与期望值；"
                    "边界值覆盖 int8 的 -128、127、0，以及累加溢出（8×127×127=129032，超过 int16，验证 32 位累加）。")

    add_heading(doc, "6.3 阶段三：NEMU 扩展、协同仿真与性能分析", 2)
    add_table(doc,
        ["任务", "文件 / 工具", "要点"],
        [
            ["NEMU 译码", "NEMU/src/isa/riscv64/instr/rvv/decode.h", "用 def_INSTR_TAB 增加 vdot.vv 的匹配模式；确保与 RTL 编码一致"],
            ["NEMU 执行", "NEMU/src/isa/riscv64/instr/rvv/vcompute.h + vcompute_impl.c", "在 vcompute.h 增加 def_EHelper(vdot)，在 vcompute_impl.c 复用/新增 8 个 int8 符号扩展乘加宏；写 vd[0]，其余清零"],
            ["NEMU 挂接", "NEMU/src/isa/riscv64/instr/rvv/decode.h + vreg.h", "decode.h 增加匹配模式；确认向量寄存器写回、vstart/vl 处理"],
            ["协同仿真", "XiangShan --diff + 新 NEMU 参考库", "编译 NEMU 为 riscv64-nemu-interpreter-so，替换 ready-to-run 中的参考库"],
            ["基线", "RVV 组合指令", "用 vwmul.vv + vwredsum.vs（或 vmul + vredsum）实现等价功能；注意 8 位溢出，优先用 widening"],
            ["性能分析", "波形 / 性能计数器 / perf", "测 latency（每条 vdot 的周期数）、throughput（每 N 周期一条）、加速比"],
        ],
        widths=[2.8, 6.8, 7.0], font_size=8.0, first_col_bold=True)

    add_para(doc, "基线实现建议：", bold=True, space_before=6)
    add_bullet(doc, "基线 A（推荐）：vle8.v 加载两个 8 元素向量 → vwmul.vv 做 8→16 位宽乘法 → vwredsum.vs 做宽化归约 → 结果写标量/向量；"
                    "功能正确，且全部是现有 RVV 指令。")
    add_bullet(doc, "基线 B：vmul.vv + vredsum.vs，但 8 位乘法和累加会溢出，必须证明输入范围不会溢出，或在报告中说明局限。")
    add_bullet(doc, "基线 C：标量 8 次乘加，作为“无向量加速”的对照，用来说明向量化本身的收益。")
    add_para(doc, "性能指标建议：", bold=True)
    add_bullet(doc, "latency：从指令发射到写回 vd[0] 的周期数；分别统计 vdot 与 baseline 的关键路径。")
    add_bullet(doc, "throughput：连续发射相同指令时的平均间隔（CPI）；可用循环跑 1000 次取平均。")
    add_bullet(doc, "加速比：speedup = baseline_latency / vdot_latency；同时给出面积/资源占用的定性分析。")
    add_bullet(doc, "如果条件允许，用 XiangShan 的性能计数器或 perf 采集指令数、周期数、停顿原因，支撑“瓶颈在哪”的判断。")

    add_heading(doc, "6.4 交付物检查清单", 2)
    add_table(doc,
        ["阶段", "交付物", "是否有", "证据 / 备注"],
        [
            ["阶段一", "1.1 hello xiangshan, I am xxx, IP address 运行输出", "☐", "终端截图 + 文本日志"],
            ["阶段一", "1.2 完整环境部署与操作日志", "☐", "命令、版本、报错与解决过程"],
            ["阶段一", "1.3 向量加法指令执行过程文档", "☐", "波形截图 + 逐级说明"],
            ["阶段二", "2.1 vdot.vv 设计文档", "☐", "语义、微架构、数据通路、时序"],
            ["阶段二", "2.2 vdot.vv RTL 实现", "☐", "Chisel/Verilog 代码 + commit hash"],
            ["阶段二", "2.3.1 正数点积测试", "☐", "输入/输出/期望值/通过"],
            ["阶段二", "2.3.2 负数点积测试", "☐", "含负数输入"],
            ["阶段二", "2.3.3 边界值测试", "☐", "-128/127/0/溢出"],
            ["阶段三", "3.1.1 NEMU vdot 扩展", "☐", "decode/exec 代码 + 编译说明"],
            ["阶段三", "3.1.2 NEMU 与 RTL 协同仿真", "☐", "--diff 通过日志"],
            ["阶段三", "3.2 基线功能实现", "☐", "RVV 组合指令代码"],
            ["阶段三", "3.3 延迟加速分析报告", "☐", "latency/throughput/加速比"],
            ["通用", "GitHub 代码仓库", "☐", "public 仓库地址"],
            ["通用", "XiangShanLab 加密提交", "☐", "submission.asc + PR"],
            ["通用", "选拔赛/总决赛 PPT", "☐", "解题思路、波形、数据"],
        ],
        widths=[1.8, 7.0, 1.4, 6.4], font_size=8.2, first_col_bold=True)

    add_heading(doc, "6.5 距报名截止 10 天的冲刺排期（建议）", 2)
    add_para(doc, "假设从 2026-10-29 开始，目标是 11-08 前完成官网报名并提交一版可评审材料。实际排期按团队人数和基础调整。",
             indent=0.74)
    add_table(doc,
        ["日期", "任务", "产出"],
        [
            ["10-29（周四）", "官网注册/登录、创建团队、选择香山赛道并报名；加入咨询群", "报名成功截图、团队信息"],
            ["10-30（周五）", "部署 xs-env + 编译 XiangShan 仿真器（可夜间跑）；跑通 Hello XiangShan", "环境日志、Hello 输出"],
            ["10-31（周六）", "写向量加法测试程序；跑仿真、抓波形；整理阶段一文档", "阶段一 1.1/1.2/1.3 初稿"],
            ["11-01（周日）", "确定 vdot 实现方案（复用 VIMac64b / 新增 VDotU）；写设计文档大纲", "设计文档 v0.1、模块框图"],
            ["11-02（周一）", "指令编码 + 译码 + FU 配置；跑通空实现/直通", "RTL 骨架、编译通过"],
            ["11-03（周二）", "实现 8×int8 乘法 + 32 位累加；写正数测试", "正数测试通过"],
            ["11-04（周三）", "补负数、边界值测试；修 bug；录阶段二讲解视频", "三项测试报告、视频"],
            ["11-05（周四）", "NEMU 增加 vdot 译码/执行；编译参考库；跑 --diff", "协同仿真通过"],
            ["11-06（周五）", "用 vwmul+vwredsum 写基线；采集 latency/throughput", "基线代码、原始数据"],
            ["11-07（周六）", "写阶段三报告；整理代码仓库、README、复现命令；录波形分析视频", "报告、视频、仓库"],
            ["11-08（周日）", "官网提交文档/视频/仓库；XiangShanLab 加密提交 + PR；检查清单逐项打勾", "全部提交完成"],
        ],
        widths=[2.8, 9.6, 4.2], font_size=8.2, first_col_bold=True)
    add_para(doc, "提示：编译 XiangShan 仿真器可能耗时 1 小时以上，建议第一晚就启动；测试与波形分析可以和编译并行准备。"
                  "如果时间不足，优先保证阶段一完整 + 阶段二可跑通 + 阶段三有最小闭环（NEMU + 一个基线 + 一组延迟数据）。",
             size=9.5, color=GRAY)


    # ================= 7. 官方原文与链接 =================
    add_heading(doc, "7. 官方原文与链接", 1)
    add_heading(doc, "7.1 官网文章", 2)
    add_table(doc,
        ["ID", "标题", "与本赛道的关系", "链接"],
        [
            ["38", "【开赛啦】第二届RISC-V高水平大赛开始报名！", "大赛通知全文：组织机构、赛道、赛程、奖励、联系方式", "https://rv.cie.org.cn/look/details?id=38"],
            ["41", "【赛题讲解】第二届RISC-V高水平大赛备赛指南三", "香山赛道赛题讲解（视频）", "https://rv.cie.org.cn/look/details?id=41"],
            ["45", "CIE全国RISC-V高水平创新及应用大赛（第二届）备赛指南合集", "公众号/微博/B站全部备赛链接", "https://rv.cie.org.cn/look/details?id=45"],
            ["39", "【趋势研判】备赛指南一", "RISC-V 与开源芯片发展趋势", "https://rv.cie.org.cn/look/details?id=39"],
            ["40", "【赛事攻略】备赛指南二", "大赛总体情况介绍", "https://rv.cie.org.cn/look/details?id=40"],
            ["42", "【赛题讲解】备赛指南四", "中兴&砺睿微赛道", "https://rv.cie.org.cn/look/details?id=42"],
            ["43", "【赛题讲解】备赛指南五", "玄铁赛道", "https://rv.cie.org.cn/look/details?id=43"],
            ["44", "【赛题讲解】备赛指南六", "进迭时空赛道", "https://rv.cie.org.cn/look/details?id=44"],
            ["33/35", "第一届总决赛圆满完成 / 大赛圆满收官", "第一届赛事背景与规模", "https://rv.cie.org.cn/look/details?id=35"],
            ["36", "第一届总决赛优胜奖名单和专项奖名单", "第一届获奖项目参考", "https://rv.cie.org.cn/look/details?id=36"],
            ["37", "关于第二届大赛建议", "官方问卷", "https://rv.cie.org.cn/look/details?id=37"],
        ],
        widths=[1.2, 6.4, 5.0, 4.0], font_size=7.6)

    add_heading(doc, "7.2 官网 API（公开、无需登录）", 2)
    add_para(doc, "官网是 Vue SPA，前端通过 https://api.rv.cie.org.cn/api/ 取数。公开接口需要带请求头 server: 1。", indent=0.74)
    add_table(doc,
        ["接口", "用途"],
        [
            ["GET /api/home/index", "首页：赛程 flow、赛事说明 contest、赛道 catetory、奖励、联系方式"],
            ["GET /api/race/detail?id=8", "香山赛道详情：名称、介绍、命题方、报名时间、报名团队数"],
            ["GET /api/subject/index?race_id=8", "香山赛道赛题列表与详情：intro、detail、submit_content、rule_content、team_demand 等"],
            ["GET /api/help/index", "常见问题 + 选手指南（报名、组队、提交、证书）"],
            ["GET /api/article/detail?id=38", "文章详情（替换 id 可读取其他文章）"],
            ["GET /api/category/index?type=article", "文章分类：新闻动态、赛事公告、赛事公示"],
        ],
        widths=[6.0, 10.6], font_size=8.5)

    add_heading(doc, "7.3 官方 PDF 与图片", 2)
    add_bullet(doc, "【盖章版】关于举办第二届 CIE 全国 RISC-V 高水平创新及应用大赛通知.pdf（attachments/notice.pdf，8 页扫描件）")
    add_bullet(doc, "大赛整体情况、报名规则等.pdf（attachments/guide.pdf，6 页，含参赛条件、赛程、奖励）")
    add_bullet(doc, "vdot_vv 参考语义图（attachments/vdot_semantics.png）")
    add_bullet(doc, "香山赛道咨询群二维码（attachments/xiangshan_group.jpg）")
    add_bullet(doc, "香山赛道咨询群海报（attachments/xiangshan_group.jpg，与上方二维码为同一文件）")

    add_heading(doc, "7.4 香山社区仓库中的赛题资料", 2)
    add_bullet(doc, "赛题 README：https://github.com/OpenXiangShan/XiangShanLab/blob/master/2026-CIE-RISC-V-Contest-Application-Track/README.md")
    add_bullet(doc, "提交指南：https://github.com/OpenXiangShan/XiangShanLab/blob/master/2026-CIE-RISC-V-Contest-Application-Track/SUBMISSION_GUIDE.md")
    add_bullet(doc, "提交脚本：https://github.com/OpenXiangShan/XiangShanLab/blob/master/2026-CIE-RISC-V-Contest-Application-Track/submit.sh")
    add_bullet(doc, "评审公钥：https://github.com/OpenXiangShan/XiangShanLab/blob/master/2026-CIE-RISC-V-Contest-Application-Track/contest/public-key.asc")
    add_bullet(doc, "提交区示例：01_参赛选手提交区/Test_Team/submission.asc、01_参赛选手提交区/零一/submission.asc")


    # ================= 8. 本地资料清单 =================
    add_heading(doc, "8. 本地资料清单与使用说明", 1)
    add_heading(doc, "8.1 docx/ 目录", 2)
    add_code_block(doc,
"""docx/
├── CIE-香山赛道-参赛资料汇总.docx      # 本文件
├── build_doc.py                        # 生成脚本（可重新运行）
├── fetch_full_repos.sh                 # 可选：下载完整版 XiangShanLab / XiangShan-doc
├── README.md                           # 资料夹导航
├── 01-官方通知与规则.md
├── 02-赛题与评分细则.md
├── 03-提交操作指南.md
├── 04-备赛学习路径.md
├── 05-FAQ与参赛规则.md
├── attachments/
│   ├── notice.pdf                      # 盖章版大赛通知（扫描件）
│   ├── guide.pdf                       # 大赛整体情况与报名规则
│   ├── vdot_semantics.png              # vdot.vv 参考语义
│   ├── xiangshan_group.jpg             # 香山赛道咨询群二维码/海报
│   ├── 香山赛道备赛指南三-BV1G3gH6rE3a.mp4
│   ├── frames/                         # 视频关键帧与联系表
│   └── course/vector-fadd-inst.zip     # 向量浮点加法波形样例
└── data/
    ├── home.json                       # 官网首页 API 原始数据
    ├── race8.json                      # 香山赛道详情
    ├── subjects8.json                  # 赛题详情（含评分规则）
    └── help.json                       # FAQ 与选手指南""")

    add_heading(doc, "8.2 repos/ 目录", 2)
    add_table(doc,
        ["目录", "内容", "说明"],
        [
            ["repos/XiangShan", "香山 RTL（kunminghu-v2）", "含子模块：difftest、ready-to-run、rocket-chip、huancun、fudian、utility、yunsuan、coupledL2、openLLC、ChiselAIA、ChiselIOPMP"],
            ["repos/xs-env", "开发环境脚本", "setup-tools.sh / setup.sh / env.sh；子模块可按需初始化"],
            ["repos/NEMU", "RISC-V 模拟器", "第三阶段扩展 vdot"],
            ["repos/YunSuan", "向量 ALU/MAC 库", "VIMac64b 等实现"],
            ["repos/XiangShanLab-docs", "XiangShanLab 的 Markdown 文本镜像", "课程、题库、赛题目录、工具说明；图片/波形未镜像"],
            ["repos/XiangShan-doc-docs", "XiangShan-doc 的 Markdown 文本镜像", "设计文档、博客；图片未镜像"],
        ],
        widths=[4.4, 6.2, 6.0], font_size=8.5, first_col_bold=True)

    add_heading(doc, "8.3 建议的下一步", 2)
    add_number(doc, "先在官网完成注册/登录，创建团队，选择 CIE-香山社区赛道并报名（截止 11-08）。")
    add_number(doc, "按第 6.1 节跑通 Hello XiangShan，保存环境日志和向量加法波形——先把阶段一 15 分拿到。")
    add_number(doc, "按第 6.2 节选定实现方案（复用 VIMac64b 或新增 VDotU），写设计文档并开始 RTL。")
    add_number(doc, "按第 6.3 节扩展 NEMU、建立基线、采集延迟数据——阶段三 25 分是拉开差距的关键。")
    add_number(doc, "所有材料按第 6.4 节清单逐项打勾；代码仓库、XiangShanLab 加密提交、官网系统三条链路都要完成。")
    add_number(doc, "加入香山赛道咨询群，关注官网“新闻动态”和“赛事公告”，以官方最新通知为准。")

    add_para(doc, "", space_after=8)
    add_callout(doc, "免责声明",
        "本资料由公开网页与官方仓库整理，力求准确，但不排除官网后续更新导致差异。\n"
        "所有时间、规则、评分、奖金、提交要求，最终以 CIE 全国 RISC-V 高水平创新及应用大赛官网和组委会通知为准。\n"
        "资料采集日期：2026-10-29。",
        bg="F2F2F2", border="808080")

    # 保存
    doc.core_properties.title = "CIE 2026 香山赛道参赛资料汇总"
    doc.core_properties.subject = "CIE-香山社区 RISC-V 应用创新赛道 · vdot.vv 赛题"
    doc.core_properties.author = "资料整理"
    doc.core_properties.keywords = "RISC-V, 香山, 昆明湖 V2, vdot, CIE, 2026"
    doc.core_properties.comments = "信息采集自 rv.cie.org.cn 与 OpenXiangShan 官方仓库，最终以官网为准。"
    doc.save(OUT)
    print("saved:", OUT)


if __name__ == "__main__":
    build()
