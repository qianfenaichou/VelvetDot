#!/usr/bin/env python3
"""Assertion tests for the ``vdot.vv`` golden model (``design/verify/vdot_model.py``).

Semantics under test come from ``design/SPEC.md`` only; the case matrix follows
``design/ALGORITHM.md`` §3.1/§3.2/§1.4 and ``design/CODING-STD.md`` §5.2:

* three independent algorithms must agree on every case:
  - the golden model under test (``vdot_model.vdot_vv``);
  - model B: bit-level model -- signed 8x8 product as a 16-bit two's-complement
    pattern -> ``sext19`` -> accumulate modulo 2**19 -> read as 19-bit signed ->
    write back as 32 bits (ALGORITHM.md §3.1 algorithm B);
  - model C: ``struct.unpack("<8b", ...)`` lanes -> unlimited-precision sum ->
    one final 32-bit mask;
* every case asserts ``vd[127:32] == 0`` (SPEC.md §1.2 machine-checkable point 2);
* lane selection: only bits [63:0] of vs1/vs2 participate, so the high 64 bits
  are filled with interference patterns (SPEC.md §1.2 point 1);
* directed cases: zero, +127, -127, -128 (raw 0x80; int8 has no +128), maximum
  sum 131072, maximum positive sum 129032, minimum sum -130048, odd negative
  lane counts 1/3/5/7, interleaved extremes;
* boundary sums are pinned to literal expected values, not merely cross-checked,
  so an 18-bit accumulator would be caught (SPEC.md §1.4);
* fixed seed 42 random set, 1000 cases with random high-64-bit bytes;
* illegal set: SEW != 8 / LMUL != 1 / vm = 0 / vstart != 0 (SPEC.md §1.1/§1.3);
* ``vl`` / ``vta`` / ``vma`` never change the result (SPEC.md §1.1);
* the SPEC.md §2.2 machine-code example ``vdot.vv v3, v2, v1`` = ``0x3A20A1D7``;
* a self-check proves the comparison predicate really rejects a 1-bit change,
  so a green run cannot be vacuous (ALGORITHM.md §3.1).

Run: ``python3 design/verify/vdot_model_test.py``
Exit code 0 and ``ALL TESTS PASSED (N cases)`` on success; non-zero and a diff
listing on any failure.
"""

import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from vdot_model import (  # noqa: E402
    ACC_MAX, ACC_MIN, IllegalInstruction, K, OUT_MASK, VLEN, MSTATUS_VS_INITIAL,
    MSTATUS_VS_OFF, decode_vdot_vv, dot_product, encode_vdot_vv, execute_vdot,
    lanes_int8, vdot_vv,
)

ACC_MASK = (1 << 19) - 1
U16_MASK = (1 << 16) - 1
U8_MASK = 0xFF

failures = []
case_count = 0


# ---------------------------------------------------------------------------
# Independent reference models (ALGORITHM.md §3.1)
# ---------------------------------------------------------------------------

def ref_bitlevel(vs1, vs2):
    """Model B: 16-bit product -> sext19 -> mod 2**19 sum -> sext32."""
    acc = 0
    for i in range(K):
        a = (vs1 >> (8 * i)) & U8_MASK
        b = (vs2 >> (8 * i)) & U8_MASK
        a_s = a - 256 if a & 0x80 else a
        b_s = b - 256 if b & 0x80 else b
        prod16 = (a_s * b_s) & U16_MASK                       # 16-bit two's complement
        # sext19 of a 16-bit pattern: subtract 2**16 when the 16-bit sign bit is set.
        prod19 = prod16 - (1 << 16) if prod16 & (1 << 15) else prod16
        acc = (acc + prod19) & ACC_MASK                        # modulo 2**19
    s19 = acc - (1 << 19) if acc & (1 << 18) else acc          # 19-bit signed
    return s19 & OUT_MASK                                      # sext32


def ref_arbitrary(vs1, vs2):
    """Model C: unpack bytes with ``struct`` and sum with unlimited precision.

    Deliberately a different code path: the register is materialised as 16
    little-endian bytes, the first 8 are unpacked as signed int8 lanes, products
    are formed by plain multiplication and accumulated with no truncation.  Only
    the final write-back masks to 32 bits (SPEC.md §1.1: ``vd[31:0] = sext32(S)``).
    """
    bytes1 = vs1.to_bytes(VLEN // 8, "little")
    bytes2 = vs2.to_bytes(VLEN // 8, "little")
    # ``<8b`` decodes the low 64 bits as eight int8 lanes; bytes 8..15 are ignored.
    lanes1 = struct.unpack("<8b", bytes1[:8])
    lanes2 = struct.unpack("<8b", bytes2[:8])
    total = 0
    for index in range(8):
        total += lanes1[index] * lanes2[index]
    return total & OUT_MASK


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def pack_reg(low_lanes, high_bytes=(0,) * 8):
    """Build a 128-bit register: 8 low int8 lanes + 8 high (ignored) bytes."""
    if len(low_lanes) != 8 or len(high_bytes) != 8:
        raise ValueError("need 8 low lanes and 8 high bytes")
    value = 0
    for i, byte in enumerate(low_lanes):
        value |= (byte & U8_MASK) << (8 * i)
    for i, byte in enumerate(high_bytes):
        value |= (byte & U8_MASK) << (64 + 8 * i)
    return value


def _signed32(value):
    value &= OUT_MASK
    return value - (1 << 32) if value & (1 << 31) else value


def result_problem(expected, got):
    """Return a reason string if ``got`` is not an acceptable model result.

    This is the single predicate every semantic case uses, so the self-check in
    ``main`` exercises exactly the path the real cases rely on.  The high-96-bit
    test comes first so a clear result cannot hide behind a generic mismatch
    message (SPEC.md §1.2 machine-checkable point 2).
    """
    if not isinstance(got, int):
        return "result is not an int"
    if got >> 32 != 0:
        return "vd[127:32] is not zero"
    if got != expected:
        return "value mismatch"
    return None


def fail(label, expected, got, detail=""):
    failures.append(
        "%s\n    expected: 0x%08x (%s)\n    got     : 0x%08x (%s)%s"
        % (label, expected & 0xFFFFFFFF, _signed32(expected),
           got & 0xFFFFFFFF, _signed32(got),
           ("\n    " + detail) if detail else "")
    )


def check(label, vs1, vs2, **kwargs):
    """One semantic case: three models must agree and the high 96 bits must be 0."""
    global case_count
    case_count += 1

    expected = ref_bitlevel(vs1, vs2)
    third = ref_arbitrary(vs1, vs2)
    if third != expected:
        fail(label + " [models B/C disagree]", expected, third,
             "vs1=0x%032x vs2=0x%032x" % (vs1, vs2))
        return

    try:
        got = vdot_vv(vs1, vs2, **kwargs)
    except Exception as exc:  # noqa: BLE001 - report, do not abort the run
        fail(label, expected, 0, "model raised %r" % (exc,))
        return

    problem = result_problem(expected, got)
    if problem is not None:
        fail(label + " [" + problem + "]", expected, got,
             "vs1=0x%032x vs2=0x%032x kwargs=%r" % (vs1, vs2, kwargs))


def check_value(label, vs1, vs2, expected):
    """Assert all three models produce a literal expected value.

    Used for the boundary numbers of ALGORITHM.md §1.4, so agreement between
    models cannot hide a shared wrong constant and an 18-bit accumulator is
    caught by the literal (S=131072 must appear as 0x00020000 in vd[31:0]).
    """
    global case_count
    case_count += 1

    expected &= OUT_MASK
    got_a = vdot_vv(vs1, vs2)
    got_b = ref_bitlevel(vs1, vs2)
    got_c = ref_arbitrary(vs1, vs2)
    for name, got in (("golden model", got_a),
                      ("bit-level model", got_b),
                      ("struct model", got_c)):
        problem = result_problem(expected, got)
        if problem is not None:
            fail("%s [%s] %s" % (label, problem, name), expected, got,
                 "vs1=0x%032x vs2=0x%032x" % (vs1, vs2))


def check_illegal(label, **kwargs):
    global case_count
    case_count += 1
    try:
        vdot_vv(0, 0, **kwargs)
    except IllegalInstruction:
        return
    except Exception as exc:  # noqa: BLE001
        fail(label + " [illegal]", 1, 0, "wrong exception type: %r" % (exc,))
        return
    fail(label + " [illegal]", 1, 0, "expected IllegalInstruction, got a result")


def check_equal_result(label, a, b):
    """Assert two model results are equal and both have vd[127:32] == 0.

    Used wherever the comparison is model-vs-model (invariance and interference
    cases), so the "high 96 bits are always zero" assertion of SPEC.md §1.2 is
    made on those results too, not only inside ``check``.
    """
    global case_count
    case_count += 1
    if a >> 32 != 0 or b >> 32 != 0:
        fail(label + " [vd[127:32] must be zero]", 0, max(a >> 32, b >> 32))
    elif a != b:
        fail(label, a, b)


# ---------------------------------------------------------------------------
# Directed cases (SPEC.md §1.1/§1.4, ALGORITHM.md §1.4)
# ---------------------------------------------------------------------------

def directed_cases():
    zero = pack_reg([0] * 8)
    check("all-zero", zero, zero)
    check_value("all-zero S=0", zero, zero, 0)

    # Positives.
    check("pos 1..8 x 1..8", pack_reg(range(1, 9)), pack_reg(range(1, 9)))
    check("pos 1..8 x 8..1", pack_reg(range(1, 9)), pack_reg(range(8, 0, -1)))
    check("all +1", pack_reg([1] * 8), pack_reg([1] * 8))
    # Maximum positive sum 8*127*127 = 129032.
    check("all +127 (max positive sum)", pack_reg([127] * 8), pack_reg([127] * 8))
    check_value("all +127 S=129032", pack_reg([127] * 8), pack_reg([127] * 8), 129032)

    # Negatives.
    all_neg128 = pack_reg([-128 & U8_MASK] * 8)
    check("all -128 (19-bit boundary case)", all_neg128, all_neg128)
    # S = 131072 = 2**17 -> vd[31:0] = 0x00020000.  An 18-bit accumulator would
    # wrap this to -131072 = 0xFFFE0000, so the literal pins the width.
    check_value("all -128 S=131072 (19-bit boundary)", all_neg128, all_neg128, 131072)
    check("all -1 (S=8)", pack_reg([0xFF] * 8), pack_reg([0xFF] * 8))
    check("all -127 x all +127", pack_reg([-127 & U8_MASK] * 8), pack_reg([127] * 8))
    # Minimum sum 8*(-128)*127 = -130048 -> vd[31:0] = 0xFFFE0400.
    check("min sum (-128 x +127)", all_neg128, pack_reg([127] * 8))
    check_value("min sum S=-130048", all_neg128, pack_reg([127] * 8), -130048)
    # Raw 0x80 (= -128) x +1 is -1024, pinning the sign extension of 0x80.
    check_value("raw 0x80 x +1 S=-1024", all_neg128, pack_reg([1] * 8), -1024)

    # int8 boundary element values.  SPEC.md §1.1 uses ``sext8`` (int8 range
    # [-128, 127]), so "+-128" can only exist on the negative side: raw byte
    # 0x80 == -128.  +128 is not representable as an int8 lane; the positive
    # extreme is +127.  Both extremes are covered here, and the raw 0x80 pattern
    # is asserted to decode as -128 in structural_cases.
    for value in (0, 127, -127, -128):
        lanes = [value & U8_MASK] * 8
        check("single-value lane %+d x 1" % value, pack_reg(lanes), pack_reg([1] * 8))
        check("single-value lane 1 x %+d" % value, pack_reg([1] * 8), pack_reg(lanes))

    # A single non-zero lane exercises lane positioning.
    for lane in (0, 3, 7):
        v1 = [0] * 8
        v1[lane] = 127
        v2 = [0] * 8
        v2[lane] = 127
        check("only lane %d non-zero (127x127)" % lane, pack_reg(v1), pack_reg(v2))

    # Odd negative-lane counts 1/3/5/7: any zero-extension of the products
    # shows up as an n*2**16 bias modulo 2**19 (ALGORITHM.md §1.4).
    for n_neg in (1, 3, 5, 7):
        v1 = [(-128 & U8_MASK) if i < n_neg else 127 for i in range(8)]
        v2 = [127] * 8
        check("odd negative lanes n=%d (-128 x +127)" % n_neg,
              pack_reg(v1), pack_reg(v2))
        v2b = [(-128 & U8_MASK) if i % 2 == 0 else 127 for i in range(8)]
        check("odd negative lanes n=%d (mixed)" % n_neg, pack_reg(v1), pack_reg(v2b))

    # Interleaved extremes.
    check("interleaved +127/-128 x interleaved -128/+127",
          pack_reg([127 if i % 2 == 0 else -128 & U8_MASK for i in range(8)]),
          pack_reg([-128 & U8_MASK if i % 2 == 0 else 127 for i in range(8)]))
    check("interleaved +127/-1",
          pack_reg([127 if i % 2 == 0 else 0xFF for i in range(8)]),
          pack_reg([0xFF if i % 2 == 0 else 127 for i in range(8)]))

    # High-64-bit interference: SPEC.md §1.2 machine-checkable point 1.
    high_patterns = [
        ("all 0xFF", (0xFF,) * 8),
        ("all 0x7F", (0x7F,) * 8),
        ("alternating AA/55", tuple(0xAA if i % 2 == 0 else 0x55 for i in range(8))),
        ("+127 lanes", (127,) * 8),
        ("-128 lanes", (0x80,) * 8),
    ]
    for name, high in high_patterns:
        check("high-64 interference (%s), low all zero" % name,
              pack_reg([0] * 8, high), pack_reg([0] * 8, high))
        check("high-64 interference (%s), low 1..8" % name,
              pack_reg(range(1, 9), high), pack_reg(range(8, 0, -1), high))
        # Lane selection as invariance: filling the high half must not change the
        # result relative to the same low halves with a zero high half.
        check_equal_result("high-64 interference (%s) does not change result" % name,
                           vdot_vv(pack_reg([0] * 8, high), pack_reg([0] * 8, high)),
                           vdot_vv(pack_reg([0] * 8), pack_reg([0] * 8)))
        check_equal_result(
            "high-64 interference (%s) does not change result (low 1..8)" % name,
            vdot_vv(pack_reg(range(1, 9), high), pack_reg(range(8, 0, -1), high)),
            vdot_vv(pack_reg(range(1, 9)), pack_reg(range(8, 0, -1))))


# ---------------------------------------------------------------------------
# vl / vta / vma invariance (SPEC.md §1.1)
# ---------------------------------------------------------------------------

def invariant_cases():
    vectors = [
        (pack_reg(range(1, 9)), pack_reg(range(8, 0, -1))),
        (pack_reg([127] * 8), pack_reg([-128 & U8_MASK] * 8)),
        (pack_reg([0, -1, 2, -3, 4, -5, 6, -7]),
         pack_reg([-8, 7, -6, 5, -4, 3, -2, 1])),
    ]
    rng = random.Random(42)  # separate stream: the main random set stays as designed
    vectors.append((rng.getrandbits(VLEN), rng.getrandbits(VLEN)))

    for index, (vs1, vs2) in enumerate(vectors):
        baseline = vdot_vv(vs1, vs2)
        for vl in (0, 1, 4, 7, 16):
            check_equal_result("vl=%d leaves result unchanged (vector %d)"
                               % (vl, index),
                               baseline, vdot_vv(vs1, vs2, vl=vl))
        for vta in (False, True):
            for vma in (False, True):
                check_equal_result("vta=%r vma=%r leaves result unchanged (vector %d)"
                                   % (vta, vma, index),
                                   baseline, vdot_vv(vs1, vs2, vta=vta, vma=vma))


# ---------------------------------------------------------------------------
# Illegal set (SPEC.md §1.1/§1.3)
# ---------------------------------------------------------------------------

def illegal_cases():
    global case_count

    check_illegal("SEW=16", sew=16)
    check_illegal("SEW=32", sew=32)
    check_illegal("SEW=64", sew=64)
    check_illegal("LMUL=2", lmul=2)
    check_illegal("LMUL=4", lmul=4)
    check_illegal("LMUL=1/2", lmul=0.5)
    check_illegal("vm=0", vm=0)
    check_illegal("vstart=1", vstart=1)
    check_illegal("vstart=7", vstart=7)
    check_illegal("SEW=16 + LMUL=2 + vm=0", sew=16, lmul=2, vm=0)
    check_illegal("vstart=1 + vm=0", vstart=1, vm=0)
    check_illegal("LMUL=2 + vstart=1", lmul=2, vstart=1)

    # Every legal combination must not raise (vl/vta/vma are ignored).
    for vl in (0, 1, 7, 16):
        for vta in (False, True):
            for vma in (False, True):
                label = ("legal sew=8 lmul=1 vm=1 vstart=0 vl=%d vta=%r vma=%r"
                         % (vl, vta, vma))
                case_count += 1
                try:
                    vdot_vv(0, 0, sew=8, lmul=1, vm=1, vstart=0,
                            vl=vl, vta=vta, vma=vma)
                except Exception as exc:  # noqa: BLE001
                    fail(label, 1, 0, "raised %r" % (exc,))


# ---------------------------------------------------------------------------
# Fixed-seed random set (seed 42, 1000 cases)
# ---------------------------------------------------------------------------

def random_cases(count=1000):
    rng = random.Random(42)
    for index in range(count):
        vs1 = rng.getrandbits(VLEN)
        vs2 = rng.getrandbits(VLEN)
        vl = rng.choice((None, 0, 1, 4, 7, 8, 16))
        kwargs = {"vl": vl, "vta": rng.random() < 0.5, "vma": rng.random() < 0.5}
        check("random #%d (seed 42)" % index, vs1, vs2, **kwargs)


# ---------------------------------------------------------------------------
# Model sanity: lane extraction, 19-bit budget, operand domain, encoding
# ---------------------------------------------------------------------------

def structural_cases():
    global case_count

    # Lane extraction reads bits [8i+7:8i] as signed int8; the high half is ignored.
    reg = pack_reg([-128 & U8_MASK, 127, 0, -1, 1, -2, 2, -127 & U8_MASK],
                   (0xFF,) * 8)
    case_count += 1
    if lanes_int8(reg) != (-128, 127, 0, -1, 1, -2, 2, -127):
        fail("lanes_int8 extraction", 0, 0, "got %r" % (lanes_int8(reg),))

    # Raw byte 0x80 is -128, not +128 (SPEC.md §1.1: sext8).
    case_count += 1
    if lanes_int8(pack_reg([0x80] * 8))[0] != -128:
        fail("raw 0x80 must decode as -128", -128, lanes_int8(pack_reg([0x80] * 8))[0])

    # The dot product itself must stay inside the 19-bit accumulator.
    case_count += 1
    worst = dot_product(pack_reg([-128 & U8_MASK] * 8), pack_reg([-128 & U8_MASK] * 8))
    if worst != 131072 or not ACC_MIN <= worst <= ACC_MAX:
        fail("worst-case sum 131072 fits 19-bit signed", 131072, worst)

    case_count += 1
    worst_neg = dot_product(pack_reg([-128 & U8_MASK] * 8), pack_reg([127] * 8))
    if worst_neg != -130048 or not ACC_MIN <= worst_neg <= ACC_MAX:
        fail("worst-case negative sum -130048 fits 19-bit signed",
             -130048, worst_neg)

    # Operand domain errors are programming errors, not illegal instructions.
    for name, bad in (("2**128", 1 << VLEN), ("-1", -1), ("string", "0")):
        case_count += 1
        try:
            vdot_vv(bad, 0)
        except (TypeError, ValueError):
            pass
        except Exception as exc:  # noqa: BLE001
            fail("operand %s rejected" % name, 1, 0, "wrong exception %r" % (exc,))
        else:
            fail("operand %s rejected" % name, 1, 0, "no exception raised")

    # SPEC.md §2.2 machine-code example and round-trip.
    case_count += 1
    encoded = encode_vdot_vv(vd=3, vs2=2, vs1=1)
    if encoded != 0x3A20A1D7:
        fail("encode vdot.vv v3, v2, v1", 0x3A20A1D7, encoded)

    case_count += 1
    if decode_vdot_vv(0x3A20A1D7) != (3, 2, 1):
        fail("decode 0x3A20A1D7", 0, 0,
             "got %r, expected (3, 2, 1)" % (decode_vdot_vv(0x3A20A1D7),))

    # vm=0 must not decode as vdot.vv (SPEC.md §1.3).
    case_count += 1
    if decode_vdot_vv(0x3A20A1D7 & ~(1 << 25)) is not None:
        fail("vm=0 word must not decode as vdot.vv", 0, 1)

    # Register ids outside [0, 31] are rejected by the encoder.
    case_count += 1
    try:
        encode_vdot_vv(vd=32, vs2=0, vs1=0)
    except ValueError:
        pass
    else:
        fail("encoder rejects vd=32", 1, 0)

    # Every legal encoding round-trips.
    case_count += 1
    bad_roundtrip = None
    for vd in range(32):
        for vs2 in range(32):
            for vs1 in range(32):
                if decode_vdot_vv(encode_vdot_vv(vd, vs2, vs1)) != (vd, vs2, vs1):
                    bad_roundtrip = (vd, vs2, vs1)
    if bad_roundtrip is not None:
        fail("encode/decode round-trip over all register ids", 1, 0,
             "first failure at vd/vs2/vs1 = %r" % (bad_roundtrip,))


# ---------------------------------------------------------------------------
# State / M08 cases (SPEC.md §1.1 2026-11-01, ALGORITHM.md §3.1 金模型 API)
# ---------------------------------------------------------------------------

def state_cases():
    vs1 = pack_reg(range(1, 9))
    vs2 = pack_reg(range(8, 0, -1))

    # old_vd 不是语义输入：任意预填都必须得到同一 128 位结果，且高 96 位为零。
    for label, old in (
        ("old_vd=0", 0),
        ("old_vd 全 1", pack_reg([0xFF] * 8)),
        ("old_vd 高 64 位填满", pack_reg([0] * 8, tuple([0xFF] * 8))),
    ):
        check_equal_result("%s 不改变结果" % label,
                           vdot_vv(vs1, vs2, old_vd=old), vdot_vv(vs1, vs2))

    # vill / mstatus.VS。
    check_illegal("vill=1 -> illegal", vill=True)
    check_illegal("mstatus.VS=OFF -> illegal", mstatus_vs=MSTATUS_VS_OFF)
    check("mstatus.VS=initial 合法", vs1, vs2, mstatus_vs=MSTATUS_VS_INITIAL)

    # execute_vdot 四元组：vxsat sticky 不变、vs_dirty=True、vstart_next=0。
    global case_count
    for vxsat_in in (0, 1):
        case_count += 1
        vd, vs_dirty, vstart_next, vxsat_next = execute_vdot(vs1, vs2, vxsat_in=vxsat_in)
        if vxsat_next != vxsat_in:
            fail("vxsat_in=%d 应保持不变（sticky）" % vxsat_in, vxsat_in, vxsat_next)
        elif vd >> 32 != 0:
            fail("execute_vdot 的 vd 高 96 位应为 0", 0, vd >> 32)
        elif vs_dirty is not True or vstart_next != 0:
            fail("执行后状态 (vs_dirty, vstart_next)", (True, 0), (vs_dirty, vstart_next))

    # reasons 顺序固定：vs_off -> vill -> sew -> lmul -> vm -> vstart。
    case_count += 1
    try:
        vdot_vv(0, 0, sew=16, lmul=2, vm=0, vstart=1, vill=True, mstatus_vs=MSTATUS_VS_OFF)
    except IllegalInstruction as exc:
        text = " | ".join(exc.reasons)
        keys = ["mstatus.VS", "vill", "SEW", "LMUL", "vm", "vstart"]
        positions = [text.find(k) for k in keys]
        if any(p < 0 for p in positions) or positions != sorted(positions):
            fail("reasons 顺序 vs_off>vill>sew>lmul>vm>vstart", keys, positions)
    else:
        fail("六条全违反时必须非法", 1, 0)


def mutation_self_check():
    """M08：三条模型变异必须变红（ALGORITHM.md §3.1）。

    变异体：① 写回把 old_vd 高 96 位并回（MASK->32 漏清零）；② 高 96 位写 1
    （Cat(96'h1, ...) 一类）；③ 删掉 vill 判定。任一不被本套件判红，模型即无效。
    """
    import vdot_model as m

    global case_count
    case_count += 1
    vs1 = pack_reg(range(1, 9))
    vs2 = pack_reg(range(8, 0, -1))
    old_dirty = pack_reg([0xFF] * 8)
    good = m.vdot_vv(vs1, vs2, old_vd=old_dirty)
    if good >> 32 != 0:
        failures.append("mutation self-check: 参照模型自身泄漏高位，自检无效")
        return

    def leak(result32, old_vd):
        return (result32 & m.WRITE_MASK) | (old_vd & ~m.WRITE_MASK & m.REG_MASK)

    def high_ones(result32, old_vd):
        return (result32 & m.WRITE_MASK) | (1 << 32)

    real_reasons = m.illegal_reasons

    def no_vill(**kwargs):
        return [r for r in real_reasons(**kwargs) if "vill" not in r]

    mutants = [
        ("M1 写回并回 old_vd 高位（MASK->32）", "writeback", leak,
         lambda: (m.vdot_vv(vs1, vs2, old_vd=old_dirty) >> 32) != 0),
        ("M2 高 96 位写 1（Cat(96'h1,...)）", "writeback", high_ones,
         lambda: (m.vdot_vv(vs1, vs2) >> 32) != 0),
        ("M3 删掉 vill 判定", "illegal_reasons", no_vill,
         lambda: _no_vill_escapes()),
    ]

    def _no_vill_escapes():
        try:
            m.vdot_vv(0, 0, vill=True)
        except m.IllegalInstruction:
            return False
        return True

    for label, seam, replacement, probe in mutants:
        original = getattr(m, seam)
        setattr(m, seam, replacement)
        try:
            caught = probe()
        finally:
            setattr(m, seam, original)
        if not caught:
            failures.append(
                "mutation self-check: %s 未被判红，金模型无效（M08）" % label)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    directed_cases()
    invariant_cases()
    illegal_cases()
    random_cases(1000)
    structural_cases()
    state_cases()
    mutation_self_check()

    # Anti-vacuous-green self-check: prove ``result_problem`` -- the predicate
    # every case above relies on -- actually rejects wrong results.  Each probe
    # simulates a model that returned a corrupted vd; all must be reported.
    global case_count
    case_count += 1
    probe_vs1 = pack_reg(range(1, 9))
    probe_vs2 = pack_reg(range(8, 0, -1))
    probe_actual = vdot_vv(probe_vs1, probe_vs2)
    corrupted_outputs = [
        ("flip result bit 0", probe_actual ^ 1),
        ("flip the 19-bit boundary bit", probe_actual ^ (1 << 17)),
        ("set vd[32]", probe_actual | (1 << 32)),
        ("fill vd[127:32] with 0xFF", probe_actual | (0xFFFFFFFF << 32)),
    ]
    for probe_name, corrupted in corrupted_outputs:
        if corrupted == probe_actual:
            failures.append("self-check probe %r is degenerate" % (probe_name,))
        elif result_problem(probe_actual, corrupted) is None:
            failures.append(
                "self-check: %r was accepted by result_problem; the suite would "
                "be vacuously green" % (probe_name,))

    if failures:
        print("FAILED: %d of %d cases" % (len(failures), case_count))
        for item in failures:
            print("  - " + item)
        return 1

    print("ALL TESTS PASSED (%d cases)" % case_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
