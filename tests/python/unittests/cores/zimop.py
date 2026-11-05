"""Testes do modulo.

Zimop on the core: the 32 mop.r.n and the 8 mop.rr.n write zero to rd
and never trap.

Each encoding runs with a destination that holds a nonzero value, a
source that is nonzero, rd = rs1 on some and rd = x0 on others. The
result is stored right after the instruction (forwarding from the
instruction), and a handler counts any exception.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.sdram_stall import (
    add,
    addi,
    jal_self,
    lui,
    sw,
)
from tests.python.unittests.Zimop.zimop_decode import mop_r, mop_rr

HANDLER_WORD = 256
RESULT_BASE = 0x200
COUNT_OFFSET = 0x100
SOURCE_VALUE = 0x12345678
DIRTY = 0x55
X0_PROBE = 21
FIRST_DEST = 15
X0_CASE = 3
ENCODINGS = 40
MOP_R_COUNT = 32


def _case(i):
    """Return rd and rs1 of the i-th encoding."""
    rd = FIRST_DEST + (i % 6)
    rs1 = 5
    if i % 4 == 1:
        rs1 = rd
    if i % 7 == X0_CASE:
        rd = 0
    return rd, rs1


def _prologue():
    """Return the setup: trap vector, source value and RAM pointer."""
    return [
        NOP,
        lui(7, RAM_BASE >> 12),
        lui(5, SOURCE_VALUE >> 12),
        addi(5, 5, SOURCE_VALUE & 0xFFF),
        addi(13, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 13),
    ]


def _encoding(i):
    """Return the instructions that run the i-th encoding."""
    rd, rs1 = _case(i)
    code = []
    if rd:
        code.append(addi(rd, 0, DIRTY))
        if rs1 == rd:
            code.append(addi(rd, 0, 7))
    if i < MOP_R_COUNT:
        code.append(mop_r(i, rd, rs1))
    else:
        code.append(mop_rr(i - MOP_R_COUNT, rd, rs1, 5 + (i % 3)))
    probe = rd
    if rd == 0:
        probe = X0_PROBE
        code.append(add(probe, 0, 5))
    return [*code, sw(probe, 7, RESULT_BASE + 4 * i)]


def _handler():
    """Return the handler: count the exception and skip the word."""
    return [
        addi(12, 12, 1),
        csrrs(10, MEPC, 0),
        addi(10, 10, 4),
        csrrw(0, MEPC, 10),
        MRET,
    ]


def build():
    """Build the program that runs the 40 encodings."""
    program = _prologue()
    for i in range(ENCODINGS):
        program += _encoding(i)
    program += [
        sw(12, 7, COUNT_OFFSET),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD, len(program))
    program += [NOP] * (HANDLER_WORD - len(program))
    return program + _handler()


@cocotb.test()
async def test_zimop_writes_zero_without_trapping(dut):
    """Verifica zimop writes zero without trapping.

    Every destination reads zero, x0 stays zero and forwards zero, and
    the exception count stays zero.
    """
    ram = await run_program(dut, build(), max_cycles=6000)
    check_equal(ram.get(RAM_BASE + COUNT_OFFSET), 0, "an exception")
    for i in range(ENCODINGS):
        rd, _ = _case(i)
        got = ram.get(RAM_BASE + RESULT_BASE + 4 * i)
        want = SOURCE_VALUE if rd == 0 else 0
        check_equal(got, want, f"encoding {i}, rd x{rd}: {got}")
