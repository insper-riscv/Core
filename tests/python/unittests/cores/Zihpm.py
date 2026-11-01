"""Testes do modulo.

Event counters on the core: a program counts its own taken branches and
load-use stalls.

The program selects an event in mhpmevent3 or mhpmevent4, runs a loop of
known length and reads the counter back, so the events of the core reach
the right counter with the right count.
"""

import cocotb

from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.IllegalInstruction import NOP
from tests.python.unittests.cores.MisalignedHalf import lw
from tests.python.unittests.cores.SdramStall import (
    addi,
    beq,
    jal_self,
    lui,
    sw,
)

MHPMEVENT3, MHPMEVENT4 = 0x323, 0x324
MHPMCOUNTER3, MHPMCOUNTER4 = 0xB03, 0xB04
HPMCOUNTER3 = 0xC03
MCOUNTINHIBIT = 0x320


def csr(funct3, rd, rs1, addr):
    """Executa csr."""
    return (addr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x73


def csrrw(rd, addr, rs1):
    """Executa csrrw."""
    return csr(0b001, rd, rs1, addr)


def csrrs(rd, addr, rs1=0):
    """Executa csrrs."""
    return csr(0b010, rd, rs1, addr)


def bne(rs1, rs2, imm):
    """Executa bne."""
    return beq(rs1, rs2, imm) | (1 << 12)


def muldiv(funct3, rd, rs1, rs2):
    """Executa muldiv."""
    return (
        (1 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | 0x33
    )


DIV, REM = 0b100, 0b110


def program(event, iterations, body):
    """Executa program.

    Select `event` in mhpmevent3, run `body` `iterations` times and
    store the counter at RAM[0].
    """
    return [
        NOP,
        lui(7, RAM_BASE >> 12),
        addi(5, 0, event),
        csrrw(0, MHPMEVENT3, 5),
        addi(6, 0, iterations),
        *body,
        addi(6, 6, -1),
        bne(6, 0, -(4 * (len(body) + 1))),
        csrrs(8, MHPMCOUNTER3),
        sw(8, 7, 0),
        csrrs(9, HPMCOUNTER3),
        sw(9, 7, 4),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]


@cocotb.test()
async def test_taken_branches_are_counted(dut):
    """Verifica taken branches are counted."""
    ram = await run_program(dut, program(3, 10, [NOP]), max_cycles=3000)
    # the loop branch is taken nine times and falls through on the tenth
    assert ram[RAM_BASE] == 9
    assert ram[RAM_BASE + 4] == 9, "the user mirror reads the same counter"


@cocotb.test()
async def test_load_use_stalls_are_counted(dut):
    """Verifica load use stalls are counted."""
    # a load and the use of its result
    body = [lw(10, 7, 8), addi(11, 10, 1)]
    ram = await run_program(dut, program(8, 6, body), max_cycles=3000)
    # the use waits two cycles for the load: one with the load in EX and
    # one with it in MEM
    assert ram[RAM_BASE] == 12, (
        f"two stall cycles per iteration, counted {ram[RAM_BASE]}"
    )


@cocotb.test()
async def test_event_zero_counts_nothing(dut):
    """Verifica event zero counts nothing."""
    ram = await run_program(dut, program(0, 10, [NOP]), max_cycles=3000)
    assert ram[RAM_BASE] == 0


@cocotb.test()
async def test_mcountinhibit_holds_the_counter(dut):
    """Verifica mcountinhibit holds the counter."""
    prog = program(3, 10, [NOP])
    # inhibit the counter before the loop: bit 3 of mcountinhibit
    prog[4:4] = [addi(12, 0, 1 << 3), csrrw(0, MCOUNTINHIBIT, 12)]
    ram = await run_program(dut, prog, max_cycles=3000)
    assert ram[RAM_BASE] == 0


@cocotb.test()
async def test_fused_pairs_are_counted(dut):
    """Verifica fused pairs are counted.

    Event 9 counts the REM that reuses the quotient and the remainder of
    the DIV before it.
    """
    prog = program(9, 3, [muldiv(DIV, 12, 10, 11), muldiv(REM, 13, 10, 11)])
    prog[4:4] = [addi(10, 0, 1000), addi(11, 0, 7)]
    ram = await run_program(dut, prog, max_cycles=6000)
    # the first DIV of the loop runs in full, the REM is fused; from the
    # second iteration on the record holds the DIV again (the fused REM
    # leaves it as it was), so every REM is fused
    assert ram[RAM_BASE] == 3, (
        f"one fused operation per iteration, counted {ram[RAM_BASE]}"
    )


@cocotb.test()
async def test_divider_stall_is_counted(dut):
    """Event 1 counts the cycles that a division holds the pipeline."""
    prog = program(1, 1, [muldiv(DIV, 12, 10, 11)])
    prog[4:4] = [addi(10, 0, 1000), addi(11, 0, 7)]
    ram = await run_program(dut, prog, max_cycles=3000)
    assert ram[RAM_BASE] >= 32, (
        f"a division stalls for more than 32 cycles, counted {ram[RAM_BASE]}"
    )
