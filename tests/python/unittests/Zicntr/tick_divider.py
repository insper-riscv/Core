"""tick_divider: one tick pulse every tick_cycles clock cycles."""

import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def start(dut):
    """Executa start."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


@cocotb.test()
async def test_one_tick_every_period(dut):
    """Verifica one tick every period."""
    await start(dut)
    period = int(dut.tick_cycles.value)
    ticks = []
    for _cycle in range(period * 5):
        ticks.append(int(dut.o_tick.value))
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    assert sum(ticks) == 5
    spots = [i for i, t in enumerate(ticks) if t]
    assert all(b - a == period for a, b in itertools.pairwise(spots)), spots


@cocotb.test()
async def test_reset_restarts_the_count(dut):
    """Verifica reset restarts the count."""
    await start(dut)
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    period = int(dut.tick_cycles.value)
    seen = []
    for _ in range(period):
        seen.append(int(dut.o_tick.value))
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    assert seen == [0] * (period - 1) + [1]
