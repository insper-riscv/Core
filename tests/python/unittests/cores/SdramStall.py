"""Pipeline stall on a variable-latency data memory (SDRAM region).

The core runs a short program against Python models of the instruction memory,
the internal RAM and an SDRAM slave. The slave answers after a chosen number
of stall cycles, holds ``sdram_ready`` high until the core advances (it learns
that from ``mem_advance``), and only then commits the read data, the way the
real bridge does. Every latency must give the same architectural result.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

SDRAM_BASE = 0x40000000
RAM_BASE = 0x00008000


# --- a tiny RV32I encoder: just what the program needs ----------------------
def _r(op, rd, f3, rs1, rs2, f7):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _i(op, rd, f3, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _s(f3, rs1, rs2, imm):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def _b(f3, rs1, rs2, imm):
    return (
        (((imm >> 12) & 1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (f3 << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 1) << 7)
        | 0x63
    )


def lui(rd, imm20):
    return (imm20 << 12) | (rd << 7) | 0x37


def addi(rd, rs1, imm):
    return _i(0x13, rd, 0, rs1, imm)


def add(rd, rs1, rs2):
    return _r(0x33, rd, 0, rs1, rs2, 0)


def lw(rd, rs1, imm):
    return _i(0x03, rd, 2, rs1, imm)


def lbu(rd, rs1, imm):
    return _i(0x03, rd, 4, rs1, imm)


def sw(rs2, rs1, imm):
    return _s(2, rs1, rs2, imm)


def sb(rs2, rs1, imm):
    return _s(0, rs1, rs2, imm)


def beq(rs1, rs2, imm):
    return _b(0, rs1, rs2, imm)


def jal_self():
    return 0x0000006F


PROGRAM = [
    addi(0, 0, 0),               # nop: the first word after reset is not executed
    lui(1, SDRAM_BASE >> 12),    # x1 = SDRAM base
    lui(7, RAM_BASE >> 12),      # x7 = internal RAM base
    addi(2, 0, 0x11),
    sw(2, 1, 0),                 # SDRAM[0] = 0x11
    addi(3, 0, 0x22),
    sw(3, 1, 4),                 # SDRAM[4] = 0x22 (back-to-back SDRAM stores)
    lw(4, 1, 0),                 # x4 = 0x11
    lw(5, 1, 4),                 # x5 = 0x22 (back-to-back SDRAM loads)
    add(6, 4, 5),                # load-use on x5: x6 = 0x33
    sw(6, 7, 0),                 # RAM[0x8000] = 0x33
    sw(4, 7, 4),                 # RAM[0x8004] = 0x11
    lw(8, 1, 8),                 # x8 = SDRAM[8] (preloaded 0xAA)
    beq(0, 0, 8),                # taken while the load above is still in MEM
    addi(9, 0, 0x7F),            # skipped: must never execute
    addi(9, 9, 1),               # x9 = 1
    sw(8, 7, 8),                 # RAM[0x8008] = 0xAA
    sw(9, 7, 12),                # RAM[0x800C] = 1
    sb(2, 1, 1),                 # SDRAM byte 1 of word 0 = 0x11 (byteena)
    lw(10, 1, 0),                # x10 = 0x1111
    sw(10, 7, 16),               # RAM[0x8010] = 0x1111
    lbu(11, 1, 1),               # x11 = 0x11
    sw(11, 7, 20),               # RAM[0x8014] = 0x11
    addi(12, 0, 1),
    sw(12, 7, 0x7C),             # RAM[0x807C] = 1: the program finished
    jal_self(),
]

EXPECTED_RAM = {
    0x8000: 0x33,
    0x8004: 0x11,
    0x8008: 0xAA,
    0x800C: 0x01,
    0x8010: 0x1111,
    0x8014: 0x11,
    0x807C: 0x01,
}
EXPECTED_SDRAM = {0x40000000: 0x1111, 0x40000004: 0x22, 0x40000008: 0xAA}


def _bytes_merge(old, new, byteena):
    out = old
    for i in range(4):
        if (byteena >> i) & 1:
            out = (out & ~(0xFF << (8 * i))) | (new & (0xFF << (8 * i)))
    return out


async def _run(dut, stall_for):
    """Run the program; stall_for(n) gives the stall cycles of the n-th access."""
    imem = {4 * i: w for i, w in enumerate(PROGRAM)}
    ram = {}
    sdram = {0x40000008: 0xAA}

    dut.reset.value = 1
    dut.sdram_ready.value = 0
    dut.sdram_rdata.value = 0
    dut.boot_rom_data.value = 0
    dut.flash_data.value = 0
    dut.flash_data2.value = 0
    dut.ram_rdata.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.reset.value = 0

    state = "idle"          # idle, wait, done
    countdown = 0
    access = None
    pending_read = 0
    rdata_q = 0
    advance_seen = False
    accesses = 0
    held_addr = None

    for _ in range(4000):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")     # outputs of this cycle have settled

        # instruction memory: on the board it is clocked 120 degrees ahead of the
        # core, so the word of the address presented in a cycle is there in the
        # same cycle
        if dut.if_addr.value.is_resolvable:
            word = imem.get(int(dut.if_addr.value) & ~3, 0)
            dut.boot_rom_data.value = word
            dut.flash_data.value = word

        # internal RAM: record the stores
        if dut.ram_en.value.is_resolvable and int(dut.ram_en.value) and int(dut.ram_wren.value):
            addr = int(dut.ram_addr.value) & ~3
            ram[addr] = _bytes_merge(
                ram.get(addr, 0), int(dut.ram_wdata.value), int(dut.ram_byteena.value)
            )

        # SDRAM slave: the pipeline advanced on the edge that just happened
        if state == "done" and advance_seen:
            dut.sdram_ready.value = 0
            rdata_q = pending_read
            dut.sdram_rdata.value = rdata_q
            state = "idle"
            advance_seen = False
            held_addr = None
            await Timer(1, unit="ns")     # let the dropped ready reach the core

        active = int(dut.sdram_rden.value) or int(dut.sdram_wren.value)
        if state == "idle" and active:
            access = {
                "addr": int(dut.sdram_addr.value) & ~3,
                "we": int(dut.sdram_wren.value),
                "wdata": int(dut.sdram_wdata.value),
                "be": int(dut.sdram_byteena.value),
            }
            held_addr = int(dut.sdram_addr.value)
            countdown = stall_for(accesses)
            accesses += 1
            state = "wait"

        if state == "wait":
            assert active, "the access left the bus before it completed"
            assert int(dut.sdram_addr.value) == held_addr, "address moved during the wait"
            assert int(dut.mem_advance.value) == 0, "the pipeline advanced while not ready"
            if countdown == 0:
                if access["we"]:
                    sdram[access["addr"]] = _bytes_merge(
                        sdram.get(access["addr"], 0), access["wdata"], access["be"]
                    )
                else:
                    pending_read = sdram.get(access["addr"], 0)
                dut.sdram_ready.value = 1
                state = "done"
            else:
                countdown -= 1

        if state == "done":
            await Timer(1, unit="ns")
            if int(dut.mem_advance.value):
                advance_seen = True       # takes effect on the next edge

        if ram.get(0x807C) == 1 and state == "idle":
            break

    return ram, sdram, accesses


def _check(ram, sdram, accesses):
    for addr, want in EXPECTED_RAM.items():
        assert ram.get(addr) == want, f"RAM[0x{addr:08X}] = {ram.get(addr)}, expected 0x{want:X}"
    for addr, want in EXPECTED_SDRAM.items():
        assert sdram.get(addr) == want, f"SDRAM[0x{addr:08X}] = {sdram.get(addr)}, expected 0x{want:X}"
    assert 0x800C in ram and ram[0x800C] == 1, "the instruction after the taken branch executed"
    assert accesses == 8, f"{accesses} SDRAM accesses, expected 8"


@cocotb.test()
async def test_no_wait(dut):
    """Zero stall cycles: ready is high in the first cycle of every access."""
    _check(*await _run(dut, lambda n: 0))


@cocotb.test()
async def test_fixed_latencies(dut):
    """The same result for 1, 2, 3 and 7 stall cycles per access."""
    for s in (1, 2, 3, 7):
        dut._log.info(f"stall cycles per access = {s}")
        _check(*await _run(dut, lambda n, s=s: s))


@cocotb.test()
async def test_random_latencies(dut):
    """The same result for random stall cycles (0 to 9) per access, several seeds."""
    for seed in range(8):
        rng = random.Random(seed)
        lat = [rng.randint(0, 9) for _ in range(32)]
        dut._log.info(f"seed {seed}: {lat[:9]}")
        _check(*await _run(dut, lambda n, lat=lat: lat[n]))
