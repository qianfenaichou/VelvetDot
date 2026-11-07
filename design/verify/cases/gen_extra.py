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
     生成结束自检并打印实测行数。另有 `negative-legal`（合法对照，must-not-trap）3 例：
     它**不计入** negative 配额，判据是 HIT GOOD TRAP + 值断言（反向证明负例不是靠
     「一律陷入」通过的）；94-run-extra.sh 的 negative 判据只认 cls=="negative"，故另立一类。
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


def SETVLA(n, ta=0, ma=0):
    """vsetvli 同时给 vl 与 vta/vma（e8,m1）：`vl=0 且 vta=1` 这类组合的唯一表达方式。

    为什么不用 `csrw vtype`：vtype（0xC21）在 RVV 里是**只读 CSR**，写它会先触发一条
    与 vdot 无关的非法指令，测不到 vdot 是否旁路 Mgu 的 tail/agnostic 路径。这里改用
    vsetvli 的 tu/ta、mu/ma 后缀正交地构造 vtype 的 bit6/bit7（SPEC §1.1 的 vta/vma），
    AVL 直接给 n，因此 `SETVLA(0, ta=1)` 得到 vtype=0x40 且 vl=0。
    """
    return {"op": "vl_vt", "n": n, "ta": ta, "ma": ma}


def RSV(n):
    return {"op": "rs_vstart", "n": n}


def CLRV():
    return {"op": "clr_vstart"}


def VSOFF():
    return {"op": "vs_off"}


def VSON():
    return {"op": "vs_on"}


def VSINIT():
    """mstatus.VS=Initial(01)：先清 0x600（bit10:9）再置 0x200，得到 01 而不是 11。"""
    return {"op": "vs_initial"}


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
# ②-bis 扩展重叠 vdot-ov +26 例：把别名形态推到上面 30 例够不到的角落。
#   上面 30 例的形态是「vd==vs2 / vd==vs1 / vs1==vs2」三选一，且操作数固定 v1/v2/v3、
#   旧值固定 0xAB、全程 vl=16。本组补五类缺口：
#     alias3      三同址 vd==vs1==vs2（含 v0/v31 边界与 19 位累加器上下界）
#     alias-hi96  128 位全 1 的旧值 + 别名（高 96 位清零 + 旧值不得残留）
#     alias-lanehi lane8..15 干扰 + 别名（误用高位时给可判别的偏差）
#     alias-wb    同一 vd 的连续写回且该 vd 就是源（写后读就地更新）
#     alias-vl    vl=0/1/4/扫掠 与别名交叉（vl 与语义解耦）
#   期望值仍逐条由 M.vdot_vv() 算出（本文件不写任何点积常量）。
# ---------------------------------------------------------------------------
# 2b.1 三同址：同一寄存器索引同时占满写口与两个读口——源必须全在写之前取完
add("xo3_tri_v5", "vdot-ov", "alias3",
    "三同址 vd=vs1=vs2=v5：S 退化为平方和 1104；就地更新不得把新值再当源读",
    [L(5, "A_pos"), VD(5, 5, 5), RD(5)])
add("xo3_tri_v0", "vdot-ov", "alias3",
    "三同址落在 v0：v0 必须作普通寄存器参与运算与写回；A_min 全 -128 使 S=131072（19 位累加器上界）",
    [L(0, "A_min"), VD(0, 0, 0), RD(0)])
add("xo3_tri_v31", "vdot-ov", "alias3",
    "三同址落在 v31：最高索引的读/写口译码边界；A_rand 平方和 43285 为奇数，抓高位泄漏/部分写",
    [L(31, "A_rand"), VD(31, 31, 31), RD(31)])

# 2b.2 双址 + 边界寄存器：vd 与一侧源同址，另一侧取对侧边界（v0 / v31 配对）
add("xo3_p_vdvs1_v0", "vdot-ov", "alias3",
    "{vd,vs1}=v0、vs2=v31：写口/vs1 读口同址落在边界寄存器，S 为负值同时钉住 sext32 写回",
    [L(0, "A_rand"), L(31, "B_rand"), VD(0, 0, 31), RD(0)])
add("xo3_p_vdvs2_v0", "vdot-ov", "alias3",
    "{vd,vs2}=v0、vs1=v31：写口/vs2 读口同址；若 vs2 读到写回后的 vd 会得到另一个值",
    [L(0, "B_pos"), L(31, "A_pos"), VD(0, 31, 0), RD(0)])
add("xo3_p_src_v0", "vdot-ov", "alias3",
    "{vs1,vs2}=v0 两读口同址、vd=v31 旧值预填 0xCD：源同址 + 旧 vd 非语义输入 + v0/v31 双边界",
    [VMV(31, 0xCD), L(0, "A_mix"), VD(31, 0, 0), RD(31)])
add("xo3_p_vdvs1_v31", "vdot-ov", "alias3",
    "{vd,vs1}=v31、vs2=v0：vd==vs1 的最高寄存器配对，S 为负值小量",
    [L(31, "A_asym"), L(0, "B_asym"), VD(31, 31, 0), RD(31)])
add("xo3_p_vdvs2_v31", "vdot-ov", "alias3",
    "{vd,vs2}=v31、vs1=v0：A_ext×B_ext2 使 S=-130048（19 位累加器最坏负值）落在最高寄存器上",
    [L(31, "B_ext2"), L(0, "A_ext"), VD(31, 0, 31), RD(31)])
add("xo3_p_src_v31", "vdot-ov", "alias3",
    "{vs1,vs2}=v31 两读口同址、vd=v0 旧值预填 0x5A：源同址下旧 vd 不参与，写口落在下边界",
    [VMV(0, 0x5A), L(31, "A_neg"), VD(0, 31, 31), RD(0)])

# 2b.3 128 位全 1 旧值 + 别名：vta/vma 与旧值都不得让 bits[127:32] 残留
add("xo3_hi_ff_tri", "vdot-ov", "alias-hi96",
    "v9 的 128 位全 1（vmv 0xFF 覆盖 16 lane）后三同址：两个源都是 -1，S=8，"
    "写回后 bits[127:32] 必须全 0（全 1 旧值不得残留）",
    [VMV(9, 0xFF), VD(9, 9, 9), RD(9)])
add("xo3_hi_ff_vs2", "vdot-ov", "alias-hi96",
    "vd==vs2=v7 预置全 1（vs2 每 lane=-1）、vs1=v1=A_lanehi：S=-8；"
    "保留旧高 96 位会得 0xFFFF…FFF8，误取 lane8..15 会得 0x3F8",
    [VMV(7, 0xFF), L(1, "A_lanehi"), VD(7, 1, 7), RD(7)])
add("xo3_hi_ff_vs1", "vdot-ov", "alias-hi96",
    "镜像到 vs1 读口：vd==vs1=v8 全 1（vs1 每 lane=-1）、vs2=v2=B_lanehi：S=-16；"
    "单侧 vs1 通路的高 96 位污染与清零必须独立正确",
    [VMV(8, 0xFF), L(2, "B_lanehi"), VD(8, 8, 2), RD(8)])
add("xo3_hi_ff_src", "vdot-ov", "alias-hi96",
    "两源同址 v0 且全 1（vs1==vs2==v0）、vd=v31 预填 0xEE：S=8；"
    "同时钉住「源 lane8..15 全 1 不进累加器」与「目的旧高半必须被覆盖」",
    [VMV(0, 0xFF), VMV(31, 0xEE), VD(31, 0, 0), RD(31)])

# 2b.4 lane8..15 干扰 + 别名：误用高 lane 时的偏差是可判别常量
add("xo3_lane_tri_ovf", "vdot-ov", "alias-lanehi",
    "三同址 v5 且 A_lanehi 高 lane 全 -128：正确 S=8；误用 lane8..15 得 131080，"
    "超过 19 位有符号上界 131071，任何低位截断都无法偶然对齐",
    [L(5, "A_lanehi"), VD(5, 5, 5), RD(5)])
add("xo3_lane_v0_vs2", "vdot-ov", "alias-lanehi",
    "v0 装 B_lanehi 且 vd==vs2=v0：正确 S=16，误用高 lane 得 -130032（偏差 -130048）",
    [L(0, "B_lanehi"), L(1, "A_lanehi"), VD(0, 1, 0), RD(0)])
add("xo3_lane_v31_vs1", "vdot-ov", "alias-lanehi",
    "v31 装 B_lanehi 且 vd==vs1=v31、vs2=v30=A_ext：正确 S=-8，误用高 lane 得 18788",
    [L(31, "B_lanehi"), L(30, "A_ext"), VD(31, 31, 30), RD(31)])
add("xo3_lane_src_pair", "vdot-ov", "alias-lanehi",
    "两源同址 v4=B_lanehi、vd=v5 预填 0xAB：正确 S=32，误用高 lane 得 129064"
    "（仍在 19 位内 ⇒ 排除「溢出截断恰好掩盖高位误用」）",
    [VMV(5, 0xAB), L(4, "B_lanehi"), VD(5, 4, 4), RD(5)])

# 2b.5 连续写回且 vd 就是源：第二次必须看到第一次的结果（写后读就地更新）
add("xo3_wb2_vdvs2", "vdot-ov", "alias-wb",
    "两次写同一 vd 且 vd==vs2：第二条必须把第一条结果当 vs2；缺失第二条或读到写前旧值时终值不同",
    [L(1, "A_pos"), L(2, "B_pos"), VD(2, 1, 2), VD(2, 1, 2), RD(2)])
add("xo3_wb3_rotate", "vdot-ov", "alias-wb",
    "三次写同一 vd=v3，v3 依次以 vs1、vs2、vs1 身份被读：别名角色轮换下的写后读",
    [L(3, "A_ext"), L(1, "A_mix"), L(2, "B_three"),
     VD(3, 3, 1), VD(3, 2, 3), VD(3, 3, 2), RD(3)])
add("xo3_wb2_v0", "vdot-ov", "alias-wb",
    "v0 边界 + 两次写回 vd==vs2=v0：边界寄存器上的第二次写回同样必须看到第一次结果",
    [L(0, "B_ext"), L(1, "A_ext"), VD(0, 1, 0), VD(0, 1, 0), RD(0)])
add("xo3_wb2_v31", "vdot-ov", "alias-wb",
    "v31 边界 + 两次写回且别名角色互换（先 vd==vs1、后 vd==vs2）：第二次必须读到第一次结果",
    [L(31, "A_asym"), L(30, "B_asym"), VD(31, 31, 30), VD(31, 30, 31), RD(31)])
add("xo3_wb4_pingpong", "vdot-ov", "alias-wb",
    "v5/v6 乒乓：4 条 vdot 交替写回且互为源，终值两条都要读回（跨寄存器写回顺序）",
    [L(5, "A_pos"), L(6, "B_pos"), VD(5, 5, 6), VD(6, 5, 6),
     VD(5, 6, 5), VD(6, 6, 5), RD(5), RD(6)])

# 2b.6 vl 与别名交叉：vl 只影响 tail 语义，不影响 vdot 的全写
add("xo3_vl0", "vdot-ov", "alias-vl",
    "vl=0 时的 vd==vs2 重叠：仍算 lane0..7 并全写 vd（含高 96 位清零），"
    "按 RVV 跳过写回会读到旧 vs2 低字",
    [L(1, "A_mix"), L(3, "B_three"), SETVL(0), VD(3, 1, 3), RD(3)])
add("xo3_vl1", "vdot-ov", "alias-vl",
    "vl=1 下的 vd==vs2：只激活 1 个元素也必须算满 8 lane，结果与 vl=16 逐位相同",
    [L(1, "A_mix"), L(3, "B_three"), SETVL(1), VD(3, 1, 3), RD(3)])
add("xo3_vl4_tri", "vdot-ov", "alias-vl",
    "vl=4 下的三同址 v5：S=130052，必须与 vl=16 的同形态结果逐位一致（全写语义）",
    [L(5, "A_ext"), SETVL(4), VD(5, 5, 5), RD(5)])

# vl 扫掠：每次先用 vl=16 重新装载（vle8.v 受当前 vl 约束），再用目标 vl 执行
_ops_vls = []
for _v in (0, 1, 7, 8, 15):
    _ops_vls += [SETVL(16), L(1, "A_mix"), L(3, "B_three"), SETVL(_v), VD(3, 1, 3), RD(3)]
add("xo3_vl_sweep", "vdot-ov", "alias-vl",
    "同一 vd==vs2 别名形态在 vl=0/1/7/8/15 各执行一次，五次读回必须全相同"
    "（7 不足 8 lane、8 恰好 8 lane、15 越过 8 lane）", _ops_vls)

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
# ③-bis 扩展流水 vdot-pl +50 例：现有 48 例的系统性缺口是「结果值不互异」与
#   「只在程序序的一个点上观测」。本组按下面 10 个维度补齐，每条都能独立失败：
#     bb-distinct   背靠背组内每组数据互异（相邻结果互换/错位立刻失配）
#     vd-reuse      同 vd 两次写之间夹 k 条独立 vdot（k=0..8，参数化）
#     raw-mid       链中读回、双链交错、自平方、vd 落在 vs2 读口
#     raw-cross     vdot→vmacc / vdot→vadd→vdot 的跨指令类真依赖
#     war           vdot 发射后覆写它的源（vadd / vmacc / vle8.v），窗口深度 1..4
#     waw-x         跨指令类的同 vd 多写（vadd/vmacc 与 vdot 两个写回源）
#     vl-imm        在背靠背/依赖链内部翻转 vl
#     vtype-imm     在背靠背/依赖链内部翻转 vta/vma（vdot 不用，vmacc 用）
#     rotate        vd/vs1/vs2 三者独立轮转（含拉丁方、递减、回绕）
#     cross-class   vdot/vadd/vmacc 三类指令的依赖链与读口连占
#   期望值仍逐条由 M.vdot_vv() 算出；vadd/vmacc 只用于制造依赖与占用写回口。
# ---------------------------------------------------------------------------
# 3.13 背靠背互异结果组：k 条 vdot 各用一组独立数据（现有 xp_bb/xp_hi 全组同值）
_BDPAIRS = [
    ("A_pos", "B_pos"), ("A_neg", "B_one"), ("A_mix", "B_three"), ("A_max", "B_max"),
    ("A_min", "B_min"), ("A_ext", "B_ext2"), ("A_asym", "B_asym"), ("A_lanehi", "B_lanehi"),
]
for _k in (2, 4, 6, 8):
    _ops = []
    for _i in range(_k):
        _ops += [L(2 * _i + 1, _BDPAIRS[_i][0]), L(2 * _i + 2, _BDPAIRS[_i][1])]
    for _i in range(_k):
        _ops.append(VD(20 + _i, 2 * _i + 1, 2 * _i + 2))
    _ops += [RD(20 + _i) for _i in range(_k)]
    add("xp_bd%d" % _k, "vdot-pl", "bb-distinct",
        "%d 条背靠背 vdot，每条一组独立数据 ⇒ %d 个期望值两两互异"
        "（结果与 vd 错位/相邻互换即刻失配）" % (_k, _k), _ops)

# 递减 vd 且操作数顺序与 vd 顺序反相关：递增序列会掩盖 vd 索引位互换
add("xp_bdrev", "vdot-pl", "bb-distinct",
    "4 条背靠背按 vd=27,26,25,24 递减写回，操作数顺序与 vd 顺序反相关"
    "（防止「顺带递增」掩盖 vd 索引位互换）",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_mix"), L(4, "B_three"),
     L(5, "A_min"), L(6, "B_min"), L(7, "A_ext"), L(8, "B_ext2"),
     VD(27, 1, 2), VD(26, 3, 4), VD(25, 5, 6), VD(24, 7, 8),
     RD(24), RD(25), RD(26), RD(27)])

# 3.14 同 vd 复用：两次写 v3 之间夹 k 条独立 vdot（k=0 即真正的 0-bubble WAW）
for _k in (0, 1, 2, 3, 4, 6, 8):
    _ops = [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
            L(7, "A_min"), L(8, "B_min"), VD(3, 1, 2)]
    for _i in range(_k):
        _ops.append(VD(10 + _i, 1, 2) if _i % 2 == 0 else VD(10 + _i, 4, 5))
    _ops += [VD(3, 7, 8), RD(3)] + [RD(10 + _i) for _i in range(_k)]
    add("xp_reuse%d" % _k, "vdot-pl", "vd-reuse",
        "同 vd 两次写之间夹 %d 条独立 vdot（共 %d 次写回在飞）：终值必须是后写"
        % (_k, _k + 2), _ops)

# 3.15 RAW 变体：链中读回 / 双链交错 / 自平方 / vd 落在 vs2 读口
add("xp_rwmid", "vdot-pl", "raw-mid",
    "RAW 链中途读回（读回序列本身会改 vl 到 4 再改回），不破坏后续写后读",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), RD(3), VD(4, 3, 2), RD(4)])
add("xp_rwpar", "vdot-pl", "raw-mid",
    "两条独立 RAW 链交错在飞（v3 链与 v4 链各 2 跳），两条终值互不串数据",
    [L(1, "A_pos"), L(2, "B_pos"), L(5, "A_mix"), L(6, "B_three"),
     VD(3, 1, 2), VD(4, 5, 6), VD(3, 3, 2), VD(4, 4, 6), RD(3), RD(4)])
add("xp_rwsq", "vdot-pl", "raw-mid",
    "自平方链：vd 同时占 vs1 与 vs2 两个读口（同一个寄存器），连续两跳",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), VD(3, 3, 3), VD(3, 3, 3), RD(3)])
add("xp_rwswap", "vdot-pl", "raw-mid",
    "链中让 vd 落在 vs2 读口（vdot v3←(v1,v3)）：vd 作 vs2 时写后读通路不破坏；"
    "点积对 vs1/vs2 可交换，故本用例只证「vd 在 vs2 读口时链成立」",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), VD(3, 1, 3), RD(3)])

# 3.16 跨指令类真依赖：vdot 结果被 vmacc / vadd 消费，消费结果又被下一条 vdot 消费
add("xp_rwvmacc", "vdot-pl", "raw-cross",
    "vdot→vmacc 同 vd 累积链：两条 vmacc 各自读上一跳结果并回写同一 vd（hi96 非零，只断言 lo32）",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), VM(3, 3, 2), VM(3, 3, 2), RD(3, hi=False)])
add("xp_rwvadd", "vdot-pl", "raw-cross",
    "vdot→vadd→vdot 三跳依赖：v3=vdot(A_pos,B_pos)，v10=vadd(v3,A_ext)，v4=vdot(v10,B_pos)，"
    "三跳结果全部断言（v10 只断言 lo32）",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"),
     VD(3, 1, 2), VA(10, 3, 6), VD(4, 10, 2), RD(3), RD(4), RD(10, hi=False)])

# 3.17 WAR：vdot 发射后覆写它的源寄存器，第二条 vdot 必须读到新值
add("xp_war_vadd", "vdot-pl", "war",
    "WAR：vdot v3←(v1,v2) 后 vadd 覆写 v1，第二条 vdot 必须用新 v1；"
    "旧 v1 与新 v1 两侧结果不同，任一读口时序错都有一侧失配",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VD(3, 1, 2), VA(1, 6, 7), VD(4, 1, 2), RD(3), RD(4)])
add("xp_war_vmacc", "vdot-pl", "war",
    "WAR 的覆写者是 vmacc（与 vdot 同处 VIMac 写回路径）：v1+=v6*v7 后第二条 vdot 必须读到新 v1",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VD(3, 1, 2), VM(1, 6, 7), VD(4, 1, 2), RD(3), RD(4)])
add("xp_war_vs2", "vdot-pl", "war",
    "WAR 落在 vs2 读口：vadd 覆写 v2，第二条 vdot 必须用新 v2（用旧 v2 会得另一个值）",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VD(3, 1, 2), VA(2, 6, 7), VD(4, 1, 2), RD(3), RD(4)])
add("xp_war_load", "vdot-pl", "war",
    "WAR 的覆写来自向量装载（装载单元 vs 已在飞的乘法单元）：vle8.v 覆写 v1 后第二条 vdot 用新 v1",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), L(1, "A_ext"), VD(4, 1, 2), RD(3), RD(4)])
add("xp_war_deep", "vdot-pl", "war",
    "WAR 窗口深度 4：4 条在飞 vdot 全读 v1，vadd 覆写 v1，再发第 5 条；"
    "前 4 条必须都是旧 v1 的结果，第 5 条是新 v1 的结果",
    [L(1, "A_pos"), L(2, "B_pos"), L(7, "A_ext"), L(8, "B_ext2"),
     VD(3, 1, 2), VD(4, 1, 2), VD(5, 1, 2), VD(6, 1, 2),
     VA(1, 7, 8), VD(10, 1, 2), RD(3), RD(4), RD(5), RD(6), RD(10)])

# 3.18 跨指令类 WAW：同一 vd 被 vadd/vmacc/vmv 与 vdot 连续写（两个写回源）
add("xp_wawx_vdlast", "vdot-pl", "waw-x",
    "vadd 先写 v3、vdot 后写 v3：vdot 必须胜出，且不读旧 vd、不被在飞的上一条非 vdot 写遮挡",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VA(3, 6, 7), VD(3, 1, 2), RD(3)])
add("xp_wawx_valast", "vdot-pl", "waw-x",
    "vdot 先写 v3、vadd 后写 v3：vadd 必须胜出（vdot 的写不得被错序排到 vadd 之后）",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VD(3, 1, 2), VA(3, 6, 7), RD(3, hi=False)])
add("xp_wawx_vmlast", "vdot-pl", "waw-x",
    "vmacc 读 vdot 结果再回写同一 vd（RAW+WAW 同 vd）：vmacc 必须拿到 vdot 刚写的结果",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2), VM(3, 3, 2), RD(3, hi=False)])
add("xp_wawx_triple", "vdot-pl", "waw-x",
    "三连写同 vd 跨两类运算 vdot→vadd→vdot：中间 vadd 的写不得压过最后一次 vdot",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
     L(6, "A_ext"), L(7, "B_ext2"), VD(3, 1, 2), VA(3, 6, 7), VD(3, 4, 5), RD(3)])
add("xp_wawx_mix", "vdot-pl", "waw-x",
    "标量广播 + vdot + vadd 三写同 vd：终值必须是 vadd 的，0x5A 预填与 vdot 的写都被覆盖",
    [VMV(3, 0x5A), L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), L(7, "B_ext2"),
     VD(3, 1, 2), VA(3, 6, 7), RD(3, hi=False)])

# 3.19 vl 在背靠背/依赖链内部翻转（装载一律先回到 vl=16）
add("xp_vl0bb", "vdot-pl", "vl-imm",
    "vl=0 下 4 条背靠背 vdot 全部全写 128 位：任何「vl=0 不写回/半写」实现 4 个读回点全失败",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_neg"), L(4, "B_one"),
     L(5, "A_mix"), L(6, "B_three"), L(7, "A_max"), L(8, "B_max"), SETVL(0),
     VD(20, 1, 2), VD(21, 3, 4), VD(22, 5, 6), VD(23, 7, 8),
     RD(20), RD(21), RD(22), RD(23)])
add("xp_vl0mid", "vdot-pl", "vl-imm",
    "vl 在 3 条互不依赖的背靠背 vdot 之间切换 16→0→16：三个结果与 vl 无关且互不串",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_ext"), L(4, "B_ext2"),
     L(5, "A_min"), L(6, "B_min"),
     VD(20, 1, 2), SETVL(0), VD(21, 3, 4), SETVL(16), VD(22, 5, 6),
     RD(20), RD(21), RD(22)])
add("xp_vlswap", "vdot-pl", "vl-imm",
    "vl=1/4/7/16 四档逐条切换，4 条 vdot 各用不同操作数（vl=16 档也在内），结果与 vl 全部无关",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_neg"), L(4, "B_one"),
     L(5, "A_mix"), L(6, "B_three"), L(7, "A_max"), L(8, "B_max"),
     SETVL(1), VD(3, 1, 2), SETVL(4), VD(4, 3, 4),
     SETVL(7), VD(5, 5, 6), SETVL(16), VD(6, 7, 8), RD(3), RD(4), RD(5), RD(6)])
add("xp_vlchain", "vdot-pl", "vl-imm",
    "RAW 链内部 vl 连变 2→0→16：vl=0 那一跳若被抑制写回，整条链立即断开",
    [L(1, "A_pos"), L(2, "B_pos"), SETVL(2), VD(3, 1, 2),
     SETVL(0), VD(3, 3, 2), SETVL(16), VD(3, 3, 2), RD(3)])
add("xp_vlhi", "vdot-pl", "vl-imm",
    "vl=3 与 vl=0（都 <8 lane，tail 区域非空）下读回：hi96 必须仍恒零（最易被 Mgu tail 路径污染）",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
     SETVL(3), VD(3, 1, 2), RD(3), SETVL(0), VD(4, 4, 5), RD(4)])

# 3.20 vta/vma 在背靠背/依赖链内部翻转（vdot 旁路 Mgu，vmacc 依赖 Mgu）
add("xp_vtbb4", "vdot-pl", "vtype-imm",
    "4 条背靠背 vdot 前逐条切换 vta/vma（0x00/0x40/0x80/0xC0）；"
    "数据与 xp_bd4 相同 ⇒ 期望常量逐项相同即「vta/vma 不影响结果」的直接证据",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_neg"), L(4, "B_one"),
     L(5, "A_mix"), L(6, "B_three"), L(7, "A_max"), L(8, "B_max"),
     SETVT(0x00), VD(20, 1, 2), SETVT(0x40), VD(21, 3, 4),
     SETVT(0x80), VD(22, 5, 6), SETVT(0xC0), VD(23, 7, 8),
     RD(20), RD(21), RD(22), RD(23)])
add("xp_vtchain", "vdot-pl", "vtype-imm",
    "vta/vma 在 RAW 链内部变化（ta,ma→vta=1→vta=1,vma=1）：链值与 xp_vlchain 同数据同终值",
    [L(1, "A_pos"), L(2, "B_pos"), VD(3, 1, 2),
     SETVT(0x40), VD(3, 3, 2), SETVT(0xC0), VD(3, 3, 2), RD(3)])
add("xp_vtta1", "vdot-pl", "vtype-imm",
    "vta=1 且旧 vd 预填 0x5A：高 96 位既不得是 agnostic 的 0xFF、也不得保留 0x5A，必须为 0",
    [VMV(3, 0x5A), L(1, "A_pos"), L(2, "B_pos"), SETVT(0x40), VD(3, 1, 2), RD(3)])
add("xp_vtvl0", "vdot-pl", "vtype-imm",
    "vl=0 且 vta=1（tail 覆盖全部 16 lane）时仍全写 128 位：旧 vd 0x5A 被完全覆盖、"
    "高 96 位为 0，证明 vdot 完全旁路 Mgu 的 tail/agnostic 路径",
    [VMV(3, 0x5A), L(1, "A_pos"), L(2, "B_pos"), SETVLA(0, ta=1), VD(3, 1, 2), RD(3)])
add("xp_vtmix", "vdot-pl", "vtype-imm",
    "vta/vma 在 vdot 与 vmacc 交错之间切换（vdot 走旁路、vmacc 走 Mgu）：两个 vdot 结果与 vtype 无关",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
     L(6, "A_ext"), L(7, "B_ext2"), VMV(10, 0x11),
     VD(3, 1, 2), SETVT(0xC0), VM(10, 6, 7), SETVT(0x00), VD(4, 4, 5),
     RD(3), RD(4)])

# 3.21 轮转：vd / vs1 / vs2 三者独立轮转（固定的端口→寄存器映射会在此暴露）
_XP_ROT3 = [  # 3×3 拉丁方：vd=20+row, vs1=1+.., vs2=5+..
    (20, 1, 5), (21, 2, 6), (22, 3, 7),
    (20, 2, 7), (21, 3, 5), (22, 1, 6),
    (20, 3, 6), (21, 1, 7), (22, 2, 5),
]
_ops = [L(1, "A_pos"), L(2, "A_neg"), L(3, "A_mix"),
        L(5, "B_pos"), L(6, "B_one"), L(7, "B_three")]
_ops += [VD(_vd, _s1, _s2) for _vd, _s1, _s2 in _XP_ROT3]
_ops += [RD(20), RD(21), RD(22)]
add("xp_rot3", "vdot-pl", "rotate",
    "9 条 vdot 的三元组 (vd,vs1,vs2) 三向轮转，每个 vd 被写 3 次且终值互异", _ops)

_XP_ROT4 = [  # 4×4 拉丁方：每行 4 个三元组两两不同
    (20, 1, 5), (21, 2, 6), (22, 3, 7), (23, 4, 8),
    (20, 2, 7), (21, 3, 8), (22, 4, 5), (23, 1, 6),
    (20, 3, 6), (21, 4, 7), (22, 1, 8), (23, 2, 5),
]
_ops = [L(1, "A_pos"), L(2, "A_neg"), L(3, "A_mix"), L(4, "A_max"),
        L(5, "B_pos"), L(6, "B_one"), L(7, "B_three"), L(8, "B_max")]
_ops += [VD(_vd, _s1, _s2) for _vd, _s1, _s2 in _XP_ROT4]
_ops += [RD(20), RD(21), RD(22), RD(23)]
add("xp_rot4", "vdot-pl", "rotate",
    "12 行 4×4 拉丁方：4 个 vd × 4 个 vs1 × 4 个 vs2，行行组合不同，4 个终值互异", _ops)

add("xp_rotwrap", "vdot-pl", "rotate",
    "轮转回绕：vd 3→4→5→3→4→5 两轮，第二轮对同一 vd 的写（间隔 3 条）必须胜出第一轮",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
     L(7, "A_min"), L(8, "B_min"),
     VD(3, 1, 2), VD(4, 4, 5), VD(5, 7, 8), VD(3, 4, 5), VD(4, 7, 8), VD(5, 1, 2),
     RD(3), RD(4), RD(5)])

_XP_ROT8 = [  # 8 个 vd 同时占用 + 两个源口各自轮转
    (20, 1, 5), (21, 2, 6), (22, 3, 7), (23, 4, 8),
    (24, 2, 5), (25, 3, 6), (26, 4, 7), (27, 1, 8),
]
_ops = [L(1, "A_pos"), L(2, "A_neg"), L(3, "A_mix"), L(4, "A_max"),
        L(5, "B_pos"), L(6, "B_one"), L(7, "B_three"), L(8, "B_max")]
_ops += [VD(_vd, _s1, _s2) for _vd, _s1, _s2 in _XP_ROT8]
_ops += [RD(20 + _i) for _i in range(8)]
add("xp_rot8", "vdot-pl", "rotate",
    "8 个不同 vd(20..27) 同时在飞（覆盖 vd 索引全部有效位），8 个结果两两互异；"
    "写回目的地解码不是 3 位截断或相邻别名", _ops)

add("xp_rotread", "vdot-pl", "rotate",
    "读写交替轮转：每条 vdot 后立刻读回，4 个读回值互异且 vd 复用跨读回 ⇒ "
    "证明读回恰好发生在写回之后",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_ext"), L(5, "B_ext2"),
     VD(3, 1, 2), RD(3), VD(4, 4, 5), RD(4), VD(3, 4, 5), RD(3), VD(4, 1, 2), RD(4)])
add("xp_rotmix", "vdot-pl", "rotate",
    "轮转 + vdot→vadd 短依赖：每次 vadd 读前一条 vdot 的结果，vdot 的轮转写与 vadd 的写交叠",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_mix"), L(5, "A_ext"),
     VD(20, 1, 2), VA(10, 20, 5), VD(21, 2, 3), VA(11, 21, 5),
     VD(20, 3, 5), VD(21, 1, 3),
     RD(20), RD(21), RD(10, hi=False), RD(11, hi=False)])

# 3.22 跨指令类交错：三类指令共享 VIMac 流水/写回口，并制造跨类旁路
add("xp_ilvd_3way", "vdot-pl", "cross-class",
    "四跳全依赖链横跨三类指令 vdot→vadd→vmacc→vdot，三类轮流占用同一 VIMac 流水与写回口",
    [L(1, "A_pos"), L(2, "B_pos"), L(6, "A_ext"), VMV(11, 0x00),
     VD(3, 1, 2), VA(10, 3, 6), VM(11, 10, 2), VD(12, 11, 2),
     RD(3), RD(12), RD(10, hi=False)])
_ops = [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_ext"), L(4, "B_ext2")]
for _i in range(4):
    _s1, _s2 = (1, 2) if _i % 2 == 0 else (3, 4)
    _ops += [VD(20 + _i, _s1, _s2), VA(10 + _i, _s1, _s2)]
_ops += [RD(20 + _i) for _i in range(4)] + [RD(10 + _i, hi=False) for _i in range(4)]
add("xp_ilvd_alt8", "vdot-pl", "cross-class",
    "8 条 vdot/vadd 交替，每条 vadd 与相邻 vdot 共享同一源对（读端口被两类指令连续抢占）；"
    "4 个 vdot 结果按奇偶交替，奇偶错位即失配", _ops)

_ops = [L(1, "A_pos"), L(2, "B_pos")] + [VMV(10 + _i, 0x11 + _i) for _i in range(4)]
for _i in range(4):
    _ops += [VD(3 + _i, 1, 2), VM(10 + _i, 3 + _i, 2)]
_ops += [RD(3 + _i) for _i in range(4)] + [RD(10 + _i, hi=False) for _i in range(4)]
add("xp_ilvd_vmacc4", "vdot-pl", "cross-class",
    "4 组 vdot→vmacc 短链交错：每个 vmacc 读上一条 vdot 的结果并写自己的 vd，"
    "8 次写回交替占用写回口", _ops)
add("xp_ilvd_double", "vdot-pl", "cross-class",
    "同一 vs1 被 vdot/vadd/vdot 三连读（读端口 3 连占用），中间 vadd 的结果又被第二条 vdot 消费",
    [L(1, "A_pos"), L(2, "B_pos"), L(5, "A_ext"), L(6, "A_ext"),
     VD(3, 1, 2), VA(10, 1, 6), VD(4, 1, 5), RD(3), RD(4), RD(10, hi=False)])
add("xp_ilvd_burst", "vdot-pl", "cross-class",
    "vadd 插在背靠背组中间并消费组内第一条 vdot 的结果（跨一条在飞 vdot 的旁路），"
    "其余 vdot 仍必须背靠背正确",
    [L(1, "A_pos"), L(2, "B_pos"), L(4, "A_mix"), L(5, "B_three"),
     L(6, "A_ext"), L(7, "A_max"), L(8, "B_max"),
     VD(20, 1, 2), VD(21, 4, 5), VA(10, 20, 6), VD(22, 7, 8),
     RD(20), RD(21), RD(22), RD(10, hi=False)])
add("xp_ilvd_2src", "vdot-pl", "cross-class",
    "3 条背靠背 vdot 共享同一 vs2、vs1 逐条不同：一个读口连占、另一个读口逐条换，不串源",
    [L(1, "A_pos"), L(2, "B_pos"), L(3, "A_neg"), L(4, "A_mix"),
     VD(20, 1, 2), VD(21, 3, 2), VD(22, 4, 2), RD(20), RD(21), RD(22)])

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

# ---------------------------------------------------------------------------
# ④-bis 扩展负例 +16：上面 41 条的缺口是「维度两两组合」与「状态构造顺序」。
#   * vstart 只取过 1/2/3/4/7/8/15（bit4~bit6 从未置位）⇒ 加 vstart=64；
#   * vstart×SEW / vstart×LMUL 的 csrw 写在 vsetvli **之前**，而 vsetvl 会清 vstart
#     （NEMU vcommon.c:128、RTL Rob.scala resetVstart）⇒ 本组把 csrw 一律放到最后一次
#     vsetvli 之后，才真正覆盖 vstart≠0 与 SEW/LMUL 同时不满足；
#   * vtype 保留位 bit[62:8] 与保留 LMUL=0b100 从未单独验证；
#   * keep-vl（rd=x0,rs1=x0）从未出现过；
#   * VS=OFF 只与 vstart / vl=0 组合过，未与 SEW/LMUL/vill 组合；
#   * 非法优先于 vl=0 只有 SEW/VS/vstart 三维，缺 LMUL 与 vm=0。
# ---------------------------------------------------------------------------
neg("xn_vstart64_vl0",
    "vstart=64（2^6，需 vstart 的 bit6）且 vl=0：非法判定必须用完整 7 位 vstart 字段，"
    "且优先于 vl=0 全写（≤6 位截断会把 64 读成 0 而漏判）",
    [("vsetvli_vl0", "e8", "m1"), ("vstart", 64)], enc_vdot(3, 1, 2))
neg("xn_vstart1_e16_ord",
    "SEW=e16 且 vstart=1，csrw vstart 放在最后一次 vsetvli 之后"
    "（vsetvl 会把 vstart 清 0，写在前面的旧用例在 vdot 处其实 vstart=0）",
    [("vsetvli", "e16", "m1"), ("vstart", 1)], enc_vdot(3, 1, 2))
neg("xn_vstart1_mf2_ord",
    "LMUL=mf2（vlmul=111）且 vstart=1，csrw 在 vsetvli 之后：分数 LMUL 与 vstart≠0 独立成立",
    [("vsetvli", "e8", "mf2"), ("vstart", 1)], enc_vdot(3, 1, 2))
neg("xn_vstart1_m2_ord",
    "LMUL=m2 且 vstart=1，操作数按 m2 对齐（vd=4,vs1=2,vs2=0），csrw 在 vsetvli 之后："
    "陷入不得来自寄存器对齐非法",
    [("vsetvli", "e8", "m2"), ("vstart", 1)], enc_vdot(4, 2, 0))
neg("xn_vtype_rsvd8",
    "vtype 保留位 bit8=1（rs2=0x100，紧邻 vma）：vsetvl 后 vill=1、vl=0，vdot 必须陷入；"
    "漏判保留位会留下 e8,m1 的合法状态而静默执行",
    [("vill", 0x100)], enc_vdot(3, 1, 2))
neg("xn_vtype_rsvd62",
    "vtype 保留位 bit62=1（rs2=2^62，保留字段最高位）：vsetvl 后 vill=1、vl=0；"
    "该位可捕获 rs2 被截成 32 位、reserved.orR 只接低位、只查 bit[11:8] 等实现",
    [("vill", 1 << 62)], enc_vdot(3, 1, 2))
neg("xn_vlmul_rsvd100",
    "vlmul=0b100 保留编码配 vsew=e8：vsetvl 后 vill=1（Vsetu 的 lmulIllegal 路径），"
    "vdot 必须陷入；现有 0x24 同时含保留 vsew，无法区分是哪个字段触发",
    [("vill", 0x04)], enc_vdot(3, 1, 2))
neg("xn_vill_keepl_vlmax",
    "keep-vl（rd=x0,rs1=x0）把 VLMAX 从 32(m2) 改成 16(m1)：vsetvl 必须判非法，vill=1、vl=0",
    [("vsetvli", "e8", "m2"), ("vsetvli_keep", "e8", "m1")], enc_vdot(3, 1, 2))
neg("xn_vs_off_e16",
    "SEW=e16 且 VS=OFF：译码级 VS 门（DecodeUnit）与 vdot 的 SEW 谓词（VecExceptionGen）"
    "是两个独立非法源，组合可抓「只修好一处」的回归",
    [("vsetvli", "e16", "m1"), ("vs_off", 0)], enc_vdot(3, 1, 2))
neg("xn_vs_off_m2",
    "LMUL=m2 且 VS=OFF，操作数按 m2 对齐：陷入不得来自寄存器对齐非法，而是 VS 门或 LMUL 谓词",
    [("vsetvli", "e8", "m2"), ("vs_off", 0)], enc_vdot(4, 2, 0))
neg("xn_vs_off_vill",
    "vill=1 且 VS=OFF：vill 门（isVArithMem）与 VS 门（DecodeUnit）分属两个模块，"
    "两道门交叉从未同时出现",
    [("vill", 0x38), ("vs_off", 0)], enc_vdot(3, 1, 2))
neg("xn_lmul_m2_vl0",
    "LMUL=m2 且 vl=0：非法判定优先于 vl=0 全写（m2 对齐操作数排除对齐非法）",
    [("vsetvli_vl0", "e8", "m2")], enc_vdot(4, 2, 0))
neg("xn_vm0_vl0",
    "vm=0 且 vl=0：25 位匹配失败（解码不命中）不得被 vl=0 的提前返回吞掉",
    [("vsetvli_vl0", "e8", "m1")], 0x3820A1D7)
neg("xn_e16_mf4",
    "SEW=e16 且 LMUL=mf4：vsetvl 合法（16 <= 64*0.25），vdot 因两个谓词同时不满足而陷入",
    [("vsetvli", "e16", "mf4")], enc_vdot(3, 1, 2))
neg("xn_e16_mf2",
    "SEW=e16 且 LMUL=mf2：vsetvl 合法（16 <= 64*0.5），mf2 与 mf4 是不同 vlmul 位型",
    [("vsetvli", "e16", "mf2")], enc_vdot(3, 1, 2))
neg("xn_e32_mf2",
    "SEW=e32 且 LMUL=mf2：vsetvl 合法边界（32 = 64*0.5），vsew 与 vlmul 两个字段同时不满足",
    [("vsetvli", "e32", "mf2")], enc_vdot(3, 1, 2))

for _n in NEG:
    add(_n["cid"], "negative", "illegal", _n["note"], None)

# ---------------------------------------------------------------------------
# ④-ter 合法对照 3 例（cls=negative-legal，must-not-trap + 值断言）
#   上面 57 条负例的通过判据都是「必须陷入」。若实现把条件写成「vl=0 就陷入」
#   「VS!=Dirty 就陷入」「vstart 写过就陷入」，负例侧全绿、错误只在合法侧暴露。
#   本组三条正是这三条边界的反证；期望值同样由金模型算出。
#   cls 取 negative-legal 而非 negative：94-run-extra.sh 的 negative 判据要求
#   HIT CRITICAL ERROR（is_negative() 判 cls=="negative"），本组要求 HIT GOOD TRAP。
# ---------------------------------------------------------------------------
add("xn_ctrl_vl0_legal", "negative-legal", "negative-control",
    "合法对照：六条必要条件全满足且 vl=0，vdot 必须执行并按全写语义写 vd[31:0]/清零高 96 位；"
    "用于证明 3 条「非法优先于 vl=0」负例不是因为「所有 vl=0 都陷入」而通过",
    [L(1, "A_pos"), L(2, "B_pos"), SETVL(0), VD(3, 1, 2), RD(3)])
add("xn_ctrl_vs_initial", "negative-legal", "negative-control",
    "合法对照：mstatus.VS=Initial(01) 不是非法态（只有 VS=OFF 才非法），vdot 必须执行并全写；"
    "若实现写成「VS 必须为 Dirty」，现有正例全绿而误陷入只在本组暴露",
    [L(1, "A_pos"), L(2, "B_pos"), VSOFF(), VSINIT(), SETVL(16), VD(3, 1, 2), RD(3)])
add("xn_ctrl_vstart_reset", "negative-legal", "negative-control",
    "合法对照：vstart=1 之后执行合法 vsetvli，架构上 vstart 被清 0，vdot 必须正常执行；"
    "把「vsetvli 清 vstart」变成可失败断言（上面 3 条 _ord 负例依赖这条规则）",
    [L(1, "A_pos"), L(2, "B_pos"), RSV(1), SETVL(16), VD(3, 1, 2), RD(3)])

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
        elif kind == "vl_vt":
            # vl 与 vta/vma 同时给：AVL 直接写 x[t1]，ta/ma 后缀决定 vtype 的 bit6/bit7
            cur_vl[0] = op["n"]
            C("vl_vt %d ta=%d ma=%d" % (op["n"], op["ta"], op["ma"]))
            S("li t1, %d" % op["n"])
            S("vsetvli zero, t1, e8, m1, %s, %s"
              % ("ta" if op["ta"] else "tu", "ma" if op["ma"] else "mu"))
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
        elif kind == "vs_initial":
            # VS 是 mstatus[10:9]：先清 0x600 再置 0x200 ⇒ 01 (Initial)，不是 11 (Dirty)
            C("vs_initial")
            S("li t4, 0x600")
            S("csrc mstatus, t4")
            S("li t4, 0x200")
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
        elif kind == "vsetvli_keep":
            # keep-vl 形式：rd=x0 且 rs1=x0 ⇒ 只写 vtype，vl 取旧值（Vsetu keepVlIllegal 路径）
            lines.append('      "vsetvli zero, zero, %s, %s, ta, ma\\n\\t"' % (st[1], st[2]))
        elif kind == "vstart":
            lines.append('      "li t4, %d\\n\\t"' % st[1])
            lines.append('      "csrw 0x008, t4\\n\\t"')
        elif kind == "vill":
            # 立即数 >0xFF 时用十六进制，2^62 这类值读起来才不费劲（<=0xFF 保持原样）
            _imm = ("0x%X" % st[1]) if st[1] > 0xFF else ("%d" % st[1])
            lines.append('      "li t4, %s\\n\\t"' % _imm)
            lines.append('      "li t5, 8\\n\\t"')
            lines.append('      "vsetvl zero, t5, t4\\n\\t"')
        elif kind == "vs_off":
            lines.append('      "li t4, 0x600\\n\\t"')
            lines.append('      "csrc mstatus, t4\\n\\t"')
        elif kind == "vs_initial":
            lines.append('      "li t4, 0x600\\n\\t"')
            lines.append('      "csrc mstatus, t4\\n\\t"')
            lines.append('      "li t4, 0x200\\n\\t"')
            lines.append('      "csrs mstatus, t4\\n\\t"')
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
    "alias3": "SPEC §1.1 全写 + §3.4.2 vd==vs 属合法重叠；v0/v31 索引边界与 §1.4 累加器上下界",
    "alias-hi96": "SPEC §1.2 第 2 条（vd[127:32] 恒零）；SPEC §1.1 旧 vd 非语义输入",
    "alias-lanehi": "SPEC §1.1 lane 8..15 不参与；§1.4 19 位累加范围",
    "alias-wb": "SPEC §1.1 全写 + 写后读就地更新（同一 vd 连续写回）",
    "alias-vl": "SPEC §1.1 vl 不影响结果；非法判定优先于 vl=0 全写",
    "bb-distinct": "ARCHITECTURE §2.2 第 7 条 / §8 R13（fireS1 拍对齐）；vd 索引逐位正确",
    "vd-reuse": "ARCHITECTURE §3.1 VimacCfg.latency=2（在飞窗口）；写回按程序序",
    "raw-mid": "SPEC §1.1 写后读依赖；读回序列不破坏后续写后读",
    "raw-cross": "ARCHITECTURE §2.2 发射/写回；跨指令类（VIMac↔Mgu）旁路",
    "war": "SPEC §1.1 源寄存器在飞读取；WAR 冒险（vadd/vmacc/vle8.v 覆写源）",
    "waw-x": "跨指令类 WAW：Mgu 与 VIMac 两个写回源的排序",
    "vl-imm": "SPEC §1.1 vl 不影响语义且全写 vd",
    "vtype-imm": "SPEC §1.1 vta/vma 不影响结果；vdot 旁路 Mgu 的 tail/agnostic 路径",
    "rotate": "vd/vs1/vs2 三者独立轮转；写回目的地解码与端口映射",
    "cross-class": "ARCHITECTURE §2.2 跨类旁路 + 写回口竞争",
    "negative-control": "SPEC §1.1 六条必要条件为「与」：合法侧反证（must-not-trap）",
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
