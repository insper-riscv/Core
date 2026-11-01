"""Testes do modulo.

Run a program on the core against synchronous models of the instruction
memory, the internal RAM and flash port 2.

The data memories answer in the cycle after the address and keep their
output while the read enable is down, the way the block RAMs of the
board do. The instruction memory answers in the same cycle (it is
clocked ahead of the core on the board).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.cores.sdram_stall import (
    _bytes_merge,
    _SdramSlave,
)

RAM_BASE = 0x8000
DONE_ADDR = RAM_BASE + 0x7FC


OPTIONS = {
    "flash",
    "monitor",
    "sdram",
    "sdram_stall",
    "imem",
    "flash_port_value",
}
DATA_PORTS = (
    "i_sdram_rdata",
    "i_boot_rom_data",
    "i_flash_data",
    "i_flash_data2",
    "i_ram_rdata",
)


class _DataMemories:
    """Synchronous models of the internal RAM and flash port 2."""

    def __init__(self, flash):
        """Start empty, with the flash contents given."""
        self.ram = {}
        self.flash = flash
        self.ram_q = self.flash_q = 0
        self.ram_next = self.flash_next = None

    def present(self, dut):
        """Show the data latched in the previous cycle."""
        if self.ram_next is not None:
            self.ram_q = self.ram_next
        if self.flash_next is not None:
            self.flash_q = self.flash_next
        self.ram_next = self.flash_next = None
        dut.i_ram_rdata.value = self.ram_q
        dut.i_flash_data2.value = self.flash_q

    def capture(self, dut):
        """Apply the writes and latch the reads of this cycle."""
        if int(dut.o_ram_en.value):
            addr = int(dut.o_ram_addr.value) & ~3
            if int(dut.o_ram_wren.value):
                self.ram[addr] = _bytes_merge(
                    self.ram.get(addr, 0),
                    int(dut.o_ram_wdata.value),
                    int(dut.o_ram_byteena.value),
                )
            if int(dut.o_ram_rden.value):
                self.ram_next = self.ram.get(addr, 0)
        if int(dut.o_flash_rden2.value):
            addr = int(dut.o_flash_addr2.value) & ~3
            self.flash_next = self.flash.get(addr, 0)


def _models(dut, program, options):
    """Build the memory models that the options ask for."""
    unknown = options.keys() - OPTIONS
    if unknown:
        raise TypeError(f"unknown run_program options: {sorted(unknown)}")
    default_imem = {4 * i: w for i, w in enumerate(program)}
    imem = options.get("imem", default_imem)
    memories = _DataMemories(options.get("flash") or {})
    sdram = options.get("sdram")
    slave = None
    if sdram is not None:
        slave = _SdramSlave(dut, sdram, options.get("sdram_stall"))
    return imem, memories, slave


async def _start(dut, with_sdram):
    """Reset the core with the clock running and zeroed data ports."""
    dut.i_rst.value = 1
    for port in DATA_PORTS:
        getattr(dut, port).value = 0
    dut.i_sdram_ready.value = 0 if with_sdram else 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0


def _drive_fetch(dut, imem, flash_port_value):
    """Answer the instruction fetch of this cycle."""
    word = imem.get(int(dut.o_if_addr.value) & ~3, 0)
    dut.i_boot_rom_data.value = word
    dut.i_flash_data.value = (
        word if flash_port_value is None else flash_port_value
    )
    dut.i_ic_data.value = word


async def run_program(dut, program, max_cycles=4000, **options):
    """Run until the program stores 1 at DONE_ADDR; return the RAM.

    The RAM comes back as {address: word}. The options come by name:

    ``monitor``, when given, is called once per cycle after the memory
    models have settled. ``imem`` (a dict {address: word}) replaces the
    instruction memory built from ``program``, so code can sit at any
    address; the word also goes to the instruction cache port
    (``i_ic_data``). ``flash`` (a dict {address: word}) is the flash
    behind port 2. ``flash_port_value``, when given, is driven on
    ``i_flash_data`` instead of the instruction, to show that a fetch
    does not use it. ``sdram`` (a dict {address: word}) turns on a slave
    for the SDRAM window; ``sdram_stall(n)`` gives the stall cycles of
    its n-th access. The slave holds ``i_sdram_ready`` until the core
    advances and commits the read data after that, the way the bridge of
    the board does.
    """
    imem, memories, slave = _models(dut, program, options)
    monitor = options.get("monitor")

    await _start(dut, slave is not None)
    for _ in range(max_cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        memories.present(dut)
        _drive_fetch(dut, imem, options.get("flash_port_value"))
        memories.capture(dut)
        if slave is not None:
            await slave.step()
        if monitor is not None:
            monitor(dut)
        if memories.ram.get(DONE_ADDR) == 1:
            break

    check_equal(memories.ram.get(DONE_ADDR), 1, "the program did not finish")
    return memories.ram
