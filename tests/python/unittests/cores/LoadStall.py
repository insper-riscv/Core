"""A load in WB keeps its data while the multiply/divide unit stalls the pipeline.

While the M unit computes, MEM/WB holds the instruction it has. A load in WB must
write the word it read, in every stalled cycle, even though the load behind it in
MEM keeps its read enable up and the synchronous memory answers for that address.
The program places two independent loads before an M instruction, once on the
internal RAM and once on the second port of the flash, and the M results are
checked too.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.cores.SdramStall import (
    RAM_BASE,
    _bytes_merge,
    _r,
    addi,
    jal_self,
    lui,
    lw,
    sw,
)

FLASH_DATA = 0x200


def mul(rd, rs1, rs2):
    return _r(0x33, rd, 0, rs1, rs2, 1)


def divu(rd, rs1, rs2):
    return _r(0x33, rd, 5, rs1, rs2, 1)


def remu(rd, rs1, rs2):
    return _r(0x33, rd, 7, rs1, rs2, 1)


NOP = addi(0, 0, 0)

PROGRAM = [
    NOP,
    lui(7, RAM_BASE >> 12),      # x7 = internal RAM base
    addi(2, 0, 0x11),
    addi(3, 0, 0x22),
    sw(2, 7, 0),                 # RAM[0x8000] = 0x11
    sw(3, 7, 4),                 # RAM[0x8004] = 0x22
    NOP, NOP, NOP,
    lw(4, 7, 0),                 # x4 = 0x11, in WB while the mul stalls
    lw(5, 7, 4),                 # x5 = 0x22, in MEM when the mul starts
    mul(6, 2, 3),                # independent of x4 and x5
    NOP, NOP, NOP,
    sw(4, 7, 16),
    sw(5, 7, 20),
    sw(6, 7, 24),                # 0x11 * 0x22
    addi(9, 0, FLASH_DATA),
    lw(10, 9, 0),                # flash port 2, in WB while the divu stalls
    lw(11, 9, 4),
    divu(12, 3, 2),              # 0x22 / 0x11
    remu(13, 3, 2),              # back to back with the divu: 0x22 % 0x11
    NOP, NOP, NOP,
    sw(10, 7, 28),
    sw(11, 7, 32),
    sw(12, 7, 36),
    sw(13, 7, 40),
    addi(14, 0, 1),
    sw(14, 7, 0x7C),             # the program finished
    jal_self(),
]

FLASH = {FLASH_DATA: 0xA5A5, FLASH_DATA + 4: 0x5A5A}

EXPECTED_RAM = {
    0x8010: 0x11,
    0x8014: 0x22,
    0x8018: 0x242,
    0x801C: 0xA5A5,
    0x8020: 0x5A5A,
    0x8024: 0x2,
    0x8028: 0x0,
}


@cocotb.test()
async def test_load_in_wb_during_m_stall(dut):
    """Registers hold the loaded words and the M results after the stalls."""
    imem = {4 * i: w for i, w in enumerate(PROGRAM)}
    ram = {}

    dut.i_rst.value = 1
    for port in ("i_sdram_rdata", "i_boot_rom_data", "i_flash_data", "i_flash_data2", "i_ram_rdata"):
        getattr(dut, port).value = 0
    dut.i_sdram_ready.value = 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    # Synchronous memories: the word of the address of the previous cycle, and
    # the output keeps its value while the read enable is down.
    ram_q = flash_q = 0
    ram_next = flash_next = None

    for _ in range(1500):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")

        if ram_next is not None:
            ram_q = ram_next
        if flash_next is not None:
            flash_q = flash_next
        ram_next = flash_next = None
        dut.i_ram_rdata.value = ram_q
        dut.i_flash_data2.value = flash_q

        # instruction memory: the word of the address presented in the cycle
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
            flash_next = FLASH.get(int(dut.o_flash_addr2.value) & ~3, 0)

        if ram.get(0x807C) == 1:
            break

    assert ram.get(0x807C) == 1, "the program did not finish"
    for addr, want in EXPECTED_RAM.items():
        assert ram.get(addr) == want, f"RAM[0x{addr:08X}] = {ram.get(addr, 0):#x}, expected {want:#x}"
