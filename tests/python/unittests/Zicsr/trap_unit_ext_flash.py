"""Testes do modulo.

trap_unit with the memory map of the sdram platform: the flash at
0x20000000 and the SDRAM at 0x40000000.
"""

import cocotb

from tests.python.unittests.Zicsr.trap_unit import (
    CAUSE_LOAD_MISALIGNED,
    CAUSE_STORE_MISALIGNED,
    CROSSING,
    IN_WORD,
    OP_LOAD,
    OP_STORE,
    probe,
)

MAIN_MEMORY = [0x20000000, 0x200FFFF0, 0x3FFFFF00, 0x40000000, 0x5FFFFFF0]
OUTSIDE_MAIN_MEMORY = [
    0x0,
    0x7F0,
    0x1000,
    0x8000,
    0x60000000,
    0x7FFFFFF0,
    0x80000000,
    0xD0000000,
]


@cocotb.test()
async def test_halfword_inside_a_word_is_executed_in_the_flash_and_the_sdram(
    dut,
):
    """Verifica halfword dentro de uma palavra na flash e na sdram.

    Verifica halfword inside a word is executed in the flash and the
    sdram.
    """
    for opcode, funct3, _ in IN_WORD:
        for base in MAIN_MEMORY:
            assert (await probe(dut, opcode, funct3, ea=base + 1))[0] == 0, (
                opcode,
                funct3,
                hex(base),
            )


@cocotb.test()
async def test_halfword_inside_a_word_traps_elsewhere(dut):
    """Verifica halfword inside a word traps elsewhere.

    The boot ROM, the unmapped holes and the peripherals do not run a
    misaligned access.
    """
    for opcode, funct3, cause in IN_WORD:
        for base in OUTSIDE_MAIN_MEMORY:
            assert await probe(dut, opcode, funct3, ea=base + 1) == (
                1,
                0,
                cause,
                base + 1,
            ), (opcode, funct3, hex(base))


@cocotb.test()
async def test_access_crossing_a_word_is_executed_in_the_flash_and_the_sdram(
    dut,
):
    """Verifica acesso que cruza uma palavra na flash e na sdram.

    Verifica access crossing a word is executed in the flash and the
    sdram.
    """
    for opcode, funct3, offset, _ in CROSSING:
        for base in MAIN_MEMORY:
            assert (await probe(dut, opcode, funct3, ea=base + offset))[
                0
            ] == 0, (opcode, funct3, offset, hex(base))


@cocotb.test()
async def test_access_crossing_a_word_traps_elsewhere(dut):
    """Verifica access crossing a word traps elsewhere."""
    for opcode, funct3, offset, cause in CROSSING:
        for base in OUTSIDE_MAIN_MEMORY:
            assert await probe(dut, opcode, funct3, ea=base + offset) == (
                1,
                0,
                cause,
                base + offset,
            ), (opcode, funct3, offset, hex(base))


@cocotb.test()
async def test_access_crossing_into_another_region_traps(dut):
    """Verifica access crossing into another region traps.

    The flash into the SDRAM, the SDRAM into the hole above it, and the
    boot ROM end all trap.
    """
    for opcode, funct3, ea, cause in [
        (OP_LOAD, 0b010, 0x3FFFFFFD, CAUSE_LOAD_MISALIGNED),
        (OP_LOAD, 0b001, 0x3FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b010, 0x3FFFFFFE, CAUSE_STORE_MISALIGNED),
        (OP_STORE, 0b001, 0x3FFFFFFF, CAUSE_STORE_MISALIGNED),
        (OP_LOAD, 0b010, 0x5FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b001, 0x5FFFFFFF, CAUSE_STORE_MISALIGNED),
    ]:
        assert await probe(dut, opcode, funct3, ea=ea) == (1, 0, cause, ea), (
            opcode,
            funct3,
            hex(ea),
        )
    # the last word of each region still takes an access that stays
    # inside it
    assert (await probe(dut, OP_LOAD, 0b010, ea=0x3FFFFFF9))[0] == 0
    assert (await probe(dut, OP_STORE, 0b010, ea=0x5FFFFFF9))[0] == 0
