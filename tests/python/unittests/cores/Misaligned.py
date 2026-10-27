"""Word-crossing loads and stores run in the RAM and in the SDRAM, whatever the latency of the slave.

LW and LH, LHU, SW and SH at every offset of the first and of the second word of a buffer run on
the core and the result is compared with a byte-level model: the loads against the value the model
reads, the stores against the three words of the buffer after the access. The core has no Zicsr, so
a trap would show on o_trap and the test fails.
"""

import random

import cocotb

from tests.python.unittests.cores.harness import DONE_ADDR, RAM_BASE, run_program
from tests.python.unittests.cores.IllegalInstruction import NOP
from tests.python.unittests.cores.MisalignedHalf import lh, lhu, load_constant, lw, sh
from tests.python.unittests.cores.SdramStall import SDRAM_BASE, addi, jal_self, lui, sw

BUFFER_OFFSET = 0x400
SLOT_BASE = 0x100
WORDS = [0x44F6A577, 0x00112233, 0x8899AABB]
STORED = 0xA1B2C3D4
OFFSETS = (0, 1, 2, 3)
BASES = (0, 4)


def _bytes(words):
    return [(w >> (8 * i)) & 0xFF for w in words for i in range(4)]


def _read(memory, address, size, signed):
    value = int.from_bytes(bytes(memory[address:address + size]), "little")
    if signed and value >> (8 * size - 1):
        value -= 1 << (8 * size)
    return value & 0xFFFFFFFF


def _build(region):
    """Return the program and the expected result of every slot."""
    base_reg = 8
    program = [NOP, lui(7, RAM_BASE >> 12)]
    program += [addi(base_reg, 7, BUFFER_OFFSET)] if region == "ram" else [lui(base_reg, SDRAM_BASE >> 12)]
    program += load_constant(13, STORED)
    expected, slot = {}, [0]

    def result_slot(value):
        address = RAM_BASE + SLOT_BASE + 4 * slot[0]
        expected[address] = value
        slot[0] += 1
        return SLOT_BASE + 4 * (slot[0] - 1)

    def reset_buffer():
        out = []
        for i, word in enumerate(WORDS):
            out += [*load_constant(12, word), sw(12, base_reg, 4 * i)]
        return out

    program += reset_buffer()
    memory = _bytes(WORDS)
    for name, encode, size, signed in (("lw", lw, 4, True), ("lh", lh, 2, True), ("lhu", lhu, 2, False)):
        for base in BASES:
            for offset in OFFSETS:
                address = base + offset
                program += [encode(20, base_reg, address), sw(20, 7, result_slot(_read(memory, address, size, signed)))]

    for encode, size in ((sw, 4), (sh, 2)):
        for base in BASES:
            for offset in OFFSETS:
                address = base + offset
                memory = _bytes(WORDS)
                memory[address:address + size] = list(STORED.to_bytes(4, "little")[:size])
                program += reset_buffer()
                program.append(encode(13, base_reg, address))
                for word in range(3):
                    program += [lw(20, base_reg, 4 * word),
                                sw(20, 7, result_slot(int.from_bytes(bytes(memory[4 * word:4 * word + 4]), "little")))]

    program += [addi(14, 0, 1), sw(14, 7, DONE_ADDR - RAM_BASE), jal_self()]
    return program, expected


async def _run(dut, region, stall_for=None):
    program, expected = _build(region)
    trapped, cycles = [], [0]

    def watch(d):
        cycles[0] += 1
        # The first fetch answers with an empty word before the program memory has been read.
        if cycles[0] > 4 and int(d.o_trap.value):
            trapped.append(cycles[0])

    ram = await run_program(
        dut, program, max_cycles=60000, sdram={} if region == "sdram" else None, sdram_stall=stall_for, monitor=watch,
    )
    assert not trapped, "the core signalled a trap"
    wrong = {hex(a): (hex(ram.get(a, -1)), hex(v)) for a, v in expected.items() if ram.get(a) != v}
    assert not wrong, f"slot: (got, expected) {wrong}"


@cocotb.test()
async def test_ram(dut):
    """Every case in the internal RAM."""
    await _run(dut, "ram")


@cocotb.test()
async def test_sdram_without_stall(dut):
    """Every case in the SDRAM, the slave ready in the same cycle."""
    await _run(dut, "sdram", lambda n: 0)


@cocotb.test()
async def test_sdram_with_stalls(dut):
    """Every case in the SDRAM with one to five stall cycles per access."""
    generator = random.Random(7)
    await _run(dut, "sdram", lambda n: generator.randint(1, 5))
