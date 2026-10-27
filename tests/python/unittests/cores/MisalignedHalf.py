"""A halfword access at offset 1 runs in the RAM; a misaligned access outside the main memory traps.

LH, LHU and SH at offset 1 stay inside one word, so the core executes them. Any misaligned access
outside the main memory (the flash and the peripheral window), even inside a word, traps with
mcause 4 or 6 and has no effect. The accesses that cross a word run in the two-step unit, which
the CoreMisaligned test covers.
"""

import cocotb

from tests.python.unittests.cores.harness import DONE_ADDR, RAM_BASE, run_program
from tests.python.unittests.cores.IllegalInstruction import (
    HANDLER_WORD, LOG_BASE, MCAUSE, MEPC, MRET, MTVEC, NOP, csrrs, csrrw,
)
from tests.python.unittests.cores.SdramStall import _i, _s, addi, jal_self, lui, sw

BUFFER = RAM_BASE + 0x200
WORD0, WORD1, HALFWORD = 0x44F6A577, 0x00112233, 0xBEEF
UNTOUCHED = 0x55


def lw(rd, rs1, imm):
    return _i(0x03, rd, 0b010, rs1, imm)


def lh(rd, rs1, imm):
    return _i(0x03, rd, 0b001, rs1, imm)


def lhu(rd, rs1, imm):
    return _i(0x03, rd, 0b101, rs1, imm)


def sh(rs2, rs1, imm):
    return _s(0b001, rs1, rs2, imm)


def load_constant(rd, value):
    upper = (value + 0x800) >> 12
    return [lui(rd, upper & 0xFFFFF), addi(rd, rd, value - (upper << 12))]


TRAPPING = [  # (instruction, expected mcause)
    (lh(24, 15, 1), 4),
    (lh(24, 16, 1), 4),
    (sh(24, 16, 1), 6),
]
RESULT = {"lh": 2, "lhu": 3, "lw_word1": 4, "lw_word0": 5, "untouched": 6, "resumed": 7, "word0_after": 8,
          "word1_after": 9}


def slot(name):
    return 4 * RESULT[name]


def build():
    program = [
        NOP,
        addi(5, 0, HANDLER_WORD * 4),
        csrrw(0, MTVEC, 5),
        lui(7, RAM_BASE >> 12),
        lui(11, LOG_BASE >> 12),
        addi(11, 11, LOG_BASE & 0xFFF),
        addi(8, 7, BUFFER - RAM_BASE),
        addi(24, 0, UNTOUCHED),
        addi(10, 0, 0),
        lui(15, 1),
        lui(16, 0x80000),
        *load_constant(12, WORD0), sw(12, 8, 0),
        *load_constant(12, WORD1), sw(12, 8, 4),
        *load_constant(13, HALFWORD),
        lh(20, 8, 1), sw(20, 7, slot("lh")),
        lhu(21, 8, 1), sw(21, 7, slot("lhu")),
        sh(13, 8, 5),
        lw(22, 8, 4), sw(22, 7, slot("lw_word1")),
        lw(23, 8, 0), sw(23, 7, slot("lw_word0")),
    ]
    for word, _ in TRAPPING:
        program += [word, addi(10, 10, 1)]
    program += [
        sw(24, 7, slot("untouched")),
        sw(10, 7, slot("resumed")),
        lw(25, 8, 0), sw(25, 7, slot("word0_after")),
        lw(26, 8, 4), sw(26, 7, slot("word1_after")),
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    assert len(program) < HANDLER_WORD, len(program)
    program += [NOP] * (HANDLER_WORD - len(program))
    program += [
        csrrs(6, MCAUSE, 0),
        sw(6, 11, 0),
        addi(11, 11, 4),
        csrrs(28, MEPC, 0),
        addi(28, 28, 4),
        csrrw(0, MEPC, 28),
        MRET,
    ]
    return program


@cocotb.test()
async def test_halfword_at_offset_one_runs_and_the_rest_traps(dut):
    """The three accesses run with the right bytes; each of the three outside the main memory traps once and changes nothing."""
    ram = await run_program(dut, build(), max_cycles=6000)
    assert ram[RAM_BASE + slot("lh")] == 0xFFFFF6A5, hex(ram[RAM_BASE + slot("lh")])
    assert ram[RAM_BASE + slot("lhu")] == 0x0000F6A5, hex(ram[RAM_BASE + slot("lhu")])
    assert ram[RAM_BASE + slot("lw_word1")] == 0x00BEEF33, hex(ram[RAM_BASE + slot("lw_word1")])
    assert ram[RAM_BASE + slot("lw_word0")] == WORD0, "the store at offset 1 touched the neighbour word"
    for i, (_, cause) in enumerate(TRAPPING):
        assert ram.get(LOG_BASE + 4 * i) == cause, f"trap {i}: mcause {ram.get(LOG_BASE + 4 * i)}"
    assert LOG_BASE + 4 * len(TRAPPING) not in ram, "an access that should run trapped"
    assert ram[RAM_BASE + slot("untouched")] == UNTOUCHED, "a trapped load wrote its destination"
    assert ram[RAM_BASE + slot("resumed")] == len(TRAPPING), "the program did not resume after each trap"
    assert ram[RAM_BASE + slot("word0_after")] == WORD0, "a trapped store changed the buffer"
    assert ram[RAM_BASE + slot("word1_after")] == 0x00BEEF33, "a trapped store changed the buffer"
