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

from tests.python.unittests.cores.SdramStall import _bytes_merge

RAM_BASE = 0x8000
DONE_ADDR = RAM_BASE + 0x7FC


async def run_program(  # complexipy: ignore
    dut,
    program,
    flash=None,
    max_cycles=4000,
    monitor=None,
    sdram=None,
    sdram_stall=None,
    imem=None,
    flash_port_value=None,
):
    """Executa run program.

    Run until the program stores 1 at DONE_ADDR; return the RAM as
    {address: word}.

    ``monitor``, when given, is called once per cycle after the memory
    models have settled. ``imem`` (a dict {address: word}) replaces the
    instruction memory built from ``program``, so code can sit at any
    address; the word also goes to the instruction cache port
    (``i_ic_data``). ``flash_port_value``, when given, is driven on
    ``i_flash_data`` instead of the instruction, to show that a fetch
    does not use it. ``sdram`` (a dict {address: word}) turns on a slave
    for the SDRAM window; ``sdram_stall(n)`` gives the stall cycles of
    its n-th access. The slave holds ``i_sdram_ready`` until the core
    advances and commits the read data after that, the way the bridge of
    the board does.
    """
    if imem is None:
        imem = {4 * i: w for i, w in enumerate(program)}
    flash = flash or {}
    ram = {}

    dut.i_rst.value = 1
    for port in (
        "i_sdram_rdata",
        "i_boot_rom_data",
        "i_flash_data",
        "i_flash_data2",
        "i_ram_rdata",
    ):
        getattr(dut, port).value = 0
    dut.i_sdram_ready.value = 0 if sdram is not None else 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    ram_q = flash_q = 0
    ram_next = flash_next = None
    slave = "idle"
    countdown = held_addr = pending_read = accesses = 0
    access = None
    advance_seen = False

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
        dut.i_flash_data.value = (
            word if flash_port_value is None else flash_port_value
        )
        dut.i_ic_data.value = word

        if int(dut.o_ram_en.value):
            addr = int(dut.o_ram_addr.value) & ~3
            if int(dut.o_ram_wren.value):
                ram[addr] = _bytes_merge(
                    ram.get(addr, 0),
                    int(dut.o_ram_wdata.value),
                    int(dut.o_ram_byteena.value),
                )
            if int(dut.o_ram_rden.value):
                ram_next = ram.get(addr, 0)
        if int(dut.o_flash_rden2.value):
            flash_next = flash.get(int(dut.o_flash_addr2.value) & ~3, 0)

        if sdram is not None:
            if slave == "done" and advance_seen:
                dut.i_sdram_ready.value = 0
                dut.i_sdram_rdata.value = pending_read
                slave, advance_seen, held_addr = "idle", False, None
                await Timer(1, unit="ns")
            active = int(dut.o_sdram_rden.value) or int(dut.o_sdram_wren.value)
            if slave == "idle" and active:
                access = {
                    "addr": int(dut.o_sdram_addr.value) & ~3,
                    "we": int(dut.o_sdram_wren.value),
                    "wdata": int(dut.o_sdram_wdata.value),
                    "be": int(dut.o_sdram_byteena.value),
                }
                held_addr = int(dut.o_sdram_addr.value)
                countdown = sdram_stall(accesses) if sdram_stall else 0
                accesses += 1
                slave = "wait"
            if slave == "wait":
                assert active, "the access left the bus before it completed"
                assert int(dut.o_sdram_addr.value) == held_addr, (
                    "address moved during the wait"
                )
                assert int(dut.o_mem_advance.value) == 0, (
                    "the memory advanced while not ready"
                )
                if countdown == 0:
                    if access["we"]:
                        sdram[access["addr"]] = _bytes_merge(
                            sdram.get(access["addr"], 0),
                            access["wdata"],
                            access["be"],
                        )
                    else:
                        pending_read = sdram.get(access["addr"], 0)
                    dut.i_sdram_ready.value = 1
                    slave = "done"
                else:
                    countdown -= 1
            if slave == "done":
                await Timer(1, unit="ns")
                if int(dut.o_mem_advance.value):
                    advance_seen = True

        if monitor is not None:
            monitor(dut)

        if ram.get(DONE_ADDR) == 1:
            break

    assert ram.get(DONE_ADDR) == 1, "the program did not finish"
    return ram
