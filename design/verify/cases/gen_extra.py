#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_extra.py — 生成 `manifest.extra.tsv` 的扩容用例（C 源 + 期望值）。

定位（与 `gen.py` 的分工，两者互不替代）：
  * `gen.py`      → 30 例主清单 `manifest.tsv`（sha256 a90d1071…，内容固定），本文件**不碰**；
  * `gen_extra.py`→ 扩容清单 `manifest.extra.tsv`（单列独立作业 94-run-extra.sh）。

硬约束：
  1. 期望值**全部**由 `design/verify/vdot_model.py` 金模型生成：每一条 `vdot` 期望都调用
     `M.vdot_vv(vs1_reg, vs2_reg)` 得到完整 128 位 vd，再取低 32 位作断言常量；本文件里
     没有任何手写的点积结果、也没有第二套点积实现（`vadd`/`vmacc` 只用来占写回端口，
     它们的结果**不被本用例断言**，正确性由 difftest 逐指令比对兜底）。
  2. 三类配额：重叠 `vdot-ov` ≥24、流水 `vdot-pl` ≥40、异常 `negative` ≥32；见 `CLASS_QUOTA`，
     生成结束自检并打印实测行数。
  3. G0 反例不可省：`g0` 类用例的期望值**故意错 1 bit**，靠自检串 `CASE <cid>: MISMATCH`
     被同一套自检判为失败（防止虚假通过，ALGORITHM §3.1）。

语义口径（SPEC §1.1/§1.2，与 `vdot_model.py` 同源，不另立）：
  S = Σ_{i=0..7} sext8(vs1[i]) × sext8(vs2[i])；vd[31:0] = sext32(S)；vd[127:32] = 0；
  lane 8..15 不参与（所有用例都把 lane 8..15 填成非零干扰值，误用高位会明显偏离）。

复现：
    python3 design/verify/cases/gen_extra.py            # 重新生成 extra/*.c 与本文件统计
    python3 design/verify/cases/gen_extra.py --check    # 只打印分类行数（不写文件）

生成物：
    design/verify/cases/extra/<cid>.c        每行清单一个独立镜像源
    design/verify/cases/extra/spec.extra.json 机器可读的用例规格（供 extra_crosscheck.py 对拍）
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY = os.path.dirname(HERE)                      # design/verify
MODEL_PATH = os.path.join(VERIFY, "vdot_model.py")
OUT_DIR = os.path.join(HERE, "extra")
MANIFEST = os.path.join(HERE, "manifest.extra.tsv")


def load_model():
    spec = importlib.util.spec_from_file_location("vdot_model", MODEL_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


M = load_model()

# 分类配额（重叠 ≥24 / 流水 ≥40 / 异常 ≥32 / 总行 ≥96）
CLASS_QUOTA = {
    "vdot-ov": 24,
    "vdot-pl": 40,
    "negative": 32,
}
MIN_ROWS = 96
# 「基础」7 行对齐竞品标尺的 7 例基础；rand10k 是独立随机大类
BASE_ROWS = 7


def to_int8(v):
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def reg128(lanes):
    """16 个 int8 lane → 128 位寄存器值（小端，lane i = bits [8i+7:8i]）。"""
    v = 0
    for i, b in enumerate(lanes):
        v |= (b & 0xFF) << (8 * i)
    return v


# ---------------------------------------------------------------------------
# 操作数数据表：每项 16 个 int8，lane 8..15 一律非零（干扰位，SPEC §1.1：不参与）
# ---------------------------------------------------------------------------
ARR = {
    # 正数定向
    "A_pos": [3, -5, 7, -9, 11, -13, 17, -19, 21, -23, 25, -27, 29, -31, 33, -35],
    "B_pos": [-2, 4, -6, 8, -10, 12, -14, 16, -18, 20, -22, 24, -26, 28, -30, 32],
    # 全负积
    "A_neg": [-1, -2, -3, -4, -5, -6, -7, -8, 9, 10, 11, 12, 13, 14, 15, 16],
    "B_one": [1, 1, 1, 1, 1, 1, 1, 1, -17, 18, -19, 20, -21, 22, -23, 24],
    # 奇数个负积（抓符号扩展）
    "A_mix": [-7, -7, -7, 5, 5, 5, 5, 5, 127, -128, 1, -1, 5, -5, 100, -100],
    "B_three": [3, 3, 3, 3, 3, 3, 3, 3, -1, 2, -3, 4, -5, 6, -7, 8],
    # 上/下边界
    "A_max": [127] * 8 + [-128, 127, -128, 127, -128, 127, -128, 127],
    "B_max": [127] * 8 + [127, -128, 127, -128, 127, -128, 127, -128],
    "A_min": [-128] * 8 + [127, -128, 127, -128, 127, -128, 127, -128],
    "B_min": [-128] * 8 + [-128, 127, -128, 127, -128, 127, -128, 127],
    # 一侧全零
    "A_zero": [0] * 8 + [1, -1, 2, -2, 3, -3, 4, -4],
    "B_ext": [127, -128, 1, -1, 5, -5, 100, -100, 1, 2, 3, 4, 5, 6, 7, 8],
    # 交错极值
    "A_ext": [-128, 127, -128, 127, -128, 127, -128, 127, 15, 16, 17, 18, 19, 20, 21, 22],
    "B_ext2": [127, -128, 127, -128, 127, -128, 127, -128, 23, 24, 25, 26, 27, 28, 29, 30],
    # 量级不对称
    "A_asym": [1, 2, 3, 4, 5, 6, 7, 8, 31, 32, 33, 34, 35, 36, 37, 38],
    "B_asym": [100, -100, 50, -50, 25, -25, 12, -12, 39, 40, 41, 42, 43, 44, 45, 46],
    # 高位干扰必须被忽略（lane 8..15 全极值）
    "A_lanehi": [1, 1, 1, 1, 1, 1, 1, 1, -128, -128, -128, -128, -128, -128, -128, -128],
    "B_lanehi": [2, 2, 2, 2, 2, 2, 2, 2, 127, 127, 127, 127, 127, 127, 127, 127],
    # 固定种子伪随机对（*_rand 与 vdot_rand10k 无关，两组独立数据）
    "A_rand": [-93, 27, -14, 109, -55, 7, -120, 66, 88, -101, 43, -8, 119, -37, 5, -73],
    "B_rand": [64, -111, 38, -7, 92, -48, 13, -125, -29, 57, -96, 21, -66, 103, -4, 61],
}

# 重叠套件用的 10 组数据模式（正 / 负 / 奇数负 / 边界 / 极值 / 零 / 交错 / 不对称 / 高位干扰 / 随机）
OV_PATTERNS = [
    ("pos", "A_pos", "B_pos"),
    ("neg", "A_neg", "B_one"),
    ("mixodd", "A_mix", "B_three"),
    ("bmax", "A_max", "B_max"),
    ("bmin", "A_min", "B_min"),
    ("zero", "A_zero", "B_ext"),
    ("ext", "A_ext", "B_ext2"),
    ("asym", "A_asym", "B_asym"),
    ("lanehi", "A_lanehi", "B_lanehi"),
    ("rand", "A_rand", "B_rand"),
]


# ---------------------------------------------------------------------------
# 编码器（**不复用** model.encode_vdot_vv 的实参顺序，以免同源错误；
# 但生成后会由 extra_crosscheck.py 用 model.decode_vdot_vv() 反解校验）
# ---------------------------------------------------------------------------
def enc_vdot(vd, vs1, vs2):
    """vdot.vv：funct6=001110, vm=1, funct3=010(OPMVV), opcode=1010111。"""
    return ((0x0E << 26) | (1 << 25) | (vs2 << 20) | (vs1 << 15) | (2 << 12) | (vd << 7) | 0x57)


def enc_vadd(vd, vs1, vs2):
    """vadd.vv：funct6=000000, vm=1, funct3=000(OPIVV), opcode=1010111。"""
    return ((0x00 << 26) | (1 << 25) | (vs2 << 20) | (vs1 << 15) | (0 << 12) | (vd << 7) | 0x57)


def enc_vmacc(vd, vs1, vs2):
    """vmacc.vv：funct6=101101, vm=1, funct3=010(OPMVV), opcode=1010111。"""
    return ((0x2D << 26) | (1 << 25) | (vs2 << 20) | (vs1 << 15) | (2 << 12) | (vd << 7) | 0x57)


# ---------------------------------------------------------------------------
# 用例规格
# ---------------------------------------------------------------------------
CASES = []


def add(cid, cls, family, note, ops, g0_bit=None):
    CASES.append({
        "cid": cid,
        "cls": cls,
        "family": family,
        "note": note,
        "ops": ops,
        "g0_bit": g0_bit,
    })


def L(vd, arr):
    return {"op": "load", "vd": vd, "arr": arr}


def VMV(vd, imm):
    return {"op": "vmv", "vd": vd, "imm": imm & 0xFF}


def VD(vd, vs1, vs2):
    return {"op": "vdot", "vd": vd, "vs1": vs1, "vs2": vs2}


def VA(vd, vs1, vs2):
    return {"op": "vadd", "vd": vd, "vs1": vs1, "vs2": vs2}


def VM(vd, vs1, vs2):
    return {"op": "vmacc", "vd": vd, "vs1": vs1, "vs2": vs2}


def NOP(n):
    return {"op": "nop", "n": n}


def SETVL(n):
    return {"op": "vl", "n": n}


def SETVT(n):
    return {"op": "vtype", "n": n}


def RSV(n):
    return {"op": "rs_vstart", "n": n}


def CLRV():
    return {"op": "clr_vstart"}


def VSOFF():
    return {"op": "vs_off"}


def VSON():
    return {"op": "vs_on"}


def JAL():
    return {"op": "jalover"}


def VDS(vd, vs1, vs2):
    """被 taken jal 跳过的 vdot：真实发射进镜像，但金模型按「不执行」推进（取消/重定向专项）。"""
    return {"op": "vdot_skipped", "vd": vd, "vs1": vs1, "vs2": vs2}


def RD(vd, hi=True):
    return {"op": "read", "vd": vd, "hi": hi}


# ---------------------------------------------------------------------------
# ① 基础 7 行（对齐竞品标尺的「7 基础」）
# ---------------------------------------------------------------------------
add("xb_pos_lanehi", "vdot-base", "base", "正数点积 + lane8..15 极值干扰必须不参与",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), RD(3)])
add("xb_neg_all", "vdot-base", "base", "全负积（符号扩展）",
    [L(1, "A_neg"), L(2, "B_one"), VD(3, 1, 2), RD(3)])
add("xb_bound_max", "vdot-base", "base", "上边界 S=8*127*127=129032",
    [L(1, "A_max"), L(2, "B_max"), VD(3, 1, 2), RD(3)])
add("xb_bound_min", "vdot-base", "base", "下边界 S=8*(-128)*(-128)=131072（19 位累加器上界）",
    [L(1, "A_min"), L(2, "B_min"), VD(3, 1, 2), RD(3)])

_ops_vl = [L(1, "A_mix"), L(2, "B_three")]
for _vl in range(0, 9):
    _ops_vl += [SETVL(_vl), VD(3, 1, 2), RD(3)]
add("xb_vl_sweep", "vdot-base", "base", "vl=0..8 全扫：结果与 vl 无关且全写 vd（SPEC §1.1 有意偏离）", _ops_vl)

_ops_vt = [L(1, "A_asym"), L(2, "B_asym")]
for _vt in (0x00, 0x40, 0x80, 0xC0):
    _ops_vt += [SETVT(_vt), VD(3, 1, 2), RD(3)]
add("xb_vta_vma", "vdot-base", "base", "vta/vma 四组合（0x00/0x40/0x80/0xC0）结果不变", _ops_vt)

add("xb_oldvd", "vdot-base", "base", "旧 vd 预填 0x5A 后执行：旧值不是语义输入",
    [VMV(3, 0x5A), L(1, "A_ext"), L(2, "B_ext2"), VD(3, 1, 2), RD(3)])

# ---------------------------------------------------------------------------
# ② 重叠套件 vdot-ov：3 类 × 10 数据模式 = 30 行（配额 ≥24）
#    语义对照 RISC-V 向量规范 vector-common.adoc（上游文档，非本仓文件）的
#    norm:vreg_overlap_rsv(:1037-1038) 与其引用的
#    norm:vreg_overlap_legal(:1013-1028)：LMUL=1 且目的 EEW ≥ 源 EEW ⇒ 最高编号寄存器相同
#    ⇒ vd==vs 属**合法**重叠（不是 reserved）；结论的仓库内依据见 design/SPEC.md §3.4.2。
# ---------------------------------------------------------------------------
OV_FORMS = [
    # (后缀, 说明, vd, vs1, vs2, 需要的 load 列表)
    ("vs2", "vs2=vd（vd 同时是源 vs2；操作数 B 先装入 vd）", 3, 1, 3),
    ("vs1", "vs1=vd（vd 同时是源 vs1；操作数 A 先装入 vd）", 3, 3, 2),
    ("v12", "vs1=vs2（同一源寄存器既是 vs1 又是 vs2；vd 独立，旧 vd 预填）", 3, 1, 1),
]
for _suf, _desc, _vd, _vs1, _vs2 in OV_FORMS:
    for _pat, _a, _b in OV_PATTERNS:
        _ops = [VMV(_vd, 0xAB)]
        if _suf == "vs2":
            _ops += [L(1, _a), L(_vd, _b)]
        elif _suf == "vs1":
            _ops += [L(_vd, _a), L(2, _b)]
        else:
            _ops += [L(1, _a)]
        _ops += [VD(_vd, _vs1, _vs2), RD(_vd)]
        add("xo_%s_%s" % (_suf, _pat), "vdot-ov", "overlap",
            "重叠 %s / 数据模式 %s" % (_desc, _pat), _ops)

# ---------------------------------------------------------------------------
# ③ 流水 / 依赖 / 取消 / 端口竞争 vdot-pl（配额 ≥40）
# ---------------------------------------------------------------------------
# 3.1 背靠背：k 条独立 vdot（不同 vd），全部读回
for _k in (2, 3, 4, 6, 8):
    _ops = [L(1, "A_pos"), L(2, "B_pos")]
    for _i in range(_k):
        _ops.append(VD(3 + _i, 1, 2))
    _ops += [RD(3 + _i) for _i in range(_k)]
    add("xp_bb%d" % _k, "vdot-pl", "back2back", "%d 条背靠背独立 vdot（0 bubble，不同 vd）" % _k, _ops)

# 3.2 插 bubble：同 vd 两条不同操作数的 vdot 之间插 k 个 nop
for _k in (1, 2, 3, 5, 7):
    add("xp_bub%d" % _k, "vdot-pl", "bubble",
        "同 vd 两条 vdot 之间插 %d 个 nop（终值必须是后者）" % _k,
        [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
         VD(3, 1, 2), NOP(_k), VD(3, 4, 5), RD(3)])

# 3.3 依赖链：同 vd 真 RAW 链（后一条把前一条结果当 vs1），长度 k
for _k in (2, 3, 4, 6, 8):
    _ops = [L(1, "A_mix"), L(2, "B_three"), VD(3, 1, 2)]
    for _ in range(_k - 1):
        _ops.append(VD(3, 3, 2))
    _ops.append(RD(3))
    add("xp_chain%d" % _k, "vdot-pl", "raw-chain", "同 vd RAW 依赖链长度 %d（后一条读前一条的 vd）" % _k, _ops)

# 3.4 写回端口竞争：vdot 与 vmacc 交替写不同 vd（同一 VIMac 写回口），只断言 vdot 结果
for _k in (2, 3, 4, 6):
    # 每个 vmacc 目标都显式预填：未写过的向量寄存器内容不在本用例的可证伪范围内
    _ops = [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_mix"), L(7, "B_three")]
    _ops += [VMV(10 + _i, 0x33 + _i) for _i in range(_k)]
    for _i in range(_k):
        _ops.append(VD(3 + _i, 1, 2))
        _ops.append(VM(10 + _i, 6, 7))
    _ops += [RD(3 + _i) for _i in range(_k)]
    add("xp_wbp%d" % _k, "vdot-pl", "wb-port",
        "%d 组 vdot↔vmacc 交替写不同 vd（写回端口竞争；vmacc 结果由 difftest 兜底）" % _k, _ops)

# 3.5 取消 / 控制流重定向：vdot 后紧跟 taken jal 跳过下一条 vdot（被跳过的 vdot 不得写回）
for _k in (2, 3, 4, 8):
    _ops = [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"), VMV(20, 0x5A)]
    for _i in range(_k):
        _ops += [VD(3, 1, 2), JAL(), VDS(20, 4, 5)]
    _ops += [RD(3), RD(20, hi=False)]
    add("xp_cxl%d" % _k, "vdot-pl", "cancel",
        "%d 轮 vdot→taken jal 跳过下一条 vdot（控制流重定向；被跳过者不得写回，vd20 必须仍是预填 0x5A）" % _k, _ops)

# 3.6 异常状态夹插（构造-清除）：把会判非法的状态先造出来再清掉，vdot 必须仍合法且结果正确
add("xp_ilv_vstart", "vdot-pl", "illegal-interleave", "vstart=1 后清 0，再执行 vdot",
    [L(1, "A_pos"), L(2, "B_pos"), RSV(1), CLRV(), VD(3, 1, 2), RD(3)])
add("xp_ilv_vill", "vdot-pl", "illegal-interleave", "非法 vtype 造出 vill=1，再用合法 vsetvli 清除，再 vdot",
    [L(1, "A_pos"), L(2, "B_pos"), SETVT(0x38), SETVL(16), VD(3, 1, 2), RD(3)])
add("xp_ilv_vs", "vdot-pl", "illegal-interleave", "mstatus.VS 关掉再打开，再 vdot",
    [L(1, "A_pos"), L(2, "B_pos"), VSOFF(), VSON(), VD(3, 1, 2), RD(3)])
add("xp_ilv_sew_back", "vdot-pl", "illegal-interleave", "vtype 切到 e16 再切回 e8，再 vdot",
    [L(1, "A_ext"), L(2, "B_ext2"), SETVT(0x08), SETVL(16), VD(3, 1, 2), RD(3)])
add("xp_ilv_lmul_back", "vdot-pl", "illegal-interleave", "vtype 切到 m4 再切回 m1，再 vdot",
    [L(1, "A_ext"), L(2, "B_ext2"), SETVT(0x02), SETVL(16), VD(3, 1, 2), RD(3)])
add("xp_ilv_all", "vdot-pl", "illegal-interleave", "vstart/vill/VS/SEW/LMUL 五类非法状态依次构造并清除后 vdot",
    [L(1, "A_mix"), L(2, "B_three"), RSV(3), CLRV(), SETVT(0x20), SETVL(16),
     VSOFF(), VSON(), SETVT(0x18), SETVL(16), SETVT(0x03), SETVL(16), VD(3, 1, 2), RD(3)])

# 3.7 混合发射：vdot 与 vadd 交替（不同 vd，vadd 只占写回口，不断言其结果）
for _k in (2, 3, 4, 6):
    _ops = [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2")]
    _ops += [VMV(10 + _i, 0x40 + _i) for _i in range(_k)]
    for _i in range(_k):
        _ops.append(VD(3 + _i, 1, 2))
        _ops.append(VA(10 + _i, 6, 7))
    _ops += [RD(3 + _i) for _i in range(_k)]
    add("xp_mix%d" % _k, "vdot-pl", "mix-issue", "%d 组 vdot↔vadd 交替发射" % _k, _ops)

# 3.8 高 96 位：k 条背靠背 vdot 全部做高 96 位恒零断言
for _k in (2, 4, 8):
    _ops = [L(1, "A_asym"), L(2, "B_asym")]
    for _i in range(_k):
        _ops.append(VD(3 + _i, 1, 2))
    _ops += [RD(3 + _i) for _i in range(_k)]
    add("xp_hi%d" % _k, "vdot-pl", "hi96", "%d 条背靠背 vdot 逐条断言 vd[127:32]=0" % _k, _ops)

# 3.9 旧 vd 预填：4 个不同预填值后紧跟 vdot（0 bubble）
for _i, _pf in enumerate((0x00, 0x01, 0x7F, 0x80), start=1):
    add("xp_oldvd%d" % _i, "vdot-pl", "old-vd", "旧 vd 预填 0x%02X 后紧跟 vdot（不读旧值）" % _pf,
        [VMV(3, _pf), L(1, "A_ext"), L(2, "B_ext2"), VD(3, 1, 2), RD(3)])

# 3.10 背靠背 + bubble 混合
for _k in (2, 3):
    _ops = [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2")]
    for _i in range(_k):
        _ops += [VD(3 + _i, 1, 2), NOP(_i + 1)]
    _ops += [VD(3, 4, 5), RD(3)]
    _ops += [RD(3 + _i) for _i in range(_k)]
    add("xp_bbbub%d" % _k, "vdot-pl", "bb+bubble",
        "%d 条背靠背 vdot，各自后跟递增 nop，再补一条覆盖 vd3 的 vdot" % _k, _ops)

# 3.11 vdot 之间也抢写回口：k 条背靠背到不同 vd（同一 vimac 写回口）
for _k in (2, 4):
    _ops = [L(1, "A_lanehi"), L(2, "B_lanehi")]
    for _i in range(_k):
        _ops.append(VD(4 + _i, 1, 2))
    _ops += [RD(4 + _i) for _i in range(_k)]
    add("xp_wbpv%d" % _k, "vdot-pl", "wb-port-vdot",
        "%d 条 vdot 连续抢同一写回口（不同 vd）" % _k, _ops)

# 3.12 循环内 vdot（控制流回边）：见 LOOP_CASES，单独模板
LOOP_CASES = [
    ("xp_loop2", 2, "循环 2 次，每次 vdot 结果累加，终值与 2*S 比对"),
    ("xp_loop4", 4, "循环 4 次"),
    ("xp_loop8", 8, "循环 8 次"),
    ("xp_loop16", 16, "循环 16 次"),
]

# ---------------------------------------------------------------------------
# ④ 异常参数组合 negative（配额 ≥32）：vill / vstart / SEW / LMUL / mstatus.VS 矩阵
#    每个负例的「陷阱必须落在 vdot 自身」：先在 e8,m1 下完成合法装载，再构造非法状态。
# ---------------------------------------------------------------------------
NEG = []


def neg(cid, note, pre, enc, extra_state=""):
    NEG.append({"cid": cid, "note": note, "pre": pre, "enc": enc, "extra": extra_state})


_SEW = {"e8": 0x00, "e16": 0x08, "e32": 0x10, "e64": 0x18}
_LMUL = {"m1": 0x00, "m2": 0x01, "m4": 0x02, "m8": 0x03,
         "mf8": 0x05, "mf4": 0x06, "mf2": 0x07}
_ALIGN = {"m1": (3, 1, 2), "m2": (4, 2, 0), "m4": (8, 4, 0), "m8": (16, 8, 0),
          "mf8": (3, 1, 2), "mf4": (3, 1, 2), "mf2": (3, 1, 2)}


def vtype_of(sew, lmul, vta=0, vma=0):
    return _SEW[sew] | _LMUL[lmul] | (vta << 6) | (vma << 7)


def pre_sew(sew):
    return [("vsetvli", sew, "m1")]


def pre_sew_lmul(sew, lmul):
    return [("vsetvli", sew, lmul)]


for _sew in ("e16", "e32", "e64"):
    neg("xn_sew_%s" % _sew, "SEW=%s（vdot 要求 SEW=8）" % _sew, pre_sew(_sew), enc_vdot(3, 1, 2))
for _lm in ("m2", "m4", "m8"):
    _vd, _v1, _v2 = _ALIGN[_lm]
    neg("xn_lmul_%s" % _lm, "LMUL=%s（vdot 要求 LMUL=1，寄存器组按 %s 对齐）" % (_lm, _lm),
        pre_sew_lmul("e8", _lm), enc_vdot(_vd, _v1, _v2))
for _lm in ("mf8", "mf4", "mf2"):
    neg("xn_lmul_%s" % _lm, "LMUL=%s（分数 LMUL，vdot 只支持 LMUL=1）" % _lm,
        pre_sew_lmul("e8", _lm), enc_vdot(3, 1, 2))
neg("xn_vm0", "vm=0（0x3820A1D7：清 bit25 后不命中 vdot 解码）", [], 0x3820A1D7)
for _n in (1, 2, 3, 4, 7, 15):
    neg("xn_vstart%d" % _n, "vstart=%d（vdot 要求 vstart=0）" % _n, [("vstart", _n)], enc_vdot(3, 1, 2))
for _vt in (0x38, 0x20, 0x3A, 0x24):
    neg("xn_vill_%02x" % _vt, "vill=1（非法 vtype 0x%02X 的 vsetvl 后立即 vdot）" % _vt,
        [("vill", _vt)], enc_vdot(3, 1, 2))
neg("xn_vs_off", "mstatus.VS=OFF（先开 VS 再关，唯一变量是 VS）", [("vs_off", 0)], enc_vdot(3, 1, 2))
for _sew in ("e16", "e32", "e64"):
    for _lm in ("m2", "m4", "m8"):
        _vd, _v1, _v2 = _ALIGN[_lm]
        neg("xn_%s_%s" % (_sew, _lm), "SEW=%s 且 LMUL=%s（两个谓词同时不满足）" % (_sew, _lm),
            pre_sew_lmul(_sew, _lm), enc_vdot(_vd, _v1, _v2))
for _sew, _n in (("e16", 1), ("e32", 1), ("e16", 8), ("e32", 8)):
    neg("xn_vstart%d_%s" % (_n, _sew), "vstart=%d 且 SEW=%s" % (_n, _sew),
        [("vstart", _n)] + pre_sew(_sew), enc_vdot(3, 1, 2))
neg("xn_lmulm8_vstart1", "LMUL=m8 且 vstart=1（两谓词同时不满足，寄存器组按 m8 对齐）",
    [("vstart", 1)] + pre_sew_lmul("e8", "m8"), enc_vdot(16, 8, 0))
neg("xn_vs_off_vstart1", "mstatus.VS=OFF 且 vstart=1",
    [("vstart", 1), ("vs_off", 0)], enc_vdot(3, 1, 2))
neg("xn_vill_vstart1", "vill=1 且 vstart=1", [("vill", 0x38), ("vstart", 1)], enc_vdot(3, 1, 2))
neg("xn_vm0_sew16", "vm=0 且 SEW=e16", pre_sew("e16"), 0x3820A1D7)
neg("xn_sew16_vl0", "SEW=e16 且 vl=0（非法判定优先于 vl=0 全写，SPEC §1.1）",
    [("vsetvli_vl0", "e16", "m1")], enc_vdot(3, 1, 2))
neg("xn_vs_off_vl0", "mstatus.VS=OFF 且 vl=0（非法优先于 vl=0 全写）",
    [("vsetvli_vl0", "e8", "m1"), ("vs_off", 0)], enc_vdot(3, 1, 2))
neg("xn_vstart1_vl0", "vstart=1 且 vl=0（非法优先于 vl=0 全写）",
    [("vsetvli_vl0", "e8", "m1"), ("vstart", 1)], enc_vdot(3, 1, 2))

for _n in NEG:
    add(_n["cid"], "negative", "illegal", _n["note"], None)

# ---------------------------------------------------------------------------
# ⑤ G0 反例 2 行（期望值故意错 1 bit，必须打印 MISMATCH 并被同一套自检判为失败）
# ---------------------------------------------------------------------------
_g0a = [VMV(3, 0xAB), L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), RD(3)]
add("xg0_overlap", "g0", "g0", "重叠用例的期望值故意错 1 bit（用于证明自检非空转）", _g0a, g0_bit=0)
_g0b = [L(1, "A_ext"), L(2, "B_ext2"), VD(3, 1, 2), VD(4, 1, 2), RD(4)]
add("xg0_pipeline", "g0", "g0", "背靠背用例的期望值故意错 1 bit（用于证明自检非空转）", _g0b, g0_bit=11)

# ---------------------------------------------------------------------------
# ⑥ 随机 10000 组（独立镜像，不改动 vdot_rand 的源与镜像）
# ---------------------------------------------------------------------------
RAND10K_CID = "vdot_rand10k"
RAND10K_GROUPS = 10000
RAND10K_SEED = 20261106


def gen_rand10k():
    """生成 vdot_rand10k.c：期望数组由金模型逐组算出，C 侧再用算法 B 独立复算一遍。"""
    s = RAND10K_SEED & 0xFFFFFFFF
    wants = []
    for _ in range(RAND10K_GROUPS):
        a, b = [], []
        for _i in range(16):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            a.append(to_int8(s >> 24))
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            b.append(to_int8(s >> 16))
        wants.append(M.vdot_vv(reg128(a), reg128(b)) & 0xFFFFFFFF)
    lines = []
    for i in range(0, len(wants), 8):
        lines.append("  " + ", ".join("0x%08Xu" % w for w in wants[i:i + 8]) + ",")
    src = """// vdot_rand10k.c — 随机 10000 组（扩容用例；与主清单 vdot_rand.bin 的 1024 组无关）
//@CID vdot_rand10k
//@CLS vdot-rand10k
//@FAMILY rand10k
//
// 生成器：design/verify/cases/gen_extra.py（固定种子 %d，LCG 常数与 vdot_rand.c 同：1664525/1013904223）
// 期望值：want10k[] 由金模型 design/verify/vdot_model.py 的 vdot_vv() 逐组算出并烧进镜像；
//         C 侧再用算法 B（int64 逐项累加）独立复算一遍，两者必须逐组相等（model_bad==0）。
//         因此 Python 与 C 两侧的 LCG 流一旦分叉，algo_b 与 want10k 立即不等，model_bad>0，
//         用例判为失败，不会出现 DUT 与期望同时错的情形。
// 语义：SPEC §1.1（S=Σ sext8(vs1[i])*sext8(vs2[i])，i=0..7；lane 8..15 不参与；vd[127:32]=0）。
// 自检串：RAND10K verdict=ALL_OK groups=%d mism=0 model_bad=0 ab_bad=0
#include <am.h>
#include <klib.h>
#include <stdint.h>

#define GROUPS %d

static volatile uint32_t out[4];
static const uint32_t want10k[GROUPS] = {
%s
};

static inline uint32_t lcg(uint32_t *s) { *s = *s * 1664525u + 1013904223u; return *s; }

static long long algo_b(const int8_t *a, const int8_t *b) {
  long long s = 0;
  for (int i = 0; i < 8; i++) s += (long long)a[i] * (long long)b[i];
  return s;
}

int main(void) {
  uint32_t seed = %du;
  int mism = 0, model_bad = 0, ab_bad = 0;
  int8_t a[16], b[16];
  for (int g = 0; g < GROUPS; g++) {
    for (int i = 0; i < 16; i++) {
      a[i] = (int8_t)(lcg(&seed) >> 24);
      b[i] = (int8_t)(lcg(&seed) >> 16);
    }
    long long want_b = algo_b(a, b);
    if ((uint32_t)want_b != want10k[g]) model_bad++;
    uint32_t got = 0;
    register uint8_t *pa = (uint8_t *)a;
    register uint8_t *pb = (uint8_t *)b;
    register uint32_t *pout = (uint32_t *)out;
    asm volatile(
        "li t0, 0x600\\n\\t"
        "csrs mstatus, t0\\n\\t"
        "li t1, 16\\n\\t"
        "vsetvli zero, t1, e8, m1, ta, ma\\n\\t"
        "vle8.v v1, (%%0)\\n\\t"
        "vle8.v v2, (%%1)\\n\\t"
        ".4byte 0x3A20A1D7\\n\\t"
        "li t2, 4\\n\\t"
        "vsetvli zero, t2, e32, m1, tu, mu\\n\\t"
        "vmv.x.s %%2, v3\\n\\t"
        "vse32.v v3, (%%3)\\n\\t"
        : "+r"(pa), "+r"(pb), "=r"(got), "+r"(pout)
        :: "t0", "t1", "t2", "memory");
    if (got != want10k[g]) mism++;
    if (out[1] != 0 || out[2] != 0 || out[3] != 0) ab_bad++;
  }
  printf("RAND10K verdict=%%s groups=%%d mism=%%d model_bad=%%d ab_bad=%%d\\n",
         (mism == 0 && model_bad == 0 && ab_bad == 0) ? "ALL_OK" : "HAS_FAIL",
         GROUPS, mism, model_bad, ab_bad);
  return (mism == 0 && model_bad == 0 && ab_bad == 0) ? 0 : 1;
}
""" % (RAND10K_SEED, RAND10K_GROUPS, RAND10K_GROUPS, "\n".join(lines), RAND10K_SEED)
    return src


# ---------------------------------------------------------------------------
# 发射器：把规格翻成 C 源（同时用金模型逐条推进寄存器状态，得到断言常量）
# ---------------------------------------------------------------------------


def emit_linear(case):
    """线性用例（base / overlap / pipeline 的除 loop 外全部）。"""
    cid = case["cid"]
    ops = case["ops"]
    regs = {}
    cur_vl = [16]
    asm = []
    reads = []
    hdr = []
    used_arr = []

    def C(s):
        asm.append("      //@OP " + s)

    def S(s):
        asm.append('      "%s\\n\\t"' % s)

    for op in ops:
        kind = op["op"]
        if kind == "load":
            arr = op["arr"]
            if arr not in used_arr:
                used_arr.append(arr)
            sym = "op%d" % (used_arr.index(arr) + 1)
            C("load v%d arr=%s" % (op["vd"], sym))
            S("la a2, %s" % sym)
            S("vle8.v v%d, (a2)" % op["vd"])
            regs[op["vd"]] = reg128(ARR[arr])
        elif kind == "vmv":
            C("vmv v%d imm=0x%02X" % (op["vd"], op["imm"]))
            S("li t3, %d" % op["imm"])
            S("vmv.v.x v%d, t3" % op["vd"])
            regs[op["vd"]] = op["imm"] * 0x01010101010101010101010101010101
        elif kind == "vdot":
            vd, vs1, vs2 = op["vd"], op["vs1"], op["vs2"]
            e = enc_vdot(vd, vs1, vs2)
            C("vdot vd=%d vs1=%d vs2=%d enc=0x%08X" % (vd, vs1, vs2, e))
            S(".4byte 0x%08X" % e)
            regs[vd] = M.vdot_vv(regs.get(vs1, 0), regs.get(vs2, 0))
        elif kind == "vdot_skipped":
            vd, vs1, vs2 = op["vd"], op["vs1"], op["vs2"]
            e = enc_vdot(vd, vs1, vs2)
            C("vdot(SKIPPED) vd=%d vs1=%d vs2=%d enc=0x%08X" % (vd, vs1, vs2, e))
            S(".4byte 0x%08X" % e)
            # 金模型按「不执行」推进：该条被紧邻的 taken jal 跳过，不得写回
        elif kind == "vadd":
            vd, vs1, vs2 = op["vd"], op["vs1"], op["vs2"]
            e = enc_vadd(vd, vs1, vs2)
            C("vadd vd=%d vs1=%d vs2=%d enc=0x%08X" % (vd, vs1, vs2, e))
            S(".4byte 0x%08X" % e)
            x, y = regs.get(vs1, 0), regs.get(vs2, 0)
            out = 0
            for i in range(16):
                out |= (((x >> (8 * i)) + (y >> (8 * i))) & 0xFF) << (8 * i)
            regs[vd] = out
        elif kind == "vmacc":
            vd, vs1, vs2 = op["vd"], op["vs1"], op["vs2"]
            e = enc_vmacc(vd, vs1, vs2)
            C("vmacc vd=%d vs1=%d vs2=%d enc=0x%08X" % (vd, vs1, vs2, e))
            S(".4byte 0x%08X" % e)
            old, x, y = regs.get(vd, 0), regs.get(vs1, 0), regs.get(vs2, 0)
            out = 0
            for i in range(16):
                ob = (old >> (8 * i)) & 0xFF
                xb = M.sext((x >> (8 * i)) & 0xFF, 8)
                yb = M.sext((y >> (8 * i)) & 0xFF, 8)
                out |= ((ob + xb * yb) & 0xFF) << (8 * i)
            regs[vd] = out
        elif kind == "nop":
            C("nop %d" % op["n"])
            for _ in range(op["n"]):
                S("nop")
        elif kind == "vl":
            cur_vl[0] = op["n"]
            C("vl %d" % op["n"])
            S("li t1, %d" % op["n"])
            S("vsetvli zero, t1, e8, m1, ta, ma")
        elif kind == "vtype":
            C("vtype 0x%02X" % op["n"])
            S("li t1, 16")
            S("li t3, %d" % op["n"])
            S("vsetvl zero, t1, t3")
            cur_vl[0] = 16
        elif kind == "rs_vstart":
            C("rs_vstart %d" % op["n"])
            S("li t4, %d" % op["n"])
            S("csrw 0x008, t4")
        elif kind == "clr_vstart":
            C("clr_vstart")
            S("csrw 0x008, zero")
        elif kind == "vs_off":
            C("vs_off")
            S("li t4, 0x600")
            S("csrc mstatus, t4")
        elif kind == "vs_on":
            C("vs_on")
            S("li t4, 0x600")
            S("csrs mstatus, t4")
        elif kind == "jalover":
            C("jalover")
            S("jal x0, .+8")
        elif kind == "read":
            vd = op["vd"]
            want = regs.get(vd, 0)
            lo = want & 0xFFFFFFFF
            hi_zero = 1 if ((want >> 32) == 0 and op.get("hi", True)) else 0
            idx = len(reads)
            if case["g0_bit"] is not None and idx == 0:
                lo ^= 1 << case["g0_bit"]
                hdr.append("//@G0 %d" % case["g0_bit"])
            reads.append({"idx": idx, "vd": vd, "want": lo, "hi": hi_zero})
            C("read idx=%d vd=%d want=0x%08X hi=%d" % (idx, vd, lo, hi_zero))
            S("li t2, 4")
            S("vsetvli zero, t2, e32, m1, tu, mu")
            S("vmv.x.s t3, v%d" % vd)
            S("la a5, got")
            S("sw t3, %d(a5)" % (4 * idx))
            S("la a5, hi_%d" % idx)
            S("vse32.v v%d, (a5)" % vd)
            S("li t1, %d" % cur_vl[0])
            S("vsetvli zero, t1, e8, m1, ta, ma")
        else:
            raise SystemExit("未知 op：%r（cid=%s）" % (kind, cid))

    # ---- 组装 C 源 ----
    out = []
    out.append("// %s.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）" % cid)
    out.append("//@CID %s" % cid)
    out.append("//@CLS %s" % case["cls"])
    out.append("//@FAMILY %s" % case["family"])
    for h in hdr:
        out.append(h)
    out.append("// 说明：%s" % case["note"])
    out.append("// 期望值：全部由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）")
    out.append("// 语义：SPEC §1.1 / §1.2；编码：SPEC §2.2（funct6=001110, vm=1, funct3=010, opcode=1010111）")
    out.append("#include <am.h>")
    out.append("#include <klib.h>")
    out.append("#include <stdint.h>")
    out.append("")
    out.append("#define ENC_VDOT(vd, vs1, vs2)                                                 \\")
    out.append("  ((uint32_t)(0x0Eu << 26) | (1u << 25) | ((uint32_t)(vs2) << 20) |            \\")
    out.append("   ((uint32_t)(vs1) << 15) | (2u << 12) | ((uint32_t)(vd) << 7) | 0x57u)")
    out.append("")
    for i, name in enumerate(used_arr, start=1):
        vals = ARR[name]
        out.append("static volatile int8_t op%d[16] = {%s};" %
                   (i, ", ".join(str(v) for v in vals)))
    out.append("")
    nread = len(reads)
    out.append("static volatile uint32_t got[%d];" % max(nread, 1))
    for r in reads:
        out.append("static volatile uint32_t hi_%d[4] __attribute__((aligned(16)));" % r["idx"])
    out.append("")
    out.append("int main(void) {")
    out.append("  int fails = 0;")
    out.append("  /* SPEC §1.1 第六条：AM start.S 只开 mstatus.FS，向量还需 VS!=OFF */")
    out.append('  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");')
    for r in reads:
        out.append("  for (int i = 0; i < 4; i++) hi_%d[i] = 0xFFFFFFFFu;  /* 哨兵：漏发 vse32.v 时断言失败 */"
                   % r["idx"])
    out.append("  asm volatile(")
    out.append("    //@PROLOGUE 载入全部操作数：e8,m1,vl=16（SPEC §1.1：lane 0..15 全写）")
    out.append('      ".balign 4\\n\\t"')
    out.append('      ".option push\\n\\t"')
    out.append('      ".option norvc\\n\\t"')
    out.append('      "li t1, 16\\n\\t"')
    out.append('      "vsetvli zero, t1, e8, m1, ta, ma\\n\\t"')
    out.extend(asm)
    out.append('      ".option pop\\n\\t"')
    out.append("      ::: \"t0\", \"t1\", \"t2\", \"t3\", \"t4\", \"a2\", \"a3\", \"a5\", \"memory\");")
    out.append("")
    out.append("  /* ---- 断言（期望常量全部来自金模型）---- */")
    for r in reads:
        out.append("  if (got[%d] != 0x%08Xu) { fails++; printf(\"EXTRA %s read%d got=0x%%08X want=0x%08X\\n\", got[%d], 0x%08Xu); }"
                   % (r["idx"], r["want"], cid, r["idx"], r["want"], r["idx"], r["want"]))
        if r["hi"]:
            out.append("  if (hi_%d[1] != 0u || hi_%d[2] != 0u || hi_%d[3] != 0u) { fails++; printf(\"EXTRA %s read%d hi96=[%%08X %%08X %%08X]\\n\", hi_%d[1], hi_%d[2], hi_%d[3]); }"
                       % (r["idx"], r["idx"], r["idx"], cid, r["idx"], r["idx"], r["idx"], r["idx"]))
    out.append("  printf(\"EXTRA %s reads=%d fails=%%d\\n\", fails);" % (cid, nread))
    out.append("  printf(\"CASE %s: %%s\\n\", fails == 0 ? \"MATCH\" : \"MISMATCH\");" % cid)
    out.append("  printf(\"EXTRA %s verdict=%%s fails=%%d\\n\", fails == 0 ? \"ALL_OK\" : \"HAS_FAIL\", fails);" % cid)
    if case["family"] == "g0":
        # G0 反例：期望值故意错 1 bit ⇒ 必打印 MISMATCH，但程序必须正常走到结尾
        # （HIT GOOD TRAP），否则失败原因会退化成 BAD TRAP，自检非空转的证明就失去意义。
        # 先例：design/verify/cases/vdot_g0_badexp.c:38 的 `return 0;`。
        out.append("  return 0;  /* 期望故意错 ⇒ 必 MISMATCH；必须 GOOD TRAP 才算 G0 捕获 */")
    else:
        out.append("  return fails == 0 ? 0 : 1;")
    out.append("}")
    return "\n".join(out) + "\n"


def emit_loop(cid, k, note):
    """循环形态：vdot 在 C for 循环里重复，每次读回并累加，终值与 k*S 比对。"""
    want = M.vdot_vv(reg128(ARR["A_pos"]), reg128(ARR["B_pos"])) & 0xFFFFFFFF
    # 必须用 raw 字符串：模板里的 \n\t 是**C 字符串字面量里的转义**，不是 Python 的换行
    body = r"""// @CID@.c — 扩容用例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID @CID@
//@CLS vdot-pl
//@FAMILY loop
// 说明：@NOTE@
// 期望值：单次 S 由 design/verify/vdot_model.py 的 vdot_vv() 算出（探针见 extra_crosscheck.py）
// 语义：SPEC §1.1（vl 不影响结果；vd[31:0]=sext32(S)，vd[127:32]=0）
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t op1[16] = {@A@};
static volatile int8_t op2[16] = {@B@};

int main(void) {
  asm volatile("csrs mstatus, %0" ::"r"((uint64_t)0x600) : "memory");
  const uint32_t want = 0x@WANT@u;
  uint64_t sum = 0;
  for (int it = 0; it < @K@; it++) {
    uint32_t r = 0;
    asm volatile(
        ".balign 4\n\t.option push\n\t.option norvc\n\t"
        "li t1, 16\n\t"
        "vsetvli zero, t1, e8, m1, ta, ma\n\t"
        "la a2, op1\n\t"
        "vle8.v v1, (a2)\n\t"
        "la a3, op2\n\t"
        "vle8.v v2, (a3)\n\t"
        ".4byte 0x3A20A1D7\n\t"
        "li t2, 4\n\t"
        "vsetvli zero, t2, e32, m1, tu, mu\n\t"
        "vmv.x.s %0, v3\n\t"
        ".option pop\n\t"
        : "=r"(r)
        :
        : "t1", "t2", "a2", "a3", "memory");
    sum += r;
  }
  int fails = 0;
  if (sum != (uint64_t)want * @K@) {
    fails++;
    printf("EXTRA @CID@ sum=0x%llX want=0x%llX\n", (unsigned long long)sum,
           (unsigned long long)((uint64_t)want * @K@));
  }
  printf("EXTRA @CID@ iters=@K@ fails=%d\n", fails);
  printf("CASE @CID@: %s\n", fails == 0 ? "MATCH" : "MISMATCH");
  printf("EXTRA @CID@ verdict=%s fails=%d\n", fails == 0 ? "ALL_OK" : "HAS_FAIL", fails);
  return fails == 0 ? 0 : 1;
}
"""
    repl = {
        "@CID@": cid,
        "@NOTE@": note,
        "@A@": ", ".join(str(v) for v in ARR["A_pos"]),
        "@B@": ", ".join(str(v) for v in ARR["B_pos"]),
        "@WANT@": "%08X" % want,
        "@K@": str(k),
    }
    for key, val in repl.items():
        body = body.replace(key, val)
    return body


def emit_negative(n):
    """负例：先合法装载（VS 已开），再构造非法状态并发射 vdot；走到 vdot 之后即打印哨兵。"""
    cid = n["cid"]
    lines = []
    # 状态构造序列在 n["pre"]（neg() 的第 3 个位置参数）；n["extra"] 只放附加说明串。
    for st in n["pre"]:
        kind = st[0]
        if kind == "vsetvli":
            lines.append('      "li t1, 16\\n\\t"')
            lines.append('      "vsetvli zero, t1, %s, %s, ta, ma\\n\\t"' % (st[1], st[2]))
        elif kind == "vsetvli_vl0":
            lines.append('      "li t1, 0\\n\\t"')
            lines.append('      "vsetvli zero, t1, %s, %s, ta, ma\\n\\t"' % (st[1], st[2]))
        elif kind == "vstart":
            lines.append('      "li t4, %d\\n\\t"' % st[1])
            lines.append('      "csrw 0x008, t4\\n\\t"')
        elif kind == "vill":
            lines.append('      "li t4, %d\\n\\t"' % st[1])
            lines.append('      "li t5, 8\\n\\t"')
            lines.append('      "vsetvl zero, t5, t4\\n\\t"')
        elif kind == "vs_off":
            lines.append('      "li t4, 0x600\\n\\t"')
            lines.append('      "csrc mstatus, t4\\n\\t"')
        else:
            raise SystemExit("未知负例状态构造：%r" % (st,))
    return """// %s.c — 扩容负例（生成器 design/verify/cases/gen_extra.py；请勿手改）
//@CID %s
//@CLS negative
//@FAMILY illegal
// 说明：%s
// 自检：DUT/NEMU 双侧一致陷入非法（HIT CRITICAL ERROR）、无失配；若未陷入，则打印「CASE <cid>: 未如期陷入非法指令」
#include <am.h>
#include <klib.h>
#include <stdint.h>

static volatile int8_t av[16] = {%s};
static volatile int8_t bv[16] = {%s};

int main(void) {
  uint64_t res = 0;
  asm volatile(
      ".balign 4\\n\\t.option push\\n\\t.option norvc\\n\\t"
      "li t0, 0x600\\n\\t"
      "csrs mstatus, t0\\n\\t"
      "li t1, 16\\n\\t"
      "vsetvli zero, t1, e8, m1, ta, ma\\n\\t"
      "la a2, av\\n\\t"
      "vle8.v v1, (a2)\\n\\t"
      "la a3, bv\\n\\t"
      "vle8.v v2, (a3)\\n\\t"
%s
      ".4byte 0x%08X\\n\\t"
      "vmv.x.s %%0, v3\\n\\t"
      ".option pop\\n\\t"
      : "=r"(res)
      :
      : "t0", "t1", "t4", "t5", "a2", "a3", "memory");
  printf("CASE %s: 未如期陷入非法指令 res=0x%%08X\\n", (unsigned int)res);
  return 1;
}
""" % (cid, cid, n["note"],
       ", ".join(str(v) for v in ARR["A_pos"]),
       ", ".join(str(v) for v in ARR["B_pos"]),
       "\n".join(lines), n["enc"], cid)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def build_all():
    sources = {}
    for case in CASES:
        if case["ops"] is not None:
            sources[case["cid"]] = emit_linear(case)
    for cid, k, note in LOOP_CASES:
        sources[cid] = emit_loop(cid, k, note)
    for n in NEG:
        sources[n["cid"]] = emit_negative(n)
    sources[RAND10K_CID] = gen_rand10k()
    return sources


ANCHOR = {
    "base": "SPEC §1.1/§1.2 语义与写回；§3.2 边界值",
    "overlap": "vector-common.adoc norm:vreg_overlap_rsv(:1037-1038) + norm:vreg_overlap_legal(:1013-1028)",
    "back2back": "ARCHITECTURE §2.2 第 7 条 / §8 R13（fireS1 拍对齐）",
    "bubble": "ARCHITECTURE §8:192（含 bubble 变体）",
    "raw-chain": "SPEC §1.1 旧 vd 非语义输入；写后读依赖",
    "wb-port": "ARCHITECTURE §2 写回级 Mux(outIsVdot)（wrapper/VIMacU.scala:158-160）",
    "wb-port-vdot": "ARCHITECTURE §2 写回级同一写回口",
    "cancel": "CODING-STD §3.4 fire/fireS1 纪律；控制流重定向",
    "illegal-interleave": "SPEC §1.1 六条必要条件（构造-清除不残留）",
    "mix-issue": "ARCHITECTURE §2.2 发射/写回竞争",
    "hi96": "SPEC §1.2 第 2 条（vd[127:32] 恒零）",
    "old-vd": "SPEC §1.1 旧 vd 不读不累加",
    "bb+bubble": "ARCHITECTURE §8:192 + R13",
    "loop": "控制流回边（循环内重复执行）",
    "illegal": "SPEC §1.1/§1.3 六条必要条件矩阵；SPEC §1.1「非法优先于 vl=0 全写」",
    "g0": "ALGORITHM §3.1 G0 反例（期望值故意错 1 bit）",
    "rand10k": "ALGORITHM §3.2 随机类（固定种子，金模型 + 算法 B 双算）",
}


def manifest_rows():
    """返回 [(cid, cls, family, note)]，顺序即 manifest 行序。"""
    rows = []
    for case in CASES:
        if case["ops"] is None:
            continue          # 负例在下面按 NEG 表统一登记（避免重复计入）
        rows.append((case["cid"], case["cls"], case["family"], case["note"]))
    for cid, _k, note in LOOP_CASES:
        rows.append((cid, "vdot-pl", "loop", note))
    for n in NEG:
        rows.append((n["cid"], "negative", "illegal", n["note"]))
    rows.append((RAND10K_CID, "vdot-rand10k", "rand10k",
                 "随机 %d 组（固定种子 %d），期望由金模型生成、C 侧算法 B 独立复算" % (RAND10K_GROUPS, RAND10K_SEED)))
    return rows


def main():
    check_only = "--check" in sys.argv
    sources = build_all()
    rows = manifest_rows()
    counts = {}
    for _cid, cls, _fam, _note in rows:
        counts[cls] = counts.get(cls, 0) + 1
    print("gen_extra: 用例 %d 个（清单行 %d）" % (len(sources), len(rows)))
    for cls in sorted(counts):
        print("  %-14s %3d 行" % (cls, counts[cls]))
    bad = 0
    for cls, quota in CLASS_QUOTA.items():
        n = counts.get(cls, 0)
        flag = "OK" if n >= quota else "配额不足"
        if n < quota:
            bad += 1
        print("  配额 %-10s %3d >= %3d  %s" % (cls, n, quota, flag))
    if len(rows) < MIN_ROWS:
        print("  [FATAL] 总行数 %d < %d" % (len(rows), MIN_ROWS))
        bad += 1
    else:
        print("  配额 总行数     %3d >= %3d  OK" % (len(rows), MIN_ROWS))
    if counts.get("vdot-base", 0) < BASE_ROWS:
        print("  [FATAL] 基础类 %d < %d" % (counts.get("vdot-base", 0), BASE_ROWS))
        bad += 1
    if counts.get("g0", 0) < 1:
        print("  [FATAL] 缺 g0 反例")
        bad += 1
    if check_only:
        return 1 if bad else 0

    os.makedirs(OUT_DIR, exist_ok=True)
    for cid, src in sorted(sources.items()):
        with open(os.path.join(OUT_DIR, cid + ".c"), "w", encoding="utf-8") as f:
            f.write(src)
    # 清理不在本次生成清单内的 .c（同一目录只保留本次产物）
    for name in sorted(os.listdir(OUT_DIR)):
        if name.endswith(".c") and name[:-2] not in sources:
            os.remove(os.path.join(OUT_DIR, name))
    with open(os.path.join(OUT_DIR, "spec.extra.json"), "w", encoding="utf-8") as f:
        json.dump({
            "generator": "design/verify/cases/gen_extra.py",
            "model": "design/verify/vdot_model.py",
            "rows": len(rows),
            "counts": counts,
            "quota": CLASS_QUOTA,
            "min_rows": MIN_ROWS,
            "cases": [{"cid": c, "cls": cl, "family": fam, "anchor": ANCHOR.get(fam, ""),
                       "note": note} for c, cl, fam, note in rows],
        }, f, ensure_ascii=False, indent=2)

    # manifest.extra.tsv：4 列（与 manifest.tsv 同格式；@IMG_DIR@ 由 make_manifest.sh 替换）
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write("# cid\tcls\timage(占位符 @IMG_DIR@ 用 make_manifest.sh 替换为绝对路径)\textra\n")
        for cid, cls, _fam, _note in rows:
            f.write("%s\t%s\t@IMG_DIR@/%s.bin\t\n" % (cid, cls, cid))

    # cover.extra.tsv：覆盖点矩阵（cid / cls / family / 规范锚点 / 说明），供报告机械汇总
    with open(os.path.join(HERE, "cover.extra.tsv"), "w", encoding="utf-8") as f:
        f.write("# cid\tcls\tfamily\tanchor\tnote\n")
        for cid, cls, fam, note in rows:
            f.write("%s\t%s\t%s\t%s\t%s\n" % (cid, cls, fam, ANCHOR.get(fam, "-"), note))
    print("  写出 %d 份 .c -> %s" % (len(sources), os.path.relpath(OUT_DIR)))
    print("  写出清单 %s（%d 行数据行）与覆盖点表 cover.extra.tsv" % (os.path.relpath(MANIFEST), len(rows)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
