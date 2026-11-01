"""Testes do modulo.

A load in WB keeps its data while the multiply/divide unit stalls the
pipeline.

While the M unit computes, MEM/WB holds the instruction it has. A load
in WB must write the word it read, in every stalled cycle, even though
the load behind it in MEM keeps its read enable up and the synchronous
memory answers for that address. The program places two independent
loads before an M instruction, once on the internal RAM and once on the
second port of the flash, and the M results are checked too.

A load that crosses a word takes two steps in MEM and joins the two
words in WB. When an M instruction in EX stalls the pipeline during the
second step, the word read by the first step must still be there when
the load reaches WB, so the joined datum is the one of the two words
and not the second word twice.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.misaligned_half import load_constant
from tests.python.unittests.cores.sdram_stall import (
    _r,
    addi,
    jal_self,
    lui,
    lw,
    sw,
)

FLASH_DATA = 0x200


def mul(rd, rs1, rs2):
    """Executa mul."""
    return _r(rd, 0, rs1, rs2, 1)


def divu(rd, rs1, rs2):
    """Executa divu."""
    return _r(rd, 5, rs1, rs2, 1)


def remu(rd, rs1, rs2):
    """Executa remu."""
    return _r(rd, 7, rs1, rs2, 1)


NOP = addi(0, 0, 0)

PROGRAM = [
    NOP,
    lui(7, RAM_BASE >> 12),  # x7 = internal RAM base
    addi(2, 0, 0x11),
    addi(3, 0, 0x22),
    sw(2, 7, 0),  # RAM[0x8000] = 0x11
    sw(3, 7, 4),  # RAM[0x8004] = 0x22
    NOP,
    NOP,
    NOP,
    lw(4, 7, 0),  # x4 = 0x11, in WB while the mul stalls
    lw(5, 7, 4),  # x5 = 0x22, in MEM when the mul starts
    mul(6, 2, 3),  # independent of x4 and x5
    NOP,
    NOP,
    NOP,
    sw(4, 7, 16),
    sw(5, 7, 20),
    sw(6, 7, 24),  # 0x11 * 0x22
    addi(9, 0, FLASH_DATA),
    lw(10, 9, 0),  # flash port 2, in WB while the divu stalls
    lw(11, 9, 4),
    divu(12, 3, 2),  # 0x22 / 0x11
    remu(13, 3, 2),  # back to back with the divu: 0x22 % 0x11
    NOP,
    NOP,
    NOP,
    sw(10, 7, 28),
    sw(11, 7, 32),
    sw(12, 7, 36),
    sw(13, 7, 40),
    addi(14, 0, 1),
    sw(14, 7, DONE_ADDR - RAM_BASE),  # the program finished
    jal_self(),
]

FLASH = {FLASH_DATA: 0xA5A5, FLASH_DATA + 4: 0x5A5A}

EXPECTED_RAM = {
    0x8010: 0x11,
    0x8014: 0x22,
    0x8018: 0x242,
    0x801C: 0xA5A5,
    0x8020: 0x5A5A,
    0x8024: 0x2,
    0x8028: 0x0,
}


@cocotb.test()
async def test_load_in_wb_during_m_stall(dut):
    """Verifica load in wb during m stall.

    Registers hold the loaded words and the M results after the stalls.
    """
    ram = await run_program(dut, PROGRAM, flash=FLASH, max_cycles=1500)
    for addr, want in EXPECTED_RAM.items():
        check_equal(
            ram.get(addr),
            want,
            f"RAM[0x{addr:08X}] = {ram.get(addr, 0):#x}, expected {want:#x}",
        )


CROSSING_WORDS = (0x44F6A577, 0x00112233, 0x8899AABB)
CROSSING_OFFSETS = (1, 2, 3)
CROSSING_SLOT = 0x100
CROSSING_BUFFER = 0x400


def _crossing_program():
    """Build one crossing load per offset, each followed by a stalling mul.

    Returns the program and the value each result slot must hold.
    """
    program = [NOP, lui(7, RAM_BASE >> 12), addi(8, 7, CROSSING_BUFFER)]
    for index, word in enumerate(CROSSING_WORDS):
        program += load_constant(6, word) + [sw(6, 8, 4 * index)]
    program += [addi(2, 0, 3), NOP, NOP, NOP]
    memory = b"".join(word.to_bytes(4, "little") for word in CROSSING_WORDS)
    expected = {}
    for number, offset in enumerate(CROSSING_OFFSETS):
        result = 10 + number
        program += [
            lw(result, 8, offset),
            mul(12 + number, 2, 2),
            NOP,
            NOP,
            NOP,
            sw(result, 7, CROSSING_SLOT + 4 * number),
        ]
        expected[RAM_BASE + CROSSING_SLOT + 4 * number] = int.from_bytes(
            memory[offset : offset + 4], "little"
        )
    program += [
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    return program, expected


@cocotb.test()
async def test_crossing_load_in_wb_during_m_stall(dut):
    """Verifica crossing load in wb during m stall.

    The mul starts while the load is in the second step of MEM, so the
    pipeline stays stopped with the memory answering the second word.
    """
    program, expected = _crossing_program()
    ram = await run_program(dut, program, max_cycles=1500)
    for addr, want in expected.items():
        check_equal(
            ram.get(addr),
            want,
            f"RAM[0x{addr:08X}] = {ram.get(addr, 0):#x}, expected {want:#x}",
        )
