"""Testes do modulo.

dsp_multiplier_rv32: the signed 64-bit product of two 32-bit operands,
in 3 cycles from the start pulse to done.

The operand sweeps and the constant-latency test are the ones of the
Booth multiplier, which has the same ports and the same contract; they
are imported so that both units run them.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.M.booth_multiplier import (
    MASK,
    _check,
    _reset,
    multiply,
    test_edge_operands,
    test_latency_is_constant,
    test_random_operands,
)

# The imported tests are collected from this module by cocotb.
SHARED_TESTS = (
    test_edge_operands,
    test_latency_is_constant,
    test_random_operands,
)


@cocotb.test()
async def test_latency_is_three_cycles(dut):
    """Verifica latency is three cycles.

    Done rises three cycles after the start pulse (two clock edges after
    the one that samples i_start, as the helper counts them).
    """
    await _reset(dut)
    for a, b in ((0, 0), (MASK, MASK), (0x80000000, 3), (5, 7)):
        check_equal((await multiply(dut, a, b))[2], 2, f"{a:#x} * {b:#x}")


@cocotb.test()
async def test_abort_cancels_the_product(dut):
    """Verifica abort cancels the product.

    A pulse on i_abort during the calculation stops it: no done follows,
    and the next product is right.
    """
    await _reset(dut)
    dut.i_multiplicand.value = 6
    dut.i_multiplier.value = 7
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    dut.i_abort.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_abort.value = 0
    for _ in range(10):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        check_equal(int(dut.o_done.value), 0, "done after an abort")
    await _check(dut, [(3, 5), (MASK, 2)])
