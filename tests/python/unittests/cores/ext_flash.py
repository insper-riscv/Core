"""Testes do modulo.

The core with the memory map of the sdram platform: the flash at
0x20000000 shares the external port with the SDRAM.

Loads and stores to the flash and to the SDRAM go through the same port,
a misaligned load across two words of the flash runs in hardware, and
the internal RAM port (here the result area) keeps working for low
addresses.
"""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.cores.harness import DONE_ADDR, run_program
from tests.python.unittests.cores.sdram_stall import (
    addi,
    jal_self,
    lui,
    lw,
    sw,
)

FLASH_BASE = 0x20000000
SDRAM_BASE = 0x40000000
RAM_BASE = 0x8000
W0, W1 = 0x11223344, 0x55667788

PROGRAM = [
    addi(0, 0, 0),  # nop: the first word after reset is not executed
    lui(1, FLASH_BASE >> 12),  # x1 = flash base
    lui(2, SDRAM_BASE >> 12),  # x2 = SDRAM base
    lui(7, RAM_BASE >> 12),  # x7 = internal RAM base (the result area)
    lw(3, 1, 0),  # x3 = flash[0]
    lw(4, 1, 4),  # x4 = flash[4], back to back on the external port
    sw(3, 2, 0),  # SDRAM[0] = x3
    sw(4, 2, 4),  # SDRAM[4] = x4
    lw(5, 2, 0),  # x5 = SDRAM[0]
    sw(5, 7, 0),  # RAM[0x8000] = flash[0] through the SDRAM
    lw(6, 1, 1),  # misaligned across two words of the flash
    sw(6, 7, 4),  # RAM[0x8004]
    lw(8, 2, 3),  # misaligned across two words of the SDRAM
    sw(8, 7, 8),  # RAM[0x8008]
    addi(10, 0, 1),
    sw(10, 7, DONE_ADDR - RAM_BASE),
    jal_self(),
]


async def _run(dut, stall_for=None):
    external = {FLASH_BASE: W0, FLASH_BASE + 4: W1, SDRAM_BASE + 4: 0xAABBCCDD}
    return await run_program(
        dut, PROGRAM, sdram=external, sdram_stall=stall_for
    ), external


def _check(ram, external):
    check_equal(ram[0x8000], W0)
    check_equal(ram[0x8004], ((W0 >> 8) | (W1 << 24)) & 0xFFFFFFFF)
    # SDRAM[0] = W0 and SDRAM[4] = W1 were stored, so the read across
    # them is the same pair
    check_equal(ram[0x8008], ((W0 >> 24) | (W1 << 8)) & 0xFFFFFFFF)
    check_true(external[SDRAM_BASE] == W0 and external[SDRAM_BASE + 4] == W1)
    check_true(
        external[FLASH_BASE] == W0 and external[FLASH_BASE + 4] == W1,
        "the program did not store to the flash",
    )


@cocotb.test()
async def test_flash_and_sdram_share_the_external_port(dut):
    """Verifica flash and sdram share the external port."""
    _check(*await _run(dut))


@cocotb.test()
async def test_the_same_result_with_stalls(dut):
    """Verifica the same result with stalls."""
    _check(*await _run(dut, stall_for=lambda n: (n * 3) % 5))


@cocotb.test()
async def test_code_in_the_flash_is_fetched_through_the_instruction_cache(dut):
    """Verifica a busca de código da flash pela cache de instruções.

    The PC moves from the boot ROM into 0x20000000; the word comes from
    the cache port, not the flash port.
    """
    boot = [
        addi(0, 0, 0),
        lui(1, FLASH_BASE >> 12),
        _jalr(0, 1, 0),  # jump to the flash
    ]
    flash_code = [
        lui(7, RAM_BASE >> 12),
        addi(2, 0, 0x55),
        sw(2, 7, 0),  # RAM[0x8000] = 0x55
        addi(10, 0, 1),
        sw(10, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    imem = {4 * i: w for i, w in enumerate(boot)}
    imem.update({FLASH_BASE + 4 * i: w for i, w in enumerate(flash_code)})
    ram = await run_program(dut, [], imem=imem, flash_port_value=0xFFFFFFFF)
    check_equal(ram[0x8000], 0x55)


def _jalr(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x67
