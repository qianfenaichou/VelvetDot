#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rand_crosscheck.py — vdot_rand 用例的「金模型侧独立复算」（ALGORITHM §3.1 三方对拍 / §3.2「随机」行）。

与 design/verify/cases/vdot_rand.c 逐位同构：
  * 同一个 splitmix64（种子 42）、同一段字节序（先 a16[0..15] 再 b16[0..15]）、同两条定向注入规则；
  * 同一套 FNV-1a/64 混入顺序（a lane0-7 → b lane0-7 → 硬件结果 4 字节小端）；
  * 期望值由金模型 `vdot_model.vdot_vv`（M08：返回完整 128 位 vd）给出，
    并与算法 A（逐项累加）/算法 B（19 位模算术）三方交叉；
  * old_vd 预填 0xAA…AA（与用例的 vmv.v.x 预填一致），断言写回与旧值无关且高 96 位恒零。

用法：
    python3 design/verify/cases/rand_crosscheck.py                 # 打印期望校验和
    python3 design/verify/cases/rand_crosscheck.py --check-log L   # 与 difftest 用例日志里的
                                                                   # RAND_SUMMARY fnv=0x… 比对，不一致退出码 1
判据：--check-log 命中且校验和相同 ⇒ 金模型 == 用例自检期望 == DUT/NEMU 实测（difftest 0 ABORT 另计）。
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, os.pardir, "vdot_model.py")

N_GROUPS = 1024
MASK64 = (1 << 64) - 1
FNV_BASIS = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
OLD_VD = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA


def load_model():
    spec = importlib.util.spec_from_file_location("vdot_model", MODEL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SplitMix64:
    def __init__(self, seed=42):
        self.state = seed & MASK64

    def next_u64(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)


def s8(x):
    return x - 256 if x >= 128 else x


def algo_a(a, b):
    return sum(s8(a[i]) * s8(b[i]) for i in range(8))


def algo_b(a, b):
    acc = 0
    for i in range(8):
        prod = s8(a[i]) * s8(b[i])
        acc = (acc + prod) & 0x7FFFF
    if acc & 0x40000:
        acc -= 0x80000
    return acc


def pack32(value):
    return value & 0xFFFFFFFF


def groups():
    """产出 (g, a16, b16)；与 C 侧 for 循环逐字节同序。"""
    rng = SplitMix64(42)
    for g in range(N_GROUPS):
        a = [rng.next_u64() & 0xFF for _ in range(16)]
        b = [rng.next_u64() & 0xFF for _ in range(16)]
        if g % 128 == 0:  # 交错极值 → S=-130048
            for i in range(8):
                a[i] = 0x80 if (i & 1) else 0x7F
                b[i] = 0x7F if (i & 1) else 0x80
        if g % 256 == 1:  # 一侧全零 → S=0
            for i in range(8):
                a[i] = 0
        yield g, a, b


def crosscheck():
    model = load_model()
    fnv = FNV_BASIS
    extremes = zerohalf = 0
    bad = []
    samples = []
    for g, a, b in groups():
        if g % 128 == 0:
            extremes += 1
        if g % 256 == 1:
            zerohalf += 1
        vs1 = sum(a[i] << (8 * i) for i in range(16))
        vs2 = sum(b[i] << (8 * i) for i in range(16))
        # 金模型只读低 64 位 lane 0-7：高半区垃圾必须不影响结果（§3.2「高 64 位干扰」）
        vd128 = model.vdot_vv(vs1, vs2, vl=16, old_vd=OLD_VD)
        res = vd128 & 0xFFFFFFFF
        if vd128 >> 32 != 0:
            bad.append((g, "high-96-not-zero", hex(vd128)))
        A = pack32(algo_a(a, b))
        B = pack32(algo_b(a, b))
        if not (A == B == res):
            bad.append((g, "A/B/model 不一致", (hex(A), hex(B), hex(res))))
        for i in range(8):
            fnv = ((fnv ^ a[i]) * FNV_PRIME) & MASK64
        for i in range(8):
            fnv = ((fnv ^ b[i]) * FNV_PRIME) & MASK64
        for shift in (0, 8, 16, 24):
            fnv = ((fnv ^ ((res >> shift) & 0xFF)) * FNV_PRIME) & MASK64
        if g < 2 or g % 256 == 3:
            samples.append((g, algo_a(a, b), hex(res)))
    return fnv, bad, extremes, zerohalf, samples


SUMMARY = re.compile(r"RAND_SUMMARY groups=(\d+) mism=(\d+) ab_bad=(\d+) "
                     r"extremes=(\d+) zerohalf=(\d+) fnv=0x([0-9A-Fa-f]{1,16})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-log", help="vdot_rand 的 difftest 单例日志路径")
    args = ap.parse_args()

    fnv, bad, extremes, zerohalf, samples = crosscheck()
    print("金模型独立复算：groups=%d extremes=%d zerohalf=%d 自检异常=%d"
          % (N_GROUPS, extremes, zerohalf, len(bad)))
    for g, s, r in samples:
        print("  g={:<4d} S={} model_res={}".format(g, s, r))
    print("  fnv=0x{:016X}".format(fnv))
    if bad:
        for item in bad[:10]:
            print("  [异常] %s" % (item,))
        print("结论：FAIL（金模型侧交叉对照不通过）")
        return 1

    if args.check_log:
        with open(args.check_log, "r", errors="replace") as f:
            text = f.read()
        m = None
        for m in SUMMARY.finditer(text):
            pass
        if not m:
            print("结论：未运行（日志 %s 中没有 RAND_SUMMARY 行）" % args.check_log)
            return 2
        c_groups, c_mism, c_ab, c_ext, c_zero, c_fnv = m.groups()
        hw_fnv = int(c_fnv, 16)
        print("用例侧（DUT/NEMU 实测混入）：groups=%s mism=%s ab_bad=%s extremes=%s zerohalf=%s "
              "fnv=0x%016X" % (c_groups, c_mism, c_ab, c_ext, c_zero, hw_fnv))
        if int(c_mism) != 0 or int(c_ab) != 0:
            print("结论：FAIL（用例自检未通过）")
            return 1
        if hw_fnv != fnv or int(c_groups) != N_GROUPS:
            print("结论：FAIL（校验和不一致：金模型 0x%016X vs 用例 0x%016X）" % (fnv, hw_fnv))
            return 1
        print("结论：PASS（Python 金模型 == 用例期望 == DUT/NEMU 实测，%d 组逐组一致）" % N_GROUPS)
        return 0
    print("结论：已产出期望校验和（未给 --check-log，不与用例日志比对）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
