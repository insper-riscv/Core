"""Testes do modulo.

An instruction right behind a load receives the data aligned and
extended, and waits two stall cycles for it.

The load data is registered at the end of WB and the forwarding reads it
from that register. Each case is a load of one width and offset, the
instruction that uses it in the next slot and a store of the result.
The values must be the aligned and extended word plus one, and the
load-use stall event must count two cycles per case.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.harness import (
    DONE_ADDR,
    RAM_BASE,
    run_program,
)
from tests.python.unittests.cores.illegal_instruction import NOP
from tests.python.unittests.cores.misaligned_half import (
    lh,
    lhu,
    load_constant,
    lw,
)
from tests.python.unittests.cores.sdram_stall import (
    _i,
    addi,
    jal_self,
    lui,
    sw,
)
from tests.python.unittests.cores.zihpm import (
    HPMCOUNTER3,
    MHPMEVENT3,
    csrrs,
    csrrw,
)

WORD = 0x8091A2B3
LOAD_USE_EVENT = 8
STALLS_PER_CASE = 2
DATA, RESULT, RAM = 10, 11, 7
COUNT_SLOT = 0x7F0
RESULT_BASE = 0x100


def lb(rd, rs1, imm):
    """Executa lb."""
    return _i(0x03, rd, 0b000, rs1, imm)


def lbu(rd, rs1, imm):
    """Executa lbu."""
    return _i(0x03, rd, 0b100, rs1, imm)


def _sign(value, bits):
    """Sign-extend `value` of `bits` bits to 32 bits."""
    if value >> (bits - 1):
        value -= 1 << bits
    return value & 0xFFFFFFFF


def _field(offset, bits):
    """Return the `bits`-bit field of WORD at byte `offset`."""
    return (WORD >> (8 * offset)) & ((1 << bits) - 1)


def _cases():
    """Return (load builder, offset, expected loaded value) per case."""
    cases = [(lb, o, _sign(_field(o, 8), 8)) for o in range(4)]
    cases += [(lbu, o, _field(o, 8)) for o in range(4)]
    cases += [(lh, o, _sign(_field(o, 16), 16)) for o in (0, 2)]
    cases += [(lhu, o, _field(o, 16)) for o in (0, 2)]
    cases.append((lw, 0, WORD))
    return cases


def _program():
    """Return the program: one load, its user and a store per case."""
    program = [
        NOP,
        lui(RAM, RAM_BASE >> 12),
        *load_constant(12, WORD),
        sw(12, RAM, 0x40),
        addi(5, 0, LOAD_USE_EVENT),
        csrrw(0, MHPMEVENT3, 5),
    ]
    for index, (load, offset, _) in enumerate(_cases()):
        program += [
            load(DATA, RAM, 0x40 + offset),
            addi(RESULT, DATA, 1),
            sw(RESULT, RAM, RESULT_BASE + 4 * index),
        ]
    program += [
        csrrs(13, HPMCOUNTER3),
        sw(13, RAM, COUNT_SLOT),
        addi(14, 0, 1),
        sw(14, RAM, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    return program


@cocotb.test()
async def test_the_dependent_gets_the_extended_data_and_waits(dut):
    """Verifica load data forwarded from WB2 and the stall cost."""
    ram = await run_program(dut, _program(), max_cycles=3000)
    cases = _cases()
    for index, (_, offset, value) in enumerate(cases):
        got = ram[RAM_BASE + RESULT_BASE + 4 * index]
        check_equal(got, (value + 1) & 0xFFFFFFFF, f"case {index} @{offset}")
    check_equal(
        ram[RAM_BASE + COUNT_SLOT],
        STALLS_PER_CASE * len(cases),
        "load-use stall cycles",
    )
