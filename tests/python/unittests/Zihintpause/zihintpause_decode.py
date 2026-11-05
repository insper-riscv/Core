"""Testes do modulo.

zihintpause_decode: a extensao Zihintpause reivindica a palavra de pause
(FENCE com pred = W, succ = 0, rs1 = rd = x0) e nenhuma outra.
"""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal

PAUSE = 0x0100000F
FENCE_RW_RW = 0x0330000F
FENCE_I = 0x0000100F


async def _is_hint(dut, instr):
    dut.i_instr.value = instr
    await Timer(1, unit="ns")
    return int(dut.o_is_hint.value)


@cocotb.test()
async def test_manual_reference_encoding(dut):
    """Verifica manual reference encoding.

    pause is the word 0x0100000F.
    """
    check_equal(await _is_hint(dut, PAUSE), 1, "pause")


@cocotb.test()
async def test_leaves_everything_else_alone(dut):
    """Verifica leaves everything else alone.

    Flipping any bit of the pause word drops the claim, and the other
    FENCE forms are not hints.
    """
    for bit in range(32):
        got = await _is_hint(dut, PAUSE ^ (1 << bit))
        check_equal(got, 0, f"bit {bit}")
    for instr in (FENCE_RW_RW, FENCE_I, 0x00000013):
        check_equal(await _is_hint(dut, instr), 0, f"{instr:#x}")
