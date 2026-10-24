"""FENCE.I: code that rewrites itself in the SDRAM runs the new instruction only after a FENCE.I.

The instruction cache is a Python model that copies a 16-byte line from the backing store on
the first fetch and serves that copy from then on, so a store to code that is already in the
cache is invisible until the core pulses ic_inval.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.cores.FetchStall import (
    BOOT, CODE_BASE, addi, jal, jalr, lui, lw, sw,
)
from tests.python.unittests.cores.SdramStall import RAM_BASE, _bytes_merge

FENCE_I = 0x0000100F
NOP = 0x00000013
TARGET = 14                                   # word index of the instruction that gets rewritten
NEW_INSTR = addi(9, 0, 2)                     # 0x00200493


def program(fence):
    return [
        lui(1, CODE_BASE >> 12),
        lui(7, RAM_BASE >> 12),
        lui(10, NEW_INSTR >> 12),
        addi(10, 10, NEW_INSTR & 0xFFF),
        jal(5, (TARGET - 4) * 4),             # first run of the target: x9 = 1
        addi(11, 9, 0),
        sw(10, 1, TARGET * 4),                # rewrite the target
        fence,
        jal(5, (TARGET - 8) * 4),             # second run of the target
        sw(9, 7, 0),
        sw(11, 7, 4),
        addi(12, 0, 1),
        sw(12, 7, 0x7C),
        0x0000006F,
        addi(9, 0, 1),                        # TARGET
        jalr(0, 5, 0),
    ]


async def run(dut, fence, latency=2, flush_latency=None):
    """Run the program. With flush_latency the data cache is write-back: a store stays dirty in
    the cache and reaches the backing memory only when the core asks for a flush and the model
    answers dc_done flush_latency cycles later."""
    boot = {4 * i: w for i, w in enumerate(BOOT)}
    backing = {CODE_BASE + 4 * i: w for i, w in enumerate(program(fence))}
    lines = {}                                # the cache: line address -> four words
    dirty = {}                                # stores that the data cache holds (write-back)
    flush_countdown = None
    flushes = 0
    ram = {}
    inval_pulses = 0

    dut.i_rst.value = 1
    for sig in ("i_boot_rom_data", "i_flash_data", "i_flash_data2", "i_ram_rdata", "i_ic_data", "i_sdram_rdata"):
        getattr(dut, sig).value = 0
    dut.i_ic_ready.value = 0
    dut.i_sdram_ready.value = 1
    dut.i_dc_done.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    read_pending = 0
    last_addr = None
    wait = 0
    for _ in range(3000):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        addr = int(dut.o_if_addr.value) & ~3
        dut.i_ram_rdata.value = read_pending

        word = boot.get(addr, 0)
        dut.i_boot_rom_data.value = word
        dut.i_flash_data.value = word

        if int(dut.o_ic_sel.value) == 1:
            line = addr & ~0xF
            if line not in lines:
                if addr != last_addr:
                    wait = latency
                    last_addr = addr
                if wait == 0:
                    lines[line] = [backing.get(line + 4 * k, 0) for k in range(4)]
                else:
                    wait -= 1
            if line in lines:
                dut.i_ic_data.value = lines[line][(addr >> 2) & 3]
                dut.i_ic_ready.value = 1
            else:
                dut.i_ic_ready.value = 0
        else:
            last_addr = None
            dut.i_ic_ready.value = 1

        dut.i_dc_done.value = 0
        if flush_latency is not None:
            if int(dut.o_dc_flush.value):
                flushes += 1
                flush_countdown = flush_latency
            elif flush_countdown is not None:
                if flush_countdown == 0:
                    backing.update(dirty)
                    dirty.clear()
                    dut.i_dc_done.value = 1
                    flush_countdown = None
                else:
                    flush_countdown -= 1
        await Timer(1, unit="ns")            # the answer of the data cache reaches the core
        if int(dut.o_ic_inval.value):
            lines.clear()
            inval_pulses += 1

        if int(dut.o_sdram_wren.value) and int(dut.o_mem_advance.value):
            a = int(dut.o_sdram_addr.value) & ~3
            target = dirty if flush_latency is not None else backing
            base = target.get(a, backing.get(a, 0))
            target[a] = _bytes_merge(base, int(dut.o_sdram_wdata.value), int(dut.o_sdram_byteena.value))
        if int(dut.o_ram_en.value) and int(dut.o_ram_rden.value):
            read_pending = ram.get(int(dut.o_ram_addr.value) & ~3, 0)
        if int(dut.o_ram_en.value) and int(dut.o_ram_wren.value):
            a = int(dut.o_ram_addr.value) & ~3
            ram[a] = _bytes_merge(ram.get(a, 0), int(dut.o_ram_wdata.value), int(dut.o_ram_byteena.value))
        if ram.get(0x807C) == 1:
            break
    return ram, (inval_pulses, flushes)


@cocotb.test()
async def test_fence_i_makes_the_new_instruction_run(dut):
    ram, (pulses, _) = await run(dut, FENCE_I)
    assert ram.get(0x8004) == 1, "the first run of the target"
    assert ram.get(0x8000) == 2, f"the rewritten instruction did not run: x9 = {ram.get(0x8000)}"
    assert pulses == 1, f"{pulses} invalidate pulses for one FENCE.I"


@cocotb.test()
async def test_without_fence_i_the_cache_is_stale(dut):
    """The model catches the missing fence: a NOP in its place leaves the old instruction in the cache."""
    ram, (pulses, _) = await run(dut, NOP)
    assert ram.get(0x8000) == 1
    assert pulses == 0


@cocotb.test()
async def test_fence_i_with_other_latencies(dut):
    for lat in (0, 1, 5):
        ram, _ = await run(dut, FENCE_I, latency=lat)
        assert ram.get(0x8000) == 2 and ram.get(0x8004) == 1, f"latency {lat}"
