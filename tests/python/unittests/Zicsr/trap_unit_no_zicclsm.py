"""Testes do modulo.

trap_unit without the Zicclsm extension: every misaligned load and store
traps.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicsr.trap_unit import (
    CAUSE_LOAD_MISALIGNED,
    CAUSE_STORE_MISALIGNED,
    MAIN_MEMORY,
    OP_LOAD,
    OP_STORE,
    probe,
)

CASES = [
    (OP_LOAD, 0b010, [1, 2, 3], CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b001, [1, 3], CAUSE_LOAD_MISALIGNED),
    (OP_LOAD, 0b101, [1, 3], CAUSE_LOAD_MISALIGNED),
    (OP_STORE, 0b010, [1, 2, 3], CAUSE_STORE_MISALIGNED),
    (OP_STORE, 0b001, [1, 3], CAUSE_STORE_MISALIGNED),
]


@cocotb.test()
async def test_every_misaligned_access_traps(dut):
    """Verifica every misaligned access traps.

    The halfword at offset 1 traps in the main memory too, with the
    address in mtval.
    """
    for opcode, funct3, offsets, cause in CASES:
        for base in MAIN_MEMORY:
            for offset in offsets:
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
async def test_aligned_accesses_do_not_trap(dut):
    """The accesses that were already aligned stay legal."""
    for base in MAIN_MEMORY:
        for opcode, funct3, offset in [
            (OP_LOAD, 0b010, 4),
            (OP_LOAD, 0b001, 2),
            (OP_LOAD, 0b000, 3),
            (OP_STORE, 0b010, 0),
            (OP_STORE, 0b001, 2),
            (OP_STORE, 0b000, 1),
        ]:
            check_equal(
                (await probe(dut, opcode, funct3, ea=base + offset))[0],
                0,
                (opcode, funct3, offset),
            )
