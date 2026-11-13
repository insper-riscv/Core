"""Testes do modulo.

trap_unit with a flash on the bus that starts right after the
BOOT_MEMORY (256 KiB) and a RAM at 0x40000000: the flash is main memory,
as the instruction cache and the data cache serve it like the RAM.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.trap_unit import (
    CAUSE_LOAD_MISALIGNED,
    CROSSING,
    IN_WORD,
    OP_LOAD,
    probe,
)

MAIN_MEMORY = [0x1000, 0x3FF00, 0x40000000, 0x43FFFFF0, 0x60000000]
OUTSIDE_MAIN_MEMORY = [0x0, 0xFFC]


@cocotb.test()
async def test_halfword_inside_a_word_is_executed_in_the_rom(dut):
    """Verifica halfword dentro de uma palavra na rom e na ram.

    Verifica halfword inside a word is executed in the ROM and the RAM.
    """
    for opcode, funct3, _ in IN_WORD:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + 1))[0],
                0,
                (opcode, funct3, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_a_word_is_executed_in_the_rom(dut):
    """Verifica acesso que cruza uma palavra na rom e na ram.

    Verifica access crossing a word is executed in the ROM and the RAM.
    """
    for opcode, funct3, offset, _ in CROSSING:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + offset))[0],
                0,
                (opcode, funct3, offset, hex(base)),
            )


@cocotb.test()
async def test_boot_memory_traps(dut):
    """Verifica que a memória de boot não executa o desalinhado.

    The BOOT_MEMORY takes the trap.
    """
    for opcode, funct3, cause in IN_WORD:
        for base in OUTSIDE_MAIN_MEMORY:
            check_equal(
                await probe(dut, opcode, funct3, ea=base + 1),
                (1, 0, cause, base + 1),
                (opcode, funct3, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_out_of_the_flash_end_traps(dut):
    """Verifica que o acesso na ultima palavra da flash nao cruza.

    The last word of the flash is followed by the hole above it, so a
    load that crosses its end traps.
    """
    check_equal(
        await probe(dut, OP_LOAD, 0b010, ea=0x3FFFF),
        (1, 0, CAUSE_LOAD_MISALIGNED, 0x3FFFF),
    )
