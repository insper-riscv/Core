"""Testes do modulo.

zihintntl_decode: a extensao Zihintntl reivindica as quatro dicas
ntl.p1, ntl.pall, ntl.s1 e ntl.all (ADD com rd = rs1 = x0 e rs2 de x2
a x5) e nenhuma outra palavra.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

OP = 0b0110011
FIRST_RS2 = 2
LAST_RS2 = 5
NTL_WORDS = {
    "ntl.p1": 0x00200033,
    "ntl.pall": 0x00300033,
    "ntl.s1": 0x00400033,
    "ntl.all": 0x00500033,
}


def add_word(rd, rs1, rs2):
    """Encode an ADD word."""
    return (rs2 << 20) | (rs1 << 15) | (rd << 7) | OP


async def _is_hint(dut, instr):
    dut.i_instr.value = instr
    await Timer(1, unit="ns")
    return int(dut.o_is_hint.value)


@cocotb.test()
async def test_manual_reference_encodings(dut):
    """Verifica manual reference encodings.

    The four hints have the words the manual gives.
    """
    for name, word in NTL_WORDS.items():
        check_equal(add_word(0, 0, (word >> 20) & 31), word, name)
        check_equal(await _is_hint(dut, word), 1, name)


@cocotb.test()
async def test_claims_only_rs2_two_to_five(dut):
    """Verifica claims only rs2 two to five.

    Every other rs2 leaves the ADD alone.
    """
    for rs2 in range(32):
        want = 1 if FIRST_RS2 <= rs2 <= LAST_RS2 else 0
        got = await _is_hint(dut, add_word(0, 0, rs2))
        check_equal(got, want, f"rs2 x{rs2}")


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Verifica leaves everything else alone.

    A nonzero rd or rs1, another funct3 or funct7, or another opcode
    drops the claim.
    """
    base = NTL_WORDS["ntl.p1"]
    for bit in (*range(7, 20), *range(25, 32), *range(0, 7)):
        got = await _is_hint(dut, base ^ (1 << bit))
        check_equal(got, 0, f"bit {bit}")
    for instr in (0x00000013, 0x0000100F, 0x0100000F, 0x40200033):
        check_equal(await _is_hint(dut, instr), 0, f"{instr:#x}")
