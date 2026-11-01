"""Testes do modulo.

booth_multiplier_rv32: the signed 64-bit product of two 32-bit operands,
in 33 cycles.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MASK = 0xFFFFFFFF
EDGES = (
    0,
    1,
    2,
    3,
    0x7FFFFFFF,
    0x80000000,
    0x80000001,
    0xFFFFFFFE,
    0xFFFFFFFF,
)
TIMEOUT_CYCLES = 100


def _signed(value):
    return value - (1 << 32) if value >> 31 else value


async def multiply(dut, a, b):
    """Executa multiply.

    Run one multiplication; return (hi, lo, cycles from the start edge
    to done).
    """
    dut.i_multiplicand.value = a
    dut.i_multiplier.value = b
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    for cycles in range(1, TIMEOUT_CYCLES):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.o_done.value):
            result = (
                int(dut.o_result_hi.value),
                int(dut.o_result_lo.value),
                cycles,
            )
            # one idle cycle with start low releases the unit for the
            # next product
            await RisingEdge(dut.i_clk)
            return result
    raise AssertionError(f"no done after {TIMEOUT_CYCLES} cycles")


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_start.value = 0
    dut.i_multiplicand.value = 0
    dut.i_multiplier.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


async def _check(dut, pairs):
    for a, b in pairs:
        hi, lo, _ = await multiply(dut, a, b)
        product = (_signed(a) * _signed(b)) & ((1 << 64) - 1)
        assert (hi, lo) == (product >> 32, product & MASK), (
            f"{a:#010x} * {b:#010x}: got hi={hi:#010x} lo={lo:#010x}, "
            f"expected hi={product >> 32:#010x} lo={product & MASK:#010x}"
        )


@cocotb.test()
async def test_edge_operands(dut):
    """Verifica edge operands.

    Every pair of edge operands (zero, one, the extremes, the sign
    boundary).
    """
    await _reset(dut)
    await _check(dut, [(a, b) for a in EDGES for b in EDGES])


@cocotb.test()
async def test_random_operands(dut):
    """Verifica random operands.

    Random operands; the high word is the signed product, the low word
    is the plain MUL.
    """
    await _reset(dut)
    rng = random.Random(1)
    await _check(
        dut, [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(300)]
    )


@cocotb.test()
async def test_latency_is_constant(dut):
    """Verifica latency is constant.

    Done rises after the same number of cycles whatever the operands.
    """
    await _reset(dut)
    cycles = {
        (await multiply(dut, a, b))[2]
        for a, b in ((0, 0), (MASK, MASK), (0x80000000, 3), (5, 7))
    }
    assert len(cycles) == 1, f"latencies differ: {sorted(cycles)}"
