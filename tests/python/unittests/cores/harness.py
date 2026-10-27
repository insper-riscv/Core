"""Run a program on the core against synchronous models of the instruction memory, the
internal RAM and flash port 2.

The data memories answer in the cycle after the address and keep their output while the
read enable is down, the way the block RAMs of the board do. The instruction memory
answers in the same cycle (it is clocked ahead of the core on the board).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.cores.SdramStall import _bytes_merge

RAM_BASE = 0x8000
DONE_ADDR = RAM_BASE + 0x7FC


async def run_program(dut, program, flash=None, max_cycles=4000, monitor=None):
    """Run until the program stores 1 at DONE_ADDR; return the RAM as {address: word}.

    ``monitor``, when given, is called once per cycle after the memory models have settled.
    """
    imem = {4 * i: w for i, w in enumerate(program)}
    flash = flash or {}
    ram = {}

    dut.i_rst.value = 1
    for port in ("i_sdram_rdata", "i_boot_rom_data", "i_flash_data", "i_flash_data2", "i_ram_rdata"):
        getattr(dut, port).value = 0
    dut.i_sdram_ready.value = 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    ram_q = flash_q = 0
    ram_next = flash_next = None

    for _ in range(max_cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")

        if ram_next is not None:
            ram_q = ram_next
        if flash_next is not None:
            flash_q = flash_next
        ram_next = flash_next = None
        dut.i_ram_rdata.value = ram_q
        dut.i_flash_data2.value = flash_q

        word = imem.get(int(dut.o_if_addr.value) & ~3, 0)
        dut.i_boot_rom_data.value = word
        dut.i_flash_data.value = word

        if int(dut.o_ram_en.value):
            addr = int(dut.o_ram_addr.value) & ~3
            if int(dut.o_ram_wren.value):
                ram[addr] = _bytes_merge(
                    ram.get(addr, 0), int(dut.o_ram_wdata.value), int(dut.o_ram_byteena.value)
                )
            if int(dut.o_ram_rden.value):
                ram_next = ram.get(addr, 0)
        if int(dut.o_flash_rden2.value):
            flash_next = flash.get(int(dut.o_flash_addr2.value) & ~3, 0)

        if monitor is not None:
            monitor(dut)

        if ram.get(DONE_ADDR) == 1:
            break

    assert ram.get(DONE_ADDR) == 1, "the program did not finish"
    return ram
