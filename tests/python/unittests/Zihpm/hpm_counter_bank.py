"""Testes do modulo.

hpm_counter_bank: the event counters of Zihpm, for any number of real
counters (hpm_counters) and any counter width (hpm_width). The generics
come from the entry of tests.json, so the same checks run on every
configuration.
"""

from typing import NamedTuple

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import Prng, check_equal, check_true

MASK32 = 0xFFFFFFFF
FIRST = 3
LAST = 31
TABLE_MASK = 0x03FE
WIDE = 32
PAIR = 2


class Access(NamedTuple):
    """One CSR access presented to the bank."""

    kind: str | None = None
    idx: int = 0
    we: int = 0
    wdata: int = 0

    def address(self):
        """Return the index of the access (mcountinhibit is index 0)."""
        return 0 if self.kind == "inhibit" else self.idx


IDLE = Access()


class Model:
    """Reference model of the bank: what a program must read."""

    def __init__(self, counters, width):
        """Start every register at its reset value."""
        self.real = counters if width else 0
        self.lo_mask = (1 << min(width, WIDE)) - 1
        self.hi_mask = (1 << max(width - WIDE, 0)) - 1
        self.code = [0] * 32
        self.inhibit = [0] * 32
        self.lo = [0] * 32
        self.hi = [0] * 32

    def is_real(self, idx):
        """Tell whether the index has a counter."""
        return FIRST <= idx < FIRST + self.real

    def read(self, kind, idx):
        """Return the word the bank must show."""
        if kind == "inhibit":
            word = 0
            for index in range(FIRST, FIRST + self.real):
                word |= self.inhibit[index] << index
            return word
        if not self.is_real(idx):
            return 0
        return {
            "event": self.code,
            "lo": self.lo,
            "hi": self.hi,
        }[kind][idx]

    def clock(self, events, access):
        """Advance one clock edge with the inputs given."""
        valid = events & TABLE_MASK
        for index in range(FIRST, FIRST + self.real):
            inc = (valid >> self.code[index]) & 1 and not self.inhibit[index]
            self._step(index, inc, access)
        if access.we and access.kind == "inhibit":
            for index in range(FIRST, FIRST + self.real):
                self.inhibit[index] = (access.wdata >> index) & 1

    def _step(self, index, inc, access):
        """Advance one counter; a write beats the increment."""
        kind, wdata = access.kind, access.wdata
        hit = access.we and access.address() == index
        lo, hi = self.lo[index], self.hi[index]
        new_lo, new_hi = lo, hi
        if hit and kind == "hi":
            new_hi = wdata & self.hi_mask
        if hit and kind == "lo":
            new_lo = wdata & self.lo_mask
        elif inc:
            new_lo = (lo + 1) & self.lo_mask
            if lo == self.lo_mask:
                new_hi = (new_hi + 1) & self.hi_mask
        if hit and kind == "event":
            self.code[index] = wdata & 0xF
        self.lo[index], self.hi[index] = new_lo, new_hi


def _generics(dut):
    """Return (hpm_counters, hpm_width) of the instance under test."""
    return int(dut.hpm_counters.value), int(dut.hpm_width.value)


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await _drive(dut, IDLE, 0)
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def _drive(dut, access, events):
    """Present one access and the events, without clocking."""
    kind = access.kind
    dut.i_idx.value = access.address()
    dut.i_sel_inhibit.value = int(kind == "inhibit")
    dut.i_sel_event.value = int(kind in ("event", "inhibit"))
    dut.i_sel_lo.value = int(kind == "lo")
    dut.i_sel_hi.value = int(kind == "hi")
    dut.i_we.value = access.we
    dut.i_wdata.value = access.wdata
    dut.i_events.value = events
    await Timer(1, unit="ns")


async def cycle(dut, access=IDLE, events=0):
    """Run one clock with an access; return the word read before it."""
    await _drive(dut, access, events)
    seen = int(dut.o_rdata.value)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return seen


async def read(dut, kind, idx):
    """Read one register."""
    return await cycle(dut, Access(kind, idx))


async def write(dut, kind, idx, value):
    """Write one register."""
    await cycle(dut, Access(kind, idx, 1, value))


async def wait_clocks(dut, count, events=0):
    """Hold the events for a number of clocks."""
    for _ in range(count):
        await cycle(dut, events=events)


def _real_indices(dut):
    counters, width = _generics(dut)
    return range(FIRST, FIRST + (counters if width else 0))


@cocotb.test()
async def test_reset_state_reads_zero_everywhere(dut):
    """Verifica reset state reads zero everywhere."""
    await _reset(dut)
    for idx in range(32):
        for kind in ("event", "lo", "hi"):
            check_equal(await read(dut, kind, idx), 0, (kind, idx))
    check_equal(await read(dut, "inhibit", 0), 0)


@cocotb.test()
async def test_each_real_index_counts_the_event_it_selects(dut):
    """Verifica each real index counts the event it selects."""
    await _reset(dut)
    real = list(_real_indices(dut))
    for position, idx in enumerate(real):
        await write(dut, "event", idx, position % 9 + 1)
    for code in sorted({position % 9 + 1 for position in range(len(real))}):
        await wait_clocks(dut, 3, events=1 << code)
        await wait_clocks(dut, 1)
    _, width = _generics(dut)
    mask = (1 << min(width, WIDE)) - 1
    for idx in real:
        # every counter saw three pulses of its own code and no others
        check_equal(await read(dut, "lo", idx), 3 & mask, idx)


@cocotb.test()
async def test_a_counter_ignores_the_other_events(dut):
    """Verifica a counter ignores the other events."""
    await _reset(dut)
    real = list(_real_indices(dut))
    if not real:
        return
    await write(dut, "event", real[0], 4)
    await wait_clocks(dut, 5, events=TABLE_MASK & ~(1 << 4))
    check_equal(await read(dut, "lo", real[0]), 0)
    await wait_clocks(dut, 5, events=1 << 4)
    _, width = _generics(dut)
    check_equal(
        await read(dut, "lo", real[0]), 5 & ((1 << min(width, WIDE)) - 1)
    )


@cocotb.test()
async def test_codes_outside_the_table_and_code_zero_count_nothing(dut):
    """Verifica codes outside the table and code zero count nothing."""
    await _reset(dut)
    real = list(_real_indices(dut))
    for code in (0, 10, 11, 15):
        for idx in real[:PAIR]:
            await write(dut, "event", idx, code)
        await wait_clocks(dut, 4, events=0xFFFF)
        for idx in real[:PAIR]:
            check_equal(await read(dut, "lo", idx), 0, (code, idx))


@cocotb.test()
async def test_indices_without_a_counter_read_zero_and_ignore_writes(dut):
    """Verifica indices without a counter read zero, ignore writes."""
    await _reset(dut)
    real = set(_real_indices(dut))
    absent = [idx for idx in range(32) if idx not in real]
    for idx in absent:
        for kind in ("event", "lo", "hi"):
            await write(dut, kind, idx, 0xFFFFFFFF)
            check_equal(await read(dut, kind, idx), 0, (kind, idx))
    await write(dut, "inhibit", 0, 0xFFFFFFFF)
    expected = sum(1 << idx for idx in real)
    check_equal(await read(dut, "inhibit", 0), expected)
    for idx in real:
        check_true(await read(dut, "lo", idx) == 0, "writes elsewhere")


@cocotb.test()
async def test_inhibit_bit_stops_only_its_counter(dut):
    """Verifica inhibit bit stops only its counter."""
    await _reset(dut)
    real = list(_real_indices(dut))
    if len(real) < PAIR:
        return
    for idx in real[:PAIR]:
        await write(dut, "event", idx, 3)
    await write(dut, "inhibit", 0, 1 << real[0])
    await wait_clocks(dut, 4, events=1 << 3)
    _, width = _generics(dut)
    mask = (1 << min(width, WIDE)) - 1
    check_equal(await read(dut, "lo", real[0]), 0, "inhibited")
    check_equal(await read(dut, "lo", real[1]), 4 & mask, "free")
    await write(dut, "inhibit", 0, 0)
    await wait_clocks(dut, 2, events=1 << 3)
    check_equal(await read(dut, "lo", real[0]), 2 & mask, "released")


@cocotb.test()
async def test_an_explicit_write_beats_the_increment(dut):
    """Verifica an explicit write beats the increment."""
    await _reset(dut)
    real = list(_real_indices(dut))
    if not real:
        return
    idx = real[0]
    _, width = _generics(dut)
    mask = (1 << min(width, WIDE)) - 1
    await write(dut, "event", idx, 1)
    await cycle(dut, Access("lo", idx, 1, 0x15), events=1 << 1)
    check_equal(await read(dut, "lo", idx), 0x15 & mask)
    await wait_clocks(dut, 1, events=1 << 1)
    check_equal(await read(dut, "lo", idx), (0x16) & mask)


@cocotb.test()
async def test_the_high_half_advances_on_the_carry(dut):
    """Verifica the high half advances on the carry."""
    await _reset(dut)
    real = list(_real_indices(dut))
    if not real:
        return
    idx = real[-1]
    _, width = _generics(dut)
    lo_mask = (1 << min(width, WIDE)) - 1
    hi_mask = (1 << max(width - WIDE, 0)) - 1
    await write(dut, "event", idx, 2)
    await write(dut, "lo", idx, lo_mask - 1)
    await wait_clocks(dut, 3, events=1 << 2)
    # the carry lands one clock later, the read already shows it
    check_equal(await read(dut, "lo", idx), 1 & lo_mask)
    check_equal(await read(dut, "hi", idx), 1 & hi_mask)


@cocotb.test()
async def test_the_width_truncates_what_is_written(dut):
    """Verifica the width truncates what is written."""
    await _reset(dut)
    _, width = _generics(dut)
    for idx in _real_indices(dut):
        await write(dut, "lo", idx, 0xFFFFFFFF)
        await write(dut, "hi", idx, 0xFFFFFFFF)
        check_equal(
            await read(dut, "lo", idx), (1 << min(width, WIDE)) - 1, idx
        )
        check_equal(
            await read(dut, "hi", idx), (1 << max(width - WIDE, 0)) - 1, idx
        )


@cocotb.test()
async def test_the_event_selector_keeps_four_bits(dut):
    """Verifica the event selector keeps four bits."""
    await _reset(dut)
    for idx in _real_indices(dut):
        await write(dut, "event", idx, 0xFFFFFFF9)
        check_equal(await read(dut, "event", idx), 9, idx)


@cocotb.test()
async def test_random_traffic_matches_the_model(dut):
    """Verifica random traffic matches the model."""
    await _reset(dut)
    counters, width = _generics(dut)
    model = Model(counters, width)
    prng = Prng(counters * 1000 + width + 1)
    special = (0, 1, MASK32, MASK32 - 1, 0x7FFFFFFF)
    indices = list(range(32))
    for _ in range(4000):
        idx = prng.choice(indices)
        kind = prng.choice(("event", "lo", "hi", "inhibit", "lo", "hi"))
        we = int(prng.getrandbits(2) == 0)
        wdata = (
            prng.choice(special)
            if prng.getrandbits(1)
            else prng.getrandbits(32)
        )
        if kind == "event":
            wdata = prng.getrandbits(4) if prng.getrandbits(1) else wdata
        if kind == "inhibit":
            wdata &= prng.getrandbits(32) | prng.getrandbits(32)
        events = prng.getrandbits(16) & prng.getrandbits(16)
        access = Access(kind, idx, we, wdata)
        shown = await cycle(dut, access, events)
        check_equal(shown, model.read(kind, access.address()), (kind, idx))
        model.clock(events, access)
