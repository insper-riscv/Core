"""Event counters on the core: a program counts its own taken branches and load-use stalls.

The program selects an event in mhpmevent3 or mhpmevent4, runs a loop of known length and reads the
counter back, so the events of the core reach the right counter with the right count.
"""

import cocotb

from tests.python.unittests.cores.harness import DONE_ADDR, RAM_BASE, run_program
from tests.python.unittests.cores.IllegalInstruction import NOP
from tests.python.unittests.cores.MisalignedHalf import lw
from tests.python.unittests.cores.SdramStall import addi, beq, jal_self, lui, sw

MHPMEVENT3, MHPMEVENT4 = 0x323, 0x324
MHPMCOUNTER3, MHPMCOUNTER4 = 0xB03, 0xB04
HPMCOUNTER3 = 0xC03
MCOUNTINHIBIT = 0x320


def csr(funct3, rd, rs1, addr):
    return (addr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x73


def csrrw(rd, addr, rs1):
    return csr(0b001, rd, rs1, addr)


def csrrs(rd, addr, rs1=0):
    return csr(0b010, rd, rs1, addr)


def bne(rs1, rs2, imm):
    return beq(rs1, rs2, imm) | (1 << 12)


def program(event, iterations, body):
    """Select `event` in mhpmevent3, run `body` `iterations` times and store the counter at RAM[0]."""
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
    ram = await run_program(dut, program(3, 10, [NOP]), max_cycles=3000)
    # the loop branch is taken nine times and falls through on the tenth
    assert ram[RAM_BASE] == 9
    assert ram[RAM_BASE + 4] == 9, "the user mirror reads the same counter"


@cocotb.test()
async def test_load_use_stalls_are_counted(dut):
    body = [lw(10, 7, 8), addi(11, 10, 1)]            # a load and the use of its result
    ram = await run_program(dut, program(8, 6, body), max_cycles=3000)
    # the use waits two cycles for the load: one with the load in EX and one with it in MEM
    assert ram[RAM_BASE] == 12, f"two stall cycles per iteration, counted {ram[RAM_BASE]}"


@cocotb.test()
async def test_event_zero_counts_nothing(dut):
    ram = await run_program(dut, program(0, 10, [NOP]), max_cycles=3000)
    assert ram[RAM_BASE] == 0


@cocotb.test()
async def test_mcountinhibit_holds_the_counter(dut):
    prog = program(3, 10, [NOP])
    # inhibit the counter before the loop: bit 3 of mcountinhibit
    prog[4:4] = [addi(12, 0, 1 << 3), csrrw(0, MCOUNTINHIBIT, 12)]
    ram = await run_program(dut, prog, max_cycles=3000)
    assert ram[RAM_BASE] == 0
