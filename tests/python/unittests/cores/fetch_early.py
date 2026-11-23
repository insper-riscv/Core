"""Testes do modulo.

Fetch with the address ahead of the memories (early_addr): the
instruction memory and the cache read, at the edge of the core clock,
the address the PC will have in the next cycle (o_if_addr_nx). The model
below does what the block RAM of the board does: it samples that address
before the edge and shows the word after it. After a taken branch, a
jump or a trap the word of that cycle is the sequential one, with a
ready that says it is valid (the cache hit on the wrong address), and
the core has to drop it and wait for the target.

Every latency must give the same architectural result as the core
without it.
"""

from types import SimpleNamespace

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal, check_true
from tests.python.unittests.cores.fetch_stall import (
    EXPECTED_RAM,
    _Model,
    check,
)

SDRAM_BASE = 0x40000000
DONE_ADDR = 0x807C
MAX_CYCLES = 6000
INPUTS = (
    "boot_memory_data",
    "flash_data",
    "flash_data2",
    "ram_rdata",
    "ic_data",
    "ic_ready",
)


class _SampledView:
    """The core as the stalled-fetch model sees it.

    The fetch address is the sampled one, and the cache is selected
    above the SDRAM base.
    """

    def __init__(self, dut, addr):
        """Show addr as the fetch address."""
        self._dut = dut
        self.o_if_addr = SimpleNamespace(value=addr)
        self.o_ic_sel = SimpleNamespace(value=int(addr >= SDRAM_BASE))

    def __getattr__(self, name):
        """Everything else is the signal of the core."""
        return getattr(self._dut, name)


class _EarlyModel(_Model):
    """The fetch answers for the address sampled at the last edge."""

    def __init__(self, latency_for):
        """Start with the address sampled at zero."""
        super().__init__(latency_for)
        self.sampled = 0

    def serve_fetch(self, dut):
        """Show the word of the address sampled before the edge."""
        super().serve_fetch(_SampledView(dut, self.sampled))


async def run(dut, latency_for):
    """Run the program; return (RAM, fetches, cycles waited, cycles)."""
    model = _EarlyModel(latency_for)

    dut.i_rst.value = 1
    for name in INPUTS:
        getattr(dut, f"i_{name}").value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0

    cycles = 0
    while cycles < MAX_CYCLES:
        cycles += 1
        model.sampled = int(dut.o_if_addr_nx.value) & ~3
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        model.serve_fetch(dut)
        model.serve_ram(dut)
        if model.ram.get(DONE_ADDR) == 1:
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
    check_equal(
        sorted(a for a in EXPECTED_RAM if a in ram), sorted(EXPECTED_RAM)
    )
