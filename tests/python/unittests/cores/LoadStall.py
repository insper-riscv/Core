"""Testes do modulo.

A load in WB keeps its data while the multiply/divide unit stalls the
pipeline.

While the M unit computes, MEM/WB holds the instruction it has. A load
in WB must write the word it read, in every stalled cycle, even though
the load behind it in MEM keeps its read enable up and the synchronous
memory answers for that address. The program places two independent
loads before an M instruction, once on the internal RAM and once on the
second port of the flash, and the M results are checked too.
"""

import cocotb

from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.SdramStall import (
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
    return _r(0x33, rd, 0, rs1, rs2, 1)


def divu(rd, rs1, rs2):
    """Executa divu."""
    return _r(0x33, rd, 5, rs1, rs2, 1)


def remu(rd, rs1, rs2):
    """Executa remu."""
    return _r(0x33, rd, 7, rs1, rs2, 1)


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
    ram = await run_program(dut, PROGRAM, FLASH, max_cycles=1500)
    for addr, want in EXPECTED_RAM.items():
        assert ram.get(addr) == want, (
            f"RAM[0x{addr:08X}] = {ram.get(addr, 0):#x}, expected {want:#x}"
        )
