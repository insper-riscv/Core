"""Testes do modulo.

Zimop on the core: the 32 mop.r.n and the 8 mop.rr.n write zero to rd
and never trap.

Each encoding runs with a destination that holds a nonzero value, a
source that is nonzero, rd = rs1 on some and rd = x0 on others. The
result is stored right after the instruction (forwarding from the
instruction), and a handler logs any exception.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    LOG_BASE,
    MCAUSE,
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
SOURCE_VALUE = 0x12345678
DIRTY = 0x55
X0_PROBE = 21
FIRST_DEST = 15
X0_CASE = 3


def _case(i):
    """Return rd and rs1 of the i-th encoding."""
    rd = FIRST_DEST + (i % 6)
    rs1 = 5
    if i % 4 == 1:
        rs1 = rd
    if i % 7 == X0_CASE:
        rd = 0
    return rd, rs1


def build():
    """Build the program that runs the 40 encodings."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(5, SOURCE_VALUE >> 12),
        addi(5, 5, SOURCE_VALUE & 0xFFF),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
    ]
    codes = [(f"mop.r.{n}", n) for n in range(32)]
    codes += [(f"mop.rr.{n}", n) for n in range(8)]
    for i, (name, n) in enumerate(codes):
        rd, rs1 = _case(i)
        if rd:
            program.append(addi(rd, 0, DIRTY))
            if rs1 == rd:
                program.append(addi(rd, 0, 7))
        if name.startswith("mop.rr"):
            program.append(mop_rr(n, rd, rs1, 5 + (i % 3)))
        else:
            program.append(mop_r(n, rd, rs1))
        if rd:
            program.append(sw(rd, 7, RESULT_BASE + 4 * i))
        else:
            program.append(add(X0_PROBE, 0, 5))
            program.append(sw(X0_PROBE, 7, RESULT_BASE + 4 * i))
    program += [
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD, len(program))
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        sw(6, 11, 0),
        addi(11, 11, 4),
        csrrs(8, MEPC, 0),
        addi(8, 8, 4),
        csrrw(0, MEPC, 8),
        MRET,
    ]
    return program


@cocotb.test()
async def test_zimop_writes_zero_without_trapping(dut):
    """Verifica zimop writes zero without trapping.

    Every destination reads zero, x0 stays zero and forwards zero, and
    the exception log stays empty.
    """
    ram = await run_program(dut, build(), max_cycles=6000)
    check_true(
        LOG_BASE not in ram, f"an exception: mcause {ram.get(LOG_BASE)}"
    )
    for i in range(40):
        rd, _ = _case(i)
        got = ram.get(RAM_BASE + RESULT_BASE + 4 * i)
        want = SOURCE_VALUE if rd == 0 else 0
        check_equal(got, want, f"encoding {i}, rd x{rd}: {got}")
