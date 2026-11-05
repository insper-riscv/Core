"""Testes do modulo.

csr_file with Zihpm over the 29 indices: every address of the five
ranges exists, the real counters count the event they select, the
indices past hpm_counters read zero and ignore writes, mcountinhibit
has one bit per real counter, and the width truncates the counters. The
generics come from the entry of tests.json.
"""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.Zicntr.csr_file_zihpm import (
    access,
    pulses,
    read,
    reset,
    write,
)

RS = 0b010
WIDE = 32
MCOUNTINHIBIT = 0x320
EVENT, MLO, MHI, LO, HI = 0x320, 0xB00, 0xB80, 0xC00, 0xC80
INDICES = range(3, 32)
MASK32 = 0xFFFFFFFF


def _generics(dut):
    """Return (hpm_counters, hpm_width) of the instance under test."""
    return int(dut.hpm_counters.value), int(dut.hpm_width.value)


def _real(dut):
    counters, width = _generics(dut)
    return range(3, 3 + (counters if width else 0))


@cocotb.test()
async def test_every_address_of_the_five_ranges_is_legal_to_read(dut):
    """Verifica every address of the five ranges is legal to read."""
    await reset(dut)
    for index in INDICES:
        for base in (EVENT, MLO, MHI, LO, HI):
            seen = await access(dut, base + index, RS, 0)
            check_equal(seen[1], 0, hex(base + index))


@cocotb.test()
async def test_a_write_to_a_mirror_is_illegal_at_every_index(dut):
    """Verifica a write to a mirror is illegal at every index."""
    await reset(dut)
    for index in INDICES:
        for base in (LO, HI):
            check_equal(
                (await write(dut, base + index, 1))[1], 1, hex(base + index)
            )
            seen = await access(dut, base + index, RS, 0)
            check_equal(seen[1], 0, "a read of a mirror is legal")


@cocotb.test()
async def test_the_addresses_the_chapter_does_not_define_are_illegal(dut):
    """Verifica addresses not defined by the chapter are illegal."""
    await reset(dut)
    for addr in (0x321, 0x322, 0xB01, 0xB81, 0x3A0):
        check_equal((await access(dut, addr, RS, 0))[1], 1, hex(addr))


@cocotb.test()
async def test_each_real_counter_counts_its_event_in_every_mirror(dut):
    """Verifica each real counter counts its event in every mirror."""
    await reset(dut)
    _, width = _generics(dut)
    lo_mask = (1 << min(width, WIDE)) - 1
    for position, index in enumerate(_real(dut)):
        code = position % 9 + 1
        await write(dut, EVENT + index, code)
        await pulses(dut, code, 2)
        await pulses(dut, 0, 1)
        counted = 2 & lo_mask
        check_equal(await read(dut, MLO + index), counted, index)
        check_equal(await read(dut, LO + index), counted, index)
        check_equal(await read(dut, EVENT + index), code, index)
        await write(dut, EVENT + index, 0)


@cocotb.test()
async def test_a_high_index_counts_the_fused_operation_event(dut):
    """Verifica a high index counts the fused operation event."""
    await reset(dut)
    real = list(_real(dut))
    if not real:
        return
    index = real[-1]
    _, width = _generics(dut)
    await write(dut, EVENT + index, 9)
    await pulses(dut, 9, 3)
    check_equal(
        await read(dut, MLO + index), 3 & ((1 << min(width, WIDE)) - 1)
    )


@cocotb.test()
async def test_indices_past_the_real_counters_read_zero_and_ignore_writes(
    dut,
):
    """Verifica indices past the counters read zero, ignore writes."""
    await reset(dut)
    real = set(_real(dut))
    for index in INDICES:
        if index in real:
            continue
        for base in (EVENT, MLO, MHI):
            check_equal((await write(dut, base + index, MASK32))[1], 0)
        for base in (EVENT, MLO, MHI, LO, HI):
            check_equal(await read(dut, base + index), 0, hex(base + index))
    expected = sum(1 << index for index in real)
    await write(dut, MCOUNTINHIBIT, MASK32)
    check_equal(await read(dut, MCOUNTINHIBIT), expected)


@cocotb.test()
async def test_one_inhibit_bit_per_real_counter(dut):
    """Verifica one inhibit bit per real counter."""
    await reset(dut)
    _, width = _generics(dut)
    lo_mask = (1 << min(width, WIDE)) - 1
    for index in _real(dut):
        await write(dut, EVENT + index, 3)
    for index in _real(dut):
        await write(dut, MCOUNTINHIBIT, 1 << index)
        await pulses(dut, 3, 2)
        for other in _real(dut):
            want = 0 if other == index else (2 & lo_mask)
            check_equal(await read(dut, MLO + other), want, (index, other))
        for other in _real(dut):
            await write(dut, MLO + other, 0)
    await write(dut, MCOUNTINHIBIT, 0)


@cocotb.test()
async def test_the_width_truncates_every_real_counter(dut):
    """Verifica the width truncates every real counter."""
    await reset(dut)
    _, width = _generics(dut)
    for index in _real(dut):
        await write(dut, MLO + index, MASK32)
        await write(dut, MHI + index, MASK32)
        check_equal(
            await read(dut, MLO + index), (1 << min(width, WIDE)) - 1, index
        )
        check_equal(
            await read(dut, HI + index), (1 << max(width - WIDE, 0)) - 1, index
        )


@cocotb.test()
async def test_the_64_bit_read_is_coherent_across_the_carry(dut):
    """Verifica the 64-bit read is coherent across the carry."""
    await reset(dut)
    _, width = _generics(dut)
    if width <= WIDE:
        return
    index = next(iter(_real(dut)))
    await write(dut, EVENT + index, 2)
    await write(dut, MLO + index, MASK32)
    await pulses(dut, 2, 1)
    high = await read(dut, HI + index)
    low = await read(dut, LO + index)
    again = await read(dut, HI + index)
    check_equal((high, low, again), (1, 0, 1))
