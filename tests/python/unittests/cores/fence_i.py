"""Testes do modulo.

FENCE.I: code that rewrites itself in the SDRAM runs the new instruction
only after a FENCE.I.

The instruction cache is a Python model that copies a 16-byte line from
the backing store on the first fetch and serves that copy from then on,
so a store to code that is already in the cache is invisible until the
core pulses ic_inval.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.fetch_stall import (
    BOOT,
    CODE_BASE,
    addi,
    jal,
    jalr,
    lui,
    sw,
)
from tests.python.unittests.cores.sdram_stall import RAM_BASE, _bytes_merge

FENCE_I = 0x0000100F
NOP = 0x00000013
TARGET = 14  # word index of the instruction that gets rewritten
NEW_INSTR = addi(9, 0, 2)  # 0x00200493


def program(fence):
    """Executa program."""
    return [
        lui(1, CODE_BASE >> 12),
        lui(7, RAM_BASE >> 12),
        lui(10, NEW_INSTR >> 12),
        addi(10, 10, NEW_INSTR & 0xFFF),
        jal(5, (TARGET - 4) * 4),  # first run of the target: x9 = 1
        addi(11, 9, 0),
        sw(10, 1, TARGET * 4),  # rewrite the target
        fence,
        jal(5, (TARGET - 8) * 4),  # second run of the target
        sw(9, 7, 0),
        sw(11, 7, 4),
        addi(12, 0, 1),
        sw(12, 7, 0x7C),
        0x0000006F,
        addi(9, 0, 1),  # TARGET
        jalr(0, 5, 0),
    ]


INPUT_PORTS = (
    "i_boot_rom_data",
    "i_flash_data",
    "i_flash_data2",
    "i_ram_rdata",
    "i_ic_data",
    "i_sdram_rdata",
)
RUN_CYCLES = 3000
DONE_FLAG = 0x807C


class _Model:
    """Instruction cache, backing memory and RAM around the core."""

    def __init__(self, fence, latency, flush_latency):
        """Hold the program with the given fence and the latencies."""
        self.boot = {4 * i: w for i, w in enumerate(BOOT)}
        self.backing = {
            CODE_BASE + 4 * i: w for i, w in enumerate(program(fence))
        }
        self.latency = latency
        self.flush_latency = flush_latency
        self.lines = {}  # the cache: line address -> four words
        self.dirty = {}  # stores that the data cache holds (write-back)
        self.flush_countdown = None
        self.flushes = 0
        self.ram = {}
        self.inval_pulses = 0
        self.read_pending = 0
        self.last_addr = None
        self.wait = 0

    def serve_fetch(self, dut):
        """Answer the instruction fetch through the cache."""
        addr = int(dut.o_if_addr.value) & ~3
        dut.i_ram_rdata.value = self.read_pending
        word = self.boot.get(addr, 0)
        dut.i_boot_rom_data.value = word
        dut.i_flash_data.value = word
        if int(dut.o_ic_sel.value) != 1:
            self.last_addr = None
            dut.i_ic_ready.value = 1
            return
        line = addr & ~0xF
        if line not in self.lines:
            self._fill(addr, line)
        if line in self.lines:
            dut.i_ic_data.value = self.lines[line][(addr >> 2) & 3]
            dut.i_ic_ready.value = 1
        else:
            dut.i_ic_ready.value = 0

    def _fill(self, addr, line):
        """Count the miss latency down, then fetch the line."""
        if addr != self.last_addr:
            self.wait = self.latency
            self.last_addr = addr
        if self.wait == 0:
            self.lines[line] = [
                self.backing.get(line + 4 * k, 0) for k in range(4)
            ]
        else:
            self.wait -= 1

    def _flush_now(self, dut):
        """Write the dirty stores back and tell the core."""
        self.backing.update(self.dirty)
        self.dirty.clear()
        dut.i_dc_done.value = 1

    def serve_flush(self, dut):
        """Answer the flush request of the write-back data cache."""
        dut.i_dc_done.value = 0
        if self.flush_latency is None:
            return
        if int(dut.o_dc_flush.value):
            self.flushes += 1
            if self.flush_latency < 0:
                # a data cache that answers in the very cycle of the
                # request
                self._flush_now(dut)
            else:
                self.flush_countdown = self.flush_latency
        elif self.flush_countdown == 0:
            self._flush_now(dut)
            self.flush_countdown = None
        elif self.flush_countdown is not None:
            self.flush_countdown -= 1

    def serve_memory(self, dut):
        """Apply the invalidate, SDRAM stores and RAM traffic."""
        if int(dut.o_ic_inval.value):
            self.lines.clear()
            self.inval_pulses += 1
        if int(dut.o_sdram_wren.value) and int(dut.o_mem_advance.value):
            a = int(dut.o_sdram_addr.value) & ~3
            target = self.backing if self.flush_latency is None else self.dirty
            base = target.get(a, self.backing.get(a, 0))
            target[a] = _bytes_merge(
                base,
                int(dut.o_sdram_wdata.value),
                int(dut.o_sdram_byteena.value),
            )
        if int(dut.o_ram_en.value) and int(dut.o_ram_rden.value):
            addr = int(dut.o_ram_addr.value) & ~3
            self.read_pending = self.ram.get(addr, 0)
        if int(dut.o_ram_en.value) and int(dut.o_ram_wren.value):
            a = int(dut.o_ram_addr.value) & ~3
            self.ram[a] = _bytes_merge(
                self.ram.get(a, 0),
                int(dut.o_ram_wdata.value),
                int(dut.o_ram_byteena.value),
            )


async def run(dut, fence, latency=2, flush_latency=None):
    """Run the program and return (RAM, (invalidate pulses, flushes)).

    With flush_latency the data cache is write-back: a store stays dirty
    in the cache and reaches the backing memory only when the core asks
    for a flush and the model answers dc_done flush_latency cycles later
    (a negative value: in the very cycle of the request).
    """
    model = _Model(fence, latency, flush_latency)

    dut.i_rst.value = 1
    for sig in INPUT_PORTS:
        getattr(dut, sig).value = 0
    dut.i_ic_ready.value = 0
    dut.i_sdram_ready.value = 1
    dut.i_dc_done.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    for _ in range(RUN_CYCLES):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        model.serve_fetch(dut)
        model.serve_flush(dut)
        # the answer of the data cache reaches the core
        await Timer(1, unit="ns")
        model.serve_memory(dut)
        if model.ram.get(DONE_FLAG) == 1:
            break
    return model.ram, (model.inval_pulses, model.flushes)


@cocotb.test()
async def test_fence_i_makes_the_new_instruction_run(dut):
    """Verifica fence i makes the new instruction run."""
    ram, (pulses, _) = await run(dut, FENCE_I)
    check_equal(ram.get(0x8004), 1, "the first run of the target")
    check_equal(
        ram.get(0x8000),
        2,
        f"the rewritten instruction did not run: x9 = {ram.get(0x8000)}",
    )
    check_equal(pulses, 1, f"{pulses} invalidate pulses for one FENCE.I")


@cocotb.test()
async def test_without_fence_i_the_cache_is_stale(dut):
    """Verifica without fence i the cache is stale.

    The model catches the missing fence: a NOP in its place leaves the
    old instruction in the cache.
    """
    ram, (pulses, _) = await run(dut, NOP)
    check_equal(ram.get(0x8000), 1)
    check_equal(pulses, 0)


@cocotb.test()
async def test_fence_i_with_other_latencies(dut):
    """Verifica fence i with other latencies."""
    for lat in (0, 1, 5):
        ram, _ = await run(dut, FENCE_I, latency=lat)
        check_equal(ram.get(0x8000), 2, f"latency {lat}")
        check_equal(ram.get(0x8004), 1, f"latency {lat}")
