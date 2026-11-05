"""Testes do modulo.

zimop_decode: the Zimop extension claims the 32 encodings of mop.r.n and
the 8 of mop.rr.n (SYSTEM, funct3 = 100) and leaves everything else
alone.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

SYSTEM = 0b1110011
OP_IMM = 0b0010011
ALU_BGEU = 0b11111
RESERVED_FUNCT3 = 0b100


def mop_r(n, rd=0, rs1=0):
    """Encode mop.r.n (n = 0 to 31)."""
    return (
        (1 << 31)
        | (((n >> 4) & 1) << 30)
        | (((n >> 2) & 3) << 26)
        | (0b0111 << 22)
        | ((n & 3) << 20)
        | (rs1 << 15)
        | (RESERVED_FUNCT3 << 12)
        | (rd << 7)
        | SYSTEM
    )


def mop_rr(n, rd=0, rs1=0, rs2=0):
    """Encode mop.rr.n (n = 0 to 7)."""
    return (
        (1 << 31)
        | (((n >> 2) & 1) << 30)
        | ((n & 3) << 26)
        | (1 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (RESERVED_FUNCT3 << 12)
        | (rd << 7)
        | SYSTEM
    )


async def _outputs(dut, instr):
    dut.i_instr.value = instr
    await Timer(1, unit="ns")
    return tuple(
        int(getattr(dut, name).value)
        for name in ("o_is_zimop", "o_we_reg", "o_alu_op", "o_opcode")
    )


@cocotb.test()
async def test_manual_reference_encodings(dut):
    """Verifica manual reference encodings.

    mop.r.0 and mop.rr.0 have the words the manual and the GNU
    assembler give.
    """
    check_equal(mop_r(0), 0x81C04073, "mop.r.0")
    check_equal(mop_rr(0), 0x82004073, "mop.rr.0")
    for word in (0x81C04073, 0x82004073):
        got = await _outputs(dut, word)
        check_equal(got[0], 1, f"{word:#x}: {got}")


@cocotb.test()
async def test_claims_every_mop_r(dut):
    """Verifica claims every mop.r.n.

    The 32 values of n, with several rd and rs1, raise the write enable
    and the zero-result ALU operation and hide the SYSTEM opcode.
    """
    for n in range(32):
        for rd, rs1 in ((0, 0), (1, 31), (31, 1), (17, 17)):
            got = await _outputs(dut, mop_r(n, rd, rs1))
            check_equal(got, (1, 1, ALU_BGEU, OP_IMM), f"mop.r.{n}: {got}")


@cocotb.test()
async def test_claims_every_mop_rr(dut):
    """Verifica claims every mop.rr.n.

    The 8 values of n, with several rd, rs1 and rs2, are claimed.
    """
    for n in range(8):
        for rd, rs1, rs2 in ((0, 0, 0), (1, 31, 30), (31, 1, 2), (9, 9, 9)):
            got = await _outputs(dut, mop_rr(n, rd, rs1, rs2))
            check_equal(got, (1, 1, ALU_BGEU, OP_IMM), f"mop.rr.{n}: {got}")


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Verifica leaves everything else alone.

    Flipping any fixed bit of any of the 40 encodings, another funct3 or
    another opcode, drops the claim.
    """
    low = [*range(14, 11, -1), *range(6, -1, -1)]
    fixed_r = [31, 29, 28, 24, 23, 22, *low]
    fixed_rr = [31, 29, 28, 25, *low]
    for n in range(32):
        for bit in fixed_r:
            got = await _outputs(dut, mop_r(n) ^ (1 << bit))
            check_equal(got[0], 0, f"mop.r.{n} bit {bit}: {got}")
    for n in range(8):
        for bit in fixed_rr:
            got = await _outputs(dut, mop_rr(n) ^ (1 << bit))
            check_equal(got[0], 0, f"mop.rr.{n} bit {bit}: {got}")
    for instr in (
        0x00000073,  # ecall
        0x00100073,  # ebreak
        0x30200073,  # mret
        0x10500073,  # wfi
        0x30529073,  # csrrw
        0x00000013,  # nop
    ):
        got = await _outputs(dut, instr)
        check_equal(got[0], 0, f"{instr:#x}: {got}")
