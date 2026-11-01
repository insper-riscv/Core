"""Testes do modulo.

non_restoring_divider_rv32: DIV, DIVU, REM and REMU as the RISC-V ISA
defines them.
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


def expected(dividend, divisor, unsigned):
    """Quotient and remainder of the ISA, as 32-bit patterns."""
    if divisor == 0:
        return MASK, dividend
    if unsigned:
        return dividend // divisor, dividend % divisor
    a, b = _signed(dividend), _signed(divisor)
    if a == -(1 << 31) and b == -1:
        return 0x80000000, 0
    quotient = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        quotient = -quotient
    return quotient & MASK, (a - quotient * b) & MASK


async def divide(dut, dividend, divisor, unsigned):
    """Executa divide.

    Run one division and return (quotient, remainder) when done rises.
    """
    dut.i_dividend.value = dividend
    dut.i_divisor.value = divisor
    dut.i_is_unsigned.value = int(unsigned)
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    for _ in range(TIMEOUT_CYCLES):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.o_done.value):
            result = int(dut.o_quotient.value), int(dut.o_remainder.value)
            # one idle cycle with start low releases the unit for the
            # next division
            await RisingEdge(dut.i_clk)
            return result
    raise AssertionError(f"no done after {TIMEOUT_CYCLES} cycles")


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_start.value = 0
    dut.i_is_unsigned.value = 0
    dut.i_dividend.value = 0
    dut.i_divisor.value = 1
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


async def _check(dut, pairs, unsigned):
    for dividend, divisor in pairs:
        got = await divide(dut, dividend, divisor, unsigned)
        want = expected(dividend, divisor, unsigned)
        kind = "unsigned" if unsigned else "signed"
        assert got == want, (
            f"{kind} {dividend:#010x} / {divisor:#010x}: "
            f"got q={got[0]:#010x} r={got[1]:#010x}, want q={want[0]:#010x} "
            f"r={want[1]:#010x}"
        )


@cocotb.test()
async def test_unsigned_edges(dut):
    """Verifica unsigned edges.

    DIVU and REMU on every pair of edge values, including divisors above
    2**31.
    """
    await _reset(dut)
    await _check(dut, [(a, b) for a in EDGES for b in EDGES], unsigned=True)


@cocotb.test()
async def test_signed_edges(dut):
    """Verifica signed edges.

    DIV and REM on every pair of edge values, including -2**31 / -1 and
    x / 0.
    """
    await _reset(dut)
    await _check(dut, [(a, b) for a in EDGES for b in EDGES], unsigned=False)


@cocotb.test()
async def test_random(dut):
    """Random operands, in both modes."""
    await _reset(dut)
    rng = random.Random(20261023)
    pairs = [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(60)]
    await _check(dut, pairs, unsigned=True)
    await _check(dut, pairs, unsigned=False)
