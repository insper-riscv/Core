"""Testes do modulo.

With Zicsr the core handles an exception at mtvec, so o_trap stays low.
The pulse o_trap_take marks the cycle in which the core takes it.

ECALL, EBREAK, an undefined encoding and a misaligned load to the
peripheral window (taken in MEM) each raise o_trap_take for exactly one
cycle, while the legal instructions between them raise none.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import (
    HANDLER_WORD,
    MCAUSE,
    MEPC,
    MRET,
    MTVEC,
    NOP,
    csrrs,
    csrrw,
)
from tests.python.unittests.cores.misaligned_half import lw
from tests.python.unittests.cores.sdram_stall import addi, jal_self, lui, sw

ECALL = 0x00000073
EBREAK = 0x00100073
UNDEFINED = 0xFFFFFFFF
PERIPHERAL = 0x80000
MIN_TRAP_CYCLE = 4
TRAPPING = [ECALL, EBREAK, UNDEFINED, lw(24, 16, 2)]


def build():
    """Executa build."""
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(16, PERIPHERAL),
        lui(7, RAM_BASE >> 12),
    ]
    for word in TRAPPING:
        program += [addi(10, 10, 1), word, addi(10, 10, 1), NOP]
    program += [
        sw(10, 7, 0),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    check_true(len(program) < HANDLER_WORD)
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        csrrs(8, MEPC, 0),
        addi(8, 8, 4),
        csrrw(0, MEPC, 8),
        MRET,
    ]
    return program


@cocotb.test()
async def test_trap_take_is_a_one_cycle_pulse(dut):
    """Verifica trap take is a one cycle pulse.

    Four exceptions give four pulses, never two in a row, and o_trap
    stays low because the core has the CSRs to record them.
    """
    state = {"pulses": 0, "last": 0, "cycle": 0}

    def watch(dut):
        """Executa watch."""
        take = int(dut.o_trap_take.value)
        state["cycle"] += 1
        check_equal(int(dut.o_trap.value), 0, "o_trap pulsed with Zicsr")
        check_true(
            not (take and state["last"]), "o_trap_take held for two cycles"
        )
        # The first fetch answers with an empty word before the program
        # memory has been read.
        if state["cycle"] > MIN_TRAP_CYCLE:
            state["pulses"] += take
        state["last"] = take

    ram = await run_program(dut, build(), monitor=watch, max_cycles=4000)
    check_equal(
        state["pulses"],
        len(TRAPPING),
        f"{state['pulses']} pulses, expected {len(TRAPPING)}",
    )
    check_equal(
        ram[RAM_BASE],
        2 * len(TRAPPING),
        "the program did not resume after each trap",
    )
