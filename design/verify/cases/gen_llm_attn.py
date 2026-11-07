#!/usr/bin/env python3
"""gen_llm_attn.py — LLM 算子级基准（Q8_0 attention QK 点积）的金模型生成器。

算子：`Q8_0 attention QK` 的 K=8 子块点积（与 `ggml_vec_dot_q8_0_q8_0` 的 block 内层同形）。
形状：8 query × 8 key × head_dim=64；head_dim=64 = 2 个 `block_q8_0`（QK=32）= 8 个 K=8 chunk。
      ⇒ 每 tile 512 个 chunk dot、64 个 score。
语义锚：`design/SPEC.md` §1.1 —— `S = Σ_{i=0..7} sext8(vs1[i])·sext8(vs2[i])`，
      取 vs1/vs2 低 64 位（lane 0–7），写回 `vd[31:0]=sext32(S)`、`vd[127:32]=0`。

期望值来源（**禁止手写常量**）：
  A 路 = `vdot_model.dot_product()`（任意精度逐项和，ALGORITHM §3.1 算法 A）
  B 路 = `vdot_model.vdot_vv()`（19 位中间模型的 128 位写回）+ 32 位补码截断取低 32 位
两路必须逐 chunk 相等；不等即生成器失败（退出码 1），不落盘。

数据规模与边界：
  · 64 行数据（8 query + 8 key）× 2 block × 32 int8，PCG 式 LCG 从 seed=42 生成（无 numpy、无 random 依赖，
    Python 版本无关）；`qs` 落在 block 的 `+2` 偏移（真实 `block_q8_0` 34 B 布局，测非对齐 `vle8.v`）。
  · 每个 block 的 `d` 固定 `0x3800`（fp16 = 0.5）⇒ 去量化因子 `d_q·d_k = 0.25` **精确**，
    score = isum/4 可在 Q16 整数域内逐位校验，不引入 FP 舍入、不依赖 Zfh。
  · 边界注入（在「G0 + 自检串」之外补的最小边界覆盖）：key 行 7 的 chunk 0/1/2 被覆写为
    {全 -128 / 全 +127 / 交替极值}，对应 S = +131072 / +129032 / -130048（19 位包络的上/下沿）。

用法：
  python3 -I design/verify/cases/gen_llm_attn.py --out <header 路径> [--seed 42]
  python3 -I design/verify/cases/gen_llm_attn.py --check <header 路径>   # 只核对不写盘

退出码：0 生成/核对成功 · 1 两路不一致或范围越界 · 2 用法错误
"""
import argparse
import hashlib
import os
import sys

# 必须以显式路径 import vdot_model：`-I` 隔离模式不把脚本目录放进 sys.path，
# 也不读 PYTHONPATH。
HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY_DIR = os.path.dirname(HERE)  # design/verify
sys.path.insert(0, VERIFY_DIR)

import vdot_model  # noqa: E402

NQ = 8          # query 行数
NK = 8          # key 行数
HD = 64         # head_dim
QK = 32         # block_q8_0 的 QK
NBLK = HD // QK          # 每行 2 个 block
CHUNK = 8                # vdot 的 K
NCHUNK = HD // CHUNK     # 每行 8 个 chunk
NCHUNK_TOTAL = NQ * NK * NCHUNK   # 512
D_FP16 = 0x3800          # fp16 0.5（指数 14、尾数 0 ⇒ 精确）；d_q*d_k = 0.25
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = (1 << 64) - 1


class Lcg:
    """固定的 64 位 LCG（PCG 常数），保证跨 Python 版本逐字节可复现。"""

    def __init__(self, seed):
        self.s = seed & MASK64

    def next_u8(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & MASK64
        return (self.s >> 33) & 0xFF

    def next_s8(self):
        v = self.next_u8()
        return v - 256 if v >= 128 else v


def fnv1a_i32(h, value):
    """对 int32 的小端 4 字节做 FNV-1a 64（与 C 侧逐位同构）。"""
    u = value & 0xFFFFFFFF
    for i in range(4):
        h ^= (u >> (8 * i)) & 0xFF
        h = (h * FNV_PRIME) & MASK64
    return h


def build(seed):
    rng = Lcg(seed)
    qs_q = [[[rng.next_s8() for _ in range(QK)] for _ in range(NBLK)] for _ in range(NQ)]
    qs_k = [[[rng.next_s8() for _ in range(QK)] for _ in range(NBLK)] for _ in range(NK)]

    # ---- 边界注入（key 行 7 的前三个 chunk；q/k 同侧取极值）----
    krow = NK - 1
    # chunk0 = 全 -128 → S = 8 * 16384 = 131072（19 位上沿）
    for i in range(CHUNK):
        qs_q[0][0][i] = -128
        qs_k[krow][0][i] = -128
    # chunk1 = 全 +127 → S = 8 * 16129 = 129032
    for i in range(CHUNK):
        qs_q[0][0][CHUNK + i] = 127
        qs_k[krow][0][CHUNK + i] = 127
    # chunk2 = 交替极值 → 每积 127*(-128) = -16256，S = -130048（19 位下沿）
    for i in range(CHUNK):
        qs_q[0][0][2 * CHUNK + i] = 127 if (i % 2 == 0) else -128
        qs_k[krow][0][2 * CHUNK + i] = -128 if (i % 2 == 0) else 127

    # ---- 金模型：A 路（任意精度）与 B 路（19 位模型）逐 chunk 交叉核对 ----
    want_chunk = [[[0] * NCHUNK for _ in range(NK)] for _ in range(NQ)]
    want_isum = [[0] * NK for _ in range(NQ)]
    abc_checked = 0
    smin, smax = 0, 0
    for qi in range(NQ):
        for ki in range(NK):
            acc = 0
            for c in range(NCHUNK):
                blk, off = divmod(c, NCHUNK // NBLK)
                a8 = qs_q[qi][blk][off * CHUNK:(off + 1) * CHUNK]
                b8 = qs_k[ki][blk][off * CHUNK:(off + 1) * CHUNK]
                # 装进 128 位寄存器的低 64 位；高 64 位填干扰值 0xFF（vdot 不得读）
                reg_a = 0
                reg_b = 0
                for i in range(CHUNK):
                    reg_a |= (a8[i] & 0xFF) << (8 * i)
                    reg_b |= (b8[i] & 0xFF) << (8 * i)
                reg_a |= ((1 << 64) - 1) << 64
                reg_b |= ((1 << 64) - 1) << 64

                s_a = vdot_model.dot_product(reg_a, reg_b)                 # 算法 A
                vd = vdot_model.vdot_vv(reg_a, reg_b)                      # 19 位模型
                s_b = vd & 0xFFFFFFFF
                if s_b >= 0x80000000:                                      # 32 位补码还原
                    s_b -= 1 << 32
                if s_a != s_b:
                    raise SystemExit(
                        "AB_CROSSCHECK_FAIL q=%d k=%d c=%d A=%d B=%d" % (qi, ki, c, s_a, s_b))
                if not vdot_model.ACC_MIN <= s_a <= vdot_model.ACC_MAX:
                    raise SystemExit("SPEC_RANGE_FAIL q=%d k=%d c=%d S=%d" % (qi, ki, c, s_a))
                abc_checked += 1
                want_chunk[qi][ki][c] = s_a
                acc += s_a
                smin = min(smin, s_a)
                smax = max(smax, s_a)
            if not -(1 << 31) <= acc < (1 << 31):
                raise SystemExit("ISUM_RANGE_FAIL q=%d k=%d isum=%d" % (qi, ki, acc))
            want_isum[qi][ki] = acc

    # ---- 摘要（C 侧按同一顺序重算并比对；chunk 摘要 = 逐 chunk 级严格性）----
    h_chunk = FNV_OFFSET
    for qi in range(NQ):
        for ki in range(NK):
            for c in range(NCHUNK):
                h_chunk = fnv1a_i32(h_chunk, want_chunk[qi][ki][c])
    h_isum = FNV_OFFSET
    for qi in range(NQ):
        for ki in range(NK):
            h_isum = fnv1a_i32(h_isum, want_isum[qi][ki])

    return dict(qs_q=qs_q, qs_k=qs_k, want_isum=want_isum, h_chunk=h_chunk,
                h_isum=h_isum, abc_checked=abc_checked, smin=smin, smax=smax)


def render(d):
    L = []
    w = L.append
    w("/* llm_attn_vectors.h — 由 design/verify/cases/gen_llm_attn.py 生成，禁止手改。")
    w(" *")
    w(" * 形状：%d query × %d key × head_dim=%d（每行 %d 个 block_q8_0，每 block %d 个 K=8 chunk）"
      % (NQ, NK, HD, NBLK, NCHUNK // NBLK))
    w(" * ⇒ 每 tile %d 个 chunk dot、%d 个 score。" % (NCHUNK_TOTAL, NQ * NK))
    w(" * 期望值：vdot_model.dot_product()（算法 A）与 vdot_model.vdot_vv()（19 位模型）逐 chunk 交叉核对。")
    w(" * d 恒 0x3800（fp16 0.5）⇒ d_q·d_k = 0.25 精确 ⇒ score = isum/4（Q16: isum*16384），无 FP 舍入。")
    w(" * 边界注入：key 行 %d 的 chunk 0/1/2 = 全 -128 / 全 +127 / 交替极值。" % (NK - 1))
    w(" */")
    w("#ifndef LLM_ATTN_VECTORS_H")
    w("#define LLM_ATTN_VECTORS_H")
    w("")
    w("#include <stdint.h>")
    w("")
    w("#define LLM_NQ %d" % NQ)
    w("#define LLM_NK %d" % NK)
    w("#define LLM_HD %d" % HD)
    w("#define LLM_NBLK %d" % NBLK)
    w("#define LLM_NCHUNK %d" % NCHUNK)
    w("#define LLM_NCHUNK_PER_BLK %d" % (NCHUNK // NBLK))
    w("#define LLM_NCHUNK_TOTAL %d" % NCHUNK_TOTAL)
    w("#define LLM_D_FP16 0x%04X" % D_FP16)
    w("#define LLM_WANT_CHUNK_FNV1A 0x%016XULL" % d["h_chunk"])
    w("#define LLM_WANT_ISUM_FNV1A  0x%016XULL" % d["h_isum"])
    w("")

    def emit_2d(name, arr, signed):
        w("static const %s %s[%d][%d][%d] = {" % ("int8_t" if signed else "uint8_t", name, arr.__len__(), NBLK, QK))
        for r in range(len(arr)):
            w("  {")
            for b in range(NBLK):
                w("    { " + ", ".join(str(v) for v in arr[r][b]) + " },")
            w("  },")
        w("};")
        w("")

    emit_2d("llm_qs_q", d["qs_q"], True)
    emit_2d("llm_qs_k", d["qs_k"], True)
    w("/* 每 block 的量化 scale（fp16 位型）；本基准全部同值，保留数组以保持 34 B/block 的真实布局意图 */")
    w("static const uint16_t llm_d_q[%d][%d] = {" % (NQ, NBLK))
    for r in range(NQ):
        w("  { " + ", ".join("0x%04X" % D_FP16 for _ in range(NBLK)) + " },")
    w("};")
    w("static const uint16_t llm_d_k[%d][%d] = {" % (NK, NBLK))
    for r in range(NK):
        w("  { " + ", ".join("0x%04X" % D_FP16 for _ in range(NBLK)) + " },")
    w("};")
    w("")
    w("/* 每 (q,k) 的整数点积和 isum = Σ_{c=0..%d} chunk[c]（score = isum/4） */" % (NCHUNK - 1))
    w("static const int32_t llm_want_isum[%d][%d] = {" % (NQ, NK))
    for qi in range(NQ):
        w("  { " + ", ".join("%d" % v for v in d["want_isum"][qi]) + " },")
    w("};")
    w("")
    w("#endif /* LLM_ATTN_VECTORS_H */")
    w("")
    return "\n".join(L)


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--check", default="")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args(argv)
    if not a.out and not a.check:
        print("用法：gen_llm_attn.py --out <header> | --check <header>", file=sys.stderr)
        return 2

    d = build(a.seed)
    text = render(d)
    blob = text.encode()
    digest = hashlib.sha256(blob).hexdigest()

    target = a.out or a.check
    if a.check:
        if not os.path.exists(target):
            print("GEN CHECK_FAIL missing=%s" % target)
            return 1
        old = open(target, "rb").read()
        same = hashlib.sha256(old).hexdigest() == digest
        print("GEN check=%s file_sha256=%s regen_sha256=%s"
              % ("OK" if same else "MISMATCH",
                 hashlib.sha256(old).hexdigest()[:16], digest[:16]))
        return 0 if same else 1

    with open(target, "wb") as f:
        f.write(blob)
    print("GEN OK chunks=%d dots=%d scores=%d spec_range_ok=yes ab_crosscheck=yes "
          "chunk_s_min=%d chunk_s_max=%d isum_fnv1a=0x%016X chunk_fnv1a=0x%016X "
          "d_fp16=0x%04X dequant_exact=0.25 sha256=%s path=%s"
          % (d["abc_checked"], d["abc_checked"], NQ * NK, d["smin"], d["smax"],
             d["h_isum"], d["h_chunk"], D_FP16, digest, target))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
