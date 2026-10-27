"""Instruction fetch from the SDRAM region, with a variable-latency instruction cache.

The program lives at 0x40000000; a short boot word sequence in the BOOT_ROM jumps there. A
Python model of the instruction cache answers ic_ready after a chosen number of cycles for
every new fetch address and holds ic_data/ic_ready while the address stays. Every latency must
give the same architectural result as no wait at all.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.cores.SdramStall import (
    RAM_BASE, SDRAM_BASE, _b, _bytes_merge, _i, add, addi, beq, lui, lw, sw,
)

CODE_BASE = SDRAM_BASE


def bne(rs1, rs2, imm):
    return _b(1, rs1, rs2, imm)


def jal(rd, imm):
    return (
        (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F
    )


def jalr(rd, rs1, imm):
    return _i(0x67, rd, 0, rs1, imm)


BOOT = [
    addi(0, 0, 0),               # the first word after reset is not executed
    lui(1, CODE_BASE >> 12),
    jalr(0, 1, 0),               # jump into the SDRAM
]

CODE = [
    addi(2, 0, 5),               # 0x40000000
    addi(3, 0, 0),
    add(3, 3, 2),                # loop: x3 += x2
    addi(2, 2, -1),
    bne(2, 0, -8),               # back to the add: x3 = 15
    lui(7, RAM_BASE >> 12),
    sw(3, 7, 0),                 # RAM[0x8000] = 15
    lw(4, 7, 0),
    addi(5, 4, 1),               # load-use: x5 = 16
    sw(5, 7, 4),                 # RAM[0x8004] = 16
    jal(1, 8),                   # skips the next instruction; x1 = address of the one after jal
    addi(6, 0, 0x7F),            # skipped
    addi(6, 6, 1),               # x6 = 1
    sw(6, 7, 8),                 # RAM[0x8008] = 1
    sw(1, 7, 12),                # RAM[0x800C] = CODE_BASE + 4 * 11
    beq(0, 0, 12),               # taken, skips two
    addi(8, 0, 0x7F),            # skipped
    addi(8, 8, 0x7F),            # skipped
    addi(8, 0, 9),               # x8 = 9
    sw(8, 7, 16),                # RAM[0x8010] = 9
    addi(12, 0, 1),
    sw(12, 7, 0x7C),             # RAM[0x807C] = 1: finished
    0x0000006F,                  # jal x0, 0
]

EXPECTED_RAM = {0x8000: 15, 0x8004: 16, 0x8008: 1, 0x800C: CODE_BASE + 4 * 11, 0x8010: 9, 0x807C: 1}


async def run(dut, latency_for):
    """latency_for(n): cycles the n-th new fetch address in the SDRAM waits for."""
    boot = {4 * i: w for i, w in enumerate(BOOT)}
    code = {CODE_BASE + 4 * i: w for i, w in enumerate(CODE)}
    ram = {}

    dut.i_rst.value = 1
    dut.i_boot_rom_data.value = 0
    dut.i_flash_data.value = 0
    dut.i_flash_data2.value = 0
    dut.i_ram_rdata.value = 0
    dut.i_ic_data.value = 0
    dut.i_ic_ready.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    read_pending = 0
    last_addr = None
    wait = 0
    fetches = 0
    waited_cycles = 0
    for _ in range(6000):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        addr = int(dut.o_if_addr.value) & ~3
        # the RAM has a registered read: the word of a load in MEM is there while it is in WB
        dut.i_ram_rdata.value = read_pending

        word = boot.get(addr, 0)
        dut.i_boot_rom_data.value = word
        dut.i_flash_data.value = word

        if int(dut.o_ic_sel.value) == 1:
            if addr != last_addr:
                wait = latency_for(fetches)
                fetches += 1
                last_addr = addr
            dut.i_ic_data.value = code.get(addr, 0)
            if wait == 0:
                dut.i_ic_ready.value = 1
            else:
                dut.i_ic_ready.value = 0
                wait -= 1
                waited_cycles += 1
        else:
            last_addr = None
            dut.i_ic_ready.value = 1

        if int(dut.o_ram_en.value) and int(dut.o_ram_rden.value):
            read_pending = ram.get(int(dut.o_ram_addr.value) & ~3, 0)
        if int(dut.o_ram_en.value) and int(dut.o_ram_wren.value):
            a = int(dut.o_ram_addr.value) & ~3
            ram[a] = _bytes_merge(ram.get(a, 0), int(dut.o_ram_wdata.value), int(dut.o_ram_byteena.value))
        if ram.get(0x807C) == 1:
            break
    return ram, fetches, waited_cycles


def check(ram):
    for a, want in EXPECTED_RAM.items():
        assert ram.get(a) == want, f"RAM[{a:#x}] = {ram.get(a)}, expected {want:#x}"


@cocotb.test()
async def test_no_wait(dut):
    ram, _, waited = await run(dut, lambda n: 0)
    check(ram)
    assert waited == 0


@cocotb.test()
async def test_fixed_latencies(dut):
    cycles = {}
    for lat in (1, 2, 3, 7):
        ram, fetches, waited = await run(dut, lambda n, lat=lat: lat)
        check(ram)
        assert waited > 0
        cycles[lat] = waited
    assert cycles[7] > cycles[1]


@cocotb.test()
async def test_random_latencies(dut):
    rng = random.Random(20261024)
    for _ in range(6):
        seed = rng.getrandbits(32)
        r = random.Random(seed)
        ram, _, _ = await run(dut, lambda n, r=r: r.choice([0, 0, 1, 2, 5]))
        check(ram)
