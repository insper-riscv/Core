"""Testes do modulo.

csr_file with Zicntr: the counters mcycle, minstret and time and their
read-only mirrors.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal, check_true

LOW_BYTE_LIMIT = 0x100

RW, RS, RC = 0b001, 0b010, 0b011
MCYCLE, MINSTRET, MCYCLEH, MINSTRETH = 0xB00, 0xB02, 0xB80, 0xB82
CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH = (
    0xC00,
    0xC01,
    0xC02,
    0xC80,
    0xC81,
    0xC82,
)


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
    dut.i_rst.value = 1
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


def _drive(dut, addr, op, wdata, src_zero):
    """Present one CSR instruction on the inputs."""
    dut.i_addr.value = addr
    dut.i_op.value = op
    dut.i_wdata.value = wdata
    dut.i_src_zero.value = int(wdata == 0) if src_zero is None else src_zero


async def _step(dut, commit, retire=0):
    """Clock the presented instruction and return (old value, illegal).

    The pair is what the core shows before the write lands.
    """
    dut.i_commit.value = commit
    dut.i_retire.value = retire
    await Timer(1, unit="ns")
    seen = int(dut.o_rdata.value), int(dut.o_illegal.value)
    await RisingEdge(dut.i_clk)
    dut.i_commit.value = 0
    dut.i_retire.value = 0
    await Timer(1, unit="ns")
    return seen


async def access(dut, addr, op, wdata=0, src_zero=None):
    """Run one CSR instruction, as committed."""
    _drive(dut, addr, op, wdata, src_zero)
    return await _step(dut, 1)


async def read(dut, addr, retire=0):
    """Executa read."""
    _drive(dut, addr, RS, 0, None)
    return (await _step(dut, 1, retire))[0]


async def idle(dut, cycles, retire=0):
    """Executa idle."""
    dut.i_commit.value = 0
    dut.i_retire.value = retire
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
    dut.i_retire.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_mcycle_counts_every_clock_cycle(dut):
    """Verifica mcycle counts every clock cycle."""
    await _reset(dut)
    first = await read(dut, MCYCLE)
    await idle(dut, 9)
    second = await read(dut, MCYCLE)
    check_equal(
        second - first,
        10,
        "one per clock cycle, the read instruction included",
    )


@cocotb.test()
async def test_cycle_mirrors_mcycle_and_the_halves_agree(dut):
    """Verifica cycle mirrors mcycle and the halves agree."""
    await _reset(dut)
    await idle(dut, 5)
    check_true(await read(dut, CYCLEH) == await read(dut, MCYCLEH) == 0)
    machine = await read(dut, MCYCLE)
    mirror = await read(dut, CYCLE)
    check_equal(mirror - machine, 1, "the mirror read one cycle later")


@cocotb.test()
async def test_minstret_counts_only_retire_pulses(dut):
    """Verifica minstret counts only retire pulses."""
    await _reset(dut)
    check_equal(await read(dut, MINSTRET), 0)
    await idle(dut, 7)
    check_equal(
        await read(dut, MINSTRET),
        0,
        "cycles without a retirement do not count",
    )
    await idle(dut, 5, retire=1)
    check_equal(await read(dut, MINSTRET), 5)
    check_equal(await read(dut, INSTRET), 5)
    check_true(await read(dut, INSTRETH) == await read(dut, MINSTRETH) == 0)


@cocotb.test()
async def test_time_advances_one_per_tick(dut):
    """Verifica time advances one per tick."""
    await _reset(dut)
    period = int(dut.tick_cycles.value)
    first = await read(dut, TIME)
    await idle(dut, period * 6 - 1)
    second = await read(dut, TIME)
    check_equal(second - first, 6)


@cocotb.test()
async def test_mcycle_and_minstret_are_writable_and_keep_counting(dut):
    """Verifica mcycle and minstret are writable and keep counting."""
    await _reset(dut)
    await access(dut, MCYCLE, RW, 0x1000)
    check_equal(
        await read(dut, MCYCLE),
        0x1000,
        "the write wins over the increment of its own cycle",
    )
    check_equal(await read(dut, MCYCLE), 0x1001, "then the counter goes on")
    await access(dut, MINSTRET, RW, 0x77)
    check_equal(await read(dut, MINSTRET), 0x77)


@cocotb.test()
async def test_writing_the_halves_sets_the_64_bit_value(dut):
    """Verifica writing the halves sets the 64 bit value."""
    await _reset(dut)
    await access(dut, MCYCLEH, RW, 0x5)
    await access(dut, MCYCLE, RW, 0xFFFFFFF0)
    await idle(dut, 40)
    low = await read(dut, MCYCLE)
    high = await read(dut, MCYCLEH)
    check_equal(high, 6, "the low half wrapped and carried into the high half")
    check_true(low < LOW_BYTE_LIMIT)


@cocotb.test()
async def test_the_mirrors_and_time_are_read_only(dut):
    """Verifica the mirrors and time are read only."""
    await _reset(dut)
    for addr in (CYCLE, TIME, INSTRET, CYCLEH, TIMEH, INSTRETH):
        check_equal((await access(dut, addr, RS, 0))[1], 0, f"{addr:#x} reads")
        check_equal(
            (await access(dut, addr, RW, 5))[1],
            1,
            f"{addr:#x} write is illegal",
        )
        check_equal(
            (await access(dut, addr, RS, 0, src_zero=1))[1],
            0,
            f"{addr:#x} csrrs x0 does not write",
        )


@cocotb.test()
async def test_a_trap_does_not_change_the_counters(dut):
    """Verifica a trap does not change the counters."""
    await _reset(dut)
    await access(dut, MINSTRET, RW, 3)
    dut.i_trap_take.value = 1
    await idle(dut, 1)
    dut.i_trap_take.value = 0
    check_equal(await read(dut, MINSTRET), 3, "no retire pulse, no increment")
