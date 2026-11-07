#!/usr/bin/env python3
"""Golden model for the ``vdot.vv`` custom vector instruction (K=8, single result).

Single source of truth: ``design/SPEC.md`` (2026-11-01 revision).  Nothing in
this file goes beyond it:

* semantics  -> SPEC.md §1.1   ``S = sum_{i=0..7} sext19(sext8(vs1[i]) * sext8(vs2[i]))``
  - lanes are taken from ``vs1``/``vs2`` bits [63:0] only (lane ``i`` = bits
    ``[8i+7 : 8i]``, little-endian); the high 64 bits never participate;
  - each 16-bit signed product is sign-extended to 19 bits before the sum;
* write-back -> SPEC.md §1.1   ``vd[31:0] = sext32(S)``, ``vd[127:32] = 0``
  (always zeroed, independent of vta/vma/tail; full-write instruction, old
  ``vd`` is NOT a semantic input);
* legal set  -> SPEC.md §1.1/§1.3   six independent necessary conditions:
  ``SEW=8`` and ``LMUL=1`` and ``vm=1`` and ``vstart=0`` and ``vill=0`` and
  ``mstatus.VS != OFF``; anything else is an illegal instruction, and the
  illegal check takes priority over the ``vl=0`` full write;
* ``vl``/``vta``/``vma`` never change the result;
* widths     -> SPEC.md §1.4   internal ``S`` is 19-bit signed (worst case
  ``8*(-128)*(-128) = 131072`` > 18-bit signed max 131071), output is 32-bit;
* encoding   -> SPEC.md §2.2   opcode 1010111 / funct3 010 / funct6 001110 / vm 1.

API (M08, 2026-11-01):

* ``vdot_vv(...)`` returns the full **128-bit** ``vd`` (high 96 bits are zero);
* ``execute_vdot(...)`` returns ``(vd, vs_dirty, vstart_next, vxsat_next)``;
* new inputs ``vill`` / ``mstatus_vs`` / ``vxsat_in`` / ``old_vd``;
* ``old_vd`` must not influence the result -- it is kept so tests can prove
  independence (a mutant that merges it in turns the high-zero test red);
* illegal reasons are ordered ``vs_off -> vill -> sew -> lmul -> vm -> vstart``;
* ``writeback()`` and ``illegal_reasons()`` are the two monkey-patch seams used
  by the mutation self-check in ``vdot_model_test.py`` (three mutants must turn
  the suite red: old-vd leak, ``Cat(96'h1, ...)`` high bits, dropped ``vill``).

Usage::

    from vdot_model import vdot_vv, execute_vdot, IllegalInstruction

    vd = vdot_vv(vs1, vs2)                  # 128-bit register value (int)
    vd, vs_dirty, vstart_next, vxsat_next = execute_vdot(vs1, vs2)

``vs1``/``vs2`` are the full 128-bit vector register values, so the model can
be driven directly by RTL/NEMU register dumps.
"""

VLEN = 128          # SPEC.md §1.1: VLEN=128, 16 byte lanes
SEW = 8             # SPEC.md §1.1: SEW=8
LMUL = 1            # SPEC.md §1.1: LMUL=1
K = 8               # SPEC.md §1.1: reduction length (lanes 0..7)
ELEM_BITS = 8
LANE_BITS = ELEM_BITS * K          # low 64 bits participate (SPEC.md §1.1)
ACC_WIDTH = 19      # SPEC.md §1.4 / ALGORITHM.md §1.3
OUT_WIDTH = 32      # SPEC.md §1.4

REG_MASK = (1 << VLEN) - 1
OUT_MASK = (1 << OUT_WIDTH) - 1
# M08: write mask covers bits [31:0]; bits [127:32] are architecturally zero.
WRITE_MASK = 0x00000000FFFFFFFF
ACC_MIN = -(1 << (ACC_WIDTH - 1))          # -262144
ACC_MAX = (1 << (ACC_WIDTH - 1)) - 1       #  262143

# mstatus.VS states (SPEC.md §1.1).  OFF -> illegal; anything else is legal.
MSTATUS_VS_OFF = "off"
MSTATUS_VS_INITIAL = "initial"
MSTATUS_VS_CLEAN = "clean"
MSTATUS_VS_DIRTY = "dirty"

# Encoding constants, SPEC.md §2.1/§2.2.
OPCODE_OP_V = 0b1010111
FUNCT3_OPMVV = 0b010
FUNCT6_VDOT = 0b001110
VM_UNMASKED = 1


class IllegalInstruction(Exception):
    """Raised when the decoded vtype/vm/vstart/vill/VS combination is not legal.

    SPEC.md §1.1/§1.3: the legal set is the intersection of six conditions
    (SEW=8 and LMUL=1 and vm=1 and vstart=0 and vill=0 and mstatus.VS != OFF).
    """

    def __init__(self, reasons):
        self.reasons = list(reasons)
        super(IllegalInstruction, self).__init__(
            "illegal vdot.vv: " + "; ".join(self.reasons)
        )


def sext(value, bits):
    """Sign-extend the low ``bits`` of ``value`` to a Python int."""
    mask = (1 << bits) - 1
    value &= mask
    sign = 1 << (bits - 1)
    return value - (1 << bits) if value & sign else value


def _check_register(value, name):
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError("%s must be an int holding a %d-bit register value" % (name, VLEN))
    if not 0 <= value <= REG_MASK:
        raise ValueError(
            "%s=0x%x is outside the %d-bit unsigned register range [0, 0x%x]"
            % (name, value, VLEN, REG_MASK)
        )


def lanes_int8(register, name="operand"):
    """Return the 8 signed int8 lanes of ``register`` bits [63:0] (SPEC.md §1.1).

    Lane ``i`` is bits ``[8i+7 : 8i]``.  Bits [127:64] are deliberately not read.
    """
    _check_register(register, name)
    return tuple(sext((register >> (ELEM_BITS * i)) & 0xFF, ELEM_BITS) for i in range(K))


def dot_product(vs1, vs2):
    """Return the unbounded integer ``S`` (algorithm A, ALGORITHM.md §3.1)."""
    lanes1 = lanes_int8(vs1, "vs1")
    lanes2 = lanes_int8(vs2, "vs2")
    return sum(a * b for a, b in zip(lanes1, lanes2))


def illegal_reasons(*, sew=SEW, lmul=LMUL, vm=1, vstart=0,
                    vill=False, mstatus_vs=MSTATUS_VS_DIRTY):
    """Return the ordered list of reasons why this state is illegal.

    Order is fixed (ALGORITHM.md §3.1, M08):
    ``vs_off -> vill -> sew -> lmul -> vm -> vstart``.
    """
    reasons = []
    if mstatus_vs == MSTATUS_VS_OFF:
        reasons.append(
            "mstatus.VS=%r (SPEC.md §1.1: VS must not be OFF)" % (mstatus_vs,)
        )
    if vill:
        reasons.append("vill=1 (SPEC.md §1.1/§1.3: vill must be 0)")
    if sew != SEW:
        reasons.append("SEW=%r (SPEC.md §1.1/§1.3: SEW must be 8)" % (sew,))
    if lmul != LMUL:
        reasons.append("LMUL=%r (SPEC.md §1.1/§1.3: LMUL must be 1)" % (lmul,))
    if vm != 1:
        reasons.append("vm=%r (SPEC.md §1.1: vdot.vv is unmasked, vm must be 1)" % (vm,))
    if vstart != 0:
        reasons.append("vstart=%r (SPEC.md §1.1/§1.3: vstart must be 0)" % (vstart,))
    return reasons


def writeback(result32, old_vd):
    """Architectural write-back: ``vd[31:0] = result32`` and ``vd[127:32] = 0``.

    ``old_vd`` is accepted and ignored on purpose (SPEC.md §1.1: the old ``vd``
    is not a semantic input).  Keeping the parameter makes the independence
    testable and gives the mutation self-check its first seam.
    """
    _ = old_vd
    return result32 & WRITE_MASK


def execute_vdot(vs1, vs2, *, sew=SEW, lmul=LMUL, vm=1, vstart=0,
                 vl=None, vta=False, vma=False, vill=False,
                 mstatus_vs=MSTATUS_VS_DIRTY, vxsat_in=0, old_vd=0):
    """Execute one ``vdot.vv`` and return ``(vd, vs_dirty, vstart_next, vxsat_next)``.

    ``vs1``/``vs2`` are full 128-bit register values; only their low 64 bits are
    read (SPEC.md §1.1).

    * ``vd``            -- full 128-bit write-back value (high 96 bits zero);
    * ``vs_dirty``      -- ``True`` on the normal path (mstatus.VS becomes Dirty).
      The illegal path raises instead; the VS value *after* an illegal is only
      recorded by the RTL/NEMU tests (decision D04: no "unchanged" claim here);
    * ``vstart_next``   -- 0 (architectural vstart after execution);
    * ``vxsat_next``    -- ``vxsat_in`` unchanged (vxsat is sticky, SPEC.md §1.1).

    Raises:
        IllegalInstruction: if any of the six legal conditions fails; the
            exception carries the ordered ``reasons`` list.
        ValueError / TypeError: if the operands are not 128-bit register values
            (programming error, not an illegal instruction).
    """
    reasons = illegal_reasons(
        sew=sew, lmul=lmul, vm=vm, vstart=vstart, vill=vill, mstatus_vs=mstatus_vs
    )
    if reasons:
        raise IllegalInstruction(reasons)

    # SPEC.md §1.1: vl / vta / vma / old_vd do not change the result.
    _ = (vl, vta, vma)

    total = dot_product(vs1, vs2)
    if not ACC_MIN <= total <= ACC_MAX:
        # Cannot happen for int8 inputs; guards the 19-bit assumption of §1.4.
        raise AssertionError(
            "internal S=%d does not fit the %d-bit signed accumulator [%d, %d]"
            % (total, ACC_WIDTH, ACC_MIN, ACC_MAX)
        )
    vd = writeback(total & OUT_MASK, old_vd)
    return vd, True, 0, vxsat_in


def vdot_vv(vs1, vs2, *, sew=SEW, lmul=LMUL, vm=1, vstart=0,
            vl=None, vta=False, vma=False, vill=False,
            mstatus_vs=MSTATUS_VS_DIRTY, vxsat_in=0, old_vd=0):
    """Execute one ``vdot.vv`` and return the full 128-bit ``vd`` value.

    Thin wrapper over :func:`execute_vdot`; see there for the semantics and the
    illegal conditions.  Kept for compatibility with the existing 1142-case
    suite (it only needs the register value).
    """
    return execute_vdot(
        vs1, vs2, sew=sew, lmul=lmul, vm=vm, vstart=vstart,
        vl=vl, vta=vta, vma=vma, vill=vill, mstatus_vs=mstatus_vs,
        vxsat_in=vxsat_in, old_vd=old_vd,
    )[0]


def encode_vdot_vv(vd, vs2, vs1):
    """Encode ``vdot.vv vd, vs2, vs1`` (SPEC.md §2.2).  Register ids are 0..31."""
    for name, value in (("vd", vd), ("vs2", vs2), ("vs1", vs1)):
        if not isinstance(value, int) or not 0 <= value <= 31:
            raise ValueError("%s=%r must be a register id in [0, 31]" % (name, value))
    return (
        (FUNCT6_VDOT << 26)
        | (VM_UNMASKED << 25)
        | (vs2 << 20)
        | (vs1 << 15)
        | (FUNCT3_OPMVV << 12)
        | (vd << 7)
        | OPCODE_OP_V
    )


def decode_vdot_vv(word):
    """Return ``(vd, vs2, vs1)`` if ``word`` encodes ``vdot.vv``, else ``None``.

    Matches the full 25-bit pattern of SPEC.md §2.2, including funct6, funct3,
    opcode and the fixed ``vm`` bit.
    """
    word &= 0xFFFFFFFF
    if (word & 0b1111111) != OPCODE_OP_V:
        return None
    if ((word >> 12) & 0b111) != FUNCT3_OPMVV:
        return None
    if ((word >> 26) & 0b111111) != FUNCT6_VDOT:
        return None
    if ((word >> 25) & 0b1) != VM_UNMASKED:
        return None
    vd = (word >> 7) & 0b11111
    vs1 = (word >> 15) & 0b11111
    vs2 = (word >> 20) & 0b11111
    return vd, vs2, vs1


__all__ = [
    "VLEN", "SEW", "LMUL", "K", "ELEM_BITS", "LANE_BITS", "ACC_WIDTH", "OUT_WIDTH",
    "REG_MASK", "OUT_MASK", "WRITE_MASK", "ACC_MIN", "ACC_MAX",
    "MSTATUS_VS_OFF", "MSTATUS_VS_INITIAL", "MSTATUS_VS_CLEAN", "MSTATUS_VS_DIRTY",
    "IllegalInstruction", "sext", "lanes_int8", "dot_product",
    "illegal_reasons", "writeback", "execute_vdot", "vdot_vv",
    "encode_vdot_vv", "decode_vdot_vv",
]
