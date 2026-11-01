"""Testes do modulo.

With the Zifencei extension FENCE.I is a legal instruction: it does not
trap and the program goes on.
"""

import cocotb

from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.IllegalInstruction import (
    HANDLER_WORD,
    LOG_BASE,
    MCAUSE,
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.SdramStall import addi, jal_self, lui, sw

FENCE_I = 0x0000100F


def build():
    """Executa build."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(10, 0, 0),
        FENCE_I,
        addi(10, 10, 1),
        FENCE_I,
        addi(10, 10, 1),
        sw(10, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
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
async def test_fence_i_is_legal_with_zifencei(dut):
    """Verifica fence i is legal with zifencei.

    Two FENCE.I run without a trap and the instruction after each one
    executes.
    """
    ram = await run_program(dut, build(), max_cycles=2000)
    assert LOG_BASE not in ram, (
        f"FENCE.I trapped with mcause {ram.get(LOG_BASE)}"
    )
    assert ram[RAM_BASE + 4] == 2
