"""Testes do modulo.

Without Zicsr the core has no CSRs: a trap is signalled on o_trap and
the instruction has no effect.

ECALL, EBREAK, an undefined encoding and a misaligned load and store to
the peripheral window each raise o_trap for one cycle each, with the
mcause code on o_trap_cause and the instruction's PC on o_trap_pc. The
core does not redirect the PC, writes no register and starts no memory
access.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import NOP
from tests.python.unittests.cores.misaligned_half import lw
from tests.python.unittests.cores.sdram_stall import addi, jal_self, lui, sw

MIN_TRAP_CYCLE = 4

ECALL = 0x00000073
EBREAK = 0x00100073
UNDEFINED = 0xFFFFFFFF
SENTINEL = 0x55
PERIPHERAL = 0x80000


def build():
    """Executa build."""
    return [
        NOP,
        addi(24, 0, SENTINEL),
        lui(16, PERIPHERAL),
        lui(7, RAM_BASE >> 12),
        ECALL,
        EBREAK,
        UNDEFINED,
        lw(24, 16, 2),
        sw(24, 16, 2),
        sw(24, 7, 8),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


EXPECTED = [(4 * 4, 11), (5 * 4, 3), (6 * 4, 2), (7 * 4, 4), (8 * 4, 6)]


@cocotb.test()
async def test_trap_is_signalled_without_effect(dut):
    """Verifica trap is signalled without effect.

    Each of the five instructions raises o_trap once, with its own cause
    and PC, and changes nothing.
    """
    seen = []

    cycles = [0]

    def watch(dut):
        """Executa watch."""
        trap = int(dut.o_trap.value)
        cycles[0] += 1
        # The first fetch answers with an empty word before the program
        # memory has been read.
        if trap and cycles[0] > MIN_TRAP_CYCLE:
            seen.append(
                (int(dut.o_trap_pc.value), int(dut.o_trap_cause.value))
            )
        check_true(
            not int(dut.o_sdram_rden.value)
            and not int(dut.o_sdram_wren.value),
            "a trapped access reached the bus",
        )

    ram = await run_program(dut, build(), monitor=watch, max_cycles=2000)
    check_equal(seen, EXPECTED, f"signalled {seen}, expected {EXPECTED}")
    check_equal(
        ram[RAM_BASE + 8],
        SENTINEL,
        "a trapped instruction wrote its destination register",
    )
