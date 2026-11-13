"""Testes do modulo.

trap_unit with a map where the flash is on the bus: the boot memory in
[0, 0x1000), the flash in [0x20000000, 0x40000000) and the RAM in
[0x40000000, 0x60000000). Everything but the boot memory is main
memory, which the port of the core serves.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.trap_unit import (
    CAUSE_LOAD_MISALIGNED,
    CAUSE_STORE_MISALIGNED,
    CROSSING,
    IN_WORD,
    OP_LOAD,
    OP_STORE,
    probe,
)

MAIN_MEMORY = [
    0x1000,
    0x8000,
    0x1FFFFF00,
    0x20000000,
    0x200FFFF0,
    0x3FFFFF00,
    0x40000000,
    0x5FFFFFF0,
    0x60000000,
    0x80000000,
    0xD0000000,
]
OUTSIDE_MAIN_MEMORY = [0x0, 0x7F0, 0xFF0]


@cocotb.test()
async def test_halfword_inside_a_word_is_executed_outside_the_boot_memory(
    dut,
):
    """Verifica halfword dentro de uma palavra fora da boot memory.

    The flash on the bus, the RAM and the external window run it.
    """
    for opcode, funct3, _ in IN_WORD:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + 1))[0],
                0,
                (
                    opcode,
                    funct3,
                    hex(base),
                ),
            )


@cocotb.test()
async def test_halfword_inside_a_word_traps_elsewhere(dut):
    """Verifica halfword inside a word traps elsewhere.

    The boot memory does not run a misaligned access.
    """
    for opcode, funct3, cause in IN_WORD:
        for base in OUTSIDE_MAIN_MEMORY:
            check_equal(
                await probe(dut, opcode, funct3, ea=base + 1),
                (
                    1,
                    0,
                    cause,
                    base + 1,
                ),
                (opcode, funct3, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_a_word_is_executed_outside_the_boot_memory(
    dut,
):
    """Verifica acesso que cruza uma palavra fora da boot memory.

    The flash on the bus, the RAM and the external window run it.
    """
    for opcode, funct3, offset, _ in CROSSING:
        for base in MAIN_MEMORY:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + offset))[0],
                0,
                (opcode, funct3, offset, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_a_word_traps_elsewhere(dut):
    """Verifica access crossing a word traps elsewhere."""
    for opcode, funct3, offset, cause in CROSSING:
        for base in OUTSIDE_MAIN_MEMORY:
            check_equal(
                await probe(dut, opcode, funct3, ea=base + offset),
                (
                    1,
                    0,
                    cause,
                    base + offset,
                ),
                (opcode, funct3, offset, hex(base)),
            )


@cocotb.test()
async def test_access_crossing_into_another_region_traps(dut):
    """Verifica access crossing into another region traps.

    The external window below the flash into the flash, the flash into
    the RAM, the RAM into the external window above it, and the end of
    the address space into its start all trap.
    """
    for opcode, funct3, ea, cause in [
        (OP_LOAD, 0b010, 0x1FFFFFFD, CAUSE_LOAD_MISALIGNED),
        (OP_LOAD, 0b010, 0x3FFFFFFD, CAUSE_LOAD_MISALIGNED),
        (OP_LOAD, 0b001, 0x3FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b010, 0x3FFFFFFE, CAUSE_STORE_MISALIGNED),
        (OP_STORE, 0b001, 0x3FFFFFFF, CAUSE_STORE_MISALIGNED),
        (OP_LOAD, 0b010, 0x5FFFFFFF, CAUSE_LOAD_MISALIGNED),
        (OP_STORE, 0b001, 0x5FFFFFFF, CAUSE_STORE_MISALIGNED),
        (OP_STORE, 0b010, 0xFFFFFFFE, CAUSE_STORE_MISALIGNED),
    ]:
        check_equal(
            await probe(dut, opcode, funct3, ea=ea),
            (1, 0, cause, ea),
            (
                opcode,
                funct3,
                hex(ea),
            ),
        )
    # the last word of each region still takes an access that stays
    # inside it
    check_equal((await probe(dut, OP_LOAD, 0b010, ea=0x1FFFFFF9))[0], 0)
    check_equal((await probe(dut, OP_LOAD, 0b010, ea=0x3FFFFFF9))[0], 0)
    check_equal((await probe(dut, OP_STORE, 0b010, ea=0x5FFFFFF9))[0], 0)
