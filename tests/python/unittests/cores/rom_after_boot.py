"""Testes do modulo.

The core with an external ROM right after the BOOT_MEMORY,
[0x1000, 0x8000), and the internal RAM at 0x8000.

Code in the ROM is fetched through the instruction cache port, a load
from the ROM region goes to the external port, and the internal RAM
keeps answering at its own base.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.harness import DONE_ADDR, run_program
from tests.python.unittests.cores.sdram_stall import (
    addi,
    jal_self,
    lui,
    lw,
    sw,
)

ROM_BASE = 0x1000
ROM_DATA = 0x2000
RAM_BASE = 0x8000
WORD = 0xCAFEBABE


def _jalr(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x67


BOOT = [
    addi(0, 0, 0),
    lui(1, ROM_BASE >> 12),  # x1 = 0x1000
    _jalr(0, 1, 0),  # jump to the ROM
]
ROM_CODE = [
    lui(7, RAM_BASE >> 12),
    addi(2, 0, 0x55),
    sw(2, 7, 0),  # RAM[0x8000] = 0x55, the internal RAM
    lui(3, ROM_DATA >> 12),
    lw(4, 3, 0),  # x4 = ROM[0x2000], through the external port
    sw(4, 7, 4),  # RAM[0x8004]
    addi(10, 0, 1),
    sw(10, 7, DONE_ADDR - RAM_BASE),
    jal_self(),
]


@cocotb.test()
async def test_rom_after_the_boot_memory(dut):
    """Verifica a ROM externa logo depois da BOOT_MEMORY.

    The code runs from 0x1000, the ROM data comes from the external port
    and the RAM at 0x8000 stays internal.
    """
    imem = {4 * i: w for i, w in enumerate(BOOT)}
    imem.update({ROM_BASE + 4 * i: w for i, w in enumerate(ROM_CODE)})
    ram = await run_program(
        dut,
        [],
        imem=imem,
        flash_port_value=0xFFFFFFFF,
        sdram={ROM_DATA: WORD},
    )
    check_equal(ram[RAM_BASE], 0x55)
    check_equal(ram[RAM_BASE + 4], WORD)
