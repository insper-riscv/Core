"""Testes do modulo.

Without Zicsr and without Zicclsm the core has no CSRs and does not run
a misaligned access.

Every misaligned load and store to the main memory raises o_trap for one
cycle with the cause of the access (4 for a load, 6 for a store) and the
PC of the instruction, like ECALL does with cause 11. The instruction
has no effect: no register is written and nothing reaches the memory. An
aligned access in the same program still works.
"""

import cocotb

from tests.python.unittests.checks import check_equal
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
SENTINEL = 0x55
LOAD, STORE = 0x03, 0x23


def lh(rd, rs1, imm):
    """Executa lh."""
    return (
        ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b001 << 12) | (rd << 7) | LOAD
    )


def sh(rs2, rs1, imm):
    """Executa sh."""
    return (
        ((imm >> 5 & 0x7F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (0b001 << 12)
        | ((imm & 0x1F) << 7)
        | STORE
    )


def build():
    """Executa build."""
    return [
        NOP,
        addi(24, 0, SENTINEL),
        lui(7, RAM_BASE >> 12),
        lw(24, 7, 2),
        sw(24, 7, 2),
        lh(24, 7, 1),
        sh(24, 7, 1),
        ECALL,
        sw(24, 7, 8),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


EXPECTED = [(3 * 4, 4), (4 * 4, 6), (5 * 4, 4), (6 * 4, 6), (7 * 4, 11)]


@cocotb.test()
async def test_misaligned_access_in_ram_traps_without_effect(dut):
    """Verifica misaligned access in ram traps without effect.

    Each misaligned access and the ECALL raise o_trap once with the
    right cause, and change nothing.
    """
    seen = []
    cycles = [0]

    def watch(dut):
        """Executa watch."""
        trap = int(dut.o_trap.value)
        cycles[0] += 1
        if trap and cycles[0] > MIN_TRAP_CYCLE:
            seen.append(
                (int(dut.o_trap_pc.value), int(dut.o_trap_cause.value))
            )

    ram = await run_program(dut, build(), monitor=watch, max_cycles=2000)
    check_equal(seen, EXPECTED, f"signalled {seen}, expected {EXPECTED}")
    check_equal(
        ram[RAM_BASE + 8],
        SENTINEL,
        "a trapped load wrote its destination, or the aligned store did not "
        "run",
    )
    check_equal(ram.get(RAM_BASE, 0), 0, "a trapped store reached the memory")
