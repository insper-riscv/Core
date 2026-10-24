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


async def run(dut, fence, latency=2):
    boot = {4 * i: w for i, w in enumerate(BOOT)}
    backing = {CODE_BASE + 4 * i: w for i, w in enumerate(program(fence))}
    lines = {}                                # the cache: line address -> four words
    ram = {}
    inval_pulses = 0

    dut.reset.value = 1
    for sig in ("boot_rom_data", "flash_data", "flash_data2", "ram_rdata", "ic_data", "sdram_rdata"):
        getattr(dut, sig).value = 0
    dut.ic_ready.value = 0
    dut.sdram_ready.value = 1
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.reset.value = 0

    read_pending = 0
    last_addr = None
    wait = 0
    for _ in range(3000):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        addr = int(dut.if_addr.value) & ~3
        dut.ram_rdata.value = read_pending

        word = boot.get(addr, 0)
        dut.boot_rom_data.value = word
        dut.flash_data.value = word

        if int(dut.ic_inval.value):
            lines.clear()
            inval_pulses += 1

        if int(dut.ic_sel.value) == 1:
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
                dut.ic_data.value = lines[line][(addr >> 2) & 3]
                dut.ic_ready.value = 1
            else:
                dut.ic_ready.value = 0
        else:
            last_addr = None
            dut.ic_ready.value = 1

        if int(dut.sdram_wren.value):
            a = int(dut.sdram_addr.value) & ~3
            backing[a] = _bytes_merge(backing.get(a, 0), int(dut.sdram_wdata.value), int(dut.sdram_byteena.value))
        if int(dut.ram_en.value) and int(dut.ram_rden.value):
            read_pending = ram.get(int(dut.ram_addr.value) & ~3, 0)
        if int(dut.ram_en.value) and int(dut.ram_wren.value):
            a = int(dut.ram_addr.value) & ~3
            ram[a] = _bytes_merge(ram.get(a, 0), int(dut.ram_wdata.value), int(dut.ram_byteena.value))
        if ram.get(0x807C) == 1:
            break
    return ram, inval_pulses


@cocotb.test()
async def test_fence_i_makes_the_new_instruction_run(dut):
    ram, pulses = await run(dut, FENCE_I)
    assert ram.get(0x8004) == 1, "the first run of the target"
    assert ram.get(0x8000) == 2, f"the rewritten instruction did not run: x9 = {ram.get(0x8000)}"
    assert pulses == 1, f"{pulses} invalidate pulses for one FENCE.I"


@cocotb.test()
async def test_without_fence_i_the_cache_is_stale(dut):
    """The model catches the missing fence: a NOP in its place leaves the old instruction in the cache."""
    ram, pulses = await run(dut, NOP)
    assert ram.get(0x8000) == 1
    assert pulses == 0


@cocotb.test()
async def test_fence_i_with_other_latencies(dut):
    for lat in (0, 1, 5):
        ram, _ = await run(dut, FENCE_I, latency=lat)
        assert ram.get(0x8000) == 2 and ram.get(0x8004) == 1, f"latency {lat}"
