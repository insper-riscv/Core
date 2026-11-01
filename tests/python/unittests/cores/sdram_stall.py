"""Pipeline stall on a variable-latency data memory (SDRAM region).

The core runs a short program against Python models of the instruction
memory, the internal RAM and an SDRAM slave. The slave answers after a
chosen number of stall cycles, holds ``sdram_ready`` high until the core
advances (it learns that from ``mem_advance``), and only then commits
the read data, the way the real bridge does. Every latency must give the
same architectural result.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal, check_true

SDRAM_BASE = 0x40000000
RAM_BASE = 0x00008000
TAKEN_BRANCH_FLAG = 0x800C
DATA_PORTS = (
    "i_sdram_rdata",
    "i_boot_rom_data",
    "i_flash_data",
    "i_flash_data2",
    "i_ram_rdata",
)


# --- a tiny RV32I encoder: just what the program needs
# ----------------------
def _r(rd, f3, rs1, rs2, f7):
    """Encode an OP (register-register) instruction."""
    return (
        (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
    )


def _i(op, rd, f3, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _s(f3, rs1, rs2, imm):
    return (
        (((imm >> 5) & 0x7F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (f3 << 12)
        | ((imm & 0x1F) << 7)
        | 0x23
    )


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
    """Executa lui."""
    return (imm20 << 12) | (rd << 7) | 0x37


def addi(rd, rs1, imm):
    """Executa addi."""
    return _i(0x13, rd, 0, rs1, imm)


def add(rd, rs1, rs2):
    """Executa add."""
    return _r(rd, 0, rs1, rs2, 0)


def lw(rd, rs1, imm):
    """Executa lw."""
    return _i(0x03, rd, 2, rs1, imm)


def lbu(rd, rs1, imm):
    """Executa lbu."""
    return _i(0x03, rd, 4, rs1, imm)


def sw(rs2, rs1, imm):
    """Executa sw."""
    return _s(2, rs1, rs2, imm)


def sb(rs2, rs1, imm):
    """Executa sb."""
    return _s(0, rs1, rs2, imm)


def beq(rs1, rs2, imm):
    """Executa beq."""
    return _b(0, rs1, rs2, imm)


def jal_self():
    """Executa jal self."""
    return 0x0000006F


PROGRAM = [
    addi(0, 0, 0),  # nop: the first word after reset is not executed
    lui(1, SDRAM_BASE >> 12),  # x1 = SDRAM base
    lui(7, RAM_BASE >> 12),  # x7 = internal RAM base
    addi(2, 0, 0x11),
    sw(2, 1, 0),  # SDRAM[0] = 0x11
    addi(3, 0, 0x22),
    sw(3, 1, 4),  # SDRAM[4] = 0x22 (back-to-back SDRAM stores)
    lw(4, 1, 0),  # x4 = 0x11
    lw(5, 1, 4),  # x5 = 0x22 (back-to-back SDRAM loads)
    add(6, 4, 5),  # load-use on x5: x6 = 0x33
    sw(6, 7, 0),  # RAM[0x8000] = 0x33
    sw(4, 7, 4),  # RAM[0x8004] = 0x11
    lw(8, 1, 8),  # x8 = SDRAM[8] (preloaded 0xAA)
    beq(0, 0, 16),  # taken while the load above is still in MEM
    addi(9, 0, 0x7F),  # skipped: must never execute
    addi(9, 9, 0x7F),  # skipped
    addi(9, 9, 0x7F),  # skipped (the PC is already past the first two
    # when the branch is in EX, so a lost redirect
    # would run these instead of reaching the target)
    addi(9, 9, 1),  # target: x9 = 1
    sw(8, 7, 8),  # RAM[0x8008] = 0xAA
    sw(9, 7, 12),  # RAM[0x800C] = 1
    sb(2, 1, 1),  # SDRAM byte 1 of word 0 = 0x11 (byteena)
    lw(10, 1, 0),  # x10 = 0x1111
    sw(10, 7, 16),  # RAM[0x8010] = 0x1111
    lbu(11, 1, 1),  # x11 = 0x11
    sw(11, 7, 20),  # RAM[0x8014] = 0x11
    # x13 = 0xC0000000: the peripheral window, same port
    lui(13, 0xC0000),
    sw(2, 13, 0),  # [0xC0000000] = 0x11
    lw(14, 13, 0),  # x14 = 0x11
    sw(14, 7, 24),  # RAM[0x8018] = 0x11
    addi(12, 0, 1),
    sw(12, 7, 0x7C),  # RAM[0x807C] = 1: the program finished
    jal_self(),
]

EXPECTED_RAM = {
    0x8000: 0x33,
    0x8004: 0x11,
    0x8008: 0xAA,
    0x800C: 0x01,
    0x8010: 0x1111,
    0x8014: 0x11,
    0x8018: 0x11,
    0x807C: 0x01,
}
EXPECTED_SDRAM = {0x40000000: 0x1111, 0x40000004: 0x22, 0x40000008: 0xAA}


def _bytes_merge(old, new, byteena):
    out = old
    for i in range(4):
        if (byteena >> i) & 1:
            out = (out & ~(0xFF << (8 * i))) | (new & (0xFF << (8 * i)))
    return out


class _SdramSlave:
    """Slave of the SDRAM window, as the bridge of the board answers."""

    def __init__(self, dut, memory, stall_for):
        """Serve the dict memory, stalling access n by stall_for(n)."""
        self.dut = dut
        self.memory = memory
        self.stall_for = stall_for
        self.state = "idle"
        self.countdown = self.accesses = self.pending_read = 0
        self.held_addr = None
        self.access = None
        self.advance_seen = False

    def _accept(self):
        """Take the access that just appeared on the bus."""
        dut = self.dut
        self.access = {
            "addr": int(dut.o_sdram_addr.value) & ~3,
            "we": int(dut.o_sdram_wren.value),
            "wdata": int(dut.o_sdram_wdata.value),
            "be": int(dut.o_sdram_byteena.value),
        }
        self.held_addr = int(dut.o_sdram_addr.value)
        stall = self.stall_for(self.accesses) if self.stall_for else 0
        self.countdown = stall
        self.accesses += 1
        self.state = "wait"

    def _wait(self, active):
        """Hold the bus stalled, then commit the access."""
        dut = self.dut
        check_true(active, "the access left the bus before it completed")
        check_equal(
            int(dut.o_sdram_addr.value),
            self.held_addr,
            "address moved during the wait",
        )
        check_equal(
            int(dut.o_mem_advance.value),
            0,
            "the memory advanced while not ready",
        )
        if self.countdown:
            self.countdown -= 1
            return
        access = self.access
        if access["we"]:
            self.memory[access["addr"]] = _bytes_merge(
                self.memory.get(access["addr"], 0),
                access["wdata"],
                access["be"],
            )
        else:
            self.pending_read = self.memory.get(access["addr"], 0)
        dut.i_sdram_ready.value = 1
        self.state = "done"

    async def step(self):
        """Advance the slave by one cycle."""
        dut = self.dut
        if self.state == "done" and self.advance_seen:
            dut.i_sdram_ready.value = 0
            dut.i_sdram_rdata.value = self.pending_read
            self.state, self.advance_seen = "idle", False
            self.held_addr = None
            await Timer(1, unit="ns")
        active = int(dut.o_sdram_rden.value) or int(dut.o_sdram_wren.value)
        if self.state == "idle" and active:
            self._accept()
        if self.state == "wait":
            self._wait(active)
        if self.state == "done":
            await Timer(1, unit="ns")
            if int(dut.o_mem_advance.value):
                self.advance_seen = True


def _serve_fetch(dut, imem):
    """Answer the fetch in the cycle of its address.

    On the board the instruction memory is clocked 120 degrees ahead of
    the core, so the word is there in the same cycle.
    """
    if dut.o_if_addr.value.is_resolvable:
        word = imem.get(int(dut.o_if_addr.value) & ~3, 0)
        dut.i_boot_rom_data.value = word
        dut.i_flash_data.value = word


def _record_store(dut, ram):
    """Record the store that the internal RAM sees in this cycle."""
    if (
        dut.o_ram_en.value.is_resolvable
        and int(dut.o_ram_en.value)
        and int(dut.o_ram_wren.value)
    ):
        addr = int(dut.o_ram_addr.value) & ~3
        ram[addr] = _bytes_merge(
            ram.get(addr, 0),
            int(dut.o_ram_wdata.value),
            int(dut.o_ram_byteena.value),
        )


async def _run(dut, stall_for):
    """Run the program; stall_for(n) is the stall of the n-th access."""
    imem = {4 * i: w for i, w in enumerate(PROGRAM)}
    ram = {}
    sdram = {0x40000008: 0xAA}

    dut.i_rst.value = 1
    dut.i_sdram_ready.value = 0
    for port in DATA_PORTS:
        getattr(dut, port).value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    slave = _SdramSlave(dut, sdram, stall_for)
    for _ in range(4000):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")  # outputs of this cycle have settled
        _serve_fetch(dut, imem)
        _record_store(dut, ram)
        await slave.step()
        if ram.get(0x807C) == 1 and slave.state == "idle":
            break

    return ram, sdram, slave.accesses


def _check(ram, sdram, accesses):
    for addr, want in EXPECTED_RAM.items():
        check_equal(
            ram.get(addr),
            want,
            f"RAM[0x{addr:08X}] = {ram.get(addr)}, expected 0x{want:X}",
        )
    for addr, want in EXPECTED_SDRAM.items():
        check_equal(
            sdram.get(addr),
            want,
            f"SDRAM[0x{addr:08X}] = {sdram.get(addr)}, expected 0x{want:X}",
        )
    check_true(
        TAKEN_BRANCH_FLAG in ram,
        "the instruction after the taken branch did not run",
    )
    check_equal(
        ram[TAKEN_BRANCH_FLAG],
        1,
        "the instruction after the taken branch executed",
    )
    check_equal(accesses, 10, f"{accesses} external accesses, expected 10")


@cocotb.test()
async def test_no_wait(dut):
    """Verifica no wait.

    Zero stall cycles: ready is high in the first cycle of every access.
    """
    _check(*await _run(dut, lambda _n: 0))


@cocotb.test()
async def test_fixed_latencies(dut):
    """The same result for 1, 2, 3 and 7 stall cycles per access."""
    for s in (1, 2, 3, 7):
        dut._log.info(f"stall cycles per access = {s}")
        _check(*await _run(dut, lambda _n, s=s: s))


@cocotb.test()
async def test_random_latencies(dut):
    """Verifica random latencies.

    The same result for random stall cycles (0 to 9) per access, several
    seeds.
    """
    for seed in range(8):
        rng = Prng(seed)
        lat = [rng.randint(0, 9) for _ in range(32)]
        dut._log.info(f"seed {seed}: {lat[:9]}")
        _check(*await _run(dut, lambda n, lat=lat: lat[n]))
