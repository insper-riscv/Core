"""Testes do modulo.

counter64 with a width below 64 bits: the low half keeps min(width, 32)
bits, the high half the rest, what is written is truncated to the width
and the bits above it read zero. The width comes from the entry of
tests.json.
"""

import cocotb

from tests.python.unittests.checks import Prng, check_equal
from tests.python.unittests.Zicntr.counter64 import start, step, value

MASK32 = 0xFFFFFFFF


def _masks(dut):
    width = int(dut.width.value)
    lo_mask = (1 << min(width, 32)) - 1
    hi_mask = (1 << max(width - 32, 0)) - 1
    return width, lo_mask, hi_mask


@cocotb.test()
async def test_the_value_wraps_at_the_width(dut):
    """Verifica the value wraps at the width."""
    await start(dut)
    width, lo_mask, hi_mask = _masks(dut)
    full = (1 << width) - 1
    await step(dut, we_lo=lo_mask)
    if hi_mask:
        await step(dut, we_hi=hi_mask)
    check_equal(value(dut), full)
    check_equal(await step(dut, inc=1), 0, "the counter wraps to zero")
    check_equal(await step(dut), 0)


@cocotb.test()
async def test_a_write_keeps_only_the_bits_that_fit(dut):
    """Verifica a write keeps only the bits that fit."""
    await start(dut)
    _, lo_mask, hi_mask = _masks(dut)
    check_equal(await step(dut, we_lo=MASK32), lo_mask)
    check_equal(await step(dut, we_hi=MASK32), (hi_mask << 32) | lo_mask)


def _next_value(model, masks, inc, we_lo, we_hi):
    """Return the ideal counter after one clock."""
    lo_mask, hi_mask = masks
    low, high = model & MASK32, model >> 32
    if we_hi is not None:
        high = we_hi & hi_mask
    if we_lo is not None:
        low = we_lo & lo_mask
    elif inc:
        if low == lo_mask:
            high = (high + 1) & hi_mask
        low = (low + 1) & lo_mask
    return (high << 32) | low


def _stimulus(prng, lo_mask):
    """Draw the inputs of one clock; a clock writes at most one half."""
    inc = prng.getrandbits(1)
    we_lo = prng.getrandbits(32) if prng.getrandbits(3) == 0 else None
    if we_lo is not None and prng.getrandbits(1):
        we_lo = prng.choice((lo_mask, lo_mask - 1, 0))
    we_hi = prng.getrandbits(32) if prng.getrandbits(4) == 0 else None
    return inc, we_lo, (None if we_lo is not None else we_hi)


@cocotb.test()
async def test_random_traffic_matches_the_ideal_counter(dut):
    """Verifica random traffic matches the ideal counter."""
    await start(dut)
    width, lo_mask, hi_mask = _masks(dut)
    prng = Prng(width + 7)
    model = 0
    for _ in range(3000):
        inc, we_lo, we_hi = _stimulus(prng, lo_mask)
        model = _next_value(model, (lo_mask, hi_mask), inc, we_lo, we_hi)
        check_equal(await step(dut, inc, we_lo, we_hi), model, width)
