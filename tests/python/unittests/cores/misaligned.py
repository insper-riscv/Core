"""Testes do modulo.

Word-crossing loads and stores run in the RAM and in the SDRAM, whatever
the latency of the slave.

LW and LH, LHU, SW and SH at every offset of the first and of the second
word of a buffer run on the core and the result is compared with a byte-
level model: the loads against the value the model reads, the stores
against the three words of the buffer after the access. The core has no
Zicsr, so a trap would show on o_trap and the test fails.
"""

import cocotb

from tests.python.unittests.checks import Prng, check_true
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
    sh,
)
from tests.python.unittests.cores.sdram_stall import (
    SDRAM_BASE,
    addi,
    jal_self,
    lui,
    sw,
)

MIN_TRAP_CYCLE = 4

BUFFER_OFFSET = 0x400
SLOT_BASE = 0x100
WORDS = [0x44F6A577, 0x00112233, 0x8899AABB]
STORED = 0xA1B2C3D4
OFFSETS = (0, 1, 2, 3)
BASES = (0, 4)


def _bytes(words):
    return [(w >> (8 * i)) & 0xFF for w in words for i in range(4)]


def _read(memory, address, size, signed):
    value = int.from_bytes(bytes(memory[address : address + size]), "little")
    if signed and value >> (8 * size - 1):
        value -= 1 << (8 * size)
    return value & 0xFFFFFFFF


class _Builder:
    """Assemble the program and the result expected in each slot."""

    base_reg = 8

    def __init__(self, region):
        """Start the program, with the buffer in the given region."""
        self.program = [NOP, lui(7, RAM_BASE >> 12)]
        if region == "ram":
            self.program += [addi(self.base_reg, 7, BUFFER_OFFSET)]
        else:
            self.program += [lui(self.base_reg, SDRAM_BASE >> 12)]
        self.program += load_constant(13, STORED)
        self.expected = {}
        self.slots = 0

    def result_slot(self, value):
        """Reserve the next result slot and return its offset."""
        address = RAM_BASE + SLOT_BASE + 4 * self.slots
        self.expected[address] = value
        self.slots += 1
        return SLOT_BASE + 4 * (self.slots - 1)

    def reset_buffer(self):
        """Store the initial words of the buffer."""
        for i, word in enumerate(WORDS):
            self.program += [
                *load_constant(12, word),
                sw(12, self.base_reg, 4 * i),
            ]

    def loads(self):
        """Read every misaligned address with LW, LH and LHU."""
        memory = _bytes(WORDS)
        for encode, size, signed in (
            (lw, 4, True),
            (lh, 2, True),
            (lhu, 2, False),
        ):
            for base in BASES:
                for offset in OFFSETS:
                    address = base + offset
                    value = _read(memory, address, size, signed)
                    self.program += [
                        encode(20, self.base_reg, address),
                        sw(20, 7, self.result_slot(value)),
                    ]

    def stores(self):
        """Store at every misaligned address with SW and SH."""
        for encode, size in ((sw, 4), (sh, 2)):
            for base in BASES:
                for offset in OFFSETS:
                    address = base + offset
                    memory = _bytes(WORDS)
                    memory[address : address + size] = list(
                        STORED.to_bytes(4, "little")[:size]
                    )
                    self.reset_buffer()
                    self.program.append(encode(13, self.base_reg, address))
                    for word in range(3):
                        chunk = bytes(memory[4 * word : 4 * word + 4])
                        value = int.from_bytes(chunk, "little")
                        self.program += [
                            lw(20, self.base_reg, 4 * word),
                            sw(20, 7, self.result_slot(value)),
                        ]


def _build(region):
    """Return the program and the expected result of every slot."""
    builder = _Builder(region)
    builder.reset_buffer()
    builder.loads()
    builder.stores()
    builder.program += [
        addi(14, 0, 1),
        sw(14, 7, DONE_ADDR - RAM_BASE),
        jal_self(),
    ]
    return builder.program, builder.expected


async def _run(dut, region, stall_for=None):
    program, expected = _build(region)
    trapped, cycles = [], [0]

    def watch(d):
        """Executa watch."""
        cycles[0] += 1
        # The first fetch answers with an empty word before the program
        # memory has been read.
        if cycles[0] > MIN_TRAP_CYCLE and int(d.o_trap.value):
            trapped.append(cycles[0])

    ram = await run_program(
        dut,
        program,
        max_cycles=60000,
        sdram={} if region == "sdram" else None,
        sdram_stall=stall_for,
        monitor=watch,
    )
    check_true(not trapped, "the core signalled a trap")
    wrong = {
        hex(a): (hex(ram.get(a, -1)), hex(v))
        for a, v in expected.items()
        if ram.get(a) != v
    }
    check_true(not wrong, f"slot: (got, expected) {wrong}")


@cocotb.test()
async def test_ram(dut):
    """Every case in the internal RAM."""
    await _run(dut, "ram")


@cocotb.test()
async def test_sdram_without_stall(dut):
    """Every case in the SDRAM, the slave ready in the same cycle."""
    await _run(dut, "sdram", lambda _n: 0)


@cocotb.test()
async def test_sdram_with_stalls(dut):
    """Verifica sdram with stalls.

    Every case in the SDRAM with one to five stall cycles per access.
    """
    generator = Prng(7)
    await _run(dut, "sdram", lambda _n: generator.randint(1, 5))
