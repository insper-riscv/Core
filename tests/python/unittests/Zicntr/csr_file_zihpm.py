"""csr_file with Zihpm (four event counters) and Zicntr: event selection, mirrors, mcountinhibit."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

RW, RS, RC = 0b001, 0b010, 0b011
MCYCLE, MINSTRET = 0xB00, 0xB02
MCOUNTINHIBIT = 0x320
MHPMEVENT = {n: 0x320 + n for n in (3, 4, 5, 6)}
MHPMCOUNTER = {n: 0xB00 + n for n in (3, 4, 5, 6)}
MHPMCOUNTERH = {n: 0xB80 + n for n in (3, 4, 5, 6)}
HPMCOUNTER = {n: 0xC00 + n for n in (3, 4, 5, 6)}
HPMCOUNTERH = {n: 0xC80 + n for n in (3, 4, 5, 6)}


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_commit.value = 0
    dut.i_addr.value = MCYCLE
    dut.i_op.value = RS
    dut.i_wdata.value = 0
    dut.i_src_zero.value = 1
    dut.i_trap_take.value = 0
    dut.i_mret_take.value = 0
    dut.i_retire.value = 0
    dut.i_events.value = 0
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def access(dut, addr, op, wdata=0, src_zero=None, commit=1):
    """One CSR instruction: returns (old value, illegal) seen before the write lands."""
    dut.i_addr.value = addr
    dut.i_op.value = op
    dut.i_wdata.value = wdata
    dut.i_src_zero.value = int(wdata == 0) if src_zero is None else src_zero
    dut.i_commit.value = commit
    await Timer(1, unit="ns")
    seen = int(dut.o_rdata.value), int(dut.o_illegal.value)
    await RisingEdge(dut.i_clk)
    dut.i_commit.value = 0
    await Timer(1, unit="ns")
    return seen


async def read(dut, addr):
    return (await access(dut, addr, RS, 0))[0]


async def write(dut, addr, value):
    return await access(dut, addr, RW, value, src_zero=0)


async def pulses(dut, code, count):
    """Raise the event of `code` for `count` consecutive clocks."""
    dut.i_events.value = 1 << code
    for _ in range(count):
        await RisingEdge(dut.i_clk)
    dut.i_events.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_a_counter_counts_only_its_event(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[3], 3)
    await write(dut, MHPMEVENT[4], 8)
    await pulses(dut, 3, 5)
    await pulses(dut, 8, 2)
    await pulses(dut, 1, 7)
    assert await read(dut, MHPMCOUNTER[3]) == 5
    assert await read(dut, MHPMCOUNTER[4]) == 2


@cocotb.test()
async def test_code_zero_and_codes_outside_the_table_count_nothing(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[3], 0)
    await write(dut, MHPMEVENT[4], 12)
    dut.i_events.value = 0x1FE                   # every event of the table at once, none of the codes past it
    for _ in range(6):
        await RisingEdge(dut.i_clk)
    dut.i_events.value = 0
    await Timer(1, unit="ns")
    assert await read(dut, MHPMCOUNTER[3]) == 0
    assert await read(dut, MHPMCOUNTER[4]) == 0


@cocotb.test()
async def test_the_event_selector_keeps_four_bits(dut):
    await _reset(dut)
    assert await read(dut, MHPMEVENT[5]) == 0
    await write(dut, MHPMEVENT[5], 0xFFFFFFF5)
    assert await read(dut, MHPMEVENT[5]) == 5


@cocotb.test()
async def test_the_mirrors_follow_and_are_read_only(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[6], 1)
    await pulses(dut, 1, 4)
    assert await read(dut, HPMCOUNTER[6]) == await read(dut, MHPMCOUNTER[6]) == 4
    assert await read(dut, HPMCOUNTERH[6]) == await read(dut, MHPMCOUNTERH[6]) == 0
    for addr in (HPMCOUNTER[6], HPMCOUNTERH[6]):
        assert (await access(dut, addr, RW, 0x1234, src_zero=0))[1] == 1, hex(addr)
        assert (await access(dut, addr, RS, 0))[1] == 0, "a read-only access does not trap"


@cocotb.test()
async def test_the_counter_is_writable_and_carries_into_the_high_half(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[3], 2)
    await write(dut, MHPMCOUNTER[3], 0xFFFFFFFE)
    await pulses(dut, 2, 3)
    await pulses(dut, 0, 1)                      # a clock without the event, for the carry to land
    assert await read(dut, MHPMCOUNTER[3]) == 1
    assert await read(dut, MHPMCOUNTERH[3]) == 1
    await write(dut, MHPMCOUNTERH[3], 0xAB)
    assert await read(dut, MHPMCOUNTERH[3]) == 0xAB


@cocotb.test()
async def test_addresses_past_the_implemented_counters_are_illegal(dut):
    await _reset(dut)
    for addr in (0xB07, 0xB87, 0xC07, 0xC87, 0x327, 0x3A0, 0xB1F, 0xC1F):
        assert (await access(dut, addr, RS, 0))[1] == 1, hex(addr)


@cocotb.test()
async def test_mcountinhibit_stops_one_counter_and_only_that_one(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[3], 3)
    await write(dut, MHPMEVENT[4], 3)
    await write(dut, MCOUNTINHIBIT, 1 << 3)
    await pulses(dut, 3, 6)
    assert await read(dut, MHPMCOUNTER[3]) == 0, "inhibited"
    assert await read(dut, MHPMCOUNTER[4]) == 6, "not inhibited"
    await write(dut, MCOUNTINHIBIT, 0)
    await pulses(dut, 3, 2)
    assert await read(dut, MHPMCOUNTER[3]) == 2, "counts again once the bit clears"
    assert await read(dut, MHPMCOUNTER[4]) == 8


@cocotb.test()
async def test_mcountinhibit_stops_mcycle_and_minstret(dut):
    await _reset(dut)
    await write(dut, MCOUNTINHIBIT, (1 << 0) | (1 << 2))
    first = await read(dut, MCYCLE)
    for _ in range(8):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    assert await read(dut, MCYCLE) == first, "mcycle holds while inhibited"
    dut.i_retire.value = 1
    for _ in range(4):
        await RisingEdge(dut.i_clk)
    dut.i_retire.value = 0
    await Timer(1, unit="ns")
    assert await read(dut, MINSTRET) == 0, "minstret holds while inhibited"
    await write(dut, MCOUNTINHIBIT, 0)
    for _ in range(5):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    assert await read(dut, MCYCLE) > first, "mcycle counts again"


@cocotb.test()
async def test_mcountinhibit_reserved_bits_read_zero_and_the_counter_stays_writable(dut):
    await _reset(dut)
    await write(dut, MCOUNTINHIBIT, 0xFFFFFFFF)
    # bit 1 (time) and the bits past the four counters are reserved
    assert await read(dut, MCOUNTINHIBIT) == 0b1111101
    await write(dut, MHPMCOUNTER[3], 0x55)
    assert await read(dut, MHPMCOUNTER[3]) == 0x55, "an inhibited counter accepts a write"


@cocotb.test()
async def test_a_trap_does_not_change_the_counters(dut):
    await _reset(dut)
    await write(dut, MHPMEVENT[3], 3)
    await pulses(dut, 3, 3)
    dut.i_trap_take.value = 1
    dut.i_trap_cause.value = 4
    await RisingEdge(dut.i_clk)
    dut.i_trap_take.value = 0
    await Timer(1, unit="ns")
    assert await read(dut, MHPMCOUNTER[3]) == 3
