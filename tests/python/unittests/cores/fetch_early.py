"""Testes do modulo.

Fetch with the address ahead of the memories (early_addr): the instruction
memory and the cache read, at the edge of the core clock, the address the PC
will have in the next cycle (o_if_addr_nx). The model below does what the
block RAM of the board does: it samples that address before the edge and shows
the word after it. After a taken branch, a jump or a trap the word of that cycle
is the sequential one, with a ready that says it is valid (the cache hit on the
wrong address), and the core has to drop it and wait for the target.

Every latency must give the same architectural result as the core without it.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal, check_true
from tests.python.unittests.cores.fetch_stall import (
    EXPECTED_RAM,
    _Model,
    check,
)


class _EarlyModel(_Model):
    """The fetch answers for the address sampled at the last edge."""

    def serve_fetch(self, dut):
        """Show the word of the address sampled before the edge."""
        addr = self.sampled
        dut.i_ram_rdata.value = self.read_pending
        word = self.boot.get(addr, 0)
        dut.i_boot_memory_data.value = word
        dut.i_flash_data.value = word
        if addr < 0x40000000:
            self.last_addr = None
            dut.i_ic_ready.value = 1
            return
        if addr != self.last_addr:
            self.last_addr = addr
            if addr != self.done and self.pending is None:
                self.pending = addr
                self.wait = self.latency_for(self.fetches)
                self.fetches += 1
        dut.i_ic_data.value = self.code.get(addr, 0)
        if self.pending is not None:
            if self.wait == 0:
                self.done, self.pending = self.pending, None
            else:
                self.wait -= 1
                self.waited_cycles += 1
        dut.i_ic_ready.value = int(addr == self.done)


async def run(dut, latency_for):
    """Run the program; return (RAM, fetches, cycles waited, cycles)."""
    model = _EarlyModel(latency_for)
    model.sampled = 0

    dut.i_rst.value = 1
    dut.i_boot_memory_data.value = 0
    dut.i_flash_data.value = 0
    dut.i_flash_data2.value = 0
    dut.i_ram_rdata.value = 0
    dut.i_ic_data.value = 0
    dut.i_ic_ready.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    cycles = 0
    for cycles in range(1, 6000):
        model.sampled = int(dut.o_if_addr_nx.value) & ~3
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        model.serve_fetch(dut)
        model.serve_ram(dut)
        if model.ram.get(0x807C) == 1:
            break
    return model.ram, model.fetches, model.waited_cycles, cycles


@cocotb.test()
async def test_no_wait(dut):
    """Verifica no wait."""
    ram, _, waited, _ = await run(dut, lambda _n: 0)
    check(ram)
    check_equal(waited, 0)


@cocotb.test()
async def test_fixed_latencies(dut):
    """Verifica fixed latencies."""
    for lat in (1, 2, 3, 7):
        ram, _fetches, waited, _ = await run(dut, lambda _n, lat=lat: lat)
        check(ram)
        check_true(waited > 0)


@cocotb.test()
async def test_random_latencies(dut):
    """Verifica random latencies."""
    rng = Prng(20261124)
    for _ in range(8):
        r = Prng(rng.getrandbits(32))
        ram, _, _, _ = await run(
            dut, lambda _n, r=r: r.choice([0, 0, 1, 2, 5])
        )
        check(ram)


@cocotb.test()
async def test_expected_ram_is_complete(dut):
    """The program leaves every expected word."""
    ram, _, _, _ = await run(dut, lambda _n: 0)
    check_equal(sorted(a for a in EXPECTED_RAM if a in ram), sorted(EXPECTED_RAM))
