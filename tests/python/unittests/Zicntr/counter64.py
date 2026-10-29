"""counter64: a 64-bit counter in two halves, the carry registered, the read always coherent."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MASK32 = 0xFFFFFFFF


async def start(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_inc.value = 0
    dut.i_we_lo.value = 0
    dut.i_we_hi.value = 0
    dut.i_wdata.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


def value(dut):
    return (int(dut.o_hi.value) << 32) | int(dut.o_lo.value)


async def step(dut, inc=0, we_lo=None, we_hi=None):
    """One clock edge with the inputs given; returns the 64-bit value after it."""
    dut.i_inc.value = inc
    dut.i_we_lo.value = int(we_lo is not None)
    dut.i_we_hi.value = int(we_hi is not None)
    dut.i_wdata.value = we_lo if we_lo is not None else (we_hi or 0)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_inc.value = 0
    dut.i_we_lo.value = 0
    dut.i_we_hi.value = 0
    return value(dut)


@cocotb.test()
async def test_reset_and_hold(dut):
    await start(dut)
    assert value(dut) == 0
    for _ in range(3):
        assert await step(dut) == 0, "no increment without i_inc"


@cocotb.test()
async def test_counts_one_per_enabled_cycle(dut):
    await start(dut)
    for n in range(1, 20):
        assert await step(dut, inc=1) == n


@cocotb.test()
async def test_the_read_is_coherent_across_the_carry(dut):
    """The value read at every cycle is the ideal 64-bit counter, also the cycle after the wrap."""
    await start(dut)
    await step(dut, we_lo=0xFFFFFFFD)
    await step(dut, we_hi=0x00000007)
    expected = (7 << 32) | 0xFFFFFFFD
    assert value(dut) == expected
    for _ in range(6):
        expected += 1
        assert await step(dut, inc=1) == expected
    assert expected >> 32 == 8


@cocotb.test()
async def test_the_carry_crosses_idle_cycles(dut):
    """A wrap followed by cycles without increment still ends with the high half summed."""
    await start(dut)
    await step(dut, we_lo=MASK32)
    assert await step(dut, inc=1) == 1 << 32
    for _ in range(3):
        assert await step(dut) == 1 << 32


@cocotb.test()
async def test_a_write_wins_over_the_increment(dut):
    await start(dut)
    assert await step(dut, inc=1, we_lo=0x1234) == 0x1234
    assert await step(dut, inc=1, we_hi=0x55) >> 32 == 0x55
    assert (await step(dut, inc=1, we_lo=0x10)) & MASK32 == 0x10


@cocotb.test()
async def test_a_low_write_on_the_wrap_cycle_makes_no_carry(dut):
    await start(dut)
    await step(dut, we_lo=MASK32)
    assert await step(dut, inc=1, we_lo=0) == 0
    assert await step(dut) == 0


@cocotb.test()
async def test_a_high_write_drops_the_pending_carry(dut):
    await start(dut)
    await step(dut, we_lo=MASK32)
    await step(dut, inc=1)  # wraps: the carry is pending now
    assert value(dut) == 1 << 32
    assert await step(dut, we_hi=0x20) == 0x20 << 32, "the write wins over the pending carry"
    assert await step(dut) == 0x20 << 32


@cocotb.test()
async def test_reset_clears_both_halves_and_the_carry(dut):
    await start(dut)
    await step(dut, we_lo=MASK32)
    await step(dut, inc=1)
    dut.i_rst.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    assert value(dut) == 0
    assert await step(dut) == 0
